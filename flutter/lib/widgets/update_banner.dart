import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_state.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../services/updates.dart';
import 'common.dart';

/// Gets the new release onto this device.
/// - Android: downloads the APK inside FitTrack and opens Android's installer; it installs over
///   the old app (same signing key) and keeps your data. One tap to confirm, no browser.
/// - iPhone: opens SideStore, which installs updates.
/// - Windows and the rest: opens the download or the release page.
Future<void> openUpdate(BuildContext context, AppUpdate update) async {
  final platform = Theme.of(context).platform;
  if (!kIsWeb && platform == TargetPlatform.android && update.downloadUrl != null) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InstallDialog(update: update),
    );
    return;
  }
  if (!kIsWeb && platform == TargetPlatform.iOS) {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse('sidestore://'), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (context.mounted) {
      showToast(
        context,
        opened ? 'In SideStore, open My Apps and tap Update.' : 'Open SideStore, then My Apps, and tap Update.',
      );
    }
    return;
  }
  await _openInBrowser(context, update);
}

Future<void> _openInBrowser(BuildContext context, AppUpdate update) async {
  final url = Uri.parse(update.downloadUrl ?? update.pageUrl);
  final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showToast(context, "Couldn’t open the download. Visit the Releases page on GitHub.");
}

/// Downloads the APK with a progress bar, then hands it to Android's installer.
class _InstallDialog extends StatefulWidget {
  const _InstallDialog({required this.update});
  final AppUpdate update;

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  StreamSubscription<OtaEvent>? _sub;
  double? _progress; // 0-1, null while starting
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    setState(() {
      _error = null;
      _progress = null;
    });
    try {
      _sub = OtaUpdate()
          .execute(widget.update.downloadUrl!, destinationFilename: 'FitTrack-${widget.update.build}.apk')
          .listen(_onEvent, onError: (_) => _fail(_genericError));
    } catch (_) {
      _fail(_genericError);
    }
  }

  static const _genericError = 'The download stopped. Check your connection and try again.';

  void _onEvent(OtaEvent e) {
    if (!mounted) return;
    switch (e.status) {
      case OtaStatus.DOWNLOADING:
        final pct = double.tryParse(e.value ?? '');
        setState(() => _progress = pct == null ? null : (pct / 100).clamp(0.0, 1.0));
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        // Android's installer is on screen now; it takes it from here.
        Navigator.of(context).pop();
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail(
          'FitTrack needs permission to install its updates. In Settings, open Apps, FitTrack, '
          'Install unknown apps, turn it on, then tap Update again.',
        );
      case OtaStatus.ALREADY_RUNNING_ERROR:
        _fail('An update is already downloading.');
      default:
        _fail(_genericError);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = _progress;
    return AlertDialog(
      title: Text(_error == null ? 'Downloading update' : 'Update didn’t finish'),
      content: _error != null
          ? Text(_error!)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.update.label, style: tt.bodyMedium),
                const SizedBox(height: S.lg),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: p, minHeight: 6),
                ),
                const SizedBox(height: S.sm),
                Text(
                  p == null ? 'Starting…' : '${(p * 100).round()}%  ·  then tap Update when Android asks',
                  style: tt.bodySmall!.copyWith(fontFeatures: tabular),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () {
            _sub?.cancel();
            Navigator.of(context).pop();
          },
          child: Text(_error == null ? 'Cancel' : 'Close'),
        ),
        if (_error != null) ...[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openInBrowser(context, widget.update);
            },
            child: const Text('Use browser'),
          ),
          FilledButton(onPressed: _start, child: const Text('Try again')),
        ],
      ],
    );
  }
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
        always: true,
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
