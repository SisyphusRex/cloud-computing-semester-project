import pytest

from search.query import format_timestamp, youtube_url


def test_youtube_url_uses_whole_seconds():
    assert (
        youtube_url("abcdefghijk", 202_999) == "https://www.youtube.com/watch?v=abcdefghijk&t=202s"
    )


@pytest.mark.parametrize(
    ("ms", "expected"),
    [(0, "00:00"), (202_000, "03:22"), (3_599_000, "59:59"), (3_723_000, "1:02:03")],
)
def test_format_timestamp(ms, expected):
    assert format_timestamp(ms) == expected
