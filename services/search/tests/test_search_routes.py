import psycopg
import pytest

import search

pytestmark = pytest.mark.db

STUDENT = "student@example.edu"


@pytest.fixture
def seeded(database_url):
    """Two courses; lectures and segments inserted as the Ingest API would."""
    with psycopg.connect(database_url) as conn:
        owner = conn.execute(
            "INSERT INTO users (google_sub, email, name, role) "
            "VALUES ('p1', 'prof@example.edu', 'Prof', 'professor') RETURNING id"
        ).fetchone()[0]

        def course(code):
            return conn.execute(
                "INSERT INTO courses (owner_id, code, title) VALUES (%s, %s, %s) RETURNING id",
                (owner, code, code),
            ).fetchone()[0]

        def lecture(course_id, video, title, status="indexed"):
            return conn.execute(
                "INSERT INTO lectures (course_id, youtube_video_id, title, status) "
                "VALUES (%s, %s, %s, %s) RETURNING id",
                (course_id, video, title, status),
            ).fetchone()[0]

        def segment(lecture_id, start_ms, text):
            conn.execute(
                "INSERT INTO segments (lecture_id, start_ms, end_ms, text) VALUES (%s, %s, %s, %s)",
                (lecture_id, start_ms, start_ms + 10_000, text),
            )

        cloud, other = course("CS6030"), course("CS1110")
        l4 = lecture(cloud, "lecture4abc", "Fall Lecture 4")
        segment(l4, 1_000, "Welcome back. Today: Kubernetes autoscaling.")
        segment(l4, 202_000, "Lambda calculus is the basis of functional languages.")
        segment(l4, 300_000, "Careful: <script>alert(1)</script> lambda & friends")
        segment(lecture(cloud, "lecture5abc", "Fall Lecture 5", "failed"), 0, "lambda draft")
        segment(lecture(other, "otherxyzabc", "Intro"), 0, "lambda calculus elsewhere")
    return {"cloud": cloud, "other": other}


@pytest.fixture
def client(make_client, db_settings, seeded):
    return make_client(search.create_app, db_settings)


def test_phrase_search_returns_deep_link(client, auth, seeded):
    resp = client.get(
        f"/search/courses/{seeded['cloud']}/segments",
        query_string={"q": '"lambda calculus"'},
        headers=auth(STUDENT),
    )
    assert resp.status_code == 200
    hits = resp.json["hits"]
    assert len(hits) == 1  # other course and failed lecture are excluded
    hit = hits[0]
    assert hit["lecture_title"] == "Fall Lecture 4"
    assert hit["timestamp"] == "03:22"
    assert hit["url"] == "https://www.youtube.com/watch?v=lecture4abc&t=202s"
    assert "<mark>Lambda</mark>" in hit["excerpt_html"]


def test_stemming_matches_word_forms(client, auth, seeded):
    hits = client.get(
        f"/search/courses/{seeded['cloud']}/segments",
        query_string={"q": "language"},  # segment says "languages"
        headers=auth(STUDENT),
    ).json["hits"]
    assert [h["timestamp"] for h in hits] == ["03:22"]


def test_excerpt_is_html_escaped(client, auth, seeded):
    hits = client.get(
        f"/search/courses/{seeded['cloud']}/segments",
        query_string={"q": "friends"},
        headers=auth(STUDENT),
    ).json["hits"]
    excerpt = hits[0]["excerpt_html"]
    assert "<script>" not in excerpt
    assert "&lt;script&gt;" in excerpt
    assert "&amp;" in excerpt


def test_stopword_only_query_returns_no_hits(client, auth, seeded):
    resp = client.get(
        f"/search/courses/{seeded['cloud']}/segments",
        query_string={"q": "the"},
        headers=auth(STUDENT),
    )
    assert resp.status_code == 200
    assert resp.json["hits"] == []


def test_list_courses_and_lectures(client, auth, seeded):
    courses = client.get("/search/courses", headers=auth(STUDENT)).json["courses"]
    assert {c["code"]: c["lecture_count"] for c in courses} == {"CS1110": 1, "CS6030": 1}
    lectures = client.get(
        f"/search/courses/{seeded['cloud']}/lectures", headers=auth(STUDENT)
    ).json["lectures"]
    assert [lec["title"] for lec in lectures] == ["Fall Lecture 4"]


def test_unknown_course_and_bad_params(client, auth, seeded):
    headers = auth(STUDENT)
    assert client.get("/search/courses/999999/segments?q=x", headers=headers).status_code == 404
    bad = client.get(f"/search/courses/{seeded['cloud']}/segments?q=x&limit=0", headers=headers)
    assert bad.status_code == 400


def test_requires_sign_in(client, seeded):
    assert client.get("/search/courses").status_code == 401
