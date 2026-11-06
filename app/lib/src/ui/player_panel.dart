import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../audio/soloud_output.dart';
import '../core/read_aloud_controller.dart';
import 'loading_bar.dart';
import 'motion.dart';

const speedSteps = [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0];

/// Bottom panel of the reader: the sentence being spoken plus transport controls.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.state,
    required this.reader,
    required this.viewerPage,
    required this.loadingVoice,
    required this.onTogglePlay,
    required this.onStop,
    required this.onOpenVoices,
    required this.followReading,
    required this.onToggleFollow,
  });

  final AppState state;
  final ReadAloudController reader;
  final int? viewerPage;

  /// True while the reader itself is waiting for a voice (app-wide loading is read live).
  final bool loadingVoice;
  final VoidCallback onTogglePlay;
  final VoidCallback onStop;
  final VoidCallback onOpenVoices;
  final bool followReading;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([reader, state]),
      builder: (context, _) {
        final status = reader.status;
        final loadingVoice = this.loadingVoice || (state.engineLoading && !reader.hasEngine);
        final busy = loadingVoice || status == ReaderStatus.preparing;
        final playing = status == ReaderStatus.playing || status == ReaderStatus.preparing;
        return Material(
          color: theme.colorScheme.surfaceContainer,
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A static bar, not an animated one: a 60 fps animation competes with
                // speech synthesis for CPU (and battery) exactly when we're behind.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 3,
                  color: busy ? theme.colorScheme.primary : Colors.transparent,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760, minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: loadingVoice && reader.error == null
                          ? LoadingBar(
                              key: ValueKey(state.voiceModel.id),
                              title: 'Getting ${state.voiceModel.name} ready',
                              stage: state.engineStage,
                              expected: Duration(seconds: state.voiceModel.loadSeconds),
                            )
                          : _caption(theme, loadingVoice),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _SpeedButton(
                        speed: state.settings.speed,
                        onChanged: (s) => state.updateSettings(state.settings.copyWith(speed: s)),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.record_voice_over_outlined, size: 18),
                        label: Text('Voice: ${state.speaker.name}'),
                        tooltip: 'Change the voice',
                        onPressed: onOpenVoices,
                      ),
                      FilterChip(
                        selected: followReading,
                        label: const Text('Auto-scroll'),
                        tooltip: followReading
                            ? 'The page scrolls to follow what is read. Tap to turn off.'
                            : 'Tap to make the page scroll along with the reading.',
                        onSelected: (_) => onToggleFollow(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final volume = _VolumeControl(state: state);
                      final transport = _transport(loadingVoice, playing);
                      // Wide: volume sits at the right of the transport buttons; narrow: below them.
                      if (constraints.maxWidth < 640) {
                        return Column(mainAxisSize: MainAxisSize.min, children: [transport, volume]);
                      }
                      return Row(
                        children: [
                          const Spacer(),
                          transport,
                          Expanded(
                            child: Align(alignment: Alignment.centerRight, child: volume),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _transport(bool loadingVoice, bool playing) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous sentence (Alt+←)',
          iconSize: 32,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: () => reader.skip(-1),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(16)),
          onPressed: loadingVoice ? null : onTogglePlay,
          child: PlayPauseIcon(playing: playing),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Stop reading',
          iconSize: 32,
          icon: const Icon(Icons.stop_rounded),
          onPressed: reader.isActive ? onStop : null,
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Next sentence (Alt+→)',
          iconSize: 32,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: () => reader.skip(1),
        ),
      ],
    );
  }

  Widget _caption(ThemeData theme, bool loadingVoice) {
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (reader.error != null) {
      return Text(reader.error!, style: muted?.copyWith(color: theme.colorScheme.error));
    }
    if (loadingVoice) return Text('Loading ${state.voiceModel.name} voice…', style: muted);
    final sentence = reader.currentSentence;
    if (reader.status == ReaderStatus.idle) {
      if (reader.finished) return Text('Finished reading.', style: muted);
      final page = viewerPage ?? reader.position.page;
      final resume = page == reader.position.page && reader.position.sentence > 0;
      return Text(
        resume
            ? 'Press play to continue on page $page, or tap any text to start there.'
            : 'Press play to read from page $page, or tap any text to start there.',
        style: muted,
      );
    }
    if (sentence == null) return Text('Preparing speech…', style: muted);
    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: smoothCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(reader.position),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Page ${reader.position.page}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 2),
                Text(sentence, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Copy this sentence',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: sentence));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Sentence copied'), duration: Duration(seconds: 1)));
            },
          ),
        ),
      ],
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.speed, required this.onChanged});

  final double speed;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Reading speed',
      initialValue: speed,
      onSelected: onChanged,
      itemBuilder: (_) => [for (final s in speedSteps) PopupMenuItem(value: s, child: Text('${_fmt(s)}×'))],
      child: Chip(avatar: const Icon(Icons.fast_forward_rounded, size: 18), label: Text('Speed ${_fmt(speed)}×')),
    );
  }

  static String _fmt(double s) => s.toStringAsFixed(s * 100 % 10 == 0 ? 1 : 2);
}

/// Volume slider with a mute button. The slider runs to 150% so quiet voices can be boosted.
class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.state});

  final AppState state;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  static const _max = 1.5;
  double? _dragging;
  double _beforeMute = 1.0;

  double get _volume => _dragging ?? widget.state.settings.volume;

  void _commit(double v) {
    _dragging = null;
    widget.state.updateSettings(widget.state.settings.copyWith(volume: v));
  }

  IconData get _icon {
    final v = _volume;
    if (v <= 0) return Icons.volume_off_rounded;
    if (v < 0.4) return Icons.volume_mute_rounded;
    if (v < 1.0) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final v = _volume;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: v <= 0 ? 'Unmute' : 'Mute',
          icon: Icon(_icon),
          onPressed: () {
            if (v > 0) {
              _beforeMute = v;
              _commit(0);
            } else {
              _commit(_beforeMute);
            }
          },
        ),
        SizedBox(
          width: 150,
          child: Slider(
            value: v.clamp(0.0, _max),
            max: _max,
            label: '${(v * 100).round()}%',
            onChanged: (x) {
              setState(() => _dragging = x);
              SoloudAudioOutput.setVolume(x); // instant; saved when the drag ends
            },
            onChangeEnd: (x) => setState(() => _commit(x)),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${(v * 100).round()}%', textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
