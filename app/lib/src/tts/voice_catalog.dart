/// The on-device voice models the app knows how to download and run.
library;

enum VoiceFamily { kokoro, piper }

class Speaker {
  const Speaker(this.id, this.key, this.name, this.description, {this.british = false, this.recommended = false});

  /// Speaker index inside the model.
  final int id;
  final String key;
  final String name;
  final String description;
  final bool british;
  final bool recommended;
}

class VoiceModel {
  const VoiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.family,
    required this.archive,
    required this.downloadMb,
    required this.speakers,
    this.onnxFile,
  });

  final String id;
  final String name;
  final String description;
  final VoiceFamily family;

  /// Archive name in the sherpa-onnx `tts-models` GitHub release (without `.tar.bz2`).
  final String archive;
  final int downloadMb;
  final List<Speaker> speakers;

  /// Model file name inside the archive (Piper voices name it after the voice).
  final String? onnxFile;

  String get url =>
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$archive.tar.bz2';

  Speaker speaker(int id) => speakers.firstWhere((s) => s.id == id, orElse: () => speakers.first);
}

const _kokoroSpeakers = [
  Speaker(0, 'af_alloy', 'Alloy', 'US female'),
  Speaker(1, 'af_aoede', 'Aoede', 'US female'),
  Speaker(2, 'af_bella', 'Bella', 'US female, warm', recommended: true),
  Speaker(3, 'af_heart', 'Heart', 'US female, most natural', recommended: true),
  Speaker(4, 'af_jessica', 'Jessica', 'US female'),
  Speaker(5, 'af_kore', 'Kore', 'US female'),
  Speaker(6, 'af_nicole', 'Nicole', 'US female, soft', recommended: true),
  Speaker(7, 'af_nova', 'Nova', 'US female'),
  Speaker(8, 'af_river', 'River', 'US female'),
  Speaker(9, 'af_sarah', 'Sarah', 'US female'),
  Speaker(10, 'af_sky', 'Sky', 'US female'),
  Speaker(11, 'am_adam', 'Adam', 'US male'),
  Speaker(12, 'am_echo', 'Echo', 'US male'),
  Speaker(13, 'am_eric', 'Eric', 'US male'),
  Speaker(14, 'am_fenrir', 'Fenrir', 'US male', recommended: true),
  Speaker(15, 'am_liam', 'Liam', 'US male'),
  Speaker(16, 'am_michael', 'Michael', 'US male', recommended: true),
  Speaker(17, 'am_onyx', 'Onyx', 'US male, deep'),
  Speaker(18, 'am_puck', 'Puck', 'US male'),
  Speaker(19, 'am_santa', 'Santa', 'US male'),
  Speaker(20, 'bf_alice', 'Alice', 'UK female', british: true),
  Speaker(21, 'bf_emma', 'Emma', 'UK female', british: true, recommended: true),
  Speaker(22, 'bf_isabella', 'Isabella', 'UK female', british: true),
  Speaker(23, 'bf_lily', 'Lily', 'UK female', british: true),
  Speaker(24, 'bm_daniel', 'Daniel', 'UK male', british: true),
  Speaker(25, 'bm_fable', 'Fable', 'UK male', british: true),
  Speaker(26, 'bm_george', 'George', 'UK male', british: true, recommended: true),
  Speaker(27, 'bm_lewis', 'Lewis', 'UK male', british: true),
];

const kokoroModel = VoiceModel(
  id: 'kokoro-v1',
  name: 'Kokoro (natural)',
  description: 'Most natural-sounding. 28 English voices. Needs a reasonably fast phone.',
  family: VoiceFamily.kokoro,
  archive: 'kokoro-int8-multi-lang-v1_0',
  downloadMb: 132,
  speakers: _kokoroSpeakers,
);

const voiceCatalog = <VoiceModel>[
  kokoroModel,
  VoiceModel(
    id: 'piper-lessac',
    name: 'Piper Lessac (fast)',
    description: 'Lightweight US English voice. Runs smoothly on any phone.',
    family: VoiceFamily.piper,
    archive: 'vits-piper-en_US-lessac-medium',
    onnxFile: 'en_US-lessac-medium.onnx',
    downloadMb: 67,
    speakers: [Speaker(0, 'lessac', 'Lessac', 'US female')],
  ),
  VoiceModel(
    id: 'piper-alba',
    name: 'Piper Alba (fast)',
    description: 'Lightweight British English voice.',
    family: VoiceFamily.piper,
    archive: 'vits-piper-en_GB-alba-medium',
    onnxFile: 'en_GB-alba-medium.onnx',
    downloadMb: 67,
    speakers: [Speaker(0, 'alba', 'Alba', 'UK female', british: true)],
  ),
];

VoiceModel voiceModelById(String id) =>
    voiceCatalog.firstWhere((m) => m.id == id, orElse: () => kokoroModel);
