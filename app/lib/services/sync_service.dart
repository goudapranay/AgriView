import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_db_service.dart';

// Sync is now local-only — no server upload.
// This service just checks connectivity (kept for future use)
// and provides the SyncResult type used across the app.

class SyncService {
  static final SyncService _i = SyncService._();
  factory SyncService() => _i;
  SyncService._();

  Future<bool> isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi    ||
        r == ConnectivityResult.ethernet);
  }

  // No-op — data is saved locally immediately in the form.
  // Kept so existing callers don't break.
  Future<SyncResult> syncPending() async {
    final pending = await LocalDbService().getPendingCount();
    // Mark all pending as saved locally
    final records = await LocalDbService().getPendingRecords();
    for (final r in records) {
      await LocalDbService().updateSyncStatus(r.plotId, kSynced);
    }
    return SyncResult(saved: pending);
  }

  Future<void> retryRecord(String plotId) async {
    await LocalDbService().updateSyncStatus(plotId, kSynced);
  }
}

class SyncResult {
  final int saved;
  SyncResult({required this.saved});

  String get message {
    if (saved == 0) return 'All records saved locally';
    return '$saved record${saved == 1 ? '' : 's'} saved locally ✅';
  }

  int get synced => saved;
  bool get offline => false;
}
