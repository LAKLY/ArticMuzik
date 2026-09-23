import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/yandex/yandex_auth_service.dart';
import '../services/yandex/yandex_audio_provider.dart';
import '../theme/artic_theme.dart';

class YandexTokenInputScreen extends StatefulWidget {
  const YandexTokenInputScreen({super.key});

  @override
  State<YandexTokenInputScreen> createState() => _YandexTokenInputScreenState();
}

class _YandexTokenInputScreenState extends State<YandexTokenInputScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller.text = 'y0__wgBEIachukIGN74BiCjqfmiF9H6E40XT2pqjGDsaESN-mx64mjX';
  }

  Future<void> _saveToken() async {
    final token = _controller.text.trim();
    if (token.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final auth = Provider.of<YandexAuthService>(context, listen: false);
      await auth.saveToken(token);
      
      final provider = Provider.of<YandexAudioProvider>(context, listen: false);
      await provider.init();
      
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: ArticTheme.backgroundGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.vpn_key, size: 80, color: ArticTheme.accent),
                const SizedBox(height: 24),
                Text(
                  'Введите Яндекс.Музыка Access Token',
                  style: TextStyle(color: ArticTheme.primary, fontSize: 18, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  style: TextStyle(color: ArticTheme.primary),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'y0_...',
                    hintStyle: TextStyle(color: ArticTheme.secondary),
                    filled: true,
                    fillColor: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: ArticTheme.accent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Как получить токен:\n1. Перейдите по ссылке:\nhttps://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d\n2. Нажмите "Разрешить"\n3. Скопируйте токен из адресной строки',
                  style: TextStyle(color: ArticTheme.secondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? CircularProgressIndicator(color: ArticTheme.accent)
                    : ElevatedButton(
                        onPressed: _saveToken,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ArticTheme.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: Text('Сохранить', style: TextStyle(color: ArticTheme.primary, fontSize: 16)),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}