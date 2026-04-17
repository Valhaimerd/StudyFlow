enum SubjectStatus { active, archived }

class SubjectRecord {
  const SubjectRecord({
    required this.id,
    required this.subjectName,
    required this.subjectCode,
    required this.iconKey,
    required this.colorValue,
    this.instructorName,
    this.termLabel,
    this.notes,
    this.status = SubjectStatus.active,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String subjectName;
  final String subjectCode;
  final String iconKey;
  final int colorValue;
  final String? instructorName;
  final String? termLabel;
  final String? notes;
  final SubjectStatus status;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isArchived => status == SubjectStatus.archived;

  SubjectRecord copyWith({
    String? id,
    String? subjectName,
    String? subjectCode,
    String? iconKey,
    int? colorValue,
    String? instructorName,
    String? termLabel,
    String? notes,
    SubjectStatus? status,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearInstructorName = false,
    bool clearTermLabel = false,
    bool clearNotes = false,
    bool clearArchivedAt = false,
    bool clearCreatedAt = false,
    bool clearUpdatedAt = false,
  }) {
    return SubjectRecord(
      id: id ?? this.id,
      subjectName: subjectName ?? this.subjectName,
      subjectCode: subjectCode ?? this.subjectCode,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      instructorName: clearInstructorName
          ? null
          : instructorName ?? this.instructorName,
      termLabel: clearTermLabel ? null : termLabel ?? this.termLabel,
      notes: clearNotes ? null : notes ?? this.notes,
      status: status ?? this.status,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
      createdAt: clearCreatedAt ? null : createdAt ?? this.createdAt,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'subjectName': subjectName,
      'subjectCode': subjectCode,
      'instructorName': instructorName,
      'termLabel': termLabel,
      'notes': notes,
      'iconKey': iconKey,
      'colorValue': colorValue,
      'status': status.name,
      'archivedAt': archivedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory SubjectRecord.fromJson(String id, Map<String, Object?> json) {
    return SubjectRecord(
      id: id,
      subjectName: json['subjectName']?.toString().trim() ?? '',
      subjectCode: json['subjectCode']?.toString().trim() ?? '',
      instructorName: _nullableText(json['instructorName']),
      termLabel: _nullableText(json['termLabel']),
      notes: _nullableText(json['notes']),
      iconKey: _nullableText(json['iconKey']) ?? 'menu_book_outlined',
      colorValue: _parseInt(json['colorValue']) ?? 0xFFE8EAFE,
      status: _parseStatus(json['status']?.toString()),
      archivedAt: _parseDateTime(json['archivedAt']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  static SubjectStatus _parseStatus(String? value) {
    for (final status in SubjectStatus.values) {
      if (status.name == value) {
        return status;
      }
    }

    return SubjectStatus.active;
  }

  static int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is double) {
      return DateTime.fromMillisecondsSinceEpoch(value.round());
    }

    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }

    final epochMillis = int.tryParse(raw);
    if (epochMillis != null) {
      return DateTime.fromMillisecondsSinceEpoch(epochMillis);
    }

    return null;
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }
}
