import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/read_aloud_controller.dart';

/// A document the user has opened, with where they stopped listening.
class LibraryEntry {
  LibraryEntry({
    required this.path,
    required this.title,
    this.pageCount = 0,
    this.position = const ReadingPosition(1),
    DateTime? lastOpened,
  }) : lastOpened = lastOpened ?? DateTime.now();

  final String path;
  final String title;
  final int pageCount;
  final ReadingPosition position;
  final DateTime lastOpened;

  LibraryEntry copyWith({int? pageCount, ReadingPosition? position, DateTime? lastOpened}) => LibraryEntry(
        path: path,
        title: title,
        pageCount: pageCount ?? this.pageCount,
        position: position ?? this.position,
        lastOpened: lastOpened ?? this.lastOpened,
      );

  Map<String, Object> toJson() => {
        'path': path,
        'title': title,
        'pageCount': pageCount,
        'page': position.page,
        'sentence': position.sentence,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory LibraryEntry.fromJson(Map<String, dynamic> j) => LibraryEntry(
        path: j['path'] as String,
        title: j['title'] as String,
        pageCount: j['pageCount'] as int? ?? 0,
        position: ReadingPosition(j['page'] as int? ?? 1, j['sentence'] as int? ?? 0),
        lastOpened: DateTime.tryParse(j['lastOpened'] as String? ?? ''),
      );
}

/// Persists the list of recently opened documents.
class LibraryStore {
  LibraryStore(this._prefs);

  static const _key = 'library.v1';
  final SharedPreferences _prefs;

  List<LibraryEntry> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(LibraryEntry.fromJson).toList()
        ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<LibraryEntry> entries) =>
      _prefs.setString(_key, jsonEncode(entries.map((e) => e.toJson()).toList()));
}

/// User preferences: which voice, which speaker, how fast.
class Settings {
  const Settings({this.modelId = 'kokoro-v1', this.speakerId = 3, this.speed = 1.0, this.followReading = true});

  final String modelId;
  final int speakerId;
  final double speed;

  /// Scroll the PDF view to the page being read.
  final bool followReading;

  Settings copyWith({String? modelId, int? speakerId, double? speed, bool? followReading}) => Settings(
        modelId: modelId ?? this.modelId,
        speakerId: speakerId ?? this.speakerId,
        speed: speed ?? this.speed,
        followReading: followReading ?? this.followReading,
      );
}

class SettingsStore {
  SettingsStore(this._prefs);
  final SharedPreferences _prefs;

  Settings load() => Settings(
        modelId: _prefs.getString('voice.model') ?? 'kokoro-v1',
        speakerId: _prefs.getInt('voice.speaker') ?? 3,
        speed: _prefs.getDouble('voice.speed') ?? 1.0,
        followReading: _prefs.getBool('view.follow') ?? true,
      );

  Future<void> save(Settings s) async {
    await _prefs.setString('voice.model', s.modelId);
    await _prefs.setInt('voice.speaker', s.speakerId);
    await _prefs.setDouble('voice.speed', s.speed);
    await _prefs.setBool('view.follow', s.followReading);
  }
}
