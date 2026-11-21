import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// OKLCH colour, the perceptual space used for the whole palette: equal L looks equally light,
/// so the three macro colours read as one family instead of one shouting over the others.
class Oklch {
  const Oklch(this.l, this.c, this.h, [this.alpha = 1]);

  final double l; // 0..1
  final double c; // chroma, ~0..0.37
  final double h; // degrees
  final double alpha;

  Oklch withL(double v) => Oklch(v, c, h, alpha);
  Oklch withC(double v) => Oklch(l, v, h, alpha);
  Oklch withAlpha(double v) => Oklch(l, c, h, v);

  /// Converts to sRGB, reducing chroma until the colour fits the gamut (keeps hue and lightness).
  Color toColor() {
    var lo = 0.0, hi = c;
    var rgb = _toLinearRgb(l, c, h);
    if (_inGamut(rgb)) return _encode(rgb, alpha);
    for (var i = 0; i < 20; i++) {
      final mid = (lo + hi) / 2;
      final t = _toLinearRgb(l, mid, h);
      if (_inGamut(t)) {
        lo = mid;
        rgb = t;
      } else {
        hi = mid;
      }
    }
    return _encode(_toLinearRgb(l, lo, h), alpha);
  }

  static Oklch lerp(Oklch a, Oklch b, double t) {
    // Hue takes the shorter way round the colour wheel.
    var dh = (b.h - a.h) % 360;
    if (dh > 180) dh -= 360;
    if (dh < -180) dh += 360;
    return Oklch(a.l + (b.l - a.l) * t, a.c + (b.c - a.c) * t, (a.h + dh * t) % 360, a.alpha + (b.alpha - a.alpha) * t);
  }

  static List<double> _toLinearRgb(double l, double c, double hDeg) {
    final h = hDeg * math.pi / 180;
    final a = c * math.cos(h), b = c * math.sin(h);
    final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = l - 0.0894841775 * a - 1.2914855480 * b;
    final ll = l_ * l_ * l_, mm = m_ * m_ * m_, ss = s_ * s_ * s_;
    return [
      4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
      -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
      -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss,
    ];
  }

  static bool _inGamut(List<double> rgb) => rgb.every((v) => v >= -0.0001 && v <= 1.0001);

  static Color _encode(List<double> rgb, double alpha) {
    double g(double x) {
      x = x.clamp(0.0, 1.0);
      return x <= 0.0031308 ? 12.92 * x : 1.055 * math.pow(x, 1 / 2.4) - 0.055;
    }

    return Color.from(alpha: alpha.clamp(0.0, 1.0), red: g(rgb[0]), green: g(rgb[1]), blue: g(rgb[2]));
  }
}

/// `linear-gradient(... in oklch, a, b)`: Flutter interpolates gradients in sRGB, which turns
/// the middle muddy grey. Sampling in OKLCH and handing Flutter many stops keeps it vivid.
List<Color> oklchStops(List<Oklch> colors, {int steps = 12}) {
  if (colors.length < 2) return colors.map((c) => c.toColor()).toList();
  final out = <Color>[];
  final segments = colors.length - 1;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps * segments;
    final seg = math.min(t.floor(), segments - 1);
    out.add(Oklch.lerp(colors[seg], colors[seg + 1], t - seg).toColor());
  }
  return out;
}

LinearGradient oklchLinearGradient(
  List<Oklch> colors, {
  AlignmentGeometry begin = Alignment.centerLeft,
  AlignmentGeometry end = Alignment.centerRight,
}) => LinearGradient(begin: begin, end: end, colors: oklchStops(colors));

SweepGradient oklchSweepGradient(List<Oklch> colors, {double startAngle = 0, double endAngle = math.pi * 2}) =>
    SweepGradient(startAngle: startAngle, endAngle: endAngle, colors: oklchStops(colors, steps: 24));
