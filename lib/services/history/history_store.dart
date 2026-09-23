import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/history_repository.dart';

class PlayHistoryEntry {
  final String trackId;
  final String title;
  final String artist;
  final String cover;
  final DateTime playedAt;

  const PlayHistoryEntry({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.cover,
    required this.playedAt,
  });

  Map<String, String> toUiMap() => {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'cover': cover,
        'url': '',
        'cached': 'false',
        'isFavorite': 'false',
      };

  factory PlayHistoryEntry.fromRow(HistoryRow r) => PlayHistoryEntry(
        trackId: r.trackId,
        title: r.title,
        artist: r.artist,
        cover: r.cover,
        playedAt: r.playedAt,
      );
}

class HistoryStore extends ChangeNotifier {
  static const String _legacyPrefsKey = 'play_history_v1';

  final HistoryRepository _repo = HistoryRepository();
  final List<PlayHistoryEntry> _entries = [];
  bool _disposed = false;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  int get count => _entries.length;
  List<PlayHistoryEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  Future<void> init() async {
    if (_initialized) return;
    await _migrateFromPrefsIfNeeded();
    await _reload();
    _initialized = true;
    if (!_disposed) notifyListeners();
  }

  /// Переносит старый `play_history_v1` (JSON-строки) в БД.
  Future<void> _migrateFromPrefsIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getStringList(_legacyPrefsKey);
    if (legacy == null || legacy.isEmpty) return;

    // Если в БД уже что-то есть — не мигрируем
    final empty = await _repo.isEmpty();
    if (!empty) {
      await prefs.remove(_legacyPrefsKey);
      return;
    }

    for (final str in legacy.reversed) {
      // reversed — чтобы последние записи оказались первыми
      try {
        final map = jsonDecode(str) as Map<String, dynamic>;
        await _repo.upsert(
          trackId: map['trackId'] as String,
          title: map['title'] as String? ?? '',
          artist: map['artist'] as String? ?? '',
          cover: map['cover'] as String? ?? '',
        );
      } catch (_) {}
    }
    await prefs.remove(_legacyPrefsKey);
    debugPrint('HistoryStore: migrated from prefs');
  }

  Future<void> _reload() async {
    final rows = await _repo.getAll();
    _entries
      ..clear()
      ..addAll(rows.map(PlayHistoryEntry.fromRow));
  }

  Future<void> add({
    required String trackId,
    required String title,
    required String artist,
    required String cover,
  }) async {
    if (trackId.isEmpty) return;
    await _repo.upsert(
      trackId: trackId,
      title: title,
      artist: artist,
      cover: cover,
    );
    await _reload();
    if (!_disposed) notifyListeners();
  }

  Future<void> clear() async {
    await _repo.clear();
    _entries.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}