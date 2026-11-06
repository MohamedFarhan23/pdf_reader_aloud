/// Turning raw PDF text into clean, sentence-sized chunks for speech.
///
/// Neural TTS sounds best (and starts fastest) when fed one sentence at a time:
/// short inputs keep latency low and stay within the model's input limit.
library;

const _ligatures = {
  'ﬀ': 'ff',
  'ﬁ': 'fi',
  'ﬂ': 'fl',
  'ﬃ': 'ffi',
  'ﬄ': 'ffl',
  '­': '', // soft hyphen
  '‐': '-',
  '‑': '-',
};

/// Normalises text extracted from a PDF page so it reads naturally:
/// expands ligatures, re-joins words hyphenated across line breaks and joins
/// hard-wrapped lines into paragraphs (blank lines stay paragraph breaks).
String cleanPdfText(String raw) {
  var text = raw;
  _ligatures.forEach((from, to) => text = text.replaceAll(from, to));
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(RegExp(r'[ \t\f\v ]+'), ' ');
  // "exam-\nple" -> "example"
  text = text.replaceAllMapped(RegExp(r'(\w)-\n\s*(\w)'), (m) => '${m[1]}${m[2]}');
  text = _markParagraphBreaks(text);
  final paragraphs = text
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
      .where((p) => p.isNotEmpty);
  return paragraphs.join('\n\n');
}

final _startsLikeNewBlock = RegExp(r'^\s*[\p{Lu}\p{N}"“‘(\[•\-–—]', unicode: true);
final _endsSentence = RegExp(r'''[.!?:]["'”’)\]]*\s*$''');
final _endsContinuation = RegExp(r'[,;\-–—]\s*$');

/// PDFs rarely contain blank lines between paragraphs; text extraction gives one
/// line per printed line. A line that is clearly shorter than the page's full
/// lines and is followed by a line starting a new block (capital letter, digit,
/// bullet) is a heading or the end of a paragraph, so mark a break there.
/// Without this, titles run into the first sentence ("Chapter One Every morning...").
String _markParagraphBreaks(String text) {
  final lines = text.split('\n');
  if (lines.length < 2) return text;
  final lengths = lines.map((l) => l.trim().length).where((n) => n > 0).toList()..sort();
  if (lengths.isEmpty) return text;
  // A "full" line: the 80th percentile length, robust to a few long outliers.
  final fullLine = lengths[(lengths.length * 0.8).floor().clamp(0, lengths.length - 1)];
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    out.write(line);
    if (i == lines.length - 1) break;
    final trimmed = line.trim();
    final next = lines[i + 1];
    final isShort = trimmed.isNotEmpty && trimmed.length < fullLine * 0.7;
    final breakHere =
        trimmed.isNotEmpty &&
        next.trim().isNotEmpty &&
        !_endsContinuation.hasMatch(trimmed) &&
        _startsLikeNewBlock.hasMatch(next) &&
        (isShort || (_endsSentence.hasMatch(trimmed) && trimmed.length < fullLine * 0.9));
    out.write(breakHere ? '\n\n' : '\n');
  }
  return out.toString();
}

/// Abbreviations that end with a period but don't end a sentence.
const _abbreviations = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'prof',
  'sr',
  'jr',
  'st',
  'vs',
  'etc',
  'e.g',
  'i.e',
  'fig',
  'figs',
  'eq',
  'eqs',
  'no',
  'vol',
  'pp',
  'p',
  'ch',
  'sec',
  'approx',
  'cf',
  'al',
  'inc',
  'ltd',
  'co',
  'jan',
  'feb',
  'mar',
  'apr',
  'jun',
  'jul',
  'aug',
  'sep',
  'sept',
  'oct',
  'nov',
  'dec',
};

final _sentenceEnd = RegExp(r'''([.!?]+["')\]]*)\s+(?=["'(\[]?[A-Z0-9])''');
final _lastWord = RegExp(r'''([\w.]+)[.!?]+["')\]]*$''');

/// Splits a paragraph into sentences, respecting abbreviations and initials.
List<String> splitSentences(String paragraph) {
  final sentences = <String>[];
  var start = 0;
  for (final match in _sentenceEnd.allMatches(paragraph)) {
    final end = match.start + match[1]!.length;
    final candidate = paragraph.substring(start, end);
    final last = _lastWord.firstMatch(candidate);
    if (last != null) {
      var word = last[1]!.toLowerCase();
      while (word.endsWith('.')) {
        word = word.substring(0, word.length - 1);
      }
      final isInitial = word.length == 1 && RegExp(r'[a-z]').hasMatch(word);
      if (_abbreviations.contains(word) || isInitial) continue;
    }
    sentences.add(candidate.trim());
    start = match.end;
  }
  final tail = paragraph.substring(start).trim();
  if (tail.isNotEmpty) sentences.add(tail);
  return sentences.where((s) => s.isNotEmpty).toList();
}

/// Breaks an over-long sentence at clause boundaries, then at word boundaries.
List<String> _splitLong(String sentence, int maxChars) {
  if (sentence.length <= maxChars) return [sentence];
  final chunks = <String>[];
  var current = '';
  void add(String piece) {
    if (current.isNotEmpty && current.length + 1 + piece.length > maxChars) {
      chunks.add(current);
      current = piece;
    } else {
      current = current.isEmpty ? piece : '$current $piece';
    }
  }

  for (final part in sentence.split(RegExp(r'(?<=[,;:—])\s+'))) {
    if (part.length > maxChars) {
      part.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).forEach(add);
    } else {
      add(part);
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

final _speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// A speakable chunk and whether it is the last one of its paragraph (or heading).
typedef Chunk = ({String text, bool endsParagraph});

/// Turns a page of (already cleaned) text into ordered speakable chunks, remembering
/// paragraph ends so the reader can pause longer there.
List<Chunk> chunkParagraphs(String text, {int maxChars = 300}) {
  final out = <Chunk>[];
  for (final paragraph in text.split(RegExp(r'\n\s*\n'))) {
    final flat = paragraph.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
    if (flat.isEmpty) continue;
    final pieces = <String>[];
    for (final sentence in splitSentences(flat)) {
      pieces.addAll(_splitLong(sentence, maxChars));
    }
    final speakable = pieces.where(_speakable.hasMatch).toList();
    for (var i = 0; i < speakable.length; i++) {
      out.add((text: speakable[i], endsParagraph: i == speakable.length - 1));
    }
  }
  return out;
}

/// Turns a page of (already cleaned) text into an ordered list of speakable chunks.
List<String> chunkText(String text, {int maxChars = 300}) => [
  for (final c in chunkParagraphs(text, maxChars: maxChars)) c.text,
];

/// Cleans raw page text and splits it into sentences in one step.
List<String> sentencesForPage(String rawText, {int maxChars = 300}) =>
    chunkText(cleanPdfText(rawText), maxChars: maxChars);
