import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_controller.dart';
import '../models/reminder_presets.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../widgets/modal_sheet_header.dart';
import '../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const List<({String version, String build, List<String> notes})>
  _releaseHistory = [
    (
      version: '1.2.1',
      build: '4',
      notes: [
        'Changed the calendar week to start on Sunday for quicker glance reading.',
        'Refined subject work details so items open fuller views with direct edit and Classroom actions.',
        'Stabilized calendar/task classification and trimmed UI work that was contributing to frame drops.',
      ],
    ),
    (
      version: '1.9.1',
      build: '3',
      notes: [
        'Expanded appearance presets with Blossom, Mono, and Passion themes.',
        'Improved dark-mode readability across pills, tabs, and themed accent surfaces.',
        'Updated the shell bars so content can pass underneath while keeping the navigation surfaces readable.',
      ],
    ),
    (
      version: '1.1.6',
      build: '3',
      notes: [
        'Extended theme accents across navigation actions, filter pills, calendar day highlights, and profile visuals.',
        'Made release notes scrollable and expanded the version history back to the first public build.',
        'Aligned the Calendar add button with the smaller circular action button used on the rest of the app.',
      ],
    ),
    (
      version: '1.1.5',
      build: '3',
      notes: [
        'Refined sync behavior, moved sync status into Home, and trimmed long calendar cards for faster scanning.',
        'Added appearance accents and auto-sync preferences.',
      ],
    ),
    (
      version: '1.1.3',
      build: '2',
      notes: [
        'Improved schedule reminders and cleaned up alert timing for recurring entries.',
        'Tuned dark-mode contrast across Home and Calendar.',
      ],
    ),
    (
      version: '1.1.1',
      build: '2',
      notes: [
        'Expanded task filtering with schedules, no-due-date work, and past-due review improvements.',
        'Improved hidden Classroom propagation across screens.',
      ],
    ),
    (
      version: '1.0.9',
      build: '2',
      notes: [
        'Added onboarding guides and first-use walkthroughs for the main screens.',
        'Improved profile controls and reminder defaults.',
      ],
    ),
    (
      version: '1.0.7',
      build: '2',
      notes: [
        'Introduced archive and hide flows for subjects and classroom-derived records.',
        'Aligned manual subject cards with Classroom subject presentation.',
      ],
    ),
    (
      version: '1.0.5',
      build: '1',
      notes: [
        'Reworked the splash/login flow and improved automatic sign-in handling for returning users.',
        'Added font size options and general UI clarity fixes.',
      ],
    ),
    (
      version: '1.0.2',
      build: '1',
      notes: [
        'Polished dashboard ordering and improved live refresh behavior after sync.',
        'Stabilized task loading and offline-friendly planner updates.',
      ],
    ),
    (
      version: '1.0.0',
      build: '1',
      notes: [
        'Initial StudyFlow release with Home, Calendar, Tasks, Subjects, and Profile workflows.',
        'Delivered Google sign-in, planner tools, and classroom-aware study organization.',
      ],
    ),
  ];

  late Future<Map<Object?, Object?>?> _profileFuture;
  late Future<PackageInfo> _packageInfoFuture;

  static const Map<ReminderCategory, List<String>> _reminderOptions = {
    ReminderCategory.tasks: taskReminderOptions,
    ReminderCategory.exams: examReminderOptions,
    ReminderCategory.lectures: lectureReminderOptions,
  };

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  Future<Map<Object?, Object?>?> _loadProfile() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null
        ? Future.value(null)
        : DatabaseService.instance.getCurrentUserProfile(user.uid);
  }

  Future<void> _reloadProfile() async {
    setState(() {
      _profileFuture = _loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final user = FirebaseAuth.instance.currentUser;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 98, 22, 138),
          children: [
            FutureBuilder<Map<Object?, Object?>?>(
              future: _profileFuture,
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final displayName =
                    _profileValue(profile, 'fullName') ??
                    user?.displayName ??
                    'Student Workspace';
                final displayEmail =
                    _profileValue(profile, 'email') ??
                    user?.email ??
                    'No email available';
                final program =
                    _profileValue(profile, 'academicProgram') ??
                    'Program pending';
                final yearLevel = _profileValue(profile, 'yearLevel');

                return Container(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? const Color(0x00000000)
                            : const Color(0x120F172A),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          UserAvatar(
                            photoUrl: user?.photoURL,
                            displayName: user?.displayName,
                            radius: 52,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.14),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _openProfileEditor(profile),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).cardColor,
                                      width: 3,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: SvgPicture.asset(
                                    'assets/icons/edit.svg',
                                    width: 18,
                                    height: 18,
                                    colorFilter: ColorFilter.mode(
                                      Theme.of(context).colorScheme.onPrimary,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        displayName,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(fontSize: 24),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayEmail,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _BadgeChip(label: program),
                          _BadgeChip(
                            label: yearLevel == null || yearLevel.isEmpty
                                ? 'Year pending'
                                : 'Year $yearLevel',
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            _SectionCard(
              iconAsset: 'assets/icons/notification.svg',
              title: 'Notifications',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SwitchRow(
                    label: 'App Notifications',
                    value: widget.controller.appNotificationsEnabled,
                    onChanged: (value) async {
                      await widget.controller.setAppNotificationsEnabled(value);
                      await _refreshPlannerNotifications();
                      if (!mounted) return;
                      _showFeedback(
                        value
                            ? 'App notifications turned on.'
                            : 'App notifications turned off.',
                      );
                    },
                  ),
                  if (widget.controller.appNotificationsEnabled) ...[
                    const SizedBox(height: 8),
                    _SwitchRow(
                      label: 'Task Notifications',
                      value: widget.controller.taskRemindersEnabled,
                      onChanged: (value) async {
                        await widget.controller.setTaskRemindersEnabled(value);
                        await _refreshPlannerNotifications();
                        if (!mounted) return;
                        _showFeedback(
                          value
                              ? 'Task notifications turned on.'
                              : 'Task notifications turned off.',
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _SwitchRow(
                      label: 'Quiz Notifications',
                      value: widget.controller.examRemindersEnabled,
                      onChanged: (value) async {
                        await widget.controller.setExamRemindersEnabled(value);
                        await _refreshPlannerNotifications();
                        if (!mounted) return;
                        _showFeedback(
                          value
                              ? 'Quiz notifications turned on.'
                              : 'Quiz notifications turned off.',
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _SwitchRow(
                      label: 'Schedule Notifications',
                      value: widget.controller.classRemindersEnabled,
                      onChanged: (value) async {
                        await widget.controller.setClassRemindersEnabled(value);
                        await _refreshPlannerNotifications();
                        if (!mounted) return;
                        _showFeedback(
                          value
                              ? 'Schedule notifications turned on.'
                              : 'Schedule notifications turned off.',
                        );
                      },
                    ),
                    if (widget.controller.classRemindersEnabled) ...[
                      const SizedBox(height: 8),
                      _SwitchRow(
                        label: 'Vibrate-Only Schedules',
                        value: widget.controller.lectureVibrationOnly,
                        onChanged: (value) async {
                          await widget.controller.setLectureVibrationOnly(
                            value,
                          );
                          await _refreshPlannerNotifications();
                          if (!mounted) return;
                          _showFeedback(
                            value
                                ? 'Schedules now use a one-minute vibration-only alert.'
                                : 'Schedules now use ringtone sound and vibration together.',
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    _SwitchRow(
                      label: 'Study Goal Alerts',
                      value: widget.controller.studyGoalAlertsEnabled,
                      onChanged: (value) async {
                        await widget.controller.setStudyGoalAlertsEnabled(
                          value,
                        );
                        await _refreshPlannerNotifications();
                        if (!mounted) return;
                        _showFeedback(
                          value
                              ? 'Study goal alerts turned on.'
                              : 'Study goal alerts turned off.',
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Schedules use a one-minute vibration alert by default. Turn off Vibrate-Only Schedules if you want ringtone sound and vibration together. Study goal alerts follow the app notification setting and only run when they are enabled here.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SectionCard(
              iconAsset: 'assets/icons/load.svg',
              title: 'Sync Preferences',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SwitchRow(
                    label: 'Auto Sync',
                    value: widget.controller.autoSyncEnabled,
                    onChanged: (value) async {
                      await widget.controller.setAutoSyncEnabled(value);
                      if (!mounted) return;
                      _showFeedback(
                        value
                            ? 'Auto sync turned on.'
                            : 'Auto sync turned off.',
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'When Auto Sync is on, StudyFlow checks for Classroom updates while the app is active and again when you come back to it.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SectionCard(
              iconAsset: 'assets/icons/clock.svg',
              title: 'Reminder Defaults',
              child: Column(
                children: [
                  _ReminderTile(
                    label: 'Tasks',
                    value: widget.controller.taskReminderDefault,
                    onTap: () => _selectReminderDefault(
                      ReminderCategory.tasks,
                      widget.controller.taskReminderDefault,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ReminderTile(
                    label: 'Exams',
                    value: widget.controller.examReminderDefault,
                    onTap: () => _selectReminderDefault(
                      ReminderCategory.exams,
                      widget.controller.examReminderDefault,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ReminderTile(
                    label: 'Schedules',
                    value: widget.controller.lectureReminderDefault,
                    onTap: () => _selectReminderDefault(
                      ReminderCategory.lectures,
                      widget.controller.lectureReminderDefault,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SectionCard(
              iconAsset: 'assets/icons/art.svg',
              title: 'Appearance',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AppearanceSelector(
                    themeMode: widget.controller.themeMode,
                    onChanged: (mode) async {
                      await widget.controller.setThemeMode(mode);
                      if (!mounted) return;
                      _showFeedback('Appearance updated.');
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'THEME',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ThemeAccentSelector(
                    accent: widget.controller.themeAccent,
                    onChanged: (accent) async {
                      await widget.controller.setThemeAccent(accent);
                      if (!mounted) return;
                      _showFeedback('Theme updated.');
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'FONT SIZE',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _FontSizeSelector(
                    fontSize: widget.controller.appFontSize,
                    onChanged: (fontSize) async {
                      await widget.controller.setAppFontSize(fontSize);
                      if (!mounted) return;
                      _showFeedback('Font size set to ${fontSize.label}.');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SectionCard(
              iconAsset: 'assets/icons/information.svg',
              title: 'About App',
              child: FutureBuilder<PackageInfo>(
                future: _packageInfoFuture,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  final version = info?.version ?? '1.2.1';
                  final build = info?.buildNumber ?? '4';

                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'StudyFlow Pro',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Version $version (Build $build)',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _showReleaseNotes,
                        child: const Text('Release Notes'),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton(
              onPressed: _confirmSignOut,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(66),
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.9),
                  width: 1.4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icons/signout.svg',
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.error,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sign Out',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'MADE FOR FOCUSED ACADEMIC SUCCESS',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                letterSpacing: 1.8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _selectReminderDefault(
    ReminderCategory category,
    String currentValue,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        final options = _reminderOptions[category]!;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              ModalSheetHeader(
                title: _titleForCategory(category),
                subtitle:
                    'Choose the default reminder timing for future items in this category.',
              ),
              const SizedBox(height: 18),
              ...options.map(
                (option) => ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  title: Text(option),
                  trailing: option == currentValue
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(option),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || selected == currentValue) {
      return;
    }

    await widget.controller.updateReminderDefault(category, selected);
    await _refreshPlannerNotifications();
    if (!mounted) return;
    _showFeedback('${_titleForCategory(category)} updated.');
  }

  Future<void> _refreshPlannerNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    try {
      await NotificationService.instance.refreshForUser(
        uid: uid,
        controller: widget.controller,
      );
    } catch (error) {
      debugPrint('StudyFlow could not refresh notification settings: $error');
    }
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            'This will end the current session and return you to the Google sign-in screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true) {
      return;
    }

    try {
      await AuthService.instance.signOut();
    } catch (_) {
      if (!mounted) return;
      _showFeedback('Couldn\'t sign out. Please try again.');
    }
  }

  Future<void> _openProfileEditor(Map<Object?, Object?>? profile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final result = await showModalBottomSheet<_EditableProfileData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        return _ProfileEditorSheet(
          initialData: _EditableProfileData(
            fullName:
                _profileValue(profile, 'fullName') ??
                user.displayName ??
                'Student',
            email: _profileValue(profile, 'email') ?? user.email ?? '',
            academicProgram: _profileValue(profile, 'academicProgram') ?? '',
            yearLevel: _profileValue(profile, 'yearLevel') ?? '',
            birthDate: _profileValue(profile, 'birthDate') ?? '',
            phoneNumber: _profileValue(profile, 'phoneNumber') ?? '',
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    await DatabaseService.instance.updateUserProfileDetails(
      uid: user.uid,
      values: {
        'fullName': result.fullName,
        'email': result.email,
        'academicProgram': result.academicProgram,
        'yearLevel': result.yearLevel,
        'birthDate': result.birthDate,
        'phoneNumber': result.phoneNumber,
      },
    );

    await _reloadProfile();

    if (!mounted) return;
    _showFeedback('Profile updated.');
  }

  void _showReleaseNotes() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.78,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ModalSheetHeader(
                    title: 'Release Notes',
                    subtitle: 'Version history across StudyFlow builds.',
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _releaseHistory.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final entry = _releaseHistory[index];
                        return Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Version ${entry.version} (Build ${entry.build})',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 10),
                              ...entry.notes.map(
                                (note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '• ',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge,
                                      ),
                                      Expanded(
                                        child: Text(
                                          note,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyLarge,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _profileValue(Map<Object?, Object?>? profile, String key) {
    final value = profile?[key];
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _titleForCategory(ReminderCategory category) {
    switch (category) {
      case ReminderCategory.tasks:
        return 'Task reminders';
      case ReminderCategory.exams:
        return 'Exam reminders';
      case ReminderCategory.lectures:
        return 'Schedule reminders';
    }
  }
}

class _EditableProfileData {
  const _EditableProfileData({
    required this.fullName,
    required this.email,
    required this.academicProgram,
    required this.yearLevel,
    required this.birthDate,
    required this.phoneNumber,
  });

  final String fullName;
  final String email;
  final String academicProgram;
  final String yearLevel;
  final String birthDate;
  final String phoneNumber;
}

class _ProfileEditorSheet extends StatefulWidget {
  const _ProfileEditorSheet({required this.initialData});

  final _EditableProfileData initialData;

  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _programController;
  late final TextEditingController _yearLevelController;
  late final TextEditingController _birthDateController;
  late final TextEditingController _phoneNumberController;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.initialData.fullName,
    );
    _emailController = TextEditingController(text: widget.initialData.email);
    _programController = TextEditingController(
      text: widget.initialData.academicProgram,
    );
    _yearLevelController = TextEditingController(
      text: widget.initialData.yearLevel,
    );
    _birthDateController = TextEditingController(
      text: widget.initialData.birthDate,
    );
    _phoneNumberController = TextEditingController(
      text: widget.initialData.phoneNumber,
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _programController.dispose();
    _yearLevelController.dispose();
    _birthDateController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

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
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ModalSheetHeader(
                  title: 'Edit profile',
                  subtitle:
                      'Update your academic identity and profile details. Sign-in access still uses your Google account.',
                ),
                const SizedBox(height: 20),
                _ProfileField(
                  controller: _fullNameController,
                  label: 'Full name',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your full name.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _ProfileField(
                  controller: _emailController,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your email.';
                    }

                    if (!value.contains('@')) {
                      return 'Enter a valid email.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _ProfileField(
                  controller: _birthDateController,
                  label: 'Birthdate',
                  readOnly: true,
                  trailingIcon: Icons.calendar_today_outlined,
                  onTap: _pickBirthDate,
                ),
                const SizedBox(height: 14),
                _ProfileField(
                  controller: _programController,
                  label: 'Academic program',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your academic program.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _ProfileField(
                  controller: _yearLevelController,
                  label: 'Year level',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your year level.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _ProfileField(
                  controller: _phoneNumberController,
                  label: 'Phone number',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _submit,
                    child: Text(_isSaving ? 'Saving...' : 'Save changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    DateTime? initialDate = DateTime(2003, 1, 1);
    final existingValue = _birthDateController.text.trim();
    if (existingValue.isNotEmpty) {
      initialDate = DateTime.tryParse(existingValue) ?? initialDate;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime.now(),
    );

    if (picked == null) {
      return;
    }

    _birthDateController.text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    Navigator.of(context).pop(
      _EditableProfileData(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        academicProgram: _programController.text.trim(),
        yearLevel: _yearLevelController.text.trim(),
        birthDate: _birthDateController.text.trim(),
        phoneNumber: _phoneNumberController.text.trim(),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.readOnly = false,
    this.onTap,
    this.trailingIcon,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: trailingIcon == null ? null : Icon(trailingIcon),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A2337)
            : const Color(0xFFF6F8FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.iconAsset,
    required this.title,
    required this.child,
  });

  final String iconAsset;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                iconAsset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _AppearanceSelector extends StatelessWidget {
  const _AppearanceSelector({required this.themeMode, required this.onChanged});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).cardColor;
    final unselectedColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF232C40)
        : const Color(0xFFE5E9F0);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: unselectedColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ThemeOption(
              label: 'Light',
              icon: Icons.light_mode_outlined,
              isSelected: themeMode == ThemeMode.light,
              backgroundColor: selectedColor,
              onTap: () => onChanged(ThemeMode.light),
            ),
          ),
          Expanded(
            child: _ThemeOption(
              label: 'Dark',
              icon: Icons.dark_mode_outlined,
              isSelected: themeMode == ThemeMode.dark,
              backgroundColor: selectedColor,
              onTap: () => onChanged(ThemeMode.dark),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeAccentSelector extends StatelessWidget {
  const _ThemeAccentSelector({required this.accent, required this.onChanged});

  final AppThemeAccent accent;
  final ValueChanged<AppThemeAccent> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).cardColor;
    final unselectedColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF232C40)
        : const Color(0xFFE5E9F0);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: unselectedColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 8.0;
          final itemWidth = (constraints.maxWidth - spacing * 2) / 3;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: AppThemeAccent.values
                .map(
                  (option) => SizedBox(
                    width: itemWidth,
                    child: _ThemeOption(
                      label: option.label,
                      icon: switch (option) {
                        AppThemeAccent.study => Icons.auto_awesome_rounded,
                        AppThemeAccent.forest => Icons.park_rounded,
                        AppThemeAccent.sunset => Icons.wb_twilight_rounded,
                        AppThemeAccent.blossom => Icons.local_florist_rounded,
                        AppThemeAccent.mono => Icons.contrast_rounded,
                        AppThemeAccent.passion => Icons.favorite_rounded,
                      },
                      isSelected: accent == option,
                      backgroundColor: selectedColor,
                      onTap: () => onChanged(option),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class _FontSizeSelector extends StatelessWidget {
  const _FontSizeSelector({required this.fontSize, required this.onChanged});

  final AppFontSize fontSize;
  final ValueChanged<AppFontSize> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).cardColor;
    final unselectedColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF232C40)
        : const Color(0xFFE5E9F0);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: unselectedColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ThemeOption(
              label: 'Default',
              icon: Icons.text_fields_rounded,
              isSelected: fontSize == AppFontSize.defaultSize,
              backgroundColor: selectedColor,
              onTap: () => onChanged(AppFontSize.defaultSize),
            ),
          ),
          Expanded(
            child: _ThemeOption(
              label: 'Small',
              icon: Icons.format_size_rounded,
              isSelected: fontSize == AppFontSize.small,
              backgroundColor: selectedColor,
              onTap: () => onChanged(AppFontSize.small),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.backgroundColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? backgroundColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
