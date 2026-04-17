import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../models/calendar_cache_snapshot.dart';
import '../models/calendar_entry.dart';
import '../models/planner_item.dart';
import '../models/subject_appearance.dart';
import '../models/subject_record.dart';
import '../services/auth_service.dart';
import '../services/calendar_repository.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../widgets/modal_sheet_header.dart';
import 'planner_item_editor_sheet.dart';
import 'smart_schedule_editor_sheet.dart';

enum SubjectCollectionFilter { all, manual, classroom, archived }

String _formatMonthDay(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}';
}

String _formatLongDate(DateTime value) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _formatShortTime(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String _normalizedSubjectKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
}

String _formatSyncLabel(DateTime? value) {
  if (value == null) {
    return 'No Classroom snapshot yet';
  }

  final now = DateTime.now();
  final isToday =
      value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;

  if (isToday) {
    return 'Updated today at ${_formatShortTime(value)}';
  }

  return 'Updated ${_formatLongDate(value)}';
}

String _deadlineLabel(DateTime? value) {
  if (value == null) {
    return 'No deadline';
  }

  final now = DateTime.now();
  final dateOnly = DateTime(value.year, value.month, value.day);
  final todayOnly = DateTime(now.year, now.month, now.day);
  final difference = dateOnly.difference(todayOnly).inDays;
  if (difference == 0) {
    return 'Due today';
  }
  if (difference == 1) {
    return 'Due tomorrow';
  }
  if (difference < 0) {
    return 'Past due';
  }

  return 'Due ${_formatMonthDay(value)}';
}

String _initialsFor(String name) {
  final words = name
      .split(RegExp(r'\s+'))
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return 'SUB';
  }

  if (words.length == 1) {
    final word = words.first;
    final end = word.length < 3 ? word.length : 3;
    return word.substring(0, end).toUpperCase();
  }

  return words.take(4).map((word) => word[0]).join().toUpperCase();
}

Color _surfaceTint(Color color, double opacity) {
  return color.withValues(alpha: opacity);
}

Color _foregroundFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF1E2433);
}

const List<_SubjectColorOption> _subjectColorOptions = [
  _SubjectColorOption('Indigo', Color(0xFF6270EA)),
  _SubjectColorOption('Sky', Color(0xFF4D91FF)),
  _SubjectColorOption('Emerald', Color(0xFF38A98D)),
  _SubjectColorOption('Amber', Color(0xFFE4A93B)),
  _SubjectColorOption('Coral', Color(0xFFE56F63)),
  _SubjectColorOption('Rose', Color(0xFFDA6E98)),
  _SubjectColorOption('Plum', Color(0xFF9273E5)),
  _SubjectColorOption('Slate', Color(0xFF61708F)),
  _SubjectColorOption('Mint', Color(0xFF4CC9A6)),
  _SubjectColorOption('Turquoise', Color(0xFF33B7C8)),
  _SubjectColorOption('Ocean', Color(0xFF2F80ED)),
  _SubjectColorOption('Sunflower', Color(0xFFF2C94C)),
  _SubjectColorOption('Tangerine', Color(0xFFF2994A)),
  _SubjectColorOption('Peach', Color(0xFFF58D7D)),
  _SubjectColorOption('Berry', Color(0xFFC65DCE)),
  _SubjectColorOption('Orchid', Color(0xFF8B6BE8)),
];

const List<_SubjectIconOption> _subjectIconOptions = [
  _SubjectIconOption('menu_book_outlined', Icons.menu_book_outlined),
  _SubjectIconOption('school_outlined', Icons.school_outlined),
  _SubjectIconOption('calculate_outlined', Icons.calculate_outlined),
  _SubjectIconOption('science_outlined', Icons.science_outlined),
  _SubjectIconOption('code_outlined', Icons.code_outlined),
  _SubjectIconOption('biotech_outlined', Icons.biotech_outlined),
  _SubjectIconOption('language_outlined', Icons.language_outlined),
  _SubjectIconOption('palette_outlined', Icons.palette_outlined),
  _SubjectIconOption('history_edu_outlined', Icons.history_edu_outlined),
  _SubjectIconOption('terminal_outlined', Icons.terminal_outlined),
];

const List<String> _semesterOptions = [
  'First Semester',
  'Second Semester',
  'Mid-Year',
];

IconData _iconForKey(String key) {
  for (final option in _subjectIconOptions) {
    if (option.key == key) {
      return option.icon;
    }
  }

  return Icons.menu_book_outlined;
}

Color _deterministicClassroomColor(String value) {
  final normalized = value.trim();
  final index = normalized.isEmpty
      ? 0
      : normalized.runes.reduce((current, next) => current + next) %
            _subjectColorOptions.length;
  return _subjectColorOptions[index].color;
}

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SubjectsScreen> createState() => SubjectsScreenState();
}

class SubjectsScreenState extends State<SubjectsScreen> {
  static final CalendarRepository _calendarRepository =
      CalendarRepository.instance;

  StreamSubscription<List<SubjectRecord>>? _subjectSubscription;
  StreamSubscription<List<SubjectAppearance>>? _appearanceSubscription;
  StreamSubscription<List<PlannerItem>>? _plannerSubscription;
  StreamSubscription<Set<String>>? _hiddenClassroomSubjectSubscription;
  StreamSubscription<Set<String>>? _hiddenClassroomEntrySubscription;
  List<SubjectRecord> _manualSubjects = const [];
  List<PlannerItem> _plannerItems = const [];
  Map<String, SubjectAppearance> _subjectAppearances = const {};
  Set<String> _hiddenClassroomSubjectKeys = const {};
  Set<String> _hiddenClassroomEntryIds = const {};
  SubjectCollectionFilter _activeFilter = SubjectCollectionFilter.all;
  CalendarCacheSnapshot? _classroomSnapshot;
  bool _isLoadingSubjects = true;
  bool _isLoadingClassroom = false;
  bool _needsClassroomAuthorization = false;
  bool _isShowingCachedSnapshot = false;
  String? _manualLoadError;
  String? _classroomError;

  @override
  void initState() {
    super.initState();
    _subscribeToSubjects();
    _subscribeToSubjectAppearances();
    _subscribeToPlannerItems();
    _subscribeToHiddenClassroomItems();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialClassroomSnapshot();
    });
  }

  @override
  void dispose() {
    _subjectSubscription?.cancel();
    _appearanceSubscription?.cancel();
    _plannerSubscription?.cancel();
    _hiddenClassroomSubjectSubscription?.cancel();
    _hiddenClassroomEntrySubscription?.cancel();
    super.dispose();
  }

  void openSearchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) => _SubjectSearchSheet(
        manualSubjects: _manualSubjects,
        classroomSubjects: _classroomSubjects,
        onManualSelected: (subject) {
          Navigator.of(context).pop();
          _openManualSubjectDetails(subject);
        },
        onClassroomSelected: (subject) {
          Navigator.of(context).pop();
          _openClassroomSubjectDetails(subject);
        },
      ),
    );
  }

  void openCreateSubjectSheet() {
    _openSubjectEditor();
  }

  void openManualSubjectById(String subjectId) {
    final match = _manualSubjects.where((subject) => subject.id == subjectId);
    if (match.isEmpty) {
      return;
    }
    _openManualSubjectDetails(match.first);
  }

  void openClassroomSubjectByKey(String subjectKey) {
    final normalizedKey = subjectKey.trim();
    if (normalizedKey.isEmpty) {
      return;
    }
    final match = _classroomSubjects.where(
      (subject) => subject.key == normalizedKey,
    );
    if (match.isEmpty) {
      return;
    }
    _openClassroomSubjectDetails(match.first);
  }

  Future<void> reloadClassroomSnapshot() async {
    await _loadInitialClassroomSnapshot();
  }

  List<SubjectRecord> get _activeManualSubjects {
    final subjects =
        _manualSubjects.where((subject) => !subject.isArchived).toList()
          ..sort((a, b) {
            return _manualSubjectDisplayName(a).toLowerCase().compareTo(
              _manualSubjectDisplayName(b).toLowerCase(),
            );
          });

    return subjects;
  }

  List<SubjectRecord> get _archivedSubjects {
    final subjects =
        _manualSubjects.where((subject) => subject.isArchived).toList()..sort(
          (a, b) => (b.archivedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                a.archivedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              ),
        );

    return subjects;
  }

  List<_ClassroomSubjectSummary> get _classroomSubjects {
    return _buildClassroomSubjects(hiddenOnly: false);
  }

  List<_ClassroomSubjectSummary> get _hiddenClassroomSubjects {
    return _buildClassroomSubjects(hiddenOnly: true);
  }

  List<_ClassroomSubjectSummary> _buildClassroomSubjects({
    required bool hiddenOnly,
  }) {
    final entries = _classroomSnapshot?.entries ?? const <CalendarEntry>[];
    if (entries.isEmpty) {
      return const <_ClassroomSubjectSummary>[];
    }

    final grouped = <String, List<CalendarEntry>>{};
    for (final entry in entries) {
      if (_hiddenClassroomEntryIds.contains(entry.id)) {
        continue;
      }
      final key = _classroomSubjectStorageKey(entry);
      final isHidden = _hiddenClassroomSubjectKeys.contains(key);
      if (hiddenOnly != isHidden) {
        continue;
      }
      grouped.putIfAbsent(key, () => <CalendarEntry>[]).add(entry);
    }

    final subjects =
        grouped.entries.map((group) {
          final firstEntry = group.value.first;
          final appearance = _appearanceForEntry(firstEntry);
          final name = firstEntry.subject.trim().isEmpty
              ? 'Classroom'
              : firstEntry.subject;

          return _ClassroomSubjectSummary(
            key: group.key,
            name: name,
            entries: group.value,
            color: appearance == null
                ? _deterministicClassroomColor(name)
                : Color(appearance.colorValue),
            iconKey: appearance?.iconKey ?? 'menu_book_outlined',
          );
        }).toList()..sort((a, b) {
          if (a.pendingCount != b.pendingCount) {
            return b.pendingCount.compareTo(a.pendingCount);
          }

          final aDeadline = a.nextDeadline;
          final bDeadline = b.nextDeadline;
          if (aDeadline != null && bDeadline != null) {
            final compare = aDeadline.compareTo(bDeadline);
            if (compare != 0) {
              return compare;
            }
          } else if (aDeadline != null) {
            return -1;
          } else if (bDeadline != null) {
            return 1;
          }

          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

    return subjects;
  }

  String _manualSubjectDisplayName(SubjectRecord subject) {
    final code = subject.subjectCode.trim();
    if (code.isEmpty) {
      return subject.subjectName;
    }
    return '${code.toUpperCase()} - ${subject.subjectName}';
  }

  List<PlannerItem> _plannerItemsForSubject(SubjectRecord subject) {
    return _plannerItems
        .where(
          (item) =>
              !item.isDeleted &&
              !item.isArchived &&
              item.subjectId == subject.id,
        )
        .toList()
      ..sort((a, b) {
        final aDate = a.scheduledAt;
        final bDate = b.scheduledAt;
        if (aDate != null && bDate != null) {
          return aDate.compareTo(bDate);
        }
        if (aDate != null) return -1;
        if (bDate != null) return 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
  }

  List<SubjectRecord> get _editorSubjects {
    final subjects = _activeManualSubjects;
    subjects.sort(
      (a, b) => _manualSubjectDisplayName(
        a,
      ).toLowerCase().compareTo(_manualSubjectDisplayName(b).toLowerCase()),
    );
    return subjects;
  }

  List<String> get _classroomSubjectNames {
    final names = _classroomSubjects
        .map((subject) => subject.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  List<SubjectRecord> get _plannerSubjectOptions {
    final manualSubjects = _editorSubjects;
    final manualNames = manualSubjects
        .map((subject) => subject.subjectName.trim().toLowerCase())
        .toSet();
    final classroomSubjects = _classroomSubjectNames
        .where((name) => !manualNames.contains(name.trim().toLowerCase()))
        .map(
          (name) => SubjectRecord(
            id: 'classroom::${_normalizedSubjectKey(name)}',
            subjectName: name,
            subjectCode: name,
            iconKey: 'school_outlined',
            colorValue: 0xFFE8F2FF,
          ),
        );

    return [...manualSubjects, ...classroomSubjects];
  }

  PlannerItem _plannerItemFromClassroomEntry(CalendarEntry entry) {
    final subjectName = entry.subject.trim().isEmpty
        ? 'Classroom'
        : entry.subject.trim();
    return PlannerItem(
      id: 'classroom::${entry.id}',
      title: entry.title,
      subjectId: 'classroom::${entry.subjectKey ?? subjectName}',
      subjectName: subjectName,
      sourceItemId: entry.id,
      type: PlannerItemType.task,
      priority: entry.tone == CalendarEntryTone.critical
          ? PlannerItemPriority.high
          : PlannerItemPriority.medium,
      description: entry.description,
      categoryLabel: 'Classroom Task',
      status: entry.isCompleted
          ? PlannerItemStatus.completed
          : PlannerItemStatus.active,
      scheduledAt: entry.scheduledDate,
      hasExplicitTime: entry.scheduledDate != null,
      reminderEnabled: entry.hasReminder,
      reminderLabel: entry.hasReminder
          ? widget.controller.taskReminderDefault
          : null,
      autoCompleteFromSubtasks: false,
    );
  }

  String? _classroomLinkForPlannerItem(PlannerItem item) {
    if (!item.isClassroomBacked) {
      return null;
    }

    final sourceId = item.sourceItemId;
    if (sourceId == null || sourceId.isEmpty) {
      return null;
    }

    final entries = _classroomSnapshot?.entries ?? const <CalendarEntry>[];
    for (final entry in entries) {
      if (entry.id == sourceId) {
        return entry.alternateLink;
      }
    }

    return null;
  }

  SubjectAppearance? _appearanceForEntry(CalendarEntry entry) {
    final key = _appearanceStorageKeyForEntry(entry);
    return key == null ? null : _subjectAppearances[key];
  }

  String _classroomSubjectStorageKey(CalendarEntry entry) {
    final subjectKey = entry.subjectKey?.trim();
    if (subjectKey != null && subjectKey.isNotEmpty) {
      return subjectKey;
    }

    final subjectName = entry.subject.trim();
    return subjectName.isEmpty ? 'classroom' : subjectName;
  }

  String? _appearanceStorageKeyForEntry(CalendarEntry entry) {
    if (entry.subjectSource != CalendarSubjectSource.classroom) {
      return null;
    }

    return '${CalendarSubjectSource.classroom.name}::${_classroomSubjectStorageKey(entry)}';
  }

  @override
  Widget build(BuildContext context) {
    final activeManualSubjects = _activeManualSubjects;
    final archivedSubjects = _archivedSubjects;
    final classroomSubjects = _classroomSubjects;
    final hiddenClassroomSubjects = _hiddenClassroomSubjects;
    final totalOpenClassroomItems = classroomSubjects.fold<int>(
      0,
      (sum, subject) => sum + subject.pendingCount,
    );
    final totalManualPlannerItems = _plannerItems
        .where((item) => !item.isArchived && !item.isDeleted)
        .length;
    final totalTracks = activeManualSubjects.length + classroomSubjects.length;
    final nextDeadline = classroomSubjects
        .map((subject) => subject.nextDeadline)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (best, value) {
          if (best == null || value.isBefore(best)) {
            return value;
          }
          return best;
        });

    return RefreshIndicator(
      onRefresh: () => _refreshClassroomSubjects(promptIfNecessary: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 100, 22, 138),
        children: [
          Text(
            'My Subjects',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 8),
          Text(
            totalTracks == 0
                ? 'Start your term by adding subjects or pulling in your Google Classroom courses.'
                : 'Track $totalTracks subject spaces with $totalManualPlannerItems linked planner items and $totalOpenClassroomItems open Classroom items.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 22),
          _SubjectOverviewCard(
            activeManualCount: activeManualSubjects.length,
            classroomCount: classroomSubjects.length,
            openClassroomItems: totalOpenClassroomItems,
            nextDeadline: nextDeadline,
            isShowingCachedSnapshot: _isShowingCachedSnapshot,
            syncLabel: _formatSyncLabel(_classroomSnapshot?.lastSyncedAt),
          ),
          const SizedBox(height: 18),
          _SearchActivator(onTap: openSearchSheet),
          const SizedBox(height: 18),
          _FilterStrip(
            activeFilter: _activeFilter,
            onChanged: (filter) {
              setState(() {
                _activeFilter = filter;
              });
            },
          ),
          const SizedBox(height: 22),
          if (_manualLoadError != null) ...[
            _InlineNoticeCard(
              icon: Icons.warning_amber_rounded,
              title: 'Manual subjects are unavailable',
              message: _manualLoadError!,
              actionLabel: 'Retry',
              onPressed: _subscribeToSubjects,
            ),
            const SizedBox(height: 18),
          ],
          if (_shouldShowManualSection) ...[
            _SectionHeader(
              title: _activeFilter == SubjectCollectionFilter.archived
                  ? 'Archived Subjects'
                  : 'Manual Subjects',
              actionLabel: _activeFilter == SubjectCollectionFilter.archived
                  ? null
                  : 'Add Subject',
              onActionPressed: _activeFilter == SubjectCollectionFilter.archived
                  ? null
                  : openCreateSubjectSheet,
            ),
            const SizedBox(height: 14),
            if (_isLoadingSubjects)
              const _SectionLoadingCard(label: 'Loading your subject setup...')
            else if (_activeFilter == SubjectCollectionFilter.archived)
              _ArchivedSubjectsList(
                subjects: archivedSubjects,
                classroomSubjects: hiddenClassroomSubjects,
                onTapSubject: _openManualSubjectDetails,
                onRestoreClassroom: _restoreClassroomSubject,
              )
            else
              _ManualSubjectsGrid(
                subjects: activeManualSubjects,
                onTapSubject: _openManualSubjectDetails,
                onTapAddSubject: openCreateSubjectSheet,
              ),
            const SizedBox(height: 26),
          ],
          if (_shouldShowClassroomSection) ...[
            _SectionHeader(
              title: 'Classroom Subjects',
              actionLabel: _classroomActionLabel,
              onActionPressed: _isLoadingClassroom
                  ? null
                  : () => _refreshClassroomSubjects(promptIfNecessary: true),
            ),
            const SizedBox(height: 14),
            _buildClassroomSection(classroomSubjects),
          ],
        ],
      ),
    );
  }

  bool get _shouldShowManualSection {
    return _activeFilter == SubjectCollectionFilter.all ||
        _activeFilter == SubjectCollectionFilter.manual ||
        _activeFilter == SubjectCollectionFilter.archived;
  }

  bool get _shouldShowClassroomSection {
    return _activeFilter == SubjectCollectionFilter.all ||
        _activeFilter == SubjectCollectionFilter.classroom;
  }

  String? get _classroomActionLabel {
    if (!AuthService.instance.authorizationRequiresUserInteraction() &&
        _classroomSnapshot != null) {
      return 'Refresh';
    }

    if (_classroomSnapshot == null) {
      return 'Connect';
    }

    return 'Sync';
  }

  Widget _buildClassroomSection(
    List<_ClassroomSubjectSummary> classroomSubjects,
  ) {
    if (_isLoadingClassroom) {
      return const _SectionLoadingCard(
        label: 'Refreshing Google Classroom subjects...',
      );
    }

    if (_classroomError != null) {
      return _InlineNoticeCard(
        icon: Icons.cloud_off_rounded,
        title: _needsClassroomAuthorization
            ? 'Classroom access required'
            : 'Classroom subjects could not refresh',
        message: _classroomError!,
        actionLabel: _needsClassroomAuthorization ? 'Grant Access' : 'Retry',
        onPressed: () => _refreshClassroomSubjects(
          promptIfNecessary: _needsClassroomAuthorization,
        ),
      );
    }

    if (classroomSubjects.isEmpty) {
      return _InlineNoticeCard(
        icon: Icons.cast_for_education_outlined,
        title: 'No Classroom subjects yet',
        message:
            'Connect Google Classroom to review course work by subject inside StudyFlow.',
        actionLabel: 'Connect Classroom',
        onPressed: () => _refreshClassroomSubjects(promptIfNecessary: true),
      );
    }

    return Column(
      children: classroomSubjects
          .map(
            (subject) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ClassroomSubjectCard(
                subject: subject,
                onTap: () => _openClassroomSubjectDetails(subject),
                onPastDueTap: subject.overdueCount == 0
                    ? null
                    : () => _openClassroomSubjectDetails(
                        subject,
                        showPastDueOnly: true,
                      ),
              ),
            ),
          )
          .toList(),
    );
  }

  void _subscribeToSubjects() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _manualSubjects = const [];
        _isLoadingSubjects = false;
      });
      return;
    }

    _subjectSubscription?.cancel();
    setState(() {
      _isLoadingSubjects = true;
      _manualLoadError = null;
    });

    _subjectSubscription = DatabaseService.instance
        .watchSubjects(user.uid)
        .listen(
          (subjects) {
            if (!mounted) {
              return;
            }

            setState(() {
              _manualSubjects = subjects;
              _isLoadingSubjects = false;
              _manualLoadError = null;
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isLoadingSubjects = false;
              _manualLoadError =
                  'We could not load your saved subjects right now.';
            });
          },
        );
  }

  void _subscribeToPlannerItems() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _plannerItems = const [];
      });
      return;
    }

    _plannerSubscription?.cancel();
    _plannerSubscription = DatabaseService.instance
        .watchPlannerItems(user.uid)
        .listen(
          (items) {
            if (!mounted) return;
            setState(() {
              _plannerItems = items;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _plannerItems = const [];
            });
          },
        );
  }

  void _subscribeToHiddenClassroomItems() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _hiddenClassroomSubjectKeys = const {};
        _hiddenClassroomEntryIds = const {};
      });
      return;
    }

    _hiddenClassroomSubjectSubscription?.cancel();
    _hiddenClassroomEntrySubscription?.cancel();

    _hiddenClassroomSubjectSubscription = DatabaseService.instance
        .watchHiddenClassroomSubjectKeys(user.uid)
        .listen(
          (keys) {
            if (!mounted) return;
            setState(() {
              _hiddenClassroomSubjectKeys = keys;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _hiddenClassroomSubjectKeys = const {};
            });
          },
        );

    _hiddenClassroomEntrySubscription = DatabaseService.instance
        .watchHiddenClassroomEntryIds(user.uid)
        .listen(
          (ids) {
            if (!mounted) return;
            setState(() {
              _hiddenClassroomEntryIds = ids;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _hiddenClassroomEntryIds = const {};
            });
          },
        );
  }

  void _subscribeToSubjectAppearances() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _subjectAppearances = const {};
      });
      return;
    }

    _appearanceSubscription?.cancel();
    _appearanceSubscription = DatabaseService.instance
        .watchSubjectAppearances(user.uid)
        .listen(
          (appearances) {
            if (!mounted) {
              return;
            }

            setState(() {
              _subjectAppearances = {
                for (final appearance in appearances)
                  appearance.storageKey: appearance,
              };
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _subjectAppearances = const {};
            });
          },
        );
  }

  Future<void> _loadInitialClassroomSnapshot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    CalendarCacheSnapshot? snapshot;
    try {
      snapshot = await _calendarRepository.loadBestAvailableSnapshot(user.uid);
    } catch (_) {
      snapshot = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _classroomSnapshot = snapshot;
      _isShowingCachedSnapshot =
          snapshot != null && snapshot.source != CalendarSnapshotSource.live;
    });
  }

  Future<void> _refreshClassroomSubjects({
    required bool promptIfNecessary,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isLoadingClassroom) {
      return;
    }

    setState(() {
      _isLoadingClassroom = true;
      _needsClassroomAuthorization = false;
      _classroomError = null;
    });

    final isOffline = await _isOffline();
    final result = await _calendarRepository.refreshFromClassroom(
      uid: user.uid,
      promptIfNecessary: promptIfNecessary,
      isOffline: isOffline,
    );

    await widget.controller.updateSyncState(
      status: result.syncStatus,
      lastSyncedAt: result.snapshot?.lastSyncedAt,
      clearLastSyncedAt: result.snapshot?.lastSyncedAt == null,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingClassroom = false;
      _needsClassroomAuthorization = result.needsAuthorization;
      _classroomError = result.errorMessage;
      if (result.snapshot != null) {
        _classroomSnapshot = result.snapshot;
      }
      _isShowingCachedSnapshot = result.isUsingCache;
    });

    await NotificationService.instance.refreshForUser(
      uid: user.uid,
      controller: widget.controller,
    );

    if (result.snapshot != null && result.errorMessage == null) {
      _showMessage('Classroom subjects refreshed.');
    }
  }

  Future<bool> _isOffline() async {
    try {
      final isConnected = await DatabaseService.instance
          .observeConnection()
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => true);
      return !isConnected;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openSubjectEditor({SubjectRecord? subject}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: _SubjectEditorSheet(
            initialSubject: subject,
            onSave: (draft) async {
              final record = SubjectRecord(
                id: subject?.id ?? '',
                subjectName: draft.subjectName,
                subjectCode: draft.subjectCode,
                instructorName: draft.instructorName,
                termLabel: draft.termLabel,
                notes: draft.notes,
                iconKey: draft.iconKey,
                colorValue: draft.colorValue,
                status: subject?.status ?? SubjectStatus.active,
                archivedAt: subject?.archivedAt,
                createdAt: subject?.createdAt,
                updatedAt: subject?.updatedAt,
              );

              if (subject == null) {
                await DatabaseService.instance.createSubject(
                  uid: user.uid,
                  subject: record,
                );
                return 'Subject created.';
              }

              await DatabaseService.instance.updateSubject(
                uid: user.uid,
                subject: record,
              );
              return 'Subject updated.';
            },
          ),
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    _showMessage(result);
  }

  Future<void> _openManualSubjectDetails(SubjectRecord subject) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        return _ManualSubjectDetailsSheet(
          subject: subject,
          plannerItems: _plannerItemsForSubject(subject),
          onEdit: () {
            Navigator.of(context).pop();
            _openSubjectEditor(subject: subject);
          },
          onArchive: () async {
            Navigator.of(context).pop();
            await _toggleSubjectArchive(subject);
          },
          onRestore: () async {
            Navigator.of(context).pop();
            await _restoreSubject(subject);
          },
          onHideTask: (item) async {
            await _hidePlannerItem(item);
          },
          onOpenItem: (item) async {
            await _openManualPlannerItemDetails(item);
          },
        );
      },
    );
  }

  Future<void> _openManualPlannerItemDetails(PlannerItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) => _ManualPlannerItemDetailsSheet(
        item: item,
        classroomLink: _classroomLinkForPlannerItem(item),
        onEdit: () {
          Navigator.of(context).pop();
          _openPlannerEditor(item: item);
        },
        onOpenInClassroom: () =>
            _launchClassroomLink(_classroomLinkForPlannerItem(item)),
      ),
    );
  }

  Future<void> _openClassroomSubjectDetails(
    _ClassroomSubjectSummary subject, {
    bool showPastDueOnly = false,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) => _ClassroomSubjectDetailsSheet(
        subject: subject,
        showPastDueOnly: showPastDueOnly,
        onOpenItem: (entry, color, iconKey) async {
          await _openClassroomEntryDetails(
            entry,
            color: color,
            iconKey: iconKey,
          );
        },
        onEditAppearance: () async {
          Navigator.of(context).pop();
          await _openClassroomAppearanceEditor(subject);
        },
        onHideSubject: () async {
          Navigator.of(context).pop();
          await _hideClassroomSubject(subject);
        },
        onHideEntry: (entry) async {
          await _hideClassroomEntry(entry);
        },
      ),
    );
  }

  Future<void> _openClassroomEntryDetails(
    CalendarEntry entry, {
    required Color color,
    required String iconKey,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) => _ClassroomEntryDetailsSheet(
        entry: entry,
        color: color,
        iconKey: iconKey,
        onEdit: () {
          Navigator.of(context).pop();
          _openPlannerEditor(classroomEntry: entry);
        },
        onOpenInClassroom: () => _launchClassroomLink(entry.alternateLink),
      ),
    );
  }

  Future<void> _openClassroomAppearanceEditor(
    _ClassroomSubjectSummary subject,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        return _ClassroomAppearanceEditorSheet(
          subject: subject,
          onSave: (iconKey, colorValue) async {
            await DatabaseService.instance.saveSubjectAppearance(
              uid: user.uid,
              appearance: SubjectAppearance(
                subjectSource: CalendarSubjectSource.classroom,
                subjectKey: subject.key,
                subjectName: subject.name,
                iconKey: iconKey,
                colorValue: colorValue,
                updatedAt: DateTime.now(),
              ),
            );
            return 'Classroom subject style updated.';
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    _showMessage(result);
  }

  Future<void> _toggleSubjectArchive(SubjectRecord subject) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Archive subject?'),
          content: const Text(
            'Archived subjects stay in your records but disappear from the main subject setup list.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await DatabaseService.instance.archiveSubject(
      uid: user.uid,
      subjectId: subject.id,
    );

    if (!mounted) {
      return;
    }

    _showMessage('Subject archived.');
  }

  Future<void> _restoreSubject(SubjectRecord subject) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await DatabaseService.instance.restoreSubject(
      uid: user.uid,
      subjectId: subject.id,
    );

    if (!mounted) {
      return;
    }

    _showMessage('Subject restored.');
  }

  Future<void> _hideClassroomSubject(_ClassroomSubjectSummary subject) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await DatabaseService.instance.hideClassroomSubject(
      uid: user.uid,
      subjectKey: subject.key,
    );
    await NotificationService.instance.refreshForUser(
      uid: user.uid,
      controller: widget.controller,
    );

    if (!mounted) return;
    _showMessage('${subject.name} hidden.');
  }

  Future<void> _restoreClassroomSubject(
    _ClassroomSubjectSummary subject,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await DatabaseService.instance.restoreClassroomSubject(
      uid: user.uid,
      subjectKey: subject.key,
    );
    await NotificationService.instance.refreshForUser(
      uid: user.uid,
      controller: widget.controller,
    );

    if (!mounted) return;
    _showMessage('${subject.name} restored.');
  }

  Future<void> _hideClassroomEntry(CalendarEntry entry) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await DatabaseService.instance.hideClassroomEntry(
      uid: user.uid,
      entryId: entry.id,
    );
    await NotificationService.instance.refreshForUser(
      uid: user.uid,
      controller: widget.controller,
    );

    if (!mounted) return;
    _showMessage('${entry.title} hidden.');
  }

  Future<void> _hidePlannerItem(PlannerItem item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await DatabaseService.instance.deletePlannerItem(
      uid: user.uid,
      itemId: item.id,
    );
    await NotificationService.instance.refreshForUser(
      uid: user.uid,
      controller: widget.controller,
    );

    if (!mounted) return;
    _showMessage('${item.title} hidden.');
  }

  Future<void> _openPlannerEditor({
    PlannerItem? item,
    CalendarEntry? classroomEntry,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final sourceItem = classroomEntry != null
        ? _plannerItemFromClassroomEntry(classroomEntry)
        : item;
    final editorType = sourceItem?.type;

    Future<String> saveDraft(PlannerItemDraft draft) async {
      final isClassroomDraft =
          classroomEntry != null ||
          sourceItem?.id.startsWith('classroom::') == true;
      final isOffline = !await DatabaseService.instance.isConnected();
      final record = PlannerItem(
        id: sourceItem?.id ?? '',
        title: draft.title,
        subjectId: draft.subjectId,
        subjectName: draft.subjectName,
        sourceItemId: sourceItem?.sourceItemId,
        type: draft.type,
        priority: draft.priority,
        description: draft.description,
        notes: draft.notes,
        location: draft.location,
        categoryLabel: draft.categoryLabel,
        status: draft.status,
        scheduledAt: draft.scheduledAt,
        endAt: draft.endAt,
        hasExplicitTime: draft.hasExplicitTime,
        reminderEnabled: draft.reminderEnabled,
        reminderLabel: draft.reminderLabel,
        repeatPattern: draft.repeatPattern,
        repeatUntil: draft.repeatUntil,
        scheduleSlots: draft.scheduleSlots,
        autoCompleteFromSubtasks: draft.autoCompleteFromSubtasks,
        subtasks: draft.subtasks,
        completedAt: sourceItem?.completedAt,
        createdAt: sourceItem?.createdAt,
        updatedAt: sourceItem?.updatedAt,
      );

      if (item == null || isClassroomDraft) {
        await DatabaseService.instance.createPlannerItem(
          uid: user.uid,
          item: record,
        );
        await NotificationService.instance.refreshForUser(
          uid: user.uid,
          controller: widget.controller,
        );
        if (isOffline) {
          return '${draft.typeLabel} saved locally. It will sync when you are online.';
        }
        return isClassroomDraft
            ? 'Classroom task copied into StudyFlow.'
            : '${draft.typeLabel} created.';
      }

      await DatabaseService.instance.updatePlannerItem(
        uid: user.uid,
        item: record,
      );
      await NotificationService.instance.refreshForUser(
        uid: user.uid,
        controller: widget.controller,
      );
      if (isOffline) {
        return '${draft.typeLabel} saved locally. It will sync when you are online.';
      }
      return '${draft.typeLabel} updated.';
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.94,
        child: editorType == PlannerItemType.schedule
            ? SmartScheduleEditorSheet(
                controller: widget.controller,
                initialItem: sourceItem,
                subjects: _editorSubjects,
                classroomSubjectNames: _classroomSubjectNames,
                onSave: saveDraft,
              )
            : PlannerItemEditorSheet(
                controller: widget.controller,
                initialItem: sourceItem,
                initialType: sourceItem?.type,
                initialDate: sourceItem?.scheduledAt,
                subjects: _plannerSubjectOptions,
                onSave: saveDraft,
              ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    _showMessage(result);
  }

  Future<void> _launchClassroomLink(String? url) async {
    if (url == null || url.isEmpty) {
      _showMessage('This classroom item does not have an external link.');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showMessage('The Classroom link is invalid.');
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _showMessage('Could not open Google Classroom.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SubjectOverviewCard extends StatelessWidget {
  const _SubjectOverviewCard({
    required this.activeManualCount,
    required this.classroomCount,
    required this.openClassroomItems,
    required this.nextDeadline,
    required this.isShowingCachedSnapshot,
    required this.syncLabel,
  });

  final int activeManualCount;
  final int classroomCount;
  final int openClassroomItems;
  final DateTime? nextDeadline;
  final bool isShowingCachedSnapshot;
  final String syncLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF18213A), Color(0xFF10192F)]
              : const [Color(0xFFEEF2FF), Color(0xFFF8FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isDark ? const Color(0xFF26304B) : const Color(0xFFDDE4FF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.auto_stories_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Subject Workspace',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextDeadline == null
                          ? 'No active Classroom deadlines are waiting right now.'
                          : '${_deadlineLabel(nextDeadline)} in your imported course work.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricPill(
                label: 'Manual',
                value: '$activeManualCount',
                icon: Icons.edit_note_rounded,
              ),
              _MetricPill(
                label: 'Classroom',
                value: '$classroomCount',
                icon: Icons.cast_for_education_outlined,
              ),
              _MetricPill(
                label: 'Open work',
                value: '$openClassroomItems',
                icon: Icons.assignment_late_outlined,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                isShowingCachedSnapshot
                    ? Icons.history_toggle_off_rounded
                    : Icons.cloud_done_outlined,
                size: 18,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '$label  $value',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _SearchActivator extends StatelessWidget {
  const _SearchActivator({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161F33) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF273147) : const Color(0xFFE9EDF5),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search manual and Classroom subjects',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.activeFilter, required this.onChanged});

  final SubjectCollectionFilter activeFilter;
  final ValueChanged<SubjectCollectionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = [
      (filter: SubjectCollectionFilter.all, label: 'All'),
      (filter: SubjectCollectionFilter.manual, label: 'Manual'),
      (filter: SubjectCollectionFilter.classroom, label: 'Classroom'),
      (filter: SubjectCollectionFilter.archived, label: 'Archived'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _FilterChipButton(
                  label: item.label,
                  isActive: activeFilter == item.filter,
                  onTap: () => onChanged(item.filter),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final activeForeground = colorScheme.brightness == Brightness.dark
        ? colorScheme.onPrimary
        : Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isActive
              ? null
              : isDark
              ? colorScheme.surface.withValues(alpha: 0.94)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isActive
                ? colorScheme.primary.withValues(alpha: 0.18)
                : Theme.of(context).dividerColor.withValues(alpha: 0.52),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 15,
            color: isActive
                ? activeForeground
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onActionPressed,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontSize: 22),
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onActionPressed, child: Text(actionLabel!)),
      ],
    );
  }
}

class _SectionLoadingCard extends StatelessWidget {
  const _SectionLoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _InlineNoticeCard extends StatelessWidget {
  const _InlineNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 18),
          FilledButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _ManualSubjectsGrid extends StatelessWidget {
  const _ManualSubjectsGrid({
    required this.subjects,
    required this.onTapSubject,
    required this.onTapAddSubject,
  });

  final List<SubjectRecord> subjects;
  final ValueChanged<SubjectRecord> onTapSubject;
  final VoidCallback onTapAddSubject;

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return _InlineNoticeCard(
        icon: Icons.auto_stories_outlined,
        title: 'No subjects yet',
        message:
            'Add your courses here so StudyFlow has a clean academic structure for this term.',
        actionLabel: 'Add Subject',
        onPressed: onTapAddSubject,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _AddSubjectCard(onTap: onTapAddSubject),
        ),
        ...subjects.map(
          (subject) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ManualSubjectCard(
              subject: subject,
              onTap: () => onTapSubject(subject),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArchivedSubjectsList extends StatelessWidget {
  const _ArchivedSubjectsList({
    required this.subjects,
    required this.classroomSubjects,
    required this.onTapSubject,
    required this.onRestoreClassroom,
  });

  final List<SubjectRecord> subjects;
  final List<_ClassroomSubjectSummary> classroomSubjects;
  final ValueChanged<SubjectRecord> onTapSubject;
  final ValueChanged<_ClassroomSubjectSummary> onRestoreClassroom;

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty && classroomSubjects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No archived subjects',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Archived subjects stay available for reference and can be restored whenever you need them again.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ...subjects.map(
          (subject) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ArchivedSubjectTile(
              subject: subject,
              onTap: () => onTapSubject(subject),
            ),
          ),
        ),
        ...classroomSubjects.map(
          (subject) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ArchivedClassroomSubjectTile(
              subject: subject,
              onRestore: onRestoreClassroom,
            ),
          ),
        ),
      ],
    );
  }
}

class _AddSubjectCard extends StatelessWidget {
  const _AddSubjectCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.32),
              width: 1.4,
            ),
            color: Theme.of(context).cardColor.withValues(alpha: 0.78),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Add Subject',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create a custom course with its own icon and color identity.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualSubjectCard extends StatelessWidget {
  const _ManualSubjectCard({required this.subject, required this.onTap});

  final SubjectRecord subject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(subject.colorValue);
    final foreground = _foregroundFor(color);
    final code = subject.subjectCode.trim();
    final title = code.isEmpty
        ? subject.subjectName
        : '${code.toUpperCase()} - ${subject.subjectName}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surfaceTint(color, 0.12),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _surfaceTint(color, 0.28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      _iconForKey(subject.iconKey),
                      color: foreground,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subject.instructorName?.isNotEmpty == true
                              ? subject.instructorName!
                              : subject.termLabel ??
                                    'Ready for tasks and exams',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _TypeChip(
                    label: 'MANUAL',
                    backgroundColor: Colors.white.withValues(alpha: 0.72),
                    foregroundColor: color,
                  ),
                  if (subject.termLabel?.isNotEmpty == true)
                    _TypeChip(
                      label: subject.termLabel!.toUpperCase(),
                      backgroundColor: _surfaceTint(color, 0.16),
                      foregroundColor: color,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualPlannerItemCard extends StatelessWidget {
  const _ManualPlannerItemCard({
    required this.item,
    required this.color,
    required this.onTap,
    required this.onHide,
  });

  final PlannerItem item;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final foreground = _foregroundFor(color);
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _surfaceTint(color, 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _plannerItemIcon(item.type),
                      color: foreground,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subjectPlannerItemDateLabel(item),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: onHide, child: const Text('Hide')),
                ],
              ),
              if ((item.description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  item.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TypeChip(
                    label: item.typeLabel.toUpperCase(),
                    backgroundColor: _surfaceTint(color, 0.16),
                    foregroundColor: color,
                  ),
                  _TypeChip(
                    label: item.priorityLabel.toUpperCase(),
                    backgroundColor: colorScheme.primary.withValues(
                      alpha: 0.12,
                    ),
                    foregroundColor: colorScheme.primary,
                  ),
                  if ((item.reminderLabel ?? '').trim().isNotEmpty &&
                      item.reminderEnabled)
                    _TypeChip(
                      label: item.reminderLabel!.toUpperCase(),
                      backgroundColor: colorScheme.secondary.withValues(
                        alpha: 0.14,
                      ),
                      foregroundColor: colorScheme.secondary,
                    ),
                ],
              ),
              if ((item.location ?? '').trim().isNotEmpty ||
                  (item.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                if ((item.location ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Location: ${item.location!}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                if ((item.notes ?? '').trim().isNotEmpty)
                  Text(
                    item.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

IconData _plannerItemIcon(PlannerItemType type) {
  switch (type) {
    case PlannerItemType.task:
      return Icons.assignment_outlined;
    case PlannerItemType.project:
      return Icons.auto_awesome_motion_outlined;
    case PlannerItemType.exam:
      return Icons.quiz_outlined;
    case PlannerItemType.schedule:
      return Icons.schedule_rounded;
  }
}

String _subjectPlannerItemDateLabel(PlannerItem item) {
  final scheduledAt = item.scheduledAt;
  if (scheduledAt == null) {
    return 'No due date';
  }

  if (item.type == PlannerItemType.schedule) {
    if (item.endAt != null) {
      return '${_formatLongDate(scheduledAt)} | ${_formatShortTime(scheduledAt)} - ${_formatShortTime(item.endAt!)}';
    }
    return '${_formatLongDate(scheduledAt)} | ${_formatShortTime(scheduledAt)}';
  }

  if (item.hasExplicitTime) {
    return '${_formatLongDate(scheduledAt)} | ${_formatShortTime(scheduledAt)}';
  }

  return _formatLongDate(scheduledAt);
}

class _ArchivedClassroomSubjectTile extends StatelessWidget {
  const _ArchivedClassroomSubjectTile({
    required this.subject,
    required this.onRestore,
  });

  final _ClassroomSubjectSummary subject;
  final ValueChanged<_ClassroomSubjectSummary> onRestore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      tileColor: Theme.of(context).cardColor.withValues(alpha: 0.94),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: subject.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          _iconForKey(subject.iconKey),
          color: _foregroundFor(subject.color),
        ),
      ),
      title: Text(subject.name),
      subtitle: Text('Classroom subject hidden in StudyFlow'),
      trailing: TextButton(
        onPressed: () => onRestore(subject),
        child: const Text('Restore'),
      ),
    );
  }
}

class _ArchivedSubjectTile extends StatelessWidget {
  const _ArchivedSubjectTile({required this.subject, required this.onTap});

  final SubjectRecord subject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(subject.colorValue);

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      tileColor: Theme.of(context).cardColor.withValues(alpha: 0.94),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(_iconForKey(subject.iconKey), color: _foregroundFor(color)),
      ),
      title: Text(subject.subjectName),
      subtitle: Text(
        [
          if (subject.subjectCode.trim().isNotEmpty)
            subject.subjectCode.toUpperCase(),
          'Archived ${_formatMonthDay(subject.archivedAt ?? DateTime.now())}',
        ].join(' - '),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ClassroomSubjectCard extends StatelessWidget {
  const _ClassroomSubjectCard({
    required this.subject,
    required this.onTap,
    this.onPastDueTap,
  });

  final _ClassroomSubjectSummary subject;
  final VoidCallback onTap;
  final VoidCallback? onPastDueTap;

  @override
  Widget build(BuildContext context) {
    final background = _surfaceTint(subject.color, 0.12);
    final border = _surfaceTint(subject.color, 0.28);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: subject.color,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      _iconForKey(subject.iconKey),
                      color: _foregroundFor(subject.color),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${subject.pendingCount} pending • ${subject.completedCount} completed',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _TypeChip(
                    label: 'CLASSROOM',
                    backgroundColor: Colors.white.withValues(alpha: 0.72),
                    foregroundColor: subject.color,
                  ),
                  if (subject.overdueCount == 0)
                    _TypeChip(
                      label: _deadlineLabel(subject.nextDeadline).toUpperCase(),
                      backgroundColor: _surfaceTint(subject.color, 0.16),
                      foregroundColor: subject.color,
                    ),
                  _TypeChip(
                    label: '${subject.totalCount} ITEMS',
                    backgroundColor: _surfaceTint(subject.color, 0.16),
                    foregroundColor: subject.color,
                  ),
                  if (subject.overdueCount > 0)
                    _ActionChip(
                      label: '${subject.overdueCount} PAST DUE',
                      backgroundColor: const Color(0xFFFFE1E4),
                      foregroundColor: const Color(0xFFC24A5B),
                      onTap: onPastDueTap ?? onTap,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 14,
                color: foregroundColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallToggleChip extends StatelessWidget {
  const _SmallToggleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ManualSubjectDetailsSheet extends StatelessWidget {
  const _ManualSubjectDetailsSheet({
    required this.subject,
    required this.plannerItems,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    required this.onHideTask,
    required this.onOpenItem,
  });

  final SubjectRecord subject;
  final List<PlannerItem> plannerItems;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final ValueChanged<PlannerItem> onHideTask;
  final ValueChanged<PlannerItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final color = Color(subject.colorValue);
    final foreground = _foregroundFor(color);
    final code = subject.subjectCode.trim();
    final title = code.isEmpty
        ? subject.subjectName
        : '${code.toUpperCase()} - ${subject.subjectName}';

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          28 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModalSheetHeader(title: title, subtitle: subject.instructorName),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(_iconForKey(subject.iconKey), color: foreground),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (subject.instructorName?.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Text(
                          subject.instructorName!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: subject.isArchived ? null : onEdit,
                  tooltip: 'Edit subject',
                  icon: Container(
                    width: 42,
                    height: 42,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: SvgPicture.asset(
                      'assets/icons/edit.svg',
                      width: 24,
                      height: 24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TypeChip(
                  label: subject.isArchived ? 'ARCHIVED' : 'ACTIVE',
                  backgroundColor: _surfaceTint(color, 0.16),
                  foregroundColor: color,
                ),
                if (subject.termLabel?.isNotEmpty == true)
                  _TypeChip(
                    label: subject.termLabel!.toUpperCase(),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 22),
            _DetailStatCard(
              icon: Icons.link_rounded,
              title: 'Subject setup complete',
              subtitle:
                  'This subject is ready for future task, exam, and planner linking.',
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: 'Instructor',
              value: subject.instructorName ?? 'Not specified',
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Term',
              value: subject.termLabel ?? 'Not specified',
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Notes',
              value: subject.notes ?? 'No notes added for this subject yet.',
            ),
            const SizedBox(height: 22),
            Text(
              'Linked planner items',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (plannerItems.isEmpty)
              _SimpleEmptyCard(
                title: 'No linked tasks',
                subtitle:
                    'Tasks, exams, and projects assigned to this subject will appear here.',
              )
            else
              ...plannerItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ManualPlannerItemCard(
                    item: item,
                    color: color,
                    onTap: () => onOpenItem(item),
                    onHide: () => onHideTask(item),
                  ),
                ),
              ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: subject.isArchived ? null : onEdit,
                child: const Text('Edit Subject'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: subject.isArchived ? onRestore : onArchive,
                child: Text(
                  subject.isArchived ? 'Restore Subject' : 'Archive Subject',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStatCard extends StatelessWidget {
  const _DetailStatCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}

class _ManualPlannerItemDetailsSheet extends StatelessWidget {
  const _ManualPlannerItemDetailsSheet({
    required this.item,
    required this.classroomLink,
    required this.onEdit,
    required this.onOpenInClassroom,
  });

  final PlannerItem item;
  final String? classroomLink;
  final VoidCallback onEdit;
  final VoidCallback onOpenInClassroom;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          28 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModalSheetHeader(title: item.title, subtitle: item.typeLabel),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _plannerItemIcon(item.type),
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.typeLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InfoRow(
              label: 'Status',
              value: item.isCompleted ? 'Completed' : 'Active',
            ),
            _InfoRow(label: 'Priority', value: item.priorityLabel),
            _InfoRow(
              label: item.type == PlannerItemType.schedule ? 'Starts' : 'Due',
              value: item.scheduledAt == null
                  ? 'No due date'
                  : _subjectPlannerItemDateLabel(item),
            ),
            if (item.endAt != null && item.type != PlannerItemType.schedule)
              _InfoRow(
                label: 'Ends',
                value:
                    '${_formatLongDate(item.endAt!)} | ${_formatShortTime(item.endAt!)}',
              ),
            if ((item.location ?? '').trim().isNotEmpty)
              _InfoRow(label: 'Location', value: item.location!),
            _InfoRow(
              label: 'Reminder',
              value: item.reminderEnabled
                  ? (item.reminderLabel ?? 'Enabled')
                  : 'Off',
            ),
            if (item.repeatPattern != PlannerRepeatPattern.none)
              _InfoRow(label: 'Repeats', value: item.repeatLabel),
            if ((item.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Description',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                item.description!,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
            if ((item.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Notes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(item.notes!, style: Theme.of(context).textTheme.bodyLarge),
            ],
            const SizedBox(height: 24),
            if (classroomLink != null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onOpenInClassroom,
                  child: const Text('Open in Classroom'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onEdit,
                child: Text(item.isClassroomBacked ? 'Copy to Edit' : 'Edit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ClassroomDetailFilter { all, pastDue }

class _ClassroomSubjectDetailsSheet extends StatefulWidget {
  const _ClassroomSubjectDetailsSheet({
    required this.subject,
    required this.showPastDueOnly,
    required this.onOpenItem,
    required this.onEditAppearance,
    required this.onHideSubject,
    required this.onHideEntry,
  });

  final _ClassroomSubjectSummary subject;
  final bool showPastDueOnly;
  final Future<void> Function(CalendarEntry entry, Color color, String iconKey)
  onOpenItem;
  final Future<void> Function() onEditAppearance;
  final Future<void> Function() onHideSubject;
  final ValueChanged<CalendarEntry> onHideEntry;

  @override
  State<_ClassroomSubjectDetailsSheet> createState() =>
      _ClassroomSubjectDetailsSheetState();
}

class _ClassroomSubjectDetailsSheetState
    extends State<_ClassroomSubjectDetailsSheet> {
  late _ClassroomDetailFilter _activeFilter;

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.showPastDueOnly
        ? _ClassroomDetailFilter.pastDue
        : _ClassroomDetailFilter.all;
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final pendingEntries =
        widget.subject.entries.where((entry) => !entry.isCompleted).toList()
          ..sort((a, b) {
            final aDate = a.scheduledDate;
            final bDate = b.scheduledDate;
            if (aDate != null && bDate != null) {
              return aDate.compareTo(bDate);
            }
            if (aDate != null) {
              return -1;
            }
            if (bDate != null) {
              return 1;
            }
            return a.title.compareTo(b.title);
          });
    final filteredPendingEntries = _activeFilter == _ClassroomDetailFilter.all
        ? pendingEntries
        : pendingEntries.where(_isPastDue).toList();
    final completedEntries = widget.subject.entries
        .where((entry) => entry.isCompleted)
        .toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          28 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModalSheetHeader(
              title: widget.subject.name,
              subtitle:
                  '${subject.pendingCount} pending • ${subject.completedCount} completed',
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: widget.subject.color,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    _iconForKey(widget.subject.iconKey),
                    color: _foregroundFor(widget.subject.color),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.subject.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${subject.pendingCount} pending • ${subject.completedCount} completed',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => widget.onEditAppearance(),
                  tooltip: 'Edit classroom subject style',
                  icon: Container(
                    width: 42,
                    height: 42,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: SvgPicture.asset(
                      'assets/icons/edit.svg',
                      width: 24,
                      height: 24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TypeChip(
                  label: 'CLASSROOM',
                  backgroundColor: _surfaceTint(subject.color, 0.16),
                  foregroundColor: subject.color,
                ),
                if (subject.overdueCount == 0)
                  _TypeChip(
                    label: _deadlineLabel(subject.nextDeadline).toUpperCase(),
                    backgroundColor: Colors.white.withValues(alpha: 0.72),
                    foregroundColor: subject.color,
                  ),
                if (subject.overdueCount > 0)
                  _ActionChip(
                    label: '${subject.overdueCount} PAST DUE',
                    backgroundColor: const Color(0xFFFFE1E4),
                    foregroundColor: const Color(0xFFC24A5B),
                    onTap: () {
                      setState(() {
                        _activeFilter = _ClassroomDetailFilter.pastDue;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 22),
            _DetailStatCard(
              icon: Icons.sync_rounded,
              title: 'Imported from Google Classroom',
              subtitle:
                  'Review course work here and open the original Classroom record when needed.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => widget.onHideSubject(),
                child: const Text('Hide Classroom Subject'),
              ),
            ),
            const SizedBox(height: 22),
            Text('Pending work', style: Theme.of(context).textTheme.titleLarge),
            if (subject.overdueCount > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _SmallToggleChip(
                    label: 'All',
                    isSelected: _activeFilter == _ClassroomDetailFilter.all,
                    onTap: () {
                      setState(() {
                        _activeFilter = _ClassroomDetailFilter.all;
                      });
                    },
                  ),
                  const SizedBox(width: 10),
                  _SmallToggleChip(
                    label: 'Past Due',
                    isSelected: _activeFilter == _ClassroomDetailFilter.pastDue,
                    onTap: () {
                      setState(() {
                        _activeFilter = _ClassroomDetailFilter.pastDue;
                      });
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (filteredPendingEntries.isEmpty)
              _SimpleEmptyCard(
                title: _activeFilter == _ClassroomDetailFilter.pastDue
                    ? 'No past due work'
                    : 'All caught up',
                subtitle: _activeFilter == _ClassroomDetailFilter.pastDue
                    ? 'Everything remaining for this Classroom subject is still on time.'
                    : 'This Classroom subject does not have any pending work right now.',
              )
            else
              ...filteredPendingEntries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ClassroomEntryTile(
                    entry: entry,
                    color: subject.color,
                    iconKey: subject.iconKey,
                    onOpen: () => widget.onOpenItem(
                      entry,
                      subject.color,
                      subject.iconKey,
                    ),
                    onHide: () => widget.onHideEntry(entry),
                  ),
                ),
              ),
            if (completedEntries.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                'Completed in Classroom',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...completedEntries
                  .take(4)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ClassroomEntryTile(
                        entry: entry,
                        color: subject.color,
                        iconKey: subject.iconKey,
                        onOpen: () => widget.onOpenItem(
                          entry,
                          subject.color,
                          subject.iconKey,
                        ),
                        onHide: () => widget.onHideEntry(entry),
                        compact: true,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isPastDue(CalendarEntry entry) {
    final date = entry.scheduledDate;
    return date != null && date.isBefore(DateTime.now());
  }
}

class _ClassroomEntryTile extends StatelessWidget {
  const _ClassroomEntryTile({
    required this.entry,
    required this.color,
    required this.iconKey,
    required this.onOpen,
    required this.onHide,
    this.compact = false,
  });

  final CalendarEntry entry;
  final Color color;
  final String iconKey;
  final VoidCallback onOpen;
  final VoidCallback onHide;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final background = compact
        ? _surfaceTint(color, 0.08)
        : _surfaceTint(color, 0.12);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: EdgeInsets.all(compact ? 14 : 16),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 42 : 48,
                height: compact ? 42 : 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_iconForKey(iconKey), color: _foregroundFor(color)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.description,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.scheduledDate == null
                          ? 'No due date'
                          : '${_formatLongDate(entry.scheduledDate!)} | ${_formatShortTime(entry.scheduledDate!)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onHide, child: const Text('Hide')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassroomEntryDetailsSheet extends StatelessWidget {
  const _ClassroomEntryDetailsSheet({
    required this.entry,
    required this.color,
    required this.iconKey,
    required this.onEdit,
    required this.onOpenInClassroom,
  });

  final CalendarEntry entry;
  final Color color;
  final String iconKey;
  final VoidCallback onEdit;
  final VoidCallback onOpenInClassroom;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          28 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModalSheetHeader(title: entry.title, subtitle: entry.typeLabel),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _iconForKey(iconKey),
                    color: _foregroundFor(color),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.subject} | ${entry.typeLabel}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InfoRow(
              label: 'Status',
              value: entry.isCompleted ? 'Completed' : 'Active',
            ),
            _InfoRow(
              label: 'Due',
              value: entry.scheduledDate == null
                  ? 'No due date'
                  : '${_formatLongDate(entry.scheduledDate!)} | ${_formatShortTime(entry.scheduledDate!)}',
            ),
            if ((entry.badgeLabel ?? '').trim().isNotEmpty)
              _InfoRow(label: 'Badge', value: entry.badgeLabel!),
            const SizedBox(height: 14),
            Text('Description', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              entry.description.trim().isEmpty
                  ? 'No additional details.'
                  : entry.description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onOpenInClassroom,
                child: const Text('Open in Classroom'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onEdit,
                child: const Text('Copy to Edit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleEmptyCard extends StatelessWidget {
  const _SimpleEmptyCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _SubjectSearchSheet extends StatefulWidget {
  const _SubjectSearchSheet({
    required this.manualSubjects,
    required this.classroomSubjects,
    required this.onManualSelected,
    required this.onClassroomSelected,
  });

  final List<SubjectRecord> manualSubjects;
  final List<_ClassroomSubjectSummary> classroomSubjects;
  final ValueChanged<SubjectRecord> onManualSelected;
  final ValueChanged<_ClassroomSubjectSummary> onClassroomSelected;

  @override
  State<_SubjectSearchSheet> createState() => _SubjectSearchSheetState();
}

class _SubjectSearchSheetState extends State<_SubjectSearchSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();

    final manualMatches = widget.manualSubjects.where((subject) {
      if (query.isEmpty) {
        return true;
      }

      return [
        subject.subjectName,
        subject.subjectCode,
        subject.instructorName ?? '',
        subject.termLabel ?? '',
        subject.notes ?? '',
        subject.status.name,
        subject.iconKey,
      ].join(' ').toLowerCase().contains(query);
    }).toList();

    final classroomMatches = widget.classroomSubjects.where((subject) {
      if (query.isEmpty) {
        return true;
      }

      return [
        subject.name,
        subject.code,
        subject.iconKey,
        ...subject.entries.map((entry) => entry.title),
        ...subject.entries.map((entry) => entry.description),
        ...subject.entries.map((entry) => entry.typeLabel),
        ...subject.entries.map((entry) => entry.badgeLabel ?? ''),
      ].join(' ').toLowerCase().contains(query);
    }).toList();

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
            title: 'Search Subjects',
            subtitle:
                'Look across manual subjects and imported Classroom courses.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by name, code, or instructor',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF182134)
                  : const Color(0xFFF4F6FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: manualMatches.isEmpty && classroomMatches.isEmpty
                ? Center(
                    child: Text(
                      'No subjects matched "${_controller.text}".',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      if (manualMatches.isNotEmpty) ...[
                        Text(
                          'Manual',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        ...manualMatches.map(
                          (subject) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SubjectSearchTile.manual(
                              subject: subject,
                              onTap: () => widget.onManualSelected(subject),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (classroomMatches.isNotEmpty) ...[
                        Text(
                          'Classroom',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        ...classroomMatches.map(
                          (subject) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SubjectSearchTile.classroom(
                              subject: subject,
                              onTap: () => widget.onClassroomSelected(subject),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SubjectSearchTile extends StatelessWidget {
  const _SubjectSearchTile.manual({
    required SubjectRecord subject,
    required this.onTap,
  }) : _manualSubject = subject,
       _classroomSubject = null;

  const _SubjectSearchTile.classroom({
    required _ClassroomSubjectSummary subject,
    required this.onTap,
  }) : _classroomSubject = subject,
       _manualSubject = null;

  final SubjectRecord? _manualSubject;
  final _ClassroomSubjectSummary? _classroomSubject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final manual = _manualSubject;
    final classroom = _classroomSubject;
    final color = manual != null ? Color(manual.colorValue) : classroom!.color;
    final title = manual?.subjectName ?? classroom!.name;
    final subtitle = manual != null
        ? [
            if (manual.subjectCode.trim().isNotEmpty)
              manual.subjectCode.toUpperCase(),
            manual.instructorName ?? 'Manual subject',
          ].join(' - ')
        : '${classroom!.code} • ${classroom.pendingCount} pending items';
    final icon = manual != null
        ? _iconForKey(manual.iconKey)
        : _iconForKey(classroom!.iconKey);

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      tileColor: _surfaceTint(color, 0.10),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: _foregroundFor(color)),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ClassroomAppearanceEditorSheet extends StatefulWidget {
  const _ClassroomAppearanceEditorSheet({
    required this.subject,
    required this.onSave,
  });

  final _ClassroomSubjectSummary subject;
  final Future<String> Function(String iconKey, int colorValue) onSave;

  @override
  State<_ClassroomAppearanceEditorSheet> createState() =>
      _ClassroomAppearanceEditorSheetState();
}

class _ClassroomAppearanceEditorSheetState
    extends State<_ClassroomAppearanceEditorSheet> {
  late String _selectedIconKey;
  late int _selectedColorValue;
  bool _isSaving = false;
  bool _allowClose = false;

  @override
  void initState() {
    super.initState();
    _selectedIconKey = widget.subject.iconKey;
    _selectedColorValue = widget.subject.color.toARGB32();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          setState(() {
            _allowClose = true;
          });
          Navigator.of(context).pop();
        }
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit Classroom Subject',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _allowClose = true;
                        });
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subject.name,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                Text('Icon', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _subjectIconOptions
                      .map(
                        (option) => _IconChoice(
                          option: option,
                          isSelected: option.key == _selectedIconKey,
                          color: Color(_selectedColorValue),
                          onTap: () {
                            setState(() {
                              _selectedIconKey = option.key;
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 22),
                Text('Color', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _subjectColorOptions
                      .map(
                        (option) => _ColorChoice(
                          option: option,
                          isSelected:
                              option.color.toARGB32() == _selectedColorValue,
                          onTap: () {
                            setState(() {
                              _selectedColorValue = option.color.toARGB32();
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _submit,
                    child: Text(_isSaving ? 'Saving...' : 'Save Style'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _isSaving = true;
    });

    final result = await widget.onSave(_selectedIconKey, _selectedColorValue);
    if (!mounted) {
      return;
    }

    setState(() {
      _allowClose = true;
    });
    Navigator.of(context).pop(result);
  }
}

class _SubjectEditorSheet extends StatefulWidget {
  const _SubjectEditorSheet({
    required this.initialSubject,
    required this.onSave,
  });

  final SubjectRecord? initialSubject;
  final Future<String> Function(_SubjectDraft draft) onSave;

  @override
  State<_SubjectEditorSheet> createState() => _SubjectEditorSheetState();
}

class _SubjectEditorSheetState extends State<_SubjectEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _subjectNameController;
  late final TextEditingController _subjectCodeController;
  late final TextEditingController _instructorController;
  late final TextEditingController _notesController;
  String? _selectedTermLabel;
  late String _selectedIconKey;
  late int _selectedColorValue;
  String? _formError;
  String? _codeConflictMessage;
  bool _isSaving = false;
  bool _allowClose = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSubject;
    _subjectNameController = TextEditingController(
      text: initial?.subjectName ?? '',
    );
    _subjectCodeController = TextEditingController(
      text: initial?.subjectCode ?? '',
    );
    _instructorController = TextEditingController(
      text: initial?.instructorName ?? '',
    );
    _selectedTermLabel = _semesterOptions.contains(initial?.termLabel)
        ? initial?.termLabel
        : null;
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _selectedIconKey = initial?.iconKey ?? _subjectIconOptions.first.key;
    _selectedColorValue =
        initial?.colorValue ?? _subjectColorOptions.first.color.toARGB32();
  }

  @override
  void dispose() {
    _subjectNameController.dispose();
    _subjectCodeController.dispose();
    _instructorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.initialSubject == null
        ? 'Add Subject'
        : 'Edit Subject';

    return PopScope<void>(
      canPop: _allowClose || !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }

        final navigator = Navigator.of(context);
        final shouldClose = await _confirmDiscardIfNeeded();
        if (!shouldClose || !mounted) {
          return;
        }

        setState(() {
          _allowClose = true;
        });
        navigator.pop();
      },
      child: SafeArea(
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
                  ModalSheetHeader(
                    title: title,
                    subtitle:
                        'Set the subject identity first, then customize the icon and color for fast recognition.',
                    onBack: _handleClosePressed,
                  ),
                  const SizedBox(height: 20),
                  _EditorField(
                    controller: _subjectNameController,
                    label: 'Subject name',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter the subject name.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _EditorField(
                    controller: _subjectCodeController,
                    label: 'Subject code (optional)',
                    validator: (value) {
                      return _codeConflictMessage;
                    },
                  ),
                  const SizedBox(height: 14),
                  _EditorField(
                    controller: _instructorController,
                    label: 'Instructor name',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTermLabel,
                    decoration: _editorDecoration(context, 'Semester'),
                    items: _semesterOptions
                        .map(
                          (semester) => DropdownMenuItem<String>(
                            value: semester,
                            child: Text(semester),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTermLabel = value;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  _EditorField(
                    controller: _notesController,
                    label: 'Study notes',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Choose an icon',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _subjectIconOptions
                        .map(
                          (option) => _IconChoice(
                            option: option,
                            isSelected: option.key == _selectedIconKey,
                            color: Color(_selectedColorValue),
                            onTap: () {
                              setState(() {
                                _selectedIconKey = option.key;
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Choose a color',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _subjectColorOptions
                        .map(
                          (option) => _ColorChoice(
                            option: option,
                            isSelected:
                                option.color.toARGB32() == _selectedColorValue,
                            onTap: () {
                              setState(() {
                                _selectedColorValue = option.color.toARGB32();
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _formError!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _submit,
                      child: Text(_isSaving ? 'Saving...' : 'Save Subject'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleClosePressed() async {
    final navigator = Navigator.of(context);
    final shouldClose = await _confirmDiscardIfNeeded();
    if (shouldClose && mounted) {
      setState(() {
        _allowClose = true;
      });
      navigator.pop();
    }
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_isDirty) {
      return true;
    }

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your subject edits have not been saved yet.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    return shouldDiscard == true;
  }

  bool get _isDirty {
    final initial = widget.initialSubject;
    return _subjectNameController.text.trim() != (initial?.subjectName ?? '') ||
        _subjectCodeController.text.trim() != (initial?.subjectCode ?? '') ||
        _instructorController.text.trim() != (initial?.instructorName ?? '') ||
        (_selectedTermLabel ?? '') != (initial?.termLabel ?? '') ||
        _notesController.text.trim() != (initial?.notes ?? '') ||
        _selectedIconKey !=
            (initial?.iconKey ?? _subjectIconOptions.first.key) ||
        _selectedColorValue !=
            (initial?.colorValue ??
                _subjectColorOptions.first.color.toARGB32());
  }

  Future<void> _submit() async {
    setState(() {
      _codeConflictMessage = null;
      _formError = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final result = await widget.onSave(
        _SubjectDraft(
          subjectName: _subjectNameController.text.trim(),
          subjectCode: _subjectCodeController.text.trim(),
          instructorName: _nullableTrimmed(_instructorController.text),
          termLabel: _selectedTermLabel,
          notes: _nullableTrimmed(_notesController.text),
          iconKey: _selectedIconKey,
          colorValue: _selectedColorValue,
        ),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(result);
    } on DuplicateSubjectCodeException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _codeConflictMessage =
            'The code ${error.subjectCode.toUpperCase()} is already in use.';
      });
      _formKey.currentState!.validate();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _formError = 'StudyFlow could not save this subject right now.';
      });
    }
  }

  String? _nullableTrimmed(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.controller,
    required this.label,
    this.validator,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      decoration: _editorDecoration(context, label),
    );
  }
}

InputDecoration _editorDecoration(BuildContext context, String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF182134)
        : const Color(0xFFF5F7FC),
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
  );
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.option,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final _SubjectIconOption option;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: isSelected ? color : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? color
                : Theme.of(context).dividerColor.withValues(alpha: 0.75),
            width: 1.4,
          ),
        ),
        child: Icon(
          option.icon,
          color: isSelected
              ? _foregroundFor(color)
              : Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _SubjectColorOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: option.color,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.2,
          ),
          boxShadow: [
            BoxShadow(
              color: option.color.withValues(alpha: 0.34),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check_rounded,
                color: _foregroundFor(option.color),
                size: 20,
              )
            : null,
      ),
    );
  }
}

class _ClassroomSubjectSummary {
  const _ClassroomSubjectSummary({
    required this.key,
    required this.name,
    required this.entries,
    required this.color,
    required this.iconKey,
  });

  final String key;
  final String name;
  final List<CalendarEntry> entries;
  final Color color;
  final String iconKey;

  String get code => _initialsFor(name);

  int get totalCount => entries.length;

  int get pendingCount => entries.where((entry) => !entry.isCompleted).length;

  int get completedCount => entries.where((entry) => entry.isCompleted).length;

  int get overdueCount {
    final now = DateTime.now();
    return entries.where((entry) {
      final date = entry.scheduledDate;
      return !entry.isCompleted && date != null && date.isBefore(now);
    }).length;
  }

  DateTime? get nextDeadline {
    final pending =
        entries
            .where((entry) => !entry.isCompleted && entry.scheduledDate != null)
            .map((entry) => entry.scheduledDate!)
            .toList()
          ..sort();
    return pending.isEmpty ? null : pending.first;
  }
}

class _SubjectDraft {
  const _SubjectDraft({
    required this.subjectName,
    required this.subjectCode,
    required this.iconKey,
    required this.colorValue,
    this.instructorName,
    this.termLabel,
    this.notes,
  });

  final String subjectName;
  final String subjectCode;
  final String iconKey;
  final int colorValue;
  final String? instructorName;
  final String? termLabel;
  final String? notes;
}

class _SubjectColorOption {
  const _SubjectColorOption(this.label, this.color);

  final String label;
  final Color color;
}

class _SubjectIconOption {
  const _SubjectIconOption(this.key, this.icon);

  final String key;
  final IconData icon;
}
