import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class ColorUtils {
  static final LinkedHashMap<String, Color> _urlCache = LinkedHashMap<String, Color>();
  static final LinkedHashMap<String, Color> _trackIdCache = LinkedHashMap<String, Color>();
  static const int _maxCacheSize = 200;

  /// Возвращает цвет для трека. Сначала смотрит кэш по trackId,
  /// потом по URL обложки, потом извлекает из изображения.
  /// Рекомендуется использовать именно этот метод, когда trackId известен.
  static Future<Color> extractDominantColorForTrack({
    required String trackId,
    required String imageUrl,
    Color fallback = const Color(0xFFFF3B5C),
    CancelToken? cancelToken,
  }) async {
    if (trackId.isEmpty) {
      return extractDominantColor(
        imageUrl,
        fallback: fallback,
        cancelToken: cancelToken,
      );
    }

    // 1) in-memory trackId кэш
    if (_trackIdCache.containsKey(trackId)) {
      final c = _trackIdCache[trackId]!;
      _trackIdCache.remove(trackId);
      _trackIdCache[trackId] = c; // LRU touch
      return c;
    }

    // 2) persistent prefs по trackId
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedHex = prefs.getString('track_color_$trackId');
      if (cachedHex != null) {
        final c = Color(int.parse(cachedHex));
        _addToTrackCache(trackId, c);
        return c;
      }
    } catch (_) {}

    // 3) извлекаем через URL (там свой кэш)
    final color = await extractDominantColor(
      imageUrl,
      fallback: fallback,
      cancelToken: cancelToken,
    );

    _addToTrackCache(trackId, color);
    try {
      final prefs = await SharedPreferences.getInstance();
      unawaited(prefs.setString(
        'track_color_$trackId',
        color.toARGB32().toRadixString(16),
      ));
    } catch (_) {}
    return color;
  }

  static void _addToTrackCache(String trackId, Color color) {
    if (_trackIdCache.length >= _maxCacheSize) {
      _trackIdCache.remove(_trackIdCache.keys.first);
    }
    _trackIdCache[trackId] = color;
  }

  static Future<Color> extractDominantColor(
    String imageUrl, {
    Color fallback = const Color(0xFFFF3B5C),
    CancelToken? cancelToken,
  }) async {
    if (_urlCache.containsKey(imageUrl)) {
      final color = _urlCache[imageUrl]!;
      _urlCache.remove(imageUrl);
      _urlCache[imageUrl] = color;
      return color;
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedColorHex = prefs.getString('color_$imageUrl');
    if (cachedColorHex != null) {
      try {
        final color = Color(int.parse(cachedColorHex));
        _addToUrlCache(imageUrl, color);
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

      _addToUrlCache(imageUrl, color);
      unawaited(
        prefs.setString('color_$imageUrl', color.toARGB32().toRadixString(16)),
      );
      return color;
    } catch (e) {
      _addToUrlCache(imageUrl, fallback);
      return fallback;
    }
  }

  static void _addToUrlCache(String key, Color color) {
    if (_urlCache.length >= _maxCacheSize) {
      _urlCache.remove(_urlCache.keys.first);
    }
    _urlCache[key] = color;
  }

  static String _toThumbnailUrl(String url) {
    return url.replaceFirst('200x200', '100x100');
  }
}

class CancelToken {
  bool isCancelled = false;
  void cancel() => isCancelled = true;
}