/// Cleans up raw TTS output before playback: consistent loudness, no clipping,
/// and a high-quality resample to the rate the audio device runs at (so the phone
/// never has to resample with a cheap interpolator).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The rate everything is played at. 48 kHz is native on nearly every phone.
const playbackSampleRate = 48000;

/// Target loudness of the speech itself (RMS), about -18 dBFS: clearly audible
/// without clipping, close to what podcasts and audiobooks use.
const _targetRms = 0.125;
const _maxGain = 8.0;
const _silence = 0.01;

/// Scales [samples] to a steady loudness and softly limits peaks. Returns a new list.
Float32List normalizeLoudness(Float32List samples, {double targetRms = _targetRms}) {
  var sumSquares = 0.0;
  var active = 0;
  for (final v in samples) {
    if (v.abs() > _silence) {
      sumSquares += v * v;
      active++;
    }
  }
  if (active == 0) return Float32List.fromList(samples);
  final rms = math.sqrt(sumSquares / active);
  final gain = (targetRms / rms).clamp(0.25, _maxGain);
  final out = Float32List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = _softLimit(samples[i] * gain);
  }
  return out;
}

/// Linear below 0.7, then a smooth curve that never exceeds 0.98.
double _softLimit(double x) {
  const knee = 0.7;
  const ceiling = 0.98;
  final a = x.abs();
  if (a <= knee) return x;
  final over = (a - knee) / (ceiling - knee);
  final y = knee + (ceiling - knee) * (over / (1 + over));
  return x < 0 ? -y : y;
}

const _halfTaps = 16; // 32-tap kernel
const _phases = 1024;

final Float32List _kernel = _buildKernel();

/// Windowed-sinc (Blackman) kernel for every fractional position.
Float32List _buildKernel() {
  final table = Float32List(_phases * _halfTaps * 2);
  for (var p = 0; p < _phases; p++) {
    final frac = p / _phases;
    var sum = 0.0;
    for (var k = 0; k < _halfTaps * 2; k++) {
      final x = (k - (_halfTaps - 1)) - frac; // distance from the output point
      final sinc = x == 0 ? 1.0 : math.sin(math.pi * x) / (math.pi * x);
      final w = x.abs() >= _halfTaps ? 0.0 : _blackman(0.5 + x / (2 * _halfTaps));
      final v = sinc * w;
      table[p * _halfTaps * 2 + k] = v;
      sum += v;
    }
    for (var k = 0; k < _halfTaps * 2; k++) {
      table[p * _halfTaps * 2 + k] /= sum; // unity gain at DC for every phase
    }
  }
  return table;
}

double _blackman(double t) => 0.42 - 0.5 * math.cos(2 * math.pi * t) + 0.08 * math.cos(4 * math.pi * t);

/// Resamples to [toRate] (upsampling only; equal rates return a copy).
Float32List resample(Float32List input, int fromRate, int toRate) {
  if (fromRate == toRate || input.isEmpty) return Float32List.fromList(input);
  assert(toRate > fromRate, 'only upsampling is supported');
  final outLength = (input.length * toRate / fromRate).floor();
  final out = Float32List(outLength);
  final step = fromRate / toRate;
  const taps = _halfTaps * 2;
  for (var n = 0; n < outLength; n++) {
    final pos = n * step;
    final base = pos.floor();
    final phase = ((pos - base) * _phases).floor();
    final row = phase * taps;
    final first = base - (_halfTaps - 1);
    var acc = 0.0;
    for (var k = 0; k < taps; k++) {
      final i = first + k;
      if (i >= 0 && i < input.length) acc += input[i] * _kernel[row + k];
    }
    out[n] = acc;
  }
  return out;
}

enum SpeechEq {
  none,

  /// For Kokoro: its output is bass-heavy with weak 1-4 kHz (where consonants and
  /// clarity live), which sounds muffled, "like talking through a phone". Cuts the
  /// low boom, lifts the presence range, and (compact model only) trims the hiss
  /// left by quantization.
  kokoro,
  kokoroCompact,
}

class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double process(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  // RBJ audio-EQ-cookbook filters.
  factory _Biquad._make(String kind, double fs, double f0, double q, double gainDb) {
    final a = math.pow(10, gainDb / 40).toDouble();
    final w = 2 * math.pi * f0 / fs;
    final cosW = math.cos(w);
    final alpha = math.sin(w) / (2 * q);
    double b0, b1, b2, a0, a1, a2;
    switch (kind) {
      case 'hp':
        b0 = (1 + cosW) / 2;
        b1 = -(1 + cosW);
        b2 = (1 + cosW) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW;
        a2 = 1 - alpha;
      case 'peak':
        b0 = 1 + alpha * a;
        b1 = -2 * cosW;
        b2 = 1 - alpha * a;
        a0 = 1 + alpha / a;
        a1 = -2 * cosW;
        a2 = 1 - alpha / a;
      case 'lowshelf':
        final k = 2 * math.sqrt(a) * alpha;
        b0 = a * ((a + 1) - (a - 1) * cosW + k);
        b1 = 2 * a * ((a - 1) - (a + 1) * cosW);
        b2 = a * ((a + 1) - (a - 1) * cosW - k);
        a0 = (a + 1) + (a - 1) * cosW + k;
        a1 = -2 * ((a - 1) + (a + 1) * cosW);
        a2 = (a + 1) + (a - 1) * cosW - k;
      case 'highshelf':
        final k = 2 * math.sqrt(a) * alpha;
        b0 = a * ((a + 1) + (a - 1) * cosW + k);
        b1 = -2 * a * ((a - 1) + (a + 1) * cosW);
        b2 = a * ((a + 1) + (a - 1) * cosW - k);
        a0 = (a + 1) - (a - 1) * cosW + k;
        a1 = 2 * ((a - 1) - (a + 1) * cosW);
        a2 = (a + 1) - (a - 1) * cosW - k;
      default:
        throw ArgumentError(kind);
    }
    return _Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }
}

/// Applies the voice-clarity EQ for [eq] at sample rate [rate].
Float32List applyEq(Float32List samples, int rate, SpeechEq eq) {
  if (eq == SpeechEq.none || samples.isEmpty) return samples;
  final fs = rate.toDouble();
  // The compact (int8) model is duller and noisier than HQ, so it gets more help.
  final compact = eq == SpeechEq.kokoroCompact;
  final chain = [
    _Biquad._make('hp', fs, 70, 0.707, 0),
    _Biquad._make('lowshelf', fs, 220, 0.7, compact ? -6 : -4),
    _Biquad._make('peak', fs, 1400, 0.9, compact ? 4 : 1.5),
    _Biquad._make('peak', fs, 3200, 0.9, compact ? 7.5 : 4),
    if (compact) _Biquad._make('highshelf', fs, 8000, 0.7, -5),
  ];
  final out = Float32List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    var v = samples[i].toDouble();
    for (final f in chain) {
      v = f.process(v);
    }
    out[i] = v;
  }
  return out;
}

/// Applies [eq], normalizes loudness, then resamples to [playbackSampleRate].
(Float32List, int) polishSpeech(Float32List samples, int sampleRate, {SpeechEq eq = SpeechEq.none}) {
  final loud = normalizeLoudness(applyEq(samples, sampleRate, eq));
  if (sampleRate >= playbackSampleRate) return (loud, sampleRate);
  return (resample(loud, sampleRate, playbackSampleRate), playbackSampleRate);
}
