import 'dart:async';

import 'package:flutter/foundation.dart';

import 'interfaces.dart';
import 'speech_text.dart';
import 'text_chunker.dart';
import 'text_spans.dart';

/// A sentence within a document: 1-based [page], 0-based [sentence].
@immutable
class ReadingPosition {
  const ReadingPosition(this.page, [this.sentence = 0]);

  final int page;
  final int sentence;

  @override
  bool operator ==(Object other) => other is ReadingPosition && other.page == page && other.sentence == sentence;

  @override
  int get hashCode => Object.hash(page, sentence);

  @override
  String toString() => 'p$page:s$sentence';
}

enum ReaderStatus { idle, preparing, playing, paused }

class _Synthesis {
  _Synthesis(this.future) {
    future.then<void>((a) => result = a, onError: (Object _) {});
  }

  final Future<TtsAudio> future;
  TtsAudio? result;
}

/// Drives reading a document aloud: sentence by sentence, page after page.
///
/// Speech for the next [lookahead] sentences is synthesized while the current
/// one plays, so playback is continuous when the device is fast enough.
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({
    required this.document,
    required this.output,
    this._engine,
    this.lookahead = 3,
    this.sentencePause = const Duration(milliseconds: 200),
    this.paragraphPause = const Duration(milliseconds: 650),
    this.headingPause = const Duration(milliseconds: 750),
    this.pagePause = const Duration(milliseconds: 600),
    this.onPositionChanged,
  });

  final DocumentText document;
  final AudioOutput output;
  final int lookahead;
  final Duration sentencePause;
  final Duration pagePause;

  /// Pause after the last sentence of a paragraph, and after a heading.
  final Duration paragraphPause;
  final Duration headingPause;

  /// Longest piece of text sent to the voice at once. Shorter pieces start sooner,
  /// which matters most after a short heading when the next sentence is long.
  static const maxChunkChars = 140;

  /// Called whenever a new sentence starts playing (use it to save progress).
  void Function(ReadingPosition position)? onPositionChanged;

  TtsEngine? _engine;
  int _speakerId = 0;
  double _speed = 1.0;

  ReaderStatus _status = ReaderStatus.idle;
  ReadingPosition _position = const ReadingPosition(1);
  String? _currentSentence;
  String? _error;
  bool _finished = false;

  int _generation = 0;
  Completer<void>? _resumeGate;
  bool _clipPlaying = false;
  bool _disposed = false;

  final Map<int, List<String>> _sentenceCache = {};
  final Map<int, List<bool>> _paragraphEnds = {};
  final Map<int, String> _rawCache = {};
  final Map<int, List<SentenceSpan>?> _spanCache = {};
  final Stopwatch _clip = Stopwatch();
  Duration _speechStart = Duration.zero;
  Duration _speechEnd = Duration.zero;

  /// The speaker lags the position the mixer reports by about one audio buffer.
  static const _outputLatency = Duration(milliseconds: 90);
  final Map<ReadingPosition, _Synthesis> _synthCache = {};

  ReaderStatus get status => _status;
  bool get isActive => _status != ReaderStatus.idle;
  ReadingPosition get position => _position;
  String? get currentSentence => _currentSentence;
  String? get error => _error;
  bool get finished => _finished;
  bool get hasEngine => _engine != null;
  int get speakerId => _speakerId;
  double get speed => _speed;

  /// Sentences of a page, cleaned and chunked (cached).
  Future<List<String>> sentencesOf(int page) async {
    final cached = _sentenceCache[page];
    if (cached != null) return cached;
    final raw = await document.pageText(page);
    final chunks = chunkParagraphs(cleanPdfText(raw), maxChars: maxChunkChars);
    final sentences = [for (final c in chunks) c.text];
    _rawCache[page] = raw;
    _paragraphEnds[page] = [for (final c in chunks) c.endsParagraph];
    _sentenceCache[page] = sentences;
    return sentences;
  }

  /// Where each sentence of [page] sits in the PDF's page text (for highlighting),
  /// or null if the text could not be aligned.
  Future<List<SentenceSpan>?> spansOf(int page) async {
    if (_spanCache.containsKey(page)) return _spanCache[page];
    final sentences = await sentencesOf(page);
    return _spanCache[page] = alignSentences(_rawCache[page]!, sentences);
  }

  /// How far (0..1) through the *spoken part* of the current sentence playback is
  /// (leading and trailing silence excluded). Uses the audio device's real position
  /// when it reports one, so the highlight follows the voice, pauses included.
  double get clipFraction {
    final span = (_speechEnd - _speechStart).inMicroseconds;
    if (span <= 0) return 0;
    final reported = output.position;
    final played = reported != null ? reported - _outputLatency : Duration(microseconds: _clip.elapsedMicroseconds);
    return ((played - _speechStart).inMicroseconds / span).clamp(0.0, 1.0);
  }

  /// Where speech starts and ends inside [audio] (TTS clips have silent edges).
  static (Duration, Duration) _speechBounds(TtsAudio audio) {
    final s = audio.samples;
    const threshold = 0.012;
    var first = 0;
    while (first < s.length && s[first].abs() < threshold) {
      first++;
    }
    var last = s.length - 1;
    while (last > first && s[last].abs() < threshold) {
      last--;
    }
    Duration at(int i) => Duration(microseconds: i * 1000000 ~/ audio.sampleRate);
    return first >= last ? (Duration.zero, audio.duration) : (at(first), at(last + 1));
  }

  /// Moves the idle cursor without playing (e.g. restoring saved progress).
  void setPosition(ReadingPosition position) {
    _position = position;
    _finished = false;
    if (!isActive) {
      _currentSentence = _sentenceCache[position.page]?.elementAtOrNull(position.sentence);
    }
    _notify();
  }

  /// Swaps the TTS engine (e.g. a different voice model). Restarts the current sentence.
  set engine(TtsEngine? engine) {
    if (identical(engine, _engine)) return;
    _engine = engine;
    _voiceChanged();
  }

  /// Changes speaker / speed; anything already synthesized is discarded.
  void setVoice({int? speakerId, double? speed}) {
    final changed = (speakerId != null && speakerId != _speakerId) || (speed != null && speed != _speed);
    _speakerId = speakerId ?? _speakerId;
    _speed = speed ?? _speed;
    if (changed) _voiceChanged();
  }

  void _voiceChanged() {
    _synthCache.clear();
    if (isActive) {
      final wasPaused = _status == ReaderStatus.paused;
      _start(_position, paused: wasPaused);
    }
    _notify();
  }

  /// Starts reading from [from] (default: the current position).
  Future<void> play([ReadingPosition? from]) async {
    if (_engine == null) {
      _error = 'No voice is loaded yet. Download a voice first.';
      _notify();
      return;
    }
    await _start(from ?? _position);
  }

  Future<void> pause() async {
    if (_status != ReaderStatus.playing && _status != ReaderStatus.preparing) return;
    _resumeGate ??= Completer<void>();
    if (_clipPlaying) {
      _clip.stop();
      await output.pause();
    }
    _status = ReaderStatus.paused;
    _notify();
    if (_engine != null) unawaited(_bufferWhilePaused(_generation));
  }

  Future<void> resume() async {
    if (_status != ReaderStatus.paused) return;
    final gate = _resumeGate;
    _resumeGate = null;
    if (_clipPlaying) {
      _status = ReaderStatus.playing;
      _clip.start();
      await output.resume();
    } else {
      _status = ReaderStatus.preparing;
    }
    gate?.complete();
    _notify();
  }

  Future<void> togglePlayPause([ReadingPosition? startAt]) async {
    switch (_status) {
      case ReaderStatus.playing:
      case ReaderStatus.preparing:
        await pause();
      case ReaderStatus.paused:
        await resume();
      case ReaderStatus.idle:
        await play(startAt);
    }
  }

  Future<void> stop() async {
    _generation++;
    _engine?.cancelPending();
    _releaseGate();
    _status = ReaderStatus.idle;
    _notify();
    await output.stop();
  }

  /// Jumps [delta] sentences forward (positive) or backward (negative).
  Future<void> skip(int delta) async {
    var target = _position;
    for (var i = 0; i < delta.abs(); i++) {
      final next = delta > 0 ? await _next(target) : await _previous(target);
      if (next == null) break;
      target = next;
    }
    if (isActive) {
      await _start(target, paused: _status == ReaderStatus.paused);
    } else {
      setPosition(target);
      _currentSentence = (await sentencesOf(target.page)).elementAtOrNull(target.sentence);
      _notify();
    }
  }

  /// Starts reading at the beginning of [page] (or moves there if idle).
  Future<void> jumpToPage(int page, {bool play = true}) async {
    final target = ReadingPosition(page.clamp(1, document.pageCount));
    if (play && _engine != null) {
      await _start(target);
    } else {
      setPosition(target);
    }
  }

  Future<void> _start(ReadingPosition from, {bool paused = false}) async {
    final gen = ++_generation;
    _engine?.cancelPending();
    _synthCache.removeWhere((_, s) => s.result == null);
    _releaseGate();
    if (paused) _resumeGate = Completer<void>();
    _error = null;
    _finished = false;
    _status = paused ? ReaderStatus.paused : ReaderStatus.preparing;
    _notify();
    await output.stop();
    if (gen != _generation) return;
    unawaited(_run(gen, from));
  }

  void _releaseGate() {
    final gate = _resumeGate;
    _resumeGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _run(int gen, ReadingPosition from) async {
    try {
      var pos = await _normalize(from);
      if (pos == null) {
        if (gen == _generation) {
          final anyText = await _normalize(const ReadingPosition(1)) != null;
          _error = anyText ? null : 'This PDF has no readable text (it may be scanned images).';
          _finished = anyText;
          _status = ReaderStatus.idle;
          _notify();
        }
        return;
      }
      while (pos != null && gen == _generation) {
        final current = pos;
        final text = (await sentencesOf(current.page))[current.sentence];
        final upcoming = await _prefetch(current);
        if (gen != _generation) return;

        final synthesis = _synthCache[current]!;
        if (synthesis.result == null && _status != ReaderStatus.paused) {
          _status = ReaderStatus.preparing;
          _notify();
        }
        final audio = await synthesis.future;
        if (gen != _generation) return;
        _synthCache.remove(current);

        _clip
          ..stop()
          ..reset();
        final bounds = _speechBounds(audio);
        _speechStart = bounds.$1;
        _speechEnd = bounds.$2;
        _position = current;
        _currentSentence = text;
        onPositionChanged?.call(current);

        final gate = _resumeGate;
        if (gate != null) {
          _notify();
          await gate.future;
          if (gen != _generation) return;
        }
        _status = ReaderStatus.playing;
        _notify();

        final next = upcoming.isEmpty ? null : upcoming.first;
        final gap = _gapAfter(current, next);
        _clipPlaying = true;
        _clip.start();
        try {
          await output.play(_withTrailingSilence(audio, gap));
        } finally {
          _clipPlaying = false;
          _clip.stop();
        }
        if (gen != _generation) return;
        pos = next;
      }
      if (gen == _generation) {
        _finished = true;
        _status = ReaderStatus.idle;
        _notify();
      }
    } catch (e) {
      if (gen != _generation) return;
      _error = 'Reading stopped: $e';
      _status = ReaderStatus.idle;
      _notify();
    }
  }

  /// How long to pause after [current]: longer after paragraphs and headings, so the
  /// structure of the text is audible.
  Duration _gapAfter(ReadingPosition current, ReadingPosition? next) {
    if (next == null || next.page != current.page) return pagePause;
    if (_paragraphEnds[current.page]?[current.sentence] != true) return sentencePause;
    final text = _sentenceCache[current.page]![current.sentence];
    final isHeading = !RegExp(r'[.!?:"”’)\]]\s*$').hasMatch(text);
    return isHeading ? headingPause : paragraphPause;
  }

  /// Ensures synthesis is queued for [current], the rest of its page, and the first
  /// [lookahead] sentences of the next page. Returns the upcoming positions (not
  /// including [current]) that were queued.
  ///
  /// The whole page is synthesized in the background while it is being read (and while
  /// paused), so a slow voice builds up a buffer instead of stalling between sentences.
  Future<List<ReadingPosition>> _prefetch(ReadingPosition current) async {
    final upcoming = <ReadingPosition>[];
    _queueSynthesis(current);
    var p = current;
    var onNextPage = 0;
    while (true) {
      final n = await _next(p);
      if (n == null) break;
      if (n.page != current.page && ++onNextPage > lookahead) break;
      upcoming.add(n);
      _queueSynthesis(n);
      p = n;
    }
    return upcoming;
  }

  /// While paused, keeps synthesizing so the whole next page is ready in memory too.
  Future<void> _bufferWhilePaused(int gen) async {
    var p = _position;
    final lastPage = p.page + 1;
    while (gen == _generation && _status == ReaderStatus.paused) {
      final n = await _next(p);
      if (n == null || n.page > lastPage) return;
      if (gen != _generation || _status != ReaderStatus.paused) return;
      _queueSynthesis(n);
      p = n;
    }
  }

  void _queueSynthesis(ReadingPosition pos) {
    if (_synthCache.containsKey(pos)) return;
    final text = _sentenceCache[pos.page]![pos.sentence];
    final future = _engine!.synthesize(speechText(text), speakerId: _speakerId, speed: _speed);
    future.ignore(); // errors surface when the sentence is awaited
    _synthCache[pos] = _Synthesis(future);
  }

  /// The first readable position at or after [p].
  Future<ReadingPosition?> _normalize(ReadingPosition p) async {
    for (var page = p.page.clamp(1, document.pageCount); page <= document.pageCount; page++) {
      final count = (await sentencesOf(page)).length;
      final sentence = page == p.page ? p.sentence : 0;
      if (sentence < count) return ReadingPosition(page, sentence < 0 ? 0 : sentence);
    }
    return null;
  }

  Future<ReadingPosition?> _next(ReadingPosition p) => _normalize(ReadingPosition(p.page, p.sentence + 1));

  Future<ReadingPosition?> _previous(ReadingPosition p) async {
    if (p.sentence > 0) return ReadingPosition(p.page, p.sentence - 1);
    for (var page = p.page - 1; page >= 1; page--) {
      final count = (await sentencesOf(page)).length;
      if (count > 0) return ReadingPosition(page, count - 1);
    }
    return null;
  }

  TtsAudio _withTrailingSilence(TtsAudio audio, Duration gap) {
    final extra = audio.sampleRate * gap.inMilliseconds ~/ 1000;
    if (extra <= 0) return audio;
    final samples = Float32List(audio.samples.length + extra)..setAll(0, audio.samples);
    return TtsAudio(samples, audio.sampleRate);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _engine?.cancelPending();
    _releaseGate();
    super.dispose();
  }
}
