enum ClassroomStreamItemType { courseWork, material, announcement }

class ClassroomStreamAttachment {
  const ClassroomStreamAttachment({
    required this.typeLabel,
    required this.title,
    this.url,
    this.thumbnailUrl,
  });

  final String typeLabel;
  final String title;
  final String? url;
  final String? thumbnailUrl;

  Map<String, Object?> toJson() {
    return {
      'typeLabel': typeLabel,
      'title': title,
      'url': url,
      'thumbnailUrl': thumbnailUrl,
    };
  }

  factory ClassroomStreamAttachment.fromJson(Map<String, Object?> json) {
    return ClassroomStreamAttachment(
      typeLabel: json['typeLabel']?.toString().trim() ?? 'Attachment',
      title: json['title']?.toString().trim() ?? 'Untitled attachment',
      url: _nullableText(json['url']),
      thumbnailUrl: _nullableText(json['thumbnailUrl']),
    );
  }
}

class ClassroomStreamItem {
  const ClassroomStreamItem({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.type,
    required this.title,
    required this.description,
    this.alternateLink,
    this.scheduledAt,
    this.updatedAt,
    this.isCompleted = false,
    this.attachments = const <ClassroomStreamAttachment>[],
  });

  final String id;
  final String courseId;
  final String courseName;
  final ClassroomStreamItemType type;
  final String title;
  final String description;
  final String? alternateLink;
  final DateTime? scheduledAt;
  final DateTime? updatedAt;
  final bool isCompleted;
  final List<ClassroomStreamAttachment> attachments;

  bool get isResource =>
      type == ClassroomStreamItemType.material ||
      type == ClassroomStreamItemType.announcement;

  String get typeLabel {
    switch (type) {
      case ClassroomStreamItemType.courseWork:
        return 'Task';
      case ClassroomStreamItemType.material:
        return 'Material';
      case ClassroomStreamItemType.announcement:
        return 'Announcement';
    }
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'courseId': courseId,
      'courseName': courseName,
      'type': type.name,
      'title': title,
      'description': description,
      'alternateLink': alternateLink,
      'scheduledAt': scheduledAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isCompleted': isCompleted,
      'attachments': attachments
          .map((attachment) => attachment.toJson())
          .toList(),
    };
  }

  factory ClassroomStreamItem.fromJson(Map<String, Object?> json) {
    final rawAttachments = json['attachments'];
    return ClassroomStreamItem(
      id: json['id']?.toString() ?? '',
      courseId: json['courseId']?.toString() ?? '',
      courseName: json['courseName']?.toString().trim() ?? '',
      type: _parseType(json['type']?.toString()),
      title: json['title']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      alternateLink: _nullableText(json['alternateLink']),
      scheduledAt: _parseDateTime(json['scheduledAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      isCompleted: json['isCompleted'] == true,
      attachments: rawAttachments is List
          ? rawAttachments
                .whereType<Map>()
                .map(
                  (entry) => ClassroomStreamAttachment.fromJson(
                    entry.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                )
                .toList()
          : const <ClassroomStreamAttachment>[],
    );
  }

  static ClassroomStreamItemType _parseType(String? value) {
    for (final type in ClassroomStreamItemType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return ClassroomStreamItemType.material;
  }
}

DateTime? _parseDateTime(Object? value) {
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

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }

  return text;
}
