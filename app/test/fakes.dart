import 'dart:async';
import 'dart:typed_data';

import 'package:pdf_reader_aloud/src/core/interfaces.dart';

class FakeDocument implements DocumentText {
  FakeDocument(this.pages);
  final List<String> pages;
  @override
  int get pageCount => pages.length;
  @override
  Future<String> pageText(int pageNumber) async => pages[pageNumber - 1];
}

/// Produces 10 samples per character so tests can tell clips apart by length.
class FakeEngine implements TtsEngine {
  FakeEngine({this.failOn});
  final String? failOn;
  final requests = <(String, int, double)>[];
  int cancelCalls = 0;

  @override
  Future<TtsAudio> synthesize(String text, {required int speakerId, required double speed}) async {
    requests.add((text, speakerId, speed));
    await Future<void>.delayed(Duration.zero);
    if (text == failOn) throw Exception('synthesis failed');
    return TtsAudio(Float32List(text.length * 10), 1000);
  }

  @override
  void cancelPending() => cancelCalls++;

  @override
  Future<void> dispose() async {}
}

/// Records clips; each one "plays" until [finishCurrent] is called (or
/// immediately when [autoFinish] is true).
class FakeOutput implements AudioOutput {
  FakeOutput({this.autoFinish = true});
  final bool autoFinish;
  final played = <TtsAudio>[];
  Completer<void>? _current;
  bool paused = false;
  int stops = 0;

  bool get isPlaying => _current != null;

  @override
  Duration? get position => null;

  @override
  Future<void> play(TtsAudio audio) {
    played.add(audio);
    final c = _current = Completer<void>();
    if (autoFinish) scheduleMicrotask(finishCurrent);
    return c.future;
  }

  void finishCurrent() {
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> pause() async => paused = true;
  @override
  Future<void> resume() async => paused = false;
  @override
  Future<void> stop() async {
    stops++;
    finishCurrent();
  }

  @override
  Future<void> dispose() async {}
}

Future<void> pump([int times = 20]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
