import 'package:flutter/material.dart';

class AppTheme {
  static const primaryBlue = Color(0xff15616d);
  static const primaryBlueDark = Color(0xff0b3f47);
  static const primaryBlueLight = Color(0xffdceff2);
  static const serviceGreen = Color(0xff1f7a4d);
  static const serviceGreenLight = Color(0xffdff3e8);
  static const warningOrange = Color(0xffc86b10);
  static const warningOrangeLight = Color(0xffffecd6);
  static const emergencyRed = Color(0xffb42318);
  static const emergencyRedLight = Color(0xffffe2df);
  static const surfaceLight = Color(0xfff7f9fb);
  static const surfaceDark = Color(0xff10191c);

  static Color statusColor(String status) => switch (status) {
        'normal' || 'active' || 'closed' || 'ok' => serviceGreen,
        'warning' || 'delay' || 'in_progress' || 'vigilance' => warningOrange,
        'critical' ||
        'sos' ||
        'suspended' ||
        'forbidden' ||
        'received' =>
          emergencyRed,
        _ => primaryBlue,
      };

  static Color statusContainer(String status) => switch (status) {
        'normal' || 'active' || 'closed' || 'ok' => serviceGreenLight,
        'warning' ||
        'delay' ||
        'in_progress' ||
        'vigilance' =>
          warningOrangeLight,
        'critical' ||
        'sos' ||
        'suspended' ||
        'forbidden' ||
        'received' =>
          emergencyRedLight,
        _ => primaryBlueLight,
      };

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: warningOrange,
          tertiary: serviceGreen,
          error: emergencyRed,
          surface: surfaceLight,
        ),
        scaffoldBackgroundColor: surfaceLight,
        cardTheme: const CardThemeData(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)))),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryBlue,
            side: const BorderSide(color: primaryBlue),
          ),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          brightness: Brightness.dark,
          primary: const Color(0xff75d2df),
          secondary: const Color(0xffffb25c),
          tertiary: const Color(0xff72d39a),
          error: const Color(0xffff8a80),
          surface: surfaceDark,
        ),
        scaffoldBackgroundColor: surfaceDark,
        cardTheme: const CardThemeData(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)))),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      );
}
