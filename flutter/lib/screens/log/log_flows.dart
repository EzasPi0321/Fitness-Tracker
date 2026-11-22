import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/tokens.dart';
import '../../models/health_score.dart';
import '../../models/food.dart';
import '../../models/util.dart';
import '../../services/ai_vision.dart';
import '../../services/label_ocr.dart';
import '../../services/open_food_facts.dart';
import '../../services/platform_caps.dart';
import '../../widgets/score.dart';
import '../../widgets/common.dart';
import 'manual_entry_screen.dart';
import 'product_sheet.dart';
import 'scan_screen.dart';
import 'snap_meal_screen.dart';

final _off = OpenFoodFactsService();

/// Logs entries, then makes the moment land: haptic, ring pulse (via AppState.logPulse) and a
/// toast with Undo.
Future<void> logAndCelebrate(BuildContext context, List<FoodEntry> entries) async {
  if (entries.isEmpty) return;
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  HapticFeedback.mediumImpact();
  final kcal = entries.fold<double>(0, (a, e) => a + e.nutrients.calories);
  final what = entries.length == 1 ? entries.first.name : '${entries.length} items';
  // The score lands with the confirmation: one food's own, or the plate's weighted by calories.
  final score = averageScore(entries);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Expanded(child: Text('Logged $what · ${Energy.format(kcal)}', maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (score != null) ...[
            const SizedBox(width: S.md),
            ScoreBadge(
              score,
              label: ScoreBand.of(score).label,
              // The snack bar is dark in light mode too.
              textColor: FT.of(context).dark ? FT.of(context).fg : FT.of(context).bg,
            ),
          ],
        ],
      ),
      duration: const Duration(seconds: 3),
      persist: false, // closes on its own, Undo or not
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          for (final e in entries) {
            state.deleteEntry(e);
          }
        },
      ),
    ),
  );
  await state.logEntries(entries);
}

Future<void> openManualEntry(
  BuildContext context, {
  required DateTime day,
  MealType? meal,
  ManualPrefill? prefill,
  DateTime? at,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ManualEntryScreen(day: day, meal: meal, prefill: prefill, at: at),
    ),
  );
}

Future<void> openBarcodeScanner(BuildContext context, {required DateTime day, DateTime? at}) async {
  final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
  if (code != null && context.mounted) await lookUpBarcode(context, code, day: day, at: at);
}

/// Desktop and web: type the digits under the barcode instead of scanning.
Future<void> openBarcodeEntry(BuildContext context, {required DateTime day, DateTime? at}) async {
  final code = await showDialog<String>(context: context, builder: (_) => const _BarcodeDialog());
  if (code != null && context.mounted) await lookUpBarcode(context, code, day: day, at: at);
}

Future<void> openSnapMeal(BuildContext context, {required DateTime day, DateTime? at}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SnapMealScreen(day: day, at: at),
    ),
  );
}

/// My Foods first (works offline), then Open Food Facts. An unknown barcode opens the manual
/// form with the barcode filled in, so saving it there makes the next scan instant.
Future<void> lookUpBarcode(BuildContext context, String raw, {required DateTime day, DateTime? at}) async {
  final state = AppScope.read(context);
  final code = OpenFoodFactsService.normalizeBarcode(raw);
  final local = state.customFoodForBarcode(code);
  if (local != null) {
    await showProductSheet(context, FoodProduct.fromCustomFood(local), day: day, at: at);
    return;
  }

  // Doherty threshold: show progress immediately while the network works.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: _LookupIndicator()),
  );
  FoodProduct? product;
  String? error;
  try {
    product = await _off.product(code);
  } on FoodLookupException catch (e) {
    error = e.message;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (product != null && product.hasNutrition) {
    await showProductSheet(context, product, day: day, at: at);
  } else if (product != null || error == FoodLookupException.notFound.message) {
    await _offerLabelPhoto(context, code, product, day: day, at: at);
  } else {
    showToast(context, error ?? 'Lookup failed.');
  }
}

class _LookupIndicator extends StatelessWidget {
  const _LookupIndicator();

  @override
  Widget build(BuildContext context) => const _BusyCard('Looking up product…');
}

class _BarcodeDialog extends StatefulWidget {
  const _BarcodeDialog();

  @override
  State<_BarcodeDialog> createState() => _BarcodeDialogState();
}

class _BarcodeDialogState extends State<_BarcodeDialog> {
  final _ctl = TextEditingController();

  // Accepts spaces and dashes as typed from a package; only the digits matter.
  bool get _valid {
    final n = OpenFoodFactsService.normalizeBarcode(_ctl.text).length;
    return n >= 6 && n <= 14;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter barcode'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'e.g. 3017 6204 2200 3'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _valid ? Navigator.pop(context, _ctl.text) : null,
            ),
            const SizedBox(height: S.sm),
            Text(
              'The digits printed under the barcode. Spaces and dashes are fine.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _valid ? () => Navigator.pop(context, _ctl.text) : null, child: const Text('Look up')),
      ],
    );
  }
}

enum _Missing { photo, library, manual }

/// The barcode isn't in Open Food Facts (or has no nutrition): offer to read the package's
/// nutrition label from a photo, or to type the numbers in. Either way it's saved to My Foods
/// under this barcode, so the next scan is instant.
Future<void> _offerLabelPhoto(
  BuildContext context,
  String code,
  FoodProduct? partial, {
  required DateTime day,
  DateTime? at,
}) async {
  final t = FT.of(context);
  final tt = Theme.of(context).textTheme;
  final choice = await showModalBottomSheet<_Missing>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            partial == null ? 'Not in the database yet' : 'No nutrition facts for this one',
            style: tt.headlineSmall,
          ),
          const SizedBox(height: S.sm),
          Text(
            'Photograph the nutrition label and FitTrack will read the numbers for you to check (no API key needed on a phone). '
            "It’s saved under barcode $code, so the next scan finds it.",
            style: tt.bodyMedium!.copyWith(color: t.muted),
          ),
          const SizedBox(height: S.xl),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, PlatformCaps.hasCamera ? _Missing.photo : _Missing.library),
            icon: FIcon(
              PlatformCaps.hasCamera ? Symbols.photo_camera : Symbols.upload_file,
              size: 20,
              weight: FontWeight.w600,
            ),
            label: Text(PlatformCaps.hasCamera ? 'Photograph the label' : 'Choose a label photo'),
          ),
          if (PlatformCaps.hasCamera) ...[
            const SizedBox(height: S.sm),
            OutlinedButton(
              onPressed: () => Navigator.pop(c, _Missing.library),
              child: const Text('Use a photo from my library'),
            ),
          ],
          const SizedBox(height: S.sm),
          TextButton(onPressed: () => Navigator.pop(c, _Missing.manual), child: const Text('Type the numbers instead')),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final base = ManualPrefill(barcode: code, name: partial?.name, brand: partial?.brand);
  if (choice == _Missing.manual) {
    await openManualEntry(context, day: day, prefill: base, at: at);
    return;
  }
  final reading = await readLabelPhoto(context, choice == _Missing.photo ? ImageSource.camera : ImageSource.gallery);
  if (reading == null || !context.mounted) return;
  await openManualEntry(
    context,
    day: day,
    prefill: ManualPrefill(barcode: code, name: partial?.name, brand: partial?.brand, label: reading),
    at: at,
  );
}

/// Picks a label photo and asks the AI to transcribe it. Shows progress right away and explains
/// any failure; returns null if the user cancels or it fails.
Future<LabelReading?> readLabelPhoto(BuildContext context, ImageSource source) async {
  final state = AppScope.read(context);
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(source: source);
  } catch (_) {
    if (context.mounted) showToast(context, "Couldn’t open the ${source == ImageSource.camera ? 'camera' : 'photo'}.");
    return null;
  }
  if (file == null || !context.mounted) return null;
  final key = (await state.keys.read(state.visionProvider.keyName)).trim();
  if (!context.mounted) return null;
  final onDevice = LabelOcr.isAvailable;
  if (key.isEmpty && !onDevice) {
    // Desktop has no on-device reader, so it needs an AI key.
    showToast(context, VisionException.missingKey.message);
    return null;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(child: _BusyCard(key.isEmpty ? 'Reading the label on your phone…' : 'Reading the label…')),
  );
  LabelReading? reading;
  String? error;
  // With a key the AI reads it (better with glare and curved packs); without one, or if the AI
  // fails, the phone reads it itself. No key and no network needed for that path.
  if (key.isNotEmpty) {
    try {
      final jpeg = await prepareMealPhoto(await file.readAsBytes());
      if (jpeg == null) throw const VisionException("That file couldn’t be read as a photo.");
      final service = AIVisionService(provider: state.visionProvider, apiKey: key, model: state.visionModel);
      try {
        reading = await service.readNutritionLabel(jpeg);
      } finally {
        state.recordAiUsage('label', service.calls);
      }
    } on VisionException catch (e) {
      error = e.message;
    }
  }
  if (reading == null && onDevice) {
    try {
      reading = await LabelOcr.read(file.path);
      error = null;
    } on VisionException catch (e) {
      error ??= e.message;
    } catch (_) {
      error ??= "The label couldn’t be read on this phone. Type the numbers instead.";
    }
  }
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop();
  if (error != null) showToast(context, error);
  return reading;
}

/// A short wait. Shows nothing for the first 400 ms, so a quick lookup never flashes a card
/// (Doherty threshold), then fades in with a calm line instead of a spinner.
class _BusyCard extends StatefulWidget {
  const _BusyCard(this.text);
  final String text;

  @override
  State<_BusyCard> createState() => _BusyCardState();
}

class _BusyCardState extends State<_BusyCard> {
  bool _shown = false;
  late final _timer = Timer(const Duration(milliseconds: 400), () {
    if (mounted) setState(() => _shown = true);
  });

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: Motion.of(context, Motion.base),
      curve: Motion.enter,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(S.xl),
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(S.radiusCard),
          border: Border.all(color: t.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.text, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: S.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(minHeight: 2, color: t.fg, backgroundColor: t.inset),
            ),
          ],
        ),
      ),
    );
  }
}
