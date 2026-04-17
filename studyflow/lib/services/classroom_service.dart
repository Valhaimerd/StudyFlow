import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/classroom_activity.dart';
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

    for (final course in courses) {
      final courseId = course['id']?.toString();
      if (courseId == null || courseId.isEmpty) {
        continue;
      }

      final courseName = _nonEmptyText(course['name']) ?? 'Untitled course';
      final courseWorkItems = await _listCourseWork(courseId, headers);

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

        activities.add(
          ClassroomActivity(
            id: '$courseId-$workId',
            courseId: courseId,
            courseName: courseName,
            title: title,
            description: _nonEmptyText(item['description']) ?? 'No description',
            workType: item['workType']?.toString() ?? 'ASSIGNMENT',
            state: item['state']?.toString() ?? 'PUBLISHED',
            isCompleted: _isSubmissionComplete(submissionState),
            alternateLink: _nonEmptyText(item['alternateLink']),
            dueAt: _dateTimeParser.parseDueAt(
              dueDate: item['dueDate'],
              dueTime: item['dueTime'],
            ),
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

    return ClassroomSnapshot(
      activities: activities,
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

    return _defaultClassroomErrorMessage(response.statusCode, fallback: fallback);
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
