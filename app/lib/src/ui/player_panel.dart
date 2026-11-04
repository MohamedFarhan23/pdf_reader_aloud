import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/read_aloud_controller.dart';

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
    required this.onOpenVoices,
  });

  final AppState state;
  final ReadAloudController reader;
  final int? viewerPage;
  /// True while the reader itself is waiting for a voice (app-wide loading is read live).
  final bool loadingVoice;
  final VoidCallback onTogglePlay;
  final VoidCallback onOpenVoices;

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
                    child: Align(alignment: Alignment.centerLeft, child: _caption(theme, loadingVoice)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SpeedButton(
                        speed: state.settings.speed,
                        onChanged: (s) => state.updateSettings(state.settings.copyWith(speed: s)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Previous sentence (Alt+←)',
                        iconSize: 32,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () => reader.skip(-1),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(16),
                        ),
                        onPressed: loadingVoice ? null : onTogglePlay,
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 36,
                          semanticLabel: playing ? 'Pause' : 'Play',
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Next sentence (Alt+→)',
                        iconSize: 32,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () => reader.skip(1),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Voice: ${state.speaker.name}',
                        icon: const Icon(Icons.record_voice_over_outlined),
                        onPressed: onOpenVoices,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
        resume ? 'Press play to continue on page $page' : 'Press play to read from page $page',
        style: muted,
      );
    }
    if (sentence == null) return Text('Preparing speech…', style: muted);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Column(
        key: ValueKey(reader.position),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Page ${reader.position.page}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 2),
          Text(sentence, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
        ],
      ),
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
      itemBuilder: (_) => [
        for (final s in speedSteps) PopupMenuItem(value: s, child: Text('${_fmt(s)}×')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('${_fmt(speed)}×', style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }

  static String _fmt(double s) => s.toStringAsFixed(s * 100 % 10 == 0 ? 1 : 2);
}
