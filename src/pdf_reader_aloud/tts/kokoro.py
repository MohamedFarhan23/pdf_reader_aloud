"""Kokoro-82M via ONNX Runtime: a small model with a very natural voice."""

from __future__ import annotations

import numpy as np

from ..models import ensure_kokoro
from .base import Audio, TTSEngine


class KokoroEngine(TTSEngine):
    name = "kokoro"
    default_voice = "af_heart"

    def __init__(self, voice: str | None = None, speed: float = 1.0, lang: str = "en-us",
                 model_path: str | None = None, voices_path: str | None = None):
        try:
            from kokoro_onnx import Kokoro
        except ImportError as exc:  # pragma: no cover - depends on optional extra
            raise RuntimeError(
                "Kokoro backend needs the 'kokoro-onnx' package: pip install 'pdf-reader-aloud[kokoro]'"
            ) from exc
        if not (model_path and voices_path):
            model_path, voices_path = (str(p) for p in ensure_kokoro())
        self._kokoro = Kokoro(model_path, voices_path)
        self.voice = voice or self.default_voice
        available = self.voices()
        if available and self.voice not in available:
            raise ValueError(f"Unknown Kokoro voice {self.voice!r}. Try one of: {', '.join(available)}")
        self.speed = speed
        self.lang = lang

    @property
    def sample_rate(self) -> int:
        return 24000

    def synthesize(self, text: str) -> Audio:
        samples, sr = self._kokoro.create(text, voice=self.voice, speed=self.speed, lang=self.lang)
        return Audio(np.asarray(samples, dtype=np.float32), sr)

    def voices(self) -> list[str]:
        return sorted(self._kokoro.get_voices())
