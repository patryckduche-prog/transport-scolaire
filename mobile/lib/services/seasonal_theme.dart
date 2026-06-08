import 'package:flutter/material.dart';

import '../theme.dart';

enum AppSeason { spring, summer, autumn, winter }

enum WeatherState { normal, rain, snow, ice, fog, accident, traffic }

class SeasonalTheme {
  const SeasonalTheme({
    required this.season,
    required this.weather,
    required this.asset,
    required this.primary,
    required this.accent,
    required this.alertIcon,
    required this.label,
  });

  final AppSeason season;
  final WeatherState weather;
  final String asset;
  final Color primary;
  final Color accent;
  final IconData alertIcon;
  final String label;

  static SeasonalTheme fromDate(
    DateTime date, {
    WeatherState weather = WeatherState.normal,
  }) {
    final season = _seasonFor(date);
    final base = switch (season) {
      AppSeason.spring => (
          asset: 'assets/seasons/spring.png',
          label: 'Printemps normand'
        ),
      AppSeason.summer => (
          asset: 'assets/seasons/summer.png',
          label: 'Ete sur les lignes'
        ),
      AppSeason.autumn => (
          asset: 'assets/seasons/autumn.png',
          label: 'Automne brumeux'
        ),
      AppSeason.winter => (
          asset: 'assets/seasons/winter.png',
          label: 'Hiver en circulation'
        ),
    };

    return SeasonalTheme(
      season: season,
      weather: weather,
      asset: base.asset,
      primary: _weatherPrimary(weather),
      accent: _weatherAccent(weather),
      alertIcon: _iconFor(weather),
      label: base.label,
    );
  }

  static AppSeason _seasonFor(DateTime date) {
    final month = date.month;
    if (month >= 3 && month <= 5) return AppSeason.spring;
    if (month >= 6 && month <= 8) return AppSeason.summer;
    if (month >= 9 && month <= 11) return AppSeason.autumn;
    return AppSeason.winter;
  }

  static WeatherState weatherFromAlerts(List<dynamic> alerts) {
    final text = alerts
        .map((item) =>
            (item as Map<String, dynamic>)['message'].toString().toLowerCase())
        .join(' ');
    if (text.contains('accident')) return WeatherState.accident;
    if (text.contains('bouchon')) return WeatherState.traffic;
    if (text.contains('verglas')) return WeatherState.ice;
    if (text.contains('neige')) return WeatherState.snow;
    if (text.contains('brouillard')) return WeatherState.fog;
    if (text.contains('pluie')) return WeatherState.rain;
    return WeatherState.normal;
  }

  static Color _weatherPrimary(WeatherState weather) => switch (weather) {
        WeatherState.accident => AppTheme.emergencyRed,
        WeatherState.traffic || WeatherState.ice => AppTheme.warningOrange,
        _ => AppTheme.primaryBlue,
      };

  static Color _weatherAccent(WeatherState weather) => switch (weather) {
        WeatherState.normal => AppTheme.serviceGreen,
        WeatherState.accident => AppTheme.emergencyRed,
        WeatherState.traffic ||
        WeatherState.ice ||
        WeatherState.rain ||
        WeatherState.snow ||
        WeatherState.fog =>
          AppTheme.warningOrange,
      };

  static IconData _iconFor(WeatherState weather) => switch (weather) {
        WeatherState.rain => Icons.water_drop_outlined,
        WeatherState.snow => Icons.ac_unit,
        WeatherState.ice => Icons.device_thermostat,
        WeatherState.fog => Icons.foggy,
        WeatherState.accident => Icons.car_crash_outlined,
        WeatherState.traffic => Icons.traffic,
        WeatherState.normal => Icons.check_circle_outline,
      };
}
