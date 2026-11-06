import 'dart:io';

import 'package:path/path.dart' as p;

/// A PDF found while scanning the user's folders.
class FoundPdf {
  const FoundPdf({required this.path, required this.size, required this.modified});

  final String path;
  final int size;
  final DateTime modified;

  String get title => p.basenameWithoutExtension(path);
  String get folder => p.basename(p.dirname(path));
}

/// Lets the caller stop a running scan.
class ScanControl {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// Folders that never hold documents but can hold millions of files.
const _skippedFolders = {
  'node_modules',
  'site-packages',
  '__pycache__',
  'venv',
  'build',
  'target',
  'dist',
  'snap',
  'proc',
  'sys',
  'dev',
  'Android',
  'flutter',
  'Steam',
  'steamapps',
};

/// Lists every PDF under [folders] (subfolders included; hidden and system-like
/// folders skipped). Unreadable folders are skipped silently.
///
/// [onProgress] gets the PDFs found so far and the number of folders looked at, every
/// few dozen items. Set [control] to cancel; what was found so far is still returned.
Future<List<FoundPdf>> scanForPdfs(
  List<String> folders, {
  int maxDepth = 8,
  int maxFiles = 5000,
  int maxFolders = 20000,
  ScanControl? control,
  void Function(List<FoundPdf> found, int foldersSeen)? onProgress,
}) async {
  final found = <String, FoundPdf>{};
  var foldersSeen = 0;

  bool stop() => (control?.cancelled ?? false) || found.length >= maxFiles || foldersSeen >= maxFolders;

  Future<void> walk(Directory dir, int depth) async {
    if (depth > maxDepth || stop()) return;
    foldersSeen++;
    if (foldersSeen % 20 == 0) {
      onProgress?.call(found.values.toList(), foldersSeen);
      await Future<void>.delayed(Duration.zero); // let the UI breathe
    }
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (stop()) return;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          if (!_skippedFolders.contains(name)) await walk(entity, depth + 1);
        } else if (entity is File && name.toLowerCase().endsWith('.pdf')) {
          try {
            final stat = await entity.stat();
            found[entity.path] = FoundPdf(path: entity.path, size: stat.size, modified: stat.modified);
          } on FileSystemException {
            // vanished or unreadable
          }
        }
      }
    } on FileSystemException {
      // no permission
    }
  }

  for (final folder in folders) {
    await walk(Directory(folder), 0);
  }
  final result = found.values.toList();
  onProgress?.call(result, foldersSeen);
  return result;
}
