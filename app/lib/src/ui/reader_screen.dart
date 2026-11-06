import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../audio/soloud_output.dart';
import '../core/read_aloud_controller.dart';
import '../core/text_spans.dart';
import '../library/stores.dart';
import '../pdf/pdfrx_document_text.dart';
import 'motion.dart';
import 'page_skeleton.dart';
import 'player_panel.dart';
import 'voices_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.state, required this.entry});

  final AppState state;
  final LibraryEntry entry;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with SingleTickerProviderStateMixin {
  final _viewer = PdfViewerController();
  final _output = SoloudAudioOutput();
  PdfrxDocumentText? _text;
  ReadAloudController? _reader;
  String? _openError;
  int? _viewerPage;
  int _pageCount = 0;
  bool _loadingVoice = false;

  // What is being read, for the highlight overlay.
  Timer? _ticker;
  int _hlPage = 0;
  PdfPageRawText? _hlText;
  List<SentenceSpan>? _hlSpans;
  int _hlSentence = -1;
  int _hlWord = -1;
  List<PdfRect> _sentenceRects = const [];
  List<PdfRect> _wordRects = const []; // where the word highlight is heading

  // ---- smooth highlight motion -------------------------------------------------
  // The word highlight glides to each new word along a cubic Bézier ease-out, with its
  // trailing edge following a beat behind the leading edge (it stretches, then catches
  // up), and a new sentence fades in while the old one fades out.
  static const _wordCurve = smoothCurve;
  static const _glide = Duration(milliseconds: 190);
  static const _fade = Duration(milliseconds: 260);
  late final Ticker _animTicker = createTicker(_onAnimFrame);
  final Stopwatch _clock = Stopwatch()..start();
  List<PdfRect> _wordShown = const []; // what is painted right now
  PdfRect? _glideFrom;
  PdfRect? _glideTo;
  int _glideStartMs = 0;
  List<PdfRect> _prevSentenceRects = const [];
  int _prevSentencePage = -1;
  int _fadeStartMs = -1000000;
  double _fadeIn = 1; // 0..1 progress of the sentence cross-fade
  int _frame = 0;
  bool _skeletonGone = false; // removed from the tree once its fade-out has finished
  // Loading: after a click the sentence is highlighted at once, but the voice needs a moment to
  // prepare the audio. The yellow "fills" along the sentence like a progress bar until it plays.
  bool _loading = false;
  ReadingPosition? _loadTarget;
  int _loadStartMs = 0;
  int _loadFinishMs = 0;
  double _loadProgress = 1; // 1 = not loading
  double _loadFrom = 1;
  bool _overPage = false; // pointer is over a PDF page, where a click starts reading
  bool _viewerShown = false; // the real page is on screen, so the loading skeleton can fade away

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _viewerPage = widget.entry.position.page;
    state.addListener(_onAppStateChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
    _open();
  }

  Future<void> _open() async {
    try {
      final text = await PdfrxDocumentText.open(widget.entry.path);
      final reader =
          ReadAloudController(
              document: text,
              output: _output,
              engine: state.engine,
              onPositionChanged: _onReadingPositionChanged,
            )
            ..setVoice(speakerId: state.settings.speakerId, speed: state.settings.speed)
            ..setPosition(widget.entry.position);
      if (!mounted) {
        await text.dispose();
        return;
      }
      setState(() {
        _text = text;
        _reader = reader;
        _pageCount = text.pageCount;
      });
      reader.addListener(_onReaderChanged);
      unawaited(state.saveProgress(widget.entry.path, pageCount: text.pageCount));
      // Load the voice while the user looks at the page, so "play" starts fast.
      unawaited(state.ensureEngine());
      unawaited(SoloudAudioOutput.ensureInitialized().catchError((Object _) {}));
      _ticker = Timer.periodic(const Duration(milliseconds: 40), (_) => _tickWord());
    } catch (e) {
      if (mounted) setState(() => _openError = 'Could not open this PDF: $e');
    }
  }

  void _onAppStateChanged() {
    final reader = _reader;
    if (reader == null) return;
    reader.setVoice(speakerId: state.settings.speakerId, speed: state.settings.speed);
    if (state.engine != null) reader.engine = state.engine;
  }

  void _onReadingPositionChanged(ReadingPosition pos) {
    unawaited(state.saveProgress(widget.entry.path, position: pos));
    unawaited(_followAndHighlight(pos));
  }

  Future<void> _followAndHighlight(ReadingPosition pos, {bool immediate = false}) async {
    final reader = _reader;
    final text = _text;
    if (reader == null || text == null) return;
    final spans = await reader.spansOf(pos.page);
    final pageText = await text.pageTextWithBounds(pos.page);
    if (!mounted || (!immediate && reader.position != pos)) return; // moved on while loading
    _prevSentenceRects = _sentenceRects;
    _prevSentencePage = _hlPage;
    _hlPage = pos.page;
    _hlText = pageText;
    _hlSpans = spans;
    _hlSentence = pos.sentence;
    _hlWord = -1;
    final span = spans != null && pos.sentence < spans.length ? spans[pos.sentence] : null;
    _sentenceRects = span == null || pageText == null ? const [] : _lineRects(pageText, span.start, span.end);
    _wordRects = const [];
    _wordShown = const [];
    _glideFrom = _glideTo = null;
    _fadeStartMs = _clock.elapsedMilliseconds;
    _fadeIn = immediate ? 1 : 0; // a clicked sentence is there at once (then fills as it loads)
    if (immediate && _sentenceRects.isNotEmpty) {
      _loading = true;
      _loadTarget = pos;
      _loadStartMs = _fadeStartMs;
      _loadProgress = 0;
    }
    _startAnimation();
    if (!state.settings.followReading || !_viewer.isReady) return;
    if (_viewer.pageNumber != pos.page) {
      await _viewer.goToPage(pageNumber: pos.page, anchor: PdfPageAnchor.top);
    }
    if (_sentenceRects.isEmpty || !mounted || (!immediate && reader.position != pos)) return;
    await _viewer.ensureVisible(
      _viewer.calcRectForRectInsidePage(pageNumber: pos.page, rect: _sentenceRects.boundingRect()),
      margin: 48,
    );
  }

  /// Moves the word highlight along as the sentence's audio plays.
  void _tickWord() {
    final reader = _reader;
    final spans = _hlSpans;
    final text = _hlText;
    if (reader == null || spans == null || text == null || reader.status != ReaderStatus.playing) return;
    if (_hlSentence < 0 || _hlSentence >= spans.length || reader.position.page != _hlPage) return;
    final span = spans[_hlSentence];
    final word = span.wordIndexAt(reader.clipFraction);
    if (word == _hlWord) return;
    _hlWord = word;
    _wordRects = word < 0 ? const [] : _lineRects(text, span.words[word].start, span.words[word].end);
    _glideToWord();
  }

  /// Starts gliding the word highlight from where it is now to [_wordRects].
  void _glideToWord() {
    final target = _wordRects;
    if (target.length == 1 && _wordShown.length == 1) {
      _glideFrom = _wordShown.first; // continue from the current (maybe mid-glide) position
      _glideTo = target.first;
      _glideStartMs = _clock.elapsedMilliseconds;
    } else {
      _glideFrom = _glideTo = null; // first word, or a word wrapping over lines: no glide
      _wordShown = target;
    }
    _startAnimation();
  }

  void _startAnimation() {
    if (!mounted) return;
    if (!_animTicker.isActive) _animTicker.start();
    _repaintHighlight();
  }

  static PdfRect _lerpRect(PdfRect a, PdfRect b, double right, double left) {
    double mix(double x, double y, double t) => x + (y - x) * t;
    return PdfRect(
      mix(a.left, b.left, left),
      mix(a.top, b.top, right),
      mix(a.right, b.right, right),
      mix(a.bottom, b.bottom, right),
    );
  }

  void _onAnimFrame(Duration _) {
    final now = _clock.elapsedMilliseconds;
    var busy = false;

    final fadeT = ((now - _fadeStartMs) / _fade.inMilliseconds).clamp(0.0, 1.0);
    _fadeIn = Curves.easeOutCubic.transform(fadeT);
    if (fadeT < 1) busy = true;

    if (_loading) {
      final t = (now - _loadStartMs) / 1000.0;
      _loadProgress = 0.92 * (1 - math.exp(-t / 1.1)); // eases toward 92%, never quite done until it plays
      busy = true;
    } else if (_loadProgress < 1) {
      final f = ((now - _loadFinishMs) / 280).clamp(0.0, 1.0);
      _loadProgress = _loadFrom + (1 - _loadFrom) * smoothCurve.transform(f);
      if (f < 1) {
        busy = true;
      } else {
        _loadProgress = 1;
      }
    }

    final from = _glideFrom, to = _glideTo;
    if (from != null && to != null) {
      final t = ((now - _glideStartMs) / _glide.inMilliseconds).clamp(0.0, 1.0);
      final height = (to.top - to.bottom).abs();
      final sameLine = (from.top - to.top).abs() < height * 0.5;
      final lead = _wordCurve.transform(t);
      // The trailing edge starts a little later, so the highlight stretches then catches up.
      final trail = sameLine ? _wordCurve.transform(((t - 0.18) / 0.82).clamp(0.0, 1.0)) : lead;
      _wordShown = [_lerpRect(from, to, lead, trail)];
      if (t < 1) {
        busy = true;
      } else {
        _glideFrom = _glideTo = null;
        _wordShown = [to];
      }
    }

    if (!busy) _animTicker.stop();
    // Phones: repaint every other frame, so the highlight never competes with speech synthesis.
    if (!isMobile || (_frame++).isEven || !busy) _repaintHighlight();
  }

  bool _wasActive = false;

  void _onReaderChanged() {
    final reader = _reader;
    if (_loading && reader != null) {
      final started = reader.status == ReaderStatus.playing && reader.position == _loadTarget;
      if (started || reader.status == ReaderStatus.idle || reader.status == ReaderStatus.paused) {
        _loading = false;
        _loadFrom = _loadProgress;
        _loadFinishMs = _clock.elapsedMilliseconds;
        _startAnimation(); // complete the fill, then the words take over
      }
    }
    final active = _reader?.isActive ?? false;
    if (active == _wasActive) return;
    _wasActive = active;
    _repaintHighlight(); // show or hide the highlight when reading starts or stops
  }

  void _repaintHighlight() {
    if (mounted && _viewer.isReady) _viewer.invalidate();
  }

  /// One rectangle per text line covering characters [start, end) of the page.
  static List<PdfRect> _lineRects(PdfPageRawText text, int start, int end) {
    final lines = <PdfRect>[];
    final limit = end < text.charRects.length ? end : text.charRects.length;
    for (var i = start; i < limit; i++) {
      final r = text.charRects[i];
      if (text.fullText[i].trim().isEmpty || r.right <= r.left || r.top <= r.bottom) continue;
      if (lines.isNotEmpty) {
        final last = lines.last;
        final overlap = (r.top < last.top ? r.top : last.top) - (r.bottom > last.bottom ? r.bottom : last.bottom);
        final smaller = (r.top - r.bottom) < (last.top - last.bottom) ? (r.top - r.bottom) : (last.top - last.bottom);
        if (overlap > smaller * 0.5) {
          lines[lines.length - 1] = PdfRect(
            last.left < r.left ? last.left : r.left,
            last.top > r.top ? last.top : r.top,
            last.right > r.right ? last.right : r.right,
            last.bottom < r.bottom ? last.bottom : r.bottom,
          );
          continue;
        }
      }
      lines.add(r);
    }
    return lines;
  }

  // Multiply blending tints the page like a highlighter pen: the background takes
  // the colour and black text stays black, so contrast is never lost.
  static const _sentenceColor = Color(0xFFFFF59D); // pale yellow
  static const _wordColor = Color(0xFF81D4FA); // sky blue; over the yellow it reads as mint green

  void _paintHighlight(Canvas canvas, Rect pageRect, PdfPage page) {
    final reader = _reader;
    if (reader == null || !reader.isActive) return;
    void draw(List<PdfRect> rects, Paint paint, double alpha) {
      if (alpha <= 0.01) return;
      paint.color = paint.color.withValues(alpha: alpha);
      for (final r in rects) {
        final box = r.toRectInDocument(page: page, pageRect: pageRect).inflate(1.5);
        canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), paint);
      }
    }

    if (page.pageNumber == _prevSentencePage) {
      draw(
        _prevSentenceRects,
        Paint()
          ..color = _sentenceColor
          ..blendMode = BlendMode.multiply,
        1 - _fadeIn,
      );
    }
    if (page.pageNumber != _hlPage) return;
    if (_loadProgress < 1) {
      _drawLoadingSentence(canvas, pageRect, page);
    } else {
      draw(
        _sentenceRects,
        Paint()
          ..color = _sentenceColor
          ..blendMode = BlendMode.multiply,
        _fadeIn,
      );
    }
    draw(
      _wordShown,
      Paint()
        ..color = _wordColor
        ..blendMode = BlendMode.multiply,
      1,
    );
  }

  /// The sentence while its audio is being prepared: faint and breathing, with the full
  /// yellow filling in from the start of the sentence along its lines like a progress bar.
  void _drawLoadingSentence(Canvas canvas, Rect pageRect, PdfPage page) {
    final boxes = [for (final r in _sentenceRects) r.toRectInDocument(page: page, pageRect: pageRect).inflate(1.5)];
    final total = boxes.fold<double>(0, (sum, b) => sum + b.width);
    if (total <= 0) return;
    final pulse = 0.5 + 0.5 * math.sin(_clock.elapsedMilliseconds / 230);
    final base = Paint()
      ..color = _sentenceColor.withValues(alpha: 0.30 + 0.14 * pulse)
      ..blendMode = BlendMode.multiply;
    final full = Paint()
      ..color = _sentenceColor
      ..blendMode = BlendMode.multiply;
    var remaining = _loadProgress * total;
    for (final box in boxes) {
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), base);
      final fill = remaining.clamp(0.0, box.width);
      remaining -= box.width;
      if (fill <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(box.left, box.top, fill, box.height), const Radius.circular(3)),
        full,
      );
      if (fill < box.width) {
        // Soft leading edge from a few solid strips of fading colour. (Not a gradient shader:
        // gradients under a multiply blend can bleed outside their rectangle.)
        const strips = 6;
        final stripW = math.min(18.0, box.width - fill) / strips;
        for (var i = 0; i < strips; i++) {
          final left = box.left + fill + i * stripW;
          if (left >= box.right) break;
          canvas.drawRect(
            Rect.fromLTRB(left, box.top, math.min(left + stripW + 0.5, box.right), box.bottom),
            Paint()
              ..color = _sentenceColor.withValues(alpha: 0.85 * (1 - i / strips))
              ..blendMode = BlendMode.multiply,
          );
        }
      }
    }
  }

  /// Where "play" should start: the saved sentence if the user is still looking
  /// at that page, otherwise the top of the page they scrolled to.
  ReadingPosition _startPosition() {
    final reader = _reader!;
    final viewing = _viewerPage;
    if (reader.finished) return ReadingPosition(viewing ?? 1);
    if (viewing == null || viewing == reader.position.page) return reader.position;
    return ReadingPosition(viewing);
  }

  /// Makes sure a voice is loaded; false (after telling the user) if there is none.
  Future<bool> _ensureVoice() async {
    final reader = _reader;
    if (reader == null) return false;
    if (reader.hasEngine) return true;
    setState(() => _loadingVoice = true);
    final engine = await state.ensureEngine();
    if (!mounted) return false;
    setState(() => _loadingVoice = false);
    if (engine == null) {
      _promptForVoice();
      return false;
    }
    reader.engine = engine;
    return true;
  }

  /// Space pauses / resumes wherever the focus is (a clicked button would otherwise
  /// swallow it), unless the user is typing in a text field or another screen is on top.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.space) return false;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    unawaited(_togglePlay());
    return true;
  }

  Future<void> _togglePlay() async {
    final reader = _reader;
    if (reader == null) return;
    if (reader.status == ReaderStatus.idle && !await _ensureVoice()) return;
    await reader.togglePlayPause(reader.status == ReaderStatus.idle ? _startPosition() : null);
  }

  Future<void> _stop() async {
    await _reader?.stop();
    _repaintHighlight();
  }

  /// The pointer moved over the viewer: show a hand over pages (a click there starts reading from
  /// that spot) instead of the text cursor, which would suggest selecting.
  void _onHover(PointerHoverEvent event) {
    var over = false;
    if (_viewer.isReady && _reader != null && _text != null) {
      final doc = _viewer.globalToDocument(event.position);
      over = doc != null && _viewer.getPdfPageHitTestResult(doc, useDocumentLayoutCoordinates: true) != null;
    }
    if (over != _overPage) setState(() => _overPage = over);
  }

  /// A link in the PDF was clicked: jump inside the document, or open the web address
  /// in the browser after a safety prompt (which can be switched off).
  Future<void> _onLinkTap(PdfLink link) async {
    final dest = link.dest;
    if (dest != null) {
      await _viewer.goToDest(dest);
      final reader = _reader;
      // If it was reading, carry on from where the link led, rather than being pulled back.
      if (reader != null && reader.isActive) unawaited(reader.jumpToPage(dest.pageNumber));
      return;
    }
    final url = link.url;
    if (url == null) return;
    if (!const {'http', 'https', 'mailto'}.contains(url.scheme.toLowerCase())) {
      _say('Blocked a link that is not a web or email address (${url.scheme}:).');
      return;
    }
    if (state.confirmExternalLinks) {
      final ok = await _confirmOpenLink(url);
      if (ok != true || !mounted) return;
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) _say('Could not open $url');
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirmOpenLink(Uri url) {
    var dontAsk = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          icon: const Icon(Icons.open_in_new),
          title: const Text('Open this link in your browser?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(url.toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Links in a PDF can lead anywhere. Only continue if you trust this address.'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: dontAsk,
                onChanged: (v) => setLocal(() => dontAsk = v ?? false),
                title: const Text("Don't ask me again"),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (dontAsk) unawaited(state.setConfirmExternalLinks(false));
                Navigator.pop(context, true);
              },
              child: const Text('Open in browser'),
            ),
          ],
        ),
      ),
    );
  }

  /// A tap on the page: start reading from the sentence nearest the tap.
  bool _onViewerTap(BuildContext context, PdfViewerController controller, PdfViewerGeneralTapHandlerDetails details) {
    if (details.type != PdfViewerGeneralTapType.tap || _reader == null || _text == null) return false;
    final hit = controller.getPdfPageHitTestResult(details.documentPosition, useDocumentLayoutCoordinates: true);
    if (hit == null) return false; // between pages
    unawaited(_startFromTap(hit.page.pageNumber, hit.offset));
    return true;
  }

  Future<void> _startFromTap(int page, PdfPoint point) async {
    final reader = _reader;
    final text = _text;
    if (reader == null || text == null) return;
    final spans = await reader.spansOf(page);
    final pageText = await text.pageTextWithBounds(page);
    var sentence = 0;
    if (spans != null && pageText != null && spans.isNotEmpty) {
      var best = double.infinity;
      for (var i = 0; i < spans.length; i++) {
        for (final r in _lineRects(pageText, spans[i].start, spans[i].end)) {
          final dx = point.x < r.left ? r.left - point.x : (point.x > r.right ? point.x - r.right : 0.0);
          final dy = point.y < r.bottom ? r.bottom - point.y : (point.y > r.top ? point.y - r.top : 0.0);
          // Lines are wide and short: weigh the vertical miss more, so a tap in the
          // margin picks the line beside it rather than one far above or below.
          final d = dx + dy * 3;
          if (d < best) {
            best = d;
            sentence = i;
          }
        }
      }
    }
    if (!mounted || !await _ensureVoice()) return;
    final target = ReadingPosition(page, sentence);
    unawaited(_followAndHighlight(target, immediate: true));
    await reader.play(target);
  }

  void _toggleFollow() => setState(() {
    state.updateSettings(state.settings.copyWith(followReading: !state.settings.followReading));
  });

  void _promptForVoice() {
    final message = state.engineError ?? 'Download a voice first to hear this document.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Voices', onPressed: _openVoices),
      ),
    );
  }

  void _openVoices() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VoicesScreen(state: state)));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _animTicker.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    state.removeListener(_onAppStateChanged);
    final reader = _reader;
    if (reader != null) {
      unawaited(state.saveProgress(widget.entry.path, position: reader.position));
      unawaited(reader.stop());
      reader.dispose();
    }
    unawaited(_output.dispose());
    unawaited(_text?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = _reader;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => reader?.skip(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => reader?.skip(-1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (_pageCount > 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text('Page ${_viewerPage ?? 1} of $_pageCount'),
                  ),
                ),
            ],
          ),
          body: _openError != null
              ? Center(
                  child: Padding(padding: const EdgeInsets.all(24), child: Text(_openError!)),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PdfViewer.file(
                            widget.entry.path,
                            controller: _viewer,
                            initialPageNumber: widget.entry.position.page,
                            params: PdfViewerParams(
                              margin: 8,
                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                              pagePaintCallbacks: [_paintHighlight],
                              linkHandlerParams: PdfLinkHandlerParams(
                                onLinkTap: _onLinkTap,
                                linkColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                                linkHoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.26),
                              ),
                              onGeneralTap: _onViewerTap,
                              // Space pauses/resumes reading (see _onKey); it must not also page-scroll the viewer.
                              onKey: (params, key, isRealKeyPress) => key == LogicalKeyboardKey.space ? true : null,
                              onPageChanged: (page) => setState(() => _viewerPage = page),
                              onViewerReady: (_, _) {
                                if (mounted) setState(() => _viewerShown = true);
                              },
                            ),
                          ),
                          // Invisible layer on top that only decides the mouse cursor (events pass through).
                          if (!isMobile)
                            MouseRegion(
                              hitTestBehavior: HitTestBehavior.translucent,
                              cursor: _overPage ? SystemMouseCursors.click : MouseCursor.defer,
                              onHover: _onHover,
                              onExit: (_) => _overPage ? setState(() => _overPage = false) : null,
                            ),
                          IgnorePointer(
                            ignoring: _viewerShown,
                            child: AnimatedOpacity(
                              opacity: _viewerShown ? 0 : 1,
                              duration: const Duration(milliseconds: 520),
                              curve: smoothCurve,
                              onEnd: () {
                                if (_viewerShown && mounted) setState(() => _skeletonGone = true);
                              },
                              child: _skeletonGone ? const SizedBox.shrink() : PageSkeleton(title: widget.entry.title),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Slides up and fades in once the text is ready, instead of popping in.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 480),
                      switchInCurve: smoothCurve,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      child: reader == null
                          ? const SizedBox(key: ValueKey('panel-wait'), width: double.infinity)
                          : PlayerPanel(
                              key: const ValueKey('panel'),
                              state: state,
                              reader: reader,
                              viewerPage: _viewerPage,
                              loadingVoice: _loadingVoice,
                              onTogglePlay: _togglePlay,
                              onStop: _stop,
                              onOpenVoices: _openVoices,
                              followReading: state.settings.followReading,
                              onToggleFollow: _toggleFollow,
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
