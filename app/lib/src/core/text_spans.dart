/// Maps spoken sentences and words back to character ranges in the PDF's text,
/// so the reader can highlight what is being read.
///
/// Cleaning (see `text_chunker.dart`) only changes whitespace, hyphens and
/// ligatures, never letters or digits. So the page's letters-and-digits stream is
/// identical before and after cleaning, and alignment is just counting.
library;

const _ligatureLetters = {'ﬀ': 'ff', 'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi', 'ﬄ': 'ffl'};

final _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _wordRun = RegExp(r'\S+');

bool _isAlnum(int codeUnit) => _alnum.hasMatch(String.fromCharCode(codeUnit));

int _countAlnum(String s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (_isAlnum(s.codeUnitAt(i))) n++;
  }
  return n;
}

/// A word (or number) inside a sentence, as a half-open range of the raw page text.
class WordSpan {
  const WordSpan(this.start, this.end, this.weight);

  final int start;
  final int end;

  /// Relative time this word takes to say (longer words and words followed by
  /// punctuation take longer).
  final double weight;
}

/// A spoken sentence as a half-open range of the raw page text, plus its words.
class SentenceSpan {
  const SentenceSpan(this.start, this.end, this.words);

  final int start;
  final int end;
  final List<WordSpan> words;

  double get _totalWeight => words.fold(0.0, (sum, w) => sum + w.weight);

  /// The word being spoken [fraction] (0..1) of the way through the sentence's audio.
  int wordIndexAt(double fraction) {
    if (words.isEmpty) return -1;
    final target = fraction.clamp(0.0, 1.0) * _totalWeight;
    var acc = 0.0;
    for (var i = 0; i < words.length; i++) {
      acc += words[i].weight;
      if (target < acc) return i;
    }
    return words.length - 1;
  }
}

int _syllables(String word) {
  final letters = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (letters.isEmpty) return 0;
  var n = RegExp(r'[aeiouy]+').allMatches(letters).length;
  if (n > 1 && letters.endsWith('e') && !letters.endsWith('le')) n--; // silent e
  return n < 1 ? 1 : n;
}

/// Roughly how long a word takes to say, in syllable-ish units: speech time follows
/// syllables, not letters; digits are spoken one by one; commas and full stops add
/// a pause (except at the end of the sentence, which is trimmed as silence).
double _weightOf(String word, int alnum, {required bool last}) {
  final digits = RegExp(r'\d').allMatches(word).length;
  var w = digits > 0 ? digits * 1.3 + _syllables(word) : _syllables(word) + 0.12 * alnum;
  if (!last) {
    if (RegExp(r'[,;]["\x27”’)\]]*$').hasMatch(word)) w += 0.9;
    if (RegExp(r'[.!?:]["\x27”’)\]]*$').hasMatch(word)) w += 1.8;
  }
  return w < 0.5 ? 0.5 : w;
}

/// Aligns [sentences] (from `sentencesForPage(rawText)`) with [rawText].
///
/// Returns one span per sentence, or null if the two disagree (then the caller
/// should simply not highlight).
List<SentenceSpan>? alignSentences(String rawText, List<String> sentences) {
  // Raw index of every letter/digit, ligatures counted as the letters they expand to.
  final rawIndex = <int>[];
  for (var i = 0; i < rawText.length; i++) {
    final ch = rawText[i];
    final expanded = _ligatureLetters[ch] ?? ch;
    for (var k = 0; k < expanded.length; k++) {
      if (_isAlnum(expanded.codeUnitAt(k))) rawIndex.add(i);
    }
  }

  final spans = <SentenceSpan>[];
  var cursor = 0;
  for (final sentence in sentences) {
    final total = _countAlnum(sentence);
    if (total == 0 || cursor + total > rawIndex.length) return null;
    final words = <WordSpan>[];
    var inSentence = cursor;
    final matches = _wordRun.allMatches(sentence).where((m) => _countAlnum(m[0]!) > 0).toList();
    for (var k = 0; k < matches.length; k++) {
      final word = matches[k][0]!;
      final n = _countAlnum(word);
      words.add(
        WordSpan(
          rawIndex[inSentence],
          rawIndex[inSentence + n - 1] + 1,
          _weightOf(word, n, last: k == matches.length - 1),
        ),
      );
      inSentence += n;
    }
    spans.add(SentenceSpan(rawIndex[cursor], rawIndex[cursor + total - 1] + 1, words));
    cursor += total;
  }
  return cursor == rawIndex.length ? spans : null;
}
