import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// How lively a control's press is. Frequent controls (list rows, steppers) barely move;
/// rare, important ones (the add button, "Log") get the full squash and spring.
enum PressFeel { subtle, normal, bold }

/// Squash & stretch with follow-through: squishes on press (wider, shorter), springs back
/// past its rest shape on release (stretches), then settles. Also widens the hit area so the
/// clickable region can be bigger than it looks.
class Squishy extends StatefulWidget {
  const Squishy({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.feel = PressFeel.normal,
    this.hitSlop = 6,
    this.haptic = false,
    this.semanticLabel,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final PressFeel feel;
  final double hitSlop;
  final bool haptic;
  final String? semanticLabel;
  final bool enabled;

  @override
  State<Squishy> createState() => _SquishyState();
}

class _SquishyState extends State<Squishy> with SingleTickerProviderStateMixin {
  // 0 = rest, 1 = fully pressed; the spring can carry it below 0 (stretch).
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  bool _focused = false;

  double get _depth => switch (widget.feel) {
    // Never below 95% (scale 0.95): tactile without looking broken.
    PressFeel.subtle => 0.02,
    PressFeel.normal => 0.04,
    PressFeel.bold => 0.05,
  };

  void _down() {
    if (!_active || Motion.reduced(context)) return;
    _c.animateTo(1, duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
  }

  void _up() {
    if (Motion.reduced(context)) {
      _c.value = 0;
      return;
    }
    // Under-damped spring: overshoots past rest (the stretch) and settles in ~250 ms.
    const spring = SpringDescription(mass: 1, stiffness: 520, damping: 18);
    _c.animateWith(SpringSimulation(spring, _c.value, 0, -4));
  }

  bool get _active => widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _tap() {
    if (!_active) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    Widget child = AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final p = _c.value;
        final sx = 1 + p * _depth * 0.35; // wider when squashed
        final sy = 1 - p * _depth; // shorter when squashed, taller when stretched (p < 0)
        return Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(sx, sy, 1), child: child);
      },
      child: widget.child,
    );

    if (_focused) {
      child = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(S.radiusControl),
          border: Border.all(color: t.fg, width: 2),
        ),
        child: child,
      );
    }

    return Semantics(
      button: true,
      enabled: _active,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _active,
        mouseCursor: _active ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _tap())},
        child: HitSlop(
          slop: widget.hitSlop,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _down(),
            onTapUp: (_) => _up(),
            onTapCancel: _up,
            onTap: _active ? _tap : null,
            onLongPress: widget.onLongPress,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Accepts taps a few pixels outside the child's painted bounds (Fitts's law) without
/// changing layout.
class HitSlop extends SingleChildRenderObjectWidget {
  const HitSlop({super.key, required this.slop, super.child});
  final double slop;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderHitSlop(slop);

  @override
  void updateRenderObject(BuildContext context, RenderHitSlop renderObject) => renderObject.slop = slop;
}

class RenderHitSlop extends RenderProxyBox {
  RenderHitSlop(this.slop);
  double slop;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final inflated = (Offset.zero & size).inflate(slop);
    if (!inflated.contains(position)) return false;
    final clamped = Offset(position.dx.clamp(0, size.width), position.dy.clamp(0, size.height));
    if (hitTestChildren(result, position: clamped)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// Icon swaps: the outgoing icon blurs as it fades out while the new one sharpens in.
class BlurSwitcher extends StatelessWidget {
  const BlurSwitcher({super.key, required this.child, this.duration = Motion.base});
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, duration),
      switchInCurve: Motion.enter,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => AnimatedBuilder(
        animation: anim,
        child: child,
        builder: (context, child) {
          final v = anim.value;
          final blur = (1 - v) * 4;
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.8 + 0.2 * v,
              child: blur < 0.05
                  ? child
                  : ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: child,
                    ),
            ),
          );
        },
      ),
      child: child,
    );
  }
}

/// Carousels fade out at the edges: transparent → opaque 15–85 % → transparent.
class FadeEdges extends StatelessWidget {
  const FadeEdges({super.key, required this.child, this.axis = Axis.horizontal, this.inset = 0.08});
  final Widget child;
  final Axis axis;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: axis == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: axis == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, inset, 1 - inset, 1],
      ).createShader(rect),
      // Its own layer: the mask is re-applied while scrolling, the content isn't redrawn.
      child: RepaintBoundary(child: child),
    );
  }
}

/// A number that counts to its new value (slow in, slow out) instead of jumping.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.format, this.style, this.duration = Motion.slow});
  final double value;
  final String Function(double) format;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: Motion.of(context, duration),
      curve: Motion.standard,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Appear with a short rise and settle; used for staged entrances, one group at a time.
/// Screens opened many times a day (the main tabs) sit inside this, so their content is
/// simply there at launch instead of rising in every time (frequency of use).
class NoEntrance extends InheritedWidget {
  const NoEntrance({super.key, required super.child});
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NoEntrance>() != null;
  @override
  bool updateShouldNotify(NoEntrance oldWidget) => false;
}

class Rise extends StatelessWidget {
  const Rise({super.key, required this.child, this.delay = Duration.zero, this.distance = 10, this.always = false});
  final Widget child;
  final Duration delay;
  final double distance;

  /// Rise even inside [NoEntrance]: for things that genuinely arrive later, like a banner.
  final bool always;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context) || (!always && NoEntrance.of(context))) return child;
    final total = Motion.slow + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Motion.settle),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - v) * distance), child: child),
      ),
    );
  }
}
