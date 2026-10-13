import logging

from flask import Blueprint, abort, g, request

from ingest import youtube
from ingest.captions import parse_segments
from li_common import db
from li_common.auth import require_user
from li_common.errors import error_response
from li_common.logging import log_event
from li_common.schemas import CourseCreate, LectureCreate

logger = logging.getLogger(__name__)

bp = Blueprint("ingest", __name__, url_prefix="/ingest")

_LECTURE_COLUMNS = """
    l.id, l.course_id, l.youtube_video_id, l.title, l.caption_language, l.status,
    l.error, l.indexed_at, l.created_at,
    (SELECT count(*) FROM segments s WHERE s.lecture_id = l.id) AS segment_count
"""


@bp.post("/courses")
@require_user("professor")
def create_course():
    body = CourseCreate.model_validate(request.get_json(silent=True) or {})
    with db.connection() as conn:
        row = conn.execute(
            """
            INSERT INTO courses (owner_id, code, title) VALUES (%s, %s, %s)
            ON CONFLICT (owner_id, code) DO NOTHING
            RETURNING id, code, title, created_at
            """,
            (g.user.id, body.code, body.title),
        ).fetchone()
    if row is None:
        abort(409, f"You already have a course with code {body.code}")
    return row, 201


@bp.get("/courses")
@require_user("professor")
def list_my_courses():
    with db.connection() as conn:
        rows = conn.execute(
            """
            SELECT c.id, c.code, c.title, c.created_at, count(l.id) AS lecture_count
            FROM courses c LEFT JOIN lectures l ON l.course_id = c.id
            WHERE c.owner_id = %s
            GROUP BY c.id ORDER BY c.code
            """,
            (g.user.id,),
        ).fetchall()
    return {"courses": rows}


@bp.post("/courses/<int:course_id>/lectures")
@require_user("professor")
def register_lecture(course_id: int):
    body = LectureCreate.model_validate(request.get_json(silent=True) or {})
    token = request.headers.get("X-YouTube-Token", "")
    if not token:
        abort(400, "X-YouTube-Token header with the professor's YouTube access token is required")
    _owned_course_or_404(course_id)

    client = youtube.YouTubeClient(token)
    try:
        video = youtube.verify_owner(client, body.video)
    except youtube.YouTubeError as exc:
        return _ingest_failed(None, body.video, exc)

    # Record the lecture before the expensive caption download so a failure is
    # visible to the professor with its reason.
    with db.connection() as conn:
        lecture_id = conn.execute(
            """
            INSERT INTO lectures (course_id, youtube_video_id, title)
            VALUES (%s, %s, %s)
            ON CONFLICT (course_id, youtube_video_id)
                DO UPDATE SET title = EXCLUDED.title, status = 'pending', error = NULL
            RETURNING id
            """,
            (course_id, video.id, video.title),
        ).fetchone()["id"]

    try:
        track = client.pick_caption_track(video.id)
        segments = parse_segments(client.download_captions(track["id"]))
        if not segments:
            raise youtube.NoCaptions("The caption track is empty")
    except youtube.YouTubeError as exc:
        return _ingest_failed(lecture_id, video.id, exc)

    with db.connection() as conn:
        conn.execute("DELETE FROM segments WHERE lecture_id = %s", (lecture_id,))
        with conn.cursor().copy(
            "COPY segments (lecture_id, start_ms, end_ms, text) FROM STDIN"
        ) as copy:
            for s in segments:
                copy.write_row((lecture_id, s.start_ms, s.end_ms, s.text))
        conn.execute(
            """
            UPDATE lectures SET status = 'indexed', error = NULL, indexed_at = now(),
                                caption_language = %s
            WHERE id = %s
            """,
            (track["snippet"].get("language"), lecture_id),
        )
        lecture = _fetch_lecture(conn, lecture_id)
    log_event(
        logger,
        "ingest_succeeded",
        video_id=video.id,
        lecture_id=lecture_id,
        segments=len(segments),
    )
    return lecture, 201


@bp.get("/lectures/<int:lecture_id>")
@require_user("professor")
def get_lecture(lecture_id: int):
    with db.connection() as conn:
        lecture = _fetch_lecture(conn, lecture_id, owner_id=g.user.id)
    if lecture is None:
        abort(404, "Lecture not found")
    return lecture


@bp.delete("/lectures/<int:lecture_id>")
@require_user("professor")
def delete_lecture(lecture_id: int):
    with db.connection() as conn:
        deleted = conn.execute(
            """
            DELETE FROM lectures l USING courses c
            WHERE l.id = %s AND l.course_id = c.id AND c.owner_id = %s
            """,
            (lecture_id, g.user.id),
        ).rowcount
    if not deleted:
        abort(404, "Lecture not found")
    return "", 204


def _owned_course_or_404(course_id: int) -> None:
    # Someone else's course is reported as missing rather than forbidden.
    with db.connection() as conn:
        found = conn.execute(
            "SELECT 1 FROM courses WHERE id = %s AND owner_id = %s", (course_id, g.user.id)
        ).fetchone()
    if not found:
        abort(404, "Course not found")


def _fetch_lecture(conn, lecture_id: int, owner_id: int | None = None) -> dict | None:
    sql = f"SELECT {_LECTURE_COLUMNS} FROM lectures l JOIN courses c ON c.id = l.course_id "
    sql += "WHERE l.id = %s" + (" AND c.owner_id = %s" if owner_id is not None else "")
    params = (lecture_id, owner_id) if owner_id is not None else (lecture_id,)
    return conn.execute(sql, params).fetchone()


def _ingest_failed(lecture_id: int | None, video_id: str, exc: youtube.YouTubeError):
    if lecture_id is not None:
        with db.connection() as conn:
            conn.execute(
                "UPDATE lectures SET status = 'failed', error = %s WHERE id = %s",
                (str(exc), lecture_id),
            )
    log_event(
        logger,
        "ingest_failed",
        logging.WARNING,
        video_id=video_id,
        lecture_id=lecture_id,
        reason=exc.code,
    )
    return error_response(exc.status, exc.code, str(exc), lecture_id=lecture_id)
