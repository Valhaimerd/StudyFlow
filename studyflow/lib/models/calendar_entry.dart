import 'planner_item.dart';

enum CalendarEntryType { exam, task, project, lab }

enum CalendarEntryTone { critical, project, laboratory, openEnded, completed }

enum CalendarSubjectSource { manual, classroom, unknown }

class CalendarEntry {
  const CalendarEntry({
    required this.id,
    required this.subject,
    required this.title,
    required this.description,
    required this.type,
    required this.tone,
    this.subjectKey,
    this.subjectSource = CalendarSubjectSource.unknown,
    this.scheduledDate,
    this.endDate,
    this.plannerType,
    this.badgeLabel,
    this.alternateLink,
    this.isCompleted = false,
    this.hasReminder = false,
  });

  final String id;
  final String subject;
  final String title;
  final String description;
  final CalendarEntryType type;
  final CalendarEntryTone tone;
  final String? subjectKey;
  final CalendarSubjectSource subjectSource;
  final DateTime? scheduledDate;
  final DateTime? endDate;
  final PlannerItemType? plannerType;
  final String? badgeLabel;
  final String? alternateLink;
  final bool isCompleted;
  final bool hasReminder;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'subject': subject,
      'title': title,
      'description': description,
      'type': type.name,
      'tone': tone.name,
      'subjectKey': subjectKey,
      'subjectSource': subjectSource.name,
      'scheduledDate': scheduledDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'plannerType': plannerType?.name,
      'badgeLabel': badgeLabel,
      'alternateLink': alternateLink,
      'isCompleted': isCompleted,
      'hasReminder': hasReminder,
    };
  }

  factory CalendarEntry.fromJson(Map<String, Object?> json) {
    return CalendarEntry(
      id: json['id']?.toString() ?? '',
      subject: json['subject']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      type: _parseType(json['type']?.toString()),
      tone: _parseTone(json['tone']?.toString()),
      subjectKey: _nullableText(json['subjectKey']),
      subjectSource: _parseSubjectSource(json['subjectSource']?.toString()),
      scheduledDate: _parseDateTime(json['scheduledDate']),
      endDate: _parseDateTime(json['endDate']),
      plannerType: _parsePlannerType(json['plannerType']?.toString()),
      badgeLabel: _nullableText(json['badgeLabel']),
      alternateLink: _nullableText(json['alternateLink']),
      isCompleted: json['isCompleted'] == true,
      hasReminder: json['hasReminder'] == true,
    );
  }

  String get typeLabel {
    switch (type) {
      case CalendarEntryType.exam:
        return 'Exam';
      case CalendarEntryType.task:
        return 'Task';
      case CalendarEntryType.project:
        return 'Project';
      case CalendarEntryType.lab:
        return 'Schedule';
    }
  }

  bool get isScheduleEntry =>
      plannerType == PlannerItemType.schedule || type == CalendarEntryType.lab;

  static CalendarEntryType _parseType(String? value) {
    for (final type in CalendarEntryType.values) {
      if (type.name == value) {
        return type;
      }
    }

    return CalendarEntryType.task;
  }

  static CalendarEntryTone _parseTone(String? value) {
    for (final tone in CalendarEntryTone.values) {
      if (tone.name == value) {
        return tone;
      }
    }

    return CalendarEntryTone.openEnded;
  }

  static CalendarSubjectSource _parseSubjectSource(String? value) {
    for (final source in CalendarSubjectSource.values) {
      if (source.name == value) {
        return source;
      }
    }

    return CalendarSubjectSource.unknown;
  }

  static PlannerItemType? _parsePlannerType(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    for (final type in PlannerItemType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return null;
  }

  static DateTime? _parseDateTime(Object? value) {
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

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }
}
