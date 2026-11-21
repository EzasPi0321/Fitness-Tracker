import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../services/platform_caps.dart';
import '../../widgets/common.dart';
import '../log/log_flows.dart';

class _Item {
  const _Item(this.label, this.icon, this.run);
  final String label;
  final IconData icon;
  final void Function(BuildContext context, DateTime day) run;
}

/// The floating add button. Opening it: a quick wind-up (anticipation), the plus blurs into
/// an × (icon swap), and three choices (Hick's law) fly out along curved paths (arcs) with a
/// small stagger, overshooting and settling (follow-through). All in under 300 ms.
class AddMenu extends StatefulWidget {
  const AddMenu({super.key, required this.day});
  final DateTime day;

  @override
  State<AddMenu> createState() => _AddMenuState();
}

class _AddMenuState extends State<AddMenu> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  bool _open = false;

  @override
  void initState() {
    super.initState();
    // Drop the items from the tree (and from screen readers) once the close finishes.
    _c.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && mounted) setState(() {});
    });
  }

  List<_Item> get _items => [
    PlatformCaps.hasCamera
        ? _Item('Scan barcode', Symbols.barcode_scanner, (c, d) => openBarcodeScanner(c, day: d))
        : _Item('Enter barcode', Symbols.keyboard, (c, d) => openBarcodeEntry(c, day: d)),
    _Item(
      PlatformCaps.hasCamera ? 'Snap meal' : 'Photo estimate',
      Symbols.photo_camera,
      (c, d) => openSnapMeal(c, day: d),
    ),
    _Item('Manual entry', Symbols.edit_note, (c, d) => openManualEntry(c, day: d)),
  ];

  void _toggle([bool? open]) {
    final next = open ?? !_open;
    if (next == _open) return;
    setState(() => _open = next);
    if (Motion.reduced(context)) {
      _c.value = next ? 1 : 0;
      return;
    }
    if (next) {
      HapticFeedback.selectionClick();
      _c.forward(from: 0);
    } else {
      _c.animateBack(0, duration: const Duration(milliseconds: 180), curve: Curves.easeIn);
    }
  }

  void _pick(_Item item) {
    _toggle(false);
    item.run(context, widget.day);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final pad = MediaQuery.paddingOf(context);
    final items = _items;
    const fab = 64.0, radius = 124.0;
    final right = 20.0 + pad.right;
    final bottom = 20.0 + pad.bottom;

    return Positioned.fill(
      child: Stack(
        children: [
          // Scrim: staging, the menu becomes the only thing in focus. A dark tint (not the page
          // background) so it reads in light mode too.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_open,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggle(false),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => ColoredBox(
                    color: (t.dark ? Colors.black : t.fg).withValues(
                      alpha: (t.dark ? 0.55 : 0.28) * Curves.easeOut.transform(_c.value.clamp(0, 1)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_open || !_c.isDismissed)
            for (var i = 0; i < items.length; i++)
              AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  // Stagger: each item starts 30 ms after the previous one.
                  final start = 0.18 + i * 0.11;
                  final raw = ((_c.value - start) / (1 - start)).clamp(0.0, 1.0);
                  final e = Motion.settle.transform(raw);
                  // Fan from left (180°) to straight up (270°). The angle also sweeps while the item
                  // travels, so its path is a curve rather than a straight line.
                  final finalAngle = math.pi + (math.pi / 2) * (i / (items.length - 1));
                  final angle = finalAngle + (1 - e) * 0.7;
                  final dist = radius * e;
                  final dx = math.cos(angle) * dist;
                  final dy = math.sin(angle) * dist;
                  return Positioned(
                    right: right + fab / 2 - 28 - dx,
                    bottom: bottom + fab / 2 - 28 - dy,
                    child: IgnorePointer(
                      ignoring: !_open,
                      child: Opacity(
                        opacity: raw.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.5 + 0.5 * e,
                          alignment: Alignment.centerRight,
                          origin: const Offset(-28, 0),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: _MenuItem(item: items[i], onTap: () => _pick(items[i])),
              ),
          Positioned(
            right: right,
            bottom: bottom,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                // Anticipation: dips to 90 % in the first fifth, then springs back past 100 %.
                final v = _c.value;
                final s = v < 0.2
                    ? 1 - 0.1 * Curves.easeOut.transform(v / 0.2)
                    : 0.9 + 0.1 * Motion.settle.transform((v - 0.2) / 0.8);
                return Transform.scale(scale: _open ? s : 1, child: child);
              },
              child: Squishy(
                onTap: _toggle,
                feel: PressFeel.bold,
                hitSlop: 10,
                semanticLabel: _open ? 'Close menu' : 'Log food',
                child: Container(
                  width: fab,
                  height: fab,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Solid drawing: a soft top-left highlight gives the disc volume.
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.45),
                      radius: 0.9,
                      colors: [t.accent, Color.lerp(t.accent, t.dark ? Colors.black : Colors.white, 0.14)!],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: t.dark ? 0.6 : 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: BlurSwitcher(
                      child: FIcon(
                        _open ? Symbols.close : Symbols.add,
                        key: ValueKey(_open),
                        size: 30,
                        color: t.onAccent,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.item, required this.onTap});
  final _Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    // Label and circle form one row, so the whole thing is the hit target (Fitts's law).
    return Squishy(
      onTap: onTap,
      feel: PressFeel.normal,
      hitSlop: 8,
      semanticLabel: item.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: t.border),
              boxShadow: t.shadow,
            ),
            child: Text(item.label, style: tt.labelLarge, maxLines: 1, softWrap: false),
          ),
          const SizedBox(width: S.sm),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: t.raised,
              shape: BoxShape.circle,
              border: Border.all(color: t.border),
              boxShadow: t.shadow,
            ),
            child: Center(
              child: FIcon(item.icon, size: 24, color: t.fg, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
