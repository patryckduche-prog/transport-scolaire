import 'dart:typed_data';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

const favoriteRouteChannelId = 'favorite_route_alerts_v5';
const criticalSafetyChannelId = 'critical_transport_safety_v4';
const alertRed = Color(0xFFB00020);

int _stableId(String value) {
  final digits = int.tryParse(value);
  if (digits != null) return digits.remainder(2147483647);
  var hash = 0;
  for (final code in value.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash == 0 ? 1001 : hash;
}

Future<bool> _shouldShowOnce(String key) async {
  final safeKey = 'shown_alert_${_stableId(key)}';
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = prefs.getInt(safeKey) ?? 0;
  if (now - last < const Duration(hours: 2).inMilliseconds) {
    return false;
  }
  await prefs.setInt(safeKey, now);
  return true;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    if (message.notification != null) {
      return;
    }
    final local = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@drawable/ic_stat_bus_alert');
    await local.initialize(const InitializationSettings(android: android));
    await _createAndroidChannels(local);
    final title = message.notification?.title ??
        message.data['title'] as String? ??
        'ALERTE BUS SCOLAIRE';
    final body = message.notification?.body ??
        message.data['body'] as String? ??
        'Nouvelle alerte sur une ligne favorite.';
    final critical = message.data['severity'] == 'critical';
    final alertId = (message.data['alertId'] ?? '').toString();
    final key = alertId.isNotEmpty ? alertId : '$title|$body';
    if (!await _shouldShowOnce(key)) return;
    await _showAndroidAlert(
      local: local,
      title: title,
      body: body,
      critical: critical,
      id: _stableId(key),
      tag: critical ? 'critical-alert-$key' : 'route-alert-$key',
    );
  } catch (_) {}
}

Future<void> _createAndroidChannels(
    FlutterLocalNotificationsPlugin local) async {
  final android = local.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return;
  await android.createNotificationChannel(
    AndroidNotificationChannel(
      favoriteRouteChannelId,
      'Alertes bus scolaire prioritaires',
      description: 'Alertes visibles avec sonnerie et vibration forte',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 900, 250, 900, 250, 900]),
    ),
  );
  await android.createNotificationChannel(
    AndroidNotificationChannel(
      criticalSafetyChannelId,
      'Alertes securite transport prioritaires',
      description: 'Alertes prioritaires securite, prefecture et circulation',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 200, 1000, 200, 1000]),
    ),
  );
}

Future<void> _showAndroidAlert({
  required FlutterLocalNotificationsPlugin local,
  required String title,
  required String body,
  required bool critical,
  int? id,
  String? tag,
}) async {
  await local.show(
    id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        critical ? criticalSafetyChannelId : favoriteRouteChannelId,
        critical
            ? 'Alertes securite transport prioritaires'
            : 'Alertes bus scolaire prioritaires',
        channelDescription: critical
            ? 'Alertes prioritaires securite, prefecture et circulation'
            : 'Alertes visibles avec sonnerie et vibration forte',
        importance: Importance.max,
        icon: 'ic_stat_bus_alert',
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: critical
            ? Int64List.fromList([0, 1000, 200, 1000, 200, 1000])
            : Int64List.fromList([0, 900, 250, 900, 250, 900]),
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Bus Scolaire Connect',
        ),
        ticker: title,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        tag: tag,
        color: alertRed,
        colorized: true,
        ledColor: alertRed,
        enableLights: true,
        ledOnMs: 1000,
        ledOffMs: 500,
      ),
    ),
  );
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _local = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@drawable/ic_stat_bus_alert');
    await _local.initialize(const InitializationSettings(android: android));
    await _createAndroidChannels(_local);
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen((message) {
        final title =
            message.notification?.title ?? 'ALERTE BUS SCOLAIRE';
        final body = message.notification?.body ??
            message.data['body'] as String? ??
            'Nouvelle alerte sur une ligne favorite.';
        final id = int.tryParse((message.data['alertId'] ?? '').toString());
        final key = (message.data['alertId'] ?? '$title|$body').toString();
        _shouldShowOnce(key).then((show) {
          if (!show) return;
          if (message.data['severity'] == 'critical') {
            showCriticalSafetyAlert(
                title: title,
                body: body,
                id: id ?? _stableId(key),
                tag: 'critical-alert-$key');
          } else {
            showBusAlert(
                title: title,
                body: body,
                id: id ?? _stableId(key),
                tag: 'route-alert-$key');
          }
        });
      });
    } catch (_) {}
  }

  Future<String?> getFcmToken() async {
    try {
      return FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> showReminder(String stopName) async {
    await _local.show(
      10,
      'Rappel transport scolaire',
      'Merci de vous presenter a l\'arret $stopName au moins 10 minutes avant le passage.',
      const NotificationDetails(
          android: AndroidNotificationDetails(
              'school_bus_alerts', 'Alertes bus scolaire',
              icon: 'ic_stat_bus_alert',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true)),
    );
  }

  Future<void> showBusAlert(
      {required String title,
      required String body,
      int? id,
      String? tag}) async {
    await _showAndroidAlert(
      local: _local,
      title: title,
      body: body,
      critical: false,
      id: id,
      tag: tag,
    );
  }

  Future<void> showCriticalSafetyAlert(
      {required String title,
      required String body,
      int? id,
      String? tag}) async {
    await _showAndroidAlert(
      local: _local,
      title: title,
      body: body,
      critical: true,
      id: id,
      tag: tag,
    );
  }
}
