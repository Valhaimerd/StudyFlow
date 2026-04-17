import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/app_settings_service.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'theme/study_flow_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudyFlowApp());
}

class StudyFlowApp extends StatefulWidget {
  const StudyFlowApp({super.key});

  @override
  State<StudyFlowApp> createState() => _StudyFlowAppState();
}

class _StudyFlowAppState extends State<StudyFlowApp> {
  static const _minimumSplashDuration = Duration(milliseconds: 2300);

  AppController? _controller;
  String _startupLabel = 'STARTING STUDYFLOW';
  double _startupProgress = 0.08;

  @override
  void initState() {
    super.initState();
    _bootstrapApplication();
  }

  Future<void> _bootstrapApplication() async {
    final minimumSplash = Future<void>.delayed(_minimumSplashDuration);

    try {
      _updateStartupState('CONNECTING SERVICES', 0.22);
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      _updateStartupState('PREPARING LOCAL DATA', 0.42);
      await DatabaseService.instance.initialize();

      _updateStartupState('READYING SIGN-IN', 0.62);
      await AuthService.instance.initialize();

      _updateStartupState('SETTING REMINDERS', 0.78);
      await NotificationService.instance.initialize();

      _updateStartupState('LOADING PREFERENCES', 0.9);
      final controller = await AppController.bootstrap();

      await minimumSplash;

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _startupLabel = 'WORKSPACE READY';
        _startupProgress = 1;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startupLabel = 'STARTUP NEEDS ATTENTION';
        _startupProgress = 1;
      });
    }
  }

  void _updateStartupState(String label, double progress) {
    if (!mounted) return;
    setState(() {
      _startupLabel = label;
      _startupProgress = progress;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      return MaterialApp(
        title: 'StudyFlow',
        debugShowCheckedModeBanner: false,
        theme: StudyFlowTheme.lightTheme(),
        darkTheme: StudyFlowTheme.darkTheme(),
        themeMode: ThemeMode.light,
        home: SplashScreen(
          progressLabel: _startupLabel,
          progressValue: _startupProgress,
        ),
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controller.themeModeListenable,
      builder: (context, themeMode, child) {
        return ValueListenableBuilder<AppThemeAccent>(
          valueListenable: controller.themeAccentListenable,
          builder: (context, themeAccent, child) {
            return ValueListenableBuilder<AppFontSize>(
              valueListenable: controller.fontSizeListenable,
              builder: (context, appFontSize, child) {
                return MaterialApp(
                  title: 'StudyFlow',
                  debugShowCheckedModeBanner: false,
                  theme: StudyFlowTheme.lightTheme(themeAccent),
                  darkTheme: StudyFlowTheme.darkTheme(themeAccent),
                  themeMode: themeMode,
                  builder: (context, child) {
                    final mediaQuery = MediaQuery.of(context);
                    return MediaQuery(
                      data: mediaQuery.copyWith(
                        textScaler: TextScaler.linear(appFontSize.textScale),
                      ),
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                  home: AppBootstrapper(controller: controller),
                );
              },
            );
          },
        );
      },
    );
  }
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  bool _allowAuthenticatedRoute = false;
  bool _isResumingSession = AuthService.instance.currentUser != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeExistingSession();
    });
  }

  Future<void> _resumeExistingSession() async {
    if (!_isResumingSession) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 450));

    if (!mounted) return;
    setState(() {
      _allowAuthenticatedRoute = AuthService.instance.currentUser != null;
      _isResumingSession = false;
    });
  }

  void _handleSignInSucceeded() {
    if (!mounted) return;
    setState(() {
      _allowAuthenticatedRoute = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      initialData: AuthService.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data ?? AuthService.instance.currentUser;

        if (!_allowAuthenticatedRoute) {
          return LoginScreen(
            initialMessage: _isResumingSession
                ? 'Signing you back in...'
                : null,
            onSignInSucceeded: _handleSignInSucceeded,
          );
        }

        if (user == null) {
          return LoginScreen(onSignInSucceeded: _handleSignInSucceeded);
        }

        DatabaseService.instance.keepUserWorkspaceSynced(user.uid);
        return HomeScreen(controller: widget.controller);
      },
    );
  }
}
