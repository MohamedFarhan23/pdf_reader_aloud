"""Piper via ONNX Runtime: tiny, fast VITS voices built for phones and Raspberry Pis."""

from __future__ import annotations

import numpy as np

from ..models import ensure_piper
from .base import Audio, TTSEngine


class PiperEngine(TTSEngine):
    name = "piper"
    default_voice = "en_US-lessac-medium"

    def __init__(self, voice: str | None = None, speed: float = 1.0, model_path: str | None = None):
        try:
            from piper import PiperVoice, SynthesisConfig
        except ImportError as exc:  # pragma: no cover - depends on optional extra
            raise RuntimeError(
                "Piper backend needs the 'piper-tts' package: pip install 'pdf-reader-aloud[piper]'"
            ) from exc
        self.voice = voice or self.default_voice
        if not model_path:
            model_path = str(ensure_piper(self.voice))
        self._voice = PiperVoice.load(model_path)
        # Piper controls speed via length_scale: larger = slower.
        self._config = SynthesisConfig(length_scale=1.0 / speed)

    @property
    def sample_rate(self) -> int:
        return self._voice.config.sample_rate

    def synthesize(self, text: str) -> Audio:
        parts = [chunk.audio_float_array for chunk in self._voice.synthesize(text, self._config)]
        samples = np.concatenate(parts) if parts else np.zeros(0, dtype=np.float32)
        return Audio(samples.astype(np.float32, copy=False), self.sample_rate)
