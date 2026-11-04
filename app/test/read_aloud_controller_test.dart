import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/core/read_aloud_controller.dart';

import 'fakes.dart';

Future<void> untilIdle(ReadAloudController c) async {
  for (var i = 0; i < 500 && c.status != ReaderStatus.idle; i++) {
    await pump(1);
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await pump(1);
  }
  expect(condition(), isTrue, reason: 'condition never became true');
}

void main() {
  final doc = FakeDocument([
    'First page. It has two sentences.',
    '', // a blank page (e.g. an image) is skipped
    'Third page only has one.',
  ]);

  test('reads every sentence in order across pages and finishes', () async {
    final engine = FakeEngine();
    final output = FakeOutput();
    final positions = <ReadingPosition>[];
    final c = ReadAloudController(
      document: doc,
      output: output,
      engine: engine,
      onPositionChanged: positions.add,
      sentencePause: Duration.zero,
      pagePause: Duration.zero,
    );
    await c.play(const ReadingPosition(1));
    await untilIdle(c);

    expect(positions, const [ReadingPosition(1, 0), ReadingPosition(1, 1), ReadingPosition(3, 0)]);
    expect(engine.requests.map((r) => r.$1), ['First page.', 'It has two sentences.', 'Third page only has one.']);
    expect(output.played.map((a) => a.samples.length), [110, 210, 240]);
    expect(c.finished, isTrue);
    expect(c.error, isNull);
  });

  test('adds pauses between sentences and longer ones between pages', () async {
    final output = FakeOutput();
    final c = ReadAloudController(
      document: doc,
      output: output,
      engine: FakeEngine(),
      sentencePause: const Duration(milliseconds: 100),
      pagePause: const Duration(milliseconds: 500),
    );
    await c.play();
    await untilIdle(c);
    // 1000 Hz fake audio: +100 samples within a page, +500 before a new page / at the end.
    expect(output.played.map((a) => a.samples.length), [110 + 100, 210 + 500, 240 + 500]);
  });

  test('can start mid-document', () async {
    final engine = FakeEngine();
    final c = ReadAloudController(document: doc, output: FakeOutput(), engine: engine);
    await c.play(const ReadingPosition(1, 1));
    await untilIdle(c);
    expect(engine.requests.first.$1, 'It has two sentences.');
  });

  test('synthesizes ahead while the current sentence plays', () async {
    final engine = FakeEngine();
    final output = FakeOutput(autoFinish: false);
    final c = ReadAloudController(document: doc, output: output, engine: engine, lookahead: 2);
    await c.play();
    await until(() => output.isPlaying);
    expect(c.status, ReaderStatus.playing);
    expect(engine.requests.length, 3); // current + 2 ahead, while sentence 1 still plays
    await c.stop();
  });

  test('pause and resume control the output', () async {
    final output = FakeOutput(autoFinish: false);
    final c = ReadAloudController(document: doc, output: output, engine: FakeEngine());
    await c.play();
    await until(() => output.isPlaying);
    await c.togglePlayPause();
    expect(c.status, ReaderStatus.paused);
    expect(output.paused, isTrue);
    await c.togglePlayPause();
    expect(c.status, ReaderStatus.playing);
    expect(output.paused, isFalse);
    await c.stop();
    expect(c.status, ReaderStatus.idle);
  });

  test('pausing before audio is ready holds playback until resumed', () async {
    final output = FakeOutput(autoFinish: false);
    final c = ReadAloudController(document: doc, output: output, engine: FakeEngine());
    await c.play();
    await c.pause(); // still preparing the first sentence
    await pump();
    expect(output.played, isEmpty);
    expect(c.status, ReaderStatus.paused);
    await c.resume();
    await until(() => output.isPlaying);
    expect(output.played, hasLength(1));
    await c.stop();
  });

  test('skip moves between sentences and across pages', () async {
    final output = FakeOutput(autoFinish: false);
    final c = ReadAloudController(document: doc, output: output, engine: FakeEngine());
    await c.play();
    await until(() => output.isPlaying);
    await c.skip(2);
    await until(() => c.position == const ReadingPosition(3, 0) && output.isPlaying);
    expect(c.currentSentence, 'Third page only has one.');
    await c.skip(-1);
    await until(() => c.position == const ReadingPosition(1, 1) && output.isPlaying);
    await c.stop();
  });

  test('skip while idle just moves the cursor', () async {
    final output = FakeOutput();
    final c = ReadAloudController(document: doc, output: output, engine: FakeEngine());
    await c.skip(1);
    expect(c.position, const ReadingPosition(1, 1));
    expect(c.currentSentence, 'It has two sentences.');
    expect(output.played, isEmpty);
  });

  test('changing the voice re-synthesizes the current sentence', () async {
    final engine = FakeEngine();
    final output = FakeOutput(autoFinish: false);
    final c = ReadAloudController(document: doc, output: output, engine: engine);
    await c.play();
    await until(() => output.isPlaying);
    c.setVoice(speakerId: 7, speed: 1.25);
    await until(() => output.played.length == 2 && output.isPlaying);
    expect(c.position, const ReadingPosition(1, 0));
    expect(engine.requests.last.$2, 7);
    expect(engine.requests.where((r) => r.$2 == 7).first.$1, 'First page.');
    expect(engine.cancelCalls, greaterThan(0));
    await c.stop();
  });

  test('reports documents without text', () async {
    final c = ReadAloudController(document: FakeDocument(['', '  ']), output: FakeOutput(), engine: FakeEngine());
    await c.play();
    await untilIdle(c);
    await pump();
    expect(c.error, contains('no readable text'));
  });

  test('surfaces synthesis errors', () async {
    final c = ReadAloudController(
        document: doc, output: FakeOutput(), engine: FakeEngine(failOn: 'It has two sentences.'));
    await c.play();
    await untilIdle(c);
    await pump();
    expect(c.error, contains('synthesis failed'));
    expect(c.position, const ReadingPosition(1, 0));
  });

  test('asks for a voice when no engine is loaded', () async {
    final c = ReadAloudController(document: doc, output: FakeOutput());
    await c.play();
    expect(c.error, contains('No voice'));
    expect(c.status, ReaderStatus.idle);
  });
}
