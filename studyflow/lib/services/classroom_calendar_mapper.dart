import '../models/calendar_entry.dart';
import '../models/classroom_activity.dart';

class ClassroomCalendarMapper {
  const ClassroomCalendarMapper();

  CalendarEntry mapActivity(ClassroomActivity activity, {DateTime? now}) {
    final referenceNow = now ?? DateTime.now();
    final normalizedTitle = activity.title.toLowerCase();
    final normalizedDescription = activity.description.toLowerCase();
    final dueAt = activity.dueAt;

    final isExamLike =
        normalizedTitle.contains('exam') ||
        normalizedTitle.contains('quiz') ||
        normalizedTitle.contains('final') ||
        normalizedTitle.contains('test');
    final isProjectLike =
        normalizedTitle.contains('project') ||
        normalizedTitle.contains('paper') ||
        normalizedTitle.contains('portfolio') ||
        normalizedTitle.contains('presentation') ||
        normalizedDescription.contains('project');
    final isLabLike =
        normalizedTitle.contains('lab') ||
        normalizedDescription.contains('lab');

    final type = isExamLike
        ? CalendarEntryType.exam
        : isProjectLike
        ? CalendarEntryType.project
        : CalendarEntryType.task;

    final tone = activity.isCompleted
        ? CalendarEntryTone.completed
        : isExamLike || isDueSoon(dueAt, now: referenceNow)
        ? CalendarEntryTone.critical
        : isProjectLike
        ? CalendarEntryTone.project
        : isLabLike
        ? CalendarEntryTone.laboratory
        : CalendarEntryTone.openEnded;

    return CalendarEntry(
      id: activity.id,
      subject: activity.courseName,
      subjectKey: activity.courseId,
      subjectSource: CalendarSubjectSource.classroom,
      title: activity.title,
      description: activity.description,
      type: type,
      tone: tone,
      scheduledDate: dueAt,
      badgeLabel: activity.isCompleted
          ? null
          : isExamLike
          ? 'EXAM'
          : isDueSoon(dueAt, now: referenceNow)
          ? 'DUE SOON'
          : null,
      alternateLink: activity.alternateLink,
      isCompleted: activity.isCompleted,
      hasReminder: dueAt != null,
    );
  }

  DateTime chooseSelectedDate(
    List<CalendarEntry> entries, {
    DateTime? fallbackNow,
  }) {
    for (final entry in entries) {
      if (entry.scheduledDate != null && !entry.isCompleted) {
        return DateTime(
          entry.scheduledDate!.year,
          entry.scheduledDate!.month,
          entry.scheduledDate!.day,
        );
      }
    }

    final now = fallbackNow ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool isDueSoon(DateTime? value, {DateTime? now}) {
    if (value == null) {
      return false;
    }

    final difference = value.difference(now ?? DateTime.now());
    return !difference.isNegative && difference <= const Duration(days: 2);
  }
}
