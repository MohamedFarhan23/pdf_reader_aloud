import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/audio/audio_polish.dart';

Float32List sine(int rate, double hz, double seconds, double amp) =>
    Float32List.fromList([for (var i = 0; i < rate * seconds; i++) amp * math.sin(2 * math.pi * hz * i / rate)]);

double rms(Float32List s) => math.sqrt(s.fold(0.0, (a, v) => a + v * v) / s.length);

void main() {
  test('quiet speech is brought up to a steady level without clipping', () {
    final quiet = sine(24000, 220, 1, 0.05);
    final loud = normalizeLoudness(quiet);
    expect(rms(loud), closeTo(0.125, 0.01));
    expect(loud.every((v) => v.abs() <= 0.98), isTrue);
  });

  test('loud peaks are limited, not clipped', () {
    final hot = sine(24000, 220, 1, 0.99);
    final out = normalizeLoudness(hot);
    expect(out.map((v) => v.abs()).reduce(math.max), lessThanOrEqualTo(0.98));
    expect(rms(out), greaterThan(0.1));
  });

  test('silence stays silent', () {
    expect(normalizeLoudness(Float32List(100)).every((v) => v == 0), isTrue);
  });

  test('resampling keeps pitch, length and level', () {
    final src = sine(24000, 1000, 0.5, 0.5);
    final up = resample(src, 24000, 48000);
    expect(up.length, 24000);
    final mid = Float32List.sublistView(up, 4000, 20000); // ignore the filter edges
    expect(rms(mid), closeTo(0.5 / math.sqrt2, 0.01));
    var crossings = 0;
    for (var i = 1; i < mid.length; i++) {
      if (mid[i - 1] < 0 && mid[i] >= 0) crossings++;
    }
    expect(crossings, closeTo(1000 * 16000 / 48000, 1)); // 1 kHz over 1/3 s
  });

  test('22.05 kHz voices are resampled to the playback rate too', () {
    final (out, rate) = polishSpeech(sine(22050, 440, 0.5, 0.3), 22050);
    expect(rate, playbackSampleRate);
    expect(out.length, closeTo(24000, 2));
  });

  test('clarity EQ lifts the presence range and cuts the low boom', () {
    double gainDb(double hz, SpeechEq eq) {
      final src = sine(24000, hz, 1, 0.1);
      final out = applyEq(src, 24000, eq);
      final mid = Float32List.sublistView(out, 6000);
      return 20 * math.log(rms(mid) / rms(Float32List.sublistView(src, 6000))) / math.ln10;
    }

    expect(gainDb(3200, SpeechEq.kokoro), greaterThan(3));
    expect(gainDb(120, SpeechEq.kokoro), lessThan(-2));
    expect(gainDb(1000, SpeechEq.kokoro), closeTo(0, 2.5));
    expect(gainDb(3200, SpeechEq.none), closeTo(0, 0.001));
    expect(gainDb(10000, SpeechEq.kokoroCompact), lessThan(-2)); // hiss trimmed on the compact model
  });
}
