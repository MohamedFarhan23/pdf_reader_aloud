// Integration test against real voice models. Point SHERPA_TEST_MODELS at a
// folder holding the unpacked archives (e.g. kokoro-int8-multi-lang-v1_0/),
// otherwise these tests are skipped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/tts/sherpa_engine.dart';
import 'package:pdf_reader_aloud/src/tts/voice_catalog.dart';

void main() {
  final root = Platform.environment['SHERPA_TEST_MODELS'];

  for (final (model, british, speaker) in [
    (kokoroModel, false, 3),
    (kokoroModel, true, 26),
    (voiceCatalog[1], false, 0),
  ]) {
    final dir = root == null ? null : '$root/${model.archive}';
    final skip = dir == null || !Directory(dir).existsSync() ? 'SHERPA_TEST_MODELS not set' : null;
    test('${model.name} (${british ? 'UK' : 'US'}) synthesizes speech off the UI isolate', () async {
      final engine = await SherpaTtsEngine.load(
        SherpaModelConfig.forModel(model, dir!, british: british),
      );
      try {
        final result = await runSpeedTest(engine, speakerId: speaker);
        final seconds = result.audio.duration.inMilliseconds / 1000;
        // ignore: avoid_print
        print('${model.name}: ${seconds.toStringAsFixed(1)}s audio, ${result.realTimeFactor.toStringAsFixed(2)}x real time');
        expect(seconds, greaterThan(5));
        expect(result.audio.samples.any((s) => s.abs() > 0.05), isTrue, reason: 'audio should not be silent');

        // Words missing from the lexicon still produce speech (espeak-ng fallback).
        final oov = await engine.synthesize('Zylqorvian xenobots.', speakerId: speaker, speed: 1.0);
        expect(oov.duration.inMilliseconds, greaterThan(500));

        // Queued requests can be cancelled after a skip.
        final a = engine.synthesize('One.', speakerId: speaker, speed: 1.0);
        final b = engine.synthesize('Two.', speakerId: speaker, speed: 1.0);
        final bCancelled = expectLater(b, throwsA(isA<CancelledException>()));
        engine.cancelPending();
        expect((await a).samples, isNotEmpty);
        await bCancelled;
      } finally {
        await engine.dispose();
      }
    }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
  }
}
