"""The read-aloud pipeline: PDF pages -> sentences -> speech -> audio sink.

Synthesis runs in a background thread a few sentences ahead of playback, so the
listener hears continuous speech instead of a pause while each sentence renders.
"""

from __future__ import annotations

import queue
import threading
from dataclasses import dataclass
from typing import Callable, Iterable, Iterator

import numpy as np

from .audio import AudioSink
from .pdf import Page
from .text import chunk_text
from .tts.base import Audio, TTSEngine


@dataclass
class Utterance:
    page: int
    index: int  # position of the sentence within its page (0-based)
    text: str


def utterances(pages: Iterable[Page], max_chars: int = 300) -> Iterator[Utterance]:
    for page in pages:
        for i, sentence in enumerate(chunk_text(page.text, max_chars=max_chars)):
            yield Utterance(page.number, i, sentence)


_DONE = object()


class ReadAloud:
    def __init__(self, engine: TTSEngine, sink: AudioSink, *, lookahead: int = 3,
                 sentence_pause: float = 0.15, page_pause: float = 0.8,
                 on_utterance: Callable[[Utterance], None] | None = None):
        self.engine = engine
        self.sink = sink
        self.lookahead = max(1, lookahead)
        self.sentence_pause = sentence_pause
        self.page_pause = page_pause
        self.on_utterance = on_utterance
        self._stop = threading.Event()

    def stop(self) -> None:
        self._stop.set()

    def _silence(self, seconds: float) -> np.ndarray:
        return np.zeros(int(self.sink.sample_rate * seconds), dtype=np.float32)

    def _resample(self, audio: Audio) -> np.ndarray:
        if audio.sample_rate == self.sink.sample_rate or len(audio.samples) == 0:
            return audio.samples
        # Linear interpolation is plenty for speech when rates differ slightly.
        n = int(round(len(audio.samples) * self.sink.sample_rate / audio.sample_rate))
        x_old = np.linspace(0.0, 1.0, num=len(audio.samples), endpoint=False)
        x_new = np.linspace(0.0, 1.0, num=n, endpoint=False)
        return np.interp(x_new, x_old, audio.samples).astype(np.float32)

    def _produce(self, items: Iterable[Utterance], out: queue.Queue) -> None:
        try:
            for utt in items:
                if self._stop.is_set():
                    break
                audio = self.engine.synthesize(utt.text)
                while not self._stop.is_set():
                    try:
                        out.put((utt, audio), timeout=0.1)
                        break
                    except queue.Full:
                        continue
        except BaseException as exc:  # surface synthesis errors in the main thread
            out.put(exc)
            return
        out.put(_DONE)

    def run(self, items: Iterable[Utterance]) -> int:
        """Speak every utterance in order. Returns how many were spoken."""
        q: queue.Queue = queue.Queue(maxsize=self.lookahead)
        worker = threading.Thread(target=self._produce, args=(items, q), daemon=True)
        worker.start()
        spoken = 0
        last_page: int | None = None
        try:
            while not self._stop.is_set():
                item = q.get()
                if item is _DONE:
                    break
                if isinstance(item, BaseException):
                    raise item
                utt, audio = item
                if last_page is not None:
                    gap = self.page_pause if utt.page != last_page else self.sentence_pause
                    self.sink.write(self._silence(gap))
                if self.on_utterance:
                    self.on_utterance(utt)
                self.sink.write(self._resample(audio))
                last_page = utt.page
                spoken += 1
        finally:
            self._stop.set()
            worker.join(timeout=5)
        return spoken
