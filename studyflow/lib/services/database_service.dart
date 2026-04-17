import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/calendar_cache_snapshot.dart';
import '../models/planner_item.dart';
import '../models/subject_record.dart';
import '../models/subject_appearance.dart';
import 'app_settings_service.dart';

class DuplicateSubjectCodeException implements Exception {
  const DuplicateSubjectCodeException(this.subjectCode);

  final String subjectCode;

  @override
  String toString() {
    return 'A subject with code "$subjectCode" already exists.';
  }
}

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://studyflow-fa5f9-default-rtdb.firebaseio.com/',
  );
  bool _didInitializePersistence = false;
  final Set<String> _keptSyncedUsers = <String>{};

  DatabaseReference get _root => _database.ref();

  Future<void> initialize() async {
    if (_didInitializePersistence) {
      return;
    }

    _database.setPersistenceEnabled(true);
    _database.setPersistenceCacheSizeBytes(10000000);
    _didInitializePersistence = true;
  }

  void keepUserWorkspaceSynced(String uid) {
    if (!_keptSyncedUsers.add(uid)) {
      return;
    }

    final userRef = _root.child('users').child(uid);
    userRef.child('plannerItems').keepSynced(true);
    userRef.child('subjects').keepSynced(true);
    userRef.child('subjectAppearances').keepSynced(true);
    userRef.child('hiddenClassroomSubjects').keepSynced(true);
    userRef.child('hiddenClassroomEntries').keepSynced(true);
    userRef.child('calendarCache').keepSynced(true);
  }

  Future<void> createOrUpdateUserProfile({
    required String uid,
    required String fullName,
    required String email,
  }) async {
    final userRef = _root.child('users').child(uid);
    final existingSnapshot = await userRef.get();
    final existingValue = existingSnapshot.value;
    final existingProfile = existingValue is Map<Object?, Object?>
        ? existingValue
        : null;
    final savedFullName = existingProfile?['fullName']?.toString().trim();
    final savedEmail = existingProfile?['email']?.toString().trim();

    await userRef.update({
      'uid': uid,
      'fullName': savedFullName?.isNotEmpty == true ? savedFullName : fullName,
      'email': savedEmail?.isNotEmpty == true ? savedEmail : email,
      'googleEmail': email,
      'updatedAt': ServerValue.timestamp,
    });

    final createdAtSnapshot = await userRef.child('createdAt').get();

    if (!createdAtSnapshot.exists) {
      await userRef.child('createdAt').set(ServerValue.timestamp);
    }
  }

  Future<void> updateUserProfileDetails({
    required String uid,
    required Map<String, Object?> values,
  }) async {
    final payload = <String, Object?>{
      ...values,
      'updatedAt': ServerValue.timestamp,
    };

    payload.removeWhere((key, value) => value == null);

    await _root.child('users').child(uid).update(payload);
  }

  Future<void> writeDatabaseReadyFlag() async {
    await _root.child('app_status').set({
      'message': 'StudyFlow database is connected',
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<Map<Object?, Object?>?> getCurrentUserProfile(String uid) async {
    final snapshot = await _root.child('users').child(uid).get();

    if (!snapshot.exists) {
      return null;
    }

    final value = snapshot.value;
    if (value is Map<Object?, Object?>) {
      return value;
    }

    return null;
  }

  Stream<List<SubjectAppearance>> watchSubjectAppearances(String uid) {
    return _root
        .child('users')
        .child(uid)
        .child('subjectAppearances')
        .onValue
        .map((event) {
          final value = event.snapshot.value;
          if (value is! Map) {
            return const <SubjectAppearance>[];
          }

          final appearances =
              value.values
                  .whereType<Map>()
                  .map(
                    (entry) => SubjectAppearance.fromJson(
                      entry.map(
                        (key, value) => MapEntry(key.toString(), value),
                      ),
                    ),
                  )
                  .where((entry) => entry.subjectKey.isNotEmpty)
                  .toList()
                ..sort((a, b) {
                  final nameCompare = a.subjectName.toLowerCase().compareTo(
                    b.subjectName.toLowerCase(),
                  );
                  if (nameCompare != 0) {
                    return nameCompare;
                  }
                  return a.subjectKey.compareTo(b.subjectKey);
                });

          return appearances;
        });
  }

  Future<void> saveSubjectAppearance({
    required String uid,
    required SubjectAppearance appearance,
  }) async {
    final payload = appearance.toJson()
      ..['updatedAt'] = DateTime.now().toIso8601String();

    final writeState = await _queueOfflineCapableWrite(
      () => _root
          .child('users')
          .child(uid)
          .child('subjectAppearances')
          .child(appearance.storageKey)
          .set(payload),
    );
    await _markPlannerMutation(uid, writeState: writeState);
  }

  Stream<Set<String>> watchHiddenClassroomSubjectKeys(String uid) {
    return _watchHiddenClassroomValues(uid, 'hiddenClassroomSubjects');
  }

  Stream<Set<String>> watchHiddenClassroomEntryIds(String uid) {
    return _watchHiddenClassroomValues(uid, 'hiddenClassroomEntries');
  }

  Future<Set<String>> getHiddenClassroomSubjectKeys(String uid) async {
    return _getHiddenClassroomValues(uid, 'hiddenClassroomSubjects');
  }

  Future<Set<String>> getHiddenClassroomEntryIds(String uid) async {
    return _getHiddenClassroomValues(uid, 'hiddenClassroomEntries');
  }

  Future<void> hideClassroomSubject({
    required String uid,
    required String subjectKey,
  }) async {
    await _setHiddenClassroomValue(
      uid: uid,
      collection: 'hiddenClassroomSubjects',
      value: subjectKey,
    );
  }

  Future<void> restoreClassroomSubject({
    required String uid,
    required String subjectKey,
  }) async {
    await _removeHiddenClassroomValue(
      uid: uid,
      collection: 'hiddenClassroomSubjects',
      value: subjectKey,
    );
  }

  Future<void> hideClassroomEntry({
    required String uid,
    required String entryId,
  }) async {
    await _setHiddenClassroomValue(
      uid: uid,
      collection: 'hiddenClassroomEntries',
      value: entryId,
    );
  }

  Future<void> restoreClassroomEntry({
    required String uid,
    required String entryId,
  }) async {
    await _removeHiddenClassroomValue(
      uid: uid,
      collection: 'hiddenClassroomEntries',
      value: entryId,
    );
  }

  Stream<Set<String>> _watchHiddenClassroomValues(
    String uid,
    String collection,
  ) {
    return _root.child('users').child(uid).child(collection).onValue.map((
      event,
    ) {
      final value = event.snapshot.value;
      if (value is! Map) {
        return const <String>{};
      }

      return value.values
          .map((entry) {
            if (entry is Map) {
              return entry['value']?.toString().trim();
            }
            return entry?.toString().trim();
          })
          .whereType<String>()
          .where((entry) => entry.isNotEmpty)
          .toSet();
    });
  }

  Future<Set<String>> _getHiddenClassroomValues(
    String uid,
    String collection,
  ) async {
    final snapshot = await _root
        .child('users')
        .child(uid)
        .child(collection)
        .get();
    final value = snapshot.value;
    if (value is! Map) {
      return const <String>{};
    }

    return value.values
        .map((entry) {
          if (entry is Map) {
            return entry['value']?.toString().trim();
          }
          return entry?.toString().trim();
        })
        .whereType<String>()
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }

  Future<void> _setHiddenClassroomValue({
    required String uid,
    required String collection,
    required String value,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final writeState = await _queueOfflineCapableWrite(
      () => _root
          .child('users')
          .child(uid)
          .child(collection)
          .child(_hiddenKey(trimmed))
          .set({
            'value': trimmed,
            'hiddenAt': DateTime.now().toIso8601String(),
          }),
    );
    await _markPlannerMutation(uid, writeState: writeState);
  }

  Future<void> _removeHiddenClassroomValue({
    required String uid,
    required String collection,
    required String value,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final writeState = await _queueOfflineCapableWrite(
      () => _root
          .child('users')
          .child(uid)
          .child(collection)
          .child(_hiddenKey(trimmed))
          .remove(),
    );
    await _markPlannerMutation(uid, writeState: writeState);
  }

  Stream<List<SubjectRecord>> watchSubjects(String uid) {
    return _root.child('users').child(uid).child('subjects').onValue.map((
      event,
    ) {
      final value = event.snapshot.value;
      if (value is! Map) {
        return const <SubjectRecord>[];
      }

      final subjects = value.entries
          .where((entry) => entry.key != null && entry.value is Map)
          .map(
            (entry) => SubjectRecord.fromJson(
              entry.key.toString(),
              (entry.value as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList();

      subjects.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }

        final codeCompare = a.subjectCode.toLowerCase().compareTo(
          b.subjectCode.toLowerCase(),
        );
        if (codeCompare != 0) {
          return codeCompare;
        }

        return a.subjectName.toLowerCase().compareTo(
          b.subjectName.toLowerCase(),
        );
      });

      return subjects;
    });
  }

  Future<List<SubjectRecord>> getSubjects(String uid) async {
    final snapshot = await _root
        .child('users')
        .child(uid)
        .child('subjects')
        .get();
    final value = snapshot.value;
    if (value is! Map) {
      return const <SubjectRecord>[];
    }

    final subjects = value.entries
        .where((entry) => entry.key != null && entry.value is Map)
        .map(
          (entry) => SubjectRecord.fromJson(
            entry.key.toString(),
            (entry.value as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList();

    subjects.sort(
      (a, b) =>
          a.subjectCode.toLowerCase().compareTo(b.subjectCode.toLowerCase()),
    );
    return subjects;
  }

  Future<SubjectRecord> createSubject({
    required String uid,
    required SubjectRecord subject,
  }) async {
    final subjectRef = _root.child('users').child(uid).child('subjects').push();
    final subjectId = subjectRef.key;
    if (subjectId == null || subjectId.isEmpty) {
      throw StateError('Could not create a subject id.');
    }

    final now = DateTime.now();
    final record = subject.copyWith(
      id: subjectId,
      createdAt: now,
      updatedAt: now,
      clearArchivedAt: subject.status != SubjectStatus.archived,
    );

    final normalizedCode = _normalizedSubjectCode(record.subjectCode);
    var reservedCode = false;
    if (normalizedCode != null) {
      await _ensureUniqueSubjectCode(
        uid: uid,
        subjectCode: record.subjectCode,
        subjectId: subjectId,
      );
      reservedCode = true;
    }

    try {
      final writeState = await _queueOfflineCapableWrite(
        () => subjectRef.set(record.toJson()),
      );
      await _markPlannerMutation(uid, writeState: writeState);
    } catch (_) {
      if (reservedCode) {
        await _releaseSubjectCodeClaim(
          uid: uid,
          normalizedCode: normalizedCode,
          subjectId: subjectId,
        );
      }
      rethrow;
    }
    return record;
  }

  Future<SubjectRecord> updateSubject({
    required String uid,
    required SubjectRecord subject,
  }) async {
    final existing = await getSubject(uid: uid, subjectId: subject.id);
    final previousNormalizedCode = _normalizedSubjectCode(
      existing?.subjectCode ?? '',
    );
    final nextNormalizedCode = _normalizedSubjectCode(subject.subjectCode);
    final codeChanged = previousNormalizedCode != nextNormalizedCode;
    var reservedNewCode = false;

    if (nextNormalizedCode != null) {
      await _ensureUniqueSubjectCode(
        uid: uid,
        subjectCode: subject.subjectCode,
        subjectId: subject.id,
        excludeSubjectId: subject.id,
      );
      reservedNewCode = codeChanged;
    }

    final now = DateTime.now();
    final record = subject.copyWith(
      updatedAt: now,
      clearArchivedAt:
          subject.status == SubjectStatus.active && subject.archivedAt != null,
    );

    try {
      final writeState = await _queueOfflineCapableWrite(
        () => _root
            .child('users')
            .child(uid)
            .child('subjects')
            .child(subject.id)
            .set(record.toJson()),
      );
      await _markPlannerMutation(uid, writeState: writeState);
    } catch (_) {
      if (reservedNewCode) {
        await _releaseSubjectCodeClaim(
          uid: uid,
          normalizedCode: nextNormalizedCode,
          subjectId: subject.id,
        );
      }
      rethrow;
    }

    if (codeChanged && previousNormalizedCode != null) {
      await _releaseSubjectCodeClaim(
        uid: uid,
        normalizedCode: previousNormalizedCode,
        subjectId: subject.id,
      );
    }
    return record;
  }

  Future<void> archiveSubject({
    required String uid,
    required String subjectId,
  }) async {
    final subject = await getSubject(uid: uid, subjectId: subjectId);
    if (subject == null) {
      return;
    }

    await updateSubject(
      uid: uid,
      subject: subject.copyWith(
        status: SubjectStatus.archived,
        archivedAt: DateTime.now(),
      ),
    );
  }

  Future<void> restoreSubject({
    required String uid,
    required String subjectId,
  }) async {
    final subject = await getSubject(uid: uid, subjectId: subjectId);
    if (subject == null) {
      return;
    }

    await updateSubject(
      uid: uid,
      subject: subject.copyWith(
        status: SubjectStatus.active,
        clearArchivedAt: true,
      ),
    );
  }

  Future<SubjectRecord?> getSubject({
    required String uid,
    required String subjectId,
  }) async {
    final snapshot = await _root
        .child('users')
        .child(uid)
        .child('subjects')
        .child(subjectId)
        .get();

    if (!snapshot.exists) {
      return null;
    }

    final value = snapshot.value;
    if (value is! Map) {
      return null;
    }

    return SubjectRecord.fromJson(
      subjectId,
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Stream<List<PlannerItem>> watchPlannerItems(String uid) {
    return _root.child('users').child(uid).child('plannerItems').onValue.map((
      event,
    ) {
      final value = event.snapshot.value;
      if (value is! Map) {
        return const <PlannerItem>[];
      }

      final items = value.entries
          .where((entry) => entry.key != null && entry.value is Map)
          .map(
            (entry) => PlannerItem.fromJson(
              entry.key.toString(),
              (entry.value as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .where((item) => !item.isDeleted)
          .toList();

      items.sort(_sortPlannerItems);
      return items;
    });
  }

  Future<List<PlannerItem>> getPlannerItems(String uid) async {
    final snapshot = await _root
        .child('users')
        .child(uid)
        .child('plannerItems')
        .get();
    final value = snapshot.value;
    if (value is! Map) {
      return const <PlannerItem>[];
    }

    final items = value.entries
        .where((entry) => entry.key != null && entry.value is Map)
        .map(
          (entry) => PlannerItem.fromJson(
            entry.key.toString(),
            (entry.value as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .where((item) => !item.isDeleted)
        .toList();

    items.sort(_sortPlannerItems);
    return items;
  }

  Future<PlannerItem> createPlannerItem({
    required String uid,
    required PlannerItem item,
  }) async {
    final itemRef = _root
        .child('users')
        .child(uid)
        .child('plannerItems')
        .push();
    final itemId = itemRef.key;
    if (itemId == null || itemId.isEmpty) {
      throw StateError('Could not create a planner item id.');
    }

    final now = DateTime.now();
    final record = item
        .copyWith(
          id: itemId,
          createdAt: now,
          updatedAt: now,
          clearDeletedAt: true,
        )
        .normalizedForSave();

    final writeState = await _queueOfflineCapableWrite(
      () => itemRef.set(record.toJson()),
    );
    await _markPlannerMutation(uid, writeState: writeState);
    return record;
  }

  Future<PlannerItem> updatePlannerItem({
    required String uid,
    required PlannerItem item,
  }) async {
    final now = DateTime.now();
    final record = item.copyWith(updatedAt: now).normalizedForSave();

    final writeState = await _queueOfflineCapableWrite(
      () => _root
          .child('users')
          .child(uid)
          .child('plannerItems')
          .child(item.id)
          .set(record.toJson()),
    );
    await _markPlannerMutation(uid, writeState: writeState);
    return record;
  }

  Future<void> deletePlannerItem({
    required String uid,
    required String itemId,
  }) async {
    final existing = await _root
        .child('users')
        .child(uid)
        .child('plannerItems')
        .child(itemId)
        .get();
    if (!existing.exists) {
      return;
    }

    final value = existing.value;
    if (value is! Map) {
      return;
    }

    final item = PlannerItem.fromJson(
      itemId,
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
    final record = item.copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final writeState = await _queueOfflineCapableWrite(
      () => _root
          .child('users')
          .child(uid)
          .child('plannerItems')
          .child(itemId)
          .set(record.toJson()),
    );
    await _markPlannerMutation(uid, writeState: writeState);
  }

  Stream<bool> observeConnection() {
    return _database
        .ref('.info/connected')
        .onValue
        .map((event) => event.snapshot.value == true)
        .distinct();
  }

  Future<bool> isConnected({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      return observeConnection().first.timeout(timeout, onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<void> saveCalendarCache({
    required String uid,
    required CalendarCacheSnapshot snapshot,
  }) async {
    await _root.child('users').child(uid).child('calendarCache').set({
      ...snapshot.toJson(),
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<CalendarCacheSnapshot?> getCalendarCache(String uid) async {
    final snapshot = await _root
        .child('users')
        .child(uid)
        .child('calendarCache')
        .get();
    if (!snapshot.exists) {
      return null;
    }

    final value = snapshot.value;
    if (value is! Map) {
      return null;
    }

    return CalendarCacheSnapshot.fromJson(
      value.map((key, value) => MapEntry(key.toString(), value)),
      source: CalendarSnapshotSource.firebase,
    );
  }

  Future<void> updateSyncRecord({
    required String uid,
    required SyncStatus status,
    DateTime? lastSuccessfulSyncAt,
    String? failureReason,
  }) async {
    final payload = <String, Object?>{
      'syncStatus': status.name,
      'lastAttemptedSyncAt': DateTime.now().toIso8601String(),
      'pendingChangesCount': status == SyncStatus.pendingChanges ? 1 : 0,
      'failureReason': failureReason,
      'updatedAt': ServerValue.timestamp,
    };
    if (lastSuccessfulSyncAt != null) {
      payload['lastSuccessfulSyncAt'] = lastSuccessfulSyncAt.toIso8601String();
    }
    await _root.child('users').child(uid).child('syncRecord').update(payload);
  }

  Future<void> _ensureUniqueSubjectCode({
    required String uid,
    required String subjectCode,
    required String subjectId,
    String? excludeSubjectId,
  }) async {
    final normalizedCode = _normalizedSubjectCode(subjectCode);
    if (normalizedCode == null) {
      return;
    }
    final subjects = await getSubjects(uid);
    final duplicateExists = subjects.any((subject) {
      return subject.id != excludeSubjectId &&
          _normalizedSubjectCode(subject.subjectCode) == normalizedCode;
    });

    if (duplicateExists) {
      throw DuplicateSubjectCodeException(subjectCode.trim());
    }

    final canUseAtomicReservation = await isConnected(
      timeout: const Duration(seconds: 1),
    );
    if (!canUseAtomicReservation) {
      return;
    }

    final result = await _root
        .child('users')
        .child(uid)
        .child('subjectCodeIndex')
        .child(_hiddenKey(normalizedCode))
        .runTransaction((currentValue) {
          final reservedSubjectId = _subjectIdFromCodeIndexValue(currentValue);
          if (reservedSubjectId != null && reservedSubjectId != subjectId) {
            return Transaction.abort();
          }
          return Transaction.success({
            'subjectId': subjectId,
            'subjectCode': normalizedCode,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        });

    if (!result.committed) {
      throw DuplicateSubjectCodeException(subjectCode.trim());
    }
  }

  String _hiddenKey(String value) {
    return base64Url.encode(utf8.encode(value));
  }

  Future<void> _markPlannerMutation(
    String uid, {
    required _WriteState writeState,
  }) async {
    final now = DateTime.now();
    final payload = <String, Object?>{
      'syncStatus': writeState == _WriteState.synced
          ? SyncStatus.stable.name
          : SyncStatus.pendingChanges.name,
      'lastAttemptedSyncAt': now.toIso8601String(),
      'pendingChangesCount': writeState == _WriteState.synced ? 0 : 1,
      'failureReason': null,
      'updatedAt': ServerValue.timestamp,
    };
    if (writeState == _WriteState.synced) {
      payload['lastSuccessfulSyncAt'] = now.toIso8601String();
    }
    await _root.child('users').child(uid).child('syncRecord').update(payload);
  }

  Future<_WriteState> _queueOfflineCapableWrite(
    Future<void> Function() write,
  ) async {
    try {
      await write().timeout(const Duration(seconds: 4));
      return _WriteState.synced;
    } on TimeoutException {
      // Firebase Realtime Database persistence has already queued the write.
      // Returning lets the UI leave its saving state while offline.
      return _WriteState.pendingChanges;
    }
  }

  String? _normalizedSubjectCode(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  String? _subjectIdFromCodeIndexValue(Object? value) {
    if (value is Map) {
      return value['subjectId']?.toString().trim();
    }
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw;
  }

  Future<void> _releaseSubjectCodeClaim({
    required String uid,
    required String? normalizedCode,
    required String subjectId,
  }) async {
    if (normalizedCode == null) {
      return;
    }

    final canUseAtomicReservation = await isConnected(
      timeout: const Duration(seconds: 1),
    );
    if (!canUseAtomicReservation) {
      return;
    }

    await _root
        .child('users')
        .child(uid)
        .child('subjectCodeIndex')
        .child(_hiddenKey(normalizedCode))
        .runTransaction((currentValue) {
          final reservedSubjectId = _subjectIdFromCodeIndexValue(currentValue);
          if (reservedSubjectId == null || reservedSubjectId != subjectId) {
            return Transaction.abort();
          }
          return Transaction.success(null);
        });
  }

  int _sortPlannerItems(PlannerItem a, PlannerItem b) {
    final statusCompare = _plannerStatusRank(
      a.status,
    ).compareTo(_plannerStatusRank(b.status));
    if (statusCompare != 0) {
      return statusCompare;
    }

    final aDate = a.scheduledAt;
    final bDate = b.scheduledAt;
    if (aDate != null && bDate != null) {
      final dateCompare = aDate.compareTo(bDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
    } else if (aDate != null) {
      return -1;
    } else if (bDate != null) {
      return 1;
    }

    final priorityCompare = _plannerPriorityRank(
      a.effectivePriority,
    ).compareTo(_plannerPriorityRank(b.effectivePriority));
    if (priorityCompare != 0) {
      return priorityCompare;
    }

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  int _plannerStatusRank(PlannerItemStatus status) {
    switch (status) {
      case PlannerItemStatus.active:
        return 0;
      case PlannerItemStatus.completed:
        return 1;
      case PlannerItemStatus.archived:
        return 2;
    }
  }

  int _plannerPriorityRank(PlannerItemPriority priority) {
    switch (priority) {
      case PlannerItemPriority.high:
        return 0;
      case PlannerItemPriority.medium:
        return 1;
      case PlannerItemPriority.low:
        return 2;
      case PlannerItemPriority.optional:
        return 3;
    }
  }
}

enum _WriteState { synced, pendingChanges }
