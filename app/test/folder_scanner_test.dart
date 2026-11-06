import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/library/folder_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  test('finds PDFs in subfolders, skips hidden folders and other files', () async {
    final dir = Directory.systemTemp.createTempSync('scan');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final f in ['a.pdf', 'sub/b.PDF', 'sub/c.txt', '.hidden/d.pdf']) {
      File(p.join(dir.path, f))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    final found = await scanForPdfs([dir.path]);
    expect(found.map((f) => f.title).toList()..sort(), ['a', 'b']);
    expect(found.first.size, 1);
  });

  test('a missing folder yields nothing', () async {
    expect(await scanForPdfs(['/no/such/folder']), isEmpty);
  });
}
