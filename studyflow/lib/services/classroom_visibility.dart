import '../models/calendar_entry.dart';
import '../models/planner_item.dart';

String classroomSubjectStorageKey(CalendarEntry entry) {
  final subjectKey = entry.subjectKey?.trim();
  if (subjectKey != null && subjectKey.isNotEmpty) {
    return subjectKey;
  }

  final subjectName = entry.subject.trim();
  return subjectName.isEmpty ? 'classroom' : subjectName;
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
    ids.add('classroom::$storageKey');
    if (subjectName.isEmpty) {
      ids.add('classroom::classroom');
      continue;
    }

    ids.add('classroom::$subjectName');
    ids.add('classroom::${_normalizedClassroomSubjectKey(subjectName)}');
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

String _normalizedClassroomSubjectKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
}
