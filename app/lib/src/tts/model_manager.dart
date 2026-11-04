import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'voice_catalog.dart';

class DownloadProgress {
  const DownloadProgress(this.phase, [this.fraction]);
  final String phase; // 'Downloading', 'Unpacking'
  final double? fraction;
}

/// Downloads, unpacks and tracks voice models stored in [rootDir].
///
/// Each model lives in `<rootDir>/<archive>/`; a `.installed` marker is written
/// only after a complete download + unpack, so partial installs are never used.
class ModelManager extends ChangeNotifier {
  ModelManager(this.rootDir, {http.Client? client}) : _client = client ?? http.Client();

  final String rootDir;
  final http.Client _client;
  final Map<String, DownloadProgress> _progress = {};
  final Map<String, String> _errors = {};

  String modelDir(VoiceModel m) => p.join(rootDir, m.archive);

  bool isInstalled(VoiceModel m) => File(p.join(modelDir(m), '.installed')).existsSync();

  List<VoiceModel> get installed => voiceCatalog.where(isInstalled).toList();

  DownloadProgress? progressOf(VoiceModel m) => _progress[m.id];
  String? errorOf(VoiceModel m) => _errors[m.id];
  bool isBusy(VoiceModel m) => _progress.containsKey(m.id);

  Future<void> download(VoiceModel model) async {
    if (isBusy(model) || isInstalled(model)) return;
    _errors.remove(model.id);
    _set(model, const DownloadProgress('Downloading', 0));
    final tmpArchive = File(p.join(rootDir, '${model.archive}.tar.bz2.part'));
    try {
      await Directory(rootDir).create(recursive: true);
      final response = await _client.send(http.Request('GET', Uri.parse(model.url)));
      if (response.statusCode != 200) {
        throw HttpException('Download failed (HTTP ${response.statusCode})');
      }
      final total = response.contentLength ?? model.downloadMb * 1000 * 1000;
      var received = 0;
      var lastNotified = 0.0;
      final sink = tmpArchive.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          final fraction = (received / total).clamp(0.0, 1.0);
          if (fraction - lastNotified >= 0.01) {
            lastNotified = fraction;
            _set(model, DownloadProgress('Downloading', fraction));
          }
        }
      } finally {
        await sink.close();
      }

      _set(model, const DownloadProgress('Unpacking'));
      final archivePath = p.join(rootDir, '${model.archive}.tar.bz2');
      await tmpArchive.rename(archivePath);
      final target = modelDir(model);
      // Unpacking ~150 MB of bzip2 is CPU heavy: keep it off the UI thread.
      await _unpackInBackground(archivePath, rootDir, target);
      if (!Directory(target).existsSync()) {
        throw const FileSystemException('Archive did not contain the expected folder');
      }
      await File(p.join(target, '.installed')).writeAsString(DateTime.now().toIso8601String());
    } catch (e) {
      _errors[model.id] = _describe(e);
      for (final f in [tmpArchive, File(p.join(rootDir, '${model.archive}.tar.bz2'))]) {
        if (f.existsSync()) await f.delete();
      }
    } finally {
      _progress.remove(model.id);
      notifyListeners();
    }
  }

  Future<void> delete(VoiceModel model) async {
    final dir = Directory(modelDir(model));
    if (dir.existsSync()) await dir.delete(recursive: true);
    notifyListeners();
  }

  void _set(VoiceModel m, DownloadProgress progress) {
    _progress[m.id] = progress;
    notifyListeners();
  }
}

String _describe(Object e) {
  final text = e.toString().split('\n').first;
  if (e is SocketException || e is http.ClientException) return 'No connection. Check your internet and try again.';
  return text.length > 160 ? '${text.substring(0, 160)}…' : text;
}

/// Top-level so the isolate closure captures only these strings, never the manager
/// (whose listeners reference UI objects that can't be sent between isolates).
Future<void> _unpackInBackground(String archivePath, String root, String target) =>
    Isolate.run(() => _unpack(archivePath, root, target));

/// Unpacks a model archive into [root] and drops data English reading doesn't need.
Future<void> _unpack(String archivePath, String root, String target) async {
  await extractFileToDisk(archivePath, root);
  await File(archivePath).delete();
  for (final name in ['lexicon-zh.txt', 'date-zh.fst', 'number-zh.fst', 'phone-zh.fst']) {
    final f = File(p.join(target, name));
    if (f.existsSync()) f.deleteSync();
  }
  final dict = Directory(p.join(target, 'dict'));
  if (dict.existsSync()) dict.deleteSync(recursive: true);
}
