import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class QueueState {
  final String queueJson;
  final int currentIndex;
  final int positionMs;

  const QueueState({
    required this.queueJson,
    required this.currentIndex,
    required this.positionMs,
  });
}

class QueueRepository {
  Future<QueueState?> load() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('queue_state', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    final m = rows.first;
    return QueueState(
      queueJson: m['queueJson'] as String? ?? '',
      currentIndex: m['currentIndex'] as int? ?? 0,
      positionMs: m['positionMs'] as int? ?? 0,
    );
  }

  Future<void> save({
    required String queueJson,
    required int currentIndex,
    required int positionMs,
  }) async {
    final db = await AppDatabase.instance.db;
    await db.insert(
      'queue_state',
      {
        'id': 1,
        'queueJson': queueJson,
        'currentIndex': currentIndex,
        'positionMs': positionMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clear() async {
    final db = await AppDatabase.instance.db;
    await db.delete('queue_state');
  }

  Future<bool> isEmpty() async {
    final db = await AppDatabase.instance.db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM queue_state'),
    );
    return (count ?? 0) == 0;
  }
}