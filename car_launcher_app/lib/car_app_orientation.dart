import 'package:flutter/services.dart';

/// Defensive helpers for landscape-only car head units.
///
/// The task requires forcing landscapeLeft and landscapeRight.
class CarAppOrientation {
  static Future<void> forceLandscape() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

