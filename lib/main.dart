import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_screen.dart';
import 'services/audio_handler.dart';
import 'services/yandex/yandex_auth_service.dart';
import 'services/yandex/yandex_audio_provider.dart';
import 'screens/yandex_token_input_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/artic_theme.dart';
import 'theme/theme_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Scaffold(
      backgroundColor: ArticTheme.backgroundDeep,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: ArticTheme.accent, size: 64),
            const SizedBox(height: 16),
            Text(
              'Произошла ошибка',
              style: TextStyle(color: ArticTheme.primary, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              details.exception.toString(),
              style: TextStyle(color: ArticTheme.secondary, fontSize: 12),
              textAlign: TextAlign.center,
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

  final prefs = await SharedPreferences.getInstance();
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

  try {
    await audioHandler.setTracksAndPlay([], 0);
    await Future.delayed(const Duration(milliseconds: 100));
  } catch (e) {
    debugPrint('Warmup error: $e');
  }

  final yandexAuth = YandexAuthService();

  final themeNotifier = ThemeNotifier();
  await themeNotifier.loadTheme();

  final lifecycleObserver = _AppLifecycleObserver(audioHandler);
  WidgetsBinding.instance.addObserver(lifecycleObserver);

  runApp(
    MultiProvider(
      providers: [
        Provider<AppAudioHandler>.value(value: audioHandler),
        Provider<YandexAuthService>.value(value: yandexAuth),
        ChangeNotifierProvider(create: (_) => YandexAudioProvider(yandexAuth)),
        ChangeNotifierProvider<ThemeNotifier>.value(value: themeNotifier),
      ],
      child: const ArticMuzikApp(),
    ),
  );
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
    final themeNotifier = Provider.of<ThemeNotifier>(context);

    return MaterialApp(
      title: 'ArticMuzik',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        fontFamily: 'StieglitzSP',
      ),
      // Сплеш теперь отвечает за навигацию, поэтому home всегда SplashScreen
      home: const SplashScreen(),
      // Маршруты оставляем для возможного использования, но сплеш сам управляет переходом
      routes: {
        '/token': (context) => const YandexTokenInputScreen(),
        '/main': (context) => const MainScreen(),
      },
    );
  }
}