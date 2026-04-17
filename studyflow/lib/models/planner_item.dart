enum PlannerItemType { task, project, exam, schedule }

enum PlannerItemPriority { high, medium, low, optional }

enum PlannerItemStatus { active, completed, archived }

enum PlannerRepeatPattern { none, daily, weekly, monthly }

class PlannerSubtask {
  const PlannerSubtask({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.completedAt,
  });

  final String id;
  final String title;
  final bool isCompleted;
  final DateTime? completedAt;

  PlannerSubtask copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return PlannerSubtask(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory PlannerSubtask.fromJson(Map<String, Object?> json) {
    return PlannerSubtask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString().trim() ?? '',
      isCompleted: json['isCompleted'] == true,
      completedAt: _parseDateTime(json['completedAt']),
    );
  }
}

class PlannerScheduleSlot {
  const PlannerScheduleSlot({
    required this.id,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    this.label,
  });

  final String id;
  final int weekday;
  final int startMinutes;
  final int endMinutes;
  final String? label;

  String get weekdayLabel {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Day $weekday';
    }
  }

  String get timeRangeLabel {
    return '${_formatMinutes(startMinutes)}-${_formatMinutes(endMinutes)}';
  }

  PlannerScheduleSlot copyWith({
    String? id,
    int? weekday,
    int? startMinutes,
    int? endMinutes,
    String? label,
    bool clearLabel = false,
  }) {
    return PlannerScheduleSlot(
      id: id ?? this.id,
      weekday: weekday ?? this.weekday,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      label: clearLabel ? null : label ?? this.label,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'weekday': weekday,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'label': label,
    };
  }

  factory PlannerScheduleSlot.fromJson(Map<String, Object?> json) {
    return PlannerScheduleSlot(
      id: json['id']?.toString() ?? '',
      weekday: _parseInt(json['weekday'], DateTime.monday),
      startMinutes: _parseInt(json['startMinutes'], 9 * 60),
      endMinutes: _parseInt(json['endMinutes'], 10 * 60),
      label: _nullableText(json['label']),
    );
  }
}

class PlannerItem {
  const PlannerItem({
    required this.id,
    required this.title,
    required this.subjectId,
    required this.type,
    required this.priority,
    this.subjectCode,
    this.subjectName,
    this.sourceItemId,
    this.description,
    this.notes,
    this.location,
    this.categoryLabel,
    this.status = PlannerItemStatus.active,
    this.scheduledAt,
    this.endAt,
    this.hasExplicitTime = false,
    this.reminderEnabled = false,
    this.reminderLabel,
    this.repeatPattern = PlannerRepeatPattern.none,
    this.repeatUntil,
    this.scheduleSlots = const <PlannerScheduleSlot>[],
    this.autoCompleteFromSubtasks = true,
    this.subtasks = const <PlannerSubtask>[],
    this.completedAt,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String subjectId;
  final PlannerItemType type;
  final PlannerItemPriority priority;
  final String? subjectCode;
  final String? subjectName;
  final String? sourceItemId;
  final String? description;
  final String? notes;
  final String? location;
  final String? categoryLabel;
  final PlannerItemStatus status;
  final DateTime? scheduledAt;
  final DateTime? endAt;
  final bool hasExplicitTime;
  final bool reminderEnabled;
  final String? reminderLabel;
  final PlannerRepeatPattern repeatPattern;
  final DateTime? repeatUntil;
  final List<PlannerScheduleSlot> scheduleSlots;
  final bool autoCompleteFromSubtasks;
  final List<PlannerSubtask> subtasks;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  bool get isCompleted => status == PlannerItemStatus.completed;

  bool get isArchived => status == PlannerItemStatus.archived;

  bool get isDeleted => deletedAt != null;

  bool get canBeCompleted => type != PlannerItemType.schedule;

  bool get isClassroomBacked =>
      id.startsWith('classroom::') || (sourceItemId ?? '').isNotEmpty;

  bool get supportsRepeat => type == PlannerItemType.schedule;

  bool get hasSubtasks => subtasks.isNotEmpty;

  bool get allSubtasksCompleted =>
      subtasks.isNotEmpty && subtasks.every((subtask) => subtask.isCompleted);

  bool get isDueSoon {
    if (isCompleted || scheduledAt == null || !canBeCompleted) {
      return false;
    }

    return scheduledAt!.difference(DateTime.now()) <= const Duration(days: 1);
  }

  PlannerItemPriority get effectivePriority {
    if (isDueSoon) {
      return PlannerItemPriority.high;
    }
    return priority;
  }

  bool get isOverdue {
    if (isCompleted || scheduledAt == null) {
      return false;
    }

    return scheduledAt!.isBefore(DateTime.now());
  }

  String get typeLabel {
    switch (type) {
      case PlannerItemType.task:
        return 'Task';
      case PlannerItemType.project:
        return 'Project';
      case PlannerItemType.exam:
        return 'Exam';
      case PlannerItemType.schedule:
        return 'Schedule';
    }
  }

  String get priorityLabel {
    switch (effectivePriority) {
      case PlannerItemPriority.high:
        return 'High Priority';
      case PlannerItemPriority.medium:
        return 'Medium';
      case PlannerItemPriority.low:
        return 'Low Priority';
      case PlannerItemPriority.optional:
        return 'Optional';
    }
  }

  String get repeatLabel {
    switch (repeatPattern) {
      case PlannerRepeatPattern.none:
        return 'Does not repeat';
      case PlannerRepeatPattern.daily:
        return 'Repeats daily';
      case PlannerRepeatPattern.weekly:
        return 'Repeats weekly';
      case PlannerRepeatPattern.monthly:
        return 'Repeats monthly';
    }
  }

  PlannerItem copyWith({
    String? id,
    String? title,
    String? subjectId,
    PlannerItemType? type,
    PlannerItemPriority? priority,
    String? subjectCode,
    String? subjectName,
    String? sourceItemId,
    String? description,
    String? notes,
    String? location,
    String? categoryLabel,
    PlannerItemStatus? status,
    DateTime? scheduledAt,
    DateTime? endAt,
    bool? hasExplicitTime,
    bool? reminderEnabled,
    String? reminderLabel,
    PlannerRepeatPattern? repeatPattern,
    DateTime? repeatUntil,
    List<PlannerScheduleSlot>? scheduleSlots,
    bool? autoCompleteFromSubtasks,
    List<PlannerSubtask>? subtasks,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDescription = false,
    bool clearSubjectName = false,
    bool clearSourceItemId = false,
    bool clearNotes = false,
    bool clearLocation = false,
    bool clearCategoryLabel = false,
    bool clearScheduledAt = false,
    bool clearEndAt = false,
    bool clearReminderLabel = false,
    bool clearRepeatUntil = false,
    bool clearCompletedAt = false,
    bool clearCreatedAt = false,
    bool clearUpdatedAt = false,
    bool clearDeletedAt = false,
  }) {
    return PlannerItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subjectId: subjectId ?? this.subjectId,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      subjectCode: subjectCode ?? this.subjectCode,
      subjectName: clearSubjectName ? null : subjectName ?? this.subjectName,
      sourceItemId: clearSourceItemId
          ? null
          : sourceItemId ?? this.sourceItemId,
      description: clearDescription ? null : description ?? this.description,
      notes: clearNotes ? null : notes ?? this.notes,
      location: clearLocation ? null : location ?? this.location,
      categoryLabel: clearCategoryLabel
          ? null
          : categoryLabel ?? this.categoryLabel,
      status: status ?? this.status,
      scheduledAt: clearScheduledAt ? null : scheduledAt ?? this.scheduledAt,
      endAt: clearEndAt ? null : endAt ?? this.endAt,
      hasExplicitTime: hasExplicitTime ?? this.hasExplicitTime,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderLabel: clearReminderLabel
          ? null
          : reminderLabel ?? this.reminderLabel,
      repeatPattern: repeatPattern ?? this.repeatPattern,
      repeatUntil: clearRepeatUntil ? null : repeatUntil ?? this.repeatUntil,
      scheduleSlots: scheduleSlots ?? this.scheduleSlots,
      autoCompleteFromSubtasks:
          autoCompleteFromSubtasks ?? this.autoCompleteFromSubtasks,
      subtasks: subtasks ?? this.subtasks,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      createdAt: clearCreatedAt ? null : createdAt ?? this.createdAt,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  PlannerItem normalizedForSave() {
    final now = DateTime.now();
    var nextStatus = status;
    var nextCompletedAt = completedAt;
    var nextSubtasks = subtasks;

    if (!canBeCompleted && nextStatus == PlannerItemStatus.completed) {
      nextStatus = PlannerItemStatus.active;
      nextCompletedAt = null;
    }

    if (autoCompleteFromSubtasks &&
        canBeCompleted &&
        !isClassroomBacked &&
        subtasks.isNotEmpty &&
        subtasks.every((subtask) => subtask.isCompleted)) {
      nextStatus = PlannerItemStatus.completed;
      nextCompletedAt ??= now;
    } else if (nextStatus == PlannerItemStatus.completed) {
      nextCompletedAt ??= now;
    } else {
      nextCompletedAt = null;
    }

    if (nextStatus == PlannerItemStatus.completed && subtasks.isNotEmpty) {
      nextSubtasks = subtasks
          .map(
            (subtask) => subtask.isCompleted
                ? subtask
                : subtask.copyWith(isCompleted: true, completedAt: now),
          )
          .toList();
    }

    return copyWith(
      status: nextStatus,
      completedAt: nextCompletedAt,
      subtasks: nextSubtasks,
      clearCompletedAt: nextCompletedAt == null,
    );
  }

  DateTime? nextOccurrenceOnOrAfter(DateTime start) {
    if (type == PlannerItemType.schedule && scheduleSlots.isNotEmpty) {
      final searchEnd = repeatUntil ?? start.add(const Duration(days: 370));
      final occurrences = occurrencesInRange(start, searchEnd);
      if (occurrences.isEmpty) {
        return null;
      }
      return occurrences.first;
    }

    final first = scheduledAt;
    if (first == null) {
      return null;
    }

    if (repeatPattern == PlannerRepeatPattern.none) {
      return first.isBefore(start) ? null : first;
    }

    var current = first;
    var guard = 0;
    while (current.isBefore(start) && guard < 512) {
      current = _advanceOccurrence(current);
      guard += 1;
    }

    if (repeatUntil != null && current.isAfter(repeatUntil!)) {
      return null;
    }

    return current;
  }

  List<DateTime> occurrencesInRange(DateTime start, DateTime end) {
    if (type == PlannerItemType.schedule && scheduleSlots.isNotEmpty) {
      return _slotOccurrencesInRange(start, end);
    }

    final first = scheduledAt;
    if (first == null) {
      return const <DateTime>[];
    }

    if (repeatPattern == PlannerRepeatPattern.none) {
      if (_isWithinRange(first, start, end)) {
        return <DateTime>[first];
      }
      return const <DateTime>[];
    }

    final results = <DateTime>[];
    var current = first;
    var guard = 0;

    while (current.isBefore(start) && guard < 512) {
      current = _advanceOccurrence(current);
      guard += 1;
    }

    while ((current.isBefore(end) || current.isAtSameMomentAs(end)) &&
        guard < 1024) {
      if (repeatUntil != null && current.isAfter(repeatUntil!)) {
        break;
      }
      if (_isWithinRange(current, start, end)) {
        results.add(current);
      }
      current = _advanceOccurrence(current);
      guard += 1;
    }

    return results;
  }

  PlannerScheduleSlot? scheduleSlotForOccurrence(DateTime occurrence) {
    if (type != PlannerItemType.schedule || scheduleSlots.isEmpty) {
      return null;
    }

    final occurrenceMinutes = occurrence.hour * 60 + occurrence.minute;
    for (final slot in scheduleSlots) {
      if (slot.weekday == occurrence.weekday &&
          slot.startMinutes == occurrenceMinutes) {
        return slot;
      }
    }
    return null;
  }

  DateTime? occurrenceEndAt(DateTime occurrence) {
    final slot = scheduleSlotForOccurrence(occurrence);
    if (slot != null) {
      return DateTime(
        occurrence.year,
        occurrence.month,
        occurrence.day,
        slot.endMinutes ~/ 60,
        slot.endMinutes % 60,
      );
    }

    final start = scheduledAt;
    final end = endAt;
    if (start == null || end == null) {
      return end;
    }

    final duration = end.difference(start);
    if (duration.isNegative || duration == Duration.zero) {
      return end;
    }
    return occurrence.add(duration);
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'subjectId': subjectId,
      'subjectCode': subjectCode,
      'subjectName': subjectName,
      'sourceItemId': sourceItemId,
      'description': description,
      'notes': notes,
      'location': location,
      'categoryLabel': categoryLabel,
      'type': type.name,
      'priority': priority.name,
      'status': status.name,
      'scheduledAt': scheduledAt?.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
      'hasExplicitTime': hasExplicitTime,
      'reminderEnabled': reminderEnabled,
      'reminderLabel': reminderLabel,
      'repeatPattern': repeatPattern.name,
      'repeatUntil': repeatUntil?.toIso8601String(),
      'scheduleSlots': scheduleSlots.map((slot) => slot.toJson()).toList(),
      'autoCompleteFromSubtasks': autoCompleteFromSubtasks,
      'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
      'completedAt': completedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }

  factory PlannerItem.fromJson(String id, Map<String, Object?> json) {
    final subtasksJson = json['subtasks'];
    final scheduleSlotsJson = json['scheduleSlots'];
    return PlannerItem(
      id: id,
      title: json['title']?.toString().trim() ?? '',
      subjectId: json['subjectId']?.toString() ?? '',
      subjectCode: _nullableText(json['subjectCode']),
      subjectName: _nullableText(json['subjectName']),
      sourceItemId: _nullableText(json['sourceItemId']),
      description: _nullableText(json['description']),
      notes: _nullableText(json['notes']),
      location: _nullableText(json['location']),
      categoryLabel: _nullableText(json['categoryLabel']),
      type: _parseType(json['type']?.toString()),
      priority: _parsePriority(json['priority']?.toString()),
      status: _parseStatus(json['status']?.toString()),
      scheduledAt: _parseDateTime(json['scheduledAt']),
      endAt: _parseDateTime(json['endAt']),
      hasExplicitTime: json['hasExplicitTime'] == true,
      reminderEnabled: json['reminderEnabled'] == true,
      reminderLabel: _nullableText(json['reminderLabel']),
      repeatPattern: _parseRepeatPattern(json['repeatPattern']?.toString()),
      repeatUntil: _parseDateTime(json['repeatUntil']),
      scheduleSlots: _parseScheduleSlots(scheduleSlotsJson),
      autoCompleteFromSubtasks: json['autoCompleteFromSubtasks'] != false,
      subtasks: _parseSubtasks(subtasksJson),
      completedAt: _parseDateTime(json['completedAt']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      deletedAt: _parseDateTime(json['deletedAt']),
    );
  }

  DateTime _advanceOccurrence(DateTime current) {
    switch (repeatPattern) {
      case PlannerRepeatPattern.none:
        return current;
      case PlannerRepeatPattern.daily:
        return current.add(const Duration(days: 1));
      case PlannerRepeatPattern.weekly:
        return current.add(const Duration(days: 7));
      case PlannerRepeatPattern.monthly:
        return _copyWithMonth(current, current.month + 1);
    }
  }

  List<DateTime> _slotOccurrencesInRange(DateTime start, DateTime end) {
    final first = scheduledAt;
    if (first == null || end.isBefore(start)) {
      return const <DateTime>[];
    }

    final startBoundary = _dateOnly(first);
    final repeatEnd = repeatUntil == null
        ? null
        : DateTime(
            repeatUntil!.year,
            repeatUntil!.month,
            repeatUntil!.day,
            23,
            59,
            59,
          );
    final searchStart = start.isAfter(startBoundary)
        ? _dateOnly(start)
        : startBoundary;
    final searchEnd = _dateOnly(end);
    final results = <DateTime>[];
    var day = searchStart;
    var guard = 0;

    while (!day.isAfter(searchEnd) && guard < 4096) {
      if (repeatEnd != null && day.isAfter(_dateOnly(repeatEnd))) {
        break;
      }

      for (final slot in scheduleSlots) {
        if (slot.weekday != day.weekday) {
          continue;
        }
        final occurrence = DateTime(
          day.year,
          day.month,
          day.day,
          slot.startMinutes ~/ 60,
          slot.startMinutes % 60,
        );
        if (occurrence.isBefore(first)) {
          continue;
        }
        if (repeatEnd != null && occurrence.isAfter(repeatEnd)) {
          continue;
        }
        if (_isWithinRange(occurrence, start, end)) {
          results.add(occurrence);
        }
      }

      day = day.add(const Duration(days: 1));
      guard += 1;
    }

    results.sort();
    return results;
  }

  static bool _isWithinRange(DateTime value, DateTime start, DateTime end) {
    return (value.isAfter(start) || value.isAtSameMomentAs(start)) &&
        (value.isBefore(end) || value.isAtSameMomentAs(end));
  }

  static PlannerItemType _parseType(String? value) {
    for (final type in PlannerItemType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return PlannerItemType.task;
  }

  static PlannerItemPriority _parsePriority(String? value) {
    for (final priority in PlannerItemPriority.values) {
      if (priority.name == value) {
        return priority;
      }
    }
    return PlannerItemPriority.medium;
  }

  static PlannerItemStatus _parseStatus(String? value) {
    for (final status in PlannerItemStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return PlannerItemStatus.active;
  }

  static PlannerRepeatPattern _parseRepeatPattern(String? value) {
    for (final pattern in PlannerRepeatPattern.values) {
      if (pattern.name == value) {
        return pattern;
      }
    }
    return PlannerRepeatPattern.none;
  }

  static List<PlannerSubtask> _parseSubtasks(Object? value) {
    if (value is! List) {
      return const <PlannerSubtask>[];
    }

    return value
        .whereType<Map>()
        .map(
          (entry) => PlannerSubtask.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((subtask) => subtask.title.isNotEmpty)
        .toList();
  }

  static List<PlannerScheduleSlot> _parseScheduleSlots(Object? value) {
    Iterable<Object?> entries;
    if (value is List) {
      entries = value;
    } else if (value is Map) {
      entries = value.values;
    } else {
      return const <PlannerScheduleSlot>[];
    }

    return entries
        .whereType<Map>()
        .map(
          (entry) => PlannerScheduleSlot.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where(
          (slot) =>
              slot.id.isNotEmpty &&
              slot.weekday >= DateTime.monday &&
              slot.weekday <= DateTime.sunday &&
              slot.startMinutes >= 0 &&
              slot.startMinutes < 24 * 60 &&
              slot.endMinutes > slot.startMinutes &&
              slot.endMinutes <= 24 * 60,
        )
        .toList()
      ..sort((a, b) {
        final dayCompare = a.weekday.compareTo(b.weekday);
        if (dayCompare != 0) {
          return dayCompare;
        }
        return a.startMinutes.compareTo(b.startMinutes);
      });
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.round());
  }

  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  final parsed = DateTime.tryParse(raw);
  if (parsed != null) {
    return parsed;
  }

  final epochMillis = int.tryParse(raw);
  if (epochMillis != null) {
    return DateTime.fromMillisecondsSinceEpoch(epochMillis);
  }

  return null;
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }

  return text;
}

int _parseInt(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _formatMinutes(int minutes) {
  final hour24 = minutes ~/ 60;
  final minute = minutes % 60;
  final hour = hour24 == 0
      ? 12
      : hour24 > 12
      ? hour24 - 12
      : hour24;
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  if (minute == 0) {
    return '$hour$suffix';
  }
  return '$hour:${minute.toString().padLeft(2, '0')}$suffix';
}

DateTime _copyWithMonth(DateTime source, int month) {
  final normalizedYear = source.year + ((month - 1) ~/ 12);
  final normalizedMonth = ((month - 1) % 12) + 1;
  final maxDay = DateTime(normalizedYear, normalizedMonth + 1, 0).day;
  final safeDay = source.day > maxDay ? maxDay : source.day;

  return DateTime(
    normalizedYear,
    normalizedMonth,
    safeDay,
    source.hour,
    source.minute,
    source.second,
    source.millisecond,
    source.microsecond,
  );
}
