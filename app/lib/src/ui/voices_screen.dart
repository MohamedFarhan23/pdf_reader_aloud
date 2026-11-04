import 'package:flutter/material.dart';

import '../app_state.dart';
import '../audio/soloud_output.dart';
import '../tts/sherpa_engine.dart';
import '../tts/voice_catalog.dart';
import 'player_panel.dart' show speedSteps;

/// Download voice models, pick a speaker and speed, and test the voice.
class VoicesScreen extends StatefulWidget {
  const VoicesScreen({super.key, required this.state});

  final AppState state;

  @override
  State<VoicesScreen> createState() => _VoicesScreenState();
}

class _VoicesScreenState extends State<VoicesScreen> {
  final _preview = SoloudAudioOutput();
  bool _testing = false;
  SpeedTestResult? _result;
  String? _testError;

  AppState get state => widget.state;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
      _testError = null;
    });
    try {
      final engine = await state.ensureEngine();
      if (engine == null) throw Exception(state.engineError ?? 'Download this voice first.');
      final result = await runSpeedTest(engine, speakerId: state.settings.speakerId, speed: state.settings.speed);
      if (!mounted) return;
      setState(() => _result = result);
      await _preview.play(result.audio);
    } catch (e) {
      if (mounted) setState(() => _testError = '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final theme = Theme.of(context);
        final selected = state.voiceModel;
        final installed = state.models.isInstalled(selected);
        return Scaffold(
          appBar: AppBar(title: const Text('Voices')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Voice models', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text('Models run on this device. Download once, then read offline.',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (final model in voiceCatalog) _ModelCard(state: state, model: model),
                  const SizedBox(height: 24),
                  Text('Speed · ${state.settings.speed.toStringAsFixed(2)}×', style: theme.textTheme.titleSmall),
                  Slider(
                    value: state.settings.speed,
                    min: speedSteps.first,
                    max: speedSteps.last,
                    divisions: ((speedSteps.last - speedSteps.first) / 0.05).round(),
                    label: '${state.settings.speed.toStringAsFixed(2)}×',
                    onChanged: (v) => state.updateSettings(state.settings.copyWith(speed: (v * 20).round() / 20)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Speaker · ${selected.name}', style: theme.textTheme.titleSmall),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: !installed || _testing ? null : _test,
                        // No spinner here: animating would steal CPU from the speed test itself.
                        icon: Icon(_testing ? Icons.hourglass_top : Icons.speed),
                        label: Text(_testing ? 'Testing…' : 'Test voice & speed'),
                      ),
                    ],
                  ),
                  if (_result != null) _SpeedVerdict(result: _result!),
                  if (_testError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_testError!, style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  const SizedBox(height: 8),
                  _SpeakerList(state: state, model: selected),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.state, required this.model});

  final AppState state;
  final VoiceModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = state.models.isInstalled(model);
    final progress = state.models.progressOf(model);
    final error = state.models.errorOf(model);
    final selected = state.settings.modelId == model.id;

    Widget trailing;
    if (progress != null) {
      trailing = SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(value: progress.fraction, strokeWidth: 3),
      );
    } else if (installed) {
      trailing = PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (_) => state.models.delete(model),
        itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete download'))],
      );
    } else {
      trailing = IconButton.filledTonal(
        tooltip: 'Download (${model.downloadMb} MB)',
        icon: const Icon(Icons.download),
        onPressed: () async {
          await state.models.download(model);
          if (state.models.isInstalled(model)) state.onModelInstalled(model);
        },
      );
    }

    return Card.outlined(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        enabled: installed,
        onTap: installed
            ? () => state.updateSettings(state.settings.copyWith(
                  modelId: model.id,
                  speakerId: model.family == VoiceFamily.kokoro ? 3 : model.speakers.first.id,
                ))
            : null,
        leading: Icon(selected && installed ? Icons.radio_button_checked : Icons.radio_button_unchecked),
        title: Text(model.name),
        subtitle: Text([
          model.description,
          if (progress != null)
            progress.fraction == null
                ? '${progress.phase}…'
                : '${progress.phase} ${(progress.fraction! * 100).round()}%'
          else if (!installed)
            '${model.downloadMb} MB download',
          if (error != null) 'Failed: $error',
        ].join('\n')),
        isThreeLine: true,
        trailing: trailing,
      ),
    );
  }
}

class _SpeakerList extends StatelessWidget {
  const _SpeakerList({required this.state, required this.model});

  final AppState state;
  final VoiceModel model;

  @override
  Widget build(BuildContext context) {
    final speakers = [...model.speakers]..sort((a, b) {
        if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
        return a.id.compareTo(b.id);
      });
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in speakers)
          ChoiceChip(
            avatar: s.recommended ? const Icon(Icons.star_rounded, size: 18) : null,
            label: Text('${s.name} · ${s.description}'),
            selected: state.settings.speakerId == s.id,
            onSelected: (_) => state.updateSettings(state.settings.copyWith(speakerId: s.id)),
          ),
      ],
    );
  }
}

class _SpeedVerdict extends StatelessWidget {
  const _SpeedVerdict({required this.result});

  final SpeedTestResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rtf = result.realTimeFactor;
    final audio = result.audio.duration.inMilliseconds / 1000;
    final took = result.elapsed.inMilliseconds / 1000;
    final (icon, color, verdict) = switch (rtf) {
      >= 1.3 => (Icons.check_circle, Colors.green, 'Fast enough for smooth, continuous reading on this device.'),
      >= 1.0 => (Icons.check_circle_outline, Colors.orange,
          'Just keeps up. Reading should flow, with an occasional short pause.'),
      _ => (Icons.warning_amber_rounded, theme.colorScheme.error,
          'Slower than real time here: expect pauses between sentences. A Piper voice will be smooth.'),
    };
    return Card.filled(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text('${rtf.toStringAsFixed(2)}× real time'),
        subtitle: Text('Made ${audio.toStringAsFixed(1)} s of speech in ${took.toStringAsFixed(1)} s. $verdict'),
      ),
    );
  }
}
