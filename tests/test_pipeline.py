import wave

import numpy as np

from pdf_reader_aloud.audio import AudioSink
from pdf_reader_aloud.cli import main
from pdf_reader_aloud.pdf import PdfDocument
from pdf_reader_aloud.reader import ReadAloud, utterances
from pdf_reader_aloud.tts import ToneEngine


class ListSink(AudioSink):
    def __init__(self, sample_rate):
        super().__init__(sample_rate)
        self.chunks = []

    def write(self, samples):
        self.chunks.append(np.asarray(samples))


def test_pdf_document_reads_all_pages(sample_pdf):
    doc = PdfDocument(sample_pdf)
    assert doc.page_count == 3
    assert doc.title == "Sample Document"
    assert "morning in the village" in doc.page(1).text
    assert [p.number for p in doc.pages([3, 1])] == [3, 1]


def test_utterances_cover_every_page_in_order(sample_pdf):
    items = list(utterances(PdfDocument(sample_pdf).pages()))
    assert [u.page for u in items] == [1, 1, 1, 2, 2, 3, 3]
    assert items[1].text == "Dr. Smith opened the door."
    assert items[-1].text == "Yes it is."


def test_read_aloud_speaks_everything_with_pauses(sample_pdf):
    engine = ToneEngine()
    sink = ListSink(engine.sample_rate)
    seen = []
    reader = ReadAloud(engine, sink, on_utterance=seen.append)
    spoken = reader.run(utterances(PdfDocument(sample_pdf).pages()))
    assert spoken == len(seen) == 7
    # One silence gap between each pair of utterances.
    assert len(sink.chunks) == 7 * 2 - 1


def test_read_aloud_resamples_to_sink_rate():
    engine = ToneEngine()
    sink = ListSink(engine.sample_rate * 2)
    from pdf_reader_aloud.reader import Utterance

    ReadAloud(engine, sink).run([Utterance(1, 0, "one two")])
    expected = len(engine.synthesize("one two").samples) * 2
    assert len(sink.chunks[0]) == expected


def test_read_aloud_surfaces_engine_errors():
    class Broken(ToneEngine):
        def synthesize(self, text):
            raise RuntimeError("boom")

    from pdf_reader_aloud.reader import Utterance
    import pytest

    with pytest.raises(RuntimeError, match="boom"):
        ReadAloud(Broken(), ListSink(16000)).run([Utterance(1, 0, "hi")])


def test_cli_read_writes_wav(sample_pdf, tmp_path, capsys):
    out = tmp_path / "out.wav"
    assert main(["read", str(sample_pdf), "--engine", "tone", "--pages", "2-3", "--out", str(out)]) == 0
    with wave.open(str(out)) as w:
        assert w.getframerate() == 16000
        assert w.getnframes() > 16000
    printed = capsys.readouterr().out
    assert "Page 2 / 3" in printed and "Chapter One" not in printed


def test_cli_view_and_info(sample_pdf, capsys):
    assert main(["view", str(sample_pdf), "--pages", "1", "--sentences"]) == 0
    assert "2. Dr. Smith opened the door." in capsys.readouterr().out
    assert main(["info", str(sample_pdf)]) == 0
    assert "Pages:  3" in capsys.readouterr().out


def test_cli_missing_file(capsys):
    assert main(["info", "nope.pdf"]) == 1
    assert "No such PDF" in capsys.readouterr().err
