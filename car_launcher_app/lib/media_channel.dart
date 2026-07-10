import 'package:flutter/services.dart';

/// Media control bridge.
///
/// Flutter invokes a platform MethodChannel and the native Android side
/// dispatches *hardware* media key events to control whatever Bluetooth
/// player is currently active (Spotify/YouTube Music/etc.).
class MediaChannel {
  static const MethodChannel _channel =
      MethodChannel('com.carapp.media/control');

  static Future<void> previous() async {
    await _channel.invokeMethod('mediaPrevious');
  }

  static Future<void> playPauseToggle() async {
    await _channel.invokeMethod('mediaToggle');
  }

  static Future<void> next() async {
    await _channel.invokeMethod('mediaNext');
  }
}

