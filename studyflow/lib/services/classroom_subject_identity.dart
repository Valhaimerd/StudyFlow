import '../models/calendar_entry.dart';
import '../models/classroom_stream_item.dart';

String classroomSubjectStorageKey({
  String? subjectKey,
  String? courseId,
  String? subjectName,
}) {
  final normalizedSubjectKey = subjectKey?.trim();
  if (normalizedSubjectKey != null && normalizedSubjectKey.isNotEmpty) {
    return normalizedSubjectKey;
  }

  final normalizedCourseId = courseId?.trim();
  if (normalizedCourseId != null && normalizedCourseId.isNotEmpty) {
    return normalizedCourseId;
  }

  final normalizedSubjectName = subjectName?.trim();
  if (normalizedSubjectName != null && normalizedSubjectName.isNotEmpty) {
    return normalizedSubjectName;
  }

  return 'classroom';
}

String classroomSubjectStorageKeyForEntry(CalendarEntry entry) {
  return classroomSubjectStorageKey(
    subjectKey: entry.subjectKey,
    subjectName: entry.subject,
  );
}

String classroomSubjectStorageKeyForStreamItem(ClassroomStreamItem item) {
  return classroomSubjectStorageKey(
    courseId: item.courseId,
    subjectName: item.courseName,
  );
}

String classroomPlannerSubjectId(String storageKey) {
  return 'classroom::$storageKey';
}

String normalizedClassroomSubjectNameKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
}
