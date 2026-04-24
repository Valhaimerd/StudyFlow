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
import '../services/app_settings_service.dart';
import '../services/calendar_repository.dart';
import '../services/classroom_visibility.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/planner_item_mutation_service.dart';
import '../theme/study_flow_theme.dart';
import '../widgets/modal_sheet_header.dart';
import 'planner_item_editor_sheet.dart' show PlannerItemDraft;
import 'smart_schedule_editor_sheet.dart';

class _EntryTone {
  const _EntryTone({
    required this.background,
    required this.accent,
    required this.iconBackground,
    required this.iconColor,
    required this.border,
  });

  final Color background;
  final Color accent;
  final Color iconBackground;
  final Color iconColor;
  final Color border;
}

class _EntryBadgeStyle {
  const _EntryBadgeStyle({
    required this.iconData,
    required this.backgroundColor,
    required this.iconColor,
  });

  final IconData iconData;
  final Color backgroundColor;
  final Color iconColor;
}

IconData _calendarIconForKey(String key) {
  switch (key) {
    case 'school_outlined':
      return Icons.school_outlined;
    case 'calculate_outlined':
      return Icons.calculate_outlined;
    case 'science_outlined':
      return Icons.science_outlined;
    case 'code_outlined':
      return Icons.code_outlined;
    case 'biotech_outlined':
      return Icons.biotech_outlined;
    case 'language_outlined':
      return Icons.language_outlined;
    case 'palette_outlined':
      return Icons.palette_outlined;
    case 'history_edu_outlined':
      return Icons.history_edu_outlined;
    case 'terminal_outlined':
      return Icons.terminal_outlined;
    case 'menu_book_outlined':
    default:
      return Icons.menu_book_outlined;
  }
}

Color _calendarForegroundFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF1E2433);
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _monthLabel(DateTime value) {
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
  return '${months[value.month - 1]} ${value.year}';
}

String _formatSectionDate(DateTime value) {
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
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

String _formatTime(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '${hour.toString().padLeft(2, '0')}:$minute $suffix';
}

String _formatDateTime(DateTime value) {
  return '${_formatLongDate(value)} | ${_formatTime(value)}';
}

String? _timeRange(CalendarEntry entry) {
  if (entry.scheduledDate == null) {
    return null;
  }

  final endDate = entry.endDate;
  if (endDate != null && endDate.isAfter(entry.scheduledDate!)) {
    return '${_formatTime(entry.scheduledDate!)} - ${_formatTime(endDate)}';
  }

  return _formatTime(entry.scheduledDate!);
}

_EntryTone _entryToneFor(CalendarEntry entry, bool isDark) {
  switch (entry.tone) {
    case CalendarEntryTone.critical:
      return _EntryTone(
        background: isDark ? const Color(0xFF2A1821) : const Color(0xFFFFF1F4),
        accent: isDark ? const Color(0xFF4D2635) : const Color(0xFFFFD3DE),
        iconBackground: isDark
            ? const Color(0xFFB34F6C)
            : const Color(0xFFFF6E89),
        iconColor: isDark ? Colors.white : const Color(0xFF7C1230),
        border: isDark ? const Color(0xFF663546) : const Color(0xFFF8B7C5),
      );
    case CalendarEntryTone.project:
      return _EntryTone(
        background: isDark ? const Color(0xFF221C31) : const Color(0xFFF8F0FF),
        accent: isDark ? const Color(0xFF3A3156) : const Color(0xFFEAD7FB),
        iconBackground: isDark
            ? const Color(0xFFB684EE)
            : const Color(0xFFF4CCFF),
        iconColor: isDark ? Colors.white : const Color(0xFF6A427F),
        border: isDark ? const Color(0xFF55456F) : const Color(0xFFEBDCF9),
      );
    case CalendarEntryTone.laboratory:
      return _EntryTone(
        background: isDark ? const Color(0xFF171E31) : const Color(0xFFF2F5FF),
        accent: isDark ? const Color(0xFF2A3554) : const Color(0xFFDDE5FF),
        iconBackground: isDark
            ? const Color(0xFF6679B7)
            : const Color(0xFFDEE2FF),
        iconColor: isDark ? Colors.white : const Color(0xFF49526F),
        border: isDark ? const Color(0xFF31405F) : const Color(0xFFE4E9FA),
      );
    case CalendarEntryTone.openEnded:
      return _EntryTone(
        background: isDark ? const Color(0xFF152130) : const Color(0xFFF2F8FF),
        accent: isDark ? const Color(0xFF26364C) : const Color(0xFFD9EAFE),
        iconBackground: isDark
            ? const Color(0xFF6A8BB4)
            : const Color(0xFFE3F0FF),
        iconColor: isDark ? Colors.white : const Color(0xFF34506E),
        border: isDark ? const Color(0xFF314766) : const Color(0xFFD8E7F8),
      );
    case CalendarEntryTone.completed:
      return _EntryTone(
        background: isDark ? const Color(0xFF182622) : const Color(0xFFF2FBF8),
        accent: isDark ? const Color(0xFF294138) : const Color(0xFFD7F3E8),
        iconBackground: isDark
            ? const Color(0xFF4A987B)
            : const Color(0xFFC7F0E0),
        iconColor: isDark ? Colors.white : const Color(0xFF1F6D55),
        border: isDark ? const Color(0xFF36584C) : const Color(0xFFCAE8DC),
      );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.controller,
    required this.onCreateTask,
    required this.onCreateExam,
    required this.onCreateSubject,
  });

  final AppController controller;
  final ValueChanged<DateTime> onCreateTask;
  final ValueChanged<DateTime> onCreateExam;
  final VoidCallback onCreateSubject;

  @override
  State<CalendarScreen> createState() => CalendarScreenState();
}

class CalendarScreenState extends State<CalendarScreen> {
  static final CalendarRepository _calendarRepository =
      CalendarRepository.instance;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<List<SubjectAppearance>>? _appearanceSubscription;
  StreamSubscription<List<PlannerItem>>? _plannerSubscription;
  StreamSubscription<List<SubjectRecord>>? _subjectSubscription;
  StreamSubscription<Set<String>>? _hiddenClassroomSubjectSubscription;
  StreamSubscription<Set<String>>? _hiddenClassroomEntrySubscription;
  List<CalendarEntry> _entries = const [];
  List<CalendarEntry> _displayEntries = const [];
  List<CalendarEntry> _focusEntries = const [];
  List<CalendarEntry> _todayScheduleEntries = const [];
  List<CalendarEntry> _completedEntries = const [];
  List<PlannerItem> _plannerItems = const [];
  Map<String, SubjectRecord> _manualSubjects = const {};
  Map<String, SubjectAppearance> _subjectAppearances = const {};
  Set<String> _hiddenClassroomSubjectKeys = const {};
  Set<String> _hiddenClassroomEntryIds = const {};
  DateTime? _lastClassroomSyncAt;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _subscribeToSubjectAppearances();
    _subscribeToPlannerItems();
    _subscribeToManualSubjects();
    _subscribeToHiddenClassroomItems();
    _connectionSubscription = _calendarRepository.observeConnection().listen((
      isConnected,
    ) {
      if (!mounted) {
        return;
      }

      if (isConnected == !_isOffline) {
        return;
      }

      final nextOffline = !isConnected;
      setState(() {
        _isOffline = nextOffline;
      });

      if (nextOffline && _entries.isNotEmpty) {
        widget.controller.updateSyncState(
          status: SyncStatus.offlineLocalOnly,
          lastSyncCheckedAt: DateTime.now(),
          lastSyncedAt: _lastClassroomSyncAt,
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapCalendar();
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _appearanceSubscription?.cancel();
    _plannerSubscription?.cancel();
    _subjectSubscription?.cancel();
    _hiddenClassroomSubjectSubscription?.cancel();
    _hiddenClassroomEntrySubscription?.cancel();
    super.dispose();
  }

  void _subscribeToSubjectAppearances() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _appearanceSubscription = DatabaseService.instance
        .watchSubjectAppearances(user.uid)
        .listen((appearances) {
          if (!mounted) {
            return;
          }

          setState(() {
            _subjectAppearances = {
              for (final appearance in appearances)
                appearance.storageKey: appearance,
            };
          });
        });
  }

  SubjectAppearance? _appearanceForEntry(CalendarEntry entry) {
    if (entry.subjectSource != CalendarSubjectSource.classroom) {
      return null;
    }

    final subjectKey = entry.subjectKey?.trim().isNotEmpty == true
        ? entry.subjectKey!.trim()
        : entry.subject.trim().isEmpty
        ? 'classroom'
        : entry.subject.trim();

    return _subjectAppearances['${CalendarSubjectSource.classroom.name}::$subjectKey'];
  }

  void _subscribeToPlannerItems() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _plannerSubscription = DatabaseService.instance
        .watchPlannerItems(user.uid)
        .listen((items) {
          if (!mounted) {
            return;
          }
          setState(() {
            _plannerItems = items;
            _refreshDisplayEntries();
          });
        });
  }

  void _subscribeToManualSubjects() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _subjectSubscription = DatabaseService.instance
        .watchSubjects(user.uid)
        .listen((subjects) {
          if (!mounted) {
            return;
          }
          setState(() {
            _manualSubjects = {
              for (final subject in subjects) subject.id: subject,
            };
            _refreshDisplayEntries();
          });
        });
  }

  void _subscribeToHiddenClassroomItems() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _hiddenClassroomSubjectSubscription = DatabaseService.instance
        .watchHiddenClassroomSubjectKeys(user.uid)
        .listen(
          (keys) {
            if (!mounted) {
              return;
            }
            setState(() {
              _hiddenClassroomSubjectKeys = keys;
              _refreshDisplayEntries();
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _hiddenClassroomSubjectKeys = const {};
              _refreshDisplayEntries();
            });
          },
        );

    _hiddenClassroomEntrySubscription = DatabaseService.instance
        .watchHiddenClassroomEntryIds(user.uid)
        .listen(
          (ids) {
            if (!mounted) {
              return;
            }
            setState(() {
              _hiddenClassroomEntryIds = ids;
              _refreshDisplayEntries();
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _hiddenClassroomEntryIds = const {};
              _refreshDisplayEntries();
            });
          },
        );
  }

  List<SubjectRecord> get _scheduleEditorSubjects {
    return _manualSubjects.values
        .where((subject) => !subject.isArchived)
        .toList()
      ..sort(
        (a, b) =>
            a.subjectCode.toLowerCase().compareTo(b.subjectCode.toLowerCase()),
      );
  }

  List<String> get _classroomSubjectNames {
    final names = _entries
        .where(
          (entry) => !isHiddenClassroomEntry(
            entry,
            hiddenSubjectKeys: _hiddenClassroomSubjectKeys,
            hiddenEntryIds: _hiddenClassroomEntryIds,
          ),
        )
        .map((entry) => entry.subject.trim())
        .where((subject) => subject.isNotEmpty)
        .toSet()
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  _EntryBadgeStyle _badgeStyleForEntry(CalendarEntry entry, _EntryTone tone) {
    final appearance = _appearanceForEntry(entry);
    if (appearance == null) {
      return _EntryBadgeStyle(
        iconData: switch (entry.type) {
          CalendarEntryType.exam => Icons.quiz_outlined,
          CalendarEntryType.project => Icons.assignment_outlined,
          CalendarEntryType.lab => Icons.schedule_rounded,
          CalendarEntryType.task => Icons.menu_book_outlined,
        },
        backgroundColor: tone.iconBackground,
        iconColor: tone.iconColor,
      );
    }

    final backgroundColor = Color(appearance.colorValue);
    return _EntryBadgeStyle(
      iconData: _calendarIconForKey(appearance.iconKey),
      backgroundColor: backgroundColor,
      iconColor: _calendarForegroundFor(backgroundColor),
    );
  }

  CalendarEntry _manualCalendarEntryForOccurrence(
    PlannerItem item,
    DateTime occurrence,
  ) {
    final subject = _manualSubjects[item.subjectId];
    final subjectLabel =
        subject?.subjectCode ??
        item.subjectName ??
        item.subjectCode ??
        'Subject';

    return CalendarEntry(
      id: '${item.id}::$occurrence',
      subject: subjectLabel,
      title: item.title,
      description:
          item.description ??
          item.location ??
          item.categoryLabel ??
          item.typeLabel,
      type: switch (item.type) {
        PlannerItemType.exam => CalendarEntryType.exam,
        PlannerItemType.project => CalendarEntryType.project,
        PlannerItemType.task => CalendarEntryType.task,
        PlannerItemType.schedule => CalendarEntryType.lab,
      },
      tone: item.isCompleted
          ? CalendarEntryTone.completed
          : item.type == PlannerItemType.schedule
          ? CalendarEntryTone.laboratory
          : item.type == PlannerItemType.project
          ? CalendarEntryTone.project
          : item.type == PlannerItemType.exam
          ? CalendarEntryTone.critical
          : item.effectivePriority == PlannerItemPriority.high
          ? CalendarEntryTone.critical
          : CalendarEntryTone.openEnded,
      subjectSource: CalendarSubjectSource.manual,
      subjectKey: subject?.id ?? item.subjectId,
      scheduledDate: occurrence,
      endDate: item.occurrenceEndAt(occurrence),
      plannerType: item.type,
      badgeLabel: item.isCompleted
          ? 'DONE'
          : item.type == PlannerItemType.schedule
          ? 'SCHEDULE'
          : item.priorityLabel.toUpperCase(),
      isCompleted: item.isCompleted,
      hasReminder: item.reminderEnabled,
    );
  }

  void _refreshDisplayEntries() {
    final rangeStart = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final rangeEnd = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month),
      23,
      59,
      59,
    );

    final hiddenPlannerSubjectIds = hiddenClassroomPlannerSubjectIds(
      _entries,
      _hiddenClassroomSubjectKeys,
    );
    final manualEntries = _plannerItems.expand((item) {
      if (isPlannerItemHiddenByClassroom(
        item,
        hiddenEntryIds: _hiddenClassroomEntryIds,
        hiddenPlannerSubjectIds: hiddenPlannerSubjectIds,
      )) {
        return const <CalendarEntry>[];
      }

      final subject = _manualSubjects[item.subjectId];
      if (subject != null && subject.isArchived) {
        return const <CalendarEntry>[];
      }

      final occurrences =
          item.repeatPattern == PlannerRepeatPattern.none &&
              item.scheduleSlots.isEmpty
          ? item.scheduledAt == null
                ? const <DateTime>[]
                : <DateTime>[item.scheduledAt!]
          : item.occurrencesInRange(rangeStart, rangeEnd);

      return occurrences.map(
        (occurrence) => _manualCalendarEntryForOccurrence(item, occurrence),
      );
    }).toList();

    final visibleClassroomEntries = _entries.where(
      (entry) => !isHiddenClassroomEntry(
        entry,
        hiddenSubjectKeys: _hiddenClassroomSubjectKeys,
        hiddenEntryIds: _hiddenClassroomEntryIds,
      ),
    );

    _displayEntries = [...visibleClassroomEntries, ...manualEntries];
    _refreshAgendaEntries();
  }

  void _refreshAgendaEntries() {
    final datedEntries = _displayEntries.where((entry) {
      return entry.scheduledDate != null &&
          _isSameDate(entry.scheduledDate!, _selectedDate);
    }).toList()..sort((a, b) => a.scheduledDate!.compareTo(b.scheduledDate!));

    _focusEntries = datedEntries
        .where((entry) => !entry.isCompleted && !entry.isScheduleEntry)
        .toList();
    _todayScheduleEntries = datedEntries
        .where((entry) => !entry.isCompleted && entry.isScheduleEntry)
        .toList();
    _completedEntries = datedEntries
        .where((entry) => entry.isCompleted)
        .toList();
  }

  void openCreateMenu({PlannerItemType? initialType, DateTime? initialDate}) {
    final effectiveDate = initialDate ?? _selectedDate;
    if (initialType != null) {
      switch (initialType) {
        case PlannerItemType.schedule:
          _openScheduleEditor(initialDate: effectiveDate);
          return;
        case PlannerItemType.task:
          widget.onCreateTask(effectiveDate);
          return;
        case PlannerItemType.exam:
          widget.onCreateExam(effectiveDate);
          return;
        case PlannerItemType.project:
          widget.onCreateTask(effectiveDate);
          return;
      }
    }
    _openScheduleEditor(initialDate: effectiveDate);
  }

  void openSearchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) => _CalendarSearchSheet(
        entries: _displayEntries,
        subjectAppearanceForEntry: _appearanceForEntry,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          _openEntryDetails(entry);
        },
      ),
    );
  }

  void openPlannerItemDetails(PlannerItem item) {
    if (item.type != PlannerItemType.schedule) {
      return;
    }

    final anchorDate = item.scheduledAt;
    if (anchorDate != null) {
      setState(() {
        _selectedDate = DateTime(
          anchorDate.year,
          anchorDate.month,
          anchorDate.day,
        );
        _visibleMonth = DateTime(anchorDate.year, anchorDate.month);
        _refreshDisplayEntries();
      });
    }

    final occurrence = anchorDate ?? _selectedDate;
    _openScheduleDetails(
      item,
      occurrenceEntry: _manualCalendarEntryForOccurrence(item, occurrence),
    );
  }

  void openEntryDetails(CalendarEntry entry) {
    _openEntryDetails(entry);
  }

  Future<String> runManualSync({bool promptIfNecessary = true}) async {
    final result = await _loadClassroomActivities(
      promptIfNecessary: promptIfNecessary,
    );
    if (result == null) {
      return 'Could not start Classroom sync right now.';
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

  @override
  Widget build(BuildContext context) {
    final focusEntries = _focusEntries;
    final todayScheduleEntries = _todayScheduleEntries;
    final completedEntries = _completedEntries;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () => _loadClassroomActivities(promptIfNecessary: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 104, 22, 138),
        children: [
          _MonthHeader(
            label: _monthLabel(_visibleMonth),
            onPrevious: _showPreviousMonth,
            onNext: _showNextMonth,
          ),
          const SizedBox(height: 18),
          _CalendarMonthCard(
            visibleMonth: _visibleMonth,
            selectedDate: _selectedDate,
            entries: _displayEntries,
            onDateSelected: _selectDate,
          ),
          const SizedBox(height: 18),
          _SmartScheduleLaunchCard(
            selectedDate: _selectedDate,
            onTap: () => _openScheduleEditor(initialDate: _selectedDate),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            title: "Today's Focus",
            trailing: _formatSectionDate(_selectedDate),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Column(
              key: ValueKey(
                '${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}',
              ),
              children: [
                if (focusEntries.isEmpty)
                  const _EmptyAgendaCard(
                    title: 'Nothing due on this day',
                    message:
                        'Tasks, quizzes, and exams with a set date will appear here.',
                  )
                else
                  ...focusEntries.map((entry) {
                    final tone = _entryToneFor(entry, isDark);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: _AgendaCard(
                        entry: entry,
                        tone: tone,
                        badgeStyle: _badgeStyleForEntry(entry, tone),
                        timeRange: _timeRange(entry),
                        onTap: () => _openEntryDetails(entry),
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _SectionHeader(
            title: "Today's Schedule",
            trailing: _formatSectionDate(_selectedDate),
          ),
          const SizedBox(height: 14),
          if (todayScheduleEntries.isEmpty)
            const _EmptyAgendaCard(
              title: 'No schedule blocks',
              message:
                  'Smart schedules you create in Calendar will appear here for this day.',
            )
          else
            ...todayScheduleEntries.map((entry) {
              final tone = _entryToneFor(entry, isDark);
              return Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: _AgendaCard(
                  entry: entry,
                  tone: tone,
                  badgeStyle: _badgeStyleForEntry(entry, tone),
                  timeRange: _timeRange(entry),
                  onTap: () => _openEntryDetails(entry),
                ),
              );
            }),
          if (completedEntries.isNotEmpty) ...[
            const SizedBox(height: 6),
            _SectionHeader(
              title: 'Completed',
              trailing: _formatSectionDate(_selectedDate),
            ),
            const SizedBox(height: 14),
            ...completedEntries.map((entry) {
              final tone = _entryToneFor(entry, isDark);
              return Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: _AgendaCard(
                  entry: entry,
                  tone: tone,
                  badgeStyle: _badgeStyleForEntry(entry, tone),
                  timeRange: _timeRange(entry),
                  onTap: () => _openEntryDetails(entry),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  void _showPreviousMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
      _syncSelectionToVisibleMonth();
      _refreshDisplayEntries();
    });
  }

  void _showNextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
      _syncSelectionToVisibleMonth();
      _refreshDisplayEntries();
    });
  }

  void _syncSelectionToVisibleMonth() {
    final daysInMonth = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final targetDay = _selectedDate.day.clamp(1, daysInMonth).toInt();
    _selectedDate = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      targetDay,
    );
  }

  void _selectDate(DateTime value) {
    setState(() {
      _selectedDate = value;
      _visibleMonth = DateTime(value.year, value.month);
      _refreshDisplayEntries();
    });
  }

  PlannerItem? _plannerItemForEntry(CalendarEntry entry) {
    if (entry.subjectSource != CalendarSubjectSource.manual) {
      return null;
    }

    final separatorIndex = entry.id.lastIndexOf('::');
    final plannerId = separatorIndex == -1
        ? entry.id
        : entry.id.substring(0, separatorIndex);
    for (final item in _plannerItems) {
      if (item.id == plannerId) {
        return item;
      }
    }
    return null;
  }

  PlannerItem _recordFromDraft(
    PlannerItemDraft draft, {
    PlannerItem? sourceItem,
  }) {
    return PlannerItem(
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
      linkedClassroomContent:
          sourceItem?.linkedClassroomContent ??
          const <PlannerLinkedClassroomContentRef>[],
      completedAt: sourceItem?.completedAt,
      createdAt: sourceItem?.createdAt,
      updatedAt: sourceItem?.updatedAt,
    );
  }

  Future<void> _openScheduleEditor({
    PlannerItem? item,
    DateTime? initialDate,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    Future<String> saveDraft(PlannerItemDraft draft) async {
      final record = _recordFromDraft(draft, sourceItem: item);
      final result = await PlannerItemMutationService.saveRecord(
        uid: user.uid,
        record: record,
        controller: widget.controller,
        currentItems: _plannerItems,
        previousItem: item,
      );
      return result.message;
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
        child: SmartScheduleEditorSheet(
          controller: widget.controller,
          initialItem: item,
          initialDate: initialDate,
          subjects: _scheduleEditorSubjects,
          classroomSubjectNames: _classroomSubjectNames,
          onSave: saveDraft,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (initialDate != null) {
      setState(() {
        _selectedDate = DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        );
        _visibleMonth = DateTime(initialDate.year, initialDate.month);
        _refreshDisplayEntries();
      });
    }

    _showMessage(result);
  }

  Future<void> _deletePlannerItem(PlannerItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    await PlannerItemMutationService.deleteItem(
      uid: uid,
      item: item,
      controller: widget.controller,
      currentItems: _plannerItems,
    );

    if (!mounted) {
      return;
    }
    _showMessage('${item.title} deleted.');
  }

  String _repeatSummary(PlannerItem item) {
    if (item.scheduleSlots.isNotEmpty) {
      final count = item.scheduleSlots.length;
      return '$count weekly ${count == 1 ? 'block' : 'blocks'}';
    }
    if (item.repeatPattern != PlannerRepeatPattern.none) {
      return item.repeatLabel;
    }
    return 'Does not repeat';
  }

  Future<void> _confirmDeleteSchedule(PlannerItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete schedule?'),
          content: Text(
            'Remove "${item.title}" and all of its recurring blocks from your calendar?',
          ),
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

    await _deletePlannerItem(item);
  }

  void _openScheduleDetails(
    PlannerItem item, {
    required CalendarEntry occurrenceEntry,
  }) {
    final tone = _entryToneFor(
      occurrenceEntry,
      Theme.of(context).brightness == Brightness.dark,
    );
    final badgeStyle = _badgeStyleForEntry(occurrenceEntry, tone);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        final now = DateTime.now();
        final startsAt = occurrenceEntry.scheduledDate;
        final endsAt = occurrenceEntry.endDate;

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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ModalSheetHeader(
                    title: item.title,
                    subtitle: '${occurrenceEntry.subject} | Schedule block',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _DocumentBadge(
                        iconData: badgeStyle.iconData,
                        iconColor: badgeStyle.iconColor,
                        backgroundColor: badgeStyle.backgroundColor,
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
                              '${occurrenceEntry.subject} | ${_repeatSummary(item)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (occurrenceEntry.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      occurrenceEntry.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  const SizedBox(height: 18),
                  _DetailRow(
                    label: 'Starts',
                    value: startsAt == null
                        ? 'Start time not set'
                        : _formatDateTime(startsAt),
                  ),
                  if (endsAt != null) ...[
                    const SizedBox(height: 10),
                    _DetailRow(label: 'Ends', value: _formatDateTime(endsAt)),
                  ],
                  const SizedBox(height: 10),
                  _DetailRow(label: 'Repeats', value: _repeatSummary(item)),
                  const SizedBox(height: 10),
                  _DetailRow(
                    label: 'Status',
                    value: _scheduleStatus(occurrenceEntry, now),
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    label: 'Reminder',
                    value: item.reminderEnabled
                        ? item.reminderLabel ?? 'Reminder enabled'
                        : 'Reminder not scheduled',
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tone.background,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: tone.border),
                    ),
                    child: Text(
                      'Editing from Calendar updates the full recurring schedule, not just this one block.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _openScheduleEditor(item: item);
                      },
                      child: const Text('Edit Schedule'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _confirmDeleteSchedule(item);
                      },
                      child: const Text('Delete Schedule'),
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

  void _openEntryDetails(CalendarEntry entry) {
    if (entry.isScheduleEntry &&
        entry.subjectSource == CalendarSubjectSource.manual) {
      final item = _plannerItemForEntry(entry);
      if (item != null) {
        _openScheduleDetails(item, occurrenceEntry: entry);
        return;
      }
    }

    final tone = _entryToneFor(
      entry,
      Theme.of(context).brightness == Brightness.dark,
    );
    final badgeStyle = _badgeStyleForEntry(entry, tone);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        final now = DateTime.now();
        final reminderText = entry.hasReminder
            ? 'Reminder enabled'
            : 'Reminder not scheduled';
        final isScheduleEntry = entry.isScheduleEntry;

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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ModalSheetHeader(
                    title: entry.title,
                    subtitle: '${entry.subject} | ${entry.typeLabel}',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _DocumentBadge(
                        iconData: badgeStyle.iconData,
                        iconColor: badgeStyle.iconColor,
                        backgroundColor: badgeStyle.backgroundColor,
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
                  Text(
                    entry.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  _DetailRow(
                    label: isScheduleEntry ? 'Starts' : 'Deadline',
                    value: _detailSchedule(entry),
                  ),
                  if (isScheduleEntry && entry.endDate != null) ...[
                    const SizedBox(height: 10),
                    _DetailRow(
                      label: 'Ends',
                      value: _formatDateTime(entry.endDate!),
                    ),
                  ],
                  if (!isScheduleEntry) ...[
                    const SizedBox(height: 10),
                    _DetailRow(
                      label: 'Current time',
                      value: _formatDateTime(now),
                    ),
                    const SizedBox(height: 10),
                    _DetailRow(
                      label: 'Time left',
                      value: _detailTimeLeft(entry, now),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _DetailRow(label: 'Status', value: _detailStatus(entry)),
                  const SizedBox(height: 10),
                  _DetailRow(label: 'Reminder', value: reminderText),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: entry.alternateLink == null
                          ? () {
                              Navigator.of(context).pop();
                              _showMessage(
                                'This planner item is managed inside StudyFlow.',
                              );
                            }
                          : () => _openClassroomActivity(entry),
                      child: Text(
                        entry.alternateLink == null
                            ? 'Managed in StudyFlow'
                            : 'Open in Classroom',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showMessage(
                          entry.alternateLink == null
                              ? 'Use the Tasks tab to edit or complete this planner item.'
                              : 'Completion is managed in Google Classroom. Refresh after turning work in there.',
                        );
                      },
                      child: Text(
                        entry.alternateLink == null
                            ? 'Open Task Workspace'
                            : 'Classroom managed',
                      ),
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

  String _detailSchedule(CalendarEntry entry) {
    if (entry.scheduledDate == null) {
      return entry.isScheduleEntry ? 'Start time not set' : 'No deadline set';
    }

    return _formatDateTime(entry.scheduledDate!);
  }

  String _detailTimeLeft(CalendarEntry entry, DateTime now) {
    final scheduledDate = entry.scheduledDate;
    if (scheduledDate == null) {
      return 'No deadline set';
    }

    if (entry.isCompleted) {
      return entry.alternateLink == null
          ? 'Completed in StudyFlow'
          : 'Completed in Classroom';
    }

    final difference = scheduledDate.difference(now);
    if (difference.isNegative) {
      return 'Overdue by ${_formatCountdown(difference.abs())}';
    }

    if (difference.inMinutes == 0) {
      return 'Due now';
    }

    return 'Due in ${_formatCountdown(difference)}';
  }

  String _formatCountdown(Duration duration) {
    if (duration.inDays >= 1) {
      final hours = duration.inHours.remainder(24);
      if (hours == 0) {
        return '${duration.inDays}d';
      }
      return '${duration.inDays}d ${hours}h';
    }

    if (duration.inHours >= 1) {
      final minutes = duration.inMinutes.remainder(60);
      if (minutes == 0) {
        return '${duration.inHours}h';
      }
      return '${duration.inHours}h ${minutes}m';
    }

    return '${duration.inMinutes}m';
  }

  String _detailStatus(CalendarEntry entry) {
    if (entry.isScheduleEntry) {
      return _scheduleStatus(entry, DateTime.now());
    }

    if (entry.isCompleted) {
      return 'Completed';
    }

    if (entry.badgeLabel != null) {
      return entry.badgeLabel!;
    }

    switch (entry.tone) {
      case CalendarEntryTone.critical:
        return 'High priority';
      case CalendarEntryTone.project:
        return 'In progress';
      case CalendarEntryTone.laboratory:
        return 'Scheduled';
      case CalendarEntryTone.openEnded:
        return 'No deadline';
      case CalendarEntryTone.completed:
        return 'Completed';
    }
  }

  String _scheduleStatus(CalendarEntry entry, DateTime now) {
    final start = entry.scheduledDate;
    if (start == null) {
      return 'Start time not set';
    }

    final end = entry.endDate;
    if (end != null && now.isAfter(end)) {
      return 'Ended ${_formatCountdown(now.difference(end))} ago';
    }
    if ((now.isAfter(start) || now.isAtSameMomentAs(start)) &&
        end != null &&
        now.isBefore(end)) {
      return 'Happening now • ends in ${_formatCountdown(end.difference(now))}';
    }
    if ((now.isAfter(start) || now.isAtSameMomentAs(start)) && end == null) {
      return 'Started ${_formatCountdown(now.difference(start))} ago';
    }

    return 'Starts in ${_formatCountdown(start.difference(now))}';
  }

  Future<CalendarRefreshResult?> _loadClassroomActivities({
    required bool promptIfNecessary,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return null;
    }

    setState(() {});
    await widget.controller.updateSyncState(
      status: SyncStatus.syncing,
      lastSyncedAt: _lastClassroomSyncAt,
    );

    try {
      final result = await _calendarRepository.refreshFromClassroom(
        uid: uid,
        promptIfNecessary: promptIfNecessary,
        isOffline: _isOffline,
      );

      if (!mounted) {
        return null;
      }

      setState(() {
        _applySnapshot(result.snapshot);
      });

      await widget.controller.updateSyncState(
        status: result.syncStatus,
        lastSyncCheckedAt: DateTime.now(),
        lastSyncedAt: result.snapshot?.lastSyncedAt ?? _lastClassroomSyncAt,
      );
      await NotificationService.instance.refreshForUser(
        uid: uid,
        controller: widget.controller,
      );
      return result;
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _bootstrapCalendar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final cachedSnapshot = await _calendarRepository.loadBestAvailableSnapshot(
      uid,
    );
    if (!mounted) {
      return;
    }

    if (cachedSnapshot != null) {
      setState(() {
        _applySnapshot(cachedSnapshot);
      });

      await widget.controller.updateSyncState(
        status: _isOffline
            ? SyncStatus.offlineLocalOnly
            : SyncStatus.pendingChanges,
        lastSyncCheckedAt: DateTime.now(),
        lastSyncedAt: cachedSnapshot.lastSyncedAt,
      );
    }
  }

  void _applySnapshot(CalendarCacheSnapshot? snapshot) {
    if (snapshot == null) {
      return;
    }

    _entries = snapshot.entries;
    _lastClassroomSyncAt = snapshot.lastSyncedAt;
    _refreshDisplayEntries();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openClassroomActivity(CalendarEntry entry) async {
    final link = entry.alternateLink;
    if (link == null) {
      _showMessage('No Classroom link is available for this activity.');
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showMessage('The Classroom link for this activity is invalid.');
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalNonBrowserApplication,
    );
    final fallbackLaunched = launched
        ? true
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!fallbackLaunched && mounted) {
      _showMessage('Could not open Google Classroom for this activity.');
    }
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontSize: 24),
          ),
        ),
        _MonthArrowButton(icon: Icons.chevron_left_rounded, onTap: onPrevious),
        const SizedBox(width: 10),
        _MonthArrowButton(icon: Icons.chevron_right_rounded, onTap: onNext),
      ],
    );
  }
}

class _MonthArrowButton extends StatelessWidget {
  const _MonthArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2236) : const Color(0xFFF1F4F8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }
}

class _CalendarMonthCard extends StatelessWidget {
  const _CalendarMonthCard({
    required this.visibleMonth,
    required this.selectedDate,
    required this.entries,
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final List<CalendarEntry> entries;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = _visibleDays();
    const weekLabels = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x00000000) : const Color(0x140F172A),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: weekLabels
                .map(
                  (label) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.72)
                              : const Color(0xFF5E6576),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          ...List.generate(_weekCount(days), (weekIndex) {
            final week = days.skip(weekIndex * 7).take(7).toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: weekIndex == _weekCount(days) - 1 ? 0 : 10,
              ),
              child: Row(
                children: week
                    .map(
                      (date) => Expanded(
                        child: _CalendarDayCell(
                          date: date,
                          visibleMonth: visibleMonth,
                          selectedDate: selectedDate,
                          markers: _markersFor(date),
                          onTap: () => onDateSelected(date),
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          }),
        ],
      ),
    );
  }

  int _weekCount(List<DateTime> days) => (days.length / 7).round();

  List<DateTime> _visibleDays() {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(
      visibleMonth.year,
      visibleMonth.month,
    );
    final startOffset = firstDay.weekday % 7;
    final totalSlots = startOffset + daysInMonth <= 35 ? 35 : 42;
    final start = firstDay.subtract(Duration(days: startOffset));

    return List.generate(totalSlots, (index) {
      return start.add(Duration(days: index));
    });
  }

  List<Color> _markersFor(DateTime date) {
    final datedEntries =
        entries
            .where((entry) => entry.scheduledDate != null)
            .where((entry) => _isSameDate(entry.scheduledDate!, date))
            .toList()
          ..sort((a, b) {
            if (a.isCompleted != b.isCompleted) {
              return a.isCompleted ? 1 : -1;
            }
            return a.scheduledDate!.compareTo(b.scheduledDate!);
          });

    final colors = datedEntries
        .map((entry) {
          switch (entry.tone) {
            case CalendarEntryTone.critical:
              return const Color(0xFFC42E5A);
            case CalendarEntryTone.project:
              return const Color(0xFF8151A5);
            case CalendarEntryTone.laboratory:
              return const Color(0xFF65739A);
            case CalendarEntryTone.openEnded:
              return StudyFlowTheme.primary;
            case CalendarEntryTone.completed:
              return StudyFlowTheme.success;
          }
        })
        .take(3)
        .toList();

    return colors;
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.visibleMonth,
    required this.selectedDate,
    required this.markers,
    required this.onTap,
  });

  final DateTime date;
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final List<Color> markers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = _isSameDate(date, selectedDate);
    final isVisibleMonth = date.month == visibleMonth.month;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedForeground = colorScheme.onPrimaryContainer;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          colorScheme.primaryContainer,
                          colorScheme.secondaryContainer,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.32)
                      : Colors.transparent,
                  width: 1.6,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${date.day}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isSelected
                      ? selectedForeground
                      : isVisibleMonth
                      ? colorScheme.onSurface
                      : (isDark
                            ? const Color(0xFF7E889F)
                            : const Color(0xFFA8B0BE)),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: markers
                    .map(
                      (color) => Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

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
        Text(
          trailing,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({
    required this.entry,
    required this.tone,
    required this.badgeStyle,
    required this.timeRange,
    required this.onTap,
  });

  final CalendarEntry entry;
  final _EntryTone tone;
  final _EntryBadgeStyle badgeStyle;
  final String? timeRange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                tone.background,
                tone.background.withValues(alpha: 0.94),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: tone.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DocumentBadge(
                    iconData: badgeStyle.iconData,
                    iconColor: badgeStyle.iconColor,
                    backgroundColor: badgeStyle.backgroundColor,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                entry.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.copyWith(fontSize: 18),
                              ),
                            ),
                            if (entry.badgeLabel != null)
                              _StatusPill(
                                label: entry.badgeLabel!,
                                backgroundColor: tone.iconBackground,
                                foregroundColor: tone.iconColor,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          entry.subject.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                                color: tone.iconColor.withValues(alpha: 0.88),
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          entry.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.74),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (timeRange != null) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 17,
                      color: tone.iconColor,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      timeRange!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        color: tone.iconColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAgendaCard extends StatelessWidget {
  const _EmptyAgendaCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.85),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _DocumentBadge extends StatelessWidget {
  const _DocumentBadge({
    required this.iconData,
    required this.iconColor,
    required this.backgroundColor,
    this.compact = false,
  });

  final IconData iconData;
  final Color iconColor;
  final Color backgroundColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 42.0 : 60.0;
    final iconSize = compact ? 18.0 : 26.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
      ),
      alignment: Alignment.center,
      child: Icon(iconData, size: iconSize, color: iconColor),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

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

class _CalendarSearchSheet extends StatefulWidget {
  const _CalendarSearchSheet({
    required this.entries,
    required this.subjectAppearanceForEntry,
    required this.onEntrySelected,
  });

  final List<CalendarEntry> entries;
  final SubjectAppearance? Function(CalendarEntry entry)
  subjectAppearanceForEntry;
  final ValueChanged<CalendarEntry> onEntrySelected;

  @override
  State<_CalendarSearchSheet> createState() => _CalendarSearchSheetState();
}

class _CalendarSearchSheetState extends State<_CalendarSearchSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ModalSheetHeader(
            title: 'Search Calendar',
            subtitle:
                'Search tasks, schedules, exams, and flexible items already on the planner.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search subjects, titles, or descriptions',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: isDark
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
            child: _SearchResultsList(
              query: _controller.text,
              entries: widget.entries,
              subjectAppearanceForEntry: widget.subjectAppearanceForEntry,
              onEntrySelected: widget.onEntrySelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({
    required this.query,
    required this.entries,
    required this.subjectAppearanceForEntry,
    required this.onEntrySelected,
  });

  final String query;
  final List<CalendarEntry> entries;
  final SubjectAppearance? Function(CalendarEntry entry)
  subjectAppearanceForEntry;
  final ValueChanged<CalendarEntry> onEntrySelected;

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final results = entries.where((entry) {
      if (normalized.isEmpty) {
        return true;
      }

      return [
        entry.title,
        entry.subject,
        entry.description,
        entry.typeLabel,
        entry.badgeLabel,
        entry.subjectKey,
        entry.subjectSource.name,
        entry.scheduledDate == null
            ? null
            : _formatDateTime(entry.scheduledDate!),
      ].join(' ').toLowerCase().contains(normalized);
    }).toList();

    if (results.isEmpty) {
      return Center(
        child: Text(
          'No calendar items matched "$query".',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = results[index];
        final tone = _entryToneFor(entry, isDark);
        final appearance = subjectAppearanceForEntry(entry);
        final badgeStyle = appearance == null
            ? _EntryBadgeStyle(
                iconData: switch (entry.type) {
                  CalendarEntryType.exam => Icons.quiz_outlined,
                  CalendarEntryType.project => Icons.assignment_outlined,
                  CalendarEntryType.lab => Icons.schedule_rounded,
                  CalendarEntryType.task => Icons.menu_book_outlined,
                },
                backgroundColor: tone.iconBackground,
                iconColor: tone.iconColor,
              )
            : _EntryBadgeStyle(
                iconData: _calendarIconForKey(appearance.iconKey),
                backgroundColor: Color(appearance.colorValue),
                iconColor: _calendarForegroundFor(Color(appearance.colorValue)),
              );

        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          tileColor: tone.background,
          leading: _DocumentBadge(
            iconData: badgeStyle.iconData,
            iconColor: badgeStyle.iconColor,
            backgroundColor: badgeStyle.backgroundColor,
            compact: true,
          ),
          title: Text(entry.title),
          subtitle: Text(entry.subject),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => onEntrySelected(entry),
        );
      },
    );
  }
}

class CalendarCreateButton extends StatelessWidget {
  const CalendarCreateButton({super.key, required this.onTap});

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

class _SmartScheduleLaunchCard extends StatelessWidget {
  const _SmartScheduleLaunchCard({
    required this.selectedDate,
    required this.onTap,
  });

  final DateTime selectedDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF1A2743), Color(0xFF111C34)]
                  : const [Color(0xFFEAF3FF), Color(0xFFF8FBFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? const Color(0xFF2A3A5A) : const Color(0xFFD8E6FF),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorScheme.primary, colorScheme.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/clock.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(
                      colorScheme.onPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Schedule',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create a recurring class or study block starting from ${_formatSectionDate(selectedDate)}.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
