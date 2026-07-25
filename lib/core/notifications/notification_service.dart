import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  Future<void> showNotification({
    required String title,
    required String body,
    int id = 0,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'adeghe_channel',
      'Adeghe Professional Services',
      channelDescription: 'General notifications from Adeghe Professional Services',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details);
  }

  Future<void> scheduleLoanReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'adeghe_reminders',
      'Adeghe Loan Reminders',
      channelDescription: 'Reminders for upcoming loan payments',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    final delay = scheduledDate.difference(DateTime.now());
    if (delay.isNegative) {
      await showNotification(id: id, title: title, body: body);
    } else {
      Timer(delay, () async {
        await _plugin.show(id, title, body, details);
      });
    }
  }

  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
