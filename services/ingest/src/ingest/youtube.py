"""Minimal YouTube Data API v3 client for caption ingestion.

Calls are made with the professor's OAuth access token, which is used for this
request only and never stored or logged. captions.list and captions.download
require the youtube.force-ssl scope and only work for the video's owner.
Only YouTube's auto-generated (ASR) caption tracks are indexed; tracks uploaded
by the creator are ignored.
"""

import logging
from dataclasses import dataclass

import requests

from li_common.logs import log_event

logger = logging.getLogger(__name__)

API = "https://www.googleapis.com/youtube/v3"

# Quota units per call, from the API reference; logged for the quota dashboard.
_QUOTA_COST = {"channels.list": 1, "videos.list": 1, "captions.list": 50, "captions.download": 200}


class YouTubeError(Exception):
    """A YouTube failure, with the HTTP status our API should answer with."""

    status = 502
    code = "youtube_error"

    def __init__(self, message: str, status: int | None = None, code: str | None = None):
        super().__init__(message)
        self.status = status or self.status
        self.code = code or self.code


class VideoNotFound(YouTubeError):
    status, code = 404, "video_not_found"


class NotVideoOwner(YouTubeError):
    status, code = 403, "not_video_owner"


class NoCaptions(YouTubeError):
    status, code = 422, "no_captions"


@dataclass(frozen=True)
class Video:
    id: str
    title: str
    channel_id: str


class YouTubeClient:
    def __init__(self, access_token: str, session: requests.Session | None = None):
        self._session = session or requests.Session()
        self._headers = {"Authorization": f"Bearer {access_token}"}

    def _get(self, method: str, path: str, params: dict) -> requests.Response:
        resp = self._session.get(f"{API}{path}", params=params, headers=self._headers, timeout=15)
        log_event(
            logger,
            "youtube_api_call",
            method=method,
            status=resp.status_code,
            quota_units=_QUOTA_COST[method],
        )
        if resp.status_code == 401:
            raise YouTubeError("YouTube rejected the access token", 400, "youtube_token_invalid")
        if resp.status_code == 403:
            reasons = {e.get("reason") for e in _json(resp).get("error", {}).get("errors", [])}
            if reasons & {"quotaExceeded", "dailyLimitExceeded", "rateLimitExceeded"}:
                raise YouTubeError("YouTube API quota exhausted", 503, "youtube_quota")
            raise NotVideoOwner("This Google account cannot access the video's captions")
        if resp.status_code == 404:
            raise VideoNotFound("Video or caption track not found")
        if not resp.ok:
            raise YouTubeError(f"YouTube API returned {resp.status_code}")
        return resp

    def my_channel_ids(self) -> set[str]:
        data = self._get("channels.list", "/channels", {"part": "id", "mine": "true"}).json()
        return {item["id"] for item in data.get("items", [])}

    def get_video(self, video_id: str) -> Video:
        data = self._get("videos.list", "/videos", {"part": "snippet", "id": video_id}).json()
        items = data.get("items", [])
        if not items:
            raise VideoNotFound(f"Video {video_id} not found")
        snippet = items[0]["snippet"]
        return Video(video_id, snippet.get("title", ""), snippet["channelId"])

    def pick_caption_track(self, video_id: str, language: str = "en") -> dict:
        data = self._get(
            "captions.list", "/captions", {"part": "snippet", "videoId": video_id}
        ).json()
        tracks = [
            t
            for t in data.get("items", [])
            if t["snippet"].get("trackKind", "").lower() == "asr"
            and t["snippet"].get("status", "serving") == "serving"
        ]
        if not tracks:
            raise NoCaptions("The video has no auto-generated captions")

        def preference(track: dict) -> bool:
            # Wanted language first, otherwise any auto-generated track.
            return track["snippet"].get("language", "").split("-")[0] != language

        return min(tracks, key=preference)

    def download_captions(self, caption_id: str) -> str:
        resp = self._get("captions.download", f"/captions/{caption_id}", {"tfmt": "vtt"})
        resp.encoding = "utf-8"
        return resp.text


def verify_owner(client: YouTubeClient, video_id: str) -> Video:
    video = client.get_video(video_id)
    if video.channel_id not in client.my_channel_ids():
        raise NotVideoOwner("You can only register videos from your own YouTube channel")
    return video


def _json(resp: requests.Response) -> dict:
    try:
        return resp.json()
    except ValueError:
        return {}
