import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../app_state.dart';
import '../audio/soloud_output.dart';
import '../core/read_aloud_controller.dart';
import '../library/stores.dart';
import '../pdf/pdfrx_document_text.dart';
import 'player_panel.dart';
import 'voices_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.state, required this.entry});

  final AppState state;
  final LibraryEntry entry;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _viewer = PdfViewerController();
  final _output = SoloudAudioOutput();
  PdfrxDocumentText? _text;
  ReadAloudController? _reader;
  String? _openError;
  int? _viewerPage;
  int _pageCount = 0;
  bool _loadingVoice = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _viewerPage = widget.entry.position.page;
    state.addListener(_onAppStateChanged);
    _open();
  }

  Future<void> _open() async {
    try {
      final text = await PdfrxDocumentText.open(widget.entry.path);
      final reader = ReadAloudController(
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
      unawaited(state.saveProgress(widget.entry.path, pageCount: text.pageCount));
      // Load the voice while the user looks at the page, so "play" starts fast.
      unawaited(state.ensureEngine());
      unawaited(SoloudAudioOutput.ensureInitialized().catchError((Object _) {}));
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
    if (state.settings.followReading && _viewer.isReady && _viewer.pageNumber != pos.page) {
      unawaited(_viewer.goToPage(pageNumber: pos.page, anchor: PdfPageAnchor.top));
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

  Future<void> _togglePlay() async {
    final reader = _reader;
    if (reader == null) return;
    if (reader.status == ReaderStatus.idle && !reader.hasEngine) {
      setState(() => _loadingVoice = true);
      final engine = await state.ensureEngine();
      if (!mounted) return;
      setState(() => _loadingVoice = false);
      if (engine == null) {
        _promptForVoice();
        return;
      }
      reader.engine = engine;
    }
    await reader.togglePlayPause(reader.status == ReaderStatus.idle ? _startPosition() : null);
  }

  void _promptForVoice() {
    final message = state.engineError ?? 'Download a voice first to hear this document.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      action: SnackBarAction(label: 'Voices', onPressed: _openVoices),
    ));
  }

  void _openVoices() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VoicesScreen(state: state)));
  }

  @override
  void dispose() {
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
        const SingleActivator(LogicalKeyboardKey.space): _togglePlay,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${_viewerPage ?? 1} / $_pageCount'),
                  ),
                ),
              IconButton(
                tooltip: state.settings.followReading ? 'Following the reading' : 'Not following the reading',
                icon: Icon(state.settings.followReading ? Icons.my_location : Icons.location_disabled),
                onPressed: () => setState(() {
                  state.updateSettings(state.settings.copyWith(followReading: !state.settings.followReading));
                }),
              ),
            ],
          ),
          body: _openError != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_openError!)))
              : Column(
                  children: [
                    Expanded(
                      child: PdfViewer.file(
                        widget.entry.path,
                        controller: _viewer,
                        initialPageNumber: widget.entry.position.page,
                        params: PdfViewerParams(
                          margin: 8,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          onPageChanged: (page) => setState(() => _viewerPage = page),
                        ),
                      ),
                    ),
                    if (reader != null)
                      PlayerPanel(
                        state: state,
                        reader: reader,
                        viewerPage: _viewerPage,
                        loadingVoice: _loadingVoice,
                        onTogglePlay: _togglePlay,
                        onOpenVoices: _openVoices,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
