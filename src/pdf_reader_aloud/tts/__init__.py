"""Text-to-speech backends.

``kokoro`` (default) - most natural voice, ~90 MB int8 model.
``piper``            - very light and fast, ideal for phones / low-end devices.
``tone``             - no model; emits beeps sized to the text. For tests and wiring checks.
"""

from __future__ import annotations

import numpy as np

from .base import Audio, TTSEngine

ENGINES = ("kokoro", "piper", "tone")


class ToneEngine(TTSEngine):
    """Dependency-free stand-in engine: a short tone per word."""

    name = "tone"

    def __init__(self, speed: float = 1.0, **_ignored):
        self.speed = speed

    @property
    def sample_rate(self) -> int:
        return 16000

    def synthesize(self, text: str) -> Audio:
        words = max(1, len(text.split()))
        per_word = int(self.sample_rate * 0.12 / self.speed)
        t = np.arange(per_word) / self.sample_rate
        beep = 0.2 * np.sin(2 * np.pi * 440 * t) * np.hanning(per_word)
        gap = np.zeros(per_word // 2)
        samples = np.tile(np.concatenate([beep, gap]), words).astype(np.float32)
        return Audio(samples, self.sample_rate)

    def warm_up(self) -> None:
        pass


def create_engine(name: str = "kokoro", **options) -> TTSEngine:
    """Build a TTS engine by name. Options with value ``None`` are ignored."""
    options = {k: v for k, v in options.items() if v is not None}
    if name == "kokoro":
        from .kokoro import KokoroEngine

        return KokoroEngine(**options)
    if name == "piper":
        from .piper import PiperEngine

        options.pop("lang", None)
        return PiperEngine(**options)
    if name == "tone":
        return ToneEngine(**options)
    raise ValueError(f"Unknown engine {name!r}; choose from {', '.join(ENGINES)}")


__all__ = ["Audio", "TTSEngine", "ToneEngine", "create_engine", "ENGINES"]
