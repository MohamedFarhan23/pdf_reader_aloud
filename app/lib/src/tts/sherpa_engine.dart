import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../audio/audio_polish.dart';
import '../core/interfaces.dart';
import 'voice_catalog.dart';

class CancelledException implements Exception {
  @override
  String toString() => 'cancelled';
}

/// Everything needed to construct a sherpa-onnx TTS model (plain data, so it can
/// be sent to the synthesis isolate).
class SherpaModelConfig {
  const SherpaModelConfig({
    required this.family,
    required this.dir,
    this.onnxFile,
    this.british = false,
    this.numThreads = 2,
  });

  factory SherpaModelConfig.forModel(VoiceModel model, String dir, {bool british = false, int? numThreads}) =>
      SherpaModelConfig(
        family: model.family,
        dir: dir,
        onnxFile: model.onnxFile,
        british: british,
        numThreads: numThreads ?? defaultThreadCount(),
      );

  final VoiceFamily family;

  /// Clarity EQ applied to this model's output (see `SpeechEq`).
  SpeechEq get eq => switch (family) {
    VoiceFamily.piper => SpeechEq.none,
    VoiceFamily.kokoro => (onnxFile ?? 'model.int8.onnx').contains('int8') ? SpeechEq.kokoroCompact : SpeechEq.kokoro,
  };

  final String dir;
  final String? onnxFile;
  final bool british;
  final int numThreads;

  /// Up to 4 threads: phones have 2-4 fast cores; more threads only add contention.
  static int defaultThreadCount() => math.max(1, math.min(4, Platform.numberOfProcessors));

  sherpa.OfflineTtsConfig toSherpa() {
    final espeak = '$dir/espeak-ng-data';
    final model = switch (family) {
      VoiceFamily.kokoro => sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: '$dir/${onnxFile ?? 'model.int8.onnx'}',
          voices: '$dir/voices.bin',
          tokens: '$dir/tokens.txt',
          dataDir: espeak,
          // The lexicon gives exact pronunciations; espeak-ng covers unknown words.
          lexicon: british ? '$dir/lexicon-gb-en.txt' : '$dir/lexicon-us-en.txt',
          lang: british ? 'en' : 'en-us',
        ),
        numThreads: numThreads,
        debug: false,
      ),
      VoiceFamily.piper => sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(model: '$dir/$onnxFile', tokens: '$dir/tokens.txt', dataDir: espeak),
        numThreads: numThreads,
        debug: false,
      ),
    };
    return sherpa.OfflineTtsConfig(model: model);
  }
}

class _Request {
  _Request(this.id, this.text, this.speakerId, this.speed);
  final stopwatch = Stopwatch();
  final int id;
  final String text;
  final int speakerId;
  final double speed;
  final completer = Completer<TtsAudio>();
}

/// Runs a sherpa-onnx TTS model on a background isolate so synthesis never
/// blocks the UI. Requests are processed one at a time, in order.
class SherpaTtsEngine implements TtsEngine {
  SherpaTtsEngine._(this._isolate, this._toIsolate, this._port, this._subscription, this.sampleRate, this.numSpeakers) {
    _subscription.onData(_onMessage);
  }

  final Isolate _isolate;
  final SendPort _toIsolate;
  final ReceivePort _port;
  final StreamSubscription<dynamic> _subscription;
  final int sampleRate;
  final int numSpeakers;

  final Queue<_Request> _queue = Queue();
  _Request? _inFlight;
  int _nextId = 0;
  bool _disposed = false;

  /// Loads the model (this can take a few seconds) and returns a ready engine.
  ///
  /// [onStage] is told what the loader is doing ("Warming up…") so the UI can show it.
  static Future<SherpaTtsEngine> load(SherpaModelConfig config, {void Function(String stage)? onStage}) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_isolateMain, [port.sendPort, config], debugName: 'tts');
    final ready = Completer<List<Object?>>();
    final subscription = port.listen((Object? message) {
      final list = message as List<Object?>;
      if (list[0] == 'stage') {
        onStage?.call(list[1] as String);
      } else if (!ready.isCompleted) {
        ready.complete(list);
      }
    });
    final reply = await ready.future;
    if (reply[0] == 'error') {
      unawaited(subscription.cancel());
      isolate.kill();
      port.close();
      throw Exception('Could not load voice model: ${reply[1]}');
    }
    return SherpaTtsEngine._(isolate, reply[1] as SendPort, port, subscription, reply[2] as int, reply[3] as int);
  }

  @override
  Future<TtsAudio> synthesize(String text, {required int speakerId, required double speed}) {
    if (_disposed) return Future.error(StateError('engine disposed'));
    final req = _Request(_nextId++, text, speakerId, speed);
    _queue.add(req);
    _pump();
    return req.completer.future;
  }

  @override
  void cancelPending() {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().completer.completeError(CancelledException());
    }
  }

  void _pump() {
    if (_inFlight != null || _queue.isEmpty || _disposed) return;
    final req = _inFlight = _queue.removeFirst();
    req.stopwatch.start();
    _toIsolate.send([req.id, req.text, req.speakerId, req.speed]);
  }

  void _onMessage(Object? msg) {
    final list = msg as List<Object?>;
    final req = _inFlight;
    if (req == null || list[0] != req.id) return;
    _inFlight = null;
    if (list[1] == 'error') {
      req.completer.completeError(Exception(list[2]));
    } else {
      final bytes = (list[2] as TransferableTypedData).materialize();
      final audio = TtsAudio(bytes.asFloat32List(), list[1] as int);
      // Printed in release builds too: `flutter run --release` shows it, so speed
      // can be judged on a real device.
      final took = req.stopwatch.elapsedMilliseconds / 1000;
      final secs = audio.duration.inMilliseconds / 1000;
      debugPrint(
        'tts: ${secs.toStringAsFixed(1)}s audio in ${took.toStringAsFixed(1)}s '
        '(${(secs / (took == 0 ? 1 : took)).toStringAsFixed(2)}x real time, ${req.text.length} chars)',
      );
      req.completer.complete(audio);
    }
    _pump();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelPending();
    _inFlight?.completer.completeError(CancelledException());
    _inFlight = null;
    _toIsolate.send(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isolate.kill(priority: Isolate.beforeNextEvent);
    await _subscription.cancel();
    _port.close();
  }
}

void _isolateMain(List<Object?> args) {
  final replyTo = args[0] as SendPort;
  final config = args[1] as SherpaModelConfig;
  final inbox = ReceivePort();
  sherpa.OfflineTts tts;
  try {
    sherpa.initBindings();
    replyTo.send(['stage', 'Reading the voice model']);
    tts = sherpa.OfflineTts(config.toSherpa());
    replyTo.send(['stage', 'Warming up the voice']);
    // The first inference is much slower (allocations, kernel selection); do it now.
    tts.generate(text: 'Hello.', sid: 0, speed: 1.0);
  } catch (e) {
    replyTo.send(['error', e.toString()]);
    inbox.close();
    return;
  }
  replyTo.send(['ok', inbox.sendPort, tts.sampleRate, tts.numSpeakers]);
  inbox.listen((msg) {
    if (msg == null) {
      tts.free();
      inbox.close();
      return;
    }
    final m = msg as List<Object?>;
    final id = m[0] as int;
    try {
      final audio = tts.generate(text: m[1] as String, sid: m[2] as int, speed: m[3] as double);
      final (samples, rate) = polishSpeech(
        audio.samples,
        audio.sampleRate == 0 ? tts.sampleRate : audio.sampleRate,
        eq: config.eq,
      );
      replyTo.send([
        id,
        rate,
        TransferableTypedData.fromList([samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes)]),
      ]);
    } catch (e) {
      replyTo.send([id, 'error', e.toString()]);
    }
  });
}

/// Measures how fast an engine synthesizes speech on this device.
class SpeedTestResult {
  const SpeedTestResult(this.audio, this.elapsed);
  final TtsAudio audio;
  final Duration elapsed;

  /// Seconds of speech produced per second of compute; >= 1 means real time.
  double get realTimeFactor => elapsed.inMicroseconds == 0 ? 0 : audio.duration.inMicroseconds / elapsed.inMicroseconds;
}

const speedTestText =
    'Reading aloud should feel effortless. This short passage checks how quickly your device can '
    'turn text into natural speech, so you know whether reading will flow without pauses.';

Future<SpeedTestResult> runSpeedTest(TtsEngine engine, {required int speakerId, double speed = 1.0}) async {
  await engine.synthesize('Hi.', speakerId: speakerId, speed: speed); // warm up
  final sw = Stopwatch()..start();
  final audio = await engine.synthesize(speedTestText, speakerId: speakerId, speed: speed);
  return SpeedTestResult(audio, sw.elapsed);
}
