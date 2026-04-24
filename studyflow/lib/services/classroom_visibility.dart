import '../models/calendar_entry.dart';
import '../models/planner_item.dart';
import 'classroom_subject_identity.dart';

String classroomSubjectStorageKey(CalendarEntry entry) {
  return classroomSubjectStorageKeyForEntry(entry);
}

bool isHiddenClassroomEntry(
  CalendarEntry entry, {
  required Set<String> hiddenSubjectKeys,
  required Set<String> hiddenEntryIds,
}) {
  return hiddenEntryIds.contains(entry.id) ||
      hiddenSubjectKeys.contains(classroomSubjectStorageKey(entry));
}

Set<String> hiddenClassroomPlannerSubjectIds(
  Iterable<CalendarEntry> entries,
  Set<String> hiddenSubjectKeys,
) {
  final ids = <String>{};

  for (final entry in entries) {
    final storageKey = classroomSubjectStorageKey(entry);
    if (!hiddenSubjectKeys.contains(storageKey)) {
      continue;
    }

    final subjectName = entry.subject.trim();
    ids.add(classroomPlannerSubjectId(storageKey));
    if (subjectName.isEmpty) {
      ids.add(classroomPlannerSubjectId('classroom'));
      continue;
    }

    ids.add(classroomPlannerSubjectId(subjectName));
    ids.add(
      classroomPlannerSubjectId(normalizedClassroomSubjectNameKey(subjectName)),
    );
  }

  return ids;
}

bool isPlannerItemHiddenByClassroom(
  PlannerItem item, {
  required Set<String> hiddenEntryIds,
  required Set<String> hiddenPlannerSubjectIds,
}) {
  final sourceItemId = item.sourceItemId?.trim();
  if (sourceItemId != null &&
      sourceItemId.isNotEmpty &&
      hiddenEntryIds.contains(sourceItemId)) {
    return true;
  }

  final subjectId = item.subjectId.trim();
  if (subjectId.startsWith('classroom::') &&
      hiddenPlannerSubjectIds.contains(subjectId)) {
    return true;
  }

  return false;
}
