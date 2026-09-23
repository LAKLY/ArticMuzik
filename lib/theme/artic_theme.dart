// artic_theme.dart (исправленный)
import 'package:flutter/material.dart';
import 'theme_notifier.dart';

class ArticTheme {
  // Получаем синглтон ThemeNotifier
  static ThemeNotifier get _notifier => ThemeNotifier.instance;

  // Динамические геттеры – обращаются к синглтону
  static Color get babyBarnOwl => _notifier.babyBarnOwl;
  static Color get intrigue => _notifier.intrigue;
  static Color get burntCrimson => _notifier.burntCrimson;
  static Color get sealBrown => _notifier.sealBrown;
  static Color get nulnOil => _notifier.nulnOil;

  // Алиасы
  static Color get accent => burntCrimson;
  static Color get primary => babyBarnOwl;
  static Color get secondary => intrigue;
  static Color get backgroundDeep => nulnOil;
  static Color get backgroundDarkest => sealBrown;

  // Градиенты (используют геттеры)
  static LinearGradient get backgroundGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [nulnOil, sealBrown],
  );

  static LinearGradient get surfaceGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [babyBarnOwl.withValues(alpha: 0.2), burntCrimson.withValues(alpha: 0.2)],
  );

  static LinearGradient get accentGradient => LinearGradient(
    colors: [burntCrimson, burntCrimson.withBlue(50)],
  );

  static List<BoxShadow> glow({Color? color, double radius = 20}) => [
    BoxShadow(
      color: (color ?? burntCrimson).withValues(alpha: 0.4),
      blurRadius: radius,
      spreadRadius: 2,
    ),
  ];
}