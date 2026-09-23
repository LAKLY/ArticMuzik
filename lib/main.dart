import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_screen.dart';
import 'services/audio_handler.dart';
import 'services/database/app_database.dart';
import 'services/database/queue_repository.dart';
import 'services/yandex/yandex_auth_service.dart';
import 'services/yandex/yandex_audio_provider.dart';
import 'screens/yandex_token_input_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/artic_theme.dart';
import 'theme/theme_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('ErrorWidget: ${details.exception}');
    return Scaffold(
      backgroundColor: ArticTheme.backgroundDeep,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: ArticTheme.accent, size: 64),
            const SizedBox(height: 16),
            Text(
              'Что-то пошло не так',
              style: TextStyle(color: ArticTheme.primary, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Попробуйте перезапустить приложение',
                style: TextStyle(color: ArticTheme.secondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  };

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // SQLite должна быть готова до CacheManager / HistoryStore / AudioHandler
  await AppDatabase.instance.init();

  final prefs = await SharedPreferences.getInstance();

  // Миграция очереди из prefs в БД (один раз, до создания handler'а).
  await _migrateQueueIfNeeded(prefs);

  final audioHandler = AppAudioHandler(prefs: prefs);

  await AudioService.init(
    builder: () => audioHandler,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.articmuzik.audio',
      androidNotificationChannelName: 'ArticMuzik',
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_notification',
    ),
  );

  // Детерминированная инициализация вместо setTracksAndPlay([], 0)
  await audioHandler.initialize();

  final yandexAuth = YandexAuthService();

  final themeNotifier = ThemeNotifier();
  await themeNotifier.loadTheme();

  // Создаём провайдер заранее — нужно связать его с audioHandler
  final yandexProvider = YandexAudioProvider(yandexAuth);

  // Связка: когда трек стартует — preload следующего + запись в историю
  audioHandler.onTrackStarted = (currentItem, nextTrackId) {
    yandexProvider.preloadNextTrack(nextTrackId);

    final trackId = currentItem.extras?['trackId'] as String?;
    if (trackId != null && trackId.isNotEmpty) {
      yandexProvider.scheduleHistoryAdd(
        trackId: trackId,
        title: currentItem.title,
        artist: currentItem.artist ?? '',
        cover: currentItem.artUri?.toString() ?? '',
      );
    }
  };

  final lifecycleObserver = _AppLifecycleObserver(audioHandler);
  WidgetsBinding.instance.addObserver(lifecycleObserver);

  runApp(
    MultiProvider(
      providers: [
        Provider<AppAudioHandler>.value(value: audioHandler),
        Provider<YandexAuthService>.value(value: yandexAuth),
        ChangeNotifierProvider<YandexAudioProvider>.value(value: yandexProvider),
        ChangeNotifierProvider<ThemeNotifier>.value(value: themeNotifier),
      ],
      child: const ArticMuzikApp(),
    ),
  );
}

/// Одноразовая миграция очереди из SharedPreferences в SQLite.
/// Выполняется ДО создания AppAudioHandler, чтобы не конфликтовать
/// с инициализацией платформенных стримов.
Future<void> _migrateQueueIfNeeded(SharedPreferences prefs) async {
  final repo = QueueRepository();

  // Если в БД уже что-то есть — миграция не нужна
  final existing = await repo.load();
  if (existing != null && existing.queueJson.isNotEmpty) {
    // На всякий случай чистим legacy ключи, если они ещё лежат
    if (prefs.containsKey('queue_items')) {
      await prefs.remove('queue_items');
      await prefs.remove('queue_index');
      await prefs.remove('position_ms');
    }
    return;
  }

  final legacyList = prefs.getStringList('queue_items');
  if (legacyList == null || legacyList.isEmpty) return;

  final queueJson = json.encode(legacyList);
  final savedIndex = prefs.getInt('queue_index') ?? 0;
  final savedPositionMs = prefs.getInt('position_ms') ?? 0;

  await repo.save(
    queueJson: queueJson,
    currentIndex: savedIndex,
    positionMs: savedPositionMs,
  );

  await prefs.remove('queue_items');
  await prefs.remove('queue_index');
  await prefs.remove('position_ms');
  debugPrint('Queue migration: migrated from prefs');
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final AppAudioHandler audioHandler;
  _AppLifecycleObserver(this.audioHandler);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      audioHandler.saveStateNow();
    }
  }
}

class ArticMuzikApp extends StatelessWidget {
  const ArticMuzikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ArticMuzik',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        fontFamily: 'StieglitzSP',
      ),
      home: const SplashScreen(),
      routes: {
        '/token': (context) => const YandexTokenInputScreen(),
        '/main': (context) => const MainScreen(),
      },
    );
  }
}