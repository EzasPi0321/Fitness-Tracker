import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_state.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../services/updates.dart';
import 'common.dart';

/// Opens the new release: the APK on Android (it installs over the old app and keeps your
/// data), the zip on Windows, or the release page elsewhere.
Future<void> openUpdate(BuildContext context, AppUpdate update) async {
  final url = Uri.parse(update.downloadUrl ?? update.pageUrl);
  final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showToast(context, "Couldn't open the download. Visit the Releases page on GitHub.");
}

/// "New version available" at the top of Today, with Update and dismiss.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final update = state.availableUpdate;
    if (!state.showUpdateBanner || update == null) return const SizedBox.shrink();
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: S.lg),
      child: Rise(
        child: Container(
          padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.sm, S.md),
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: BorderRadius.circular(S.radiusControl + 4),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              FIcon(Symbols.system_update, color: t.fg, weight: FontWeight.w600),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New version available', style: tt.titleSmall),
                    Text(
                      update.notes.isEmpty ? update.label : '${update.label} · ${update.notes}',
                      style: tt.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.sm),
              Squishy(
                onTap: () => openUpdate(context, update),
                feel: PressFeel.bold,
                child: IgnorePointer(
                  child: FilledButton(onPressed: () {}, child: const Text('Update')),
                ),
              ),
              IconButton(
                tooltip: 'Not now',
                onPressed: state.dismissUpdate,
                icon: FIcon(Symbols.close, size: 20, color: t.muted, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
