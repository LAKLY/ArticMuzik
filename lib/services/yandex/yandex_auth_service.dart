import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class YandexAuthService {
  static const String _tokenKey = 'yandex_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> isAuthorized() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}