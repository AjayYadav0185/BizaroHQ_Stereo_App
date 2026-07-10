import 'package:flutter/services.dart';

/// Media Control Bridge for Background Bluetooth Playback.
///
/// This class provides a Flutter MethodChannel interface to send media control
/// commands to the native Android layer. The native side dispatches hardware
/// media key events to control whatever Bluetooth audio player is active
/// (Spotify, YouTube Music, etc.) without requesting audio focus.
///
/// Channel: 'com.carapp.media/control'
/// Methods:
/// - mediaPrevious: Skip to previous track
/// - mediaToggle: Play/Pause toggle
/// - mediaNext: Skip to next track
class MediaChannel {
  static const MethodChannel _channel =
      MethodChannel('com.carapp.media/control');

  /// Skip to the previous track.
  ///
  /// Sends a KEYCODE_MEDIA_PREVIOUS hardware event to the active media session.
  static Future<void> previous() async {
    await _channel.invokeMethod('mediaPrevious');
  }

  /// Toggle play/pause state.
  ///
  /// Sends a KEYCODE_MEDIA_PLAY_PAUSE hardware event to the active media session.
  static Future<void> playPauseToggle() async {
    await _channel.invokeMethod('mediaToggle');
  }

  /// Skip to the next track.
  ///
  /// Sends a KEYCODE_MEDIA_NEXT hardware event to the active media session.
  static Future<void> next() async {
    await _channel.invokeMethod('mediaNext');
  }
}