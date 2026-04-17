import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncStatus { stable, syncing, pendingChanges, failed, offlineLocalOnly }

enum ReminderCategory { tasks, exams, lectures }

enum AppFontSize { defaultSize, small }

enum AppThemeAccent { study, forest, sunset, blossom, mono, passion }

enum SyncDisplayStatus { stable, syncing, offline, outdated }

extension AppThemeAccentDetails on AppThemeAccent {
  String get label {
    switch (this) {
      case AppThemeAccent.study:
        return 'Study';
      case AppThemeAccent.forest:
        return 'Forest';
      case AppThemeAccent.sunset:
        return 'Sunset';
      case AppThemeAccent.blossom:
        return 'Blossom';
      case AppThemeAccent.mono:
        return 'Mono';
      case AppThemeAccent.passion:
        return 'Passion';
    }
  }
}

extension AppFontSizeDetails on AppFontSize {
  String get label {
    switch (this) {
      case AppFontSize.defaultSize:
        return 'Default';
      case AppFontSize.small:
        return 'Small';
    }
  }

  String get storageValue {
    switch (this) {
      case AppFontSize.defaultSize:
        return 'default';
      case AppFontSize.small:
        return 'small';
    }
  }

  double get textScale {
    switch (this) {
      case AppFontSize.defaultSize:
        return 1;
      case AppFontSize.small:
        return 0.9;
    }
  }
}

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.appFontSize,
    required this.themeAccent,
    required this.appNotificationsEnabled,
    required this.taskRemindersEnabled,
    required this.examRemindersEnabled,
    required this.classRemindersEnabled,
    required this.lectureVibrationOnly,
    required this.studyGoalAlertsEnabled,
    required this.autoSyncEnabled,
    required this.taskReminderDefault,
    required this.examReminderDefault,
    required this.lectureReminderDefault,
    required this.syncStatus,
    required this.lastSyncCheckedAt,
    required this.lastSyncedAt,
  });

  final ThemeMode themeMode;
  final AppFontSize appFontSize;
  final AppThemeAccent themeAccent;
  final bool appNotificationsEnabled;
  final bool taskRemindersEnabled;
  final bool examRemindersEnabled;
  final bool classRemindersEnabled;
  final bool lectureVibrationOnly;
  final bool studyGoalAlertsEnabled;
  final bool autoSyncEnabled;
  final String taskReminderDefault;
  final String examReminderDefault;
  final String lectureReminderDefault;
  final SyncStatus syncStatus;
  final DateTime? lastSyncCheckedAt;
  final DateTime? lastSyncedAt;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppFontSize? appFontSize,
    AppThemeAccent? themeAccent,
    bool? appNotificationsEnabled,
    bool? taskRemindersEnabled,
    bool? examRemindersEnabled,
    bool? classRemindersEnabled,
    bool? lectureVibrationOnly,
    bool? studyGoalAlertsEnabled,
    bool? autoSyncEnabled,
    String? taskReminderDefault,
    String? examReminderDefault,
    String? lectureReminderDefault,
    SyncStatus? syncStatus,
    DateTime? lastSyncCheckedAt,
    DateTime? lastSyncedAt,
    bool clearLastSyncCheckedAt = false,
    bool clearLastSyncedAt = false,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      appFontSize: appFontSize ?? this.appFontSize,
      themeAccent: themeAccent ?? this.themeAccent,
      appNotificationsEnabled:
          appNotificationsEnabled ?? this.appNotificationsEnabled,
      taskRemindersEnabled: taskRemindersEnabled ?? this.taskRemindersEnabled,
      examRemindersEnabled: examRemindersEnabled ?? this.examRemindersEnabled,
      classRemindersEnabled:
          classRemindersEnabled ?? this.classRemindersEnabled,
      lectureVibrationOnly: lectureVibrationOnly ?? this.lectureVibrationOnly,
      studyGoalAlertsEnabled:
          studyGoalAlertsEnabled ?? this.studyGoalAlertsEnabled,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      taskReminderDefault: taskReminderDefault ?? this.taskReminderDefault,
      examReminderDefault: examReminderDefault ?? this.examReminderDefault,
      lectureReminderDefault:
          lectureReminderDefault ?? this.lectureReminderDefault,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncCheckedAt: clearLastSyncCheckedAt
          ? null
          : lastSyncCheckedAt ?? this.lastSyncCheckedAt,
      lastSyncedAt: clearLastSyncedAt
          ? null
          : lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class AppSettingsService {
  AppSettingsService._();

  static final AppSettingsService instance = AppSettingsService._();

  static const _themeModeKey = 'theme_mode';
  static const _appFontSizeKey = 'app_font_size';
  static const _themeAccentKey = 'theme_accent';
  static const _appNotificationsKey = 'app_notifications_enabled';
  static const _taskRemindersEnabledKey = 'task_reminders_enabled';
  static const _examRemindersEnabledKey = 'exam_reminders_enabled';
  static const _classRemindersKey = 'class_reminders_enabled';
  static const _lectureVibrationOnlyKey = 'lecture_vibration_only';
  static const _studyGoalAlertsKey = 'study_goal_alerts_enabled';
  static const _autoSyncEnabledKey = 'auto_sync_enabled';
  static const _taskReminderKey = 'task_reminder_default';
  static const _examReminderKey = 'exam_reminder_default';
  static const _lectureReminderKey = 'lecture_reminder_default';
  static const _syncStatusKey = 'sync_status';
  static const _lastSyncCheckedAtKey = 'last_sync_checked_at';
  static const _lastSyncedAtKey = 'last_synced_at';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncCheckedRaw = prefs.getString(_lastSyncCheckedAtKey);
    final lastSyncedRaw = prefs.getString(_lastSyncedAtKey);

    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_themeModeKey)),
      appFontSize: _parseAppFontSize(prefs.getString(_appFontSizeKey)),
      themeAccent: _parseThemeAccent(prefs.getString(_themeAccentKey)),
      appNotificationsEnabled: prefs.getBool(_appNotificationsKey) ?? true,
      taskRemindersEnabled: prefs.getBool(_taskRemindersEnabledKey) ?? true,
      examRemindersEnabled: prefs.getBool(_examRemindersEnabledKey) ?? true,
      classRemindersEnabled: prefs.getBool(_classRemindersKey) ?? true,
      lectureVibrationOnly: prefs.getBool(_lectureVibrationOnlyKey) ?? true,
      studyGoalAlertsEnabled: prefs.getBool(_studyGoalAlertsKey) ?? false,
      autoSyncEnabled: prefs.getBool(_autoSyncEnabledKey) ?? true,
      taskReminderDefault: prefs.getString(_taskReminderKey) ?? '15m before',
      examReminderDefault: prefs.getString(_examReminderKey) ?? '2 days before',
      lectureReminderDefault:
          prefs.getString(_lectureReminderKey) ?? '10m before',
      syncStatus: _parseSyncStatus(prefs.getString(_syncStatusKey)),
      lastSyncCheckedAt: lastSyncCheckedRaw == null
          ? null
          : DateTime.tryParse(lastSyncCheckedRaw),
      lastSyncedAt: lastSyncedRaw == null
          ? null
          : DateTime.tryParse(lastSyncedRaw),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, settings.themeMode.name);
    await prefs.setString(_appFontSizeKey, settings.appFontSize.storageValue);
    await prefs.setString(_themeAccentKey, settings.themeAccent.name);
    await prefs.setBool(_appNotificationsKey, settings.appNotificationsEnabled);
    await prefs.setBool(
      _taskRemindersEnabledKey,
      settings.taskRemindersEnabled,
    );
    await prefs.setBool(
      _examRemindersEnabledKey,
      settings.examRemindersEnabled,
    );
    await prefs.setBool(_classRemindersKey, settings.classRemindersEnabled);
    await prefs.setBool(
      _lectureVibrationOnlyKey,
      settings.lectureVibrationOnly,
    );
    await prefs.setBool(_studyGoalAlertsKey, settings.studyGoalAlertsEnabled);
    await prefs.setBool(_autoSyncEnabledKey, settings.autoSyncEnabled);
    await prefs.setString(_taskReminderKey, settings.taskReminderDefault);
    await prefs.setString(_examReminderKey, settings.examReminderDefault);
    await prefs.setString(_lectureReminderKey, settings.lectureReminderDefault);
    await prefs.setString(_syncStatusKey, settings.syncStatus.name);

    if (settings.lastSyncCheckedAt != null) {
      await prefs.setString(
        _lastSyncCheckedAtKey,
        settings.lastSyncCheckedAt!.toIso8601String(),
      );
    } else {
      await prefs.remove(_lastSyncCheckedAtKey);
    }

    if (settings.lastSyncedAt != null) {
      await prefs.setString(
        _lastSyncedAtKey,
        settings.lastSyncedAt!.toIso8601String(),
      );
    } else {
      await prefs.remove(_lastSyncedAtKey);
    }
  }

  ThemeMode _parseThemeMode(String? value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  AppFontSize _parseAppFontSize(String? value) {
    switch (value) {
      case 'small':
        return AppFontSize.small;
      case 'default':
      case 'defaultSize':
      default:
        return AppFontSize.defaultSize;
    }
  }

  AppThemeAccent _parseThemeAccent(String? value) {
    for (final accent in AppThemeAccent.values) {
      if (accent.name == value) {
        return accent;
      }
    }
    return AppThemeAccent.study;
  }

  SyncStatus _parseSyncStatus(String? value) {
    for (final status in SyncStatus.values) {
      if (status.name == value) {
        return status;
      }
    }

    return SyncStatus.stable;
  }
}
