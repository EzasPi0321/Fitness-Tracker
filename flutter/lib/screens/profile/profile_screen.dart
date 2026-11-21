import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../settings/profile_section.dart';
import '../settings/settings_screen.dart' show TargetsSection;

/// Who you are and what you're aiming for: name, body stats, goal, and the daily targets
/// that come out of them. App preferences stay in Settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 840 ? S.xxl : S.lg;
    final twoCol = width >= 1000;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: WithSmoothScroll(
          builder: (c) => ListView(
            controller: c,
            padding: EdgeInsets.fromLTRB(gutter, S.lg, gutter, S.xxl),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: twoCol ? 1100 : 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Profile', style: tt.headlineMedium),
                      const SizedBox(height: S.xl),
                      const Rise(child: _NameCard()),
                      const SizedBox(height: S.xl),
                      if (twoCol)
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: ProfileSection()),
                            SizedBox(width: S.xl),
                            Expanded(child: TargetsSection()),
                          ],
                        )
                      else ...const [ProfileSection(), SizedBox(height: S.xl), TargetsSection()],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The avatar (initials) and the name. Typing updates the greeting on Today straight away.
class _NameCard extends StatefulWidget {
  const _NameCard();

  @override
  State<_NameCard> createState() => _NameCardState();
}

class _NameCardState extends State<_NameCard> {
  late final _ctl = TextEditingController(text: AppScope.read(context).profile?.name ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final initials = p?.initials ?? '';

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Row(
        children: [
          // A flat ink disc with the initials, like a monogram stamp.
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: t.accent),
            child: Center(
              child: BlurSwitcher(
                child: initials.isEmpty
                    ? FIcon(
                        Symbols.person,
                        key: const ValueKey('icon'),
                        size: 30,
                        color: t.onAccent,
                        weight: FontWeight.w600,
                      )
                    : Text(
                        initials,
                        key: ValueKey(initials),
                        style: tt.headlineSmall!.copyWith(color: t.onAccent),
                      ),
              ),
            ),
          ),
          const SizedBox(width: S.lg),
          Expanded(
            child: TextField(
              controller: _ctl,
              textCapitalization: TextCapitalization.words,
              style: tt.titleLarge,
              decoration: const InputDecoration(labelText: 'Your name', hintText: 'What should we call you?'),
              onChanged: (v) => state.updateProfile((p) => p.name = v.trim()),
            ),
          ),
        ],
      ),
    );
  }
}
