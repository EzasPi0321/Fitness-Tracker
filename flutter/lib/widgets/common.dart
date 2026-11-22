import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/food.dart';
import '../models/nutrients.dart';
import '../models/util.dart';

/// An icon whose stroke weight matches the text next to it.
class FIcon extends StatelessWidget {
  const FIcon(this.icon, {super.key, this.size = 20, this.color, this.weight = FontWeight.w500, this.fill = false});
  final IconData icon;
  final double size;
  final Color? color;
  final FontWeight weight;
  final bool fill;

  @override
  Widget build(BuildContext context) => Icon(
    icon,
    size: size,
    color: color,
    weight: weight.value.toDouble().clamp(100, 700),
    fill: fill ? 1 : 0,
    opticalSize: size.clamp(20, 48),
  );
}

IconData mealIcon(MealType m) => switch (m) {
  MealType.breakfast => Symbols.wb_twilight,
  MealType.lunch => Symbols.sunny,
  MealType.dinner => Symbols.bedtime,
  MealType.snack => Symbols.nutrition,
};

IconData sourceIcon(EntrySource s) => switch (s) {
  EntrySource.barcode => Symbols.barcode_scanner,
  EntrySource.photoAI => Symbols.photo_camera,
  EntrySource.manual => Symbols.edit_note,
  EntrySource.customFood => Symbols.star,
  EntrySource.voice => Symbols.mic,
};

/// A surface card. Inner elements should use `S.inner(radius, padding)`.
class FCard extends StatelessWidget {
  const FCard({super.key, required this.child, this.padding = const EdgeInsets.all(S.lg), this.radius = S.radiusCard});
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.border),
        boxShadow: t.shadow,
      ),
      padding: padding,
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, S.sm),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.labelMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

/// "P 12  C 30  F 5" with each letter in its macro colour.
class MacroInline extends StatelessWidget {
  const MacroInline(this.n, {super.key, this.style});
  final Nutrients n;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final base = (style ?? Theme.of(context).textTheme.bodySmall!).copyWith(fontFeatures: tabular);
    return Semantics(
      label: 'Protein ${whole(n.protein)} grams, carbs ${whole(n.carbs)} grams, fat ${whole(n.fat)} grams',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            for (final m in Macro.values) ...[
              TextSpan(
                text: m.short,
                style: TextStyle(color: t.macro(m), fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ' ${whole(n.of(m))}${m == Macro.fat ? '' : '   '}'),
            ],
          ],
        ),
      ),
    );
  }
}

/// A list row inside a card: label on the left, control or value on the right.
class FRow extends StatelessWidget {
  const FRow({super.key, required this.label, this.trailing, this.onTap, this.sub, this.leading});
  final String label;
  final String? sub;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: S.minTarget + 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 6),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: S.md)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: tt.bodyLarge),
                  if (sub != null) Text(sub!, style: tt.bodySmall),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: S.md), trailing!],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Squishy(onTap: onTap, feel: PressFeel.subtle, hitSlop: 0, child: row);
  }
}

/// Groups rows in one card with hairline separators.
class FGroup extends StatelessWidget {
  const FGroup({super.key, required this.children, this.label, this.footer});
  final List<Widget> children;
  final String? label;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) SectionLabel(label!),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(S.radiusCard - 4),
            border: Border.all(color: t.border),
          ),
          padding: const EdgeInsets.symmetric(vertical: S.xs),
          child: Column(
            children: [
              // No hairlines between rows: each row's own height already separates them.
              for (var i = 0; i < children.length; i++) children[i],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, S.sm, 6, 0),
            child: DefaultTextStyle.merge(style: Theme.of(context).textTheme.bodySmall, child: footer!),
          ),
      ],
    );
  }
}

/// Postel's law in a text field: takes "6,3", "1 1/2" or "150 kcal", hands back a clean number,
/// and rewrites the field tidily when focus leaves.
class NumberInput extends StatefulWidget {
  const NumberInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.unit,
    this.hint = '0',
    this.width = 110,
    this.maxDigits = 1,
    this.label,
  });

  final double? value;
  final ValueChanged<double?> onChanged;
  final String? unit;
  final String hint;
  final double width;
  final int maxDigits;
  final String? label;

  @override
  State<NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<NumberInput> {
  late final _ctl = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  // Grouped like every other number in the app ("10,000", "2,250"); the lenient parser reads
  // the comma back as a thousands separator.
  String _fmt(double? v) => v == null
      ? ''
      : NumberFormat('#,##0${widget.maxDigits > 0 ? '.${'#' * widget.maxDigits}' : ''}', 'en_US').format(v);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        final clean = _fmt(parseLenientNumber(_ctl.text));
        if (clean != _ctl.text) _ctl.text = clean;
      }
    });
  }

  @override
  void didUpdateWidget(NumberInput old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && parseLenientNumber(_ctl.text) != widget.value) _ctl.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _ctl,
        focusNode: _focus,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\t]'))],
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontFeatures: tabular),
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixText: widget.unit,
          suffixStyle: TextStyle(color: t.muted),
          semanticCounterText: widget.label,
        ),
        onChanged: (s) => widget.onChanged(parseLenientNumber(s)),
      ),
    );
  }
}

/// A − value + stepper with big targets (frequent control, so its press is subtle).
class Stepper2 extends StatelessWidget {
  const Stepper2({super.key, required this.onMinus, required this.onPlus, this.minusEnabled = true});
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final bool minusEnabled;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    Widget b(IconData i, VoidCallback? f, String label) => Squishy(
      onTap: f,
      feel: PressFeel.subtle,
      semanticLabel: label,
      child: SizedBox(
        width: 44,
        height: 40,
        child: Center(
          child: FIcon(i, size: 20, color: f == null ? t.muted.withValues(alpha: 0.4) : t.fg, weight: FontWeight.w600),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(color: t.inset, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(Symbols.remove, minusEnabled ? onMinus : null, 'Decrease'),
          Container(width: 1, height: 20, color: t.border),
          b(Symbols.add, onPlus, 'Increase'),
        ],
      ),
    );
  }
}

/// A pill that carries status by shape and colour together.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      // One paragraph with the icon inline, so a long message wraps inside the pill instead of
      // running off the screen, and a short one still sizes to its text.
      child: Text.rich(
        TextSpan(
          children: [
            if (icon != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FIcon(icon!, size: 14, color: color, weight: FontWeight.w600),
                ),
              ),
            TextSpan(text: text),
          ],
        ),
        style: Theme.of(context).textTheme.labelMedium!.copyWith(color: color),
      ),
    );
  }
}

/// Lifts toasts raised from inside [child] clear of something floating at the bottom of the
/// screen, such as Today's add button, so a toast never covers it.
class ToastInset extends InheritedWidget {
  const ToastInset({super.key, required this.bottom, required super.child});
  final double bottom;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ToastInset>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(ToastInset old) => old.bottom != bottom;
}

void showToast(BuildContext context, String text, {String? actionLabel, VoidCallback? onAction}) {
  final m = ScaffoldMessenger.of(context);
  final inset = ToastInset.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(text),
      margin: inset > 0 ? EdgeInsets.fromLTRB(S.lg, 0, S.lg, inset) : null,
      // Gone on its own: 2.5 s to read, 3 s when there's an Undo to reach for. Flutter keeps
      // snack bars with an action open until dismissed unless told otherwise.
      duration: Duration(milliseconds: actionLabel == null ? 2500 : 3000),
      persist: false,
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

/// Verified / Unverified nutrition tag. Shape and colour both carry the state; the reason
/// shows on hover or long-press. `compact` is an icon only, for dense rows.
class TrustTag extends StatelessWidget {
  const TrustTag(this.trust, {super.key, this.compact = false});
  final NutritionTrust trust;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final color = trust.verified ? t.good : t.warn;
    final icon = trust.verified ? Symbols.verified : Symbols.help;
    final child = compact
        ? Padding(
            padding: const EdgeInsets.all(2),
            child: FIcon(icon, size: 16, color: color, fill: trust.verified, weight: FontWeight.w600),
          )
        : StatusPill(text: trust.label, color: color, icon: icon);
    return Tooltip(
      message: '${trust.label}: ${trust.note}',
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(label: '${trust.label} nutrition. ${trust.note}', excludeSemantics: true, child: child),
    );
  }
}
