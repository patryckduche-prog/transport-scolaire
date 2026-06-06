import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _local = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {}
    const android = AndroidInitializationSettings('@drawable/ic_launcher');
    await _local.initialize(const InitializationSettings(android: android));
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
      const NotificationDetails(android: AndroidNotificationDetails('school_bus_alerts', 'Alertes bus scolaire', importance: Importance.high, priority: Priority.high, playSound: true, enableVibration: true)),
    );
  }
}
