import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import '../theme/artic_theme.dart';
import '../services/audio_handler.dart';
import '../services/yandex/yandex_audio_provider.dart';
import '../services/yandex/yandex_auth_service.dart';
import 'main_screen.dart';
import 'yandex_token_input_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isLoading = true;
  String? _errorMessage;

  late AppAudioHandler _audioHandler;
  late YandexAudioProvider _yandexProvider;
  late YandexAuthService _authService;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      _audioHandler = Provider.of<AppAudioHandler>(context, listen: false);
      _yandexProvider = Provider.of<YandexAudioProvider>(context, listen: false);
      _authService = Provider.of<YandexAuthService>(context, listen: false);

      await _audioHandler.ready;

      final isAuthorized = await _authService.isAuthorized();
      if (!isAuthorized) {
        _navigateToTokenScreen();
        return;
      }

      await _yandexProvider.init();

      if (_yandexProvider.error != null) {
        if (_yandexProvider.error!.contains('токен') ||
            _yandexProvider.error!.contains('Token')) {
          await _authService.logout();
          _navigateToTokenScreen();
          return;
        } else {
          setState(() {
            _errorMessage = _yandexProvider.error;
            _isLoading = false;
          });
          return;
        }
      }

      _navigateToMainScreen();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigateToMainScreen() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  void _navigateToTokenScreen() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const YandexTokenInputScreen()),
    );
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ваш ASCII-арт – вставляйте сюда
                _buildAsciiArtPlaceholder(screenWidth, screenHeight),

                const SizedBox(height: 40),

                if (_errorMessage != null)
                  _buildErrorWidget()
                else if (_isLoading)
                  _buildLoadingIndicator()
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),

          if (_isLoading)
            Positioned(
              bottom: 40,
              left: 30,
              right: 30,
              child: _buildProgressBar(),
            ),
        ],
      ),
    );
  }

  /// Виджет для ASCII-арта (адаптивный, без ошибок ParentData)
  Widget _buildAsciiArtPlaceholder(double width, double height) {
    // Подбираем размер шрифта в зависимости от высоты экрана
    double fontSize = (height / 40).clamp(8.0, 24.0);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final opacity = _animationController.value;
        return Opacity(
          opacity: opacity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              // ЗДЕСЬ ВАШ ASCII-АРТ (замените строку на вашу переменную)
              r'''
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⡿⠿⠿⠿⠿⠿⠿⠿⠿⠿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢟⢉⢀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣷⣝⢶⣜⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠏⠄⢀⣴⣿⣿⣿⣿⡸⣿⣦⢻⣷⣿⣿⣿⣷⣝⢶⣜⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠏⠄⣰⣿⣿⣿⣿⣿⣿⣷⣿⣿⡽⣿⣿⣿⣿⣿⣿⣧⡹⣦⡙⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠄⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡝⣿⣿⣿⣿⣿⣿⣿⣌⢳⣌⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡜⣿⣿⣿⣿⣿⣿⣿⣷⡙⢷⣦⡙⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡜⢿⣿⣿⣿⣿⣿⣿⣿⣎⢿⣍⠢⢹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠄⠄⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡌⣿⣿⣿⣿⣿⣏⢻⣿⢧⢻⡄⠄⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠄⠄⣿⣿⣿⣿⣿⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⢳⢸⡿⣿⣿⠻⣿⡆⠉⠈⡌⡇⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⠄⣿⢿⣿⣿⣿⡇⢿⣿⣿⣿⣿⣿⣿⣿⣿⠘⢀⡇⣿⣿⠄⠹⢳⠄⠄⠄⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⠄⠘⠄⠙⠿⣿⣿⡀⣝⡻⠟⠛⠿⠍⢉⠥⠂⡸⢡⣿⣿⠄⠄⠈⠄⠄⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⠄⠄⠄⠄⠄⠐⢶⢚⣛⣉⣩⣼⣿⡃⠄⠄⠈⠄⠉⠘⠁⠄⠄⣀⣤⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⡀⠄⠄⠄⠄⠄⠄⠄⠙⢶⣾⣿⡿⢟⣥⣶⣦⣤⣄⠠⣤⣤⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣤⣄⠄⠄⠄⠄⠄⢀⣀⣬⡍⣶⣿⣿⣿⣿⣿⣿⣄⠹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢣⣿⣿⣿⣿⣿⣿⣿⣿⣷⣌⡙⠛⠟⠛⠛⠛⠛⠛⠻⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⠛⠛⠛⠛⠫⠵⢿⣿⣿⡿⢿⡿⠿⢟⣛⣭⣵⣶⣾⣿⣿⣿⣿⣿⣷⣶⣶⣄⠈⢻⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠉⠄⠄⠄⠄⠄⠄⠄⠄⠄⡀⣴⢰⣶⣶⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⡄⢹⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠃⠄⠄⠄⠄⠄⠄⠄⣀⣤⠄⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠄⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠃⠄⠄⠄⠄⠄⠄⣴⣾⣿⠟⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡆⢸⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠄⠄⠄⠄⠄⠄⢠⣿⣿⡿⢡⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇⢈⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⠄⠄⠄⠄⢀⣿⣿⣿⠏⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢻⣿⣿⣿⣿⣿⣿⣿⣿⢸⡜⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠃⠄⠄⠄⠄⠄⡘⢛⠛⠛⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠈⣿⠋⣿⣿⣿⣿⣿⠇⢸⣿⡸⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠄⠄⠄⠄⠄⢠⣿⣿⣿⣷⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠄⣿⠄⣿⣿⣿⣿⣿⡇⣸⣿⣇⢿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⠄⠄⠄⠄⠄⠈⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠄⠄⠄⣿⣿⣿⣿⣿⠃⣿⣿⣿⢸⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠃⠄⠄⠄⠄⠄⠄⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠁⠄⠄⠄⢿⣿⣿⣿⡇⢰⣿⣿⣿⡇⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⠄⠄⠄⠄⠄⠄⠄⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠇⠄⠄⠄⠄⢸⣿⣿⣿⣇⡸⢿⣿⣿⣷⢻⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠄⠄⠄⠄⠄⠄⠄⠄⠄⠏⠿⠹⠋⠇⠿⠸⠇⠻⠸⠋⠏⡏⣿⢻⡟⣿⣿⣿⣿⣧⣦⡄⠄⠄⠄⢸⣿⣿⣿⡿⠁⣼⣿⣿⣿⢸⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠃⠄⠄⠄⠄⠄⠄⠄⠄⢀⣠⣴⣶⣶⣷⢷⣷⣷⣷⣷⣷⣦⣄⠉⠘⠁⠏⣿⠟⣿⣿⣿⣿⠄⠄⠄⢸⣿⣿⡿⠁⢠⣿⣿⣿⣿⡇⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠄⠄⠄⠄⠄⠄⠄⠄⢰⣿⣿⣿⣿⣿⠇⣼⣿⣿⣿⣿⣿⣿⣿⣿⣶⣤⡀⠉⠺⢻⢟⡿⡿⠄⠄⠄⠘⣿⡿⠁⢀⣾⣿⣿⣿⣿⣷⢹⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⠄⠄⠄⠄⠄⠄⠄⣼⣿⣿⣿⣿⡟⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡷⠄⠈⠘⠃⠁⠄⠄⠄⠄⠉⠄⠄⠈⠋⠁⢀⣼⣿⣿⡏⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠏⠄⠄⠄⣀⣀⠄⠄⢀⣾⣿⣿⣿⣿⣿⣧⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠁⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣀⣴⣾⣿⣿⣿⣿⣷⢻
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⠄⠄⠒⠋⠁⠄⢀⣴⣿⣿⣿⣿⣿⣿⡿⢙⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣤⣾⣿⣿⣿⣿⣿⣿⣿⣿⢸
⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠇⠄⠄⣀⣤⠄⣠⣿⣿⣿⣿⣿⣿⣿⣿⣤⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⣄⣀⣀⣀⣀⡀⠄⣀⠄⠄⠘⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⢸
⣿⣿⣿⣿⣿⣿⣿⣿⠏⠄⠄⠄⠛⠉⢠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠸⣿⣿⣿⣿⣿⣿⡟⠄⠄⠄⠄⣸⣿⣿⠿⠟⠛⣻⣿⡏⣾
⣿⣿⣿⣿⣿⣿⣿⣿⠄⠄⠄⠄⠄⣤⠈⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⢿⣿⣿⣿⣿⠏⠄⢀⣤⣴⡾⠛⠉⢀⣠⣴⣿⣿⣿⢸⣿
⣿⣿⣿⣿⣿⣿⣿⣿⠄⠄⠄⠄⣼⣿⣆⠈⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠘⣿⣿⣿⣿⠄⠄⠛⠿⠿⣿⣶⣶⣿⣿⣿⣿⣿⣿⢸⣿
⣿⣿⣿⣿⣿⣿⣿⠟⠄⠄⠄⣸⣿⣿⣿⣆⠄⠈⠻⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⡫⣁⣤⣶⢹⣿⣿⣿⡄⠄⠄⠄⠄⠄⠄⠉⠉⠛⠛⠿⣿⣿⡇⣿
⣿⣿⣿⣿⣿⣿⣯⠄⠄⠄⢠⣿⣿⣿⣿⣿⣆⠄⠄⠄⠈⢙⡛⠿⠿⣿⣿⣿⣿⣿⠿⠿⢟⠛⢯⠅⣠⣵⣾⣿⣿⣿⡇⣿⣿⣿⣇⠄⠄⠄⠈⠛⠿⣶⣶⣶⣤⣤⢿⢏⣼⣿
⣿⣿⣿⣿⣿⣿⡿⣰⣿⢢⣿⣿⣿⣿⣿⣿⣿⣆⠄⠄⠄⣷⣶⣿⣭⣥⣤⣤⣭⣭⣶⡶⠂⣐⣵⣾⣿⣿⣿⣿⣿⣿⣷⢹⣿⣿⣿⠄⠄⠄⠄⡀⠄⠄⠉⠛⢿⣷⢎⣾⣿⣿
⣿⣿⣿⣿⣿⣿⢱⣿⡟⣼⣿⣿⣿⣿⣿⣿⣿⣿⣆⠄⠄⣿⣿⣿⣿⣿⣿⣿⣿⡿⠋⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡞⣿⣿⣿⣦⢀⣴⣶⣤⡛⠄⠄⠄⠄⢩⣾⣿⣿⣿
⣿⣿⣿⣿⣿⢣⣿⣿⠁⠙⠛⠿⣿⣿⣿⣿⣿⣿⣿⡆⠄⠹⣿⣿⣿⣿⣿⠿⠋⢀⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⢻⣿⣿⡿⢸⣿⣿⣿⠏⣀⣤⣾⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⢣⣿⣿⠏⠄⠄⠄⠄⠄⠉⠛⠿⣿⣿⣿⣿⣆⠄⠄⠉⠉⠉⠄⠄⣠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⠿⠸⣿⣿⢃⣿⣿⣿⡟⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⢣⡿⠟⠋⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠉⠛⠿⣿⣦⡀⠄⠄⠄⠄⣴⣿⣿⣿⣿⣿⣿⣿⠿⠟⠛⠉⠁⠄⠄⠄⠄⠄⣿⡿⢸⣿⣿⣿⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⠃⣿⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠉⠛⢶⣤⠄⢸⣿⣿⣿⠿⠟⠋⠁⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⢸⢁⣿⣿⣿⡟⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⡿⢃⡇⠏⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⢸⠺⠟⠉⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣸⣿⣿⣿⡇⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⡇⢸⡇⠄⠄⠄⠄⠄⠈⢐⠄⣀⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣾⡀⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣿⣿⣿⣿⡇⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⡇⠈⠇⠄⠄⠄⠄⠄⠄⠘⣸⡇⢐⡠⢄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣿⡇⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣿⣿⣿⣿⣧⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⢀⠆⠄⠄⠄⠄⠄⠄⠄⣿⠁⠸⣿⣷⣭⣗⡤⢀⠄⣀⡀⠄⠄⢸⣿⣿⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠘⣿⡟⢻⣿⡈⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣇⠄⠄⠄⠄⡀⠄⠄⠄⣿⡀⠄⠘⠻⣿⣿⣿⣷⡆⡠⠈⠥⢐⡲⠭⢽⣂⣀⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣠⣤⣄⠄⠄⠄⡀⢿⡇⠘⣿⢱⢹⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣆⠄⠄⠄⣿⣷⣤⡀⠈⠁⢻⣦⡠⣄⣉⣛⠻⠡⠂⣩⣷⠲⢈⢢⣧⢀⣤⣶⣶⣮⣅⢀⣠⣶⣷⣦⡀⢼⣿⡿⡛⠳⣸⣿⣿⡸⠇⠄⣿⡆⡇⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⡀⠄⠄⣿⣿⣿⣿⣶⡄⣨⣿⣿⣌⠻⣿⣷⣦⣄⡈⠙⠃⠘⠸⠇⢦⣿⡏⣽⠉⢻⡜⣿⡏⣶⠈⣷⢸⣿⣧⣓⣠⡏⠛⠛⠁⠄⠄⢿⡇⡇⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⡇⠄⠄⢻⣿⣿⣿⣿⢳⣿⣿⣟⠻⣷⡈⢿⣿⣿⣿⢰⣶⣦⡀⠄⣾⣿⣷⣮⣴⣿⡇⣿⣿⣶⣾⣿⢸⣿⣿⣿⣿⣧⠄⠄⠄⠄⠄⢹⠠⢱⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣧⠄⠄⠈⢿⣿⣿⣿⢸⣿⣿⣿⣷⣄⠑⠄⠙⢿⡿⣸⣿⣿⡇⠄⣹⣿⣿⣿⣿⣿⡇⢹⣿⣿⣿⡿⠇⣻⠟⠙⠟⠙⠄⠄⠄⠄⠄⠄⣡⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⠄⠄⠄⠄⢻⣿⣿⣾⣿⣿⣿⣿⣿⣷⣄⠄⠄⠁⠿⣿⡿⠄⠄⠈⠛⠁⠘⠋⠁⠃⠘⠋⠄⠈⠄⠄⠄⠄⢀⣠⣴⣶⣿⡿⠿⠿⢣⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⡇⠄⠄⠄⠄⣿⣿⣿⣿⣿⣿⣧⡙⠻⣿⣷⣄⠄⠄⠈⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⢠⣴⡿⠿⠛⠋⠉⠄⠄⠄⠄⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣷⠄⠄⠄⣴⣿⣿⣿⣿⣿⣿⣿⣿⣦⣄⠉⠉⠁⠄⠄⠄⠄⠄⠄⠄⠄⣠⣤⣤⣴⣶⣶⣶⣾⣿⢸⣷⣶⣴⣶⣶⣶⣶⣶⡆⠄⠄⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⡆⠄⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣶⣤⡀⠄⠄⠄⠄⠄⠄⠄⠘⢿⣿⣿⣿⣿⣿⣿⣿⡞⣿⣿⣿⣿⣿⣿⣿⣿⡇⠄⠄⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
''',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize,
                color: ArticTheme.accent,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingIndicator() {
    return Column(
      children: [
        CircularProgressIndicator(
          color: ArticTheme.accent,
          strokeWidth: 3,
        ),
        const SizedBox(height: 16),
        Text(
          'Загрузка...',
          style: TextStyle(
            color: ArticTheme.secondary,
            fontSize: 14,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      children: [
        Icon(Icons.error_outline, color: ArticTheme.accent, size: 48),
        const SizedBox(height: 16),
        Text(
          'Ошибка загрузки',
          style: TextStyle(color: ArticTheme.primary, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _errorMessage ?? 'Неизвестная ошибка',
            style: TextStyle(color: ArticTheme.secondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _retry,
          style: ElevatedButton.styleFrom(
            backgroundColor: ArticTheme.accent,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Text(
            'Повторить',
            style: TextStyle(color: ArticTheme.primary, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final progress = _animationController.value;
        return Container(
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                gradient: ArticTheme.accentGradient,
                borderRadius: BorderRadius.circular(2),
                boxShadow: ArticTheme.glow(radius: 8),
              ),
            ),
          ),
        );
      },
    );
  }
}