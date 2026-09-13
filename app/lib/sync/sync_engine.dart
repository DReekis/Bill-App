import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/sync_service.dart';
import '../data/repositories.dart';

class SyncEngine extends ChangeNotifier {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  bool syncing = false;
  DateTime? lastSyncedAt;
  int? pendingCount;
  final SyncService _service = SyncService(ApiClient());

  Future<void> refreshPending() async {
    pendingCount = await Repository.instance.pendingSyncCount();
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    try {
      final queue = await Repository.instance.syncQueue();
      for (final record in queue) {
        try {
          await _service.push(record);
          await Repository.instance.markSyncSuccess(record.id!);
        } catch (e) {
          await Repository.instance.markSyncFailed(record.id!, e.toString());
          // Stop on first failure to preserve order
          break;
        }
      }
      lastSyncedAt = DateTime.now();
    } finally {
      syncing = false;
      await refreshPending();
    }
  }
}
