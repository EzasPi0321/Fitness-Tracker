import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'data/app_state.dart';
import 'design/tokens.dart';
import 'screens/log/food_log_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/progress/progress_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/today/today_screen.dart';
import 'widgets/common.dart';

class FitTrackApp extends StatefulWidget {
  const FitTrackApp({super.key, required this.state});
  final AppState state;

  @override
  State<FitTrackApp> createState() => _FitTrackAppState();
}

class _FitTrackAppState extends State<FitTrackApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.detached) widget.state.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => MaterialApp(
          title: 'FitTrack',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(FT.light()),
          darkTheme: buildTheme(FT.darkTheme()),
          themeMode: widget.state.appearance,
          scrollBehavior: kIsWeb ? const _WebScrollBehavior() : null,
          home: const _Root(),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.loaded) return const Scaffold();
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.slow),
      switchInCurve: Motion.enter,
      child: state.profile == null
          ? const OnboardingScreen(key: ValueKey('onboarding'))
          : const Shell(key: ValueKey('shell')),
    );
  }
}

class _Dest {
  const _Dest(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _dests = [
  _Dest('Today', Symbols.donut_large),
  _Dest('Food log', Symbols.restaurant_menu),
  _Dest('Progress', Symbols.monitoring),
  _Dest('Profile', Symbols.person),
  _Dest('Settings', Symbols.settings),
];

/// Five top-level places (Hick's law: still a glance). Phones get the bottom bar people already know;
/// wide windows get a side rail (Jakob's law). Tabs are switched constantly, so they don't
/// animate (frequency of use).
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final pages = IndexedStack(
      index: _index,
      children: const [TodayScreen(), FoodLogScreen(), ProgressScreen(), ProfileScreen(), SettingsScreen()],
    );

    if (wide) {
      final extended = MediaQuery.sizeOf(context).width >= 1180;
      return Scaffold(
        body: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: t.surface,
                border: Border(right: BorderSide(color: t.border)),
              ),
              child: SafeArea(
                child: NavigationRail(
                  extended: extended,
                  minExtendedWidth: 220,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.lg),
                    child: _Brand(extended: extended),
                  ),
                  destinations: [
                    for (var i = 0; i < _dests.length; i++)
                      NavigationRailDestination(
                        icon: FIcon(_dests[i].icon, size: 24, weight: FontWeight.w500),
                        selectedIcon: FIcon(_dests[i].icon, size: 24, weight: FontWeight.w600, fill: true, color: t.fg),
                        label: Text(_dests[i].label),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(child: pages),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          animationDuration: Motion.fast,
          destinations: [
            for (final d in _dests)
              NavigationDestination(
                icon: FIcon(d.icon, size: 24, weight: FontWeight.w500),
                selectedIcon: FIcon(d.icon, size: 24, weight: FontWeight.w600, fill: true, color: t.fg),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: FT.of(context).accent),
      child: Center(
        child: FIcon(Symbols.donut_large, size: 22, color: FT.of(context).onAccent, weight: FontWeight.w700),
      ),
    );
    if (!extended) return mark;
    return SizedBox(
      width: 188,
      child: Row(
        children: [
          mark,
          const SizedBox(width: S.md),
          Flexible(
            child: Text(
              'FitTrack',
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// The web build ships without shader assets, so no stretch overscroll (it needs one).
class _WebScrollBehavior extends MaterialScrollBehavior {
  const _WebScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
