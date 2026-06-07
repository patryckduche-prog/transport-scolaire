import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class OfflineEventQueue {
  const OfflineEventQueue(this.api);

  static const _key = 'driver_offline_events';
  final ApiService api;

  Future<void> enqueue(Map<String, dynamic> event) async {
    final prefs = await SharedPreferences.getInstance();
    final events = prefs.getStringList(_key) ?? <String>[];
    events.add(jsonEncode({
      ...event,
      'createdAt': DateTime.now().toIso8601String(),
    }));
    await prefs.setStringList(_key, events);
  }

  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? <String>[]).length;
  }

  Future<int> flush() async {
    final prefs = await SharedPreferences.getInstance();
    final events = prefs.getStringList(_key) ?? <String>[];
    var sent = 0;
    final remaining = <String>[];

    for (final raw in events) {
      final event = jsonDecode(raw) as Map<String, dynamic>;
      try {
        await _send(event);
        sent++;
      } catch (_) {
        remaining.add(raw);
      }
    }

    await prefs.setStringList(_key, remaining);
    return sent;
  }

  Future<void> _send(Map<String, dynamic> event) async {
    switch (event['type']) {
      case 'runGps':
        await api.sendRunGps(
          runId: event['runId'] as String,
          latitude: (event['latitude'] as num).toDouble(),
          longitude: (event['longitude'] as num).toDouble(),
          speed: (event['speed'] as num?)?.toDouble() ?? 0,
          recordedAt: event['recordedAt'] as String?,
        );
      case 'presence':
        await api.updateRunStudentPresence(
          runId: event['runId'] as String,
          studentId: event['studentId'] as String,
          present: event['present'] as bool,
          status: event['status'] as String?,
        );
      case 'incident':
        await api.sendRunIncident(
          runId: event['runId'] as String,
          type: event['incidentType'] as String,
          message: event['message'] as String,
          severity: event['severity'] as String? ?? 'warning',
        );
      case 'finishCheck':
        await api.sendFinishCheck(
          runId: event['runId'] as String,
          allStudentsChecked: event['allStudentsChecked'] as bool,
          busEmptyConfirmed: event['busEmptyConfirmed'] as bool,
          comment: event['comment'] as String? ?? '',
        );
      default:
        throw UnsupportedError('Unknown offline event ${event['type']}');
    }
  }
}
