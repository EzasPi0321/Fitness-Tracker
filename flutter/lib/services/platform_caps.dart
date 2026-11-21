import 'package:flutter/foundation.dart';

/// What this device can do. The camera features (barcode scanner, meal photo) and the
/// health store only exist on phones; desktop and web get typed-barcode and file-picker
/// fallbacks instead.
class PlatformCaps {
  static bool get isPhone =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static bool get hasCamera => isPhone;
  static bool get hasHealthStore => isPhone;
  static bool get isWeb => kIsWeb;
}
