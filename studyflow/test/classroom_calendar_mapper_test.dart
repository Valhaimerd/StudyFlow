import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/models/classroom_activity.dart';
import 'package:studyflow/models/calendar_entry.dart';
import 'package:studyflow/services/classroom_calendar_mapper.dart';

void main() {
  const mapper = ClassroomCalendarMapper();

  test('maps exam-like coursework to exam entries', () {
    final entry = mapper.mapActivity(
      ClassroomActivity(
        id: 'course-1-work-1',
        courseId: 'course-1',
        courseName: 'Advanced Calculus',
        title: 'Final Exam Coverage',
        description: 'Comprehensive final exam reviewer.',
        workType: 'ASSIGNMENT',
        state: 'PUBLISHED',
        isCompleted: false,
        dueAt: DateTime(2026, 4, 12, 9),
      ),
      now: DateTime(2026, 4, 10, 8),
    );

    expect(entry.type, CalendarEntryType.exam);
    expect(entry.tone, CalendarEntryTone.critical);
    expect(entry.badgeLabel, 'EXAM');
    expect(entry.hasReminder, isTrue);
    expect(entry.subjectKey, 'course-1');
    expect(entry.subjectSource, CalendarSubjectSource.classroom);
  });

  test('maps near-term non-exam coursework to due-soon critical entries', () {
    final entry = mapper.mapActivity(
      ClassroomActivity(
        id: 'course-2-work-1',
        courseId: 'course-2',
        courseName: 'Research Methods',
        title: 'Literature Review Draft',
        description: 'Submit the first full draft.',
        workType: 'ASSIGNMENT',
        state: 'PUBLISHED',
        isCompleted: false,
        dueAt: DateTime(2026, 4, 11, 23, 59),
      ),
      now: DateTime(2026, 4, 10, 12),
    );

    expect(entry.type, CalendarEntryType.task);
    expect(entry.tone, CalendarEntryTone.critical);
    expect(entry.badgeLabel, 'DUE SOON');
  });

  test('maps undated coursework to open-ended entries', () {
    final entry = mapper.mapActivity(
      const ClassroomActivity(
        id: 'course-3-work-1',
        courseId: 'course-3',
        courseName: 'Philosophy',
        title: 'Reading Reflection',
        description: 'Capture your strongest reaction to the reading.',
        workType: 'ASSIGNMENT',
        state: 'PUBLISHED',
        isCompleted: false,
      ),
      now: DateTime(2026, 4, 10),
    );

    expect(entry.type, CalendarEntryType.task);
    expect(entry.tone, CalendarEntryTone.openEnded);
    expect(entry.scheduledDate, isNull);
    expect(entry.badgeLabel, isNull);
  });

  test('keeps classroom lab coursework in tasks instead of schedules', () {
    final entry = mapper.mapActivity(
      ClassroomActivity(
        id: 'course-4-work-1',
        courseId: 'course-4',
        courseName: 'Chemistry',
        title: 'Lab report 2',
        description: 'Submit the completed lab worksheet.',
        workType: 'ASSIGNMENT',
        state: 'PUBLISHED',
        isCompleted: false,
        dueAt: DateTime(2026, 4, 13, 17),
      ),
      now: DateTime(2026, 4, 10, 12),
    );

    expect(entry.type, CalendarEntryType.task);
    expect(entry.isScheduleEntry, isFalse);
    expect(entry.tone, CalendarEntryTone.laboratory);
  });

  test('prefers first active dated entry for selected date', () {
    final selectedDate = mapper.chooseSelectedDate([
      CalendarEntry(
        id: 'completed',
        subject: 'Course',
        title: 'Done',
        description: 'Done',
        type: CalendarEntryType.task,
        tone: CalendarEntryTone.completed,
        scheduledDate: DateTime(2026, 4, 9, 9),
        isCompleted: true,
      ),
      CalendarEntry(
        id: 'active',
        subject: 'Course',
        title: 'Upcoming',
        description: 'Upcoming',
        type: CalendarEntryType.task,
        tone: CalendarEntryTone.critical,
        scheduledDate: DateTime(2026, 4, 12, 13),
      ),
    ], fallbackNow: DateTime(2026, 4, 10));

    expect(selectedDate, DateTime(2026, 4, 12));
  });

  test('falls back to today when no active dated entries exist', () {
    final selectedDate = mapper.chooseSelectedDate(
      const [],
      fallbackNow: DateTime(2026, 4, 10, 16, 30),
    );

    expect(selectedDate, DateTime(2026, 4, 10));
  });
}
