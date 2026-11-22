import 'package:flutter/foundation.dart';

/// What this device can do. The camera features (barcode scanner, meal photo) and the
/// health store only exist on phones; desktop and web get typed-barcode and file-picker
/// fallbacks instead.
class PlatformCaps {
  static bool get isPhone =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static bool get hasCamera => isPhone;

  /// Apple Health needs the app to be signed by a paid developer account (App Store or
  /// TestFlight). The iPhone builds are installed with SideStore or iloader on a free Apple
  /// ID, which iOS doesn't allow to use Health at all, so it's switched off there. A
  /// TestFlight build turns it back on with --dart-define=FITTRACK_IOS_HEALTH=true.
  static const iosHealthAllowed = bool.fromEnvironment('FITTRACK_IOS_HEALTH');

  static bool get hasHealthStore => isPhone && (defaultTargetPlatform == TargetPlatform.android || iosHealthAllowed);

  /// A phone with no health store: say nothing about Health at all, rather than offer a
  /// Connect button that can't work.
  static bool get hideHealth => isPhone && !hasHealthStore;
  static bool get isWeb => kIsWeb;
}
