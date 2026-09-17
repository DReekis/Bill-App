import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/sync_service.dart';
import '../data/repositories.dart';

/// Bidirectional cloud sync manager with health ping, exponential backoff,
/// offline queue dispatch, and local SQLite delta reconciliation.
class SyncEngine extends ChangeNotifier {
  SyncEngine._() {
    startAutoSync();
  }
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
      pendingCount = await Repository.instance.pendingSyncCount();
      notifyListeners();
    } catch (_) {}
  }

  void startAutoSync({Duration interval = const Duration(seconds: 45)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      syncNow();
    });
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<void> syncNow({bool force = false}) async {
    if (syncing) return;
    syncing = true;
    lastError = null;
    notifyListeners();

    try {
      // 1. Verify Reachability
      final online = await checkConnectivity();
      if (!online) {
        // Offline — fail gracefully without blocking UI or throwing
        return;
      }

      // Configure session credentials onto ApiClient
      final session = Repository.instance.session;
      if (session.token != null) {
        apiClient.setToken(session.token);
      }
      if (session.businessId != null) {
        apiClient.setBusinessId(session.businessId.toString());
      }

      // 2. Push Phase: Send pending SQLite sync_queue records to cloud
      final queue = await Repository.instance.syncQueue();
      for (final record in queue) {
        // Exponential backoff check for failed items
        if (!force && record.attempts > 0) {
          final backoffSecs = min(60, pow(2, record.attempts).toInt());
          // Wait for backoff window before retry
          final createdTime = DateTime.tryParse(record.createdAt);
          if (createdTime != null &&
              DateTime.now().difference(createdTime).inSeconds < backoffSecs) {
            continue;
          }
        }

        try {
          await _service.push(record);
          await Repository.instance.markSyncSuccess(record.id!);
        } catch (e) {
          lastError = e.toString();
          await Repository.instance.markSyncFailed(record.id!, e.toString());
          // Break to preserve FIFO transactional consistency
          break;
        }
      }

      // 3. Pull Phase: Fetch cloud changes created or updated since last sync
      final bizId = session.businessId;
      if (bizId != null) {
        final prefs = await SharedPreferences.getInstance();
        final lastSyncIso = prefs.getString(_kLastSyncTimeKey);

        final pullResult = await _service.pull(bizId, since: lastSyncIso);
        final changes = pullResult['changes'] as List<Map<String, dynamic>>;

        for (final change in changes) {
          await Repository.instance.reconcileRemoteChange(change);
        }

        final serverTime = pullResult['serverTime'] as String?;
        if (serverTime != null) {
          await prefs.setString(_kLastSyncTimeKey, serverTime);
        }
      }

      lastSyncedAt = DateTime.now();
      lastError = null;
    } catch (e) {
      lastError = e.toString();
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
