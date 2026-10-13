import pytest
from pydantic import ValidationError

from li_common.schemas import CourseCreate, LectureCreate, SearchParams, parse_video_id

VIDEO = "dQw4w9WgXcQ"


@pytest.mark.parametrize(
    "value",
    [
        VIDEO,
        f"https://www.youtube.com/watch?v={VIDEO}",
        f"https://youtube.com/watch?feature=share&v={VIDEO}&t=42",
        f"https://m.youtube.com/watch?v={VIDEO}",
        f"https://youtu.be/{VIDEO}?si=abc",
        f"youtu.be/{VIDEO}",
        f"https://www.youtube.com/live/{VIDEO}",
        f"https://www.youtube.com/embed/{VIDEO}",
        f"https://www.youtube.com/shorts/{VIDEO}",
        f"  {VIDEO}  ",
    ],
)
def test_parse_video_id_accepts_common_forms(value):
    assert parse_video_id(value) == VIDEO


@pytest.mark.parametrize(
    "value",
    ["", "short", "https://example.com/watch?v=dQw4w9WgXcQ", "https://youtube.com/watch?v=bad"],
)
def test_parse_video_id_rejects_others(value):
    with pytest.raises(ValueError):
        parse_video_id(value)


def test_lecture_create_normalizes_url():
    assert LectureCreate(video=f"https://youtu.be/{VIDEO}").video == VIDEO


def test_course_create_strips_and_rejects_extra_fields():
    assert CourseCreate(code=" CS6030 ", title="Cloud").code == "CS6030"
    with pytest.raises(ValidationError):
        CourseCreate(code="CS6030", title="Cloud", owner_id=1)
    with pytest.raises(ValidationError):
        CourseCreate(code="   ", title="Cloud")


def test_search_params_bounds():
    assert SearchParams.model_validate({"q": "lambda", "limit": "5"}).limit == 5
    with pytest.raises(ValidationError):
        SearchParams.model_validate({"q": "lambda", "limit": "500"})
    with pytest.raises(ValidationError):
        SearchParams.model_validate({"q": ""})
