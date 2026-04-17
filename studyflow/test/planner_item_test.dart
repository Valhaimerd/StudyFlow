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
      NotificationService.parseReminderOffset('15m before'),
      const Duration(minutes: 15),
    );
    expect(
      NotificationService.parseReminderOffset('1 hour before'),
      const Duration(hours: 1),
    );
    expect(
      NotificationService.parseReminderOffset('1 week before'),
      const Duration(days: 7),
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
}
