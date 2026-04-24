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
import '../theme/study_flow_theme.dart';
import '../widgets/modal_sheet_header.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onOpenCalendar,
    required this.onOpenTasks,
    required this.onOpenSubjects,
    required this.onOpenManualSubject,
    required this.onOpenClassroomSubject,
    required this.onSearch,
    required this.onCreateTask,
    required this.onCreateExam,
    required this.onCreateSchedule,
    required this.onCreateSubject,
    required this.onSyncData,
  });

  final AppController controller;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenSubjects;
  final ValueChanged<String> onOpenManualSubject;
  final ValueChanged<String> onOpenClassroomSubject;
  final VoidCallback onSearch;
  final VoidCallback onCreateTask;
  final VoidCallback onCreateExam;
  final VoidCallback onCreateSchedule;
  final VoidCallback onCreateSubject;
  final Future<void> Function() onSyncData;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  CalendarCacheSnapshot? _calendarSnapshot;
  SyncStatus? _lastObservedSyncStatus;
  DateTime? _lastObservedSyncedAt;
  int _calendarSnapshotRequestId = 0;
  bool _isLoadingCalendar = true;
  bool _isSaving = false;
  bool _isSyncing = false;
  bool _isOffline = false;
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _lastObservedSyncStatus = widget.controller.syncStatus;
    _lastObservedSyncedAt = widget.controller.lastSyncedAt;
    widget.controller.addListener(_handleControllerChanged);
    _connectionSubscription = DatabaseService.instance
        .observeConnection()
        .listen((connected) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isOffline = !connected;
          });
        });
    _loadCalendarSnapshot();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller == widget.controller) {
      return;
    }

    oldWidget.controller.removeListener(_handleControllerChanged);
    _lastObservedSyncStatus = widget.controller.syncStatus;
    _lastObservedSyncedAt = widget.controller.lastSyncedAt;
    widget.controller.addListener(_handleControllerChanged);
    _loadCalendarSnapshot();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _connectionSubscription?.cancel();
    super.dispose();
  }

  void _handleControllerChanged() {
    final previousStatus = _lastObservedSyncStatus;
    final previousSyncedAt = _lastObservedSyncedAt;
    final currentStatus = widget.controller.syncStatus;
    final currentSyncedAt = widget.controller.lastSyncedAt;

    _lastObservedSyncStatus = currentStatus;
    _lastObservedSyncedAt = currentSyncedAt;

    final syncJustFinished =
        previousStatus == SyncStatus.syncing &&
        currentStatus != SyncStatus.syncing;
    final syncTimestampChanged = previousSyncedAt != currentSyncedAt;

    if (syncJustFinished || syncTimestampChanged) {
      _loadCalendarSnapshot(showLoading: false);
    }
  }

  Future<void> _loadCalendarSnapshot({bool showLoading = true}) async {
    final requestId = ++_calendarSnapshotRequestId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        setState(() => _isLoadingCalendar = false);
      }
      return;
    }

    if (showLoading && mounted) {
      setState(() => _isLoadingCalendar = true);
    }

    final snapshot = await CalendarRepository.instance
        .loadBestAvailableSnapshot(uid);
    if (!mounted || requestId != _calendarSnapshotRequestId) return;
    setState(() {
      _calendarSnapshot = snapshot;
      _isLoadingCalendar = false;
    });
  }

  Future<void> _completeItem(PlannerItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _isSaving || item.isClassroomBacked) return;

    setState(() => _isSaving = true);
    try {
      await DatabaseService.instance.updatePlannerItem(
        uid: uid,
        item: item.copyWith(
          status: PlannerItemStatus.completed,
          completedAt: DateTime.now(),
        ),
      );
      await _refreshNotifications(uid);
      if (!mounted) return;
      _showMessage('${item.title} marked complete.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not complete this item.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _refreshNotifications(String uid) async {
    try {
      await NotificationService.instance.refreshForUser(
        uid: uid,
        controller: widget.controller,
      );
    } catch (error) {
      debugPrint('StudyFlow could not refresh planner notifications: $error');
    }
  }

  Future<void> _openOverdueReviewSheet(List<PlannerItem> items) async {
    if (items.isEmpty) {
      _showMessage('No overdue planner items need review.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
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
                const ModalSheetHeader(
                  title: 'Review overdue work',
                  subtitle:
                      'These unfinished tasks, exams, quizzes, and projects are beyond their due date. Complete them here once finished, or open Tasks if you need to review them first.',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: (MediaQuery.of(context).size.height * 0.38)
                      .clamp(160.0, 360.0)
                      .toDouble(),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final accentColor = _overdueTypeColor(item.type);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: accentColor.withValues(alpha: 0.18),
                          child: Icon(
                            _plannerTypeIcon(item.type),
                            color: accentColor,
                          ),
                        ),
                        title: Text(item.title),
                        subtitle: Text(
                          '${item.typeLabel} | ${_overdueSubtitle(item)}',
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _completeOverdueItems([item]);
                          },
                          child: const Text('Complete'),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onOpenTasks();
                  },
                  child: const Text('Open Tasks'),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _confirmCompleteOverdueItems(items);
                    },
                    child: Text('Complete all ${items.length}'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCompleteOverdueItems(List<PlannerItem> items) async {
    final shouldComplete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Complete overdue items?'),
          content: Text(
            'This will mark ${items.length} overdue ${items.length == 1 ? 'item' : 'items'} as completed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Complete'),
            ),
          ],
        );
      },
    );

    if (shouldComplete == true) {
      await _completeOverdueItems(items);
    }
  }

  Future<void> _completeOverdueItems(List<PlannerItem> items) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _isSaving) {
      return;
    }

    final now = DateTime.now();
    final candidates = items
        .where(
          (item) =>
              !item.isArchived &&
              !item.isCompleted &&
              item.canBeCompleted &&
              _isPlannerPastDue(item, now),
        )
        .toList();
    if (candidates.isEmpty) {
      _showMessage('No eligible overdue items to complete.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      for (final item in candidates) {
        await DatabaseService.instance.updatePlannerItem(
          uid: uid,
          item: item.copyWith(
            status: PlannerItemStatus.completed,
            completedAt: now,
          ),
        );
      }
      await _refreshNotifications(uid);
      if (!mounted) {
        return;
      }
      _showMessage(
        '${candidates.length} overdue ${candidates.length == 1 ? 'item' : 'items'} completed.',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not complete the overdue items.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _syncData() async {
    if (_isSyncing || widget.controller.isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await widget.onSyncData();
      await _loadCalendarSnapshot();
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<PlannerItem>>(
      stream: DatabaseService.instance.watchPlannerItems(uid),
      builder: (context, itemSnapshot) {
        return StreamBuilder<List<SubjectRecord>>(
          stream: DatabaseService.instance.watchSubjects(uid),
          builder: (context, subjectSnapshot) {
            return StreamBuilder<List<SubjectAppearance>>(
              stream: DatabaseService.instance.watchSubjectAppearances(uid),
              builder: (context, appearanceSnapshot) {
                return StreamBuilder<Set<String>>(
                  stream: DatabaseService.instance
                      .watchHiddenClassroomSubjectKeys(uid),
                  builder: (context, hiddenSubjectSnapshot) {
                    return StreamBuilder<Set<String>>(
                      stream: DatabaseService.instance
                          .watchHiddenClassroomEntryIds(uid),
                      builder: (context, hiddenEntrySnapshot) {
                        return AnimatedBuilder(
                          animation: widget.controller,
                          builder: (context, _) {
                            final isLoading =
                                itemSnapshot.connectionState ==
                                    ConnectionState.waiting ||
                                subjectSnapshot.connectionState ==
                                    ConnectionState.waiting ||
                                appearanceSnapshot.connectionState ==
                                    ConnectionState.waiting ||
                                hiddenSubjectSnapshot.connectionState ==
                                    ConnectionState.waiting ||
                                hiddenEntrySnapshot.connectionState ==
                                    ConnectionState.waiting ||
                                _isLoadingCalendar;
                            return _DashboardBody(
                              controller: widget.controller,
                              items: itemSnapshot.data ?? const <PlannerItem>[],
                              subjects:
                                  subjectSnapshot.data ??
                                  const <SubjectRecord>[],
                              subjectAppearances: {
                                for (final appearance
                                    in appearanceSnapshot.data ??
                                        const <SubjectAppearance>[])
                                  appearance.storageKey: appearance,
                              },
                              hiddenClassroomSubjectKeys:
                                  hiddenSubjectSnapshot.data ??
                                  const <String>{},
                              hiddenClassroomEntryIds:
                                  hiddenEntrySnapshot.data ?? const <String>{},
                              calendarSnapshot: _calendarSnapshot,
                              isLoading: isLoading,
                              isSaving: _isSaving,
                              isSyncing:
                                  _isSyncing || widget.controller.isSyncing,
                              isOffline: _isOffline,
                              onCompleteItem: _completeItem,
                              onOpenOverdueReview: _openOverdueReviewSheet,
                              onOpenCalendar: widget.onOpenCalendar,
                              onOpenTasks: widget.onOpenTasks,
                              onOpenSubjects: widget.onOpenSubjects,
                              onOpenManualSubject: widget.onOpenManualSubject,
                              onOpenClassroomSubject:
                                  widget.onOpenClassroomSubject,
                              onSearch: widget.onSearch,
                              onCreateTask: widget.onCreateTask,
                              onCreateExam: widget.onCreateExam,
                              onCreateSchedule: widget.onCreateSchedule,
                              onCreateSubject: widget.onCreateSubject,
                              onSyncData: _syncData,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.controller,
    required this.items,
    required this.subjects,
    required this.subjectAppearances,
    required this.hiddenClassroomSubjectKeys,
    required this.hiddenClassroomEntryIds,
    required this.calendarSnapshot,
    required this.isLoading,
    required this.isSaving,
    required this.isSyncing,
    required this.isOffline,
    required this.onCompleteItem,
    required this.onOpenOverdueReview,
    required this.onOpenCalendar,
    required this.onOpenTasks,
    required this.onOpenSubjects,
    required this.onOpenManualSubject,
    required this.onOpenClassroomSubject,
    required this.onSearch,
    required this.onCreateTask,
    required this.onCreateExam,
    required this.onCreateSchedule,
    required this.onCreateSubject,
    required this.onSyncData,
  });

  final AppController controller;
  final List<PlannerItem> items;
  final List<SubjectRecord> subjects;
  final Map<String, SubjectAppearance> subjectAppearances;
  final Set<String> hiddenClassroomSubjectKeys;
  final Set<String> hiddenClassroomEntryIds;
  final CalendarCacheSnapshot? calendarSnapshot;
  final bool isLoading;
  final bool isSaving;
  final bool isSyncing;
  final bool isOffline;
  final ValueChanged<PlannerItem> onCompleteItem;
  final void Function(List<PlannerItem>) onOpenOverdueReview;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenSubjects;
  final ValueChanged<String> onOpenManualSubject;
  final ValueChanged<String> onOpenClassroomSubject;
  final VoidCallback onSearch;
  final VoidCallback onCreateTask;
  final VoidCallback onCreateExam;
  final VoidCallback onCreateSchedule;
  final VoidCallback onCreateSubject;
  final Future<void> Function() onSyncData;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hiddenPlannerSubjectIds = hiddenClassroomPlannerSubjectIds(
      calendarSnapshot?.entries ?? const <CalendarEntry>[],
      hiddenClassroomSubjectKeys,
    );
    final openItems = items
        .where(
          (item) => !item.isArchived && !item.isDeleted && !item.isCompleted,
        )
        .where(
          (item) => !isPlannerItemHiddenByClassroom(
            item,
            hiddenEntryIds: hiddenClassroomEntryIds,
            hiddenPlannerSubjectIds: hiddenPlannerSubjectIds,
          ),
        )
        .toList();
    final activeItems = items
        .where((item) => !item.isArchived && !item.isDeleted)
        .where(
          (item) => !isPlannerItemHiddenByClassroom(
            item,
            hiddenEntryIds: hiddenClassroomEntryIds,
            hiddenPlannerSubjectIds: hiddenPlannerSubjectIds,
          ),
        )
        .toList();
    final activeSubjects = subjects
        .where((subject) => !subject.isArchived)
        .toList();
    final subjectsById = {for (final subject in subjects) subject.id: subject};
    final classroomEntries = _visibleClassroomEntries(
      activeItems,
      hiddenClassroomSubjectKeys: hiddenClassroomSubjectKeys,
      hiddenClassroomEntryIds: hiddenClassroomEntryIds,
    );
    final openClassroomEntries = classroomEntries
        .where((entry) => !entry.isCompleted)
        .toList();
    final dueSoon = _dueSoonItems(
      openItems,
      openClassroomEntries,
      subjectsById,
      subjectAppearances,
    );
    final overdueReviewItems = _buildOverdueReviewItems(
      openItems,
      openClassroomEntries,
    );
    final agenda = _todaysAgenda(now, openItems, subjectsById);
    final subjectPulse = _subjectPulse(
      activeSubjects,
      openItems,
      openClassroomEntries,
    );
    final completedThisWeek = activeItems
        .where((item) => item.completedAt != null)
        .where((item) => _isThisWeek(item.completedAt!, now))
        .length;
    final dueToday =
        openItems
            .where(
              (item) =>
                  item.type != PlannerItemType.schedule &&
                  item.scheduledAt != null &&
                  _sameDay(item.scheduledAt!, now),
            )
            .length +
        openClassroomEntries
            .where(
              (entry) =>
                  entry.scheduledDate != null &&
                  _sameDay(entry.scheduledDate!, now),
            )
            .length;
    final upcomingExams =
        openItems
            .where(
              (item) =>
                  item.type == PlannerItemType.exam &&
                  item.scheduledAt != null &&
                  item.scheduledAt!.isAfter(now),
            )
            .length +
        openClassroomEntries
            .where((entry) => entry.type == CalendarEntryType.exam)
            .length;
    final pendingTasks =
        openItems
            .where(
              (item) =>
                  item.type == PlannerItemType.task ||
                  item.type == PlannerItemType.project,
            )
            .length +
        openClassroomEntries
            .where((entry) => entry.type != CalendarEntryType.exam)
            .length;
    final firstName = _firstName(
      FirebaseAuth.instance.currentUser?.displayName,
    );
    final syncDisplayStatus = controller.syncDisplayStatus(
      isOffline: isOffline,
      now: now,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 102, 22, 150),
      children: [
        _HeroCard(
          title: '${_greetingFor(now)}, ${firstName ?? 'Student'}',
          subtitle: _fullDate(now),
          status: syncDisplayStatus,
          isLoading: isLoading,
        ),
        const SizedBox(height: 18),
        _SearchCard(onTap: onSearch),
        const SizedBox(height: 18),
        _StatsGrid(
          stats: [
            _StatData(
              'Pending Tasks',
              pendingTasks,
              const Color(0xFF5466E6),
              'assets/icons/document.svg',
            ),
            _StatData(
              'Due Today',
              dueToday,
              const Color(0xFFC24A5B),
              'assets/icons/calendar.svg',
            ),
            _StatData(
              'Upcoming Exams',
              upcomingExams,
              const Color(0xFF8E73E9),
              'assets/icons/book.svg',
            ),
            _StatData(
              'Completed Week',
              completedThisWeek,
              const Color(0xFF2B7A63),
              'assets/icons/shieldcheck.svg',
            ),
          ],
        ),
        const SizedBox(height: 28),
        _SectionTitle(
          title: 'Today\'s Schedule',
          actionLabel: 'Calendar',
          onTap: onOpenCalendar,
        ),
        const SizedBox(height: 14),
        if (agenda.isEmpty)
          _EmptyCard(
            title: 'No schedule today',
            body:
                'Smart schedules you create in Calendar will appear here when they have a meeting today.',
            actionLabel: 'Create schedule',
            onTap: onCreateSchedule,
          )
        else
          _Timeline(entries: agenda.take(5).toList()),
        const SizedBox(height: 28),
        _SectionTitle(
          title: 'Due Soon',
          actionLabel: 'View all',
          onTap: onOpenTasks,
        ),
        const SizedBox(height: 14),
        if (dueSoon.isEmpty)
          _EmptyCard(
            title: 'No urgent work',
            body: 'Tasks and exams due soon will surface here automatically.',
            actionLabel: 'Add task',
            onTap: onCreateTask,
          )
        else
          ...dueSoon
              .take(4)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DueSoonCard(
                    entry: item,
                    isSaving: isSaving,
                    onOpenDetails: () => _openDueSoonDetails(context, item),
                    onComplete:
                        item.sourceItem?.canBeCompleted == true &&
                            item.sourceItem?.isClassroomBacked == false
                        ? () => onCompleteItem(item.sourceItem!)
                        : null,
                  ),
                ),
              ),
        const SizedBox(height: 14),
        _OverdueReviewCard(
          overdueCount: overdueReviewItems.length,
          onTap: overdueReviewItems.isEmpty
              ? null
              : () => onOpenOverdueReview(overdueReviewItems),
        ),
        const SizedBox(height: 28),
        _SectionTitle(
          title: 'Subject Pulse',
          actionLabel: 'Subjects',
          onTap: onOpenSubjects,
        ),
        const SizedBox(height: 14),
        if (subjectPulse.isEmpty)
          _EmptyCard(
            title: 'No subjects yet',
            body:
                'Add subjects so tasks, exams, and schedules have course context.',
            actionLabel: 'Add subject',
            onTap: onCreateSubject,
          )
        else
          _SubjectPulseStrip(
            subjects: subjectPulse.take(3).toList(),
            onOpenManualSubject: onOpenManualSubject,
            onOpenClassroomSubject: onOpenClassroomSubject,
          ),
        const SizedBox(height: 28),
        _QuickActions(
          isSyncing: isSyncing,
          onCreateTask: onCreateTask,
          onCreateExam: onCreateExam,
          onCreateSchedule: onCreateSchedule,
          onCreateSubject: onCreateSubject,
          onSyncData: onSyncData,
        ),
        const SizedBox(height: 18),
        _StatusCard(
          controller: controller,
          snapshot: calendarSnapshot,
          status: syncDisplayStatus,
          isOffline: isOffline,
          isSyncing: isSyncing,
          onSyncData: onSyncData,
        ),
      ],
    );
  }

  List<_DueSoonEntry> _dueSoonItems(
    List<PlannerItem> openItems,
    List<CalendarEntry> classroomEntries,
    Map<String, SubjectRecord> subjectsById,
    Map<String, SubjectAppearance> subjectAppearances,
  ) {
    final now = DateTime.now();
    final soonEnd = now.add(const Duration(days: 7));
    final results = <_DueSoonEntry>[
      ...openItems
          .where((item) {
            final scheduledAt = item.scheduledAt;
            return item.type != PlannerItemType.schedule &&
                scheduledAt != null &&
                !_isPlannerPastDue(item, now) &&
                !scheduledAt.isAfter(soonEnd);
          })
          .map((item) {
            final subject = subjectsById[item.subjectId];
            final accentColor = Color(
              subject?.colorValue ?? _typeColorValue(item.type),
            );
            return _DueSoonEntry(
              title: item.title,
              subjectLabel: _manualSubjectLabel(subject, item),
              scheduledAt: item.scheduledAt!,
              priorityLabel: item.priorityLabel,
              priority: item.effectivePriority,
              iconData: _iconForKey(subject?.iconKey),
              accentColor: accentColor,
              description: item.description ?? item.notes,
              typeLabel: item.typeLabel,
              sourceItem: item,
            );
          }),
      ...classroomEntries
          .where((entry) {
            final scheduledAt = entry.scheduledDate;
            return scheduledAt != null &&
                !scheduledAt.isBefore(now) &&
                !scheduledAt.isAfter(soonEnd);
          })
          .map((entry) {
            final appearance = _appearanceForEntry(entry, subjectAppearances);
            final accentColor = appearance == null
                ? _classroomColor(entry.subject)
                : Color(appearance.colorValue);
            return _DueSoonEntry(
              title: entry.title,
              subjectLabel: _classroomSubjectLabel(entry),
              scheduledAt: entry.scheduledDate!,
              priorityLabel: entry.tone == CalendarEntryTone.critical
                  ? 'High Priority'
                  : entry.typeLabel,
              priority: entry.tone == CalendarEntryTone.critical
                  ? PlannerItemPriority.high
                  : PlannerItemPriority.medium,
              iconData: _iconForKey(appearance?.iconKey),
              accentColor: accentColor,
              description: entry.description,
              typeLabel: 'Classroom ${entry.typeLabel}',
              classroomEntry: entry,
            );
          }),
    ];
    results.sort((a, b) {
      final priorityRank = {
        PlannerItemPriority.high: 0,
        PlannerItemPriority.medium: 1,
        PlannerItemPriority.low: 2,
        PlannerItemPriority.optional: 3,
      };
      final priorityCompare = priorityRank[a.effectivePriority]!.compareTo(
        priorityRank[b.effectivePriority]!,
      );
      if (priorityCompare != 0) return priorityCompare;
      return a.scheduledAt.compareTo(b.scheduledAt);
    });
    return results;
  }

  List<PlannerItem> _buildOverdueReviewItems(
    List<PlannerItem> openItems,
    List<CalendarEntry> openClassroomEntries,
  ) {
    final now = DateTime.now();
    final overdueItems =
        <PlannerItem>[
          ...openItems.where((item) => item.canBeCompleted),
          ...openClassroomEntries.map((entry) {
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
                  ? controller.taskReminderDefault
                  : null,
              autoCompleteFromSubtasks: false,
            );
          }),
        ].where((item) => _isPlannerPastDue(item, now)).toList()..sort((a, b) {
          final scheduledAtA = a.scheduledAt;
          final scheduledAtB = b.scheduledAt;
          if (scheduledAtA == null && scheduledAtB == null) {
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          }
          if (scheduledAtA == null) return 1;
          if (scheduledAtB == null) return -1;
          final dueCompare = scheduledAtA.compareTo(scheduledAtB);
          if (dueCompare != 0) return dueCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
    return overdueItems;
  }

  List<_AgendaEntry> _todaysAgenda(
    DateTime now,
    List<PlannerItem> openItems,
    Map<String, SubjectRecord> subjectsById,
  ) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final entries = <_AgendaEntry>[];

    for (final item in openItems) {
      if (item.type == PlannerItemType.schedule) {
        for (final occurrence in item.occurrencesInRange(
          todayStart,
          todayEnd,
        )) {
          final subject = subjectsById[item.subjectId];
          entries.add(
            _AgendaEntry(
              title: item.title,
              subtitle:
                  subject?.subjectName ?? item.subjectName ?? 'Custom subject',
              location: item.location,
              at: occurrence,
              endAt: item.occurrenceEndAt(occurrence),
              label: 'Schedule',
              color: const Color(0xFF38A98D),
            ),
          );
        }
        continue;
      }
    }

    entries.sort((a, b) => a.at.compareTo(b.at));
    return entries;
  }

  List<_SubjectPulse> _subjectPulse(
    List<SubjectRecord> subjects,
    List<PlannerItem> openItems,
    List<CalendarEntry> classroomEntries,
  ) {
    final results = <_SubjectPulse>[];

    for (final subject in subjects) {
      final subjectItems = openItems
          .where(
            (item) =>
                item.subjectId == subject.id &&
                item.type != PlannerItemType.schedule,
          )
          .toList();
      if (subjectItems.isEmpty) {
        continue;
      }
      final deadlines =
          subjectItems
              .map((item) => item.scheduledAt)
              .whereType<DateTime>()
              .toList()
            ..sort();
      results.add(
        _SubjectPulse(
          code: subject.subjectCode.trim().isEmpty
              ? _initialsForLabel(subject.subjectName)
              : subject.subjectCode.toUpperCase(),
          name: subject.subjectName,
          color: Color(subject.colorValue),
          openCount: subjectItems.length,
          nextDeadline: deadlines.isEmpty ? null : deadlines.first,
          manualSubjectId: subject.id,
        ),
      );
    }

    final groupedClassroom = <String, List<CalendarEntry>>{};
    for (final entry in classroomEntries) {
      final key = entry.subjectKey?.trim().isNotEmpty == true
          ? entry.subjectKey!.trim()
          : entry.subject.trim().isEmpty
          ? 'classroom'
          : entry.subject.trim();
      groupedClassroom.putIfAbsent(key, () => <CalendarEntry>[]).add(entry);
    }

    results.addAll(
      groupedClassroom.entries.map((group) {
        final name = group.value.first.subject.trim().isEmpty
            ? 'Classroom'
            : group.value.first.subject.trim();
        final deadlines =
            group.value
                .map((entry) => entry.scheduledDate)
                .whereType<DateTime>()
                .toList()
              ..sort();
        return _SubjectPulse(
          code: _initialsForLabel(name),
          name: name,
          color: _classroomColor(name),
          openCount: group.value.length,
          nextDeadline: deadlines.isEmpty ? null : deadlines.first,
          classroomSubjectKey: group.key,
        );
      }),
    );

    results.sort((a, b) {
      final countCompare = b.openCount.compareTo(a.openCount);
      if (countCompare != 0) return countCompare;
      return (a.nextDeadline ?? DateTime(2100)).compareTo(
        b.nextDeadline ?? DateTime(2100),
      );
    });
    return results;
  }

  List<CalendarEntry> _visibleClassroomEntries(
    List<PlannerItem> activeItems, {
    required Set<String> hiddenClassroomSubjectKeys,
    required Set<String> hiddenClassroomEntryIds,
  }) {
    final importedIds = activeItems
        .map((item) => item.sourceItemId)
        .whereType<String>()
        .toSet();
    return (calendarSnapshot?.entries ?? const <CalendarEntry>[])
        .where((entry) => !importedIds.contains(entry.id))
        .where(
          (entry) => !isHiddenClassroomEntry(
            entry,
            hiddenSubjectKeys: hiddenClassroomSubjectKeys,
            hiddenEntryIds: hiddenClassroomEntryIds,
          ),
        )
        .toList();
  }

  void _openDueSoonDetails(BuildContext context, _DueSoonEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        final classroom = entry.classroomEntry;
        final sourceItem = entry.sourceItem;
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
                ModalSheetHeader(
                  title: entry.title,
                  subtitle: '${entry.subjectLabel} | ${entry.typeLabel}',
                ),
                const SizedBox(height: 12),
                _SubjectIconBadge(
                  iconData: entry.iconData,
                  color: entry.accentColor,
                ),
                if ((entry.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    entry.description!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: 18),
                _DetailLine(
                  label: 'Deadline',
                  value:
                      '${_monthDay(entry.scheduledAt)} at ${_timeLabel(entry.scheduledAt)}',
                ),
                const SizedBox(height: 10),
                _DetailLine(
                  label: 'Time left',
                  value: _timeLeft(entry.scheduledAt, DateTime.now()),
                ),
                const SizedBox(height: 10),
                _DetailLine(label: 'Priority', value: entry.priorityLabel),
                const SizedBox(height: 10),
                _DetailLine(
                  label: 'Source',
                  value: classroom == null
                      ? 'StudyFlow planner'
                      : 'Google Classroom',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (classroom?.alternateLink != null) {
                        _openClassroomLink(classroom!);
                      } else {
                        onOpenTasks();
                      }
                    },
                    child: Text(
                      classroom?.alternateLink != null
                          ? 'Open in Classroom'
                          : sourceItem == null
                          ? 'Open Tasks'
                          : 'Open in Tasks',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AgendaEntry {
  const _AgendaEntry({
    required this.title,
    required this.subtitle,
    required this.location,
    required this.at,
    required this.endAt,
    required this.label,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String? location;
  final DateTime at;
  final DateTime? endAt;
  final String label;
  final Color color;
}

class _DueSoonEntry {
  const _DueSoonEntry({
    required this.title,
    required this.subjectLabel,
    required this.scheduledAt,
    required this.priorityLabel,
    required this.priority,
    required this.iconData,
    required this.accentColor,
    required this.typeLabel,
    this.description,
    this.sourceItem,
    this.classroomEntry,
  });

  final String title;
  final String subjectLabel;
  final DateTime scheduledAt;
  final String priorityLabel;
  final PlannerItemPriority priority;
  final IconData iconData;
  final Color accentColor;
  final String typeLabel;
  final String? description;
  final PlannerItem? sourceItem;
  final CalendarEntry? classroomEntry;

  PlannerItemPriority get effectivePriority => priority;
}

class _SubjectIconBadge extends StatelessWidget {
  const _SubjectIconBadge({required this.iconData, required this.color});

  final IconData iconData;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF1E2433);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(iconData, color: foreground, size: 22),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}

class _SubjectPulse {
  const _SubjectPulse({
    required this.code,
    required this.name,
    required this.color,
    required this.openCount,
    required this.nextDeadline,
    this.manualSubjectId,
    this.classroomSubjectKey,
  });

  final String code;
  final String name;
  final Color color;
  final int openCount;
  final DateTime? nextDeadline;
  final String? manualSubjectId;
  final String? classroomSubjectKey;
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.isLoading,
  });

  final String title;
  final String subtitle;
  final SyncDisplayStatus status;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF17213A), Color(0xFF101726)]
              : const [Color(0xFFFFFFFF), Color(0xFFF1F5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? const Color(0xFF253149) : const Color(0xFFE4E9F7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(fontSize: 30),
                ),
              ),
              _SyncChip(status: status, isLoading: isLoading),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.status, required this.isLoading});

  final SyncDisplayStatus status;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncDisplayStatus.stable => StudyFlowTheme.success,
      SyncDisplayStatus.syncing => StudyFlowTheme.primary,
      SyncDisplayStatus.offline => const Color(0xFF61708F),
      SyncDisplayStatus.outdated => const Color(0xFFE4A93B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 7),
          Text(
            isLoading ? 'Loading' : _syncLabel(status),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF182134) : const Color(0xFFEDEFF2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search tasks, exams, or subjects...',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final List<_StatData> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 14) / 2;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: stats
              .map((stat) => _StatCard(width: width, data: stat))
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.width, required this.data});

  final double width;
  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                data.value.toString(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: data.color,
                  fontSize: 26,
                ),
              ),
              const Spacer(),
              SvgPicture.asset(
                data.iconAsset,
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(data.color, BlendMode.srcIn),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            data.label.toUpperCase(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 11,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatData {
  const _StatData(this.label, this.value, this.color, this.iconAsset);

  final String label;
  final int value;
  final Color color;
  final String iconAsset;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton(onPressed: onTap, child: Text(actionLabel)),
      ],
    );
  }
}

class _DueSoonCard extends StatelessWidget {
  const _DueSoonCard({
    required this.entry,
    required this.isSaving,
    required this.onOpenDetails,
    required this.onComplete,
  });

  final _DueSoonEntry entry;
  final bool isSaving;
  final VoidCallback onOpenDetails;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final date = entry.scheduledAt;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onOpenDetails,
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.transparent
                  : const Color(0x120F172A),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            _SubjectIconBadge(
              iconData: entry.iconData,
              color: entry.accentColor,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(
                        label: entry.subjectLabel,
                        color: StudyFlowTheme.primary,
                      ),
                      _Pill(
                        label: entry.priorityLabel,
                        color:
                            entry.effectivePriority == PlannerItemPriority.high
                            ? StudyFlowTheme.warning
                            : StudyFlowTheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    entry.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_monthDay(date)} at ${_timeLabel(date)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: isSaving ? null : onComplete,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFF222C42)
                      : const Color(0xFFEEF1F6),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF35415B)
                        : const Color(0xFFD9DEEA),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.check_rounded,
                  size: 22,
                  color: onComplete == null || isSaving
                      ? (isDark
                            ? const Color(0xFF7F8AA2)
                            : const Color(0xFF9BA3B2))
                      : (isDark
                            ? const Color(0xFFE3EAFB)
                            : const Color(0xFF5C6472)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          fontSize: 11,
          height: 1.1,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});

  final List<_AgendaEntry> entries;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: List.generate(entries.length, (index) {
          final entry = entries[index];
          final entryColor = _agendaEntryColor(entry, context);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    Container(
                      width: 2,
                      height: index == 0 ? 18 : 10,
                      color: index == 0
                          ? Colors.transparent
                          : (isDark
                                ? const Color(0xFF35415B)
                                : const Color(0xFFD8DDE8)),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: entryColor.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: entryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Container(
                      width: 2,
                      height: index == entries.length - 1 ? 14 : 34,
                      color: index == entries.length - 1
                          ? Colors.transparent
                          : (isDark
                                ? const Color(0xFF35415B)
                                : const Color(0xFFD8DDE8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _agendaTimeLabel(entry),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: entryColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.label,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if ((entry.location ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.location!.trim(),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.72),
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _OverdueReviewCard extends StatelessWidget {
  const _OverdueReviewCard({required this.overdueCount, required this.onTap});

  final int overdueCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasOverdue = overdueCount > 0;
    final backgroundColor = hasOverdue
        ? StudyFlowTheme.warning.withValues(alpha: isDark ? 0.18 : 0.1)
        : Theme.of(context).cardColor.withValues(alpha: 0.95);
    final foregroundColor = hasOverdue
        ? StudyFlowTheme.warning
        : Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasOverdue
                ? StudyFlowTheme.warning.withValues(alpha: 0.22)
                : Theme.of(context).dividerColor.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasOverdue
                  ? Icons.notification_important_outlined
                  : Icons.notifications_active_outlined,
              color: foregroundColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasOverdue
                        ? '$overdueCount overdue ${overdueCount == 1 ? 'item' : 'items'} need review'
                        : 'No overdue alerts',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasOverdue
                        ? 'Check unfinished work and complete what is already done.'
                        : 'Past-due tasks, exams, quizzes, and projects will surface here.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (hasOverdue)
              Text(
                'Review',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubjectPulseStrip extends StatelessWidget {
  const _SubjectPulseStrip({
    required this.subjects,
    required this.onOpenManualSubject,
    required this.onOpenClassroomSubject,
  });

  final List<_SubjectPulse> subjects;
  final ValueChanged<String> onOpenManualSubject;
  final ValueChanged<String> onOpenClassroomSubject;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 154,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: subjects.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final pulse = subjects[index];
          final color = pulse.color;
          final foreground =
              ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : const Color(0xFF1E2433);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () {
                final manualSubjectId = pulse.manualSubjectId;
                final classroomSubjectKey = pulse.classroomSubjectKey;
                if (manualSubjectId != null) {
                  onOpenManualSubject(manualSubjectId);
                } else if (classroomSubjectKey != null) {
                  onOpenClassroomSubject(classroomSubjectKey);
                }
              },
              child: Ink(
                width: 224,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pulse.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      pulse.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground,
                        height: 1.1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      pulse.nextDeadline == null
                          ? '${pulse.openCount} open items'
                          : '${pulse.openCount} open - next ${_monthDay(pulse.nextDeadline!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _manualSubjectLabel(SubjectRecord? subject, PlannerItem item) {
  if (subject != null) {
    final code = subject.subjectCode.trim();
    if (code.isEmpty) {
      return subject.subjectName;
    }
    return '${code.toUpperCase()} - ${subject.subjectName}';
  }

  final subjectCode = item.subjectCode?.trim();
  final subjectName = item.subjectName?.trim();
  if (subjectCode != null &&
      subjectCode.isNotEmpty &&
      subjectName != null &&
      subjectName.isNotEmpty) {
    return '${subjectCode.toUpperCase()} - $subjectName';
  }
  if (subjectName != null && subjectName.isNotEmpty) {
    return subjectName;
  }
  if (subjectCode != null && subjectCode.isNotEmpty) {
    return subjectCode.toUpperCase();
  }
  return item.typeLabel;
}

String _classroomSubjectLabel(CalendarEntry entry) {
  final subject = entry.subject.trim();
  return subject.isEmpty ? 'Classroom' : subject;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.isSyncing,
    required this.onCreateTask,
    required this.onCreateExam,
    required this.onCreateSchedule,
    required this.onCreateSubject,
    required this.onSyncData,
  });

  final bool isSyncing;
  final VoidCallback onCreateTask;
  final VoidCallback onCreateExam;
  final VoidCallback onCreateSchedule;
  final VoidCallback onCreateSubject;
  final Future<void> Function() onSyncData;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickTile(
                  width: width,
                  icon: 'assets/icons/document.svg',
                  label: 'Add Task',
                  onTap: onCreateTask,
                ),
                _QuickTile(
                  width: width,
                  icon: 'assets/icons/calendar.svg',
                  label: 'Exams & Quizzes',
                  onTap: onCreateExam,
                ),
                _QuickTile(
                  width: width,
                  icon: 'assets/icons/clock.svg',
                  label: 'Smart Schedule',
                  onTap: onCreateSchedule,
                ),
                _QuickTile(
                  width: width,
                  icon: 'assets/icons/subject.svg',
                  label: 'Add Subject',
                  onTap: onCreateSubject,
                ),
                _QuickTile(
                  width: constraints.maxWidth,
                  icon: 'assets/icons/load.svg',
                  label: isSyncing ? 'Syncing Data...' : 'Sync Data',
                  onTap: isSyncing ? null : onSyncData,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double width;
  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              icon,
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.primary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          TextButton(onPressed: onTap, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.controller,
    required this.snapshot,
    required this.status,
    required this.isOffline,
    required this.isSyncing,
    required this.onSyncData,
  });

  final AppController controller;
  final CalendarCacheSnapshot? snapshot;
  final SyncDisplayStatus status;
  final bool isOffline;
  final bool isSyncing;
  final Future<void> Function() onSyncData;

  @override
  Widget build(BuildContext context) {
    final lastChecked = controller.lastSyncCheckedAt;
    final lastSynced = controller.lastSyncedAt ?? snapshot?.lastSyncedAt;
    final isShowingCachedSnapshot =
        snapshot != null && (status == SyncDisplayStatus.syncing || isOffline);
    final detail = switch (status) {
      SyncDisplayStatus.stable =>
        lastSynced == null
            ? 'Your latest data is ready.'
            : 'Last updated ${_monthDay(lastSynced)} at ${_timeLabel(lastSynced)}.',
      SyncDisplayStatus.syncing =>
        isShowingCachedSnapshot
            ? 'Showing saved data while new assignments and schedules refresh in the background.'
            : 'Refreshing assignments and schedules now.',
      SyncDisplayStatus.offline =>
        'You are offline. Cached data is available until you reconnect.',
      SyncDisplayStatus.outdated =>
        lastSynced == null
            ? 'No recent sync yet. Refresh to load the latest planner data.'
            : 'The last sync is over 12 hours old. Refresh to catch new work.',
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.78),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.asset(
                'assets/icons/notification.svg',
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  Theme.of(context).colorScheme.primary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sync center',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Status: ${_syncLabel(status).toLowerCase()}. $detail',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (lastChecked != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Last checked ${_monthDay(lastChecked)} at ${_timeLabel(lastChecked)}.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: isSyncing || isOffline ? null : onSyncData,
            child: Text(isSyncing ? 'Syncing...' : 'Sync now'),
          ),
          if (controller.autoSyncEnabled) ...[
            const SizedBox(height: 8),
            Text(
              'Auto Sync checks while the app is active and when you return to it.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isPlannerPastDue(PlannerItem item, DateTime now) {
  final scheduledAt = item.scheduledAt;
  if (item.isCompleted || scheduledAt == null || !item.canBeCompleted) {
    return false;
  }

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

bool _isThisWeek(DateTime value, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final weekEnd = weekStart.add(const Duration(days: 7));
  return !value.isBefore(weekStart) && value.isBefore(weekEnd);
}

String? _firstName(String? displayName) {
  final parts = displayName
      ?.trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  return parts == null || parts.isEmpty ? null : parts.first;
}

String _greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 18) return 'Good afternoon';
  return 'Good evening';
}

String _fullDate(DateTime value) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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
  return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
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

String _timeRangeLabel(DateTime start, DateTime? end) {
  if (end == null || !end.isAfter(start)) {
    return _timeLabel(start);
  }
  return '${_timeLabel(start)} - ${_timeLabel(end)}';
}

String _agendaTimeLabel(_AgendaEntry entry) {
  return _timeRangeLabel(entry.at, entry.endAt);
}

Color _agendaEntryColor(_AgendaEntry entry, BuildContext context) {
  final now = DateTime.now();
  final ended = entry.endAt != null && entry.endAt!.isBefore(now);
  if (!ended) {
    return entry.color;
  }
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF6E778B)
      : const Color(0xFF98A1B3);
}

String _syncLabel(SyncDisplayStatus status) {
  switch (status) {
    case SyncDisplayStatus.stable:
      return 'Stable';
    case SyncDisplayStatus.syncing:
      return 'Syncing';
    case SyncDisplayStatus.offline:
      return 'Offline';
    case SyncDisplayStatus.outdated:
      return 'Outdated';
  }
}

SubjectAppearance? _appearanceForEntry(
  CalendarEntry entry,
  Map<String, SubjectAppearance> appearances,
) {
  if (entry.subjectSource != CalendarSubjectSource.classroom) return null;
  final subjectKey = entry.subjectKey?.trim().isNotEmpty == true
      ? entry.subjectKey!.trim()
      : entry.subject.trim().isEmpty
      ? 'classroom'
      : entry.subject.trim();
  return appearances['${CalendarSubjectSource.classroom.name}::$subjectKey'];
}

IconData _iconForKey(String? key) {
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

int _typeColorValue(PlannerItemType type) {
  switch (type) {
    case PlannerItemType.exam:
      return 0xFFFFE1E8;
    case PlannerItemType.schedule:
      return 0xFFD9F4EA;
    case PlannerItemType.project:
      return 0xFFF1E1FF;
    case PlannerItemType.task:
      return 0xFFDDE5FF;
  }
}

Color _overdueTypeColor(PlannerItemType type) {
  switch (type) {
    case PlannerItemType.exam:
      return const Color(0xFFC24A5B);
    case PlannerItemType.schedule:
      return const Color(0xFF2B7A63);
    case PlannerItemType.project:
      return const Color(0xFF9273E5);
    case PlannerItemType.task:
      return const Color(0xFF5466E6);
  }
}

IconData _plannerTypeIcon(PlannerItemType type) {
  switch (type) {
    case PlannerItemType.exam:
      return Icons.workspace_premium_outlined;
    case PlannerItemType.schedule:
      return Icons.schedule_outlined;
    case PlannerItemType.project:
      return Icons.inventory_2_outlined;
    case PlannerItemType.task:
      return Icons.checklist_rounded;
  }
}

String _overdueSubtitle(PlannerItem item) {
  final scheduledAt = item.scheduledAt;
  if (scheduledAt == null) {
    return 'No due date';
  }
  final dueLabel = item.hasExplicitTime
      ? '${_monthDay(scheduledAt)} at ${_timeLabel(scheduledAt)}'
      : _monthDay(scheduledAt);
  return '$dueLabel | ${_timeLeft(scheduledAt, DateTime.now())}';
}

String _timeLeft(DateTime value, DateTime now) {
  final difference = value.difference(now);
  if (difference.isNegative) {
    return 'Overdue by ${_formatDuration(difference.abs())}';
  }
  if (difference.inMinutes <= 0) return 'Due now';
  return 'Due in ${_formatDuration(difference)}';
}

String _formatDuration(Duration duration) {
  if (duration.inDays >= 1) {
    final hours = duration.inHours.remainder(24);
    return hours == 0 ? '${duration.inDays}d' : '${duration.inDays}d ${hours}h';
  }
  if (duration.inHours >= 1) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? '${duration.inHours}h'
        : '${duration.inHours}h ${minutes}m';
  }
  return '${duration.inMinutes}m';
}

Future<void> _openClassroomLink(CalendarEntry entry) async {
  final rawLink = entry.alternateLink;
  if (rawLink == null || rawLink.isEmpty) return;
  final uri = Uri.tryParse(rawLink);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _initialsForLabel(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'CLS';
  if (words.length == 1) {
    final end = words.first.length < 3 ? words.first.length : 3;
    return words.first.substring(0, end).toUpperCase();
  }
  return words.take(4).map((word) => word[0]).join().toUpperCase();
}

Color _classroomColor(String value) {
  const colors = [
    Color(0xFF6270EA),
    Color(0xFF4D91FF),
    Color(0xFF38A98D),
    Color(0xFFE4A93B),
    Color(0xFFE56F63),
    Color(0xFFDA6E98),
    Color(0xFF9273E5),
    Color(0xFF61708F),
  ];
  final normalized = value.trim();
  if (normalized.isEmpty) return colors.first;
  final index =
      normalized.runes.reduce((current, next) => current + next) %
      colors.length;
  return colors[index];
}
