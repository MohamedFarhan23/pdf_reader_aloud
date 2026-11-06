/// The seams between the reader and the platform.
///
/// Everything platform-specific (PDF library, TTS runtime, audio output) sits
/// behind these small interfaces, so the reading logic is shared by Android and
/// desktop, and can be unit-tested with fakes.
library;

import 'dart:typed_data';

/// Mono float32 PCM audio in [-1, 1].
class TtsAudio {
  const TtsAudio(this.samples, this.sampleRate);

  final Float32List samples;
  final int sampleRate;

  Duration get duration => Duration(microseconds: sampleRate == 0 ? 0 : samples.length * 1000000 ~/ sampleRate);
}

/// A text-to-speech backend that runs on-device.
abstract class TtsEngine {
  /// Synthesizes one chunk of text (ideally one sentence).
  Future<TtsAudio> synthesize(String text, {required int speakerId, required double speed});

  /// Drops queued (not yet started) synthesis requests, e.g. after a skip.
  void cancelPending() {}

  Future<void> dispose();
}

/// Plays audio clips one after another.
abstract class AudioOutput {
  /// Plays [audio]; the future completes when playback finishes or is stopped.
  Future<void> play(TtsAudio audio);
  Future<void> pause();
  Future<void> resume();

  /// How far into the current clip playback is, or null if unknown or nothing is
  /// playing. Used to keep the on-screen highlight in step with the voice.
  Duration? get position => null;

  /// Stops the current clip (its [play] future completes).
  Future<void> stop();
  Future<void> dispose();
}

/// Access to a document's text, page by page (1-based page numbers).
abstract class DocumentText {
  int get pageCount;
  Future<String> pageText(int pageNumber);
}
