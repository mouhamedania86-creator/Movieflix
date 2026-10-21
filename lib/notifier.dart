import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'device.dart'; // 👈 ضروري جداً لمعرفة نوع الجهاز

/// إشعارات التذكير (محلية). تخدم على Android وiPhone،
/// وعلى الكمبيوتر التذكير يظهر داخل التطبيق فقط.
class Notifier {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static Future<void> init() async {
    // 👈 هذا السطر هو السر: إذا كان الجهاز تلفاز، نوقف الإشعارات فوراً
    if (Device.isTv) return;

    if (!supported || _ready) return;
    try {
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ));
      _ready = true;
    } catch (_) {}
  }

  static Future<bool> requestPermission() async {
    if (!supported || Device.isTv) return false; // 👈 تعطيل للتلفاز
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? true;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? true;
    } catch (_) {
      return true;
    }
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Release reminders',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
  );

  /// يرجع false إذا فشل الجدولة أو الإذن مرفوض أو المنصة ما تدعمش.
  static Future<bool> schedule(int id, String title, String body, DateTime when) async {
    if (!supported || Device.isTv) return false; // 👈 تعطيل للتلفاز
    try {
      await init();
      final granted = await requestPermission();
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.UTC),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      return granted;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancel(int id) async {
    if (!supported || Device.isTv) return; // 👈 تعطيل للتلفاز
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }
}
