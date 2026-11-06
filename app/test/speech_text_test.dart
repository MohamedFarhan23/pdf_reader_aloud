import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/core/speech_text.dart';

void main() {
  speechCleanupTests();
  test('phone numbers are read digit by digit', () {
    expect(speechText('Call +91 98765 43210 today.'), 'Call plus 9 1, 9 8 7 6 5, 4 3 2 1 0 today.');
    expect(speechText('Call (555) 123-4567.'), 'Call 5 5 5, 1 2 3, 4 5 6 7.');
    expect(speechText('Phone: 555.123.4567'), 'Phone: 5 5 5, 1 2 3, 4 5 6 7');
    expect(speechText('Mobile 9876543210'), 'Mobile 9 8 7, 6 5 4, 3 2 1 0');
  });

  test('years, dates, prices, decimals and short numbers are left alone', () {
    for (final s in [
      'In 1999 and 2024 it grew.',
      'From 1990-2005 only.',
      'Dated 2024-05-17.',
      'It costs 1,234,567 dollars.',
      'Pi is 3.14159265 roughly.',
      'Page 12 of 340.',
      'Section 4.2.1 covers it.',
    ]) {
      expect(speechText(s), s, reason: s);
    }
  });
}

void speechCleanupTests() {
  test('citations, links and abbreviations are spoken naturally', () {
    expect(speechText('It works [12] well [3, 4].'), 'It works well.');
    expect(speechText('See www.example.com/x for more.'), 'See link for more.');
    expect(speechText('Fruit, e.g. apples, etc. are fine.'), 'Fruit, for example apples, et cetera are fine.');
    expect(speechText('Dr. Lee & Mr. Wu saw Fig. 3.'), 'Doctor Lee and Mister Wu saw Figure 3.');
  });
}
