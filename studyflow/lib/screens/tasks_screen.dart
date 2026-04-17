import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../models/calendar_entry.dart';
import '../models/planner_item.dart';
import '../models/subject_record.dart';
import '../services/calendar_repository.dart';
import '../services/classroom_visibility.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../theme/study_flow_theme.dart';
import '../widgets/modal_sheet_header.dart';
import 'planner_item_editor_sheet.dart';
import 'smart_schedule_editor_sheet.dart';

enum TasksCollectionFilter {
  all,
  pending,
  pastDue,
  noDueDate,
  completed,
  highPriority,
  exams,
  schedules,
}

enum TasksSortOption {
  dueDateEarliest,
  dueDateLatest,
  postedNewest,
  postedOldest,
  titleAZ,
  subjectAZ,
  priority,
}

extension _IntCompareExtension on int {
  int ifZero(int fallback) {
    return this == 0 ? fallback : this;
  }
}

String _monthDay(DateTime value) {
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

String _fullDate(DateTime value) {
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

String _timeLabel(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String _dateTimeLabel(DateTime value, {required bool showTime}) {
  if (!showTime) {
    return _fullDate(value);
  }
  return '${_fullDate(value)} at ${_timeLabel(value)}';
}

String _normalizedSubjectKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
}

String _relativeDueLabel(PlannerItem item) {
  final scheduledAt = item.scheduledAt;
  if (scheduledAt == null) {
    return 'No date';
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day);
  final difference = target.difference(today).inDays;

  if (item.type == PlannerItemType.schedule && item.scheduleSlots.isNotEmpty) {
    final count = item.scheduleSlots.length;
    return '$count weekly ${count == 1 ? 'meeting' : 'meetings'}';
  }

  if (item.type == PlannerItemType.schedule &&
      item.repeatPattern != PlannerRepeatPattern.none) {
    return item.repeatLabel;
  }

  if (difference == 0) {
    return item.hasExplicitTime
        ? 'Today, ${_timeLabel(scheduledAt)}'
        : 'Due today';
  }
  if (difference == 1) {
    return item.hasExplicitTime
        ? 'Tomorrow, ${_timeLabel(scheduledAt)}'
        : 'Due tomorrow';
  }
  if (difference < 0 && !item.isCompleted) {
    return 'Past due';
  }

  final base = _monthDay(scheduledAt);
  return item.hasExplicitTime ? '$base, ${_timeLabel(scheduledAt)}' : base;
}

Color _priorityColor(PlannerItemPriority priority, bool isDark) {
  switch (priority) {
    case PlannerItemPriority.high:
      return isDark ? const Color(0xFFE27B90) : const Color(0xFFFFD3DE);
    case PlannerItemPriority.medium:
      return isDark ? const Color(0xFFB983E4) : const Color(0xFFF1DAFF);
    case PlannerItemPriority.low:
      return isDark ? const Color(0xFF9FB2E8) : const Color(0xFFDDE5FF);
    case PlannerItemPriority.optional:
      return isDark ? const Color(0xFF5C6478) : const Color(0xFFE7EAF1);
  }
}

Color _priorityForeground(PlannerItemPriority priority, bool isDark) {
  if (isDark) {
    return Colors.white;
  }

  switch (priority) {
    case PlannerItemPriority.high:
      return const Color(0xFF8A1732);
    case PlannerItemPriority.medium:
      return const Color(0xFF6E3A89);
    case PlannerItemPriority.low:
      return const Color(0xFF3C4E82);
    case PlannerItemPriority.optional:
      return const Color(0xFF586275);
  }
}

Color _typeColor(PlannerItemType type, bool isDark) {
  switch (type) {
    case PlannerItemType.task:
      return isDark ? const Color(0xFF8EA0FF) : const Color(0xFFDDE5FF);
    case PlannerItemType.project:
      return isDark ? const Color(0xFFC9A0FF) : const Color(0xFFF1E1FF);
    case PlannerItemType.exam:
      return isDark ? const Color(0xFFFF9CB1) : const Color(0xFFFFE1E8);
    case PlannerItemType.schedule:
      return isDark ? const Color(0xFF8ACCB6) : const Color(0xFFD9F4EA);
  }
}

Color _typeForeground(PlannerItemType type, bool isDark) {
  if (isDark) {
    return Colors.white;
  }

  switch (type) {
    case PlannerItemType.task:
      return const Color(0xFF4058A9);
    case PlannerItemType.project:
      return const Color(0xFF7A4AB2);
    case PlannerItemType.exam:
      return const Color(0xFF9A2944);
    case PlannerItemType.schedule:
      return const Color(0xFF1E705A);
  }
}

IconData _typeIcon(PlannerItemType type) {
  switch (type) {
    case PlannerItemType.task:
      return Icons.description_outlined;
    case PlannerItemType.project:
      return Icons.auto_awesome_motion_outlined;
    case PlannerItemType.exam:
      return Icons.school_outlined;
    case PlannerItemType.schedule:
      return Icons.schedule_rounded;
  }
}

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<TasksScreen> createState() => TasksScreenState();
}

class TasksScreenState extends State<TasksScreen> {
  StreamSubscription<List<PlannerItem>>? _plannerSubscription;
  StreamSubscription<List<SubjectRecord>>? _subjectSubscription;
  StreamSubscription<Set<String>>? _hiddenClassroomSubjectSubscription;
  StreamSubscription<Set<String>>? _hiddenClassroomEntrySubscription;
  Timer? _plannerInitialLoadTimer;
  Timer? _subjectInitialLoadTimer;
  List<PlannerItem> _items = const [];
  List<CalendarEntry> _classroomEntries = const [];
  List<SubjectRecord> _subjects = const [];
  Set<String> _hiddenClassroomSubjectKeys = const {};
  Set<String> _hiddenClassroomEntryIds = const {};
  final Set<String> _classroomCompletionSyncing = <String>{};
  TasksCollectionFilter _filter = TasksCollectionFilter.all;
  TasksSortOption _sortOption = TasksSortOption.dueDateEarliest;
  bool _isLoadingItems = true;
  bool _isLoadingSubjects = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _subscribeToPlannerItems();
    _subscribeToSubjects();
    _subscribeToHiddenClassroomItems();
    _loadClassroomTasks();
  }

  @override
  void dispose() {
    _plannerInitialLoadTimer?.cancel();
    _subjectInitialLoadTimer?.cancel();
    _plannerSubscription?.cancel();
    _subjectSubscription?.cancel();
    _hiddenClassroomSubjectSubscription?.cancel();
    _hiddenClassroomEntrySubscription?.cancel();
    super.dispose();
  }

  void openCreateMenu({PlannerItemType? initialType, DateTime? initialDate}) {
    if (initialType != null) {
      _openEditor(initialType: initialType, initialDate: initialDate);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        final options = [
          (
            type: PlannerItemType.task,
            title: 'Add Task',
            subtitle: 'Assignments, readings, and study actions.',
          ),
          (
            type: PlannerItemType.exam,
            title: 'Exams & Quizzes',
            subtitle: 'Store quizzes, presentations, and exam schedules.',
          ),
          (
            type: PlannerItemType.schedule,
            title: 'Smart Schedule',
            subtitle: 'Create repeating class blocks and study schedules.',
          ),
        ];

        return SafeArea(
          child: SingleChildScrollView(
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
                  title: 'Create planner item',
                  subtitle:
                      'Everything created here is tied to a subject and will also feed Calendar and Home.',
                ),
                const SizedBox(height: 16),
                ...options.map(
                  (option) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: _typeColor(
                        option.type,
                        Theme.of(context).brightness == Brightness.dark,
                      ),
                      child: Icon(
                        _typeIcon(option.type),
                        color: _typeForeground(
                          option.type,
                          Theme.of(context).brightness == Brightness.dark,
                        ),
                      ),
                    ),
                    title: Text(option.title),
                    subtitle: Text(option.subtitle),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).pop();
                      _openEditor(initialType: option.type);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void openSearchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) => _TaskSearchSheet(
        items: _visibleItems,
        subjectsById: _subjectsById,
        onSelected: (item) {
          Navigator.of(context).pop();
          _openDetails(item);
        },
      ),
    );
  }

  void openItemDetails(PlannerItem item) {
    _openDetails(item);
  }

  Future<void> reloadClassroomSnapshot() async {
    await _loadClassroomTasks();
  }

  List<SubjectRecord> get _activeSubjects {
    return _subjects.where((subject) => !subject.isArchived).toList()..sort(
      (a, b) =>
          a.subjectCode.toLowerCase().compareTo(b.subjectCode.toLowerCase()),
    );
  }

  List<SubjectRecord> get _plannerSubjectOptions {
    final manualSubjects = _activeSubjects;
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

  Map<String, SubjectRecord> get _subjectsById {
    return {for (final subject in _subjects) subject.id: subject};
  }

  List<String> get _classroomSubjectNames {
    final names = _visibleClassroomEntries
        .map((entry) => entry.subject.trim())
        .where((subject) => subject.isNotEmpty)
        .toSet()
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  List<PlannerItem> get _visibleItems {
    return _buildVisibleItems(_allDisplayItems);
  }

  List<PlannerItem> _buildVisibleItems(List<PlannerItem> allItems) {
    final filtered = allItems.where((item) {
      switch (_filter) {
        case TasksCollectionFilter.all:
          return !item.isArchived && item.type != PlannerItemType.schedule;
        case TasksCollectionFilter.pending:
          return !item.isArchived &&
              !item.isCompleted &&
              item.type != PlannerItemType.schedule;
        case TasksCollectionFilter.pastDue:
          return !item.isArchived && _isPastDue(item);
        case TasksCollectionFilter.noDueDate:
          return !item.isArchived &&
              !item.isCompleted &&
              item.canBeCompleted &&
              item.scheduledAt == null;
        case TasksCollectionFilter.completed:
          return !item.isArchived && item.isCompleted;
        case TasksCollectionFilter.highPriority:
          return !item.isArchived &&
              !item.isCompleted &&
              item.effectivePriority == PlannerItemPriority.high;
        case TasksCollectionFilter.exams:
          return !item.isArchived && item.type == PlannerItemType.exam;
        case TasksCollectionFilter.schedules:
          return !item.isArchived && item.type == PlannerItemType.schedule;
      }
    }).toList();

    filtered.sort(_comparePlannerItems);

    return filtered;
  }

  List<PlannerItem> get _allDisplayItems {
    final hiddenPlannerSubjectIds = hiddenClassroomPlannerSubjectIds(
      _classroomEntries,
      _hiddenClassroomSubjectKeys,
    );
    final importedSourceIds = _items
        .map((item) => item.sourceItemId)
        .whereType<String>()
        .toSet();
    final visiblePlannerItems = _items.where(
      (item) => !isPlannerItemHiddenByClassroom(
        item,
        hiddenEntryIds: _hiddenClassroomEntryIds,
        hiddenPlannerSubjectIds: hiddenPlannerSubjectIds,
      ),
    );
    final classroomItems = _visibleClassroomEntries
        .where((entry) => !importedSourceIds.contains(entry.id))
        .map(_plannerItemFromClassroomEntry);
    return [...visiblePlannerItems, ...classroomItems];
  }

  List<CalendarEntry> get _visibleClassroomEntries {
    return _classroomEntries
        .where(
          (entry) => !isHiddenClassroomEntry(
            entry,
            hiddenSubjectKeys: _hiddenClassroomSubjectKeys,
            hiddenEntryIds: _hiddenClassroomEntryIds,
          ),
        )
        .toList();
  }

  int _comparePlannerItems(PlannerItem a, PlannerItem b) {
    switch (_sortOption) {
      case TasksSortOption.dueDateEarliest:
        return _compareByDueDateEarliest(a, b);
      case TasksSortOption.dueDateLatest:
        return _compareByDueDateLatest(a, b);
      case TasksSortOption.postedNewest:
        return _compareNullableDateDescending(
          _postedAt(a),
          _postedAt(b),
        ).ifZero(_compareTitle(a, b));
      case TasksSortOption.postedOldest:
        return _compareNullableDate(
          _postedAt(a),
          _postedAt(b),
          nullsLast: true,
        ).ifZero(_compareTitle(a, b));
      case TasksSortOption.titleAZ:
        return _compareTitle(a, b);
      case TasksSortOption.subjectAZ:
        return _compareSubject(a, b).ifZero(_compareByDueDateEarliest(a, b));
      case TasksSortOption.priority:
        return _comparePriority(a, b).ifZero(_compareByDueDateEarliest(a, b));
    }
  }

  int _compareByDueDateEarliest(PlannerItem a, PlannerItem b) {
    return _compareNullableDate(
      a.scheduledAt,
      b.scheduledAt,
      nullsLast: true,
    ).ifZero(_compareTitle(a, b));
  }

  int _compareByDueDateLatest(PlannerItem a, PlannerItem b) {
    return _compareNullableDateDescending(
      a.scheduledAt,
      b.scheduledAt,
    ).ifZero(_compareTitle(a, b));
  }

  int _comparePriority(PlannerItem a, PlannerItem b) {
    const rank = {
      PlannerItemPriority.high: 0,
      PlannerItemPriority.medium: 1,
      PlannerItemPriority.low: 2,
      PlannerItemPriority.optional: 3,
    };
    return rank[a.effectivePriority]!.compareTo(rank[b.effectivePriority]!);
  }

  int _compareSubject(PlannerItem a, PlannerItem b) {
    return _subjectSortLabel(a).compareTo(_subjectSortLabel(b));
  }

  int _compareTitle(PlannerItem a, PlannerItem b) {
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  int _compareNullableDate(
    DateTime? a,
    DateTime? b, {
    required bool nullsLast,
  }) {
    if (a != null && b != null) {
      return a.compareTo(b);
    }
    if (a != null) return nullsLast ? -1 : 1;
    if (b != null) return nullsLast ? 1 : -1;
    return 0;
  }

  int _compareNullableDateDescending(DateTime? a, DateTime? b) {
    if (a != null && b != null) {
      return b.compareTo(a);
    }
    if (a != null) return -1;
    if (b != null) return 1;
    return 0;
  }

  String _subjectSortLabel(PlannerItem item) {
    final subject = _subjectsById[item.subjectId];
    final label =
        (subject?.subjectCode ?? item.subjectCode ?? item.subjectName ?? '')
            .trim()
            .toLowerCase();
    return label.isEmpty ? 'zzzzzz' : label;
  }

  DateTime? _postedAt(PlannerItem item) {
    return item.createdAt ?? item.updatedAt;
  }

  bool _isPastDue(PlannerItem item) {
    final scheduledAt = item.scheduledAt;
    if (item.isCompleted || scheduledAt == null || !item.canBeCompleted) {
      return false;
    }

    final now = DateTime.now();
    if (item.hasExplicitTime) {
      return scheduledAt.isBefore(now);
    }

    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
    );
    return dueDate.isBefore(today);
  }

  String _sortLabel(TasksSortOption option) {
    switch (option) {
      case TasksSortOption.dueDateEarliest:
        return 'Due Date';
      case TasksSortOption.dueDateLatest:
        return 'Latest Due';
      case TasksSortOption.postedNewest:
        return 'Newest Posted';
      case TasksSortOption.postedOldest:
        return 'Oldest Posted';
      case TasksSortOption.titleAZ:
        return 'Title A-Z';
      case TasksSortOption.subjectAZ:
        return 'Subject A-Z';
      case TasksSortOption.priority:
        return 'Priority';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allDisplayItems = _allDisplayItems;
    final visibleItems = _buildVisibleItems(allDisplayItems);
    final openWorkCount = allDisplayItems
        .where(
          (item) =>
              !item.isCompleted &&
              !item.isArchived &&
              item.type != PlannerItemType.schedule,
        )
        .length;
    final remainingCount = visibleItems
        .where((item) => !item.isCompleted && !item.isArchived)
        .length;
    final examCount = allDisplayItems
        .where((item) => item.type == PlannerItemType.exam && !item.isArchived)
        .length;
    final scheduleCount = allDisplayItems
        .where(
          (item) => item.type == PlannerItemType.schedule && !item.isArchived,
        )
        .length;
    final remainingLabel = _filter == TasksCollectionFilter.schedules
        ? 'schedules'
        : 'items';

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 102, 22, 140),
      children: [
        Text(
          'All Tasks',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontSize: 30),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage Exams & Quizzes, editable Classroom tasks, subtasks, and repeating study schedules in one workspace.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        _SearchBarActivator(onTap: openSearchSheet),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _MiniStatCard(
                label: 'Open Work',
                value: openWorkCount.toString(),
                accent: const Color(0xFF5466E6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStatCard(
                label: 'Exams & Quizzes',
                value: examCount.toString(),
                accent: const Color(0xFFE66C89),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStatCard(
                label: 'Schedules',
                value: scheduleCount.toString(),
                accent: const Color(0xFF3BAE90),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _TaskFilterStrip(
          activeFilter: _filter,
          onChanged: (filter) {
            setState(() {
              _filter = filter;
            });
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              '$remainingCount $remainingLabel remaining',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            PopupMenuButton<TasksSortOption>(
              initialValue: _sortOption,
              onSelected: (value) {
                setState(() {
                  _sortOption = value;
                });
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: TasksSortOption.dueDateEarliest,
                  child: Text('Due date: earliest first'),
                ),
                PopupMenuItem(
                  value: TasksSortOption.dueDateLatest,
                  child: Text('Due date: latest first'),
                ),
                PopupMenuItem(
                  value: TasksSortOption.priority,
                  child: Text('Priority'),
                ),
                PopupMenuItem(
                  value: TasksSortOption.postedNewest,
                  child: Text('Posted: newest first'),
                ),
                PopupMenuItem(
                  value: TasksSortOption.postedOldest,
                  child: Text('Posted: oldest first'),
                ),
                PopupMenuItem(
                  value: TasksSortOption.titleAZ,
                  child: Text('Title: A-Z'),
                ),
                PopupMenuItem(
                  value: TasksSortOption.subjectAZ,
                  child: Text('Subject: A-Z'),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_vert_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _sortLabel(_sortOption),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_isLoadingItems || _isLoadingSubjects)
          const _LoadingCard(label: 'Loading your planner workspace...')
        else if (_loadError != null)
          _InlinePlannerErrorCard(
            message: _loadError!,
            onRetry: () {
              _subscribeToPlannerItems();
              _subscribeToSubjects();
              _loadClassroomTasks();
            },
          )
        else if (visibleItems.isEmpty)
          _EmptyTasksCard(
            filter: _filter,
            onCreatePressed: () => openCreateMenu(),
          )
        else
          ...visibleItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _PlannerItemCard(
                item: item,
                subject: _subjectsById[item.subjectId],
                onTap: () => _openDetails(item),
                onToggleComplete: item.canBeCompleted && !item.isClassroomBacked
                    ? () => _toggleItemCompletion(item)
                    : null,
                isDark: isDark,
              ),
            ),
          ),
      ],
    );
  }

  void _subscribeToPlannerItems() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _isLoadingItems = false;
        _loadError = 'Sign in again to load your planner items.';
      });
      return;
    }

    _plannerInitialLoadTimer?.cancel();
    _plannerSubscription?.cancel();
    setState(() {
      _isLoadingItems = true;
      _loadError = null;
    });

    _plannerInitialLoadTimer = Timer(const Duration(seconds: 6), () {
      unawaited(_loadPlannerItemsFallback(uid));
    });

    _plannerSubscription = DatabaseService.instance
        .watchPlannerItems(uid)
        .listen(
          (items) {
            if (!mounted) {
              return;
            }
            _plannerInitialLoadTimer?.cancel();
            setState(() {
              _items = items;
              _isLoadingItems = false;
            });
            unawaited(_reschedulePlannerNotifications());
            _syncClassroomTurnedInItems();
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            _plannerInitialLoadTimer?.cancel();
            setState(() {
              _loadError = 'StudyFlow could not load your saved planner items.';
              _isLoadingItems = false;
            });
          },
        );
  }

  void _subscribeToSubjects() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _isLoadingSubjects = false;
        _loadError ??= 'Sign in again to load your subjects.';
      });
      return;
    }

    _subjectInitialLoadTimer?.cancel();
    _subjectSubscription?.cancel();
    setState(() {
      _isLoadingSubjects = true;
    });

    _subjectInitialLoadTimer = Timer(const Duration(seconds: 6), () {
      unawaited(_loadSubjectsFallback(uid));
    });

    _subjectSubscription = DatabaseService.instance
        .watchSubjects(uid)
        .listen(
          (subjects) {
            if (!mounted) {
              return;
            }
            _subjectInitialLoadTimer?.cancel();
            setState(() {
              _subjects = subjects;
              _isLoadingSubjects = false;
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            _subjectInitialLoadTimer?.cancel();
            setState(() {
              _isLoadingSubjects = false;
              _loadError ??=
                  'Your subjects could not be loaded, so item linkage is incomplete.';
            });
          },
        );
  }

  void _subscribeToHiddenClassroomItems() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _hiddenClassroomSubjectKeys = const {};
        _hiddenClassroomEntryIds = const {};
      });
      return;
    }

    _hiddenClassroomSubjectSubscription?.cancel();
    _hiddenClassroomEntrySubscription?.cancel();

    _hiddenClassroomSubjectSubscription = DatabaseService.instance
        .watchHiddenClassroomSubjectKeys(uid)
        .listen(
          (keys) {
            if (!mounted) {
              return;
            }
            setState(() {
              _hiddenClassroomSubjectKeys = keys;
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _hiddenClassroomSubjectKeys = const {};
            });
          },
        );

    _hiddenClassroomEntrySubscription = DatabaseService.instance
        .watchHiddenClassroomEntryIds(uid)
        .listen(
          (ids) {
            if (!mounted) {
              return;
            }
            setState(() {
              _hiddenClassroomEntryIds = ids;
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _hiddenClassroomEntryIds = const {};
            });
          },
        );
  }

  Future<void> _loadPlannerItemsFallback(String uid) async {
    if (!mounted || !_isLoadingItems) {
      return;
    }

    try {
      final items = await DatabaseService.instance
          .getPlannerItems(uid)
          .timeout(const Duration(seconds: 5));
      if (!mounted || !_isLoadingItems) {
        return;
      }
      setState(() {
        _items = items;
        _isLoadingItems = false;
      });
      unawaited(_reschedulePlannerNotifications());
      _syncClassroomTurnedInItems();
    } catch (_) {
      if (!mounted || !_isLoadingItems) {
        return;
      }
      setState(() {
        _isLoadingItems = false;
        _loadError = 'StudyFlow could not load your saved planner items.';
      });
    }
  }

  Future<void> _loadSubjectsFallback(String uid) async {
    if (!mounted || !_isLoadingSubjects) {
      return;
    }

    try {
      final subjects = await DatabaseService.instance
          .getSubjects(uid)
          .timeout(const Duration(seconds: 5));
      if (!mounted || !_isLoadingSubjects) {
        return;
      }
      setState(() {
        _subjects = subjects;
        _isLoadingSubjects = false;
      });
    } catch (_) {
      if (!mounted || !_isLoadingSubjects) {
        return;
      }
      setState(() {
        _isLoadingSubjects = false;
        _loadError ??=
            'Your subjects could not be loaded, so item linkage is incomplete.';
      });
    }
  }

  Future<void> _loadClassroomTasks() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final snapshot = await CalendarRepository.instance
        .loadBestAvailableSnapshot(uid);
    if (!mounted || snapshot == null) {
      return;
    }

    setState(() {
      _classroomEntries = snapshot.entries;
    });
    unawaited(_reschedulePlannerNotifications());
    _syncClassroomTurnedInItems();
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

  Future<void> _syncClassroomTurnedInItems() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _items.isEmpty || _classroomEntries.isEmpty) {
      return;
    }

    final completedClassroomIds = _classroomEntries
        .where((entry) => entry.isCompleted)
        .map((entry) => entry.id)
        .toSet();
    if (completedClassroomIds.isEmpty) {
      return;
    }

    for (final item in _items) {
      final sourceId = item.sourceItemId;
      if (sourceId == null ||
          sourceId.isEmpty ||
          !completedClassroomIds.contains(sourceId) ||
          item.isCompleted ||
          !_classroomCompletionSyncing.add(item.id)) {
        continue;
      }

      try {
        await DatabaseService.instance.updatePlannerItem(
          uid: uid,
          item: item.copyWith(
            status: PlannerItemStatus.completed,
            completedAt: DateTime.now(),
            autoCompleteFromSubtasks: false,
          ),
        );
      } finally {
        _classroomCompletionSyncing.remove(item.id);
      }
    }
  }

  Future<void> _openEditor({
    PlannerItem? item,
    PlannerItemType? initialType,
    DateTime? initialDate,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final editorType = item?.type ?? initialType;

    Future<String> saveDraft(PlannerItemDraft draft) async {
      final isClassroomDraft = item?.id.startsWith('classroom::') == true;
      final isOffline = !await DatabaseService.instance.isConnected();
      final record = PlannerItem(
        id: item?.id ?? '',
        title: draft.title,
        subjectId: draft.subjectId,
        subjectName: draft.subjectName,
        sourceItemId: item?.sourceItemId,
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
        completedAt: item?.completedAt,
        createdAt: item?.createdAt,
        updatedAt: item?.updatedAt,
      );

      if (item == null || isClassroomDraft) {
        final saved = await DatabaseService.instance.createPlannerItem(
          uid: user.uid,
          item: record,
        );
        await _reschedulePlannerNotifications(
          overrideItems: _mergePlannerItems(_allDisplayItems, saved),
        );
        if (isOffline) {
          return '${draft.typeLabel} saved locally. It will sync when you are online.';
        }
        return isClassroomDraft
            ? 'Classroom task copied into StudyFlow.'
            : '${draft.typeLabel} created.';
      }

      final saved = await DatabaseService.instance.updatePlannerItem(
        uid: user.uid,
        item: record,
      );
      await _reschedulePlannerNotifications(
        overrideItems: _mergePlannerItems(_allDisplayItems, saved),
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
                initialItem: item,
                subjects: _activeSubjects,
                classroomSubjectNames: _classroomSubjectNames,
                onSave: saveDraft,
              )
            : PlannerItemEditorSheet(
                controller: widget.controller,
                initialItem: item,
                initialType: initialType,
                initialDate: initialDate,
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

  Future<void> _openDetails(PlannerItem item) async {
    final updated = await showModalBottomSheet<PlannerItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) => _PlannerItemDetailsSheet(
        initialItem: item,
        subject: _subjectsById[item.subjectId],
        classroomLink: _classroomLinkForItem(item),
        onOpenInClassroom: _launchClassroomLink,
        onSave: _persistItem,
        onDelete: () async {
          await _deleteItem(item);
        },
        onEditRequested: () {
          Navigator.of(context).pop();
          _openEditor(item: item);
        },
      ),
    );

    if (!mounted || updated == null) {
      return;
    }

    _showMessage('${updated.typeLabel} updated.');
  }

  Future<PlannerItem> _persistItem(PlannerItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('User not found.');
    }
    final saved = await DatabaseService.instance.updatePlannerItem(
      uid: uid,
      item: item,
    );
    await _reschedulePlannerNotifications(
      overrideItems: _mergePlannerItems(_allDisplayItems, saved),
    );
    return saved;
  }

  Future<void> _toggleItemCompletion(PlannerItem item) async {
    final nextStatus = item.isCompleted
        ? PlannerItemStatus.active
        : PlannerItemStatus.completed;
    final updated = item.copyWith(
      status: nextStatus,
      completedAt: nextStatus == PlannerItemStatus.completed
          ? DateTime.now()
          : null,
      clearCompletedAt: nextStatus != PlannerItemStatus.completed,
    );
    await _persistItem(updated);

    if (!mounted) {
      return;
    }
    _showMessage(
      item.isCompleted ? '${item.title} restored.' : '${item.title} completed.',
    );
  }

  Future<void> _deleteItem(PlannerItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    await DatabaseService.instance.deletePlannerItem(uid: uid, itemId: item.id);
    await _reschedulePlannerNotifications(
      overrideItems: _allDisplayItems.where((current) => current.id != item.id),
    );

    if (!mounted) {
      return;
    }
    _showMessage('${item.title} deleted.');
  }

  String? _classroomLinkForItem(PlannerItem item) {
    if (!item.isClassroomBacked) {
      return null;
    }

    final sourceId = item.sourceItemId;
    if (sourceId == null || sourceId.isEmpty) {
      return null;
    }

    for (final entry in _classroomEntries) {
      if (entry.id == sourceId) {
        return entry.alternateLink;
      }
    }

    return null;
  }

  Future<void> _launchClassroomLink(String? url) async {
    if (url == null || url.trim().isEmpty) {
      _showMessage('This Classroom item does not have an openable link.');
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

  Future<void> _reschedulePlannerNotifications({
    Iterable<PlannerItem>? overrideItems,
  }) async {
    try {
      await NotificationService.instance.schedulePlannerItems(
        items: overrideItems ?? _allDisplayItems,
        controller: widget.controller,
      );
    } catch (error) {
      debugPrint('StudyFlow could not refresh planner notifications: $error');
    }
  }

  List<PlannerItem> _mergePlannerItems(
    Iterable<PlannerItem> currentItems,
    PlannerItem saved,
  ) {
    final merged = <PlannerItem>[];
    var replaced = false;

    for (final item in currentItems) {
      final isSameRecord = item.id == saved.id;
      final isCopiedClassroomRecord =
          saved.sourceItemId != null &&
          saved.sourceItemId == item.sourceItemId &&
          item.id.startsWith('classroom::');

      if (isSameRecord || isCopiedClassroomRecord) {
        if (!replaced) {
          merged.add(saved);
          replaced = true;
        }
        continue;
      }
      merged.add(item);
    }

    if (!replaced) {
      merged.add(saved);
    }

    return merged;
  }
}

class _SearchBarActivator extends StatelessWidget {
  const _SearchBarActivator({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF182134) : const Color(0xFFF2F4F8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded),
            const SizedBox(width: 12),
            Text(
              'Search your assignments...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontSize: 24, color: accent),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TaskFilterStrip extends StatelessWidget {
  const _TaskFilterStrip({required this.activeFilter, required this.onChanged});

  final TasksCollectionFilter activeFilter;
  final ValueChanged<TasksCollectionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = const [
      (filter: TasksCollectionFilter.all, label: 'All'),
      (filter: TasksCollectionFilter.pending, label: 'Pending'),
      (filter: TasksCollectionFilter.pastDue, label: 'Past Due'),
      (filter: TasksCollectionFilter.noDueDate, label: 'No Due Date'),
      (filter: TasksCollectionFilter.completed, label: 'Completed'),
      (filter: TasksCollectionFilter.highPriority, label: 'High'),
      (filter: TasksCollectionFilter.exams, label: 'Exams'),
      (filter: TasksCollectionFilter.schedules, label: 'Schedules'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _TaskFilterChip(
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

class _TaskFilterChip extends StatelessWidget {
  const _TaskFilterChip({
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
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive
                ? colorScheme.primary.withValues(alpha: 0.18)
                : Theme.of(context).dividerColor.withValues(alpha: 0.52),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isActive
                ? activeForeground
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PlannerItemCard extends StatelessWidget {
  const _PlannerItemCard({
    required this.item,
    required this.subject,
    required this.onTap,
    required this.onToggleComplete,
    required this.isDark,
  });

  final PlannerItem item;
  final SubjectRecord? subject;
  final VoidCallback onTap;
  final VoidCallback? onToggleComplete;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(item.type, isDark);
    final typeForeground = _typeForeground(item.type, isDark);
    final priorityColor = _priorityColor(item.effectivePriority, isDark);
    final priorityForeground = _priorityForeground(
      item.effectivePriority,
      isDark,
    );
    final isCompleted = item.isCompleted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isCompleted
                  ? StudyFlowTheme.success.withValues(alpha: 0.24)
                  : Theme.of(context).dividerColor.withValues(alpha: 0.7),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _typeIcon(item.type),
                      color: typeForeground,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subject?.subjectCode ??
                              item.subjectName ??
                              'Linked subject',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (onToggleComplete != null) const SizedBox(width: 12),
                  if (onToggleComplete != null)
                    Checkbox(
                      value: isCompleted,
                      onChanged: (_) => onToggleComplete?.call(),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                ],
              ),
              if ((item.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  item.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ItemPill(
                    label: item.typeLabel.toUpperCase(),
                    background: typeColor,
                    foreground: typeForeground,
                  ),
                  _ItemPill(
                    label: item.priorityLabel.toUpperCase(),
                    background: priorityColor,
                    foreground: priorityForeground,
                  ),
                  if (item.hasSubtasks)
                    _ItemPill(
                      label:
                          '${item.subtasks.where((subtask) => subtask.isCompleted).length}/${item.subtasks.length} SUBTASKS',
                      background: const Color(0xFFE9EDF4),
                      foreground: const Color(0xFF5B6578),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _relativeDueLabel(item),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (item.reminderEnabled)
                    Text(
                      item.reminderLabel ?? 'Reminder',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: StudyFlowTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
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

class _ItemPill extends StatelessWidget {
  const _ItemPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _InlinePlannerErrorCard extends StatelessWidget {
  const _InlinePlannerErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Planner unavailable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyTasksCard extends StatelessWidget {
  const _EmptyTasksCard({required this.filter, required this.onCreatePressed});

  final TasksCollectionFilter filter;
  final VoidCallback onCreatePressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      TasksCollectionFilter.all => 'No planner items yet',
      TasksCollectionFilter.pending => 'No pending work',
      TasksCollectionFilter.pastDue => 'No past-due work',
      TasksCollectionFilter.noDueDate => 'No undated work',
      TasksCollectionFilter.completed => 'No completed items yet',
      TasksCollectionFilter.highPriority => 'No high-priority items',
      TasksCollectionFilter.exams => 'No Exams & Quizzes yet',
      TasksCollectionFilter.schedules => 'No smart schedules yet',
    };

    final body = switch (filter) {
      TasksCollectionFilter.all =>
        'Start with a task, project, exam, or smart schedule.',
      TasksCollectionFilter.pending =>
        'Your open work list is clear for this filter.',
      TasksCollectionFilter.pastDue =>
        'Nothing is overdue right now. Keep your schedule current.',
      TasksCollectionFilter.noDueDate =>
        'Tasks without due dates will appear here so you can schedule them later.',
      TasksCollectionFilter.completed =>
        'Completed items will appear here after you finish them.',
      TasksCollectionFilter.highPriority =>
        'Nothing urgent is marked as high priority right now.',
      TasksCollectionFilter.exams =>
        'Add quizzes, exams, or presentations so they stay visible across the app.',
      TasksCollectionFilter.schedules =>
        'Create a repeating class or review schedule to keep Home and Calendar informed.',
    };

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onCreatePressed,
            child: const Text('Create Item'),
          ),
        ],
      ),
    );
  }
}

class _TaskSearchSheet extends StatefulWidget {
  const _TaskSearchSheet({
    required this.items,
    required this.subjectsById,
    required this.onSelected,
  });

  final List<PlannerItem> items;
  final Map<String, SubjectRecord> subjectsById;
  final ValueChanged<PlannerItem> onSelected;

  @override
  State<_TaskSearchSheet> createState() => _TaskSearchSheetState();
}

class _TaskSearchSheetState extends State<_TaskSearchSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final results = widget.items.where((item) {
      if (query.isEmpty) {
        return true;
      }
      final subject = widget.subjectsById[item.subjectId];
      return [
        item.title,
        item.description,
        item.notes,
        item.location,
        item.categoryLabel,
        item.typeLabel,
        item.priorityLabel,
        item.repeatLabel,
        item.status.name,
        ...item.subtasks.map((subtask) => subtask.title),
        ...item.scheduleSlots.map(
          (slot) =>
              '${slot.weekdayLabel} ${slot.timeRangeLabel} ${slot.label ?? ''}',
        ),
        subject?.subjectName,
        subject?.subjectCode,
      ].whereType<String>().join(' ').toLowerCase().contains(query);
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
            title: 'Search Tasks',
            subtitle:
                'Search across tasks, projects, exams, and schedules tied to your subjects.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search titles, subjects, notes, or categories',
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
            child: results.isEmpty
                ? Center(
                    child: Text(
                      'No planner items matched "${_controller.text}".',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = results[index];
                      final subject = widget.subjectsById[item.subjectId];
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        tileColor: Theme.of(
                          context,
                        ).cardColor.withValues(alpha: 0.95),
                        leading: CircleAvatar(
                          backgroundColor: _typeColor(item.type, isDark),
                          child: Icon(
                            _typeIcon(item.type),
                            color: _typeForeground(item.type, isDark),
                          ),
                        ),
                        title: Text(item.title),
                        subtitle: Text(
                          '${subject?.subjectCode ?? item.subjectName ?? 'Subject'} • ${item.typeLabel}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => widget.onSelected(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlannerItemDetailsSheet extends StatefulWidget {
  const _PlannerItemDetailsSheet({
    required this.initialItem,
    required this.subject,
    required this.classroomLink,
    required this.onOpenInClassroom,
    required this.onSave,
    required this.onDelete,
    required this.onEditRequested,
  });

  final PlannerItem initialItem;
  final SubjectRecord? subject;
  final String? classroomLink;
  final ValueChanged<String?> onOpenInClassroom;
  final Future<PlannerItem> Function(PlannerItem item) onSave;
  final Future<void> Function() onDelete;
  final VoidCallback onEditRequested;

  @override
  State<_PlannerItemDetailsSheet> createState() =>
      _PlannerItemDetailsSheetState();
}

class _PlannerItemDetailsSheetState extends State<_PlannerItemDetailsSheet> {
  late PlannerItem _item = widget.initialItem;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ModalSheetHeader(
                title: _item.title,
                subtitle:
                    '${widget.subject?.subjectCode ?? _item.subjectName ?? 'Subject'} • ${_item.typeLabel}',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _typeColor(_item.type, isDark),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _typeIcon(_item.type),
                      color: _typeForeground(_item.type, isDark),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _item.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.subject?.subjectCode ?? _item.subjectName ?? 'Subject'} • ${_item.typeLabel}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DetailInfoRow(
                label: 'Status',
                value: _item.isCompleted ? 'Completed' : 'Active',
              ),
              _DetailInfoRow(label: 'Priority', value: _item.priorityLabel),
              _DetailInfoRow(
                label: 'Category',
                value: _item.categoryLabel ?? _item.typeLabel,
              ),
              if (_item.scheduledAt != null)
                _DetailInfoRow(
                  label: _item.type == PlannerItemType.schedule
                      ? 'Starts'
                      : 'Due',
                  value: _dateTimeLabel(
                    _item.scheduledAt!,
                    showTime: _item.hasExplicitTime,
                  ),
                ),
              if (_item.endAt != null)
                _DetailInfoRow(
                  label: 'Ends',
                  value: _dateTimeLabel(_item.endAt!, showTime: true),
                ),
              if (_item.repeatPattern != PlannerRepeatPattern.none)
                _DetailInfoRow(label: 'Repeats', value: _item.repeatLabel),
              if (_item.scheduleSlots.isNotEmpty)
                _DetailInfoRow(
                  label: 'Meetings',
                  value: _item.scheduleSlots
                      .map(
                        (slot) => '${slot.weekdayLabel} ${slot.timeRangeLabel}',
                      )
                      .join(', '),
                ),
              _DetailInfoRow(
                label: 'Reminder',
                value: _item.reminderEnabled
                    ? (_item.reminderLabel ?? 'Enabled')
                    : 'Off',
              ),
              if ((_item.location ?? '').isNotEmpty)
                _DetailInfoRow(label: 'Room/Location', value: _item.location!),
              if ((_item.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  _item.description!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if ((_item.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Notes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  _item.notes!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if (_item.subtasks.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Subtasks',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (_item.autoCompleteFromSubtasks)
                      Text(
                        'Auto-completes parent',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: StudyFlowTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._item.subtasks.map(
                  (subtask) => CheckboxListTile(
                    value: subtask.isCompleted,
                    onChanged: _isSaving
                        ? null
                        : (_) => _toggleSubtask(subtask),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      subtask.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        decoration: subtask.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_item.isClassroomBacked && widget.classroomLink != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _isSaving
                        ? null
                        : () => widget.onOpenInClassroom(widget.classroomLink),
                    child: const Text('Open in Classroom'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : widget.onEditRequested,
                      child: Text(
                        _item.isClassroomBacked ? 'Copy to Edit' : 'Edit',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_item.canBeCompleted && !_item.isClassroomBacked)
                    Expanded(
                      child: FilledButton(
                        onPressed: _isSaving ? null : _toggleCompletion,
                        child: Text(
                          _item.isCompleted ? 'Restore' : 'Mark Complete',
                        ),
                      ),
                    ),
                ],
              ),
              if (!_item.isClassroomBacked) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _isSaving ? null : _confirmDelete,
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSubtask(PlannerSubtask subtask) async {
    setState(() {
      _isSaving = true;
    });

    final updatedSubtasks = _item.subtasks.map((current) {
      if (current.id != subtask.id) {
        return current;
      }
      final nextCompleted = !current.isCompleted;
      return current.copyWith(
        isCompleted: nextCompleted,
        completedAt: nextCompleted ? DateTime.now() : null,
        clearCompletedAt: !nextCompleted,
      );
    }).toList();

    final saved = await widget.onSave(
      _item.copyWith(subtasks: updatedSubtasks),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _item = saved;
      _isSaving = false;
    });
  }

  Future<void> _toggleCompletion() async {
    setState(() {
      _isSaving = true;
    });

    final saved = await widget.onSave(
      _item.copyWith(
        status: _item.isCompleted
            ? PlannerItemStatus.active
            : PlannerItemStatus.completed,
        completedAt: _item.isCompleted ? null : DateTime.now(),
        clearCompletedAt: _item.isCompleted,
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _item = saved;
      _isSaving = false;
    });
  }

  Future<void> _confirmDelete() async {
    final navigator = Navigator.of(context);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete item?'),
          content: Text('Remove "${_item.title}" from your planner?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    final delete = widget.onDelete;
    navigator.pop();
    await delete();
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
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
      ),
    );
  }
}
