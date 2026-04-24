import 'package:flutter/foundation.dart';

import '../app_controller.dart';
import '../models/planner_item.dart';
import 'database_service.dart';
import 'notification_service.dart';

class PlannerItemMutationResult {
  const PlannerItemMutationResult({required this.item, required this.message});

  final PlannerItem item;
  final String message;
}

class PlannerItemMutationService {
  const PlannerItemMutationService._();

  static Future<PlannerItemMutationResult> saveRecord({
    required String uid,
    required PlannerItem record,
    required AppController controller,
    required Iterable<PlannerItem> currentItems,
    PlannerItem? previousItem,
    bool isClassroomDraft = false,
  }) async {
    final isOffline = !await DatabaseService.instance.isConnected();

    if (previousItem == null || isClassroomDraft) {
      final saved = await DatabaseService.instance.createPlannerItem(
        uid: uid,
        item: record,
      );
      await _schedulePlannerNotifications(
        items: mergePlannerItems(currentItems, saved),
        controller: controller,
      );
      return PlannerItemMutationResult(
        item: saved,
        message: isOffline
            ? '${_typeLabel(record.type)} saved locally. It will sync when you are online.'
            : isClassroomDraft
            ? 'Classroom task copied into StudyFlow.'
            : '${_typeLabel(record.type)} created.',
      );
    }

    final saved = await DatabaseService.instance.updatePlannerItem(
      uid: uid,
      item: record,
    );
    await _schedulePlannerNotifications(
      items: mergePlannerItems(currentItems, saved),
      controller: controller,
    );
    return PlannerItemMutationResult(
      item: saved,
      message: isOffline
          ? '${_typeLabel(record.type)} saved locally. It will sync when you are online.'
          : '${_typeLabel(record.type)} updated.',
    );
  }

  static Future<PlannerItem> persistItem({
    required String uid,
    required PlannerItem item,
    required AppController controller,
    required Iterable<PlannerItem> currentItems,
  }) async {
    final saved = await DatabaseService.instance.updatePlannerItem(
      uid: uid,
      item: item,
    );
    await _schedulePlannerNotifications(
      items: mergePlannerItems(currentItems, saved),
      controller: controller,
    );
    return saved;
  }

  static Future<void> deleteItem({
    required String uid,
    required PlannerItem item,
    required AppController controller,
    required Iterable<PlannerItem> currentItems,
  }) async {
    await DatabaseService.instance.deletePlannerItem(uid: uid, itemId: item.id);
    await _schedulePlannerNotifications(
      items: currentItems.where((current) => current.id != item.id),
      controller: controller,
    );
  }

  static List<PlannerItem> mergePlannerItems(
    Iterable<PlannerItem> currentItems,
    PlannerItem saved,
  ) {
    final merged = <PlannerItem>[];
    var replaced = false;

    for (final item in currentItems) {
      final isSameRecord = item.id == saved.id;
      final isCopiedClassroomRecord =
          saved.sourceItemId != null &&
          saved.sourceItemId == item.sourceItemId &&
          item.id.startsWith('classroom::');

      if (isSameRecord || isCopiedClassroomRecord) {
        if (!replaced) {
          merged.add(saved);
          replaced = true;
        }
        continue;
      }
      merged.add(item);
    }

    if (!replaced) {
      merged.add(saved);
    }

    return merged;
  }

  static String _typeLabel(PlannerItemType type) {
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

  static Future<void> _schedulePlannerNotifications({
    required Iterable<PlannerItem> items,
    required AppController controller,
  }) async {
    try {
      await NotificationService.instance.schedulePlannerItems(
        items: items,
        controller: controller,
      );
    } catch (error) {
      debugPrint('StudyFlow could not refresh planner notifications: $error');
    }
  }
}
