import pytest


@pytest.fixture
def sample_pdf(tmp_path):
    """A three-page PDF with hard-wrapped lines and a word hyphenated across lines."""
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfgen import canvas

    path = tmp_path / "sample.pdf"
    c = canvas.Canvas(str(path), pagesize=letter)
    c.setTitle("Sample Document")
    pages = [
        ["Chapter One.", "", "Dr. Smith opened the door. It was a quiet morn-",
         "ing in the village, and nobody was awake."],
        ["The second page has two sentences. Here is the second one!"],
        ["Is this the last page? Yes it is."],
    ]
    for lines in pages:
        y = 720
        for line in lines:
            c.drawString(72, y, line)
            y -= 28 if not line else 14
        c.showPage()
    c.save()
    return path
