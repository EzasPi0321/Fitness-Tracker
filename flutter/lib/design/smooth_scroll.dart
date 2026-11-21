import 'package:flutter/widgets.dart';

/// Mouse-wheel scrolling that glides instead of jumping.
///
/// Flutter applies each wheel notch as an instant ~100 px jump, which reads as stutter with a
/// mouse. Here a notch animates to its target with a short ease-out (200 ms), and notches that
/// arrive mid-glide add to the target, so a fast spin carries on smoothly. Trackpads already
/// send small, continuous deltas, so those (and reduced motion) keep the direct behaviour;
/// touch scrolling and flings never come through here at all.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({super.initialScrollOffset, super.keepScrollOffset, super.debugLabel});

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) {
    return _SmoothWheelPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothWheelPosition extends ScrollPositionWithSingleContext {
  _SmoothWheelPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  @override
  void pointerScroll(double delta) {
    final reduced = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    // Small deltas are a trackpad: already continuous, so follow it directly.
    if (reduced || delta.abs() < 40 || !hasContentDimensions) {
      super.pointerScroll(delta);
      return;
    }
    final current = activity;
    final base = current is _GlideActivity ? current.target : pixels;
    final target = (base + delta).clamp(minScrollExtent, maxScrollExtent);
    if (target == pixels && current is! _GlideActivity) return;
    if (current is _GlideActivity) {
      // Keep the one glide going and move its finish line: no restart, no extra
      // scroll-start/end notifications for every notch of a fast spin.
      current.retarget(target);
    } else {
      beginActivity(_GlideActivity(this, from: pixels, to: target, vsync: context.vsync));
    }
  }
}

/// One glide toward a target that further notches can move.
class _GlideActivity extends ScrollActivity {
  _GlideActivity(super.delegate, {required double from, required double to, required TickerProvider vsync})
    : target = to {
    _controller = AnimationController.unbounded(value: from, vsync: vsync)..addListener(_tick);
    _run();
  }

  static const _duration = Duration(milliseconds: 200);
  late final AnimationController _controller;
  double target;

  void retarget(double to) {
    target = to;
    _run();
  }

  void _run() {
    // A plain .then only fires on a natural finish, not when a retarget cancels the run.
    _controller.animateTo(target, duration: _duration, curve: Curves.easeOutCubic).then((_) {
      delegate.goBallistic(0);
    });
  }

  void _tick() {
    if (delegate.setPixels(_controller.value) != 0.0) delegate.goIdle(); // hit an edge
  }

  @override
  bool get shouldIgnorePointer => false; // taps land during a glide

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _controller.velocity;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Gives a stateless screen its own [SmoothScrollController] (created once, disposed with it).
class WithSmoothScroll extends StatefulWidget {
  const WithSmoothScroll({super.key, required this.builder});
  final Widget Function(ScrollController controller) builder;

  @override
  State<WithSmoothScroll> createState() => _WithSmoothScrollState();
}

class _WithSmoothScrollState extends State<WithSmoothScroll> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}
