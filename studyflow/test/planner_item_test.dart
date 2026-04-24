import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/models/planner_item.dart';
import 'package:studyflow/services/notification_service.dart';

void main() {
  test('items due within one day are treated as high priority', () {
    final item = PlannerItem(
      id: 'task-1',
      title: 'Reading',
      subjectId: 'subject-1',
      type: PlannerItemType.task,
      priority: PlannerItemPriority.low,
      scheduledAt: DateTime.now().add(const Duration(hours: 6)),
    );

    expect(item.effectivePriority, PlannerItemPriority.high);
    expect(item.priorityLabel, 'High Priority');
  });

  test('completed manual item marks unfinished subtasks complete', () {
    final item = PlannerItem(
      id: 'task-2',
      title: 'Lab report',
      subjectId: 'subject-1',
      type: PlannerItemType.task,
      priority: PlannerItemPriority.medium,
      status: PlannerItemStatus.completed,
      subtasks: const [PlannerSubtask(id: 'subtask-1', title: 'Draft')],
    );

    final normalized = item.normalizedForSave();

    expect(normalized.isCompleted, isTrue);
    expect(normalized.subtasks.single.isCompleted, isTrue);
    expect(normalized.subtasks.single.completedAt, isNotNull);
  });

  test('classroom-backed item does not auto-complete from subtasks', () {
    final item = PlannerItem(
      id: 'task-3',
      title: 'Classroom assignment',
      subjectId: 'classroom::course',
      sourceItemId: 'coursework-1',
      type: PlannerItemType.task,
      priority: PlannerItemPriority.medium,
      autoCompleteFromSubtasks: true,
      subtasks: const [
        PlannerSubtask(id: 'subtask-1', title: 'Prepare', isCompleted: true),
      ],
    );

    final normalized = item.normalizedForSave();

    expect(normalized.isClassroomBacked, isTrue);
    expect(normalized.isCompleted, isFalse);
    expect(normalized.completedAt, isNull);
  });

  test('notification reminder labels convert to schedule offsets', () {
    expect(
      NotificationService.parseReminderOffset('10m before'),
      const Duration(minutes: 10),
    );
    expect(
      NotificationService.parseReminderOffset('1hr before'),
      const Duration(hours: 1),
    );
    expect(
      NotificationService.parseReminderOffset('12hr before'),
      const Duration(hours: 12),
    );
    expect(
      NotificationService.parseReminderOffset('3 day before'),
      const Duration(days: 3),
    );
  });

  test('planner items parse epoch-millis timestamps from storage', () {
    final scheduledAt = DateTime(2026, 4, 11, 14, 30);
    final createdAt = DateTime(2026, 4, 10, 8, 15);

    final item = PlannerItem.fromJson('task-4', {
      'title': 'Stored item',
      'subjectId': 'subject-1',
      'type': 'task',
      'priority': 'medium',
      'scheduledAt': scheduledAt.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch.toString(),
    });

    expect(item.scheduledAt, scheduledAt);
    expect(item.createdAt, createdAt);
  });

  test('planner items persist linked classroom content refs', () {
    final item = PlannerItem(
      id: 'task-5',
      title: 'Review notes',
      subjectId: 'subject-1',
      type: PlannerItemType.task,
      priority: PlannerItemPriority.medium,
      linkedClassroomContent: const [
        PlannerLinkedClassroomContentRef(
          id: 'announcement:course-1-post-1',
          subjectKey: 'course-1',
          typeLabel: 'Announcement',
          title: 'Lecture moved online',
          alternateLink: 'https://classroom.google.com/example',
        ),
      ],
    );

    final restored = PlannerItem.fromJson('task-5', item.toJson());

    expect(restored.linkedClassroomContent, hasLength(1));
    expect(restored.linkedClassroomContent.single.typeLabel, 'Announcement');
    expect(
      restored.linkedClassroomContent.single.alternateLink,
      'https://classroom.google.com/example',
    );
  });
}
