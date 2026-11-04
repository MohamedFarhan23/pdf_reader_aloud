from pdf_reader_aloud.pdf import clean_text, parse_page_range
from pdf_reader_aloud.text import chunk_text, split_sentences

import pytest


def test_clean_text_joins_lines_and_hyphenation():
    raw = "It was a quiet morn-\ning in the\nvillage.\n\nNew paraﬁne."
    assert clean_text(raw) == "It was a quiet morning in the village.\n\nNew parafine."


def test_split_sentences_respects_abbreviations_and_initials():
    text = "Dr. Smith met J. R. Tolkien, e.g. at noon. Then they left! Did they?"
    assert split_sentences(text) == [
        "Dr. Smith met J. R. Tolkien, e.g. at noon.",
        "Then they left!",
        "Did they?",
    ]


def test_chunk_text_splits_long_sentences():
    long = ", ".join(["a clause with some words"] * 30) + "."
    chunks = chunk_text(long, max_chars=100)
    assert all(len(c) <= 100 for c in chunks)
    assert " ".join(chunks).replace(" ", "") == long.replace(" ", "")


def test_chunk_text_drops_unpronounceable():
    assert chunk_text("...\n\n Hello there.") == ["Hello there."]


@pytest.mark.parametrize("spec,expected", [
    (None, [1, 2, 3, 4, 5]),
    ("2", [2]),
    ("1-2,4", [1, 2, 4]),
    ("4-", [4, 5]),
    ("-2", [1, 2]),
    ("3,1-2,3", [1, 2, 3]),
])
def test_parse_page_range(spec, expected):
    assert parse_page_range(spec, 5) == expected


@pytest.mark.parametrize("spec", ["0", "6", "3-2", "x"])
def test_parse_page_range_rejects_bad(spec):
    with pytest.raises(ValueError):
        parse_page_range(spec, 5)
