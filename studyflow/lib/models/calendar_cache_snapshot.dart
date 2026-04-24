import 'calendar_entry.dart';
import 'classroom_stream_item.dart';

enum CalendarSnapshotSource { local, firebase, live }

class CalendarCacheSnapshot {
  const CalendarCacheSnapshot({
    required this.entries,
    this.streamItems = const <ClassroomStreamItem>[],
    required this.courseCount,
    required this.lastSyncedAt,
    required this.source,
  });

  final List<CalendarEntry> entries;
  final List<ClassroomStreamItem> streamItems;
  final int courseCount;
  final DateTime? lastSyncedAt;
  final CalendarSnapshotSource source;

  Map<String, Object?> toJson() {
    return {
      'courseCount': courseCount,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
      'streamItems': streamItems.map((item) => item.toJson()).toList(),
    };
  }

  factory CalendarCacheSnapshot.fromJson(
    Map<String, Object?> json, {
    required CalendarSnapshotSource source,
  }) {
    final rawEntries = json['entries'];
    final rawStreamItems = json['streamItems'];
    final entries = rawEntries is List
        ? rawEntries
              .whereType<Map>()
              .map(
                (entry) => CalendarEntry.fromJson(
                  entry.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList()
        : const <CalendarEntry>[];
    final streamItems = rawStreamItems is List
        ? rawStreamItems
              .whereType<Map>()
              .map(
                (item) => ClassroomStreamItem.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList()
        : const <ClassroomStreamItem>[];

    return CalendarCacheSnapshot(
      entries: entries,
      streamItems: streamItems,
      courseCount: _parseInt(json['courseCount']) ?? 0,
      lastSyncedAt: _parseDateTime(json['lastSyncedAt']),
      source: source,
    );
  }

  static int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is double) {
      return DateTime.fromMillisecondsSinceEpoch(value.round());
    }

    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }

    final epochMillis = int.tryParse(raw);
    if (epochMillis != null) {
      return DateTime.fromMillisecondsSinceEpoch(epochMillis);
    }

    return null;
  }
}
