# PDF Reader Aloud

A terminal PDF reader that reads documents aloud in a **natural voice** using
neural text-to-speech models that run **entirely on-device**, small enough for
a laptop, a Raspberry Pi or a phone. No audio or text leaves your machine once
the voice model has been downloaded.

This is the first milestone: the **text-to-speech layer** plus a simple
terminal front end (view pages, read them aloud, save to WAV).

## Install

```bash
pip install -e '.[all]'        # kokoro + piper + sounddevice
# or pick what you need:
pip install -e '.[kokoro]'     # most natural voice
pip install -e '.[piper]'      # lightest / fastest, best for phones
```

The first run downloads the voice model into `~/.cache/pdf-reader-aloud`
(override with `PDF_READER_ALOUD_MODELS`). Run `pdf-reader-aloud download` to
fetch it ahead of time.

For live playback you need one of: the `sounddevice` package (PortAudio),
`ffplay`, `pacat`, `aplay`, or `sox`'s `play`. Without any of these, use `--out file.wav`.

## Usage

```bash
pdf-reader-aloud info paper.pdf                 # pages, word count, listening time
pdf-reader-aloud view paper.pdf -p 1-2          # print page text in the terminal
pdf-reader-aloud view paper.pdf -p 1 --sentences  # see exactly what will be spoken

pdf-reader-aloud read paper.pdf                 # read the whole thing aloud
pdf-reader-aloud read paper.pdf -p 3-5 -s 1.2   # pages 3-5, 20% faster
pdf-reader-aloud read paper.pdf -v bm_george    # a British male Kokoro voice
pdf-reader-aloud read paper.pdf -e piper        # the lightweight engine
pdf-reader-aloud read paper.pdf -o paper.wav    # save as audio instead of playing

pdf-reader-aloud say "Try a voice on any text"  # quick voice test
pdf-reader-aloud voices                         # list Kokoro voices
```

While reading, the current sentence is printed under a page header. Press
**Ctrl+C** to stop; the CLI prints a `--pages N- --from-sentence K` command to
resume where you left off.

## Voice engines

| Engine | Model | Size | Quality | Speed (4-core cloud CPU) |
|---|---|---|---|---|
| `kokoro` (default) | [Kokoro-82M](https://github.com/thewh1teagle/kokoro-onnx), int8 ONNX | ~90 MB + 28 MB voices | Very natural, 50+ voices | ~1x real time |
| `piper` | [Piper](https://github.com/rhasspy/piper) VITS, ONNX | ~60 MB per voice | Good, slightly synthetic | ~35x real time |
| `tone` | none | 0 | Beeps (for tests) | instant |

Kokoro is the most natural, but on slow CPUs it can only just keep up with
playback. If you hear gaps between sentences, use `-e piper`, or render
ahead of time with `-o`.

## How it works

```
PDF ──pypdf──▶ page text ──clean_text──▶ paragraphs ──chunk_text──▶ sentences
                                                                       │
          speakers / WAV ◀── AudioSink ◀── ReadAloud (look-ahead) ◀── TTSEngine
```

* `pdf.py`: extracts text per page; fixes ligatures, hyphenation across line
  breaks and hard-wrapped lines; parses page ranges like `1-3,5,8-`.
* `text.py`: sentence splitting that respects abbreviations (Dr., e.g.,
  initials), and splits over-long sentences at clause or word boundaries.
* `tts/`: the `TTSEngine` interface (`synthesize(text) -> Audio`) with
  Kokoro, Piper and a test tone backend. New engines only need to implement
  `sample_rate` and `synthesize`.
* `reader.py`: synthesizes a few sentences ahead on a background thread while
  the current one plays, adds short pauses between sentences and longer ones
  between pages.
* `audio.py`: live playback (sounddevice, or piping PCM to ffplay, pacat,
  aplay or sox) and a WAV writer.

## Running on Android (Termux)

The engines are pure ONNX Runtime, so the same code runs in
[Termux](https://termux.dev): `pkg install python sox`, then install the
package with the `piper` extra. Piper is the recommended engine on phones.
The future mobile app can reuse the same models through ONNX Runtime Mobile.

## Development

```bash
pip install -e '.[dev]'
pytest
```

The tests use generated PDFs and the `tone` engine, so they need no model downloads.

## Limitations / next steps

* Scanned PDFs without a text layer are reported by `info` but not OCR'd yet.
* Headers, footers and multi-column layouts are read in extraction order.
* Ideas: interactive pause/skip keys, bookmarks, a TUI page viewer,
  sentence highlighting, and a mobile app on the same TTS layer.
