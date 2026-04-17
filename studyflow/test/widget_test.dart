import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/screens/login_screen.dart';
import 'package:studyflow/screens/splash_screen.dart';
import 'package:studyflow/theme/study_flow_theme.dart';

void main() {
  testWidgets('splash screen shows brand and loading copy', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrapForTest(const SplashScreen()));

    expect(find.text('StudyFlow'), findsOneWidget);
    expect(find.text('INITIALIZING WORKSPACE'), findsOneWidget);
  });

  testWidgets('login screen renders access messaging', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrapForTest(
        const LoginScreen(initialMessage: 'Sign in with Google to continue.'),
      ),
    );

    expect(find.text('Access your\nworkspace'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Google account access'), findsOneWidget);
  });
}

Widget _wrapForTest(Widget child) {
  return MaterialApp(theme: StudyFlowTheme.lightTheme(), home: child);
}
