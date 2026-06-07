import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const favoriteRouteChannelId = 'favorite_route_alerts_v2';
const criticalSafetyChannelId = 'critical_transport_safety_v1';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    final local = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@drawable/ic_launcher');
    await local.initialize(const InitializationSettings(android: android));
    await _createAndroidChannels(local);
    final title = message.notification?.title ??
        message.data['title'] as String? ??
        'Alerte bus scolaire';
    final body = message.notification?.body ??
        message.data['body'] as String? ??
        'Nouvelle alerte sur une ligne favorite.';
    final critical = message.data['severity'] == 'critical';
    await _showAndroidAlert(
      local: local,
      title: title,
      body: body,
      critical: critical,
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
      'Alertes lignes favorites',
      description: 'Notifications sonores pour les lignes favorites',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 700, 250, 700]),
    ),
  );
  await android.createNotificationChannel(
    AndroidNotificationChannel(
      criticalSafetyChannelId,
      'Alertes securite transport',
      description: 'Alertes prioritaires securite, prefecture et circulation',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 900, 250, 900, 250, 900]),
    ),
  );
}

Future<void> _showAndroidAlert({
  required FlutterLocalNotificationsPlugin local,
  required String title,
  required String body,
  required bool critical,
  int? id,
}) async {
  await local.show(
    id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        critical ? criticalSafetyChannelId : favoriteRouteChannelId,
        critical ? 'Alertes securite transport' : 'Alertes lignes favorites',
        channelDescription: critical
            ? 'Alertes prioritaires securite, prefecture et circulation'
            : 'Notifications sonores pour les lignes favorites',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: critical
            ? Int64List.fromList([0, 900, 250, 900, 250, 900])
            : Int64List.fromList([0, 700, 250, 700]),
      ),
    ),
  );
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _local = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@drawable/ic_launcher');
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
        final title = message.notification?.title ?? 'Alerte bus scolaire';
        final body = message.notification?.body ??
            message.data['body'] as String? ??
            'Nouvelle alerte sur une ligne favorite.';
        if (message.data['severity'] == 'critical') {
          showCriticalSafetyAlert(title: title, body: body);
        } else {
          showBusAlert(title: title, body: body);
        }
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
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true)),
    );
  }

  Future<void> showBusAlert(
      {required String title, required String body, int? id}) async {
    await _showAndroidAlert(
      local: _local,
      title: title,
      body: body,
      critical: false,
      id: id,
    );
  }

  Future<void> showCriticalSafetyAlert(
      {required String title, required String body, int? id}) async {
    await _showAndroidAlert(
      local: _local,
      title: title,
      body: body,
      critical: true,
      id: id,
    );
  }
}
