import 'package:flutter/material.dart';

import 'services/app_settings_service.dart';

class AppController extends ChangeNotifier {
  AppController._(this._settingsService, this._settings)
    : themeModeListenable = ValueNotifier<ThemeMode>(_settings.themeMode),
      fontSizeListenable = ValueNotifier<AppFontSize>(_settings.appFontSize),
      themeAccentListenable = ValueNotifier<AppThemeAccent>(
        _settings.themeAccent,
      );

  final AppSettingsService _settingsService;
  AppSettings _settings;
  final ValueNotifier<ThemeMode> themeModeListenable;
  final ValueNotifier<AppFontSize> fontSizeListenable;
  final ValueNotifier<AppThemeAccent> themeAccentListenable;

  static const Duration syncFreshnessWindow = Duration(hours: 12);
  static const Duration autoSyncInterval = Duration(minutes: 30);

  static Future<AppController> bootstrap() async {
    final service = AppSettingsService.instance;
    final settings = await service.load();
    return AppController._(service, settings);
  }

  ThemeMode get themeMode => _settings.themeMode;
  AppFontSize get appFontSize => _settings.appFontSize;
  AppThemeAccent get themeAccent => _settings.themeAccent;
  bool get appNotificationsEnabled => _settings.appNotificationsEnabled;
  bool get taskRemindersEnabled => _settings.taskRemindersEnabled;
  bool get examRemindersEnabled => _settings.examRemindersEnabled;
  bool get classRemindersEnabled => _settings.classRemindersEnabled;
  bool get lectureVibrationOnly => _settings.lectureVibrationOnly;
  bool get studyGoalAlertsEnabled => _settings.studyGoalAlertsEnabled;
  bool get autoSyncEnabled => _settings.autoSyncEnabled;
  String get taskReminderDefault => _settings.taskReminderDefault;
  String get examReminderDefault => _settings.examReminderDefault;
  String get lectureReminderDefault => _settings.lectureReminderDefault;
  SyncStatus get syncStatus => _settings.syncStatus;
  DateTime? get lastSyncCheckedAt => _settings.lastSyncCheckedAt;
  DateTime? get lastSyncedAt => _settings.lastSyncedAt;
  bool get isSyncing => _settings.syncStatus == SyncStatus.syncing;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_settings.themeMode == mode) {
      return;
    }
    _settings = _settings.copyWith(themeMode: mode);
    themeModeListenable.value = mode;
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setAppFontSize(AppFontSize fontSize) async {
    if (_settings.appFontSize == fontSize) {
      return;
    }
    _settings = _settings.copyWith(appFontSize: fontSize);
    fontSizeListenable.value = fontSize;
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setThemeAccent(AppThemeAccent accent) async {
    if (_settings.themeAccent == accent) {
      return;
    }
    _settings = _settings.copyWith(themeAccent: accent);
    themeAccentListenable.value = accent;
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setAppNotificationsEnabled(bool value) async {
    if (_settings.appNotificationsEnabled == value) {
      return;
    }
    _settings = _settings.copyWith(appNotificationsEnabled: value);
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setTaskRemindersEnabled(bool value) async {
    if (_settings.taskRemindersEnabled == value) {
      return;
    }
    _settings = _settings.copyWith(taskRemindersEnabled: value);
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setExamRemindersEnabled(bool value) async {
    if (_settings.examRemindersEnabled == value) {
      return;
    }
    _settings = _settings.copyWith(examRemindersEnabled: value);
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setClassRemindersEnabled(bool value) async {
    if (_settings.classRemindersEnabled == value) {
      return;
    }
    _settings = _settings.copyWith(classRemindersEnabled: value);
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setLectureVibrationOnly(bool value) async {
    if (_settings.lectureVibrationOnly == value) {
      return;
    }
    _settings = _settings.copyWith(lectureVibrationOnly: value);
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setStudyGoalAlertsEnabled(bool value) async {
    if (_settings.studyGoalAlertsEnabled == value) {
      return;
    }
    _settings = _settings.copyWith(studyGoalAlertsEnabled: value);
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> setAutoSyncEnabled(bool value) async {
    if (_settings.autoSyncEnabled == value) {
      return;
    }
    _settings = _settings.copyWith(autoSyncEnabled: value);
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> updateSyncState({
    required SyncStatus status,
    DateTime? lastSyncCheckedAt,
    DateTime? lastSyncedAt,
    bool clearLastSyncCheckedAt = false,
    bool clearLastSyncedAt = false,
  }) async {
    final nextLastSyncCheckedAt = clearLastSyncCheckedAt
        ? null
        : lastSyncCheckedAt ?? _settings.lastSyncCheckedAt;
    final nextLastSyncedAt = clearLastSyncedAt
        ? null
        : lastSyncedAt ?? _settings.lastSyncedAt;
    if (_settings.syncStatus == status &&
        _settings.lastSyncCheckedAt == nextLastSyncCheckedAt &&
        _settings.lastSyncedAt == nextLastSyncedAt) {
      return;
    }

    _settings = _settings.copyWith(
      syncStatus: status,
      lastSyncCheckedAt: lastSyncCheckedAt,
      lastSyncedAt: lastSyncedAt,
      clearLastSyncCheckedAt: clearLastSyncCheckedAt,
      clearLastSyncedAt: clearLastSyncedAt,
    );
    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> updateReminderDefault(
    ReminderCategory category,
    String value,
  ) async {
    final currentValue = switch (category) {
      ReminderCategory.tasks => _settings.taskReminderDefault,
      ReminderCategory.exams => _settings.examReminderDefault,
      ReminderCategory.lectures => _settings.lectureReminderDefault,
    };
    if (currentValue == value) {
      return;
    }

    switch (category) {
      case ReminderCategory.tasks:
        _settings = _settings.copyWith(taskReminderDefault: value);
        break;
      case ReminderCategory.exams:
        _settings = _settings.copyWith(examReminderDefault: value);
        break;
      case ReminderCategory.lectures:
        _settings = _settings.copyWith(lectureReminderDefault: value);
        break;
    }

    notifyListeners();
    await _settingsService.save(_settings);
  }

  Future<void> runCloudBackup() async {
    if (isSyncing) return;

    _settings = _settings.copyWith(syncStatus: SyncStatus.syncing);
    notifyListeners();
    await _settingsService.save(_settings);

    await Future<void>.delayed(const Duration(milliseconds: 1400));

    _settings = _settings.copyWith(
      syncStatus: SyncStatus.stable,
      lastSyncedAt: DateTime.now(),
    );
    notifyListeners();
    await _settingsService.save(_settings);
  }

  @override
  void dispose() {
    themeModeListenable.dispose();
    fontSizeListenable.dispose();
    themeAccentListenable.dispose();
    super.dispose();
  }

  SyncDisplayStatus syncDisplayStatus({
    required bool isOffline,
    DateTime? now,
  }) {
    if (isSyncing) {
      return SyncDisplayStatus.syncing;
    }
    if (isOffline) {
      return SyncDisplayStatus.offline;
    }
    final resolvedNow = now ?? DateTime.now();
    final lastSyncedAt = _settings.lastSyncedAt;
    if (lastSyncedAt == null ||
        resolvedNow.difference(lastSyncedAt) > syncFreshnessWindow) {
      return SyncDisplayStatus.outdated;
    }
    return SyncDisplayStatus.stable;
  }

  bool shouldAutoRefresh({required bool isOffline, DateTime? now}) {
    if (isOffline) {
      return false;
    }
    final resolvedNow = now ?? DateTime.now();
    final status = syncDisplayStatus(isOffline: false, now: resolvedNow);
    if (lastSyncedAt == null || status == SyncDisplayStatus.outdated) {
      return true;
    }
    final lastCheckedAt = _settings.lastSyncCheckedAt;
    if (lastCheckedAt == null) {
      return true;
    }
    return resolvedNow.difference(lastCheckedAt) >= autoSyncInterval;
  }
}
