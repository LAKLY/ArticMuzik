import 'package:flutter/foundation.dart';

/// Тонкий логгер с замером времени между вызовами.
/// Помогает понять, что именно тормозит при переключении вкладок.
class ArticLog {
  static final Stopwatch _sw = Stopwatch()..start();
  static final Map<String, int> _last = {};

  /// Событие: ArticLog.tick('library:build')
  /// Выведет: [+1234ms | Δ56ms] library:build
  static void tick(String tag, [Object? data]) {
    final now = _sw.elapsedMilliseconds;
    final prev = _last[tag] ?? 0;
    final delta = now - prev;
    _last[tag] = now;
    if (kDebugMode) {
      final suffix = data != null ? '  $data' : '';
      debugPrint('[+${now}ms | Δ${delta}ms] $tag$suffix');
    }
  }

  /// Просто событие без дельты: ArticLog.evt('user:tabSwitch', 0)
  static void evt(String tag, [Object? data]) {
    if (kDebugMode) {
      final suffix = data != null ? '  $data' : '';
      debugPrint('[+${_sw.elapsedMilliseconds}ms] $tag$suffix');
    }
  }
}