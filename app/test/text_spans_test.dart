import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/core/text_chunker.dart';
import 'package:pdf_reader_aloud/src/core/text_spans.dart';

void main() {
  String slice(String raw, int a, int b) => raw.substring(a, b);

  test('sentence spans point at the right text, across wrapped lines', () {
    const raw = 'The quick brown fox\njumps over. It was a "good" day, they said.';
    final spans = alignSentences(raw, sentencesForPage(raw))!;
    expect(spans, hasLength(2));
    expect(slice(raw, spans[0].start, spans[0].end), 'The quick brown fox\njumps over');
    expect(slice(raw, spans[1].start, spans[1].end), 'It was a "good" day, they said');
    expect(spans[0].words.map((w) => slice(raw, w.start, w.end)), ['The', 'quick', 'brown', 'fox', 'jumps', 'over']);
  });

  test('ligatures and words hyphenated across lines still align', () {
    const raw = 'An ofﬁce exam-\nple works. Next.';
    final sentences = sentencesForPage(raw);
    expect(sentences.first, 'An office example works.');
    final spans = alignSentences(raw, sentences)!;
    final words = spans.first.words.map((w) => slice(raw, w.start, w.end)).toList();
    expect(words, ['An', 'ofﬁce', 'exam-\nple', 'works']);
    expect(slice(raw, spans[1].start, spans[1].end), 'Next');
  });

  test('wordIndexAt walks through the words as the clip progresses', () {
    const raw = 'One two three four.';
    final s = alignSentences(raw, sentencesForPage(raw))!.single;
    expect(s.wordIndexAt(0), 0);
    expect(s.wordIndexAt(0.99), 3);
    final seen = [for (var f = 0.0; f <= 1; f += 0.05) s.wordIndexAt(f)];
    expect(seen, orderedEquals([...seen]..sort()));
  });

  test('returns null when the sentences do not match the page text', () {
    expect(alignSentences('Hello world.', ['Something else entirely.']), isNull);
  });
}
