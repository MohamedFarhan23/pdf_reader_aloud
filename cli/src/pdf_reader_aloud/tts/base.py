"""The text-to-speech engine interface every backend implements."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

import numpy as np


@dataclass
class Audio:
    """Mono float32 PCM samples in the range [-1, 1]."""

    samples: np.ndarray
    sample_rate: int

    @property
    def duration(self) -> float:
        return len(self.samples) / self.sample_rate if self.sample_rate else 0.0


class TTSEngine(ABC):
    """A text-to-speech backend.

    Engines are expected to run fully on-device (no network at synthesis time),
    so the same code path works on a laptop, a Raspberry Pi or a phone (Termux).
    """

    name: str = "base"

    @property
    @abstractmethod
    def sample_rate(self) -> int:
        """Sample rate of the audio this engine produces."""

    @abstractmethod
    def synthesize(self, text: str) -> Audio:
        """Turn one chunk of text (ideally a sentence) into audio."""

    def voices(self) -> list[str]:
        """Voices this engine can speak with, if it has more than one."""
        return []

    def warm_up(self) -> None:
        """Run a tiny synthesis so the first real sentence starts quickly."""
        self.synthesize("Hi.")
