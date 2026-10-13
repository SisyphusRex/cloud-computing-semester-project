from flask import Blueprint, abort, request

from li_common import db
from li_common.auth import require_user
from li_common.schemas import SearchParams
from search.query import search_segments

bp = Blueprint("search", __name__, url_prefix="/search")


@bp.get("/courses")
@require_user()
def list_courses():
    with db.connection() as conn:
        rows = conn.execute(
            """
            SELECT c.id, c.code, c.title, u.name AS professor,
                   count(l.id) FILTER (WHERE l.status = 'indexed') AS lecture_count
            FROM courses c
            JOIN users u ON u.id = c.owner_id
            LEFT JOIN lectures l ON l.course_id = c.id
            GROUP BY c.id, u.name
            ORDER BY c.code
            """
        ).fetchall()
    return {"courses": rows}


@bp.get("/courses/<int:course_id>/lectures")
@require_user()
def list_lectures(course_id: int):
    with db.connection() as conn:
        _course_or_404(conn, course_id)
        rows = conn.execute(
            """
            SELECT id, youtube_video_id AS video_id, title, indexed_at
            FROM lectures
            WHERE course_id = %s AND status = 'indexed'
            ORDER BY created_at
            """,
            (course_id,),
        ).fetchall()
    return {"lectures": rows}


@bp.get("/courses/<int:course_id>/segments")
@require_user()
def search(course_id: int):
    params = SearchParams.model_validate(request.args.to_dict())
    with db.connection() as conn:
        _course_or_404(conn, course_id)
        hits = search_segments(conn, course_id, params.q, params.limit)
    return {"query": params.q, "hits": hits}


def _course_or_404(conn, course_id: int) -> None:
    if not conn.execute("SELECT 1 FROM courses WHERE id = %s", (course_id,)).fetchone():
        abort(404, "Course not found")
