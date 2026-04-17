class ClassroomDateTimeParser {
  const ClassroomDateTimeParser();

  DateTime? parseDueAt({Object? dueDate, Object? dueTime}) {
    if (dueDate is! Map) {
      return null;
    }

    final year = _asInt(dueDate['year']);
    final month = _asInt(dueDate['month']);
    final day = _asInt(dueDate['day']);
    if (year == null || month == null || day == null) {
      return null;
    }

    if (dueTime is Map) {
      final hours = _asInt(dueTime['hours']) ?? 23;
      final minutes = _asInt(dueTime['minutes']) ?? 59;

      // Classroom returns dueTime components in UTC. Convert to device-local
      // time so comparisons and display match the student's timezone.
      return DateTime.utc(year, month, day, hours, minutes).toLocal();
    }

    return DateTime(year, month, day, 23, 59);
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }
}
