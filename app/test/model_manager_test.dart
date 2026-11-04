import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf_reader_aloud/src/tts/model_manager.dart';
import 'package:pdf_reader_aloud/src/tts/voice_catalog.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('models'));
  tearDown(() => tmp.deleteSync(recursive: true));

  List<int> fakeArchive(String folder) {
    final archive = Archive()
      ..add(ArchiveFile.string('$folder/model.int8.onnx', 'model'))
      ..add(ArchiveFile.string('$folder/lexicon-zh.txt', 'zh'))
      ..add(ArchiveFile.string('$folder/dict/jieba.dict.utf8', 'dict'));
    return BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(archive));
  }

  test('downloads, unpacks, trims and marks a model installed', () async {
    final client = MockClient((req) async {
      expect(req.url.toString(), kokoroModel.url);
      return http.Response.bytes(fakeArchive(kokoroModel.archive), 200);
    });
    final manager = ModelManager(tmp.path, client: client);
    final phases = <String>{};
    // Listeners in the real app hold UI objects that can't cross isolates.
    final unsendable = ReceivePort();
    addTearDown(unsendable.close);
    manager.addListener(() {
      unsendable.hashCode;
      final p = manager.progressOf(kokoroModel);
      if (p != null) phases.add(p.phase);
    });

    expect(manager.isInstalled(kokoroModel), isFalse);
    await manager.download(kokoroModel);

    expect(manager.errorOf(kokoroModel), isNull);
    expect(manager.isInstalled(kokoroModel), isTrue);
    expect(phases, containsAll(['Downloading', 'Unpacking']));
    final dir = manager.modelDir(kokoroModel);
    expect(File('$dir/model.int8.onnx').readAsStringSync(), 'model');
    expect(File('$dir/lexicon-zh.txt').existsSync(), isFalse);
    expect(Directory('$dir/dict').existsSync(), isFalse);
    expect(tmp.listSync().whereType<File>(), isEmpty, reason: 'archive cleaned up');

    await manager.delete(kokoroModel);
    expect(manager.isInstalled(kokoroModel), isFalse);
  });

  test('a failed download leaves nothing installed', () async {
    final manager = ModelManager(tmp.path, client: MockClient((_) async => http.Response('nope', 404)));
    await manager.download(kokoroModel);
    expect(manager.isInstalled(kokoroModel), isFalse);
    expect(manager.errorOf(kokoroModel), contains('404'));
    expect(manager.isBusy(kokoroModel), isFalse);
  });
}
