import 'package:flutter/material.dart';

class AppTheme {
  static const _primary = Color(0xff15616d);
  static const _accent = Color(0xffffb703);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _primary, primary: _primary, secondary: _accent, surface: const Color(0xfff7f9fb)),
        scaffoldBackgroundColor: const Color(0xfff7f9fb),
        cardTheme: const CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)))),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _primary, brightness: Brightness.dark, primary: const Color(0xff4cc9d8), secondary: _accent),
        cardTheme: const CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)))),
      );
}

