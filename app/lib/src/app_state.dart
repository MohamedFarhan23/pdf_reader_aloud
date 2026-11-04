import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/interfaces.dart';
import 'core/read_aloud_controller.dart';
import 'library/stores.dart';
import 'tts/model_manager.dart';
import 'tts/sherpa_engine.dart';
import 'tts/voice_catalog.dart';

/// Things that differ between phones and desktops.
bool get isMobile => Platform.isAndroid || Platform.isIOS;

/// App-wide state: settings, the document library, voice models and the
/// currently loaded TTS engine.
class AppState extends ChangeNotifier {
  AppState._(this._settingsStore, this._libraryStore, this.models, this.libraryDir)
      : _settings = _settingsStore.load(),
        _library = _libraryStore.load() {
    models.addListener(notifyListeners);
  }

  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    // On phones, picked files live in a temporary cache, so we keep our own copy.
    // (Desktop never needs the documents folder, which may not exist on Linux.)
    final base = isMobile ? (await getApplicationDocumentsDirectory()).path : support.path;
    final libraryDir = p.join(base, 'pdf_library');
    return AppState._(
      SettingsStore(prefs),
      LibraryStore(prefs),
      ModelManager(p.join(support.path, 'voices')),
      libraryDir,
    );
  }

  final SettingsStore _settingsStore;
  final LibraryStore _libraryStore;
  final ModelManager models;
  final String libraryDir;

  Settings _settings;
  List<LibraryEntry> _library;

  TtsEngine? _engine;
  String? _engineKey;
  Future<TtsEngine?>? _engineLoading;
  String? _engineError;

  Settings get settings => _settings;
  List<LibraryEntry> get library => List.unmodifiable(_library);
  VoiceModel get voiceModel => voiceModelById(_settings.modelId);
  Speaker get speaker => voiceModel.speaker(_settings.speakerId);
  TtsEngine? get engine => _engine;
  bool get engineLoading => _engineLoading != null;
  String? get engineError => _engineError;
  bool get hasAnyVoice => models.installed.isNotEmpty;

  // ---- Voice ---------------------------------------------------------------

  String _keyFor(VoiceModel m, Speaker s) => '${m.id}/${s.british ? 'gb' : 'us'}';

  /// Returns the engine for the selected voice, loading it if needed.
  /// Returns null if the selected voice model isn't downloaded.
  Future<TtsEngine?> ensureEngine() {
    final model = voiceModel;
    final key = _keyFor(model, speaker);
    if (_engine != null && _engineKey == key) return Future.value(_engine);
    if (!models.isInstalled(model)) return Future.value(null);
    return _engineLoading ??= _loadEngine(model, key);
  }

  Future<TtsEngine?> _loadEngine(VoiceModel model, String key) async {
    _engineError = null;
    notifyListeners();
    try {
      final engine = await SherpaTtsEngine.load(
        SherpaModelConfig.forModel(model, models.modelDir(model), british: speaker.british),
      );
      final old = _engine;
      _engine = engine;
      _engineKey = key;
      unawaited(old?.dispose());
      return engine;
    } catch (e) {
      _engineError = e.toString();
      return null;
    } finally {
      _engineLoading = null;
      notifyListeners();
      // The selection may have changed while we were loading.
      if (_engineKey != _keyFor(voiceModel, speaker) && models.isInstalled(voiceModel)) {
        unawaited(ensureEngine());
      }
    }
  }

  Future<void> updateSettings(Settings next) async {
    final previousKey = _keyFor(voiceModel, speaker);
    _settings = next;
    // Keep the speaker valid for the chosen model.
    if (!voiceModel.speakers.any((s) => s.id == next.speakerId)) {
      _settings = next.copyWith(speakerId: voiceModel.speakers.first.id);
    }
    await _settingsStore.save(_settings);
    notifyListeners();
    if (_engine != null && previousKey != _keyFor(voiceModel, speaker)) {
      unawaited(ensureEngine());
    }
  }

  /// After a download, select the model if the current choice isn't usable.
  void onModelInstalled(VoiceModel model) {
    if (!models.isInstalled(voiceModel)) {
      final defaultSpeaker = model.family == VoiceFamily.kokoro ? 3 /* Heart */ : model.speakers.first.id;
      updateSettings(_settings.copyWith(modelId: model.id, speakerId: defaultSpeaker));
    }
  }

  // ---- Library -------------------------------------------------------------

  /// Adds (or re-opens) a PDF and returns its library entry.
  Future<LibraryEntry> openDocument(String path, {String? name}) async {
    var stablePath = path;
    final title = p.basenameWithoutExtension(name ?? path);
    if (isMobile && !p.isWithin(libraryDir, path)) {
      await Directory(libraryDir).create(recursive: true);
      final source = File(path);
      var target = File(p.join(libraryDir, name ?? p.basename(path)));
      if (target.existsSync() && target.lengthSync() != source.lengthSync()) {
        target = File(p.join(libraryDir, '${DateTime.now().millisecondsSinceEpoch}_${p.basename(target.path)}'));
      }
      if (!target.existsSync()) await source.copy(target.path);
      stablePath = target.path;
    }
    final existing = _library.where((e) => e.path == stablePath).firstOrNull;
    final entry = (existing ?? LibraryEntry(path: stablePath, title: title)).copyWith(lastOpened: DateTime.now());
    _library = [entry, ..._library.where((e) => e.path != stablePath)];
    await _libraryStore.save(_library);
    notifyListeners();
    return entry;
  }

  LibraryEntry? entryFor(String path) => _library.where((e) => e.path == path).firstOrNull;

  Future<void> saveProgress(String path, {ReadingPosition? position, int? pageCount}) async {
    final i = _library.indexWhere((e) => e.path == path);
    if (i < 0) return;
    _library[i] = _library[i].copyWith(position: position, pageCount: pageCount);
    await _libraryStore.save(_library);
    notifyListeners();
  }

  Future<void> removeDocument(LibraryEntry entry) async {
    _library = _library.where((e) => e.path != entry.path).toList();
    await _libraryStore.save(_library);
    if (p.isWithin(libraryDir, entry.path)) {
      final f = File(entry.path);
      if (f.existsSync()) await f.delete();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    models.removeListener(notifyListeners);
    _engine?.dispose();
    super.dispose();
  }
}
