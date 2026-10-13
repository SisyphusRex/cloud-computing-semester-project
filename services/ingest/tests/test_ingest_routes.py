from pathlib import Path

import pytest

import ingest
from ingest import youtube

pytestmark = pytest.mark.db

PROF = "prof@example.edu"
VTT = (Path(__file__).parent / "fixtures" / "lecture4.vtt").read_text()
VIDEO_ID = "abcdefghijk"


class FakeYouTube:
    """Stands in for YouTubeClient; the real verify_owner logic still runs."""

    channel = "UC_mine"
    captions = VTT

    def __init__(self, token):
        assert token == "yt-token"

    def get_video(self, video_id):
        return youtube.Video(video_id, "Fall Lecture 4", "UC_mine")

    def my_channel_ids(self):
        return {self.channel}

    def pick_caption_track(self, video_id):
        return {"id": "cap1", "snippet": {"language": "en"}}

    def download_captions(self, caption_id):
        return self.captions


@pytest.fixture
def client(make_client, db_settings, monkeypatch):
    monkeypatch.setattr(youtube, "YouTubeClient", FakeYouTube)
    return make_client(ingest.create_app, db_settings)


@pytest.fixture
def course_id(client, auth):
    resp = client.post(
        "/ingest/courses", json={"code": "CS6030", "title": "Cloud"}, headers=auth(PROF)
    )
    assert resp.status_code == 201, resp.json
    return resp.json["id"]


def register(client, auth, course_id, email=PROF, token="yt-token"):
    headers = {**auth(email), "X-YouTube-Token": token}
    return client.post(
        f"/ingest/courses/{course_id}/lectures",
        json={"video": f"https://youtu.be/{VIDEO_ID}"},
        headers=headers,
    )


def test_student_cannot_create_course(client, auth):
    resp = client.post(
        "/ingest/courses", json={"code": "X", "title": "Y"}, headers=auth("student@example.edu")
    )
    assert resp.status_code == 403


def test_duplicate_course_code_conflicts(client, auth, course_id):
    resp = client.post(
        "/ingest/courses", json={"code": "CS6030", "title": "Again"}, headers=auth(PROF)
    )
    assert resp.status_code == 409


def test_register_lecture_indexes_segments(client, auth, course_id):
    resp = register(client, auth, course_id)
    assert resp.status_code == 201, resp.json
    assert resp.json["status"] == "indexed"
    assert resp.json["title"] == "Fall Lecture 4"
    assert resp.json["youtube_video_id"] == VIDEO_ID
    assert resp.json["segment_count"] == 2

    courses = client.get("/ingest/courses", headers=auth(PROF)).json["courses"]
    assert courses[0]["lecture_count"] == 1


def test_reregistering_replaces_segments(client, auth, course_id):
    register(client, auth, course_id)
    resp = register(client, auth, course_id)
    assert resp.status_code == 201
    assert resp.json["segment_count"] == 2


def test_validation_and_missing_youtube_token(client, auth, course_id):
    bad = client.post(
        f"/ingest/courses/{course_id}/lectures",
        json={"video": "nope"},
        headers={**auth(PROF), "X-YouTube-Token": "yt-token"},
    )
    assert bad.status_code == 400
    assert bad.json["details"][0]["field"] == "video"
    assert register(client, auth, course_id, token="").status_code == 400


def test_other_professors_course_is_404(client, auth, db_settings, course_id):
    import dataclasses

    db_settings = dataclasses.replace(
        db_settings, professor_emails=db_settings.professor_emails | {"other@example.edu"}
    )
    client.application.config["LI_SETTINGS"] = db_settings
    assert register(client, auth, course_id, email="other@example.edu").status_code == 404


def test_not_owner_is_rejected_without_a_lecture_row(client, auth, course_id, monkeypatch):
    monkeypatch.setattr(FakeYouTube, "channel", "UC_someone_else")
    resp = register(client, auth, course_id)
    assert resp.status_code == 403
    assert resp.json["error"] == "not_video_owner"
    assert (
        client.get("/ingest/courses", headers=auth(PROF)).json["courses"][0]["lecture_count"] == 0
    )


def test_empty_captions_mark_lecture_failed(client, auth, course_id, monkeypatch):
    monkeypatch.setattr(FakeYouTube, "captions", "WEBVTT\n\n")
    resp = register(client, auth, course_id)
    assert resp.status_code == 422
    lecture = client.get(f"/ingest/lectures/{resp.json['lecture_id']}", headers=auth(PROF))
    assert lecture.json["status"] == "failed"
    assert lecture.json["error"] == "The caption track is empty"


def test_delete_lecture(client, auth, course_id):
    lecture_id = register(client, auth, course_id).json["id"]
    assert client.delete(f"/ingest/lectures/{lecture_id}", headers=auth(PROF)).status_code == 204
    assert client.get(f"/ingest/lectures/{lecture_id}", headers=auth(PROF)).status_code == 404
