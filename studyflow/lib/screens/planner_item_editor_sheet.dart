import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/planner_item.dart';
import '../models/reminder_presets.dart';
import '../models/subject_record.dart';
import '../widgets/modal_sheet_header.dart';

enum _SubjectInputMode { existing, custom }

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

class PlannerItemDraft {
  const PlannerItemDraft({
    required this.title,
    required this.subjectId,
    required this.subjectName,
    required this.type,
    required this.priority,
    required this.status,
    required this.categoryLabel,
    required this.scheduledAt,
    required this.hasExplicitTime,
    required this.reminderEnabled,
    required this.repeatPattern,
    required this.autoCompleteFromSubtasks,
    required this.subtasks,
    this.scheduleSlots = const <PlannerScheduleSlot>[],
    this.description,
    this.notes,
    this.location,
    this.endAt,
    this.reminderLabel,
    this.repeatUntil,
  });

  final String title;
  final String subjectId;
  final String subjectName;
  final PlannerItemType type;
  final PlannerItemPriority priority;
  final PlannerItemStatus status;
  final String categoryLabel;
  final String? description;
  final String? notes;
  final String? location;
  final DateTime scheduledAt;
  final DateTime? endAt;
  final bool hasExplicitTime;
  final bool reminderEnabled;
  final String? reminderLabel;
  final PlannerRepeatPattern repeatPattern;
  final DateTime? repeatUntil;
  final List<PlannerScheduleSlot> scheduleSlots;
  final bool autoCompleteFromSubtasks;
  final List<PlannerSubtask> subtasks;

  String get typeLabel {
    switch (type) {
      case PlannerItemType.task:
        return 'Task';
      case PlannerItemType.project:
        return 'Project';
      case PlannerItemType.exam:
        return 'Exam';
      case PlannerItemType.schedule:
        return 'Schedule';
    }
  }
}

class PlannerItemEditorSheet extends StatefulWidget {
  const PlannerItemEditorSheet({
    super.key,
    required this.controller,
    required this.initialItem,
    required this.initialType,
    required this.initialDate,
    required this.subjects,
    required this.onSave,
  });

  final AppController controller;
  final PlannerItem? initialItem;
  final PlannerItemType? initialType;
  final DateTime? initialDate;
  final List<SubjectRecord> subjects;
  final Future<String> Function(PlannerItemDraft draft) onSave;

  @override
  State<PlannerItemEditorSheet> createState() => _PlannerItemEditorSheetState();
}

class _PlannerItemEditorSheetState extends State<PlannerItemEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _customSubjectController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;
  late final TextEditingController _locationController;
  late PlannerItemType _selectedType;
  late PlannerItemPriority _selectedPriority;
  late PlannerItemStatus _selectedStatus;
  late String _selectedSubjectId;
  late String _subjectText;
  late _SubjectInputMode _subjectMode;
  late String _selectedCategory;
  late bool _reminderEnabled;
  late String _reminderLabel;
  late PlannerRepeatPattern _repeatPattern;
  late DateTime? _scheduledDate;
  late DateTime? _repeatUntil;
  late TimeOfDay? _selectedTime;
  late TimeOfDay? _selectedEndTime;
  late bool _hasExplicitTime;
  late bool _autoCompleteFromSubtasks;
  late List<_EditableSubtaskDraft> _subtasks;
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
    _selectedType = initial?.type ?? widget.initialType ?? PlannerItemType.task;
    _selectedPriority = initial?.priority ?? PlannerItemPriority.medium;
    _selectedStatus = initial?.status ?? PlannerItemStatus.active;
    _selectedSubjectId =
        initial?.subjectId ?? widget.subjects.firstOrNull?.id ?? '';
    _subjectText =
        initial?.subjectName ??
        widget.subjects
            .where((subject) => subject.id == _selectedSubjectId)
            .firstOrNull
            ?.subjectName ??
        '';
    _initializeSubjectSelection(initial);
    _selectedCategory =
        initial?.categoryLabel ?? _defaultCategoryForType(_selectedType);
    _reminderEnabled = initial?.reminderEnabled ?? true;
    _reminderLabel =
        initial?.reminderLabel ?? _defaultReminderForType(_selectedType);
    _repeatPattern = initial?.repeatPattern ?? PlannerRepeatPattern.none;
    _scheduledDate =
        initial?.scheduledAt ?? widget.initialDate ?? DateTime.now();
    _repeatUntil = initial?.repeatUntil;
    _selectedTime = initial?.scheduledAt == null
        ? null
        : TimeOfDay.fromDateTime(initial!.scheduledAt!);
    _selectedEndTime = initial?.endAt == null
        ? null
        : TimeOfDay.fromDateTime(initial!.endAt!);
    _hasExplicitTime =
        initial?.hasExplicitTime ??
        (_selectedType != PlannerItemType.task &&
            _selectedType != PlannerItemType.project);
    _autoCompleteFromSubtasks = initial?.autoCompleteFromSubtasks ?? true;
    _subtasks = (initial?.subtasks ?? const <PlannerSubtask>[])
        .map(
          (subtask) => _EditableSubtaskDraft(
            id: subtask.id,
            controller: TextEditingController(text: subtask.title),
            isCompleted: subtask.isCompleted,
            completedAt: subtask.completedAt,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customSubjectController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    for (final draft in _subtasks) {
      draft.controller.dispose();
    }
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
                        ? 'Create Item'
                        : 'Edit Item',
                    onBack: _handleClosePressed,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This form supports subject linkage, reminders, repetition, subtasks, and schedule visibility.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  _PlannerStepRail(step: _step),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: switch (_step) {
                        0 => _buildBasicsStep(context),
                        1 => _buildTimingStep(context),
                        2 => _buildDetailsStep(context),
                        _ => _buildSubtasksStep(context),
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
                              : _step == 3
                              ? _submit
                              : _nextStep,
                          child: Text(
                            _isSaving
                                ? 'Saving...'
                                : _step == 3
                                ? 'Save Item'
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

  Widget _buildBasicsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('1. Basics', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        DropdownButtonFormField<PlannerItemType>(
          initialValue: _selectedType,
          items: _typeOptions
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(switch (type) {
                    PlannerItemType.task => 'Task',
                    PlannerItemType.project => 'Project',
                    PlannerItemType.exam => 'Exams & Quizzes',
                    PlannerItemType.schedule => 'Smart Schedule',
                  }),
                ),
              )
              .toList(),
          decoration: _fieldDecoration(context, 'Item type'),
          onChanged: _isClassroomBacked
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedType = value;
                    _selectedCategory = _defaultCategoryForType(value);
                    if (value == PlannerItemType.schedule ||
                        value == PlannerItemType.exam) {
                      _hasExplicitTime = true;
                    }
                    if (value != PlannerItemType.schedule) {
                      _repeatPattern = PlannerRepeatPattern.none;
                      _repeatUntil = null;
                    }
                  });
                },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _titleController,
          readOnly: _isClassroomBacked,
          decoration:
              _fieldDecoration(
                context,
                _selectedType == PlannerItemType.exam
                    ? 'Exam or quiz title'
                    : 'Title',
              ).copyWith(
                helperText: _isClassroomBacked
                    ? 'Classroom titles stay locked to the teacher-provided task.'
                    : null,
              ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Enter a title.';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _buildSubjectField(context),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          items: _categoryOptions
              .map(
                (category) =>
                    DropdownMenuItem(value: category, child: Text(category)),
              )
              .toList(),
          decoration: _fieldDecoration(context, 'Category'),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedCategory = value;
            });
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<PlannerItemPriority>(
          initialValue: _selectedPriority,
          items: PlannerItemPriority.values
              .map(
                (priority) => DropdownMenuItem(
                  value: priority,
                  child: Text(switch (priority) {
                    PlannerItemPriority.high => 'High',
                    PlannerItemPriority.medium => 'Medium',
                    PlannerItemPriority.low => 'Low',
                    PlannerItemPriority.optional => 'Optional',
                  }),
                ),
              )
              .toList(),
          decoration: _fieldDecoration(context, 'Priority'),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedPriority = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSubjectField(BuildContext context) {
    if (_isClassroomBacked) {
      return TextFormField(
        initialValue: _subjectText,
        readOnly: true,
        decoration: _fieldDecoration(context, 'Linked subject').copyWith(
          helperText:
              'Classroom-linked subjects are locked for imported tasks.',
        ),
      );
    }

    final hasSubjects = widget.subjects.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              selected: _subjectMode == _SubjectInputMode.existing,
              label: const Text('Existing subject'),
              onSelected: hasSubjects
                  ? (_) {
                      setState(() {
                        _subjectMode = _SubjectInputMode.existing;
                        _selectedSubjectId = _existingSubjectDropdownValue;
                        _subjectText = _selectedSubjectLabel;
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
                  _subjectText = _customSubjectController.text.trim();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_subjectMode == _SubjectInputMode.existing && hasSubjects)
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _existingSubjectDropdownValue,
            items: widget.subjects
                .map(
                  (subject) => DropdownMenuItem(
                    value: subject.id,
                    child: Text(
                      '${subject.subjectCode} - ${subject.subjectName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => widget.subjects
                .map(
                  (subject) => Text(
                    '${subject.subjectCode} - ${subject.subjectName}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                )
                .toList(),
            decoration: _fieldDecoration(context, 'Linked subject'),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedSubjectId = value;
                _subjectText = _selectedSubjectLabel;
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
                  'Use a subject that is not in your saved subject list.',
            ),
            onChanged: (value) {
              _subjectText = value.trim();
              _selectedSubjectId = '';
            },
            validator: (value) {
              if (_subjectMode == _SubjectInputMode.custom &&
                  (value == null || value.trim().isEmpty)) {
                return 'Enter a subject name.';
              }
              return null;
            },
          ),
      ],
    );
  }

  Widget _buildTimingStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2. $_dateStepLabel',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (_isClassroomBacked)
          Text(
            'Classroom due dates are locked to the teacher-provided schedule.',
            style: Theme.of(context).textTheme.bodyLarge,
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _QuickDateChip(label: 'Today', onTap: () => _setQuickDate(0)),
              _QuickDateChip(label: 'Tomorrow', onTap: () => _setQuickDate(1)),
              _QuickDateChip(label: 'Next Week', onTap: () => _setQuickDate(7)),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _PickerCard(
                label: _selectedType == PlannerItemType.exam
                    ? _dateStepLabel
                    : 'Due date',
                value: _scheduledDate == null
                    ? 'Select date'
                    : _fullDate(_scheduledDate!),
                onTap: _isClassroomBacked ? null : _pickDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PickerCard(
                label: 'Time',
                value: _selectedTime == null
                    ? 'No time set'
                    : _selectedTime!.format(context),
                onTap: _isClassroomBacked ? null : _pickTime,
              ),
            ),
          ],
        ),
        if (!_isClassroomBacked &&
            (_selectedType == PlannerItemType.task ||
                _selectedType == PlannerItemType.project))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hasExplicitTime,
            onChanged: (value) {
              setState(() {
                _hasExplicitTime = value;
                if (!value) {
                  _selectedTime = null;
                }
              });
            },
            title: const Text('Include an exact due time'),
          ),
        if (_selectedType == PlannerItemType.exam) ...[
          const SizedBox(height: 10),
          _PickerCard(
            label: 'End time',
            value: _selectedEndTime == null
                ? 'Optional'
                : _selectedEndTime!.format(context),
            onTap: _isClassroomBacked ? null : _pickEndTime,
          ),
        ],
      ],
    );
  }

  Widget _buildDetailsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('3. Details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _reminderEnabled,
          onChanged: (value) {
            setState(() {
              _reminderEnabled = value;
            });
          },
          title: const Text('Enable reminder'),
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
              if (value == null) return;
              setState(() {
                _reminderLabel = value;
              });
            },
          ),
        ],
        const SizedBox(height: 14),
        TextFormField(
          controller: _descriptionController,
          readOnly: _isClassroomBacked,
          minLines: 5,
          maxLines: 8,
          decoration: _fieldDecoration(context, 'Description').copyWith(
            helperText: _isClassroomBacked
                ? 'Classroom descriptions stay locked to the teacher-provided task.'
                : null,
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _notesController,
          minLines: 5,
          maxLines: 9,
          decoration: _fieldDecoration(context, 'Notes'),
        ),
        if (_selectedType == PlannerItemType.exam) ...[
          const SizedBox(height: 14),
          TextFormField(
            controller: _locationController,
            decoration: _fieldDecoration(context, 'Room/Location'),
          ),
        ],
      ],
    );
  }

  Widget _buildSubtasksStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('4. Subtasks', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: _addSubtask,
              child: const Text('Add subtask'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Break the work into smaller steps. Completing all subtasks can complete the parent item automatically.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        if (_subtasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF182134)
                  : const Color(0xFFF5F7FC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text('No subtasks added yet.'),
          )
        else
          ..._subtasks.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: entry.value.controller,
                      decoration: _fieldDecoration(
                        context,
                        'Subtask ${entry.key + 1}',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeSubtask(entry.key),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _autoCompleteFromSubtasks,
          onChanged: (value) {
            setState(() {
              _autoCompleteFromSubtasks = value;
            });
          },
          title: const Text(
            'Complete this item automatically when all subtasks are done',
          ),
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

  List<String> _categoriesForType(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.task:
        return const [
          'Assignment',
          'Project',
          'Milestone',
          'Final Output',
          'Reading',
          'Study Task',
          'Research',
          'Other',
        ];
      case PlannerItemType.project:
        return const ['Project', 'Milestone', 'Final Output', 'Portfolio'];
      case PlannerItemType.exam:
        return const ['Exam', 'Quiz', 'Presentation', 'Consultation'];
      case PlannerItemType.schedule:
        return const ['Class Session', 'Review Block', 'Study Session', 'Lab'];
    }
  }

  String _defaultCategoryForType(PlannerItemType type) {
    return _categoriesForType(type).first;
  }

  List<String> get _categoryOptions {
    final defaults = _categoriesForType(_selectedType);
    if (defaults.contains(_selectedCategory)) {
      return defaults;
    }
    return [_selectedCategory, ...defaults];
  }

  String get _existingSubjectDropdownValue {
    if (widget.subjects.isEmpty) {
      return '';
    }
    if (widget.subjects.any((subject) => subject.id == _selectedSubjectId)) {
      return _selectedSubjectId;
    }
    return widget.subjects.first.id;
  }

  bool get _isClassroomBacked {
    final initial = widget.initialItem;
    return initial?.id.startsWith('classroom::') == true ||
        (initial?.sourceItemId ?? '').isNotEmpty;
  }

  String get _selectedSubjectLabel {
    if (_subjectMode == _SubjectInputMode.custom) {
      return _customSubjectController.text.trim();
    }

    final effectiveSubjectId = _existingSubjectDropdownValue;
    final subject =
        widget.subjects
            .where((subject) => subject.id == _selectedSubjectId)
            .firstOrNull ??
        widget.subjects
            .where((subject) => subject.id == effectiveSubjectId)
            .firstOrNull;
    return subject?.subjectName ?? _subjectText.trim();
  }

  String get _effectiveSubjectId {
    if (_isClassroomBacked) {
      return _selectedSubjectId.isEmpty
          ? 'classroom::${_normalizedSubjectKey(_subjectText)}'
          : _selectedSubjectId;
    }

    if (_subjectMode == _SubjectInputMode.custom) {
      return 'custom::${_normalizedSubjectKey(_customSubjectController.text)}';
    }

    final existingSubjectId = _existingSubjectDropdownValue;
    return existingSubjectId.isEmpty
        ? 'custom::${_normalizedSubjectKey(_selectedSubjectLabel)}'
        : existingSubjectId;
  }

  String get _effectiveSubjectName {
    if (_isClassroomBacked) {
      return _subjectText.trim();
    }
    return _selectedSubjectLabel;
  }

  List<PlannerItemType> get _typeOptions {
    const defaults = [PlannerItemType.task, PlannerItemType.exam];
    if (_selectedType == PlannerItemType.project) {
      return [PlannerItemType.project, ...defaults];
    }
    if (_selectedType == PlannerItemType.schedule) {
      return [PlannerItemType.schedule, ...defaults];
    }
    return defaults;
  }

  String get _dateStepLabel {
    if (_selectedType != PlannerItemType.exam) {
      return 'Due date';
    }

    return '${_selectedCategory.trim().isEmpty ? 'Exam' : _selectedCategory} date';
  }

  List<String> get _reminderOptionsForSelectedValue {
    final options = _reminderOptionsForType(_selectedType);
    if (options.contains(_reminderLabel)) {
      return options;
    }
    return [_reminderLabel, ...options];
  }

  void _initializeSubjectSelection(PlannerItem? initial) {
    final hasManualSubject =
        initial != null &&
        widget.subjects.any((subject) => subject.id == initial.subjectId);

    if (_isClassroomBacked) {
      _subjectMode = _SubjectInputMode.custom;
      _customSubjectController.text = _subjectText;
      return;
    }

    if (hasManualSubject || (initial == null && widget.subjects.isNotEmpty)) {
      _subjectMode = _SubjectInputMode.existing;
      if (_selectedSubjectId.isEmpty && widget.subjects.isNotEmpty) {
        _selectedSubjectId = widget.subjects.first.id;
        _subjectText = widget.subjects.first.subjectName;
      }
      return;
    }

    _subjectMode = _SubjectInputMode.custom;
    _customSubjectController.text = _subjectText;
  }

  String _defaultReminderForType(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.task:
      case PlannerItemType.project:
        return widget.controller.taskReminderDefault;
      case PlannerItemType.exam:
        return widget.controller.examReminderDefault;
      case PlannerItemType.schedule:
        return widget.controller.lectureReminderDefault;
    }
  }

  List<String> _reminderOptionsForType(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.task:
      case PlannerItemType.project:
        return taskReminderOptions;
      case PlannerItemType.exam:
        return examReminderOptions;
      case PlannerItemType.schedule:
        return lectureReminderOptions;
    }
  }

  Future<void> _pickDate() async {
    final initialDate = _scheduledDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      _scheduledDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _selectedTime?.hour ?? 0,
        _selectedTime?.minute ?? 0,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      _selectedTime = picked;
      _hasExplicitTime = true;
      if (_scheduledDate != null) {
        _scheduledDate = DateTime(
          _scheduledDate!.year,
          _scheduledDate!.month,
          _scheduledDate!.day,
          picked.hour,
          picked.minute,
        );
      }
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedEndTime ?? _selectedTime ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      _selectedEndTime = picked;
    });
  }

  void _setQuickDate(int offsetDays) {
    final date = DateTime.now().add(Duration(days: offsetDays));
    setState(() {
      _scheduledDate = DateTime(
        date.year,
        date.month,
        date.day,
        _selectedTime?.hour ?? 0,
        _selectedTime?.minute ?? 0,
      );
    });
  }

  void _addSubtask() {
    setState(() {
      _subtasks = [
        ..._subtasks,
        _EditableSubtaskDraft(
          id: 'subtask-${DateTime.now().microsecondsSinceEpoch}',
          controller: TextEditingController(),
        ),
      ];
    });
  }

  void _removeSubtask(int index) {
    final draft = _subtasks[index];
    draft.controller.dispose();
    setState(() {
      _subtasks = List<_EditableSubtaskDraft>.from(_subtasks)..removeAt(index);
    });
  }

  void _nextStep() {
    setState(() {
      _formError = null;
    });

    if (!_validateCurrentStep()) {
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

  bool _validateCurrentStep() {
    if (_step == 0 && !_formKey.currentState!.validate()) {
      return false;
    }

    if (_step == 1) {
      if (_scheduledDate == null) {
        setState(() {
          _formError = 'Choose a valid date first.';
        });
        return false;
      }

      if (_selectedType == PlannerItemType.exam && _selectedTime == null) {
        setState(() {
          _formError = 'Time is required for exams and quizzes.';
        });
        return false;
      }
    }

    return true;
  }

  bool get _isDirty {
    final initial = widget.initialItem;
    final initialType =
        initial?.type ?? widget.initialType ?? PlannerItemType.task;
    return _titleController.text.trim() != (initial?.title ?? '') ||
        _descriptionController.text.trim() != (initial?.description ?? '') ||
        _notesController.text.trim() != (initial?.notes ?? '') ||
        _locationController.text.trim() != (initial?.location ?? '') ||
        _selectedType != initialType ||
        _selectedPriority !=
            (initial?.priority ?? PlannerItemPriority.medium) ||
        _selectedStatus != (initial?.status ?? PlannerItemStatus.active) ||
        _selectedSubjectId !=
            (initial?.subjectId ?? widget.subjects.firstOrNull?.id ?? '') ||
        _subjectText !=
            (initial?.subjectName ??
                widget.subjects
                    .where(
                      (subject) =>
                          subject.id ==
                          (initial?.subjectId ??
                              widget.subjects.firstOrNull?.id ??
                              ''),
                    )
                    .firstOrNull
                    ?.subjectName ??
                '') ||
        _selectedCategory !=
            (initial?.categoryLabel ?? _defaultCategoryForType(initialType)) ||
        _reminderEnabled != (initial?.reminderEnabled ?? true) ||
        _reminderLabel !=
            (initial?.reminderLabel ?? _defaultReminderForType(initialType)) ||
        _repeatPattern !=
            (initial?.repeatPattern ?? PlannerRepeatPattern.none) ||
        _scheduledDate != initial?.scheduledAt ||
        _repeatUntil != initial?.repeatUntil ||
        _selectedTime !=
            (initial?.scheduledAt == null
                ? null
                : TimeOfDay.fromDateTime(initial!.scheduledAt!)) ||
        _selectedEndTime !=
            (initial?.endAt == null
                ? null
                : TimeOfDay.fromDateTime(initial!.endAt!)) ||
        _hasExplicitTime !=
            (initial?.hasExplicitTime ??
                (initialType != PlannerItemType.task &&
                    initialType != PlannerItemType.project)) ||
        _autoCompleteFromSubtasks !=
            (initial?.autoCompleteFromSubtasks ?? true) ||
        _subtasks.length != (initial?.subtasks.length ?? 0);
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
          title: const Text('Discard changes?'),
          content: const Text('Your planner edits have not been saved yet.'),
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
        _formError = 'Enter a title.';
      });
      return;
    }

    if (_effectiveSubjectName.trim().isEmpty) {
      setState(() {
        _step = 0;
        _formError = 'Choose or enter a linked subject.';
      });
      return;
    }

    if (_scheduledDate == null) {
      setState(() {
        _step = 1;
        _formError = 'Choose a valid date first.';
      });
      return;
    }

    if (_selectedType == PlannerItemType.exam && _selectedTime == null) {
      setState(() {
        _step = 1;
        _formError = 'Time is required for exams and quizzes.';
      });
      return;
    }

    final scheduledAt = DateTime(
      _scheduledDate!.year,
      _scheduledDate!.month,
      _scheduledDate!.day,
      _hasExplicitTime ? (_selectedTime?.hour ?? 0) : 0,
      _hasExplicitTime ? (_selectedTime?.minute ?? 0) : 0,
    );

    DateTime? endAt;
    if (_selectedEndTime != null) {
      endAt = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _selectedEndTime!.hour,
        _selectedEndTime!.minute,
      );
      if (!endAt.isAfter(scheduledAt)) {
        endAt = endAt.add(const Duration(days: 1));
      }
    }

    final subtasks = _subtasks
        .where((draft) => draft.controller.text.trim().isNotEmpty)
        .map(
          (draft) => PlannerSubtask(
            id: draft.id,
            title: draft.controller.text.trim(),
            isCompleted: draft.isCompleted,
            completedAt: draft.completedAt,
          ),
        )
        .toList();

    setState(() {
      _isSaving = true;
    });

    try {
      final message = await widget.onSave(
        PlannerItemDraft(
          title: _titleController.text.trim(),
          subjectId: _effectiveSubjectId,
          subjectName: _effectiveSubjectName,
          type: _selectedType,
          priority: _selectedPriority,
          status: _selectedStatus,
          categoryLabel: _selectedCategory,
          description: _nullableTrimmed(_descriptionController.text),
          notes: _nullableTrimmed(_notesController.text),
          location: _nullableTrimmed(_locationController.text),
          scheduledAt: scheduledAt,
          endAt: endAt,
          hasExplicitTime: _hasExplicitTime,
          reminderEnabled: _reminderEnabled,
          reminderLabel: _reminderEnabled ? _reminderLabel : null,
          repeatPattern: _selectedType == PlannerItemType.schedule
              ? _repeatPattern
              : PlannerRepeatPattern.none,
          repeatUntil: _selectedType == PlannerItemType.schedule
              ? _repeatUntil
              : null,
          autoCompleteFromSubtasks: _autoCompleteFromSubtasks,
          subtasks: subtasks,
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
        _formError = 'StudyFlow could not save this planner item right now.';
      });
    }
  }

  String? _nullableTrimmed(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _PlannerStepRail extends StatelessWidget {
  const _PlannerStepRail({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final labels = const ['Basics', 'Date', 'Details', 'Steps'];
    return Row(
      children: labels.asMap().entries.map((entry) {
        final isActive = entry.key == step;
        final isDone = entry.key < step;
        final color = isActive || isDone
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).dividerColor;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: EdgeInsets.only(
              right: entry.key == labels.length - 1 ? 0 : 8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isActive ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              labels[entry.key],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isActive || isDone ? color : null,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        );
      }).toList(),
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF182134)
              : const Color(0xFFF5F7FC),
          borderRadius: BorderRadius.circular(18),
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

class _QuickDateChip extends StatelessWidget {
  const _QuickDateChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      side: BorderSide.none,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF182134)
          : const Color(0xFFF1F3F7),
    );
  }
}

class _EditableSubtaskDraft {
  const _EditableSubtaskDraft({
    required this.id,
    required this.controller,
    this.isCompleted = false,
    this.completedAt,
  });

  final String id;
  final TextEditingController controller;
  final bool isCompleted;
  final DateTime? completedAt;
}

String _normalizedSubjectKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
