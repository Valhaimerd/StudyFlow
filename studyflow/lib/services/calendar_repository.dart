import '../models/calendar_cache_snapshot.dart';
import 'app_settings_service.dart';
import 'calendar_cache_service.dart';
import 'classroom_calendar_mapper.dart';
import 'classroom_service.dart';
import 'database_service.dart';

class CalendarRefreshResult {
  const CalendarRefreshResult({
    required this.syncStatus,
    this.snapshot,
    this.needsAuthorization = false,
    this.errorMessage,
    this.isUsingCache = false,
  });

  final CalendarCacheSnapshot? snapshot;
  final SyncStatus syncStatus;
  final bool needsAuthorization;
  final String? errorMessage;
  final bool isUsingCache;
}

class CalendarRepository {
  CalendarRepository._();

  static final CalendarRepository instance = CalendarRepository._();

  static const ClassroomCalendarMapper _mapper = ClassroomCalendarMapper();

  final CalendarCacheService _cacheService = CalendarCacheService.instance;
  final DatabaseService _databaseService = DatabaseService.instance;

  Stream<bool> observeConnection() {
    return _databaseService.observeConnection();
  }

  Future<CalendarCacheSnapshot?> loadBestAvailableSnapshot(String uid) async {
    final local = await _cacheService.loadSnapshot(uid);
    CalendarCacheSnapshot? remote;
    try {
      remote = await _databaseService.getCalendarCache(uid);
      final preferred = _newerSnapshot(local, remote);
      if (remote != null && preferred != null && identical(preferred, remote)) {
        await _cacheService.saveSnapshot(uid, remote);
      }
    } catch (_) {
      return local;
    }

    return _newerSnapshot(local, remote);
  }

  CalendarCacheSnapshot? _newerSnapshot(
    CalendarCacheSnapshot? local,
    CalendarCacheSnapshot? remote,
  ) {
    if (local == null) {
      return remote;
    }
    if (remote == null) {
      return local;
    }

    final localSyncedAt = local.lastSyncedAt;
    final remoteSyncedAt = remote.lastSyncedAt;
    if (localSyncedAt == null && remoteSyncedAt == null) {
      return local;
    }
    if (localSyncedAt == null) {
      return remote;
    }
    if (remoteSyncedAt == null) {
      return local;
    }
    if (remoteSyncedAt.isAfter(localSyncedAt) ||
        remoteSyncedAt.isAtSameMomentAs(localSyncedAt)) {
      return remote;
    }
    return local;
  }

  Future<CalendarRefreshResult> refreshFromClassroom({
    required String uid,
    required bool promptIfNecessary,
    required bool isOffline,
  }) async {
    final cachedSnapshot = await loadBestAvailableSnapshot(uid);

    if (isOffline) {
      return CalendarRefreshResult(
        snapshot: cachedSnapshot,
        syncStatus: SyncStatus.offlineLocalOnly,
        errorMessage: cachedSnapshot == null
            ? 'You are offline. Connect to the internet to load Google Classroom.'
            : 'You are offline. Showing the last saved calendar snapshot on this device.',
        isUsingCache: cachedSnapshot != null,
      );
    }

    try {
      final classroomSnapshot = await ClassroomService.instance
          .fetchCurrentStudentActivities(promptIfNecessary: promptIfNecessary);
      final snapshot = CalendarCacheSnapshot(
        entries: classroomSnapshot.activities
            .map((activity) => _mapper.mapActivity(activity))
            .toList(),
        courseCount: classroomSnapshot.courseCount,
        lastSyncedAt: classroomSnapshot.fetchedAt,
        source: CalendarSnapshotSource.live,
      );

      var savedLocally = false;
      try {
        await _cacheService.saveSnapshot(uid, snapshot);
        savedLocally = true;
      } catch (_) {
        savedLocally = false;
      }

      try {
        await _databaseService.saveCalendarCache(uid: uid, snapshot: snapshot);
        await _databaseService.updateSyncRecord(
          uid: uid,
          status: SyncStatus.stable,
          lastSuccessfulSyncAt: snapshot.lastSyncedAt,
        );

        if (!savedLocally) {
          return CalendarRefreshResult(
            snapshot: snapshot,
            syncStatus: SyncStatus.failed,
            errorMessage:
                'Live Classroom data loaded, but offline storage on this device could not be updated.',
          );
        }

        return CalendarRefreshResult(
          snapshot: snapshot,
          syncStatus: SyncStatus.stable,
        );
      } catch (_) {
          return CalendarRefreshResult(
            snapshot: snapshot,
            syncStatus: savedLocally
              ? SyncStatus.pendingChanges
              : SyncStatus.failed,
          errorMessage: savedLocally
              ? 'Saved on this device, but cloud sync is still catching up.'
              : 'Live Classroom data loaded, but StudyFlow could not save it completely right now.',
        );
      }
    } on ClassroomAuthorizationRequiredException {
      return CalendarRefreshResult(
        snapshot: cachedSnapshot,
        syncStatus: cachedSnapshot == null
            ? SyncStatus.failed
            : SyncStatus.failed,
        needsAuthorization: true,
        errorMessage: cachedSnapshot == null
            ? null
            : 'Classroom access is required again. Showing your last saved calendar snapshot.',
        isUsingCache: cachedSnapshot != null,
      );
    } on ClassroomSyncException catch (error) {
      return CalendarRefreshResult(
        snapshot: cachedSnapshot,
        syncStatus: cachedSnapshot == null
            ? SyncStatus.failed
            : SyncStatus.failed,
        errorMessage: cachedSnapshot == null
            ? error.message
            : '${error.message} Showing your last saved calendar snapshot.',
        isUsingCache: cachedSnapshot != null,
      );
    } catch (_) {
      return CalendarRefreshResult(
        snapshot: cachedSnapshot,
        syncStatus: cachedSnapshot == null
            ? SyncStatus.failed
            : SyncStatus.failed,
        errorMessage: cachedSnapshot == null
            ? 'Could not load Google Classroom right now. Please try again in a moment.'
            : 'Could not refresh Google Classroom. Showing your last saved calendar snapshot.',
        isUsingCache: cachedSnapshot != null,
      );
    }
  }
}
