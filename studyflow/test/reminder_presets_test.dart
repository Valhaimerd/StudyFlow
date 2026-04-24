import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/models/reminder_presets.dart';

void main() {
  test('task reminder options expose the approved range', () {
    expect(taskReminderOptions, const [
      '10m before',
      '30m before',
      '1hr before',
      '3hr before',
      '6hr before',
      '12hr before',
      '1 day before',
      '2 day before',
      '3 day before',
    ]);
  });
}
