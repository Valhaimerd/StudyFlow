import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_cache_snapshot.dart';

class CalendarCacheService {
  CalendarCacheService._();

  static final CalendarCacheService instance = CalendarCacheService._();

  static const _snapshotKeyPrefix = 'calendar_cache_snapshot_v1_';

  Future<CalendarCacheSnapshot?> loadSnapshot(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = '$_snapshotKeyPrefix$uid';
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await prefs.remove(storageKey);
        return null;
      }

      return CalendarCacheSnapshot.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
        source: CalendarSnapshotSource.local,
      );
    } catch (_) {
      await prefs.remove(storageKey);
      return null;
    }
  }

  Future<void> saveSnapshot(String uid, CalendarCacheSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_snapshotKeyPrefix$uid',
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<void> clearSnapshot(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_snapshotKeyPrefix$uid');
  }
}
