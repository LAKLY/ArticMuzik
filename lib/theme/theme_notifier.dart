// theme_notifier.dart (исправленный)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme { defaultTheme, darkCrimson, neonCyber, matrixGreen }

class ThemeNotifier extends ChangeNotifier {
  // Синглтон
  static final ThemeNotifier _instance = ThemeNotifier._internal();
  factory ThemeNotifier() => _instance;
  static ThemeNotifier get instance => _instance;

  ThemeNotifier._internal();

  // Базовые цвета
  static const Color _defaultBabyBarnOwl = Color(0xFFA87FCD);
  static const Color _defaultIntrigue = Color(0xFF594C57);
  static const Color _defaultBurntCrimson = Color(0xFFA94E93);
  static const Color _defaultSealBrown = Color(0x001a1017);
  static const Color _defaultNulnOil = Color(0xFF070207);

  Color _babyBarnOwl = _defaultBabyBarnOwl;
  Color _intrigue = _defaultIntrigue;
  Color _burntCrimson = _defaultBurntCrimson;
  Color _sealBrown = _defaultSealBrown;
  Color _nulnOil = _defaultNulnOil;

  Color get babyBarnOwl => _babyBarnOwl;
  Color get intrigue => _intrigue;
  Color get burntCrimson => _burntCrimson;
  Color get sealBrown => _sealBrown;
  Color get nulnOil => _nulnOil;

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('app_theme') ?? 'defaultTheme';
    final theme = _fromString(themeName);
    applyTheme(theme);
  }

  void applyTheme(AppTheme theme) {
    switch (theme) {
      case AppTheme.defaultTheme:
        _babyBarnOwl = _defaultBabyBarnOwl;
        _intrigue = _defaultIntrigue;
        _burntCrimson = _defaultBurntCrimson;
        _sealBrown = _defaultSealBrown;
        _nulnOil = _defaultNulnOil;
        break;
      case AppTheme.darkCrimson:
        _babyBarnOwl = const Color(0xFFE0C8FF);
        _intrigue = const Color(0xFF8A6F8A);
        _burntCrimson = const Color(0xFFD93B6B);
        _sealBrown = const Color(0x1A1C0A0A);
        _nulnOil = const Color(0xFF0D0205);
        break;
      case AppTheme.neonCyber:
        _babyBarnOwl = const Color(0xFF00FFCC);
        _intrigue = const Color(0xFF666666);
        _burntCrimson = const Color(0xFFFF007F);
        _sealBrown = const Color(0x1A0D0D0D);
        _nulnOil = const Color(0xFF050510);
        break;
      case AppTheme.matrixGreen:
        _babyBarnOwl = const Color(0xFFB0FFB0);
        _intrigue = const Color(0xFF3D6B3D);
        _burntCrimson = const Color(0xFF00AA00);
        _sealBrown = const Color(0x1A0A1A0A);
        _nulnOil = const Color(0xFF021A02);
        break;
    }
    _saveTheme(theme);
    notifyListeners();
  }

  Future<void> _saveTheme(AppTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('app_theme', theme.toString().split('.').last);
  }

  AppTheme _fromString(String name) {
    switch (name) {
      case 'darkCrimson': return AppTheme.darkCrimson;
      case 'neonCyber': return AppTheme.neonCyber;
      case 'matrixGreen': return AppTheme.matrixGreen;
      default: return AppTheme.defaultTheme;
    }
  }
}