import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'folder_scanner.dart';

/// First-page thumbnails for the PDF library, rendered once and kept on disk.
///
/// Rendering is done one PDF at a time so scrolling a big library stays smooth.
class ThumbnailCache {
  ThumbnailCache(this.dir, {this.width = 320});

  final String dir;
  final int width;

  final Map<String, Future<File?>> _futures = {};
  Future<void> _queue = Future.value();

  /// The thumbnail file for [pdf], or null if the PDF can't be rendered.
  Future<File?> thumbnailFor(FoundPdf pdf) => _futures.putIfAbsent(pdf.path, () => _enqueue(pdf));

  Future<File?> _enqueue(FoundPdf pdf) {
    final result = _queue.then((_) => _load(pdf));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Stable file name for this exact version of the PDF.
  String _fileName(FoundPdf pdf) {
    var h = 0xcbf29ce484222325; // FNV-1a
    for (final unit in '${pdf.path}|${pdf.size}|${pdf.modified.millisecondsSinceEpoch}'.codeUnits) {
      h = ((h ^ unit) * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${h.toRadixString(16)}.png';
  }

  Future<File?> _load(FoundPdf pdf) async {
    final file = File(p.join(dir, _fileName(pdf)));
    if (file.existsSync()) return file;
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdf.path);
      if (doc.pages.isEmpty) return null;
      final page = doc.pages.first;
      final height = (width * page.height / page.width).round();
      final rendered = await page.render(fullWidth: width.toDouble(), fullHeight: height.toDouble());
      if (rendered == null) return null;
      final ui.Image image;
      try {
        image = await rendered.createImage();
      } finally {
        rendered.dispose();
      }
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return null;
      await Directory(dir).create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return file;
    } catch (_) {
      return null; // damaged or password-protected: show a placeholder
    } finally {
      await doc?.dispose();
    }
  }
}
