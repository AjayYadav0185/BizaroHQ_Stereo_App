import 'package:flutter/services.dart';

/// Media Control Bridge for Background Bluetooth Playback.
///
/// This class provides a Flutter MethodChannel interface to send media control
/// commands to the native Android layer. The native side targets the active
/// Bluetooth (A2DP) media session directly (via MediaSessionManager) and
/// dispatches hardware media key events / transport controls to control whatever
/// Bluetooth audio player is active (Spotify, YouTube Music, etc.) without
/// requesting audio focus.
///
/// Channel: 'com.carapp.media/control'
/// Methods:
/// - mediaPrevious: Skip to previous track
/// - mediaToggle: Play/Pause toggle
/// - mediaNext: Skip to next track
/// - isBluetoothConnected: Query active Bluetooth A2DP connection
class MediaChannel {
  static const MethodChannel _channel =
      MethodChannel('com.carapp.media/control');

  /// Skip to the previous track.
  ///
  /// Routes to the active media session (e.g. Bluetooth player) on the device.
  static Future<void> previous() async {
    try {
      await _channel.invokeMethod('mediaPrevious');
    } catch (_) {
      // Ignore – button simply does nothing if native bridge is unavailable.
    }
  }

  /// Toggle play/pause state.
  ///
  /// Routes to the active media session (e.g. Bluetooth player) on the device.
  static Future<void> playPauseToggle() async {
    try {
      await _channel.invokeMethod('mediaToggle');
    } catch (_) {
      // Ignore – button simply does nothing if native bridge is unavailable.
    }
  }

  /// Skip to the next track.
  ///
  /// Routes to the active media session (e.g. Bluetooth player) on the device.
  static Future<void> next() async {
    try {
      await _channel.invokeMethod('mediaNext');
    } catch (_) {
      // Ignore – button simply does nothing if native bridge is unavailable.
    }
  }

  /// Increase the device/media volume by one step (affects Bluetooth output).
  static Future<void> volumeUp() async {
    try {
      await _channel.invokeMethod('mediaVolumeUp');
    } catch (_) {
      // Ignore – button simply does nothing if native bridge is unavailable.
    }
  }

  /// Decrease the device/media volume by one step (affects Bluetooth output).
  static Future<void> volumeDown() async {
    try {
      await _channel.invokeMethod('mediaVolumeDown');
    } catch (_) {
      // Ignore – button simply does nothing if native bridge is unavailable.
    }
  }

  /// Returns true when a Bluetooth audio (A2DP) device is connected.
  static Future<bool> isBluetoothConnected() async {
    try {
      final result = await _channel.invokeMethod('isBluetoothConnected');
      return result == true;
    } catch (_) {
      return false;
    }
  }
}