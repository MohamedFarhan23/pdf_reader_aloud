import 'package:pdfrx/pdfrx.dart';

import '../core/interfaces.dart';

/// Page text from a PDF opened with pdfrx (PDFium), on every platform.
class PdfrxDocumentText implements DocumentText {
  PdfrxDocumentText._(this._document);

  final PdfDocument _document;

  static Future<PdfrxDocumentText> open(String path) async => PdfrxDocumentText._(await PdfDocument.openFile(path));

  @override
  int get pageCount => _document.pages.length;

  final Map<int, PdfPageRawText?> _pageTexts = {};

  /// The page's text with per-character bounds (for highlighting). Cached.
  Future<PdfPageRawText?> pageTextWithBounds(int pageNumber) async {
    if (_pageTexts.containsKey(pageNumber)) return _pageTexts[pageNumber];
    return _pageTexts[pageNumber] = await _document.pages[pageNumber - 1].loadText();
  }

  @override
  Future<String> pageText(int pageNumber) async => (await pageTextWithBounds(pageNumber))?.fullText ?? '';

  Future<void> dispose() => _document.dispose();
}
