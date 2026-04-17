import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyflow/models/calendar_cache_snapshot.dart';
import 'package:studyflow/models/calendar_entry.dart';
import 'package:studyflow/services/calendar_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and restores calendar snapshots locally', () async {
    final service = CalendarCacheService.instance;
    const uid = 'student-1';
    final snapshot = CalendarCacheSnapshot(
      entries: [
        CalendarEntry(
          id: 'task-1',
          subject: 'Mobile Development',
          title: 'Project Checkpoint',
          description: 'Upload the progress report.',
          type: CalendarEntryType.project,
          tone: CalendarEntryTone.project,
          scheduledDate: DateTime(2026, 4, 10, 23, 59),
          badgeLabel: 'DUE SOON',
          alternateLink: 'https://classroom.google.com/c/example/a/task',
          hasReminder: true,
        ),
      ],
      courseCount: 3,
      lastSyncedAt: DateTime(2026, 4, 10, 15, 59),
      source: CalendarSnapshotSource.live,
    );

    await service.saveSnapshot(uid, snapshot);
    final restored = await service.loadSnapshot(uid);

    expect(restored, isNotNull);
    expect(restored!.courseCount, 3);
    expect(restored.lastSyncedAt, DateTime(2026, 4, 10, 15, 59));
    expect(restored.entries, hasLength(1));
    expect(restored.entries.first.title, 'Project Checkpoint');
    expect(restored.entries.first.alternateLink, isNotNull);
    expect(restored.source, CalendarSnapshotSource.local);
  });

  test('returns null when no local snapshot exists', () async {
    final restored = await CalendarCacheService.instance.loadSnapshot(
      'missing-student',
    );

    expect(restored, isNull);
  });

  test('drops corrupted local snapshot payloads', () async {
    const uid = 'broken-student';
    SharedPreferences.setMockInitialValues({
      'calendar_cache_snapshot_v1_$uid': '{not-valid-json',
    });

    final restored = await CalendarCacheService.instance.loadSnapshot(uid);
    final prefs = await SharedPreferences.getInstance();

    expect(restored, isNull);
    expect(prefs.getString('calendar_cache_snapshot_v1_$uid'), isNull);
  });
}
