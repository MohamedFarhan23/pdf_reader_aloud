import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/core/text_chunker.dart';

void main() {
  test('chunks remember which one ends a paragraph or heading', () {
    final chunks = chunkParagraphs('Heading\n\nOne. Two.\n\nThree.');
    expect(chunks.map((c) => c.text), ['Heading', 'One.', 'Two.', 'Three.']);
    expect(chunks.map((c) => c.endsParagraph), [true, false, true, true]);
  });
}
