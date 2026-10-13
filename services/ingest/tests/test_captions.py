from pathlib import Path

from ingest.captions import Cue, merge_segments, parse_cues, parse_segments

FIXTURES = Path(__file__).parent / "fixtures"


def test_parse_vtt_times_tags_and_entities():
    cues = parse_cues((FIXTURES / "lecture4.vtt").read_text())
    assert cues[0] == Cue(1_000, 4_500, "Welcome back to CS 6030.")
    assert cues[1].text == "Today we start with lambda calculus & its"
    # Hours are optional in VTT: 03:22.000 is 3 min 22 s.
    assert cues[-1].start_ms == 202_000


def test_parse_srt():
    srt = (
        "1\r\n00:00:01,000 --> 00:00:02,000\r\nFirst line\r\n\r\n"
        "2\r\n01:00:00,500 --> 01:00:03,000\r\nAn hour in\r\n"
    )
    assert parse_cues(srt) == [
        Cue(1_000, 2_000, "First line"),
        Cue(3_600_500, 3_603_000, "An hour in"),
    ]


def test_rolling_auto_captions_are_deduplicated():
    vtt = """WEBVTT

00:00:00.000 --> 00:00:02.000
so today we

00:00:02.000 --> 00:00:04.000
so today we
talk about recursion

00:00:04.000 --> 00:00:04.010
talk about recursion

00:00:04.010 --> 00:00:06.000
talk about recursion
and induction
"""
    assert [c.text for c in parse_cues(vtt)] == [
        "so today we",
        "talk about recursion",
        "and induction",
    ]


def test_merge_keeps_first_start_and_splits_on_window():
    cues = [Cue(0, 5_000, "a"), Cue(5_000, 15_000, "b"), Cue(15_000, 25_000, "c")]
    segments = merge_segments(cues, max_ms=20_000)
    assert [(s.start_ms, s.end_ms, s.text) for s in segments] == [
        (0, 15_000, "a b"),
        (15_000, 25_000, "c"),
    ]


def test_merge_splits_on_length():
    cues = [Cue(i * 1000, i * 1000 + 1000, "x" * 50) for i in range(4)]
    assert len(merge_segments(cues, max_chars=120)) == 2


def test_phrase_across_cues_lands_in_one_segment():
    segments = parse_segments((FIXTURES / "lecture4.vtt").read_text())
    assert segments[0].start_ms == 1_000
    assert "its reduction rules" in segments[0].text
    assert segments[-1].start_ms == 202_000


def test_empty_input():
    assert parse_segments("WEBVTT\n\n") == []
