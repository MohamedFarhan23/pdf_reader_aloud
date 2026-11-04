import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/interfaces.dart';

/// Low-latency playback through SoLoud (miniaudio): AAudio/OpenSL on Android,
/// PulseAudio/ALSA on Linux, WASAPI on Windows, Core Audio on macOS.
///
/// Clips are handed over in memory and start within milliseconds, so sentences
/// flow without the gaps a file-based media player adds between clips.
class SoloudAudioOutput implements AudioOutput {
  static Future<void>? _initializing;

  /// Initializes the shared audio engine once per app run.
  static Future<void> ensureInitialized() => _initializing ??= SoLoud.instance.init(
        sampleRate: 24000, // Kokoro's native rate; Piper's 22.05 kHz is resampled
        channels: Channels.mono,
        bufferSize: 2048,
      );

  AudioSource? _source;
  SoundHandle? _handle;
  Completer<void>? _done;
  StreamSubscription<StreamSoundEvent>? _events;
  int _clips = 0;

  @override
  Future<void> play(TtsAudio audio) async {
    await stop();
    await ensureInitialized();
    final done = _done = Completer<void>();
    final source = _source = await SoLoud.instance.loadMem('clip${_clips++}.wav', encodeWav(audio));
    if (!identical(done, _done)) {
      // Stopped while loading.
      await SoLoud.instance.disposeSource(source);
      return;
    }
    _events = source.soundEvents.listen((e) {
      if (e.event == SoundEventType.handleIsNoMoreValid) _finish();
    });
    _handle = SoLoud.instance.play(source);
    return done.future;
  }

  void _finish() {
    final done = _done;
    _done = null;
    _handle = null;
    _events?.cancel();
    _events = null;
    final source = _source;
    _source = null;
    if (source != null) SoLoud.instance.disposeSource(source).ignore();
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> pause() async {
    final h = _handle;
    if (h != null) SoLoud.instance.setPause(h, true);
  }

  @override
  Future<void> resume() async {
    final h = _handle;
    if (h != null) SoLoud.instance.setPause(h, false);
  }

  @override
  Future<void> stop() async {
    final h = _handle;
    if (h != null && SoLoud.instance.isInitialized) await SoLoud.instance.stop(h);
    _finish();
  }

  @override
  Future<void> dispose() => stop();
}

/// Encodes mono float samples as a 16-bit PCM WAV file.
Uint8List encodeWav(TtsAudio audio) {
  final n = audio.samples.length;
  final bytes = ByteData(44 + n * 2);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + n * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, audio.sampleRate, Endian.little);
  bytes.setUint32(28, audio.sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (audio.samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + i * 2, v, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
