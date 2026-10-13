"""Request validation models. Flask has no built-in validation, so views call
`Model.model_validate(...)` and the error handler turns failures into 400s."""

import re
from typing import Annotated
from urllib.parse import parse_qs, urlparse

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_PATH_PREFIXES = ("/embed/", "/live/", "/shorts/", "/v/")

Text = Annotated[str, StringConstraints(strip_whitespace=True)]


def parse_video_id(value: str) -> str:
    """Accept a bare YouTube video ID or any common YouTube URL form."""
    value = value.strip()
    if _VIDEO_ID.match(value):
        return value
    url = urlparse(value if "://" in value else f"https://{value}")
    host = (url.hostname or "").removeprefix("www.").removeprefix("m.")
    candidate = None
    if host == "youtu.be":
        candidate = url.path.lstrip("/").split("/")[0]
    elif host in ("youtube.com", "music.youtube.com"):
        if url.path == "/watch":
            candidate = parse_qs(url.query).get("v", [None])[0]
        else:
            for prefix in _PATH_PREFIXES:
                if url.path.startswith(prefix):
                    candidate = url.path.removeprefix(prefix).split("/")[0]
    if candidate and _VIDEO_ID.match(candidate):
        return candidate
    raise ValueError("not a YouTube video ID or URL")


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CourseCreate(_Strict):
    code: Annotated[Text, Field(min_length=1, max_length=32)]
    title: Annotated[Text, Field(min_length=1, max_length=200)]


class LectureCreate(_Strict):
    video: Annotated[str, Field(description="YouTube video ID or URL")]

    @field_validator("video")
    @classmethod
    def _video_id(cls, value: str) -> str:
        return parse_video_id(value)


class SearchParams(_Strict):
    q: Annotated[Text, Field(min_length=1, max_length=200)]
    limit: Annotated[int, Field(ge=1, le=50)] = 20
