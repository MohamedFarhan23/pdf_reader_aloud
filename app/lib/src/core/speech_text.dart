/// Rewrites a sentence for the voice model (the on-screen text is left alone).
///
/// TTS models read a digit string as one number ("9876543210" becomes "nine
/// billion eight hundred..."). Phone numbers, IDs and similar long digit runs
/// are spoken digit by digit instead; years, dates, prices and decimals are kept.
library;

// Digits with spaces, hyphens, dots or brackets between them: "+91 98765 43210",
// "(555) 123-4567", "555.123.4567", "9876543210".
final _digitRun = RegExp(r'(?<![\w.,/])(\+?)(\(?\d[\d\s().-]{5,}\d)(?![\w/]|,\d)');
final _plainRange = RegExp(r'^\d{4}\s*[-–]\s*\d{4}$'); // 1990-2005
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$'); // 2024-05-17
final _decimal = RegExp(r'^\d+\.\d+$'); // 3.14159265

String _spoken(String digits) => digits.split('').join(' ');

final _citation = RegExp(r'\s*\[\d+(?:\s*[,–-]\s*\d+)*\]');
final _superscripts = RegExp(r'[⁰¹²³⁴⁵⁶⁷⁸⁹]+');
final _url = RegExp(r'\b(?:https?://|www\.)\S+');

/// Spoken forms of abbreviations the voice would otherwise spell out or stumble on.
final _abbreviations = <RegExp, String>{
  RegExp(r'\be\.g\.', caseSensitive: false): 'for example',
  RegExp(r'\bi\.e\.', caseSensitive: false): 'that is',
  RegExp(r'\betc\.'): 'et cetera',
  RegExp(r'\bvs\.'): 'versus',
  RegExp(r'\bFigs?\.(?=\s*\d)'): 'Figure',
  RegExp(r'\bDr\.'): 'Doctor',
  RegExp(r'\bMr\.'): 'Mister',
  RegExp(r'\bMrs\.'): 'Missus',
  RegExp(r'\bProf\.'): 'Professor',
  RegExp(r' & '): ' and ',
};

String speechText(String sentence) {
  var text = sentence.replaceAll(_citation, '').replaceAll(_superscripts, '').replaceAll(_url, 'link');
  _abbreviations.forEach((pattern, spoken) => text = text.replaceAll(pattern, spoken));
  return _spokenDigits(text);
}

String _spokenDigits(String sentence) {
  return sentence.replaceAllMapped(_digitRun, (m) {
    final body = m[2]!.trim();
    final digitCount = RegExp(r'\d').allMatches(body).length;
    if (digitCount < 7 || digitCount > 15) return m[0]!;
    if (_plainRange.hasMatch(body) || _isoDate.hasMatch(body) || _decimal.hasMatch(body)) return m[0]!;
    final groups = body.split(RegExp(r'[^\d]+')).where((g) => g.isNotEmpty).toList();
    final spoken = groups.length == 1 ? _chunk(groups.single).join(', ') : groups.map(_spoken).join(', ');
    return '${m[1]!.isEmpty ? '' : 'plus '}$spoken';
  });
}

/// "9876543210" -> ["9 8 7", "6 5 4", "3 2 1 0"]: short groups give natural pauses.
List<String> _chunk(String digits) {
  final out = <String>[];
  for (var i = 0; i < digits.length; i += 3) {
    final end = digits.length - (i + 3) < 2 ? digits.length : i + 3; // never leave a 1-digit tail group
    out.add(_spoken(digits.substring(i, end)));
    if (end == digits.length) break;
  }
  return out;
}
