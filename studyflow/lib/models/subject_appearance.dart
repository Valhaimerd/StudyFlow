import 'calendar_entry.dart';

class SubjectAppearance {
  const SubjectAppearance({
    required this.subjectSource,
    required this.subjectKey,
    required this.subjectName,
    required this.iconKey,
    required this.colorValue,
    this.updatedAt,
  });

  final CalendarSubjectSource subjectSource;
  final String subjectKey;
  final String subjectName;
  final String iconKey;
  final int colorValue;
  final DateTime? updatedAt;

  String get storageKey => '${subjectSource.name}::$subjectKey';

  Map<String, Object?> toJson() {
    return {
      'subjectSource': subjectSource.name,
      'subjectKey': subjectKey,
      'subjectName': subjectName,
      'iconKey': iconKey,
      'colorValue': colorValue,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory SubjectAppearance.fromJson(Map<String, Object?> json) {
    return SubjectAppearance(
      subjectSource: _parseSubjectSource(json['subjectSource']?.toString()),
      subjectKey: json['subjectKey']?.toString() ?? '',
      subjectName: json['subjectName']?.toString() ?? '',
      iconKey: json['iconKey']?.toString() ?? 'menu_book_outlined',
      colorValue: _parseInt(json['colorValue']) ?? 0xFF6270EA,
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  static CalendarSubjectSource _parseSubjectSource(String? value) {
    for (final source in CalendarSubjectSource.values) {
      if (source.name == value) {
        return source;
      }
    }

    return CalendarSubjectSource.unknown;
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
}
