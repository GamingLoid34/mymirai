import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';
import '../theme/mirai_tokens.dart';

/// Rad i profilmenyn: av/på + tidväljare för den dagliga läxpåminnelsen.
class ReminderSettingsRow extends StatefulWidget {
  const ReminderSettingsRow({super.key});

  @override
  State<ReminderSettingsRow> createState() => _ReminderSettingsRowState();
}

class _ReminderSettingsRowState extends State<ReminderSettingsRow> {
  bool _loading = true;
  bool _enabled = false;
  TimeOfDay _time = const TimeOfDay(hour: 16, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enabled = prefs.getBool('reminder_enabled') ?? false;
      _time = TimeOfDay(
        hour: prefs.getInt('reminder_hour') ?? 16,
        minute: prefs.getInt('reminder_minute') ?? 0,
      );
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tillåt notiser i telefonens inställningar för att få påminnelser.'),
          ),
        );
      }
      await NotificationService.instance.scheduleDailyStudyTime(_time);
    } else {
      await NotificationService.instance.cancelDailyStudyTime();
    }
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() => _time = picked);
    if (_enabled) {
      await NotificationService.instance.scheduleDailyStudyTime(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (_loading) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Påminnelse varje dag', style: tt.bodyMedium),
            ),
            Switch(value: _enabled, onChanged: _toggle),
          ],
        ),
        if (_enabled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _pickTime,
                child: Text(
                  'Kl. ${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
