import 'dart:async';

import 'package:flutter/material.dart';

/// The one easing curve used across the app (a Bézier ease-out: quick start, long soft
/// landing), so highlighting, loading, page changes and hover effects all feel alike.
const smoothCurve = Cubic(0.22, 0.9, 0.3, 1.0);

/// Screen change: the new screen fades and glides in a few pixels while the old one
/// drifts back and fades slightly.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entering = CurvedAnimation(parent: animation, curve: smoothCurve, reverseCurve: Curves.easeInCubic);
    final leaving = CurvedAnimation(parent: secondaryAnimation, curve: smoothCurve, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.92).animate(leaving),
      child: SlideTransition(
        position: Tween(begin: Offset.zero, end: const Offset(-0.03, 0)).animate(leaving),
        child: FadeTransition(
          opacity: entering,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(entering),
            child: child,
          ),
        ),
      ),
    );
  }
}

PageTransitionsTheme get smoothPageTransitions =>
    PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: const SmoothPageTransitionsBuilder()});

/// Fades and lifts its child into place once, after an optional [delay] (use a growing
/// delay across a list for a staggered entrance). With [animate] false it just shows.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.animate = true,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final bool animate;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () => mounted ? _c.forward() : null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: smoothCurve);
    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => Opacity(
        opacity: t.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t.value) * widget.offset), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Gently grows under the mouse pointer.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.scale = 1.03});

  final Widget child;
  final double scale;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? widget.scale : 1,
        duration: const Duration(milliseconds: 220),
        curve: smoothCurve,
        child: widget.child,
      ),
    );
  }
}

/// Play ⇄ pause icon that morphs instead of swapping.
class PlayPauseIcon extends StatefulWidget {
  const PlayPauseIcon({super.key, required this.playing, this.size = 36});

  final bool playing;
  final double size;

  @override
  State<PlayPauseIcon> createState() => _PlayPauseIconState();
}

class _PlayPauseIconState extends State<PlayPauseIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(PlayPauseIcon old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) widget.playing ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
    icon: AnimatedIcons.play_pause,
    progress: CurvedAnimation(parent: _c, curve: smoothCurve),
    size: widget.size,
    semanticLabel: widget.playing ? 'Pause' : 'Play',
  );
}
