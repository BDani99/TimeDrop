import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/errors/app_exception.dart';

/// On-device scheduled unlock reminders — deliberately does NOT require a
/// Firebase project or any push credentials (see [PushService] for the
/// separate, currently-mocked remote-push path). This alone covers "the
/// recipient gets notified on unlock day" from the spec.
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  static Future<bool> ensurePermissionGranted() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final androidGranted =
          await androidImpl?.requestNotificationsPermission() ?? true;
      final iosGranted = await iosImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
      return androidGranted && iosGranted;
    } catch (_) {
      return false;
    }
  }

  /// Schedules a local notification for [unlockTime]. [capsuleId]'s hash
  /// seeds the notification id so re-scheduling the same capsule replaces
  /// rather than duplicates it.
  static Future<void> scheduleUnlockReminder({
    required String capsuleId,
    required DateTime unlockTime,
  }) async {
    if (unlockTime.isBefore(DateTime.now())) return;

    try {
      await initialize();
      final id = capsuleId.hashCode & 0x7fffffff;
      await _plugin.zonedSchedule(
        id,
        'A memory is ready to unlock',
        'Head to the location to open it.',
        tz.TZDateTime.from(unlockTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'capsule_unlock',
            'Capsule unlock reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact scheduling deliberately avoids Android 12+'s
        // SCHEDULE_EXACT_ALARM permission, which Play Store restricts to
        // alarm-clock/calendar-category apps — a reminder notification like
        // this one doesn't qualify, and being off by a few minutes is fine.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      throw CapsuleException('Could not schedule the unlock reminder.', cause: e);
    }
  }

  static Future<void> cancelReminder(String capsuleId) async {
    final id = capsuleId.hashCode & 0x7fffffff;
    await _plugin.cancel(id);
  }
}
