import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A progress bar for work that reports no real progress (loading a voice model).
///
/// It eases toward ~94% over [expected] and then waits with a gentle shimmer, so the
/// wait feels paced rather than frozen. The owner removes it when the work is done.
/// It animates only while visible, i.e. while the model loads on another isolate.
class LoadingBar extends StatefulWidget {
  const LoadingBar({
    super.key,
    required this.title,
    required this.expected,
    this.stage,
    this.hint = 'The first time takes longest.',
  });

  final String title;
  final String? stage;

  /// Reassurance shown after the stage name.
  final String hint;
  final Duration expected;

  @override
  State<LoadingBar> createState() => _LoadingBarState();
}

class _LoadingBarState extends State<LoadingBar> with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(hours: 1))..forward();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  double get _seconds => _clock.value * const Duration(hours: 1).inSeconds;

  double _progress() {
    final tau = math.max(1.0, widget.expected.inMilliseconds / 1000 / 2.5);
    return 0.94 * (1 - math.exp(-_seconds / tau));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedBuilder(
                animation: _clock,
                builder: (_, _) => Text(
                  '${(_progress() * 100).round()}%',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RepaintBoundary(
            child: SizedBox(
              height: 8,
              child: AnimatedBuilder(
                animation: _clock,
                builder: (_, _) => CustomPaint(
                  size: const Size(double.infinity, 8),
                  painter: _BarPainter(
                    progress: _progress(),
                    shimmer: (_seconds * 0.8) % 1,
                    track: scheme.surfaceContainerHighest,
                    from: scheme.primary,
                    to: scheme.tertiary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              '${widget.stage ?? 'Starting up'}… ${widget.hint}',
              key: ValueKey(widget.stage),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.progress,
    required this.shimmer,
    required this.track,
    required this.from,
    required this.to,
  });

  final double progress;
  final double shimmer;
  final Color track;
  final Color from;
  final Color to;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius), Paint()..color = track);
    final width = size.width * progress;
    if (width <= 0) return;
    final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, size.height), radius);
    canvas.drawRRect(
      fill,
      Paint()..shader = LinearGradient(colors: [from, to]).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    // A soft highlight sweeping across the filled part.
    canvas.save();
    canvas.clipRRect(fill);
    final sweepX = -60 + (width + 120) * shimmer;
    canvas.drawRect(
      Rect.fromLTWH(sweepX, 0, 60, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(sweepX, 0, 60, size.height)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.progress != progress || old.shimmer != shimmer;
}
