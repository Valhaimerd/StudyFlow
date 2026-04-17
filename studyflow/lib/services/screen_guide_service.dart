import 'package:shared_preferences/shared_preferences.dart';

class ScreenGuideService {
  ScreenGuideService._();

  static final ScreenGuideService instance = ScreenGuideService._();

  static const _keyPrefix = 'screen_guide_seen_v2';

  Future<bool> shouldShowGuide({
    required String uid,
    required String screenId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_storageKey(uid, screenId)) ?? false);
  }

  Future<void> markGuideSeen({
    required String uid,
    required String screenId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey(uid, screenId), true);
  }

  Future<void> resetGuides(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith('screen_guide_seen_') && key.contains('::$uid::'),
        )
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  String _storageKey(String uid, String screenId) {
    return '$_keyPrefix::$uid::$screenId';
  }
}
