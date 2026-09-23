import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Единая SQLite-база ArticMuzik.
/// Схема: история, метаданные кэша, состояние очереди.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const int _version = 1;
  static const String _dbName = 'artic_muzik.db';

  Database? _db;
  Completer<Database>? _opening;

  Future<Database> get db async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;

    _opening = Completer<Database>();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, _dbName);
      final database = await openDatabase(
        path,
        version: _version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );
      _db = database;
      _opening!.complete(database);
      return database;
    } catch (e, st) {
      _opening!.completeError(e, st);
      _opening = null;
      rethrow;
    }
  }

  Future<void> init() async {
    await db;
    debugPrint('AppDatabase: ready');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trackId TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL DEFAULT '',
        artist TEXT NOT NULL DEFAULT '',
        cover TEXT NOT NULL DEFAULT '',
        playedAt INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_history_playedAt ON history(playedAt DESC)');

    await db.execute('''
      CREATE TABLE cache_entries (
        trackId TEXT PRIMARY KEY,
        filePath TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        artist TEXT NOT NULL DEFAULT '',
        cover TEXT NOT NULL DEFAULT '',
        isPinned INTEGER NOT NULL DEFAULT 0,
        sizeBytes INTEGER NOT NULL DEFAULT 0,
        cachedAt INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_cache_pinned ON cache_entries(isPinned)');

    await db.execute('''
      CREATE TABLE queue_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        queueJson TEXT NOT NULL,
        currentIndex INTEGER NOT NULL DEFAULT 0,
        positionMs INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Пока миграций нет. Когда появятся — switch по oldVersion.
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}