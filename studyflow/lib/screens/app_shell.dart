import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models/calendar_entry.dart';
import '../models/planner_item.dart';
import '../models/subject_record.dart';
import '../services/app_settings_service.dart';
import '../services/calendar_repository.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/screen_guide_service.dart';
import '../widgets/modal_sheet_header.dart';
import '../widgets/study_flow_background.dart';
import '../widgets/user_avatar.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'subjects_screen.dart';
import 'tasks_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, this.initialIndex = 0});

  final AppController controller;
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int _currentIndex = widget.initialIndex;
  final GlobalKey<CalendarScreenState> _calendarKey =
      GlobalKey<CalendarScreenState>();
  final GlobalKey<TasksScreenState> _tasksKey = GlobalKey<TasksScreenState>();
  final GlobalKey<SubjectsScreenState> _subjectsKey =
      GlobalKey<SubjectsScreenState>();
  final ScreenGuideService _screenGuideService = ScreenGuideService.instance;
  final CalendarRepository _calendarRepository = CalendarRepository.instance;
  DateTime? _lastExitAttemptAt;
  bool _isShowingGuide = false;
  String? _notificationPrimedUid;
  Timer? _autoSyncTimer;
  bool _autoSyncInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAutoSyncLoop();
    unawaited(_maybeRunAutoSync(force: false));
    _scheduleGuideCheck();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _startAutoSyncLoop();
      unawaited(_maybeRunAutoSync(force: false));
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_maybeRunAutoSync(force: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final textTheme = Theme.of(context).textTheme;

    final pages = <Widget>[
      DashboardScreen(
        controller: widget.controller,
        onOpenCalendar: () => _setCurrentIndex(1),
        onOpenTasks: () => _setCurrentIndex(2),
        onOpenSubjects: () => _setCurrentIndex(3),
        onOpenManualSubject: _openManualSubject,
        onOpenClassroomSubject: _openClassroomSubject,
        onSearch: _handleSearch,
        onCreateTask: () => _openTaskCreator(PlannerItemType.task, null),
        onCreateExam: () => _openTaskCreator(PlannerItemType.exam, null),
        onCreateSchedule: () => _openScheduleCreator(null),
        onCreateSubject: _openSubjectCreator,
        onSyncData: _runManualSyncAndShowMessage,
      ),
      CalendarScreen(
        key: _calendarKey,
        controller: widget.controller,
        onCreateTask: (date) => _openTaskCreator(PlannerItemType.task, date),
        onCreateExam: (date) => _openTaskCreator(PlannerItemType.exam, date),
        onCreateSubject: _openSubjectCreator,
      ),
      TasksScreen(key: _tasksKey, controller: widget.controller),
      SubjectsScreen(key: _subjectsKey, controller: widget.controller),
      ProfileScreen(controller: widget.controller),
    ];

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }

        final now = DateTime.now();
        final canExit =
            _lastExitAttemptAt != null &&
            now.difference(_lastExitAttemptAt!) <= const Duration(seconds: 2);

        if (canExit) {
          await SystemNavigator.pop();
          return;
        }

        _lastExitAttemptAt = now;
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit StudyFlow.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        extendBody: true,
        body: StudyFlowBackground(
          child: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(index: _currentIndex, children: pages),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: RepaintBoundary(
                  child: _TopNavigationBar(
                    user: user,
                    textTheme: textTheme,
                    onShowGuide: () => _scheduleGuideCheck(force: true),
                    onSearch: _handleSearch,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: RepaintBoundary(
                  child: _BottomNavigationBar(
                    currentIndex: _currentIndex,
                    onTap: _setCurrentIndex,
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _buildFloatingActionButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  void _setCurrentIndex(int index, {bool showGuide = true}) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }
    if (showGuide) {
      _scheduleGuideCheck();
    }
  }

  void _startAutoSyncLoop() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(AppController.autoSyncInterval, (_) {
      unawaited(_maybeRunAutoSync(force: false));
    });
  }

  Future<void> _maybeRunAutoSync({required bool force}) async {
    if (!mounted || !widget.controller.autoSyncEnabled || _autoSyncInFlight) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final isOffline = !await DatabaseService.instance.isConnected();
    final now = DateTime.now();
    if (isOffline) {
      await widget.controller.updateSyncState(
        status: SyncStatus.offlineLocalOnly,
        lastSyncCheckedAt: now,
        lastSyncedAt: widget.controller.lastSyncedAt,
      );
      return;
    }

    final needsRefresh =
        force ||
        widget.controller.shouldAutoRefresh(isOffline: false, now: now);
    if (!needsRefresh) {
      return;
    }

    _autoSyncInFlight = true;
    try {
      await _runSync(promptIfNecessary: false);
    } finally {
      _autoSyncInFlight = false;
    }
  }

  void _scheduleGuideCheck({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startOnboardingFlow(forceGuide: force);
    });
  }

  Future<void> _startOnboardingFlow({bool forceGuide = false}) async {
    if (!mounted || _isShowingGuide) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    if (!forceGuide) {
      final shouldShowWelcome = await _screenGuideService.shouldShowGuide(
        uid: user.uid,
        screenId: 'welcome',
      );
      if (!mounted) {
        return;
      }
      if (shouldShowWelcome) {
        final shouldContinue = await _showWelcomeSheet(user.uid);
        if (!mounted) {
          return;
        }
        await _screenGuideService.markGuideSeen(
          uid: user.uid,
          screenId: 'welcome',
        );
        if (!shouldContinue) {
          return;
        }
      }
    }

    await _showGuideForCurrentScreen(force: forceGuide);
    await _primeNotificationsAfterOnboarding(user.uid);
  }

  Future<void> _primeNotificationsAfterOnboarding(String uid) async {
    if (!mounted || _notificationPrimedUid == uid) {
      return;
    }

    _notificationPrimedUid = uid;
    try {
      await NotificationService.instance.ensurePermissionsRequested();
      await NotificationService.instance.refreshForUser(
        uid: uid,
        controller: widget.controller,
      );
    } catch (_) {
      // Keep startup navigation stable even if local notification refresh fails.
    }
  }

  Future<bool> _showGuideForCurrentScreen({bool force = false}) async {
    if (!mounted || _isShowingGuide) {
      return false;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }

    final guide = _guideForIndex(_currentIndex);
    if (guide == null) {
      return false;
    }

    if (!force) {
      final shouldShow = await _screenGuideService.shouldShowGuide(
        uid: user.uid,
        screenId: guide.id,
      );
      if (!mounted || !shouldShow) {
        return false;
      }
    }

    _isShowingGuide = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).cardColor,
        showDragHandle: true,
        builder: (context) {
          return _ScreenGuideSheet(guide: guide);
        },
      );

      if (!force) {
        await _screenGuideService.markGuideSeen(
          uid: user.uid,
          screenId: guide.id,
        );
      }
      return true;
    } finally {
      _isShowingGuide = false;
    }
  }

  Future<bool> _showWelcomeSheet(String uid) async {
    if (!mounted) {
      return false;
    }

    _isShowingGuide = true;
    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).cardColor,
        builder: (context) {
          return _WelcomeOnboardingSheet(
            onConnectClassroom: () => _connectClassroomFromWelcome(uid),
          );
        },
      );
      return result ?? false;
    } finally {
      _isShowingGuide = false;
    }
  }

  Future<String> _connectClassroomFromWelcome(String uid) async {
    final isOffline = !await DatabaseService.instance.isConnected();
    final result = await _calendarRepository.refreshFromClassroom(
      uid: uid,
      promptIfNecessary: true,
      isOffline: isOffline,
    );

    await widget.controller.updateSyncState(
      status: result.syncStatus,
      lastSyncCheckedAt: DateTime.now(),
      lastSyncedAt:
          result.snapshot?.lastSyncedAt ?? widget.controller.lastSyncedAt,
    );

    try {
      await NotificationService.instance.refreshForUser(
        uid: uid,
        controller: widget.controller,
      );
    } catch (_) {
      // Keep onboarding stable even if reminder refresh fails.
    }

    if (result.needsAuthorization) {
      return 'Classroom still needs your permission before it can sync.';
    }
    await _refreshCachedClassroomConsumers();
    if (result.errorMessage != null && result.errorMessage!.trim().isNotEmpty) {
      return result.errorMessage!;
    }
    if (result.snapshot != null) {
      return 'Google Classroom connected. Your schedule and activities are ready to sync.';
    }
    return 'Classroom connection could not be completed right now.';
  }

  _ScreenGuideContent? _guideForIndex(int index) {
    switch (index) {
      case 0:
        return const _ScreenGuideContent(
          id: 'home',
          title: 'Home Dashboard',
          summary:
              'This is your command center. It surfaces today\'s workload, schedule, and the fastest paths into the rest of StudyFlow.',
          tips: [
            _ScreenGuideTip(
              title: 'Search quickly',
              body:
                  'Use the top search button to look across tasks, subjects, and cached Classroom activities from anywhere.',
            ),
            _ScreenGuideTip(
              title: 'Read the overview',
              body:
                  'The top stats show pending work, what is due today, upcoming exams, and progress completed this week.',
            ),
            _ScreenGuideTip(
              title: 'Check today first',
              body:
                  'Today\'s Schedule lists the schedule blocks happening today so you know what needs attention right now.',
            ),
            _ScreenGuideTip(
              title: 'Watch deadlines and alerts',
              body:
                  'Due Soon shows upcoming deadlines. The overdue alert below it helps you review unfinished work that is already past due.',
            ),
            _ScreenGuideTip(
              title: 'Move around fast',
              body:
                  'Quick Actions and the bottom navigation open the main parts of the app without extra steps.',
            ),
          ],
        );
      case 1:
        return const _ScreenGuideContent(
          id: 'calendar',
          title: 'Calendar',
          summary:
              'Use Calendar to see deadlines by date, manage smart schedules, and review Classroom items alongside StudyFlow entries.',
          tips: [
            _ScreenGuideTip(
              title: 'Browse by day',
              body:
                  'Select a date to inspect tasks, exams, projects, and schedule blocks attached to that day.',
            ),
            _ScreenGuideTip(
              title: 'Search and inspect',
              body:
                  'The search action helps you find planner items or Classroom entries quickly, then open their details.',
            ),
            _ScreenGuideTip(
              title: 'Add from context',
              body:
                  'Use the add button to create work or recurring schedule blocks directly for the date you are looking at.',
            ),
            _ScreenGuideTip(
              title: 'Trust the sync state',
              body:
                  'Calendar mixes local planner items with the latest saved Classroom snapshot, and hidden Classroom subjects stay filtered out here.',
            ),
          ],
        );
      case 2:
        return const _ScreenGuideContent(
          id: 'tasks',
          title: 'Tasks',
          summary:
              'Tasks is the planner workspace for assignments, exams, projects, and copied Classroom work.',
          tips: [
            _ScreenGuideTip(
              title: 'Filter what matters',
              body:
                  'Use the filter strip to jump between pending work, past due items, no-due-date items, completed work, exams, and high-priority items.',
            ),
            _ScreenGuideTip(
              title: 'Search and sort',
              body:
                  'Search narrows the list quickly, while sort lets you organize by due date, posted date, title, subject, or priority.',
            ),
            _ScreenGuideTip(
              title: 'Open items to manage them',
              body:
                  'Tap an item to edit details, subtasks, reminders, notes, or completion state.',
            ),
            _ScreenGuideTip(
              title: 'Create everything here',
              body:
                  'The add action can create tasks and exams from one place while Calendar owns recurring schedules.',
            ),
          ],
        );
      case 3:
        return const _ScreenGuideContent(
          id: 'subjects',
          title: 'Subjects',
          summary:
              'Subjects keeps your manual and Classroom subjects organized, including old courses you still need for reference.',
          tips: [
            _ScreenGuideTip(
              title: 'See all subject sources together',
              body:
                  'Manual subjects and Classroom subjects appear in one place so you can compare workload by course.',
            ),
            _ScreenGuideTip(
              title: 'Filter and archive',
              body:
                  'Use the filters to switch between all, manual, Classroom, and archived subjects. Hide or archive older courses you no longer want in daily views.',
            ),
            _ScreenGuideTip(
              title: 'Review course context',
              body:
                  'Each subject card shows the course identity, open work, and nearby deadlines so you can spot heavy courses quickly.',
            ),
            _ScreenGuideTip(
              title: 'Add manual subjects cleanly',
              body:
                  'Use the add action to create subjects with names, optional codes, semester labels, colors, and icons.',
            ),
          ],
        );
      case 4:
        return const _ScreenGuideContent(
          id: 'profile',
          title: 'Profile',
          summary:
              'Profile is where you control reminders, schedule vibration behavior, sync status, display settings, and your account details.',
          tips: [
            _ScreenGuideTip(
              title: 'Tune notifications',
              body:
                  'Adjust class reminders, schedule vibration alerts, study goal alerts, and reminder lead times here.',
            ),
            _ScreenGuideTip(
              title: 'Check sync status',
              body:
                  'The sync section shows the latest sync state and when your data was last updated.',
            ),
            _ScreenGuideTip(
              title: 'Adjust readability',
              body:
                  'Theme mode, font size, and other presentation settings live here so you can make the app easier to use.',
            ),
            _ScreenGuideTip(
              title: 'Manage your account',
              body:
                  'Use this screen to review your profile details, app version, and sign-out state.',
            ),
          ],
        );
    }
    return null;
  }

  Widget? _buildFloatingActionButton() {
    const insetButtonPadding = EdgeInsets.only(right: 18, bottom: 96);

    if (_currentIndex == 0) {
      return Padding(
        padding: insetButtonPadding,
        child: _ShellActionButton(onTap: _openHomeQuickActions),
      );
    }

    if (_currentIndex == 1) {
      return null;
    }

    if (_currentIndex == 2) {
      return Padding(
        padding: insetButtonPadding,
        child: _ShellActionButton(
          onTap: () => _tasksKey.currentState?.openCreateMenu(),
        ),
      );
    }

    if (_currentIndex == 3) {
      return Padding(
        padding: insetButtonPadding,
        child: _ShellActionButton(
          onTap: () => _subjectsKey.currentState?.openCreateSubjectSheet(),
        ),
      );
    }

    return null;
  }

  void _openTaskCreator(PlannerItemType type, DateTime? initialDate) {
    if (type == PlannerItemType.schedule) {
      _openScheduleCreator(initialDate);
      return;
    }

    _setCurrentIndex(2, showGuide: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tasksKey.currentState?.openCreateMenu(
        initialType: type,
        initialDate: initialDate,
      );
    });
  }

  void _openScheduleCreator(DateTime? initialDate) {
    _setCurrentIndex(1, showGuide: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calendarKey.currentState?.openCreateMenu(
        initialType: PlannerItemType.schedule,
        initialDate: initialDate,
      );
    });
  }

  void _openSubjectCreator() {
    _setCurrentIndex(3, showGuide: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subjectsKey.currentState?.openCreateSubjectSheet();
    });
  }

  void _openManualSubject(String subjectId) {
    _setCurrentIndex(3, showGuide: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subjectsKey.currentState?.openManualSubjectById(subjectId);
    });
  }

  void _openClassroomSubject(String subjectKey) {
    _setCurrentIndex(3, showGuide: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subjectsKey.currentState?.openClassroomSubjectByKey(subjectKey);
    });
  }

  Future<void> _runManualSyncAndShowMessage() async {
    final message = await _runSync(promptIfNecessary: true);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String> _runSync({required bool promptIfNecessary}) async {
    final calendarState = _calendarKey.currentState;
    final message = calendarState != null
        ? await calendarState.runManualSync(
            promptIfNecessary: promptIfNecessary,
          )
        : await _runManualSyncFallback(promptIfNecessary: promptIfNecessary);
    await _refreshCachedClassroomConsumers();
    return message;
  }

  Future<String> _runManualSyncFallback({
    required bool promptIfNecessary,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return 'Could not start Classroom sync right now.';
    }

    final isOffline = !await DatabaseService.instance.isConnected();
    await widget.controller.updateSyncState(
      status: SyncStatus.syncing,
      lastSyncCheckedAt: DateTime.now(),
      lastSyncedAt: widget.controller.lastSyncedAt,
    );

    final result = await _calendarRepository.refreshFromClassroom(
      uid: uid,
      promptIfNecessary: promptIfNecessary,
      isOffline: isOffline,
    );
    await widget.controller.updateSyncState(
      status: result.syncStatus,
      lastSyncCheckedAt: DateTime.now(),
      lastSyncedAt:
          result.snapshot?.lastSyncedAt ?? widget.controller.lastSyncedAt,
    );

    try {
      await NotificationService.instance.refreshForUser(
        uid: uid,
        controller: widget.controller,
      );
    } catch (_) {
      // Keep sync UX stable even if reminder refresh fails.
    }

    if (result.needsAuthorization) {
      return 'Classroom still needs your permission before it can sync.';
    }
    if ((result.errorMessage ?? '').trim().isNotEmpty) {
      return result.errorMessage!;
    }
    if (result.snapshot != null) {
      return 'Classroom data refreshed.';
    }
    return 'Sync finished.';
  }

  Future<void> _refreshCachedClassroomConsumers() async {
    await _tasksKey.currentState?.reloadClassroomSnapshot();
    await _subjectsKey.currentState?.reloadClassroomSnapshot();
  }

  void _openHomeQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const ModalSheetHeader(
                title: 'Quick Actions',
                subtitle:
                    'Use the same shortcuts as the Home quick-action grid.',
              ),
              const SizedBox(height: 16),
              _QuickActionSheetTile(
                iconAsset: 'assets/icons/document.svg',
                label: 'Add Task',
                onTap: () {
                  Navigator.of(context).pop();
                  _openTaskCreator(PlannerItemType.task, null);
                },
              ),
              _QuickActionSheetTile(
                iconAsset: 'assets/icons/calendar.svg',
                label: 'Exams & Quizzes',
                onTap: () {
                  Navigator.of(context).pop();
                  _openTaskCreator(PlannerItemType.exam, null);
                },
              ),
              _QuickActionSheetTile(
                iconAsset: 'assets/icons/clock.svg',
                label: 'Smart Schedule',
                onTap: () {
                  Navigator.of(context).pop();
                  _openScheduleCreator(null);
                },
              ),
              _QuickActionSheetTile(
                iconAsset: 'assets/icons/subject.svg',
                label: 'Add Subject',
                onTap: () {
                  Navigator.of(context).pop();
                  _openSubjectCreator();
                },
              ),
              _QuickActionSheetTile(
                iconAsset: 'assets/icons/load.svg',
                label: 'Sync Data',
                onTap: () {
                  Navigator.of(context).pop();
                  _runManualSyncAndShowMessage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openGlobalSearchSheet() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        return _GlobalSearchSheet(
          loader: () async {
            final plannerItems = await DatabaseService.instance.getPlannerItems(
              uid,
            );
            final subjects = await DatabaseService.instance.getSubjects(uid);
            final snapshot = await CalendarRepository.instance
                .loadBestAvailableSnapshot(uid);
            return _GlobalSearchData(
              plannerItems: plannerItems,
              subjects: subjects,
              classroomEntries: snapshot?.entries ?? const <CalendarEntry>[],
            );
          },
          onPlannerSelected: (item) {
            Navigator.of(context).pop();
            if (item.type == PlannerItemType.schedule) {
              _setCurrentIndex(1, showGuide: false);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _calendarKey.currentState?.openPlannerItemDetails(item);
              });
              return;
            }

            _setCurrentIndex(2, showGuide: false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _tasksKey.currentState?.openItemDetails(item);
            });
          },
          onClassroomSelected: (entry) {
            Navigator.of(context).pop();
            _setCurrentIndex(1, showGuide: false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _calendarKey.currentState?.openEntryDetails(entry);
            });
          },
          onSubjectSelected: (_) {
            Navigator.of(context).pop();
            _setCurrentIndex(3, showGuide: false);
          },
        );
      },
    );
  }

  void _handleSearch() {
    if (_currentIndex == 0) {
      _openGlobalSearchSheet();
      return;
    }

    if (_currentIndex == 2) {
      _tasksKey.currentState?.openSearchSheet();
      return;
    }

    if (_currentIndex == 1) {
      _calendarKey.currentState?.openSearchSheet();
      return;
    }

    if (_currentIndex == 3) {
      _subjectsKey.currentState?.openSearchSheet();
      return;
    }

    _setCurrentIndex(2, showGuide: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tasksKey.currentState?.openSearchSheet();
    });
  }
}

class _GlobalSearchData {
  const _GlobalSearchData({
    required this.plannerItems,
    required this.subjects,
    required this.classroomEntries,
  });

  final List<PlannerItem> plannerItems;
  final List<SubjectRecord> subjects;
  final List<CalendarEntry> classroomEntries;
}

class _GlobalSearchSheet extends StatefulWidget {
  const _GlobalSearchSheet({
    required this.loader,
    required this.onPlannerSelected,
    required this.onClassroomSelected,
    required this.onSubjectSelected,
  });

  final Future<_GlobalSearchData> Function() loader;
  final ValueChanged<PlannerItem> onPlannerSelected;
  final ValueChanged<CalendarEntry> onClassroomSelected;
  final ValueChanged<SubjectRecord> onSubjectSelected;

  @override
  State<_GlobalSearchSheet> createState() => _GlobalSearchSheetState();
}

class _GlobalSearchSheetState extends State<_GlobalSearchSheet> {
  late final Future<_GlobalSearchData> _future = widget.loader();
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ModalSheetHeader(
            title: 'Global Search',
            subtitle:
                'Search across StudyFlow tasks, exams, schedules, subjects, and cached Classroom activities.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search titles, subjects, notes, or deadlines',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF182134)
                  : const Color(0xFFF2F4F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: FutureBuilder<_GlobalSearchData>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _GlobalSearchResults(
                  query: _controller.text,
                  data: snapshot.data!,
                  onPlannerSelected: widget.onPlannerSelected,
                  onClassroomSelected: widget.onClassroomSelected,
                  onSubjectSelected: widget.onSubjectSelected,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalSearchResults extends StatelessWidget {
  const _GlobalSearchResults({
    required this.query,
    required this.data,
    required this.onPlannerSelected,
    required this.onClassroomSelected,
    required this.onSubjectSelected,
  });

  final String query;
  final _GlobalSearchData data;
  final ValueChanged<PlannerItem> onPlannerSelected;
  final ValueChanged<CalendarEntry> onClassroomSelected;
  final ValueChanged<SubjectRecord> onSubjectSelected;

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final plannerResults = data.plannerItems
        .where((item) {
          if (normalized.isEmpty) return true;
          return [
            item.title,
            item.description,
            item.notes,
            item.categoryLabel,
            item.subjectName,
            item.subjectCode,
            item.typeLabel,
            item.priorityLabel,
          ].whereType<String>().join(' ').toLowerCase().contains(normalized);
        })
        .take(8)
        .toList();
    final subjectResults = data.subjects
        .where((subject) {
          if (normalized.isEmpty) return true;
          return [
            subject.subjectName,
            subject.subjectCode,
            subject.instructorName,
            subject.termLabel,
          ].whereType<String>().join(' ').toLowerCase().contains(normalized);
        })
        .take(6)
        .toList();
    final classroomResults = data.classroomEntries
        .where((entry) {
          if (normalized.isEmpty) return true;
          return [
            entry.title,
            entry.subject,
            entry.description,
            entry.typeLabel,
            entry.badgeLabel,
          ].whereType<String>().join(' ').toLowerCase().contains(normalized);
        })
        .take(8)
        .toList();

    if (plannerResults.isEmpty &&
        subjectResults.isEmpty &&
        classroomResults.isEmpty) {
      return Center(
        child: Text(
          'No results matched "$query".',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      children: [
        if (plannerResults.isNotEmpty)
          _GlobalResultSection(
            title: 'Planner',
            children: plannerResults
                .map(
                  (item) => _GlobalResultTile(
                    icon: switch (item.type) {
                      PlannerItemType.exam => Icons.quiz_outlined,
                      PlannerItemType.schedule => Icons.schedule_rounded,
                      PlannerItemType.project =>
                        Icons.auto_awesome_motion_outlined,
                      PlannerItemType.task => Icons.description_outlined,
                    },
                    title: item.title,
                    subtitle:
                        '${item.subjectName ?? item.subjectCode ?? 'Subject'} | ${item.typeLabel}',
                    onTap: () => onPlannerSelected(item),
                  ),
                )
                .toList(),
          ),
        if (classroomResults.isNotEmpty)
          _GlobalResultSection(
            title: 'Classroom',
            children: classroomResults
                .map(
                  (entry) => _GlobalResultTile(
                    icon: entry.type == CalendarEntryType.exam
                        ? Icons.quiz_outlined
                        : Icons.school_outlined,
                    title: entry.title,
                    subtitle: '${entry.subject} | ${entry.typeLabel}',
                    onTap: () => onClassroomSelected(entry),
                  ),
                )
                .toList(),
          ),
        if (subjectResults.isNotEmpty)
          _GlobalResultSection(
            title: 'Subjects',
            children: subjectResults
                .map(
                  (subject) => _GlobalResultTile(
                    icon: Icons.menu_book_outlined,
                    title: subject.subjectName,
                    subtitle: subject.subjectCode,
                    onTap: () => onSubjectSelected(subject),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _GlobalResultSection extends StatelessWidget {
  const _GlobalResultSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _GlobalResultTile extends StatelessWidget {
  const _GlobalResultTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: Theme.of(context).cardColor.withValues(alpha: 0.95),
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.14),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _QuickActionSheetTile extends StatelessWidget {
  const _QuickActionSheetTile({
    required this.iconAsset,
    required this.label,
    required this.onTap,
  });

  final String iconAsset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: SvgPicture.asset(
        iconAsset,
        width: 22,
        height: 22,
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.primary,
          BlendMode.srcIn,
        ),
      ),
      title: Text(label),
      onTap: onTap,
    );
  }
}

class _ScreenGuideContent {
  const _ScreenGuideContent({
    required this.id,
    required this.title,
    required this.summary,
    required this.tips,
  });

  final String id;
  final String title;
  final String summary;
  final List<_ScreenGuideTip> tips;
}

class _ScreenGuideTip {
  const _ScreenGuideTip({required this.title, required this.body});

  final String title;
  final String body;
}

class _ScreenGuideSheet extends StatelessWidget {
  const _ScreenGuideSheet({required this.guide});

  final _ScreenGuideContent guide;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModalSheetHeader(title: guide.title, subtitle: guide.summary),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: guide.tips.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final tip = guide.tips[index];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).cardColor.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.65),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.lightbulb_outline_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tip.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tip.body,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeOnboardingSheet extends StatefulWidget {
  const _WelcomeOnboardingSheet({required this.onConnectClassroom});

  final Future<String> Function() onConnectClassroom;

  @override
  State<_WelcomeOnboardingSheet> createState() =>
      _WelcomeOnboardingSheetState();
}

class _WelcomeOnboardingSheetState extends State<_WelcomeOnboardingSheet> {
  bool _isConnecting = false;
  String? _statusMessage;

  Future<void> _handleConnectClassroom() async {
    if (_isConnecting) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = null;
    });

    try {
      final message = await widget.onConnectClassroom();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModalSheetHeader(
              title: 'Welcome to StudyFlow',
              subtitle:
                  'Before the tour starts, you can connect Google Classroom right away so schedules, activities, and deadlines are ready from the beginning.',
              onBack: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 16),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.waving_hand_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isConnecting ? null : _handleConnectClassroom,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.school_outlined),
              label: Text(
                _isConnecting ? 'Connecting Classroom...' : 'Connect Classroom',
              ),
            ),
            if ((_statusMessage ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Start Tour'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF12192B).withValues(alpha: 0.84)
        : Colors.white.withValues(alpha: 0.82);

    final items = const [
      _NavItemData(label: 'Home', iconAsset: 'assets/icons/home.svg'),
      _NavItemData(label: 'Calendar', iconAsset: 'assets/icons/calendar.svg'),
      _NavItemData(label: 'Tasks', iconAsset: 'assets/icons/plus.svg'),
      _NavItemData(label: 'Subjects', iconAsset: 'assets/icons/subject.svg'),
      _NavItemData(label: 'Profile', iconAsset: 'assets/icons/profile.svg'),
    ];

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF313A52).withValues(alpha: 0.85)
                    : const Color(0xFFE7EBF4).withValues(alpha: 0.9),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x220F172A),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: List.generate(
                items.length,
                (index) => Expanded(
                  child: _NavButton(
                    data: items[index],
                    isSelected: currentIndex == index,
                    isCenter: index == 2,
                    onTap: () => onTap(index),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.data,
    required this.isSelected,
    required this.onTap,
    required this.isCenter,
  });

  final _NavItemData data;
  final bool isSelected;
  final bool isCenter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;
    final activeForeground =
        Theme.of(context).colorScheme.brightness == Brightness.dark
        ? Theme.of(context).colorScheme.onPrimary
        : Colors.white;
    final inactiveColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFAAB3C7)
        : const Color(0xFF6F7890);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected && !isCenter
              ? activeColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCenter)
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  data.iconAsset,
                  width: 15,
                  height: 15,
                  colorFilter: ColorFilter.mode(
                    activeForeground,
                    BlendMode.srcIn,
                  ),
                ),
              )
            else
              SvgPicture.asset(
                data.iconAsset,
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  isSelected ? activeColor : inactiveColor,
                  BlendMode.srcIn,
                ),
              ),
            const SizedBox(height: 5),
            Text(
              data.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 12,
                color: isSelected ? activeColor : inactiveColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopNavigationBar extends StatelessWidget {
  const _TopNavigationBar({
    required this.user,
    required this.textTheme,
    required this.onShowGuide,
    required this.onSearch,
  });

  final User? user;
  final TextTheme textTheme;
  final VoidCallback onShowGuide;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isDark
        ? const Color(0xFF12192B).withValues(alpha: 0.8)
        : Colors.white.withValues(alpha: 0.78);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF313A52).withValues(alpha: 0.8)
                    : const Color(0xFFE7EBF4).withValues(alpha: 0.88),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x160F172A),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                UserAvatar(
                  photoUrl: user?.photoURL,
                  displayName: user?.displayName,
                  radius: 18,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.14),
                ),
                const SizedBox(width: 14),
                Text(
                  'StudyFlow',
                  style: textTheme.titleLarge?.copyWith(
                    color: colorScheme.primary,
                    fontSize: 22,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onShowGuide,
                  icon: Icon(
                    Icons.help_outline_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
                IconButton(
                  onPressed: onSearch,
                  icon: Icon(
                    Icons.search_rounded,
                    color: colorScheme.primary,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellActionButton extends StatelessWidget {
  const _ShellActionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.onPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Ink(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: SvgPicture.asset(
              'assets/icons/plus.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({required this.label, required this.iconAsset});

  final String label;
  final String iconAsset;
}
