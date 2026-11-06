import 'package:flutter/material.dart';

import 'loading_bar.dart';
import 'motion.dart';

/// Shown while a PDF opens: a ghost page whose text lines shimmer, with a progress bar
/// beneath it. Cross-fade it out (see `ReaderScreen`) when the real page is ready.
class PageSkeleton extends StatefulWidget {
  const PageSkeleton({super.key, required this.title});

  final String title;

  @override
  State<PageSkeleton> createState() => _PageSkeletonState();
}

class _PageSkeletonState extends State<PageSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))
    ..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  // Each text line: its width as a fraction of the page, and whether it's a heading.
  static const _lines = <(double, bool)>[
    (0.55, true),
    (1.0, false),
    (0.97, false),
    (1.0, false),
    (0.62, false),
    (0, false), // paragraph gap
    (1.0, false),
    (0.94, false),
    (0.99, false),
    (1.0, false),
    (0.88, false),
    (0.4, false),
    (0, false),
    (0.97, false),
    (1.0, false),
    (0.7, false),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.onSurface.withValues(alpha: 0.08);
    final glow = scheme.onSurface.withValues(alpha: 0.2);
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                    child: AnimatedBuilder(
                      animation: _sweep,
                      builder: (_, child) {
                        final t = smoothCurve.transform(_sweep.value);
                        return ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (rect) => LinearGradient(
                            colors: [base, glow, base],
                            stops: const [0.35, 0.5, 0.65],
                            transform: _Slide(-1.2 + 2.4 * t),
                          ).createShader(rect),
                          child: child,
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (width, heading) in _lines)
                            width == 0
                                ? const SizedBox(height: 18)
                                : Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.5),
                                    child: FractionallySizedBox(
                                      widthFactor: width,
                                      child: Container(
                                        height: heading ? 16 : 9,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(heading ? 5 : 4),
                                        ),
                                      ),
                                    ),
                                  ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                LoadingBar(
                  title: 'Opening ${widget.title}',
                  expected: const Duration(seconds: 3),
                  stage: 'Rendering the first page',
                  hint: 'Reading the text so it can be highlighted',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slides a gradient horizontally by [percent] of the shape's width.
class _Slide extends GradientTransform {
  const _Slide(this.percent);

  final double percent;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * percent, 0, 0);
}
