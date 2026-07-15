import 'dart:async';
import 'package:flutter/services.dart';

/// Bluetooth A2DP Media Control Bridge for TopWay TS7 Head Unit
///
/// This is the PRIMARY Bluetooth media control interface. All A2DP
/// media playback operations go through this dedicated channel.
///
/// The native BluetoothMediaService handles:
/// - Real-time A2DP connection monitoring via BroadcastReceiver
/// - Active media session polling for now-playing track info (every 1.5s)
/// - Transport controls (play/pause/next/prev) routed to A2DP
/// - Volume control on the A2DP audio stream
///
/// Channel: 'com.carapp.btmedia/control'
class BluetoothMediaChannel {
  static const MethodChannel _channel =
      MethodChannel('com.carapp.btmedia/control');

  // ── Connection State ──

  /// Returns true when a Bluetooth A2DP device is currently connected.
  static Future<bool> isConnected() async {
    try {
      final result = await _channel.invokeMethod('bt_isConnected');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the name of the connected Bluetooth device.
  static Future<String> getDeviceName() async {
    try {
      final result = await _channel.invokeMethod('bt_getDeviceName');
      return (result as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Returns the MAC address of the connected Bluetooth device.
  static Future<String> getDeviceAddress() async {
    try {
      final result = await _channel.invokeMethod('bt_getDeviceAddress');
      return (result as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  // ── Now-Playing Metadata ──

  /// Returns the current track title from the active A2DP media session.
  static Future<String> getTrackTitle() async {
    try {
      final result = await _channel.invokeMethod('bt_getTrackTitle');
      return (result as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Returns the current track artist from the active A2DP media session.
  static Future<String> getTrackArtist() async {
    try {
      final result = await _channel.invokeMethod('bt_getTrackArtist');
      return (result as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Returns true if media is currently playing on the A2DP device.
  static Future<bool> isPlaying() async {
    try {
      final result = await _channel.invokeMethod('bt_isPlaying');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the package name of the active media player app.
  static Future<String> getActivePackage() async {
    try {
      final result = await _channel.invokeMethod('bt_getActivePackage');
      return (result as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  // ── Transport Controls (A2DP) ──

  /// Toggle play/pause on the connected A2DP Bluetooth device.
  /// Uses MediaSessionManager TransportControls with hardware key fallback.
  static Future<void> playPause() async {
    try {
      await _channel.invokeMethod('bt_playPause');
    } catch (_) {}
  }

  /// Skip to the next track on the A2DP device.
  static Future<void> next() async {
    try {
      await _channel.invokeMethod('bt_next');
    } catch (_) {}
  }

  /// Skip to the previous track on the A2DP device.
  static Future<void> previous() async {
    try {
      await _channel.invokeMethod('bt_previous');
    } catch (_) {}
  }

  // ── Volume Control (A2DP) ──

  /// Increase the A2DP audio stream volume by one step.
  static Future<void> volumeUp() async {
    try {
      await _channel.invokeMethod('bt_volumeUp');
    } catch (_) {}
  }

  /// Decrease the A2DP audio stream volume by one step.
  static Future<void> volumeDown() async {
    try {
      await _channel.invokeMethod('bt_volumeDown');
    } catch (_) {}
  }

  // ── Convenience ──

  /// Get complete now-playing info in one call.
  static Future<({String title, String artist, bool isPlaying})>
      getNowPlaying() async {
    final results = await Future.wait([
      getTrackTitle(),
      getTrackArtist(),
      isPlaying(),
    ]);
    return (
      title: results[0] as String,
      artist: results[1] as String,
      isPlaying: results[2] as bool,
    );
  }

  /// Get complete connection info in one call.
  static Future<({bool connected, String name, String address})>
      getConnectionInfo() async {
    final results = await Future.wait([
      isConnected(),
      getDeviceName(),
      getDeviceAddress(),
    ]);
    return (
      connected: results[0] as bool,
      name: results[1] as String,
      address: results[2] as String,
    );
  }
}

/// LEGACY - Media Control Bridge for Background Bluetooth Playback.
///
/// DEPRECATED: Use BluetoothMediaChannel instead for all Bluetooth A2DP
/// media control. This class is kept for backward compatibility.
class MediaChannel {
  static const MethodChannel _channel =
      MethodChannel('com.carapp.media/control');

  /// Skip to the previous track.
  @Deprecated('Use BluetoothMediaChannel.previous() instead')
  static Future<void> previous() async {
    try {
      await _channel.invokeMethod('mediaPrevious');
    } catch (_) {}
  }

  /// Toggle play/pause state.
  @Deprecated('Use BluetoothMediaChannel.playPause() instead')
  static Future<void> playPauseToggle() async {
    try {
      await _channel.invokeMethod('mediaToggle');
    } catch (_) {}
  }

  /// Skip to the next track.
  @Deprecated('Use BluetoothMediaChannel.next() instead')
  static Future<void> next() async {
    try {
      await _channel.invokeMethod('mediaNext');
    } catch (_) {}
  }

  /// Increase the device/media volume by one step.
  @Deprecated('Use BluetoothMediaChannel.volumeUp() instead')
  static Future<void> volumeUp() async {
    try {
      await _channel.invokeMethod('mediaVolumeUp');
    } catch (_) {}
  }

  /// Decrease the device/media volume by one step.
  @Deprecated('Use BluetoothMediaChannel.volumeDown() instead')
  static Future<void> volumeDown() async {
    try {
      await _channel.invokeMethod('mediaVolumeDown');
    } catch (_) {}
  }

  /// Returns true when a Bluetooth audio (A2DP) device is connected.
  @Deprecated('Use BluetoothMediaChannel.isConnected() instead')
  static Future<bool> isBluetoothConnected() async {
    try {
      final result = await _channel.invokeMethod('isBluetoothConnected');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Prompts the user (on Android 12+) for the BLUETOOTH_CONNECT runtime
  /// permission and returns whether it is now granted.
  static Future<bool> requestBluetoothPermission() async {
    try {
      final result = await _channel.invokeMethod('requestBluetoothPermission');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the currently playing track title/artist.
  @Deprecated('Use BluetoothMediaChannel.getNowPlaying() instead')
  static Future<({String title, String artist})> getNowPlaying() async {
    try {
      final result = await _channel.invokeMethod('getNowPlaying');
      if (result is Map) {
        return (
          title: (result['title'] as String?) ?? '',
          artist: (result['artist'] as String?) ?? '',
        );
      }
    } catch (_) {}
    return (title: '', artist: '');
  }
}

/// PT2313 Audio IC Control Bridge for TopWay TS7 Head Unit
///
/// Controls the PT2313 hardware audio processor via I2C communication.
/// Provides low-level control over:
/// - Volume (0-63 steps)
/// - Bass (0-14)
/// - Treble (0-14)
/// - Balance (-7 to +7)
/// - Fader (-7 to +7)
/// - Mute
/// - Input source selection (Radio/USB/AUX/BT)
///
/// Channel: 'com.carapp.audio/pt2313'
class PT2313Channel {
  static const MethodChannel _channel =
      MethodChannel('com.carapp.audio/pt2313');

  /// Set hardware volume level (0-63).
  static Future<bool> setVolume(int volume) async {
    try {
      final result = await _channel
          .invokeMethod('pt2313_setVolume', {'volume': volume});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Get current hardware volume level (0-63).
  static Future<int> getVolume() async {
    try {
      final result = await _channel.invokeMethod('pt2313_getVolume');
      return (result as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Mute or unmute the audio output.
  static Future<bool> setMute(bool mute) async {
    try {
      final result =
          await _channel.invokeMethod('pt2313_setMute', {'mute': mute});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Check if audio is currently muted.
  static Future<bool> isMuted() async {
    try {
      final result = await _channel.invokeMethod('pt2313_isMuted');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Set bass level (0-14).
  static Future<bool> setBass(int bass) async {
    try {
      final result =
          await _channel.invokeMethod('pt2313_setBass', {'bass': bass});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Get current bass level (0-14).
  static Future<int> getBass() async {
    try {
      final result = await _channel.invokeMethod('pt2313_getBass');
      return (result as int?) ?? 8;
    } catch (_) {
      return 8;
    }
  }

  /// Set treble level (0-14).
  static Future<bool> setTreble(int treble) async {
    try {
      final result =
          await _channel.invokeMethod('pt2313_setTreble', {'treble': treble});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Get current treble level (0-14).
  static Future<int> getTreble() async {
    try {
      final result = await _channel.invokeMethod('pt2313_getTreble');
      return (result as int?) ?? 8;
    } catch (_) {
      return 8;
    }
  }

  /// Set balance (-7 to +7, 0 = center).
  static Future<bool> setBalance(int balance) async {
    try {
      final result = await _channel
          .invokeMethod('pt2313_setBalance', {'balance': balance});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Get current balance (-7 to +7, 0 = center).
  static Future<int> getBalance() async {
    try {
      final result = await _channel.invokeMethod('pt2313_getBalance');
      return (result as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Set fader (-7 to +7, 0 = center).
  static Future<bool> setFader(int fader) async {
    try {
      final result =
          await _channel.invokeMethod('pt2313_setFader', {'fader': fader});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Get current fader (-7 to +7, 0 = center).
  static Future<int> getFader() async {
    try {
      final result = await _channel.invokeMethod('pt2313_getFader');
      return (result as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Select audio input source.
  /// 0 = Radio, 1 = USB/SD, 2 = AUX, 3 = Bluetooth
  static Future<bool> setInputSource(int source) async {
    try {
      final result = await _channel
          .invokeMethod('pt2313_setInputSource', {'source': source});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Get current input source (0-3).
  static Future<int> getInputSource() async {
    try {
      final result = await _channel.invokeMethod('pt2313_getInputSource');
      return (result as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Get map of available input source names.
  static Future<Map<int, String>> getInputSourceNames() async {
    try {
      final result =
          await _channel.invokeMethod('pt2313_getInputSourceNames');
      if (result is Map) {
        return result.map((k, v) => MapEntry(k as int, v as String));
      }
    } catch (_) {}
    return {
      0: 'Radio',
      1: 'USB/SD',
      2: 'AUX',
      3: 'Bluetooth',
    };
  }

  /// Reset PT2313 to default audio settings.
  static Future<void> reset() async {
    try {
      await _channel.invokeMethod('pt2313_reset');
    } catch (_) {}
  }
}

/// Bluetooth 5.0 LE Control Bridge for TopWay TS7 Head Unit
///
/// Provides Bluetooth Low Energy 5.0 capabilities:
/// - BLE hardware detection
/// - BLE device scanning and discovery
/// - GATT connection management
///
/// Channel: 'com.carapp.ble/control'
class BluetoothLEChannel {
  static const MethodChannel _channel =
      MethodChannel('com.carapp.ble/control');

  /// Check if BLE hardware is supported on this device.
  static Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod('ble_isSupported');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Check if Bluetooth is currently enabled.
  static Future<bool> isEnabled() async {
    try {
      final result = await _channel.invokeMethod('ble_isEnabled');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Start scanning for nearby BLE devices.
  static Future<bool> startScan() async {
    try {
      final result = await _channel.invokeMethod('ble_startScan');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Stop the BLE scan.
  static Future<void> stopScan() async {
    try {
      await _channel.invokeMethod('ble_stopScan');
    } catch (_) {}
  }

  /// Check if BLE scanning is currently active.
  static Future<bool> isScanning() async {
    try {
      final result = await _channel.invokeMethod('ble_isScanning');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Connect to a BLE device by MAC address.
  static Future<bool> connect(String address, {bool autoConnect = false}) async {
    try {
      final result = await _channel
          .invokeMethod('ble_connect', {'address': address, 'autoConnect': autoConnect});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Disconnect from the current BLE device.
  static Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('ble_disconnect');
    } catch (_) {}
  }

  /// Get list of connected BLE devices (map with address + name).
  static Future<List<Map<String, dynamic>>> getConnectedDevices() async {
    try {
      final result = await _channel.invokeMethod('ble_getConnectedDevices');
      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  /// Get list of discovered BLE device addresses from the last scan.
  static Future<List<String>> getDiscoveredDevices() async {
    try {
      final result = await _channel.invokeMethod('ble_getDiscoveredDevices');
      if (result is List) {
        return result.cast<String>();
      }
    } catch (_) {}
    return [];
  }
}