import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../app_controller.dart';
import '../models/calendar_entry.dart';
import '../models/planner_item.dart';
import 'calendar_repository.dart';
import 'classroom_visibility.dart';
import 'classroom_subject_identity.dart';
import 'database_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int _maxScheduledNotifications = 64;
  static const Duration _lookAhead = Duration(days: 60);
  static const Duration _minimumLeadTime = Duration(seconds: 20);
  static const Duration _lectureVibrationAlarmLength = Duration(minutes: 1);
  static const UriAndroidNotificationSound _defaultRingtoneSound =
      UriAndroidNotificationSound('content://settings/system/ringtone');
  static const String _remindersChannelId = 'studyflow_reminders_v2';
  static const String _scheduleVibrationChannelId =
      'studyflow_schedule_vibration_v6';
  static const String _scheduleAlertsChannelId = 'studyflow_schedule_alerts_v6';
  static const String _goalAlertsChannelId = 'studyflow_goal_alerts_v2';
  static const int _androidFlagInsistent = 4;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _supportedPlatform = false;
  bool _notificationPermissionsRequested = false;
  bool _exactAlarmPermissionRequested = false;
  bool _fullScreenIntentPermissionRequested = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      _initialized = true;
      _supportedPlatform = false;
      return;
    }

    tz_data.initializeTimeZones();
    await _configureLocalTimezone();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(settings: settings);

    await _configureAndroidChannels();

    _initialized = true;
    _supportedPlatform = true;
  }

  Future<void> _configureAndroidChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      return;
    }

    final lecturePattern = _lectureAlarmVibrationPattern();

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _remindersChannelId,
        'StudyFlow Reminders',
        description:
            'StudyFlow reminders for tasks, projects, exams, and general planner items.',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );

    await androidPlugin.createNotificationChannel(
      AndroidNotificationChannel(
        _scheduleVibrationChannelId,
        'StudyFlow Schedule Vibrations',
        description:
            'One-minute vibration alarms for StudyFlow schedules on Android.',
        importance: Importance.max,
        bypassDnd: true,
        playSound: false,
        enableVibration: true,
        vibrationPattern: lecturePattern,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      ),
    );

    await androidPlugin.createNotificationChannel(
      AndroidNotificationChannel(
        _scheduleAlertsChannelId,
        'StudyFlow Schedule Alarms',
        description:
            'Ringtone and vibration alarms for StudyFlow schedules on Android.',
        importance: Importance.max,
        bypassDnd: true,
        playSound: true,
        sound: _defaultRingtoneSound,
        enableVibration: true,
        vibrationPattern: lecturePattern,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _goalAlertsChannelId,
        'StudyFlow Goal Alerts',
        description:
            'StudyFlow goal alerts for overdue work, exam prep, and study planning.',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
  }

  Future<int> schedulePlannerItems({
    required Iterable<PlannerItem> items,
    required AppController controller,
  }) async {
    await initialize();
    if (!_supportedPlatform) {
      return 0;
    }

    final candidates = _buildScheduledCandidates(
      items: items,
      controller: controller,
    );

    await _plugin.cancelAll();
    if (candidates.isEmpty) {
      return 0;
    }

    final canUseExactAlarms = await _requestPermissions(
      includeExactAlarms: candidates.any((candidate) => candidate.prefersExact),
    );

    var scheduledCount = 0;
    for (final candidate in candidates.take(_maxScheduledNotifications)) {
      await _plugin.zonedSchedule(
        id: candidate.id,
        title: candidate.title,
        body: candidate.body,
        scheduledDate: tz.TZDateTime.from(candidate.triggerAt, tz.local),
        notificationDetails: candidate.details,
        androidScheduleMode: candidate.scheduleMode(
          canUseExactAlarms: canUseExactAlarms,
        ),
        payload: candidate.payload,
      );
      scheduledCount += 1;
    }

    return scheduledCount;
  }

  Future<void> ensurePermissionsRequested() async {
    await initialize();
    if (!_supportedPlatform) {
      return;
    }
    await _requestPermissions(includeExactAlarms: false);
  }

  Future<int> refreshForUser({
    required String uid,
    required AppController controller,
  }) async {
    final plannerItems = await DatabaseService.instance.getPlannerItems(uid);
    final snapshot = await CalendarRepository.instance
        .loadBestAvailableSnapshot(uid);
    final hiddenSubjectKeys = await DatabaseService.instance
        .getHiddenClassroomSubjectKeys(uid);
    final hiddenEntryIds = await DatabaseService.instance
        .getHiddenClassroomEntryIds(uid);

    final allClassroomEntries = snapshot?.entries ?? const <CalendarEntry>[];
    final classroomEntries = allClassroomEntries
        .where(
          (entry) => !isHiddenClassroomEntry(
            entry,
            hiddenSubjectKeys: hiddenSubjectKeys,
            hiddenEntryIds: hiddenEntryIds,
          ),
        )
        .toList();
    final hiddenPlannerSubjectIds = hiddenClassroomPlannerSubjectIds(
      allClassroomEntries,
      hiddenSubjectKeys,
    );
    final visiblePlannerItems = plannerItems.where(
      (item) => !isPlannerItemHiddenByClassroom(
        item,
        hiddenEntryIds: hiddenEntryIds,
        hiddenPlannerSubjectIds: hiddenPlannerSubjectIds,
      ),
    );
    final importedSourceIds = visiblePlannerItems
        .map((item) => item.sourceItemId)
        .whereType<String>()
        .toSet();
    final classroomItems = classroomEntries
        .where((entry) => !importedSourceIds.contains(entry.id))
        .map(
          (entry) => _plannerItemFromClassroomEntry(
            entry,
            taskReminderDefault: controller.taskReminderDefault,
          ),
        );

    return schedulePlannerItems(
      items: [...visiblePlannerItems, ...classroomItems],
      controller: controller,
    );
  }

  Future<void> cancelAllPlannerNotifications() async {
    await initialize();
    if (_supportedPlatform) {
      await _plugin.cancelAll();
    }
  }

  List<_ScheduledNotificationCandidate> _buildScheduledCandidates({
    required Iterable<PlannerItem> items,
    required AppController controller,
  }) {
    final list = <_ScheduledNotificationCandidate>[
      ..._buildReminderCandidates(items: items, controller: controller),
      ..._buildGoalAlertCandidates(items: items, controller: controller),
    ];
    list.sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    return list;
  }

  List<_ScheduledNotificationCandidate> _buildReminderCandidates({
    required Iterable<PlannerItem> items,
    required AppController controller,
  }) {
    final now = DateTime.now();
    final rangeEnd = now.add(_lookAhead);
    final candidates = <_ScheduledNotificationCandidate>[];

    for (final item in items) {
      if (!_canScheduleReminder(item, controller)) {
        continue;
      }

      final reminderOffset = _reminderOffsetFor(item, controller);
      final occurrences = item
          .occurrencesInRange(now, rangeEnd)
          .map((occurrence) => _baseReminderTime(item, occurrence))
          .toList();

      for (final occurrence in occurrences) {
        final triggerAt = occurrence.subtract(reminderOffset);
        if (!triggerAt.isAfter(now.add(_minimumLeadTime))) {
          continue;
        }

        candidates.add(
          _ScheduledNotificationCandidate(
            id: _stableNotificationId(
              '${item.id}|${occurrence.toIso8601String()}',
            ),
            triggerAt: triggerAt,
            title: _titleFor(item),
            body: _bodyFor(item, occurrence),
            payload: '${item.type.name}:${item.id}',
            details: _notificationDetails(item: item, controller: controller),
            prefersExact: true,
          ),
        );
      }
    }

    return candidates;
  }

  List<_ScheduledNotificationCandidate> _buildGoalAlertCandidates({
    required Iterable<PlannerItem> items,
    required AppController controller,
  }) {
    if (!controller.appNotificationsEnabled ||
        !controller.studyGoalAlertsEnabled) {
      return const <_ScheduledNotificationCandidate>[];
    }

    final now = DateTime.now();
    final openItems = items
        .where(
          (item) => !item.isCompleted && !item.isArchived && !item.isDeleted,
        )
        .toList();
    if (openItems.isEmpty) {
      return const <_ScheduledNotificationCandidate>[];
    }

    final candidates = <_ScheduledNotificationCandidate>[];
    final overdueItems = openItems
        .where((item) => item.canBeCompleted && _isPastDue(item, now))
        .toList();
    if (overdueItems.isNotEmpty) {
      final triggerAt = _nextDailyTrigger(
        now,
        const Duration(hours: 7, minutes: 30),
      );
      candidates.add(
        _ScheduledNotificationCandidate(
          id: _stableNotificationId(
            'goal:overdue:${triggerAt.toIso8601String()}',
          ),
          triggerAt: triggerAt,
          title: 'Study goal check-in',
          body:
              'You have ${overdueItems.length} overdue ${overdueItems.length == 1 ? 'item' : 'items'} to review. Finish what is done and clear the rest.',
          payload: 'goal:overdue',
          details: _goalAlertDetails(),
          prefersExact: false,
        ),
      );
    }

    final upcomingExams =
        openItems
            .where((item) => item.type == PlannerItemType.exam)
            .where((item) => item.scheduledAt != null)
            .where((item) => item.scheduledAt!.isAfter(now))
            .where(
              (item) =>
                  item.scheduledAt!.isBefore(now.add(const Duration(days: 3))),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    if (upcomingExams.isNotEmpty) {
      final exam = upcomingExams.first;
      final scheduledAt = exam.scheduledAt!;
      final prepTrigger = exam.hasExplicitTime
          ? scheduledAt.subtract(const Duration(hours: 18))
          : DateTime(
              scheduledAt.year,
              scheduledAt.month,
              scheduledAt.day,
              18,
            ).subtract(const Duration(days: 1));
      if (prepTrigger.isAfter(now.add(_minimumLeadTime))) {
        candidates.add(
          _ScheduledNotificationCandidate(
            id: _stableNotificationId(
              'goal:exam:${exam.id}:${prepTrigger.toIso8601String()}',
            ),
            triggerAt: prepTrigger,
            title: 'Exam prep reminder',
            body:
                '${exam.title} is coming up on ${_dateLabel(scheduledAt)}. Set aside time to review tonight.',
            payload: 'goal:exam:${exam.id}',
            details: _goalAlertDetails(),
            prefersExact: false,
          ),
        );
      }
    }

    final deadlinesTomorrow = openItems
        .where((item) => item.type != PlannerItemType.schedule)
        .where((item) => item.scheduledAt != null)
        .where(
          (item) =>
              _sameDay(item.scheduledAt!, now.add(const Duration(days: 1))),
        )
        .toList();
    if (deadlinesTomorrow.isNotEmpty && !_hasScheduleTomorrow(openItems, now)) {
      final triggerAt = _eveningAnchor(now);
      if (triggerAt.isAfter(now.add(_minimumLeadTime))) {
        candidates.add(
          _ScheduledNotificationCandidate(
            id: _stableNotificationId(
              'goal:schedule-gap:${triggerAt.toIso8601String()}',
            ),
            triggerAt: triggerAt,
            title: 'Plan a study block',
            body:
                'You have ${deadlinesTomorrow.length} deadline${deadlinesTomorrow.length == 1 ? '' : 's'} tomorrow and no schedule block planned yet.',
            payload: 'goal:schedule-gap',
            details: _goalAlertDetails(),
            prefersExact: false,
          ),
        );
      }
    }

    candidates.sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    return candidates;
  }

  bool _canScheduleReminder(PlannerItem item, AppController controller) {
    if (!controller.appNotificationsEnabled ||
        !item.reminderEnabled ||
        item.isCompleted ||
        item.isArchived ||
        item.isDeleted ||
        item.scheduledAt == null) {
      return false;
    }

    switch (item.type) {
      case PlannerItemType.schedule:
        return controller.classRemindersEnabled;
      case PlannerItemType.exam:
        return controller.examRemindersEnabled;
      case PlannerItemType.task:
      case PlannerItemType.project:
        return controller.taskRemindersEnabled;
    }
  }

  Duration _reminderOffsetFor(PlannerItem item, AppController controller) {
    final label = item.reminderLabel ?? _defaultReminderLabel(item, controller);
    return parseReminderOffset(label);
  }

  String _defaultReminderLabel(PlannerItem item, AppController controller) {
    switch (item.type) {
      case PlannerItemType.exam:
        return controller.examReminderDefault;
      case PlannerItemType.schedule:
        return controller.lectureReminderDefault;
      case PlannerItemType.task:
      case PlannerItemType.project:
        return controller.taskReminderDefault;
    }
  }

  DateTime _baseReminderTime(PlannerItem item, DateTime occurrence) {
    if (item.hasExplicitTime || item.type == PlannerItemType.schedule) {
      return occurrence;
    }

    return DateTime(occurrence.year, occurrence.month, occurrence.day, 9);
  }

  NotificationDetails _notificationDetails({
    required PlannerItem item,
    required AppController controller,
  }) {
    final isLecture = item.type == PlannerItemType.schedule;
    final useVibrationOnly = isLecture && controller.lectureVibrationOnly;
    final channelId = !isLecture
        ? _remindersChannelId
        : useVibrationOnly
        ? _scheduleVibrationChannelId
        : _scheduleAlertsChannelId;
    final channelName = !isLecture
        ? 'StudyFlow Reminders'
        : useVibrationOnly
        ? 'StudyFlow Schedule Vibrations'
        : 'StudyFlow Schedule Alarms';
    final lectureVibrationPattern = isLecture
        ? _lectureAlarmVibrationPattern()
        : null;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription:
            'StudyFlow reminders for schedules, exams, quizzes, and tasks.',
        importance: isLecture ? Importance.max : Importance.high,
        priority: isLecture ? Priority.max : Priority.high,
        fullScreenIntent: isLecture && !useVibrationOnly,
        visibility: isLecture ? NotificationVisibility.public : null,
        channelBypassDnd: isLecture,
        channelAction: isLecture
            ? AndroidNotificationChannelAction.update
            : AndroidNotificationChannelAction.createIfNotExists,
        category: isLecture
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,
        playSound: !useVibrationOnly,
        sound: isLecture && !useVibrationOnly ? _defaultRingtoneSound : null,
        enableVibration: isLecture || !useVibrationOnly,
        vibrationPattern: lectureVibrationPattern,
        timeoutAfter: isLecture
            ? _lectureVibrationAlarmLength.inMilliseconds
            : null,
        ongoing: isLecture,
        autoCancel: !isLecture,
        onlyAlertOnce: !isLecture,
        additionalFlags: isLecture
            ? Int32List.fromList(const <int>[_androidFlagInsistent])
            : null,
        audioAttributesUsage: isLecture
            ? useVibrationOnly
                  ? AudioAttributesUsage.notificationRingtone
                  : AudioAttributesUsage.notificationRingtone
            : AudioAttributesUsage.notification,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: !useVibrationOnly,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: !useVibrationOnly,
      ),
    );
  }

  NotificationDetails _goalAlertDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _goalAlertsChannelId,
        'StudyFlow Goal Alerts',
        channelDescription:
            'StudyFlow goal alerts for overdue work, exam prep, and study planning.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: true,
        enableVibration: true,
        onlyAlertOnce: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  String _titleFor(PlannerItem item) {
    switch (item.type) {
      case PlannerItemType.exam:
        return 'Exam & quiz reminder';
      case PlannerItemType.schedule:
        return 'Class schedule reminder';
      case PlannerItemType.project:
        return 'Project reminder';
      case PlannerItemType.task:
        return 'Task reminder';
    }
  }

  String _bodyFor(PlannerItem item, DateTime occurrence) {
    final subject = (item.subjectName ?? item.subjectCode ?? '').trim();
    final subjectPrefix = subject.isEmpty ? '' : '$subject: ';
    final time = _timeLabel(occurrence);
    final isDateOnly =
        !item.hasExplicitTime && item.type != PlannerItemType.schedule;

    switch (item.type) {
      case PlannerItemType.exam:
        return '$subjectPrefix${item.title} is scheduled for ${_dateLabel(occurrence)} at $time.';
      case PlannerItemType.schedule:
        final end = item.occurrenceEndAt(occurrence);
        final location = (item.location ?? '').trim();
        final locationSuffix = location.isEmpty ? '' : ' Location: $location.';
        return end != null && end.isAfter(occurrence)
            ? '$subjectPrefix${item.title} runs from $time to ${_timeLabel(end)}.$locationSuffix'
            : '$subjectPrefix${item.title} starts at $time.$locationSuffix';
      case PlannerItemType.project:
        return isDateOnly
            ? '$subjectPrefix${item.title} is due on ${_dateLabel(occurrence)}.'
            : '$subjectPrefix${item.title} is due ${_dateLabel(occurrence)} at $time.';
      case PlannerItemType.task:
        return isDateOnly
            ? '$subjectPrefix${item.title} is due on ${_dateLabel(occurrence)}.'
            : '$subjectPrefix${item.title} is due ${_dateLabel(occurrence)} at $time.';
    }
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } catch (error) {
      debugPrint('StudyFlow notifications using default timezone: $error');
    }
  }

  Future<bool> _requestPermissions({
    required bool includeExactAlarms,
    bool includePolicyAccess = false,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin == null) {
        return false;
      }

      if (!_notificationPermissionsRequested) {
        _notificationPermissionsRequested = true;
        await androidPlugin.requestNotificationsPermission();
      }

      return _requestAndroidPermissions(
        androidPlugin,
        includeExactAlarms: includeExactAlarms,
        includePolicyAccess: includePolicyAccess,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (!_notificationPermissionsRequested) {
        _notificationPermissionsRequested = true;
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
      return true;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      if (!_notificationPermissionsRequested) {
        _notificationPermissionsRequested = true;
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
      return true;
    }

    return false;
  }

  Future<bool> _requestAndroidPermissions(
    AndroidFlutterLocalNotificationsPlugin androidPlugin, {
    required bool includeExactAlarms,
    required bool includePolicyAccess,
  }) async {
    if (!includeExactAlarms) {
      if (includePolicyAccess) {
        await androidPlugin.requestNotificationPolicyAccess();
        await _configureAndroidChannels();
      }
      return await androidPlugin.canScheduleExactNotifications() ?? false;
    }

    var canUseExactAlarms =
        await androidPlugin.canScheduleExactNotifications() ?? false;
    if (!canUseExactAlarms && !_exactAlarmPermissionRequested) {
      _exactAlarmPermissionRequested = true;
      await androidPlugin.requestExactAlarmsPermission();
      canUseExactAlarms =
          await androidPlugin.canScheduleExactNotifications() ?? false;
    }
    if (!_fullScreenIntentPermissionRequested) {
      _fullScreenIntentPermissionRequested = true;
      await androidPlugin.requestFullScreenIntentPermission();
    }
    if (includePolicyAccess) {
      await androidPlugin.requestNotificationPolicyAccess();
      await _configureAndroidChannels();
    }
    return canUseExactAlarms;
  }

  static Duration parseReminderOffset(String label) {
    final normalized = label.trim().toLowerCase();
    final amount = int.tryParse(
      RegExp(r'\d+').firstMatch(normalized)?.group(0) ?? '',
    );
    if (amount == null) {
      return const Duration(minutes: 15);
    }

    if (normalized.contains('week')) {
      return Duration(days: amount * 7);
    }
    if (normalized.contains('day')) {
      return Duration(days: amount);
    }
    if (normalized.contains('hour') || normalized.contains(RegExp(r'\bh\b'))) {
      return Duration(hours: amount);
    }
    return Duration(minutes: amount);
  }

  static int _stableNotificationId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static Int64List _lectureAlarmVibrationPattern() {
    final pattern = <int>[0];
    const vibrationMs = 1000;
    const pauseMs = 500;
    const cycleCount = 40; // 40 * (1000 + 500) = 60 seconds
    for (var index = 0; index < cycleCount; index += 1) {
      pattern
        ..add(vibrationMs)
        ..add(pauseMs);
    }
    return Int64List.fromList(pattern);
  }

  static String _dateLabel(DateTime value) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}';
  }

  static String _timeLabel(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  static PlannerItem _plannerItemFromClassroomEntry(
    CalendarEntry entry, {
    required String taskReminderDefault,
  }) {
    final subjectName = entry.subject.trim().isEmpty
        ? 'Classroom'
        : entry.subject.trim();
    return PlannerItem(
      id: 'classroom::${entry.id}',
      title: entry.title,
      subjectId: classroomPlannerSubjectId(
        classroomSubjectStorageKeyForEntry(entry),
      ),
      subjectName: subjectName,
      sourceItemId: entry.id,
      type: PlannerItemType.task,
      priority: entry.tone == CalendarEntryTone.critical
          ? PlannerItemPriority.high
          : PlannerItemPriority.medium,
      description: entry.description,
      categoryLabel: 'Classroom Task',
      status: entry.isCompleted
          ? PlannerItemStatus.completed
          : PlannerItemStatus.active,
      scheduledAt: entry.scheduledDate,
      hasExplicitTime: entry.scheduledDate != null,
      reminderEnabled: entry.hasReminder,
      reminderLabel: entry.hasReminder ? taskReminderDefault : null,
      autoCompleteFromSubtasks: false,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool _isPastDue(PlannerItem item, DateTime now) {
    final scheduledAt = item.scheduledAt;
    if (item.isCompleted || scheduledAt == null || !item.canBeCompleted) {
      return false;
    }
    if (item.hasExplicitTime) {
      return scheduledAt.isBefore(now);
    }
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
    );
    return dueDate.isBefore(today);
  }

  static bool _hasScheduleTomorrow(List<PlannerItem> items, DateTime now) {
    final tomorrowStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final tomorrowEnd = DateTime(
      tomorrowStart.year,
      tomorrowStart.month,
      tomorrowStart.day,
      23,
      59,
      59,
    );
    return items
        .where((item) => item.type == PlannerItemType.schedule)
        .any(
          (item) =>
              item.occurrencesInRange(tomorrowStart, tomorrowEnd).isNotEmpty,
        );
  }

  static DateTime _nextDailyTrigger(DateTime now, Duration timeOfDay) {
    final candidate = DateTime(now.year, now.month, now.day).add(timeOfDay);
    if (candidate.isAfter(now.add(_minimumLeadTime))) {
      return candidate;
    }
    return candidate.add(const Duration(days: 1));
  }

  static DateTime _eveningAnchor(DateTime now) {
    return DateTime(now.year, now.month, now.day, 20);
  }
}

class _ScheduledNotificationCandidate {
  const _ScheduledNotificationCandidate({
    required this.id,
    required this.triggerAt,
    required this.title,
    required this.body,
    required this.payload,
    required this.details,
    required this.prefersExact,
  });

  final int id;
  final DateTime triggerAt;
  final String title;
  final String body;
  final String payload;
  final NotificationDetails details;
  final bool prefersExact;

  AndroidScheduleMode scheduleMode({required bool canUseExactAlarms}) {
    if (prefersExact && canUseExactAlarms) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }
}
