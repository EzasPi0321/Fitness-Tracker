import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  // The web build is the desktop preview: it opens on sample data so the dashboards have
  // something to show. Phones and the Windows app start with onboarding.
  await state.load(seedSampleIfEmpty: kIsWeb);
  runApp(FitTrackApp(state: state));
}
