import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class CacheRow {
  final String trackId;
  final String filePath;
  final String title;
  final String artist;
  final String cover;
  final bool isPinned;
  final int sizeBytes;
  final DateTime cachedAt;

  const CacheRow({
    required this.trackId,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.cover,
    required this.isPinned,
    required this.sizeBytes,
    required this.cachedAt,
  });

  factory CacheRow.fromMap(Map<String, dynamic> m) => CacheRow(
        trackId: m['trackId'] as String,
        filePath: m['filePath'] as String,
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        cover: m['cover'] as String? ?? '',
        isPinned: (m['isPinned'] as int? ?? 0) == 1,
        sizeBytes: m['sizeBytes'] as int? ?? 0,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(
          (m['cachedAt'] as int?) ?? 0,
        ),
      );

  Map<String, dynamic> toMap() => {
        'trackId': trackId,
        'filePath': filePath,
        'title': title,
        'artist': artist,
        'cover': cover,
        'isPinned': isPinned ? 1 : 0,
        'sizeBytes': sizeBytes,
        'cachedAt': cachedAt.millisecondsSinceEpoch,
      };
}

class CacheRepository {
  Future<List<CacheRow>> getAll() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('cache_entries', orderBy: 'cachedAt DESC');
    return rows.map(CacheRow.fromMap).toList(growable: false);
  }

  Future<List<CacheRow>> getByType({required bool pinned}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query(
      'cache_entries',
      where: 'isPinned = ?',
      whereArgs: [pinned ? 1 : 0],
      orderBy: 'cachedAt DESC',
    );
    return rows.map(CacheRow.fromMap).toList(growable: false);
  }

  Future<void> upsert(CacheRow row) async {
    final db = await AppDatabase.instance.db;
    await db.insert(
      'cache_entries',
      row.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String trackId) async {
    final db = await AppDatabase.instance.db;
    await db.delete('cache_entries', where: 'trackId = ?', whereArgs: [trackId]);
  }

  Future<void> deleteMany(List<String> trackIds) async {
    if (trackIds.isEmpty) return;
    final db = await AppDatabase.instance.db;
    final placeholders = List.filled(trackIds.length, '?').join(',');
    await db.delete(
      'cache_entries',
      where: 'trackId IN ($placeholders)',
      whereArgs: trackIds,
    );
  }

  Future<void> clearTemp() async {
    final db = await AppDatabase.instance.db;
    await db.delete('cache_entries', where: 'isPinned = 0');
  }

  Future<void> clearAll() async {
    final db = await AppDatabase.instance.db;
    await db.delete('cache_entries');
  }

  Future<bool> isEmpty() async {
    final db = await AppDatabase.instance.db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM cache_entries'),
    );
    return (count ?? 0) == 0;
  }
}