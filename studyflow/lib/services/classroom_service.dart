import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/classroom_activity.dart';
import '../models/classroom_stream_item.dart';
import 'auth_service.dart';
import 'classroom_date_time_parser.dart';

class ClassroomAuthorizationRequiredException implements Exception {
  const ClassroomAuthorizationRequiredException();

  @override
  String toString() {
    return 'Google Classroom access has not been granted yet.';
  }
}

class ClassroomSyncException implements Exception {
  const ClassroomSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ClassroomService {
  ClassroomService._();

  static final ClassroomService instance = ClassroomService._();

  static const List<String> scopes = [
    'https://www.googleapis.com/auth/classroom.courses.readonly',
    'https://www.googleapis.com/auth/classroom.coursework.me.readonly',
    'https://www.googleapis.com/auth/classroom.courseworkmaterials.readonly',
    'https://www.googleapis.com/auth/classroom.announcements.readonly',
    'https://www.googleapis.com/auth/classroom.student-submissions.me.readonly',
  ];

  static const String _baseUrl = 'https://classroom.googleapis.com/v1';

  final http.Client _client = http.Client();
  final ClassroomDateTimeParser _dateTimeParser =
      const ClassroomDateTimeParser();

  Future<ClassroomSnapshot> fetchCurrentStudentActivities({
    required bool promptIfNecessary,
  }) async {
    final headers = await AuthService.instance.authorizationHeadersForScopes(
      scopes,
      promptIfNecessary: promptIfNecessary,
    );

    if (headers == null) {
      throw const ClassroomAuthorizationRequiredException();
    }

    final courses = await _listCourses(headers);
    final activities = <ClassroomActivity>[];
    final streamItems = <ClassroomStreamItem>[];

    for (final course in courses) {
      final courseId = course['id']?.toString();
      if (courseId == null || courseId.isEmpty) {
        continue;
      }

      final courseName = _nonEmptyText(course['name']) ?? 'Untitled course';
      final courseWorkItems = await _listCourseWork(courseId, headers);
      final courseWorkMaterials = await _listCourseWorkMaterials(
        courseId,
        headers,
      );
      final announcements = await _listAnnouncements(courseId, headers);

      for (final item in courseWorkItems) {
        final title = _nonEmptyText(item['title']);
        if (title == null) {
          continue;
        }

        final workId = item['id']?.toString();
        if (workId == null || workId.isEmpty) {
          continue;
        }

        final submissionState = await _getSubmissionState(
          courseId: courseId,
          courseWorkId: workId,
          headers: headers,
        );
        final isCompleted = _isSubmissionComplete(submissionState);
        final dueAt = _dateTimeParser.parseDueAt(
          dueDate: item['dueDate'],
          dueTime: item['dueTime'],
        );

        activities.add(
          ClassroomActivity(
            id: '$courseId-$workId',
            courseId: courseId,
            courseName: courseName,
            title: title,
            description: _nonEmptyText(item['description']) ?? 'No description',
            workType: item['workType']?.toString() ?? 'ASSIGNMENT',
            state: item['state']?.toString() ?? 'PUBLISHED',
            isCompleted: isCompleted,
            alternateLink: _nonEmptyText(item['alternateLink']),
            dueAt: dueAt,
          ),
        );

        streamItems.add(
          ClassroomStreamItem(
            id: '$courseId-$workId',
            courseId: courseId,
            courseName: courseName,
            type: ClassroomStreamItemType.courseWork,
            title: title,
            description: _nonEmptyText(item['description']) ?? 'No description',
            alternateLink: _nonEmptyText(item['alternateLink']),
            scheduledAt: dueAt,
            updatedAt:
                _parseDateTime(item['updateTime']) ??
                _parseDateTime(item['creationTime']),
            isCompleted: isCompleted,
            attachments: _parseMaterialsList(item['materials']),
          ),
        );
      }

      for (final item in courseWorkMaterials) {
        final title =
            _nonEmptyText(item['title']) ??
            _firstAttachmentTitle(item['materials']) ??
            'Material';
        streamItems.add(
          ClassroomStreamItem(
            id: 'material:$courseId-${item['id']?.toString() ?? title}',
            courseId: courseId,
            courseName: courseName,
            type: ClassroomStreamItemType.material,
            title: title,
            description:
                _nonEmptyText(item['description']) ?? 'No additional details.',
            alternateLink: _nonEmptyText(item['alternateLink']),
            scheduledAt: _parseDateTime(item['scheduledTime']),
            updatedAt:
                _parseDateTime(item['updateTime']) ??
                _parseDateTime(item['creationTime']),
            attachments: _parseMaterialsList(item['materials']),
          ),
        );
      }

      for (final item in announcements) {
        final text = _nonEmptyText(item['text']) ?? '';
        streamItems.add(
          ClassroomStreamItem(
            id: 'announcement:$courseId-${item['id']?.toString() ?? text.hashCode}',
            courseId: courseId,
            courseName: courseName,
            type: ClassroomStreamItemType.announcement,
            title: _announcementTitle(text),
            description: text.isEmpty ? 'No additional details.' : text,
            alternateLink: _nonEmptyText(item['alternateLink']),
            scheduledAt: _parseDateTime(item['scheduledTime']),
            updatedAt:
                _parseDateTime(item['updateTime']) ??
                _parseDateTime(item['creationTime']),
            attachments: _parseMaterialsList(item['materials']),
          ),
        );
      }
    }

    activities.sort((a, b) {
      if (a.dueAt == null && b.dueAt == null) {
        return a.title.compareTo(b.title);
      }
      if (a.dueAt == null) {
        return 1;
      }
      if (b.dueAt == null) {
        return -1;
      }
      return a.dueAt!.compareTo(b.dueAt!);
    });

    streamItems.sort((a, b) {
      final aTimestamp = a.updatedAt ?? a.scheduledAt;
      final bTimestamp = b.updatedAt ?? b.scheduledAt;
      if (aTimestamp != null && bTimestamp != null) {
        final compare = bTimestamp.compareTo(aTimestamp);
        if (compare != 0) {
          return compare;
        }
      } else if (aTimestamp != null) {
        return -1;
      } else if (bTimestamp != null) {
        return 1;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return ClassroomSnapshot(
      activities: activities,
      streamItems: streamItems,
      fetchedAt: DateTime.now(),
      courseCount: courses.length,
    );
  }

  Future<List<Map<String, Object?>>> _listCourses(
    Map<String, String> headers,
  ) async {
    final items = await _fetchPagedItems(
      '$_baseUrl/courses?studentId=me&courseStates=ACTIVE&pageSize=100',
      headers: headers,
      itemsKey: 'courses',
    );

    return items.cast<Map<String, Object?>>();
  }

  Future<List<Map<String, Object?>>> _listCourseWork(
    String courseId,
    Map<String, String> headers,
  ) async {
    final items = await _fetchPagedItems(
      '$_baseUrl/courses/$courseId/courseWork?pageSize=100',
      headers: headers,
      itemsKey: 'courseWork',
    );

    return items.cast<Map<String, Object?>>();
  }

  Future<List<Map<String, Object?>>> _listCourseWorkMaterials(
    String courseId,
    Map<String, String> headers,
  ) async {
    final items = await _fetchPagedItems(
      '$_baseUrl/courses/$courseId/courseWorkMaterials?pageSize=100',
      headers: headers,
      itemsKey: 'courseWorkMaterial',
    );

    return items.cast<Map<String, Object?>>();
  }

  Future<List<Map<String, Object?>>> _listAnnouncements(
    String courseId,
    Map<String, String> headers,
  ) async {
    final items = await _fetchPagedItems(
      '$_baseUrl/courses/$courseId/announcements?pageSize=100&orderBy=updateTime%20desc',
      headers: headers,
      itemsKey: 'announcements',
    );

    return items.cast<Map<String, Object?>>();
  }

  Future<String?> _getSubmissionState({
    required String courseId,
    required String courseWorkId,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse(
          '$_baseUrl/courses/$courseId/courseWork/$courseWorkId/studentSubmissions'
          '?userId=me&pageSize=1',
        ),
        headers: headers,
      );

      if (response.statusCode == 403) {
        return null;
      }

      if (response.statusCode >= 400) {
        throw ClassroomSyncException(
          _errorMessageFromResponse(
            response,
            fallback: 'Could not load submission state.',
          ),
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final submissions = payload['studentSubmissions'];
      if (submissions is! List || submissions.isEmpty) {
        return null;
      }

      final submission = submissions.first;
      if (submission is! Map) {
        return null;
      }

      return submission['state']?.toString();
    } on ClassroomSyncException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> _fetchPagedItems(
    String url, {
    required Map<String, String> headers,
    required String itemsKey,
  }) async {
    final items = <dynamic>[];
    String? nextPageToken;

    do {
      final uri = Uri.parse(url).replace(
        queryParameters: {
          ...Uri.parse(url).queryParameters,
          ...?nextPageToken == null ? null : {'pageToken': nextPageToken},
        },
      );

      final response = await _client.get(uri, headers: headers);
      if (response.statusCode == 401) {
        throw const ClassroomAuthorizationRequiredException();
      }

      if (response.statusCode >= 400) {
        throw ClassroomSyncException(
          _errorMessageFromResponse(
            response,
            fallback: 'Google Classroom request failed.',
          ),
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final pageItems = payload[itemsKey];
      if (pageItems is List) {
        items.addAll(pageItems);
      }

      nextPageToken = payload['nextPageToken']?.toString();
    } while (nextPageToken != null && nextPageToken.isNotEmpty);

    return items;
  }

  bool _isSubmissionComplete(String? state) {
    if (state == null) {
      return false;
    }

    return state == 'TURNED_IN' || state == 'RETURNED';
  }

  String? _nonEmptyText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  DateTime? _parseDateTime(Object? value) {
    final raw = _nonEmptyText(value);
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  String _announcementTitle(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return 'Announcement';
    }

    final firstLine = normalized.split('\n').first.trim();
    if (firstLine.length <= 80) {
      return firstLine;
    }
    return '${firstLine.substring(0, 77)}...';
  }

  String? _firstAttachmentTitle(Object? materials) {
    final attachments = _parseMaterialsList(materials);
    if (attachments.isEmpty) {
      return null;
    }
    return attachments.first.title;
  }

  List<ClassroomStreamAttachment> _parseMaterialsList(Object? materials) {
    if (materials is! List) {
      return const <ClassroomStreamAttachment>[];
    }

    final attachments = <ClassroomStreamAttachment>[];
    for (final item in materials.whereType<Map>()) {
      final material = item.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final link = material['link'];
      if (link is Map) {
        attachments.add(
          ClassroomStreamAttachment(
            typeLabel: 'Link',
            title: _nonEmptyText(link['title']) ?? 'Link',
            url: _nonEmptyText(link['url']),
            thumbnailUrl: _nonEmptyText(link['thumbnailUrl']),
          ),
        );
        continue;
      }

      final driveWrapper = material['driveFile'];
      if (driveWrapper is Map) {
        final driveFile = driveWrapper['driveFile'];
        if (driveFile is Map) {
          attachments.add(
            ClassroomStreamAttachment(
              typeLabel: 'Drive file',
              title: _nonEmptyText(driveFile['title']) ?? 'Drive file',
              url: _nonEmptyText(driveFile['alternateLink']),
              thumbnailUrl: _nonEmptyText(driveFile['thumbnailUrl']),
            ),
          );
          continue;
        }
      }

      final video = material['youtubeVideo'];
      if (video is Map) {
        attachments.add(
          ClassroomStreamAttachment(
            typeLabel: 'YouTube',
            title: _nonEmptyText(video['title']) ?? 'YouTube video',
            url: _nonEmptyText(video['alternateLink']),
            thumbnailUrl: _nonEmptyText(video['thumbnailUrl']),
          ),
        );
        continue;
      }

      final form = material['form'];
      if (form is Map) {
        attachments.add(
          ClassroomStreamAttachment(
            typeLabel: 'Form',
            title: _nonEmptyText(form['title']) ?? 'Form',
            url:
                _nonEmptyText(form['formUrl']) ??
                _nonEmptyText(form['responseUrl']),
          ),
        );
      }
    }

    return attachments;
  }

  String _errorMessageFromResponse(
    http.Response response, {
    required String fallback,
  }) {
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final error = payload['error'];
      if (error is Map) {
        final status = error['status']?.toString().trim().toUpperCase();
        final message = error['message']?.toString().trim().toLowerCase();
        final sanitized = _sanitizedClassroomErrorMessage(
          response.statusCode,
          status: status,
          message: message,
        );
        if (sanitized != null) {
          return sanitized;
        }
      }
    } catch (_) {
      // Ignore malformed error payloads and fall back to a generic message.
    }

    return _defaultClassroomErrorMessage(
      response.statusCode,
      fallback: fallback,
    );
  }

  String? _sanitizedClassroomErrorMessage(
    int statusCode, {
    String? status,
    String? message,
  }) {
    if (status == 'PERMISSION_DENIED' ||
        message?.contains('insufficient authentication scopes') == true ||
        message?.contains('permission') == true) {
      return 'StudyFlow does not have access to this Google Classroom data right now. Reconnect Classroom and try again.';
    }
    if (status == 'RESOURCE_EXHAUSTED' ||
        message?.contains('quota') == true ||
        statusCode == 429) {
      return 'Google Classroom is busy right now. Please try syncing again in a moment.';
    }
    if (status == 'UNAUTHENTICATED' || statusCode == 401) {
      return 'Classroom needs your Google permission again before it can sync.';
    }
    if (status == 'UNAVAILABLE' || statusCode >= 500) {
      return 'Google Classroom is temporarily unavailable. Please try again shortly.';
    }
    return null;
  }

  String _defaultClassroomErrorMessage(
    int statusCode, {
    required String fallback,
  }) {
    if (statusCode == 400) {
      return 'StudyFlow could not complete the Google Classroom request right now.';
    }
    if (statusCode == 401) {
      return 'Classroom needs your Google permission again before it can sync.';
    }
    if (statusCode == 403) {
      return 'StudyFlow does not have access to this Google Classroom data right now. Reconnect Classroom and try again.';
    }
    if (statusCode == 404) {
      return 'Some Google Classroom data is no longer available.';
    }
    if (statusCode == 429) {
      return 'Google Classroom is busy right now. Please try syncing again in a moment.';
    }
    if (statusCode >= 500) {
      return 'Google Classroom is temporarily unavailable. Please try again shortly.';
    }
    return fallback;
  }
}
