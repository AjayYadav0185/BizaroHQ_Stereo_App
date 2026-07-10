import 'package:flutter/services.dart';

/// Defensive landscape orientation helpers for car head units.
///
/// This utility class enforces landscape-only orientation at the Flutter layer.
/// The native Android Activity also enforces landscape via
/// android:screenOrientation="landscape" in AndroidManifest.xml.
///
/// Usage in main.dart:
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   CarAppOrientation.forceLandscape();
///   runApp(const MyApp());
/// }
/// ```
class CarAppOrientation {
  /// Forces the app to run in landscape left or right orientation only.
  ///
  /// This is a defensive measure - the native Android manifest also
  /// enforces landscape orientation.
  static Future<void> forceLandscape() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}