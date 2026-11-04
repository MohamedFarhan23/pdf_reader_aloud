import 'package:pdfrx/pdfrx.dart';

import '../core/interfaces.dart';

/// Page text from a PDF opened with pdfrx (PDFium), on every platform.
class PdfrxDocumentText implements DocumentText {
  PdfrxDocumentText._(this._document);

  final PdfDocument _document;

  static Future<PdfrxDocumentText> open(String path) async =>
      PdfrxDocumentText._(await PdfDocument.openFile(path));

  @override
  int get pageCount => _document.pages.length;

  @override
  Future<String> pageText(int pageNumber) async {
    final text = await _document.pages[pageNumber - 1].loadText();
    return text?.fullText ?? '';
  }

  Future<void> dispose() => _document.dispose();
}
