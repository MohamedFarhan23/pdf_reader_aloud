"""Loading PDFs and turning their pages into clean, speakable text."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Page:
    number: int  # 1-based, as a human would say it
    text: str


class PdfDocument:
    """A thin wrapper around pypdf that extracts and cleans text page by page."""

    def __init__(self, path: str | Path):
        from pypdf import PdfReader

        self.path = Path(path)
        if not self.path.exists():
            raise FileNotFoundError(f"No such PDF: {self.path}")
        self._reader = PdfReader(str(self.path))
        if self._reader.is_encrypted:
            # Many "encrypted" PDFs only have an owner password; try an empty user password.
            if not self._reader.decrypt(""):
                raise ValueError(f"{self.path} is password protected")
        self._cache: dict[int, str] = {}

    @property
    def page_count(self) -> int:
        return len(self._reader.pages)

    @property
    def title(self) -> str | None:
        meta = self._reader.metadata
        return (meta.title or None) if meta else None

    def page(self, number: int) -> Page:
        if not 1 <= number <= self.page_count:
            raise IndexError(f"Page {number} out of range (1-{self.page_count})")
        if number not in self._cache:
            raw = self._reader.pages[number - 1].extract_text() or ""
            self._cache[number] = clean_text(raw)
        return Page(number, self._cache[number])

    def pages(self, numbers: list[int] | None = None):
        for n in numbers or range(1, self.page_count + 1):
            yield self.page(n)


_LIGATURES = {
    "ﬀ": "ff", "ﬁ": "fi", "ﬂ": "fl", "ﬃ": "ffi", "ﬄ": "ffl",
    "­": "",  # soft hyphen
    "‐": "-", "‑": "-",
}


def clean_text(raw: str) -> str:
    """Normalise text extracted from a PDF so it reads naturally.

    * expands ligatures and drops soft hyphens
    * re-joins words hyphenated across line breaks ("exam-\\nple" -> "example")
    * joins hard-wrapped lines into flowing paragraphs, keeping blank-line breaks
    """
    text = raw
    for src, dst in _LIGATURES.items():
        text = text.replace(src, dst)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t\f\v]+", " ", text)
    # Words broken across lines with a hyphen.
    text = re.sub(r"(\w)-\n\s*(\w)", r"\1\2", text)
    # Paragraph breaks: two or more newlines.
    paragraphs = re.split(r"\n\s*\n", text)
    joined = [re.sub(r"\s*\n\s*", " ", p).strip() for p in paragraphs]
    return "\n\n".join(p for p in joined if p)


def parse_page_range(spec: str | None, page_count: int) -> list[int]:
    """Parse a page selection like ``"1-3,5,8-"`` into a sorted list of page numbers."""
    if not spec:
        return list(range(1, page_count + 1))
    pages: set[int] = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start_s, end_s = part.split("-", 1)
            start = int(start_s) if start_s.strip() else 1
            end = int(end_s) if end_s.strip() else page_count
        else:
            start = end = int(part)
        if start < 1 or end > page_count or start > end:
            raise ValueError(f"Invalid page range {part!r} for a {page_count}-page document")
        pages.update(range(start, end + 1))
    return sorted(pages)
