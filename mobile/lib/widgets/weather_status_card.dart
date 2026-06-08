import 'package:flutter/material.dart';

import '../theme.dart';

class WeatherStatusCard extends StatelessWidget {
  const WeatherStatusCard({
    super.key,
    required this.weather,
    this.compact = false,
  });

  final Map<String, dynamic>? weather;
  final bool compact;

  Color get color {
    final state = weather?['weatherState'] as String? ?? 'normal';
    return switch (state) {
      'rain' || 'snow' || 'ice' || 'fog' => AppTheme.warningOrange,
      'accident' => AppTheme.emergencyRed,
      _ => AppTheme.serviceGreen,
    };
  }

  IconData get icon {
    final state = weather?['weatherState'] as String? ?? 'normal';
    return switch (state) {
      'rain' => Icons.water_drop_outlined,
      'snow' => Icons.ac_unit,
      'ice' => Icons.device_thermostat,
      'fog' => Icons.foggy,
      _ => Icons.wb_sunny_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final temperature = (weather?['temperatureC'] as num?)?.round();
    final wind = (weather?['windKmh'] as num?)?.round();
    final humidity = (weather?['humidity'] as num?)?.round();
    final label = weather?['weatherLabel'] as String? ?? 'Meteo locale';
    final location =
        (weather?['location'] as Map?)?['name'] as String? ?? 'Normandie';
    final isDay = weather?['isDay'] as bool?;
    final tempLabel = temperature == null ? '-- degres' : '$temperature degres';

    return Card(
      color: AppTheme.statusContainer(
          color == AppTheme.serviceGreen ? 'normal' : 'vigilance'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: compact ? 42 : 50,
              height: compact ? 42 : 50,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: compact ? 24 : 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$tempLabel - $label',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (isDay != null)
                        Icon(isDay ? Icons.light_mode : Icons.dark_mode,
                            color: color, size: 20),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      location,
                      if (wind != null) 'vent $wind km/h',
                      if (humidity != null) 'humidite $humidity%',
                    ].join(' - '),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
