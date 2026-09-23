import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/cache_repository.dart';

class CacheEntry {
  final String trackId;
  final String filePath;
  final String title;
  final String artist;
  final String cover;
  final bool isPinned;
  final int sizeBytes;
  final DateTime cachedAt;

  const CacheEntry({
    required this.trackId,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.cover,
    required this.isPinned,
    required this.sizeBytes,
    required this.cachedAt,
  });

  Map<String, String> toUiMap() => {
        'title': title,
        'artist': artist,
        'cover': cover,
        'trackId': trackId,
        'url': filePath,
        'cached': 'true',
        'isFavorite': 'true',
      };

  factory CacheEntry.fromRow(CacheRow r) => CacheEntry(
        trackId: r.trackId,
        filePath: r.filePath,
        title: r.title,
        artist: r.artist,
        cover: r.cover,
        isPinned: r.isPinned,
        sizeBytes: r.sizeBytes,
        cachedAt: r.cachedAt,
      );

  CacheRow toRow() => CacheRow(
        trackId: trackId,
        filePath: filePath,
        title: title,
        artist: artist,
        cover: cover,
        isPinned: isPinned,
        sizeBytes: sizeBytes,
        cachedAt: cachedAt,
      );
}

class CacheStats {
  final int pinnedCount;
  final int tempCount;
  final int pinnedBytes;
  final int tempBytes;

  const CacheStats({
    required this.pinnedCount,
    required this.tempCount,
    required this.pinnedBytes,
    required this.tempBytes,
  });

  int get totalCount => pinnedCount + tempCount;
  int get totalBytes => pinnedBytes + tempBytes;
  double get pinnedMb => pinnedBytes / (1024 * 1024);
  double get tempMb => tempBytes / (1024 * 1024);
  double get totalMb => totalBytes / (1024 * 1024);
}

class TrackCacheManager extends ChangeNotifier {
  final Future<List<int>> Function(String trackId) _downloader;

  TrackCacheManager({
    required Future<List<int>> Function(String trackId) downloader,
  }) : _downloader = downloader;

  static const int _maxTempTracks = 10;
  static const String _legacyPrefsKey = 'cache_entries_v2';
  static const String _legacyPinnedKey = 'pinned_tracks';
  static const String _legacyMetaKey = 'cached_tracks_metadata';

  final CacheRepository _repo = CacheRepository();

  final Map<String, CacheEntry> _pinned = {};
  final LinkedHashMap<String, CacheEntry> _temp = LinkedHashMap();
  final Map<String, Completer<String?>> _pending = {};

  bool _disposed = false;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool isDownloading(String trackId) => _pending.containsKey(trackId);
  List<String> get activeDownloadIds => _pending.keys.toList(growable: false);
  int get activeDownloadCount => _pending.length;

  List<CacheEntry> get pinnedEntries => _pinned.values.toList(growable: false);
  List<CacheEntry> get tempEntries => _temp.values.toList(growable: false);

  // ---------- Инициализация ----------

  Future<void> init() async {
    if (_initialized) return;
    await _migrateFromPrefsIfNeeded();
    await _restoreFromDb();
    await _validateFiles();
    _initialized = true;
    if (!_disposed) notifyListeners();
  }

  /// Миграция с v2 prefs (JSON-строки в List<String>)
  /// и ещё более старых pinned_tracks/cached_tracks_metadata.
  Future<void> _migrateFromPrefsIfNeeded() async {
    final dbEmpty = await _repo.isEmpty();
    if (!dbEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    // 1) Новый формат: cache_entries_v2
    final v2 = prefs.getStringList(_legacyPrefsKey);
    if (v2 != null && v2.isNotEmpty) {
      for (final str in v2) {
        try {
          final raw = jsonDecode(str) as Map<String, dynamic>;
          final row = CacheRow(
            trackId: raw['trackId'] as String,
            filePath: raw['filePath'] as String,
            title: raw['title'] as String? ?? '',
            artist: raw['artist'] as String? ?? '',
            cover: raw['cover'] as String? ?? '',
            isPinned: raw['isPinned'] as bool? ?? false,
            sizeBytes: raw['sizeBytes'] as int? ?? 0,
            cachedAt: DateTime.tryParse(raw['cachedAt'] as String? ?? '') ??
                DateTime.now(),
          );
          await _repo.upsert(row);
        } catch (_) {}
      }
      await prefs.remove(_legacyPrefsKey);
      debugPrint('CacheManager: migrated from prefs v2');
      return;
    }

    // 2) Совсем старый формат
    final oldPinned = prefs.getStringList(_legacyPinnedKey) ?? [];
    final oldMeta = prefs.getStringList(_legacyMetaKey) ?? [];
    if (oldPinned.isEmpty && oldMeta.isEmpty) return;

    final metaById = <String, Map<String, dynamic>>{};
    for (final str in oldMeta) {
      try {
        final raw = jsonDecode(str) as Map<String, dynamic>;
        final id = raw['trackId']?.toString();
        if (id != null) metaById[id] = raw;
      } catch (_) {}
    }

    final docsDir = await getApplicationDocumentsDirectory();
    for (final trackId in oldPinned) {
      final meta = metaById[trackId];
      if (meta == null) continue;

      final candidates = [
        File('${docsDir.path}/$trackId.mp3'),
        File('${docsDir.path}/cache/$trackId.mp3'),
      ];
      File? found;
      for (final f in candidates) {
        if (await f.exists()) {
          found = f;
          break;
        }
      }
      if (found == null) continue;

      final size = await found.length();
      await _repo.upsert(CacheRow(
        trackId: trackId,
        filePath: found.path,
        title: meta['title']?.toString() ?? '',
        artist: meta['artist']?.toString() ?? '',
        cover: meta['cover']?.toString() ?? '',
        isPinned: true,
        sizeBytes: size,
        cachedAt: DateTime.now(),
      ));
    }

    await prefs.remove(_legacyPinnedKey);
    await prefs.remove(_legacyMetaKey);
    debugPrint('CacheManager: migrated from legacy prefs');
  }

  Future<void> _restoreFromDb() async {
    final rows = await _repo.getAll();
    for (final r in rows) {
      final entry = CacheEntry.fromRow(r);
      if (entry.isPinned) {
        _pinned[entry.trackId] = entry;
      } else {
        _temp[entry.trackId] = entry;
      }
    }
  }

  Future<void> _validateFiles() async {
    final broken = <String>[];
    for (final entry in [..._pinned.values, ..._temp.values]) {
      if (!await File(entry.filePath).exists()) broken.add(entry.trackId);
    }
    if (broken.isEmpty) return;
    for (final id in broken) {
      _pinned.remove(id);
      _temp.remove(id);
    }
    await _repo.deleteMany(broken);
    debugPrint('CacheManager: removed ${broken.length} broken entries');
  }

  bool isPinned(String trackId) => _pinned.containsKey(trackId);
  bool isTemp(String trackId) => _temp.containsKey(trackId);
  bool isCached(String trackId) =>
      _pinned.containsKey(trackId) || _temp.containsKey(trackId);

  Future<String?> get(String trackId) async {
    final pinned = _pinned[trackId];
    if (pinned != null) {
      if (await File(pinned.filePath).exists()) return pinned.filePath;
      _pinned.remove(trackId);
      await _repo.delete(trackId);
    }
    final temp = _temp[trackId];
    if (temp != null) {
      if (await File(temp.filePath).exists()) {
        _temp.remove(trackId);
        _temp[trackId] = temp;
        return temp.filePath;
      }
      _temp.remove(trackId);
      await _repo.delete(trackId);
    }
    return null;
  }

  // ---------- Pin / Unpin ----------

  Future<bool> pin({
    required String trackId,
    required String title,
    required String artist,
    required String cover,
  }) async {
    if (_pinned.containsKey(trackId)) return true;

    final path = await _downloadAndSave(trackId);
    if (path == null) return false;

    final size = await File(path).length();
    final entry = CacheEntry(
      trackId: trackId,
      filePath: path,
      title: title,
      artist: artist,
      cover: cover,
      isPinned: true,
      sizeBytes: size,
      cachedAt: DateTime.now(),
    );
    _temp.remove(trackId);
    _pinned[trackId] = entry;
    await _repo.upsert(entry.toRow());
    if (!_disposed) notifyListeners();
    return true;
  }

  Future<void> unpin(String trackId) async {
    final entry = _pinned.remove(trackId);
    if (entry == null) return;
    try {
      final f = File(entry.filePath);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('unpin delete error: $e');
    }
    await _repo.delete(trackId);
    if (!_disposed) notifyListeners();
  }

  // ---------- Temp cache ----------

  Future<String?> cacheTemp({
    required String trackId,
    required String title,
    required String artist,
    required String cover,
  }) async {
    final existing = await get(trackId);
    if (existing != null) return existing;

    final path = await _downloadAndSave(trackId);
    if (path == null) return null;

    final size = await File(path).length();
    final entry = CacheEntry(
      trackId: trackId,
      filePath: path,
      title: title,
      artist: artist,
      cover: cover,
      isPinned: false,
      sizeBytes: size,
      cachedAt: DateTime.now(),
    );
    _temp[trackId] = entry;
    await _repo.upsert(entry.toRow());
    await _enforceTempLimit();
    if (!_disposed) notifyListeners();
    return path;
  }

  Future<void> _enforceTempLimit() async {
    final removed = <String>[];
    while (_temp.length > _maxTempTracks) {
      final oldestKey = _temp.keys.first;
      final entry = _temp.remove(oldestKey);
      if (entry != null) {
        removed.add(oldestKey);
        try {
          File(entry.filePath).delete();
        } catch (_) {}
      }
    }
    if (removed.isNotEmpty) {
      await _repo.deleteMany(removed);
    }
  }

  // ---------- Очистка ----------

  Future<void> clearTemp() async {
    final entries = _temp.values.toList();
    _temp.clear();
    for (final e in entries) {
      try {
        final f = File(e.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _repo.clearTemp();
    if (!_disposed) notifyListeners();
  }

  Future<void> clearAll() async {
    final all = [..._pinned.values, ..._temp.values];
    _pinned.clear();
    _temp.clear();
    for (final e in all) {
      try {
        final f = File(e.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _repo.clearAll();
    if (!_disposed) notifyListeners();
  }

  // ---------- Статистика ----------

  CacheStats getStats() {
    int pinnedBytes = 0;
    for (final e in _pinned.values) {
      pinnedBytes += e.sizeBytes;
    }
    int tempBytes = 0;
    for (final e in _temp.values) {
      tempBytes += e.sizeBytes;
    }
    return CacheStats(
      pinnedCount: _pinned.length,
      tempCount: _temp.length,
      pinnedBytes: pinnedBytes,
      tempBytes: tempBytes,
    );
  }

  // ---------- Загрузка ----------

  Future<String?> _downloadAndSave(String trackId) async {
    if (_pending.containsKey(trackId)) {
      return _pending[trackId]!.future;
    }
    final completer = Completer<String?>();
    _pending[trackId] = completer;
    if (!_disposed) notifyListeners();

    try {
      final bytes = await _downloader(trackId);
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/cache');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final file = File('${cacheDir.path}/$trackId.mp3');
      await file.writeAsBytes(bytes);
      completer.complete(file.path);
      return file.path;
    } catch (e) {
      debugPrint('CacheManager download error [$trackId]: $e');
      completer.complete(null);
      return null;
    } finally {
      _pending.remove(trackId);
      if (!_disposed) notifyListeners();
    }
  }

  void cancelAllDownloads() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelAllDownloads();
    super.dispose();
  }
}