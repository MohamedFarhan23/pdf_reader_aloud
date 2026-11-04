import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/core/text_chunker.dart';

void main() {
  test('cleanPdfText joins wrapped lines, hyphenation and ligatures', () {
    expect(
      cleanPdfText('It was a quiet morn-\ning in the\nvillage.\n\nNew paraﬁne.'),
      'It was a quiet morning in the village.\n\nNew parafine.',
    );
  });

  test('splitSentences respects abbreviations and initials', () {
    expect(
      splitSentences('Dr. Smith met J. R. Tolkien, e.g. at noon. Then they left! Did they?'),
      ['Dr. Smith met J. R. Tolkien, e.g. at noon.', 'Then they left!', 'Did they?'],
    );
  });

  test('splitSentences handles quotes and numbers', () {
    expect(
      splitSentences('He said "Stop." 42 people agreed. See Fig. 3 for details.'),
      ['He said "Stop."', '42 people agreed.', 'See Fig. 3 for details.'],
    );
  });

  test('chunkText keeps chunks under the limit without losing words', () {
    final long = '${List.filled(30, 'a clause with some words').join(', ')}.';
    final chunks = chunkText(long, maxChars: 100);
    expect(chunks.every((c) => c.length <= 100), isTrue);
    expect(chunks.join(' ').replaceAll(' ', ''), long.replaceAll(' ', ''));
  });

  test('chunkText drops chunks with nothing to say', () {
    expect(chunkText('...\n\n Hello there.'), ['Hello there.']);
  });

  test('sentencesForPage works on raw extracted text', () {
    expect(sentencesForPage('Chapter One\n\nThe first line wraps\nhere. Done!'),
        ['Chapter One', 'The first line wraps here.', 'Done!']);
  });

  test('headings and short paragraph endings become their own chunks', () {
    const page = 'The Quiet Library\n'
        'Chapter One\n'
        'Every morning, Dr. Amara Okafor unlocked the old library on Willow Street before the\n'
        'town was awake. She liked the silence, the smell of paper, and the way the light came\n'
        'through the tall windows.\n'
        'Today was different. A parcel was waiting on the front step, wrapped in brown paper\n'
        'and tied with string.';
    expect(sentencesForPage(page), [
      'The Quiet Library',
      'Chapter One',
      'Every morning, Dr. Amara Okafor unlocked the old library on Willow Street before the town was awake.',
      'She liked the silence, the smell of paper, and the way the light came through the tall windows.',
      'Today was different.',
      'A parcel was waiting on the front step, wrapped in brown paper and tied with string.',
    ]);
  });

  test('wrapped lines that continue a sentence are not split', () {
    const page = 'The results, shown in Table 2, were consistent across all of the\n'
        'Western sites, and the effect held for every age group we sampled in\n'
        'October and November of that year.';
    expect(sentencesForPage(page), [
      'The results, shown in Table 2, were consistent across all of the Western sites, '
          'and the effect held for every age group we sampled in October and November of that year.',
    ]);
  });
}
