"""Turn WebVTT from YouTube's captions.download into timestamped search segments.

Caption cues are a few seconds long, so a phrase often spans two cues. We merge
consecutive cues into windows of up to ~20 s; each window keeps the start time
of its first cue, which becomes the video deep link.
"""

import html
import re
from dataclasses import dataclass

# "00:01:02.345 --> 00:01:05.000"; hours are optional in VTT.
_TIMING = re.compile(
    r"(?:(\d+):)?(\d{1,2}):(\d{2})\.(\d{3})\s*-->\s*(?:(\d+):)?(\d{1,2}):(\d{2})\.(\d{3})"
)
_TAG = re.compile(r"<[^>]*>")
# Sound tags from YouTube ASR: [Music], [Applause], [Laughter], and [ __ ] for
# censored words. They aren't speech, so they shouldn't match searches.
_SOUND_TAG = re.compile(r"\[[^\]]*\]")
_SPACE = re.compile(r"\s+")


@dataclass(frozen=True)
class Cue:
    start_ms: int
    end_ms: int
    text: str


@dataclass(frozen=True)
class Segment:
    start_ms: int
    end_ms: int
    text: str


def _ms(hours: str | None, minutes: str, seconds: str, millis: str) -> int:
    return ((int(hours or 0) * 60 + int(minutes)) * 60 + int(seconds)) * 1000 + int(millis)


def _clean(line: str) -> str:
    text = _SOUND_TAG.sub(" ", html.unescape(_TAG.sub("", line)))
    return _SPACE.sub(" ", text).strip()


def parse_cues(raw: str) -> list[Cue]:
    raw = raw.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n")
    cues: list[Cue] = []
    previous_lines: set[str] = set()
    # Cues end at an empty line. Not a whitespace-only one: YouTube ASR cues often
    # start with a " " line between the timing and the text.
    for block in re.split(r"\n{2,}", raw):
        lines = block.strip().split("\n")
        timing_index = next((i for i, line in enumerate(lines) if _TIMING.search(line)), None)
        if timing_index is None:
            continue  # WEBVTT header, NOTE/STYLE block, or stray text
        g = _TIMING.search(lines[timing_index]).groups()
        text_lines = [c for c in (_clean(line) for line in lines[timing_index + 1 :]) if c]
        # Auto-generated tracks "roll": each cue repeats the previous cue's line
        # before adding a new one. Drop lines we just saw.
        new_lines = [line for line in text_lines if line not in previous_lines]
        previous_lines = set(text_lines)
        if new_lines:
            cues.append(Cue(_ms(*g[:4]), _ms(*g[4:]), " ".join(new_lines)))
    return cues


def merge_segments(cues: list[Cue], max_ms: int = 20_000, max_chars: int = 400) -> list[Segment]:
    segments: list[Segment] = []
    start = end = 0
    parts: list[str] = []
    length = 0
    for cue in cues:
        if parts and (cue.end_ms - start > max_ms or length + len(cue.text) > max_chars):
            segments.append(Segment(start, end, " ".join(parts)))
            parts, length = [], 0
        if not parts:
            start = cue.start_ms
        parts.append(cue.text)
        length += len(cue.text) + 1
        end = max(end, cue.end_ms)
    if parts:
        segments.append(Segment(start, end, " ".join(parts)))
    return segments


def parse_segments(raw: str) -> list[Segment]:
    return merge_segments(parse_cues(raw))
