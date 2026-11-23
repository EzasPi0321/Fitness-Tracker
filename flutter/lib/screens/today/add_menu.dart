import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/tokens.dart';
import '../../models/food.dart';
import '../../services/platform_caps.dart';
import '../../widgets/common.dart';
import '../log/log_flows.dart';
import '../log/voice_entry_screen.dart';

/// Every way to log food, opened from a meal's Add. Whatever is picked lands in that meal:
/// search, barcode and photo log at the meal's time, manual entry starts with the meal set.
/// Replaces the old floating button, so there's one place to add and it already knows the meal.
Future<void> showMealAddSheet(BuildContext context, {required DateTime day, required MealType meal}) async {
  HapticFeedback.selectionClick();
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _MealAddSheet(meal: meal),
  );
  if (choice == null || !context.mounted) return;
  final at = mealTime(day, meal);
  switch (choice) {
    case 'search':
      AppScope.read(context).requestFoodSearch(day, at);
    case 'barcode':
      PlatformCaps.hasCamera
          ? await openBarcodeScanner(context, day: day, at: at)
          : await openBarcodeEntry(context, day: day, at: at);
    case 'photo':
      await openSnapMeal(context, day: day, at: at);
    case 'voice':
      await openVoiceEntry(context, day: day);
    case 'manual':
      await openManualEntry(context, day: day, meal: meal);
  }
}

class _MealAddSheet extends StatelessWidget {
  const _MealAddSheet({required this.meal});
  final MealType meal;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    Widget option(String value, IconData icon, String label) => FRow(
      leading: FIcon(icon, color: t.fg, weight: FontWeight.w500),
      label: label,
      onTap: () => Navigator.pop(context, value),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, S.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add to ${meal.title.toLowerCase()}', style: tt.headlineSmall),
          const SizedBox(height: S.lg),
          FGroup(
            children: [
              option('search', Symbols.search, 'Search foods'),
              option(
                'barcode',
                PlatformCaps.hasCamera ? Symbols.barcode_scanner : Symbols.keyboard,
                PlatformCaps.hasCamera ? 'Scan barcode' : 'Enter barcode',
              ),
              option('photo', Symbols.photo_camera, PlatformCaps.hasCamera ? 'Snap meal' : 'Photo estimate'),
              option('voice', Symbols.mic, 'Voice entry'),
              option('manual', Symbols.edit_note, 'Manual entry'),
            ],
          ),
        ],
      ),
    );
  }
}
