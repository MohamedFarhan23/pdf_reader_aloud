"""Locating and downloading on-device voice models.

Models are cached in ``$PDF_READER_ALOUD_MODELS`` (default ``~/.cache/pdf-reader-aloud``)
and downloaded once; after that, reading aloud works fully offline.
"""

from __future__ import annotations

import os
import sys
import urllib.request
from pathlib import Path

KOKORO_BASE = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
KOKORO_FILES = ("kokoro-v1.0.int8.onnx", "voices-v1.0.bin")
PIPER_BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0"


def models_dir() -> Path:
    root = os.environ.get("PDF_READER_ALOUD_MODELS")
    path = Path(root).expanduser() if root else Path.home() / ".cache" / "pdf-reader-aloud"
    path.mkdir(parents=True, exist_ok=True)
    return path


def download(url: str, dest: Path) -> Path:
    """Download ``url`` to ``dest`` atomically, with a simple progress line on stderr."""
    if dest.exists():
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".part")
    print(f"Downloading {dest.name} ...", file=sys.stderr)
    try:
        with urllib.request.urlopen(url) as resp, open(tmp, "wb") as out:
            total = int(resp.headers.get("Content-Length") or 0)
            done = 0
            while block := resp.read(1 << 20):
                out.write(block)
                done += len(block)
                if total and sys.stderr.isatty():
                    print(f"\r  {done / total:6.1%} of {total / 1e6:.0f} MB", end="", file=sys.stderr)
        if sys.stderr.isatty():
            print(file=sys.stderr)
        tmp.replace(dest)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    return dest


def ensure_kokoro() -> tuple[Path, Path]:
    """Return paths to the Kokoro model and voices file, downloading them if needed."""
    base = models_dir() / "kokoro"
    model, voices = (download(f"{KOKORO_BASE}/{name}", base / name) for name in KOKORO_FILES)
    return model, voices


def piper_voice_url(voice: str) -> str:
    """Map a voice id like ``en_US-lessac-medium`` to its location in the piper-voices repo."""
    try:
        locale, speaker, quality = voice.split("-", 2)
        lang = locale.split("_")[0]
    except ValueError:
        raise ValueError(
            f"Piper voice {voice!r} should look like 'en_US-lessac-medium' or be a path to a .onnx file"
        ) from None
    return f"{PIPER_BASE}/{lang}/{locale}/{speaker}/{quality}/{voice}.onnx"


def ensure_piper(voice: str) -> Path:
    """Return the path to a Piper voice model (downloading model + config if needed).

    ``voice`` can also be a path to a local ``.onnx`` file (with its ``.onnx.json`` alongside).
    """
    local = Path(voice).expanduser()
    if local.suffix == ".onnx" and local.exists():
        return local
    base = models_dir() / "piper"
    url = piper_voice_url(voice)
    model = download(url, base / f"{voice}.onnx")
    download(url + ".json", base / f"{voice}.onnx.json")
    return model
