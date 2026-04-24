import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyflow/models/reminder_presets.dart';
import 'package:studyflow/services/app_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('new users get the expected reminder defaults', () async {
    final settings = await AppSettingsService.instance.load();

    expect(settings.themeMode, ThemeMode.light);
    expect(settings.themeAccent, AppThemeAccent.study);
    expect(settings.appNotificationsEnabled, isTrue);
    expect(settings.taskRemindersEnabled, isTrue);
    expect(settings.examRemindersEnabled, isTrue);
    expect(settings.classRemindersEnabled, isTrue);
    expect(settings.lectureVibrationOnly, isTrue);
    expect(settings.studyGoalAlertsEnabled, isFalse);
    expect(settings.autoSyncEnabled, isTrue);
    expect(settings.taskReminderDefault, defaultTaskReminderLabel);
  });
}
