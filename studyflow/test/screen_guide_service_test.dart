import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyflow/services/screen_guide_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('guides are shown once per user and screen', () async {
    const uid = 'student-1';
    const screenId = 'home';
    final service = ScreenGuideService.instance;

    expect(await service.shouldShowGuide(uid: uid, screenId: screenId), isTrue);

    await service.markGuideSeen(uid: uid, screenId: screenId);

    expect(
      await service.shouldShowGuide(uid: uid, screenId: screenId),
      isFalse,
    );
  });
}
