import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class ColorUtils {
  static final LinkedHashMap<String, Color> _cache = LinkedHashMap<String, Color>();
  static const int _maxCacheSize = 100;

  static Future<Color> extractDominantColor(
    String imageUrl, {
    Color fallback = const Color(0xFFFF3B5C),
    CancelToken? cancelToken,
  }) async {
    if (_cache.containsKey(imageUrl)) {
      final color = _cache[imageUrl]!;
      _cache.remove(imageUrl);
      _cache[imageUrl] = color;
      return color;
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedColorHex = prefs.getString('color_$imageUrl');
    if (cachedColorHex != null) {
      try {
        final color = Color(int.parse(cachedColorHex));
        _addToCache(imageUrl, color);
        return color;
      } catch (e) {}
    }

    if (cancelToken?.isCancelled == true) return fallback;

    try {
      final thumbnailUrl = _toThumbnailUrl(imageUrl);
      final imageProvider = NetworkImage(thumbnailUrl);
      final completer = Completer<ui.Image>();
      
      final stream = imageProvider.resolve(const ImageConfiguration());
      final listener = ImageStreamListener(
        (image, synchronousCall) {
          completer.complete(image.image);
        },
        onError: (error, stackTrace) {
          completer.completeError(error);
        },
      );
      stream.addListener(listener);

      final ui.Image image = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Image load timeout'),
      );
      stream.removeListener(listener);

      if (cancelToken?.isCancelled == true) return fallback;

      final generator = await PaletteGenerator.fromImage(image);
      final color = generator.dominantColor?.color ?? fallback;
      
      _addToCache(imageUrl, color);
      unawaited(prefs.setString('color_$imageUrl', color.toARGB32().toRadixString(16)));
      return color;
    } catch (e) {
      _addToCache(imageUrl, fallback);
      return fallback;
    }
  }

  static void _addToCache(String key, Color color) {
    if (_cache.length >= _maxCacheSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
    _cache[key] = color;
  }

  static String _toThumbnailUrl(String url) {
    return url.replaceFirst('200x200', '100x100');
  }
}

class CancelToken {
  bool isCancelled = false;
  void cancel() => isCancelled = true;
}