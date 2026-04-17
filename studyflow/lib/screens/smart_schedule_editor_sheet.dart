import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/planner_item.dart';
import '../models/subject_record.dart';
import '../widgets/modal_sheet_header.dart';
import 'planner_item_editor_sheet.dart';

enum _SubjectInputMode { existing, custom }

class SmartScheduleEditorSheet extends StatefulWidget {
  const SmartScheduleEditorSheet({
    super.key,
    required this.controller,
    required this.initialItem,
    required this.subjects,
    required this.classroomSubjectNames,
    required this.onSave,
  });

  final AppController controller;
  final PlannerItem? initialItem;
  final List<SubjectRecord> subjects;
  final List<String> classroomSubjectNames;
  final Future<String> Function(PlannerItemDraft draft) onSave;

  @override
  State<SmartScheduleEditorSheet> createState() =>
      _SmartScheduleEditorSheetState();
}

class _SmartScheduleEditorSheetState extends State<SmartScheduleEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _customSubjectController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;
  late final TextEditingController _locationController;

  late _SubjectInputMode _subjectMode;
  late String? _selectedSubjectValue;
  late String _selectedCategory;
  late DateTime _startDate;
  late DateTime? _repeatUntil;
  late bool _reminderEnabled;
  late String _reminderLabel;
  late List<_EditableScheduleSlot> _slots;

  int _step = 0;
  bool _allowClose = false;
  bool _isSaving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialItem;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _customSubjectController = TextEditingController();
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _locationController = TextEditingController(text: initial?.location ?? '');
    _selectedCategory = initial?.categoryLabel ?? 'Class Session';
    _startDate = initial?.scheduledAt ?? DateTime.now();
    _repeatUntil = initial?.repeatUntil;
    _reminderEnabled = initial?.reminderEnabled ?? true;
    _reminderLabel =
        initial?.reminderLabel ?? widget.controller.lectureReminderDefault;
    _slots = _initialSlots(initial);
    _initializeSubjectSelection(initial);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customSubjectController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _allowClose || !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        final navigator = Navigator.of(context);
        final shouldClose = await _confirmDiscard();
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
                    title: widget.initialItem == null
                        ? 'Create Smart Schedule'
                        : 'Edit Smart Schedule',
                    onBack: _handleClosePressed,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Build a weekly class schedule one step at a time. Use saved subjects, Classroom labels, or a new subject name.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  _StepRail(step: _step),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: switch (_step) {
                        0 => _buildIdentityStep(context),
                        1 => _buildMeetingsStep(context),
                        _ => _buildReviewStep(context),
                      },
                    ),
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
                  Row(
                    children: [
                      if (_step > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : _previousStep,
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: _isSaving
                              ? null
                              : _step == 2
                              ? _submit
                              : _nextStep,
                          child: Text(
                            _isSaving
                                ? 'Saving...'
                                : _step == 2
                                ? 'Save Schedule'
                                : 'Next',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityStep(BuildContext context) {
    final choices = _subjectChoices;
    final hasExistingChoices = choices.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. Schedule identity',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _titleController,
          decoration: _fieldDecoration(context, 'Schedule title').copyWith(
            helperText: 'Example: IT 214 Lectures or Friday lab block',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Enter a schedule title.';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              selected: _subjectMode == _SubjectInputMode.existing,
              label: const Text('Select subject'),
              onSelected: hasExistingChoices
                  ? (_) {
                      setState(() {
                        _subjectMode = _SubjectInputMode.existing;
                        _selectedSubjectValue ??= choices.first.value;
                      });
                    }
                  : null,
            ),
            ChoiceChip(
              selected: _subjectMode == _SubjectInputMode.custom,
              label: const Text('Custom subject'),
              onSelected: (_) {
                setState(() {
                  _subjectMode = _SubjectInputMode.custom;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_subjectMode == _SubjectInputMode.existing && hasExistingChoices)
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedSubjectValue),
            isExpanded: true,
            initialValue: _selectedSubjectValue,
            items: choices
                .map(
                  (choice) => DropdownMenuItem(
                    value: choice.value,
                    child: Text(choice.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => choices
                .map(
                  (choice) => Text(
                    choice.label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                )
                .toList(),
            decoration: _fieldDecoration(context, 'Subject'),
            onChanged: (value) {
              setState(() {
                _selectedSubjectValue = value;
              });
            },
            validator: (value) {
              if (_subjectMode == _SubjectInputMode.existing &&
                  (value == null || value.isEmpty)) {
                return 'Choose a subject.';
              }
              return null;
            },
          )
        else
          TextFormField(
            controller: _customSubjectController,
            decoration: _fieldDecoration(context, 'Custom subject').copyWith(
              helperText:
                  'Use any subject name, including a Classroom course that is not saved manually.',
            ),
            validator: (value) {
              if (_subjectMode == _SubjectInputMode.custom &&
                  (value == null || value.trim().isEmpty)) {
                return 'Enter a custom subject.';
              }
              return null;
            },
          ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          items: _categoryOptions
              .map(
                (category) =>
                    DropdownMenuItem(value: category, child: Text(category)),
              )
              .toList(),
          decoration: _fieldDecoration(context, 'Schedule category'),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _selectedCategory = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildMeetingsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2. Weekly meetings',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Add every lecture block. Same-day multiple meetings are allowed.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        _PickerCard(
          label: 'Schedule starts',
          value: _fullDate(_startDate),
          onTap: _pickStartDate,
        ),
        const SizedBox(height: 12),
        _PickerCard(
          label: 'Repeat until',
          value: _repeatUntil == null
              ? 'No end date'
              : _fullDate(_repeatUntil!),
          onTap: _pickRepeatUntil,
        ),
        if (_repeatUntil != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() {
                  _repeatUntil = null;
                });
              },
              child: const Text('Clear end date'),
            ),
          ),
        const SizedBox(height: 16),
        ..._slots.asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ScheduleSlotCard(
              slot: entry.value,
              canDelete: _slots.length > 1,
              onWeekdayChanged: (weekday) => _updateSlot(
                entry.key,
                entry.value.copyWith(weekday: weekday),
              ),
              onStartTap: () => _pickSlotTime(entry.key, isStart: true),
              onEndTap: () => _pickSlotTime(entry.key, isStart: false),
              onDelete: () => _removeSlot(entry.key),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _addSlot,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add another meeting'),
        ),
      ],
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    final subject = _selectedSubjectLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '3. Review details',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        _SummaryCard(
          title: _titleController.text.trim().isEmpty
              ? 'Untitled schedule'
              : _titleController.text.trim(),
          subject: subject.isEmpty ? 'No subject selected' : subject,
          startDate: _fullDate(_startDate),
          repeatUntil: _repeatUntil == null
              ? 'No end date'
              : _fullDate(_repeatUntil!),
          slots: _sortedSlots
              .map((slot) => '${slot.weekdayLabel} ${slot.timeRangeLabel}')
              .toList(),
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _reminderEnabled,
          onChanged: (value) {
            setState(() {
              _reminderEnabled = value;
            });
          },
          title: const Text('Enable lecture reminder'),
        ),
        if (_reminderEnabled) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reminderLabel,
            items: _reminderOptionsForSelectedValue
                .map(
                  (label) => DropdownMenuItem(value: label, child: Text(label)),
                )
                .toList(),
            decoration: _fieldDecoration(context, 'Reminder timing'),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _reminderLabel = value;
              });
            },
          ),
        ],
        const SizedBox(height: 14),
        TextFormField(
          controller: _locationController,
          decoration: _fieldDecoration(context, 'Room or meeting link'),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _descriptionController,
          maxLines: 2,
          decoration: _fieldDecoration(context, 'Description'),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          decoration: _fieldDecoration(context, 'Notes'),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(BuildContext context, String label) {
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  void _initializeSubjectSelection(PlannerItem? initial) {
    final choices = _subjectChoices;
    final selectedManual = initial == null
        ? null
        : choices
              .where(
                (choice) =>
                    choice.subjectId == initial.subjectId &&
                    choice.source == _SubjectChoiceSource.manual,
              )
              .firstOrNull;
    final selectedClassroom = initial == null
        ? null
        : choices
              .where(
                (choice) =>
                    choice.name.toLowerCase() ==
                        (initial.subjectName ?? '').toLowerCase() &&
                    choice.source == _SubjectChoiceSource.classroom,
              )
              .firstOrNull;
    final selected = selectedManual ?? selectedClassroom;
    if (selected != null) {
      _subjectMode = _SubjectInputMode.existing;
      _selectedSubjectValue = selected.value;
      return;
    }

    if (initial?.subjectName != null && initial!.subjectName!.isNotEmpty) {
      _subjectMode = _SubjectInputMode.custom;
      _selectedSubjectValue = choices.firstOrNull?.value;
      _customSubjectController.text = initial.subjectName!;
      return;
    }

    _subjectMode = choices.isEmpty
        ? _SubjectInputMode.custom
        : _SubjectInputMode.existing;
    _selectedSubjectValue = choices.firstOrNull?.value;
  }

  List<_EditableScheduleSlot> _initialSlots(PlannerItem? initial) {
    if (initial != null && initial.scheduleSlots.isNotEmpty) {
      return initial.scheduleSlots
          .map(
            (slot) => _EditableScheduleSlot(
              id: slot.id,
              weekday: slot.weekday,
              startMinutes: slot.startMinutes,
              endMinutes: slot.endMinutes,
            ),
          )
          .toList();
    }

    final scheduledAt = initial?.scheduledAt;
    final endAt = initial?.endAt;
    if (scheduledAt != null) {
      final startMinutes = scheduledAt.hour * 60 + scheduledAt.minute;
      final endMinutes = endAt == null
          ? startMinutes + 60
          : endAt.hour * 60 + endAt.minute;
      return [
        _EditableScheduleSlot(
          id: 'slot-${DateTime.now().microsecondsSinceEpoch}',
          weekday: scheduledAt.weekday,
          startMinutes: startMinutes,
          endMinutes: endMinutes > startMinutes
              ? endMinutes
              : startMinutes + 60,
        ),
      ];
    }

    return [
      _EditableScheduleSlot(
        id: 'slot-${DateTime.now().microsecondsSinceEpoch}',
        weekday: DateTime.monday,
        startMinutes: 9 * 60,
        endMinutes: 11 * 60,
      ),
    ];
  }

  List<_SubjectChoice> get _subjectChoices {
    final choices = <_SubjectChoice>[
      ...widget.subjects.map(
        (subject) => _SubjectChoice(
          value: 'manual::${subject.id}',
          source: _SubjectChoiceSource.manual,
          subjectId: subject.id,
          name: subject.subjectName,
          label: '${subject.subjectCode} - ${subject.subjectName}',
        ),
      ),
    ];

    final manualNames = widget.subjects
        .map((subject) => subject.subjectName.toLowerCase())
        .toSet();
    final seenClassroomNames = <String>{};
    for (final name in widget.classroomSubjectNames) {
      final trimmed = name.trim();
      final normalized = trimmed.toLowerCase();
      if (trimmed.isEmpty ||
          manualNames.contains(normalized) ||
          !seenClassroomNames.add(normalized)) {
        continue;
      }
      choices.add(
        _SubjectChoice(
          value: 'classroom::${_normalizedSubjectKey(trimmed)}',
          source: _SubjectChoiceSource.classroom,
          subjectId: 'classroom::${_normalizedSubjectKey(trimmed)}',
          name: trimmed,
          label: '$trimmed (Classroom)',
        ),
      );
    }

    return choices;
  }

  List<_EditableScheduleSlot> get _sortedSlots {
    return [..._slots]..sort((a, b) {
      final dayCompare = a.weekday.compareTo(b.weekday);
      if (dayCompare != 0) {
        return dayCompare;
      }
      return a.startMinutes.compareTo(b.startMinutes);
    });
  }

  List<String> get _categoryOptions {
    const defaults = [
      'Class Session',
      'Lecture',
      'Laboratory',
      'Review Block',
      'Study Session',
    ];
    if (defaults.contains(_selectedCategory)) {
      return defaults;
    }
    return [_selectedCategory, ...defaults];
  }

  List<String> get _reminderOptionsForSelectedValue {
    if (_reminderOptions.contains(_reminderLabel)) {
      return _reminderOptions;
    }
    return [_reminderLabel, ..._reminderOptions];
  }

  String get _selectedSubjectLabel {
    if (_subjectMode == _SubjectInputMode.custom) {
      return _customSubjectController.text.trim();
    }

    final selected = _subjectChoices
        .where((choice) => choice.value == _selectedSubjectValue)
        .firstOrNull;
    return selected?.name ?? '';
  }

  String get _selectedSubjectId {
    if (_subjectMode == _SubjectInputMode.custom) {
      return 'custom::${_normalizedSubjectKey(_customSubjectController.text)}';
    }

    final selected = _subjectChoices
        .where((choice) => choice.value == _selectedSubjectValue)
        .firstOrNull;
    return selected?.subjectId ??
        'custom::${_normalizedSubjectKey(_selectedSubjectLabel)}';
  }

  bool get _isDirty {
    final initial = widget.initialItem;
    return _titleController.text.trim() != (initial?.title ?? '') ||
        _descriptionController.text.trim() != (initial?.description ?? '') ||
        _notesController.text.trim() != (initial?.notes ?? '') ||
        _locationController.text.trim() != (initial?.location ?? '') ||
        _selectedSubjectLabel != (initial?.subjectName ?? '') ||
        _selectedCategory != (initial?.categoryLabel ?? 'Class Session') ||
        _repeatUntil != initial?.repeatUntil ||
        _reminderEnabled != (initial?.reminderEnabled ?? true) ||
        _reminderLabel !=
            (initial?.reminderLabel ??
                widget.controller.lectureReminderDefault) ||
        _slots.length != (initial?.scheduleSlots.length ?? 0);
  }

  void _nextStep() {
    setState(() {
      _formError = null;
    });

    if (_step == 0 && !_formKey.currentState!.validate()) {
      return;
    }
    if (_step == 1 && !_validateSlots()) {
      return;
    }

    setState(() {
      _step += 1;
    });
  }

  void _previousStep() {
    setState(() {
      _formError = null;
      _step -= 1;
    });
  }

  bool _validateSlots() {
    if (_slots.isEmpty) {
      setState(() {
        _formError = 'Add at least one weekly meeting.';
      });
      return false;
    }
    final invalid = _slots.any((slot) => slot.endMinutes <= slot.startMinutes);
    if (invalid) {
      setState(() {
        _formError = 'Each meeting must end after it starts.';
      });
      return false;
    }
    return true;
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _startDate = picked;
      if (_repeatUntil != null && _repeatUntil!.isBefore(_startDate)) {
        _repeatUntil = null;
      }
    });
  }

  Future<void> _pickRepeatUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _repeatUntil ?? _startDate.add(const Duration(days: 120)),
      firstDate: _startDate,
      lastDate: DateTime(2035),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _repeatUntil = picked;
    });
  }

  Future<void> _pickSlotTime(int index, {required bool isStart}) async {
    final slot = _slots[index];
    final initialMinutes = isStart ? slot.startMinutes : slot.endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinutes ~/ 60,
        minute: initialMinutes % 60,
      ),
    );
    if (picked == null) {
      return;
    }

    final minutes = picked.hour * 60 + picked.minute;
    var next = isStart
        ? slot.copyWith(startMinutes: minutes)
        : slot.copyWith(endMinutes: minutes);
    if (isStart && next.endMinutes <= minutes) {
      next = next.copyWith(endMinutes: (minutes + 60).clamp(1, 24 * 60));
    }
    _updateSlot(index, next);
  }

  void _addSlot() {
    final last = _slots.isEmpty ? null : _slots.last;
    final start = last == null
        ? 9 * 60
        : (last.endMinutes + 60).clamp(0, 22 * 60);
    setState(() {
      _slots = [
        ..._slots,
        _EditableScheduleSlot(
          id: 'slot-${DateTime.now().microsecondsSinceEpoch}',
          weekday: last?.weekday ?? DateTime.monday,
          startMinutes: start,
          endMinutes: (start + 60).clamp(1, 24 * 60),
        ),
      ];
    });
  }

  void _updateSlot(int index, _EditableScheduleSlot slot) {
    setState(() {
      _slots = [..._slots]..[index] = slot;
    });
  }

  void _removeSlot(int index) {
    if (_slots.length == 1) {
      return;
    }
    setState(() {
      _slots = [..._slots]..removeAt(index);
    });
  }

  Future<void> _handleClosePressed() async {
    final shouldClose = await _confirmDiscard();
    if (!shouldClose || !mounted) {
      return;
    }
    setState(() {
      _allowClose = true;
    });
    Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) {
      return true;
    }

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Discard schedule?'),
          content: const Text(
            'Your Smart Schedule changes have not been saved.',
          ),
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

  Future<void> _submit() async {
    setState(() {
      _formError = null;
    });

    if (_titleController.text.trim().isEmpty) {
      setState(() {
        _step = 0;
        _formError = 'Enter a schedule title.';
      });
      return;
    }
    if (_selectedSubjectLabel.isEmpty) {
      setState(() {
        _step = 0;
        _formError = 'Choose or enter a subject.';
      });
      return;
    }
    if (!_validateSlots()) {
      setState(() {
        _step = 1;
      });
      return;
    }

    final slots = _sortedSlots
        .map(
          (slot) => PlannerScheduleSlot(
            id: slot.id,
            weekday: slot.weekday,
            startMinutes: slot.startMinutes,
            endMinutes: slot.endMinutes,
          ),
        )
        .toList();
    final firstOccurrence = _firstOccurrenceOnOrAfter(_startDate, slots);
    final firstSlot = slots.firstWhere(
      (slot) =>
          slot.weekday == firstOccurrence.weekday &&
          slot.startMinutes ==
              firstOccurrence.hour * 60 + firstOccurrence.minute,
      orElse: () => slots.first,
    );
    final endAt = DateTime(
      firstOccurrence.year,
      firstOccurrence.month,
      firstOccurrence.day,
      firstSlot.endMinutes ~/ 60,
      firstSlot.endMinutes % 60,
    );

    setState(() {
      _isSaving = true;
    });

    try {
      final message = await widget.onSave(
        PlannerItemDraft(
          title: _titleController.text.trim(),
          subjectId: _selectedSubjectId,
          subjectName: _selectedSubjectLabel,
          type: PlannerItemType.schedule,
          priority: PlannerItemPriority.medium,
          status: widget.initialItem?.status ?? PlannerItemStatus.active,
          categoryLabel: _selectedCategory,
          description: _nullableTrimmed(_descriptionController.text),
          notes: _nullableTrimmed(_notesController.text),
          location: _nullableTrimmed(_locationController.text),
          scheduledAt: firstOccurrence,
          endAt: endAt.isAfter(firstOccurrence) ? endAt : null,
          hasExplicitTime: true,
          reminderEnabled: _reminderEnabled,
          reminderLabel: _reminderEnabled ? _reminderLabel : null,
          repeatPattern: PlannerRepeatPattern.weekly,
          repeatUntil: _repeatUntil,
          scheduleSlots: slots,
          autoCompleteFromSubtasks: false,
          subtasks: const <PlannerSubtask>[],
        ),
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = 'StudyFlow could not save this Smart Schedule right now.';
      });
    }
  }

  String? _nullableTrimmed(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final labels = const ['Subject', 'Meetings', 'Review'];
    return Row(
      children: labels.asMap().entries.map((entry) {
        final isActive = entry.key == step;
        final isDone = entry.key < step;
        final color = isActive || isDone
            ? const Color(0xFF3BAE90)
            : Theme.of(context).dividerColor;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: EdgeInsets.only(
              right: entry.key == labels.length - 1 ? 0 : 8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isActive ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              labels[entry.key],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isActive || isDone ? const Color(0xFF1E705A) : null,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ScheduleSlotCard extends StatelessWidget {
  const _ScheduleSlotCard({
    required this.slot,
    required this.canDelete,
    required this.onWeekdayChanged,
    required this.onStartTap,
    required this.onEndTap,
    required this.onDelete,
  });

  final _EditableScheduleSlot slot;
  final bool canDelete;
  final ValueChanged<int> onWeekdayChanged;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF182134)
            : const Color(0xFFF5F7FC),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: slot.weekday,
                  items: _weekdays
                      .map(
                        (day) => DropdownMenuItem(
                          value: day.value,
                          child: Text(day.label),
                        ),
                      )
                      .toList(),
                  decoration: const InputDecoration(
                    labelText: 'Day',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      onWeekdayChanged(value);
                    }
                  },
                ),
              ),
              IconButton(
                onPressed: canDelete ? onDelete : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PickerCard(
                  label: 'Starts',
                  value: _formatMinutes(slot.startMinutes),
                  onTap: onStartTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickerCard(
                  label: 'Ends',
                  value: _formatMinutes(slot.endMinutes),
                  onTap: onEndTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
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
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF111827)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.subject,
    required this.startDate,
    required this.repeatUntil,
    required this.slots,
  });

  final String title;
  final String subject;
  final String startDate;
  final String repeatUntil;
  final List<String> slots;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF172236)
        : const Color(0xFFF4F7FC);
    final border = isDark ? const Color(0xFF2C3B56) : const Color(0xFFDCE5F2);
    final secondary = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: isDark ? 0.78 : 0.72);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subject,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: secondary),
          ),
          const SizedBox(height: 12),
          Text(
            'Starts $startDate • $repeatUntil',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: secondary),
          ),
          const SizedBox(height: 10),
          ...slots.map(
            (slot) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      slot,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableScheduleSlot {
  const _EditableScheduleSlot({
    required this.id,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
  });

  final String id;
  final int weekday;
  final int startMinutes;
  final int endMinutes;

  String get weekdayLabel {
    return _weekdays.where((day) => day.value == weekday).firstOrNull?.label ??
        'Day $weekday';
  }

  String get timeRangeLabel {
    return '${_formatMinutes(startMinutes)}-${_formatMinutes(endMinutes)}';
  }

  _EditableScheduleSlot copyWith({
    String? id,
    int? weekday,
    int? startMinutes,
    int? endMinutes,
  }) {
    return _EditableScheduleSlot(
      id: id ?? this.id,
      weekday: weekday ?? this.weekday,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
    );
  }
}

enum _SubjectChoiceSource { manual, classroom }

class _SubjectChoice {
  const _SubjectChoice({
    required this.value,
    required this.source,
    required this.subjectId,
    required this.name,
    required this.label,
  });

  final String value;
  final _SubjectChoiceSource source;
  final String subjectId;
  final String name;
  final String label;
}

DateTime _firstOccurrenceOnOrAfter(
  DateTime startDate,
  List<PlannerScheduleSlot> slots,
) {
  final sorted = [...slots]
    ..sort((a, b) {
      final dayCompare = a.weekday.compareTo(b.weekday);
      if (dayCompare != 0) {
        return dayCompare;
      }
      return a.startMinutes.compareTo(b.startMinutes);
    });

  for (var offset = 0; offset < 8; offset += 1) {
    final day = startDate.add(Duration(days: offset));
    final matches = sorted.where((slot) => slot.weekday == day.weekday);
    for (final slot in matches) {
      return DateTime(
        day.year,
        day.month,
        day.day,
        slot.startMinutes ~/ 60,
        slot.startMinutes % 60,
      );
    }
  }

  final fallback = sorted.first;
  return DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    fallback.startMinutes ~/ 60,
    fallback.startMinutes % 60,
  );
}

String _normalizedSubjectKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
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

String _formatMinutes(int minutes) {
  final hour24 = minutes ~/ 60;
  final minute = minutes % 60;
  final hour = hour24 == 0
      ? 12
      : hour24 > 12
      ? hour24 - 12
      : hour24;
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  if (minute == 0) {
    return '$hour$suffix';
  }
  return '$hour:${minute.toString().padLeft(2, '0')}$suffix';
}

const _weekdays = [
  (value: DateTime.monday, label: 'Monday'),
  (value: DateTime.tuesday, label: 'Tuesday'),
  (value: DateTime.wednesday, label: 'Wednesday'),
  (value: DateTime.thursday, label: 'Thursday'),
  (value: DateTime.friday, label: 'Friday'),
  (value: DateTime.saturday, label: 'Saturday'),
  (value: DateTime.sunday, label: 'Sunday'),
];

const List<String> _reminderOptions = [
  '10m before',
  '15m before',
  '30m before',
  '1h before',
  '1 day before',
  '2 days before',
];

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
