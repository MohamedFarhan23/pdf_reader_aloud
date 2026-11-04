"""Command-line interface: ``pdf-reader-aloud <command> ...``."""

from __future__ import annotations

import argparse
import itertools
import shutil
import sys
import textwrap
import time

from . import __version__
from .audio import WavSink, open_player
from .pdf import PdfDocument, parse_page_range
from .reader import ReadAloud, Utterance, utterances
from .text import chunk_text
from .tts import ENGINES, create_engine


def _engine_from_args(args) -> object:
    print(f"Loading {args.engine} voice model...", file=sys.stderr)
    t0 = time.perf_counter()
    engine = create_engine(args.engine, voice=args.voice, speed=args.speed)
    engine.warm_up()
    print(f"Ready in {time.perf_counter() - t0:.1f}s.", file=sys.stderr)
    return engine


def _wrap(text: str, indent: str = "") -> str:
    width = min(shutil.get_terminal_size((100, 24)).columns, 100) - len(indent)
    return "\n\n".join(
        textwrap.fill(p, width=width, initial_indent=indent, subsequent_indent=indent)
        for p in text.split("\n\n")
    )


def cmd_info(args) -> int:
    doc = PdfDocument(args.pdf)
    print(f"File:   {doc.path}")
    print(f"Title:  {doc.title or '(none)'}")
    print(f"Pages:  {doc.page_count}")
    words = sum(len(p.text.split()) for p in doc.pages())
    print(f"Words:  {words}")
    # Neural voices speak roughly 150-170 words per minute at speed 1.0.
    print(f"Listen: ~{max(1, round(words / 160))} min at normal speed")
    empty = [p.number for p in doc.pages() if not p.text.strip()]
    if empty:
        print(f"Note:   no text layer on page(s) {', '.join(map(str, empty))} (scanned? needs OCR)")
    return 0


def cmd_view(args) -> int:
    doc = PdfDocument(args.pdf)
    for page in doc.pages(parse_page_range(args.pages, doc.page_count)):
        header = f" Page {page.number} / {doc.page_count} "
        print(header.center(min(shutil.get_terminal_size((100, 24)).columns, 100), "─"))
        if not page.text.strip():
            print("(no extractable text on this page)")
        elif args.sentences:
            for i, sentence in enumerate(chunk_text(page.text), 1):
                print(f"{i:>4}. {sentence}")
        else:
            print(_wrap(page.text))
        print()
    return 0


def cmd_read(args) -> int:
    doc = PdfDocument(args.pdf)
    page_numbers = parse_page_range(args.pages, doc.page_count)
    items = utterances(doc.pages(page_numbers))
    if args.from_sentence > 1:
        # Skip into the first selected page, e.g. to resume where you stopped.
        first = page_numbers[0]
        items = itertools.dropwhile(lambda u: u.page == first and u.index < args.from_sentence - 1, items)

    engine = _engine_from_args(args)
    sink = WavSink(args.out, engine.sample_rate) if args.out else open_player(engine.sample_rate)

    last = {"utt": None}
    current_page = {"n": None}

    def show(utt: Utterance) -> None:
        last["utt"] = utt
        if args.quiet:
            return
        if utt.page != current_page["n"]:
            current_page["n"] = utt.page
            print(f"\n── Page {utt.page} / {doc.page_count} ──")
        print(_wrap(utt.text, indent="  "), flush=True)

    reader = ReadAloud(engine, sink, sentence_pause=args.pause, on_utterance=show)
    target = f"to {args.out}" if args.out else "aloud"
    print(f"Reading {doc.path.name} {target} (Ctrl+C to stop)", file=sys.stderr)
    t0 = time.perf_counter()
    try:
        with sink:
            spoken = reader.run(items)
    except KeyboardInterrupt:
        reader.stop()
        utt = last["utt"]
        print("\nStopped.", file=sys.stderr)
        if utt:
            print(
                f"Resume with: pdf-reader-aloud read {args.pdf!r} --pages {utt.page}- "
                f"--from-sentence {utt.index + 1}",
                file=sys.stderr,
            )
        return 130
    if args.out:
        print(f"Wrote {spoken} sentences to {args.out} in {time.perf_counter() - t0:.1f}s", file=sys.stderr)
    return 0


def cmd_say(args) -> int:
    engine = _engine_from_args(args)
    text = " ".join(args.text) if args.text else sys.stdin.read()
    sink = WavSink(args.out, engine.sample_rate) if args.out else open_player(engine.sample_rate)
    with sink:
        ReadAloud(engine, sink).run(Utterance(0, i, s) for i, s in enumerate(chunk_text(text)))
    return 0


def cmd_voices(args) -> int:
    if args.engine == "piper":
        print("Piper voices are separate models named like 'en_US-lessac-medium'.")
        print("Browse them at https://huggingface.co/rhasspy/piper-voices (or pass a local .onnx path).")
        return 0
    engine = create_engine(args.engine)
    for voice in engine.voices():
        print(voice)
    return 0


def cmd_download(args) -> int:
    create_engine(args.engine, voice=args.voice)
    print(f"{args.engine} model ready - reading now works offline.")
    return 0


def _add_voice_options(p: argparse.ArgumentParser) -> None:
    p.add_argument("-e", "--engine", choices=ENGINES, default="kokoro",
                   help="TTS engine (default: kokoro, the most natural; piper is lighter/faster)")
    p.add_argument("-v", "--voice", help="voice name (kokoro: e.g. af_heart, bm_george; "
                                         "piper: e.g. en_US-lessac-medium or a .onnx path)")
    p.add_argument("-s", "--speed", type=float, default=1.0, help="speaking speed multiplier (default 1.0)")
    p.add_argument("-o", "--out", help="write a WAV file instead of playing through the speakers")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pdf-reader-aloud",
        description="Read PDFs aloud in a natural voice, using TTS models that run on-device.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("info", help="show page count, length and estimated listening time")
    p.add_argument("pdf")
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("view", help="print the text of pages in the terminal")
    p.add_argument("pdf")
    p.add_argument("-p", "--pages", help="pages to show, e.g. '1-3,5' or '4-' (default: all)")
    p.add_argument("--sentences", action="store_true", help="show the sentence chunks that will be spoken")
    p.set_defaults(func=cmd_view)

    p = sub.add_parser("read", help="read a PDF aloud")
    p.add_argument("pdf")
    p.add_argument("-p", "--pages", help="pages to read, e.g. '1-3,5' or '4-' (default: all)")
    p.add_argument("--from-sentence", type=int, default=1, metavar="N",
                   help="start at sentence N of the first selected page (to resume)")
    p.add_argument("--pause", type=float, default=0.15, help="seconds of silence between sentences")
    p.add_argument("-q", "--quiet", action="store_true", help="don't print text while reading")
    _add_voice_options(p)
    p.set_defaults(func=cmd_read)

    p = sub.add_parser("say", help="speak some text (or stdin) - handy for trying voices")
    p.add_argument("text", nargs="*")
    _add_voice_options(p)
    p.set_defaults(func=cmd_say)

    p = sub.add_parser("voices", help="list available voices for an engine")
    p.add_argument("-e", "--engine", choices=ENGINES, default="kokoro")
    p.set_defaults(func=cmd_voices)

    p = sub.add_parser("download", help="fetch a voice model now so later reading works offline")
    p.add_argument("-e", "--engine", choices=ENGINES, default="kokoro")
    p.add_argument("-v", "--voice")
    p.set_defaults(func=cmd_download)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (FileNotFoundError, ValueError, IndexError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
