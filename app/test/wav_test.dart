import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader_aloud/src/audio/soloud_output.dart';
import 'package:pdf_reader_aloud/src/core/interfaces.dart';

void main() {
  test('encodeWav writes a valid 16-bit mono header and clamps samples', () {
    final wav = encodeWav(TtsAudio(Float32List.fromList([0, 1, -1, 2]), 24000));
    final data = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 24000);
    expect(data.getUint32(40, Endian.little), 8);
    expect([for (var i = 0; i < 4; i++) data.getInt16(44 + i * 2, Endian.little)], [0, 32767, -32767, 32767]);
  });
}
