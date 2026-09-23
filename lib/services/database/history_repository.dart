import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class HistoryRow {
  final String trackId;
  final String title;
  final String artist;
  final String cover;
  final DateTime playedAt;

  const HistoryRow({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.cover,
    required this.playedAt,
  });

  factory HistoryRow.fromMap(Map<String, dynamic> m) => HistoryRow(
        trackId: m['trackId'] as String,
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        cover: m['cover'] as String? ?? '',
        playedAt: DateTime.fromMillisecondsSinceEpoch(
          (m['playedAt'] as int?) ?? 0,
        ),
      );
}

class HistoryRepository {
  static const int maxEntries = 100;

  Future<List<HistoryRow>> getAll({int limit = maxEntries}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query(
      'history',
      orderBy: 'playedAt DESC',
      limit: limit,
    );
    return rows.map(HistoryRow.fromMap).toList(growable: false);
  }

  /// Вставляет или обновляет трек в истории.
  /// Если такой уже есть — удаляет старую запись и создаёт новую,
  /// чтобы трек всплыл наверх.
  Future<void> upsert({
    required String trackId,
    required String title,
    required String artist,
    required String cover,
  }) async {
    if (trackId.isEmpty) return;
    final db = await AppDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete('history', where: 'trackId = ?', whereArgs: [trackId]);
      await txn.insert('history', {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'cover': cover,
        'playedAt': now,
      });

      // Обрезаем до лимита
      final count = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM history'),
          ) ??
          0;
      if (count > maxEntries) {
        await txn.rawDelete(
          'DELETE FROM history WHERE id IN ('
          'SELECT id FROM history ORDER BY playedAt ASC LIMIT ?'
          ')',
          [count - maxEntries],
        );
      }
    });
  }

  Future<void> clear() async {
    final db = await AppDatabase.instance.db;
    await db.delete('history');
  }

  Future<bool> isEmpty() async {
    final db = await AppDatabase.instance.db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM history'),
    );
    return (count ?? 0) == 0;
  }
}