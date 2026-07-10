import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A custom [TileProvider] that caches map tiles to the device's local file
/// system.
///
/// - Online: Downloads tiles from OpenStreetMap and saves them to local disk.
/// - Offline: Serves previously cached tiles from disk — no blank map.
/// - Uncached + Offline: Returns a transparent pixel (no crash/errors).
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  /// The root cache directory on disk.
  static Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/map_tiles');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Build a local file path for a given tile URL.
  static Future<File> _tileFile(String url) async {
    final dir = await _cacheDir();
    final safeName = base64Url.encode(utf8.encode(url));
    return File('${dir.path}/$safeName.png');
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImageProvider(
      url: getTileUrl(coordinates, options),
    );
  }
}

/// Internal [ImageProvider] that resolves tiles from cache first, then network.
class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  final String url;

  const _CachedTileImageProvider({required this.url});

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(key.url, decode),
      scale: 1.0,
      debugLabel: key.url,
    );
  }

  /// Attempt to load a tile: try cache first, fall back to network, save to cache.
  Future<ui.Codec> _loadTile(
      String tileUrl, ImageDecoderCallback decode) async {
    // 1. Try loading from disk cache
    final file = await CachedTileProvider._tileFile(tileUrl);
    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        }
      } catch (_) {
        // Corrupted cache file — delete it
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    // 2. Try loading from network, then save to cache
    try {
      final response = await http.get(Uri.parse(tileUrl));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        // Save to cache in the background
        unawaited(_saveToCache(tileUrl, response.bodyBytes));
        return await decode(
            await ui.ImmutableBuffer.fromUint8List(response.bodyBytes));
      }
    } catch (_) {
      // Network error — fall through
    }

    // 3. If nothing available, return a transparent 1x1 pixel PNG
    //    This prevents any crash or error in the console
    return await decode(
        await ui.ImmutableBuffer.fromUint8List(TileProvider.transparentImage));
  }

  /// Save downloaded tile bytes to disk cache.
  Future<void> _saveToCache(String tileUrl, List<int> bytes) async {
    try {
      final file = await CachedTileProvider._tileFile(tileUrl);
      await file.writeAsBytes(bytes);
    } catch (_) {
      // Silently ignore cache write failures
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _CachedTileImageProvider && url == other.url);

  @override
  int get hashCode => url.hashCode;
}