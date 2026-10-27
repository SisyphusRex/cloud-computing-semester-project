import pytest

from ingest import youtube


class FakeResponse:
    def __init__(self, status=200, json=None, text=""):
        self.status_code = status
        self._json = json or {}
        self.text = text
        self.ok = status < 400
        self.encoding = None

    def json(self):
        return self._json


class FakeSession:
    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def get(self, url, params, headers, timeout):
        path = url.removeprefix(youtube.API)
        self.calls.append((path, params, headers))
        return self.routes[path]


def client(routes):
    return youtube.YouTubeClient("ya29.token", session=FakeSession(routes))


VIDEO = {"items": [{"snippet": {"title": "Fall Lecture 4", "channelId": "UC_mine"}}]}


def test_verify_owner_accepts_own_video():
    c = client(
        {
            "/videos": FakeResponse(json=VIDEO),
            "/channels": FakeResponse(json={"items": [{"id": "UC_mine"}]}),
        }
    )
    video = youtube.verify_owner(c, "abcdefghijk")
    assert video == youtube.Video("abcdefghijk", "Fall Lecture 4", "UC_mine")
    assert c._session.calls[0][2] == {"Authorization": "Bearer ya29.token"}


def test_verify_owner_rejects_other_channel():
    c = client(
        {
            "/videos": FakeResponse(json=VIDEO),
            "/channels": FakeResponse(json={"items": [{"id": "UC_someone_else"}]}),
        }
    )
    with pytest.raises(youtube.NotVideoOwner):
        youtube.verify_owner(c, "abcdefghijk")


def test_get_video_reads_embeddable():
    listing = {"items": [{**VIDEO["items"][0], "status": {"embeddable": False}}]}
    c = client({"/videos": FakeResponse(json=listing)})
    assert c.get_video("abcdefghijk").embeddable is False
    assert c._session.calls[0][1]["part"] == "snippet,status"


def test_missing_video():
    c = client({"/videos": FakeResponse(json={"items": []})})
    with pytest.raises(youtube.VideoNotFound):
        c.get_video("abcdefghijk")


def tracks(*items):
    return {"items": [{"id": i, "snippet": snippet} for i, snippet in items]}


def test_pick_caption_track_prefers_english_asr():
    listing = tracks(
        ("asr-es", {"language": "es", "trackKind": "asr"}),
        ("std-en", {"language": "en", "trackKind": "standard"}),
        ("asr-en-US", {"language": "en-US", "trackKind": "ASR"}),
        ("broken", {"language": "en", "trackKind": "asr", "status": "failed"}),
    )
    c = client({"/captions": FakeResponse(json=listing)})
    assert c.pick_caption_track("abcdefghijk")["id"] == "asr-en-US"


def test_non_english_asr_used_when_no_english():
    listing = tracks(
        ("std-en", {"language": "en", "trackKind": "standard"}),
        ("asr-de", {"language": "de", "trackKind": "asr"}),
    )
    c = client({"/captions": FakeResponse(json=listing)})
    assert c.pick_caption_track("abcdefghijk")["id"] == "asr-de"


def test_uploaded_tracks_are_ignored():
    listing = tracks(
        ("std-en", {"language": "en", "trackKind": "standard"}),
        ("forced-en", {"language": "en", "trackKind": "forced"}),
    )
    c = client({"/captions": FakeResponse(json=listing)})
    with pytest.raises(youtube.NoCaptions, match="auto-generated"):
        c.pick_caption_track("abcdefghijk")


def test_no_caption_tracks():
    c = client({"/captions": FakeResponse(json={"items": []})})
    with pytest.raises(youtube.NoCaptions):
        c.pick_caption_track("abcdefghijk")


@pytest.mark.parametrize(
    ("response", "status", "code"),
    [
        (FakeResponse(401), 400, "youtube_token_invalid"),
        (
            FakeResponse(403, json={"error": {"errors": [{"reason": "quotaExceeded"}]}}),
            503,
            "youtube_quota",
        ),
        (
            FakeResponse(403, json={"error": {"errors": [{"reason": "forbidden"}]}}),
            403,
            "not_video_owner",
        ),
        (FakeResponse(500), 502, "youtube_error"),
    ],
)
def test_error_mapping(response, status, code):
    c = client({"/captions/cap1": response})
    with pytest.raises(youtube.YouTubeError) as exc:
        c.download_captions("cap1")
    assert (exc.value.status, exc.value.code) == (status, code)


def test_download_requests_vtt():
    c = client({"/captions/cap1": FakeResponse(text="WEBVTT\n")})
    assert c.download_captions("cap1") == "WEBVTT\n"
    assert c._session.calls[0][1] == {"tfmt": "vtt"}
