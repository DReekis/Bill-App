import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/sync_service.dart';
import '../core/telemetry_service.dart';
import '../data/repositories.dart';

/// Bidirectional cloud sync manager with health ping, exponential backoff,
/// offline queue dispatch, and local SQLite delta reconciliation.
class SyncEngine extends ChangeNotifier {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  static const String _kLastSyncTimeKey = 'sync.last_server_time';

  final ApiClient apiClient = ApiClient();
  late final SyncService _service = SyncService(apiClient);
  SyncService get service => _service;

  bool syncing = false;
  bool isOnline = false;
  DateTime? lastSyncedAt;
  int pendingCount = 0;
  String? lastError;
  String? lastSyncResultSummary;
  int lastPushedCount = 0;
  int lastPulledCount = 0;
  Timer? _autoSyncTimer;

  Future<bool> checkConnectivity() async {
    final online = await _service.checkHealth();
    if (isOnline != online) {
      isOnline = online;
      notifyListeners();
    }
    return online;
  }

  Future<void> refreshPending() async {
    try {
      final newCount = await Repository.instance.pendingSyncCount();
      if (pendingCount != newCount) {
        pendingCount = newCount;
        notifyListeners();
      }
    } catch (_) {}
  }

  Timer? _debounceTimer;

  void startAutoSync({Duration interval = const Duration(seconds: 45)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      syncNow();
    });
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Trigger a debounced background sync when an entity is saved locally.
  void triggerSync({Duration debounce = const Duration(seconds: 2)}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      final session = Repository.instance.session;
      if (!syncing && session.token != null && session.token!.isNotEmpty) {
        syncNow();
      }
    });
  }

  Future<void> syncNow({bool force = false}) async {
    if (syncing) return;
    syncing = true;
    lastError = null;
    notifyListeners();
    TelemetryService.instance.addBreadcrumb('Cloud sync started', category: 'sync', data: {'force': force});

    var pushedCount = 0;
    var pulledCount = 0;

    try {
      // 1. Verify Reachability
      final online = await checkConnectivity();
      if (!online) {
        lastError =
            'Cloud server unreachable at ${apiClient.baseUrl}. Start the AWS instance or update the Backend Server URL.';
        return;
      }

      // Configure session credentials onto ApiClient
      final session = Repository.instance.session;
      if (session.token == null || session.token!.isEmpty) {
        lastError = 'Sign in to Billket Cloud before syncing.';
        return;
      }
      apiClient.setToken(session.token);

      var cloudBizId = session.cloudBusinessId;
      if ((cloudBizId == null || cloudBizId.isEmpty) && session.token != null) {
        try {
          final res = await apiClient.get('/api/v1/businesses');
          if (res.statusCode == 200) {
            final decoded = jsonDecode(res.body);
            if (decoded is List && decoded.isNotEmpty && decoded.first['id'] != null) {
              final fetchedId = decoded.first['id'].toString();
              await session.setCloudBusinessId(fetchedId);
              cloudBizId = fetchedId;
            }
          }
        } catch (_) {}
      }

      if (cloudBizId != null && cloudBizId.isNotEmpty) {
        apiClient.setBusinessId(cloudBizId);
      } else if (session.businessId != null) {
        apiClient.setBusinessId(session.businessId.toString());
      }

      // 2. Push Phase: Send pending SQLite sync_queue records in batches of up to 50
      final queue = await Repository.instance.syncQueue();
      final readyRecords = <SyncRecord>[];
      for (final record in queue) {
        // Exponential backoff check for failed items
        if (!force && record.attempts > 0) {
          final backoffSecs = min(300, pow(2, record.attempts).toInt());
          final createdTime = DateTime.tryParse(record.createdAt);
          if (createdTime != null &&
              DateTime.now().difference(createdTime).inSeconds < backoffSecs) {
            continue;
          }
        }
        readyRecords.add(record);
      }

      for (var i = 0; i < readyRecords.length; i += 50) {
        final end = min(i + 50, readyRecords.length);
        final chunk = readyRecords.sublist(i, end);

        // Enrich payload if missing or plain text
        final enrichedChunk = <SyncRecord>[];
        for (final rec in chunk) {
          if (rec.payload == null ||
              rec.payload!.isEmpty ||
              (!rec.payload!.startsWith('{') && !rec.payload!.startsWith('['))) {
            final resolved = await Repository.instance.resolveSyncPayload(rec.entity, rec.entityId);
            if (resolved != null) {
              enrichedChunk.add(rec.copyWith(payload: resolved));
            } else {
              enrichedChunk.add(rec);
            }
          } else {
            enrichedChunk.add(rec);
          }
        }

        try {
          await _service.pushBatch(enrichedChunk, cloudBusinessId: cloudBizId);
          for (final rec in enrichedChunk) {
            await Repository.instance.markSyncSuccess(rec.id!);
            pushedCount++;
          }
        } catch (batchError) {
          // Fallback to sequential to isolate the failing record
          for (final rec in enrichedChunk) {
            try {
              await _service.push(rec, cloudBusinessId: cloudBizId);
              await Repository.instance.markSyncSuccess(rec.id!);
              pushedCount++;
            } catch (singleError) {
              lastError = singleError.toString();
              await Repository.instance.markSyncFailed(rec.id!, singleError.toString());
              break;
            }
          }
          break;
        }
      }

      // 3. Pull Phase: Fetch cloud changes created or updated since last sync
      final pullBizId = (cloudBizId != null && cloudBizId.isNotEmpty) ? cloudBizId : session.businessId?.toString();
      if (pullBizId != null) {
        final prefs = await SharedPreferences.getInstance();
        final lastSyncIso = prefs.getString(_kLastSyncTimeKey);

        final pullResult = await _service.pull(pullBizId, since: lastSyncIso);
        final changes = pullResult['changes'] as List<Map<String, dynamic>>;

        for (final change in changes) {
          await Repository.instance.reconcileRemoteChange(change);
          pulledCount++;
        }

        final serverTime = pullResult['serverTime'] as String?;
        if (serverTime != null) {
          await prefs.setString(_kLastSyncTimeKey, serverTime);
        }
      }

      lastPushedCount = pushedCount;
      lastPulledCount = pulledCount;
      if (pushedCount == 0 && pulledCount == 0) {
        lastSyncResultSummary = 'Up to date';
      } else if (pushedCount > 0 && pulledCount > 0) {
        lastSyncResultSummary = '$pushedCount pushed, $pulledCount pulled';
      } else if (pushedCount > 0) {
        lastSyncResultSummary = '$pushedCount pushed';
      } else {
        lastSyncResultSummary = '$pulledCount pulled';
      }

      lastSyncedAt = DateTime.now();
      lastError = null;
      TelemetryService.instance.addBreadcrumb('Cloud sync completed', category: 'sync', data: {'summary': lastSyncResultSummary});
    } catch (e, stack) {
      lastError = e.toString();
      TelemetryService.instance.captureException(e, stackTrace: stack, tag: 'sync_engine');
    } finally {
      syncing = false;
      await refreshPending();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopAutoSync();
    super.dispose();
  }
}
