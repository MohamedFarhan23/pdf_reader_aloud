# PDF Reader Aloud

Read PDFs aloud in a **natural voice**, using neural text-to-speech that runs
**entirely on your device**. Reading works offline, and your documents never
leave the phone or computer.

| Folder | What it is |
|---|---|
| [`app/`](app/) | **The application.** Flutter app for **Android** and **desktop** (Linux, Windows, macOS) from one codebase. |
| [`cli/`](cli/) | The original Python terminal prototype (`pdf-reader-aloud read file.pdf`). Handy for scripting and quick voice experiments. |

## The app at a glance

* Open any PDF and view all of its pages (pinch, zoom, scroll).
* Press play and it reads from the page you're looking at, sentence by sentence.
  The page follows along, and the sentence being spoken is shown under the page.
* Pause, skip forward or back by sentence, and change speed (0.75×–2×).
* Remembers where you stopped in every document.
* 28 natural English voices (Kokoro), plus lightweight Piper voices for slower phones.
* A built-in **speed test** that tells you whether your device can run Kokoro smoothly.
* Desktop keyboard shortcuts: <kbd>Space</kbd> play/pause, <kbd>Alt</kbd>+<kbd>←</kbd>/<kbd>→</kbd> previous/next sentence.

See **[app/README.md](app/README.md)** to build and run it on Arch Linux or your Android phone.

## How it fits together

```
 PDF ──pdfrx (PDFium)──▶ page text ──cleanup + sentence split──▶ sentences
                                                                    │
  speakers ◀── SoLoud (miniaudio) ◀── ReadAloudController ◀── sherpa-onnx TTS
                                       (synthesizes ahead)     (Kokoro / Piper,
                                                                background isolate)
```

The reading logic (`app/lib/src/core/`) only talks to three small interfaces:
`DocumentText`, `TtsEngine` and `AudioOutput`. The PDF library, voice engine and
audio backend are each swappable, and the core logic is unit-tested with fakes.
