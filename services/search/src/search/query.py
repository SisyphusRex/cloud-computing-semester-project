"""Postgres full-text search over caption segments."""

# The segment text is HTML-escaped before ts_headline adds <mark> tags, so
# `excerpt_html` is safe to render as HTML: the only tags in it are ours.
_SEARCH_SQL = """
SELECT l.id AS lecture_id,
       l.title AS lecture_title,
       l.youtube_video_id AS video_id,
       s.start_ms,
       ts_headline(
           'english',
           replace(replace(replace(s.text, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'),
           q,
           'StartSel=<mark>, StopSel=</mark>, MinWords=8, MaxWords=30, MaxFragments=2'
       ) AS excerpt_html,
       ts_rank_cd(s.tsv, q) AS rank
FROM segments s
JOIN lectures l ON l.id = s.lecture_id,
     websearch_to_tsquery('english', %(q)s) AS q
WHERE l.course_id = %(course_id)s
  AND l.status = 'indexed'
  AND s.tsv @@ q
ORDER BY rank DESC, l.id, s.start_ms
LIMIT %(limit)s
"""


def youtube_url(video_id: str, start_ms: int) -> str:
    return f"https://www.youtube.com/watch?v={video_id}&t={start_ms // 1000}s"


def format_timestamp(start_ms: int) -> str:
    minutes, seconds = divmod(start_ms // 1000, 60)
    hours, minutes = divmod(minutes, 60)
    return f"{hours}:{minutes:02d}:{seconds:02d}" if hours else f"{minutes:02d}:{seconds:02d}"


def search_segments(conn, course_id: int, q: str, limit: int) -> list[dict]:
    rows = conn.execute(_SEARCH_SQL, {"course_id": course_id, "q": q, "limit": limit}).fetchall()
    return [
        {
            "lecture_id": r["lecture_id"],
            "lecture_title": r["lecture_title"],
            "video_id": r["video_id"],
            "start_seconds": r["start_ms"] // 1000,
            "timestamp": format_timestamp(r["start_ms"]),
            "excerpt_html": r["excerpt_html"],
            "url": youtube_url(r["video_id"], r["start_ms"]),
        }
        for r in rows
    ]
