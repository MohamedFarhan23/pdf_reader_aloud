"""Splitting text into sentence-sized chunks that TTS models handle well.

Neural TTS models sound best (and start faster) when fed one sentence at a time:
short inputs keep latency low and avoid the model's maximum input length.
"""

from __future__ import annotations

import re

# Abbreviations that end with a period but don't end a sentence.
_ABBREVIATIONS = {
    "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e",
    "fig", "figs", "eq", "eqs", "no", "vol", "pp", "p", "ch", "sec", "approx", "cf",
    "al", "inc", "ltd", "co", "jan", "feb", "mar", "apr", "jun", "jul", "aug",
    "sep", "sept", "oct", "nov", "dec",
}

_SENTENCE_END = re.compile(r"([.!?]+[\"')\]]*)\s+(?=[\"'(\[]?[A-Z0-9])")


def split_sentences(paragraph: str) -> list[str]:
    """Split a paragraph into sentences, respecting common abbreviations."""
    sentences: list[str] = []
    start = 0
    for match in _SENTENCE_END.finditer(paragraph):
        end = match.end(1)
        candidate = paragraph[start:end]
        last_word = re.search(r"([\w.]+)[.!?]+[\"')\]]*$", candidate)
        if last_word:
            word = last_word.group(1).lower().rstrip(".")
            # Skip abbreviations and single initials like "J. Smith".
            if word in _ABBREVIATIONS or (len(word) == 1 and word.isalpha()):
                continue
        sentences.append(candidate.strip())
        start = match.end()
    tail = paragraph[start:].strip()
    if tail:
        sentences.append(tail)
    return [s for s in sentences if s]


def _split_long(sentence: str, max_chars: int) -> list[str]:
    """Break an over-long sentence at clause boundaries, then at word boundaries."""
    if len(sentence) <= max_chars:
        return [sentence]
    parts = re.split(r"(?<=[,;:—])\s+", sentence)
    chunks: list[str] = []
    current = ""
    for part in parts:
        if len(part) > max_chars:
            words = part.split()
            for word in words:
                if current and len(current) + 1 + len(word) > max_chars:
                    chunks.append(current)
                    current = word
                else:
                    current = f"{current} {word}".strip()
            continue
        if current and len(current) + 1 + len(part) > max_chars:
            chunks.append(current)
            current = part
        else:
            current = f"{current} {part}".strip()
    if current:
        chunks.append(current)
    return chunks


def chunk_text(text: str, max_chars: int = 300) -> list[str]:
    """Turn a page of text into an ordered list of speakable chunks."""
    chunks: list[str] = []
    for paragraph in re.split(r"\n\s*\n", text):
        paragraph = " ".join(paragraph.split())
        if not paragraph:
            continue
        for sentence in split_sentences(paragraph):
            chunks.extend(_split_long(sentence, max_chars))
    # Drop chunks with nothing pronounceable (e.g. stray page numbers are fine, lone dots aren't).
    return [c for c in chunks if re.search(r"\w", c)]
