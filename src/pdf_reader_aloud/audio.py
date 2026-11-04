"""Audio outputs: live playback through the speakers, or writing a WAV file."""

from __future__ import annotations

import shutil
import subprocess
import wave
from abc import ABC, abstractmethod
from pathlib import Path

import numpy as np


class AudioSink(ABC):
    def __init__(self, sample_rate: int):
        self.sample_rate = sample_rate

    @abstractmethod
    def write(self, samples: np.ndarray) -> None:
        """Queue mono float32 samples for output. May block while audio plays."""

    def close(self) -> None:
        """Flush and release the output."""

    def abort(self) -> None:
        """Stop immediately, dropping anything still buffered."""
        self.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, *_):
        if exc_type is None:
            self.close()
        else:
            self.abort()


class WavSink(AudioSink):
    """Writes 16-bit mono PCM WAV using only the standard library."""

    def __init__(self, path: str | Path, sample_rate: int):
        super().__init__(sample_rate)
        self._wav = wave.open(str(path), "wb")
        self._wav.setnchannels(1)
        self._wav.setsampwidth(2)
        self._wav.setframerate(sample_rate)

    def write(self, samples: np.ndarray) -> None:
        pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
        self._wav.writeframes(pcm.tobytes())

    def close(self) -> None:
        self._wav.close()


class SoundDeviceSink(AudioSink):
    """Plays through PortAudio (sounddevice). Writes block, giving natural pacing."""

    def __init__(self, sample_rate: int):
        super().__init__(sample_rate)
        import sounddevice as sd

        self._stream = sd.OutputStream(samplerate=sample_rate, channels=1, dtype="float32")
        self._stream.start()

    def write(self, samples: np.ndarray) -> None:
        self._stream.write(np.ascontiguousarray(samples, dtype=np.float32).reshape(-1, 1))

    def close(self) -> None:
        self._stream.stop()
        self._stream.close()

    def abort(self) -> None:
        self._stream.abort()
        self._stream.close()


class PipeSink(AudioSink):
    """Streams raw PCM into an external player (ffplay, aplay, pacat, termux)."""

    def __init__(self, sample_rate: int, command: list[str], fmt: str = "f32"):
        super().__init__(sample_rate)
        self._fmt = fmt
        self._proc = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    def write(self, samples: np.ndarray) -> None:
        if self._fmt == "s16":
            data = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2").tobytes()
        else:
            data = np.asarray(samples, dtype="<f4").tobytes()
        try:
            self._proc.stdin.write(data)
            self._proc.stdin.flush()
        except BrokenPipeError:
            raise RuntimeError("Audio player exited unexpectedly") from None

    def close(self) -> None:
        if self._proc.stdin and not self._proc.stdin.closed:
            try:
                self._proc.stdin.close()
            except BrokenPipeError:
                pass
        self._proc.wait()

    def abort(self) -> None:
        self._proc.kill()
        self._proc.wait()


def _pipe_players(sample_rate: int) -> list[tuple[str, list[str], str]]:
    sr = str(sample_rate)
    return [
        ("ffplay", ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet",
                    "-f", "f32le", "-ar", sr, "-ch_layout", "mono", "-i", "-"], "f32"),
        ("pacat", ["pacat", "--format=float32le", f"--rate={sr}", "--channels=1"], "f32"),
        ("aplay", ["aplay", "-q", "-f", "FLOAT_LE", "-r", sr, "-c", "1"], "f32"),
        # Android / Termux: `pkg install sox` provides `play`.
        ("play", ["play", "-q", "-t", "raw", "-e", "floating-point", "-b", "32",
                  "-r", sr, "-c", "1", "-"], "f32"),
    ]


def open_player(sample_rate: int) -> AudioSink:
    """Open the best available live audio output."""
    try:
        return SoundDeviceSink(sample_rate)
    except Exception:
        pass
    for binary, command, fmt in _pipe_players(sample_rate):
        if shutil.which(binary):
            return PipeSink(sample_rate, command, fmt)
    raise RuntimeError(
        "No audio output found. Install one of: the 'sounddevice' Python package (PortAudio), "
        "ffplay (ffmpeg), pacat, aplay or sox. Or use --out file.wav to save the audio instead."
    )
