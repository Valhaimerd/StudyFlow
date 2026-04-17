import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/services/classroom_date_time_parser.dart';

void main() {
  const parser = ClassroomDateTimeParser();

  test('converts Classroom UTC due time to local time', () {
    final dueAt = parser.parseDueAt(
      dueDate: {'year': 2026, 'month': 4, 'day': 10},
      dueTime: {'hours': 15, 'minutes': 59},
    );

    expect(dueAt, isNotNull);
    expect(dueAt!.year, 2026);
    expect(dueAt.month, 4);
    expect(dueAt.day, 10);
    expect(dueAt.hour, 23);
    expect(dueAt.minute, 59);
  });

  test('defaults date-only due items to end of day', () {
    final dueAt = parser.parseDueAt(
      dueDate: {'year': 2026, 'month': 4, 'day': 10},
    );

    expect(dueAt, DateTime(2026, 4, 10, 23, 59));
  });

  test('returns null when due date is missing', () {
    final dueAt = parser.parseDueAt(dueDate: null, dueTime: null);

    expect(dueAt, isNull);
  });
}
