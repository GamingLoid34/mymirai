import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/homework_item.dart';

const _kPrefReminderEnabled = 'reminder_enabled';
const _kPrefReminderHour = 'reminder_hour';
const _kPrefReminderMinute = 'reminder_minute';

const _kDailyStudyNotificationId = 900000;

/// Lokala schemalagda notiser: daglig läxpåminnelse + deadline-varningar.
///
/// Hoppar helt över sig själv på webb och Windows, där lokala notiser
/// antingen saknas eller inte stöds av paketet.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!_supported || _initialized) return;
    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kPrefReminderEnabled) ?? false;
    if (enabled) {
      final hour = prefs.getInt(_kPrefReminderHour) ?? 16;
      final minute = prefs.getInt(_kPrefReminderMinute) ?? 0;
      await scheduleDailyStudyTime(TimeOfDay(hour: hour, minute: minute));
    }
  }

  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }
    return false;
  }

  Future<void> scheduleDailyStudyTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefReminderEnabled, true);
    await prefs.setInt(_kPrefReminderHour, time.hour);
    await prefs.setInt(_kPrefReminderMinute, time.minute);
    if (!_initialized) return;

    await _plugin.zonedSchedule(
      id: _kDailyStudyNotificationId,
      title: 'Läxdags! 📚',
      body: 'Dagens pass väntar – det tar bara några minuter.',
      scheduledDate: _nextInstanceOfTime(time),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_study_time',
          'Daglig läxpåminnelse',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyStudyTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefReminderEnabled, false);
    if (!_initialized) return;
    await _plugin.cancel(id: _kDailyStudyNotificationId);
  }

  /// Synkar deadline-påminnelser (dagen innan kl 17:00) för aktiva läxor.
  Future<void> syncDeadlineReminders(List<HomeworkItem> homework) async {
    if (!_initialized) return;
    final pending = await _plugin.pendingNotificationRequests();
    final activeIds = <int>{};

    for (final h in homework) {
      final due = h.dueAt;
      if (due == null || h.status == HomeworkStatus.done) continue;
      final reminderAt = DateTime(due.year, due.month, due.day - 1, 17);
      if (reminderAt.isBefore(DateTime.now())) continue;

      final id = h.id.hashCode & 0x7fffffff;
      activeIds.add(id);
      await _plugin.zonedSchedule(
        id: id,
        title: 'Imorgon: ${h.title}',
        body: 'Lämnas in imorgon – hinner du en sista koll?',
        scheduledDate: tz.TZDateTime.from(reminderAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'deadline_reminders',
            'Läxa lämnas in imorgon',
            importance: Importance.defaultImportance,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }

    for (final p in pending) {
      if (p.id == _kDailyStudyNotificationId) continue;
      if (!activeIds.contains(p.id)) {
        await _plugin.cancel(id: p.id);
      }
    }
  }

  /// Visar lokal notis när en fotad/uppladdad läxa har analyserats klart i bakgrunden (AP6).
  Future<void> showHomeworkProcessed({
    required String title,
    required String homeworkId,
  }) async {
    if (!_initialized) return;
    final id = homeworkId.hashCode & 0x7fffffff;
    await _plugin.show(
      id: id,
      title: 'Läxan är klar! ✨',
      body: '$title har analyserats och är redo för dig.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'homework_processed',
          'Färdiganalyserad läxa',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
