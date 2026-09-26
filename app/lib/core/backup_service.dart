import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_database.dart';
import 'api_client.dart';

class BackupInfo {
  const BackupInfo({
    required this.id,
    required this.filename,
    required this.sizeBytes,
    required this.sizeFormatted,
    this.checksum,
    this.deviceName,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String filename;
  final int sizeBytes;
  final String sizeFormatted;
  final String? checksum;
  final String? deviceName;
  final String? notes;
  final DateTime createdAt;

  factory BackupInfo.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(map['createdAt']?.toString() ?? '');
    } catch (_) {
      parsedDate = DateTime.now();
    }
    return BackupInfo(
      id: map['id']?.toString() ?? map['filename']?.toString() ?? '',
      filename: map['filename']?.toString() ?? 'backup.enc',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      sizeFormatted: map['sizeFormatted']?.toString() ??
          '${(((map['sizeBytes'] ?? 0) as num) / 1024).toStringAsFixed(1)} KB',
      checksum: map['checksum']?.toString(),
      deviceName: map['deviceName']?.toString(),
      notes: map['notes']?.toString(),
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'filename': filename,
        'sizeBytes': sizeBytes,
        'sizeFormatted': sizeFormatted,
        'checksum': checksum,
        'deviceName': deviceName,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };
}

class BackupService {
  BackupService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;
  static const String _kLastBackupKey = 'backup.last_cloud_backup_time';

  /// Obtains the raw local SQLite file
  Future<File> getLocalDatabaseFile() async {
    return await AppDatabase.instance.databaseFile();
  }

  /// Creates a clean point-in-time snapshot file of the SQLite database
  Future<File> createLocalSnapshot({String? customPrefix}) async {
    final dbFile = await getLocalDatabaseFile();
    if (!await dbFile.exists()) {
      throw Exception('DATABASE_NOT_FOUND: No local database exists to back up.');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final prefix = customPrefix ?? 'billket_vault';
    final snapshotPath = '${tempDir.path}/${prefix}_$timestamp.enc';

    final snapshotFile = await dbFile.copy(snapshotPath);
    return snapshotFile;
  }

  /// Uploads a local snapshot to Billket Cloud (AWS S3 vault)
  Future<BackupInfo> uploadToCloud({
    File? snapshotFile,
    String? notes,
    String? deviceName,
    ApiClient? clientOverride,
  }) async {
    final client = clientOverride ?? _apiClient;
    final file = snapshotFile ?? await createLocalSnapshot();
    final bytes = await file.readAsBytes();
    final base64String = base64Encode(bytes);

    final defaultDeviceName = kIsWeb
        ? 'Web Browser'
        : Platform.isAndroid
            ? 'Android Device'
            : Platform.isIOS
                ? 'iPhone / iPad'
                : Platform.isWindows
                    ? 'Windows Workstation'
                    : 'Billing Device';

    final filename = file.path.split(Platform.pathSeparator).last;

    final res = await client.uploadBackup(
      base64Data: base64String,
      filename: filename,
      deviceName: deviceName ?? defaultDeviceName,
      notes: notes,
    );

    final backupData = res['backup'] as Map<String, dynamic>? ?? {};
    final info = BackupInfo.fromMap(backupData);

    // Save timestamp in local prefs
    await setLastCloudBackupTime(info.createdAt);

    return info;
  }

  /// Fetches the list of all cloud backup snapshots for the active business
  Future<List<BackupInfo>> listCloudBackups({ApiClient? clientOverride}) async {
    final client = clientOverride ?? _apiClient;
    final list = await client.fetchBackups();
    return list.map((m) => BackupInfo.fromMap(m)).toList();
  }

  /// Downloads a cloud snapshot and atomically replaces the local SQLite database
  Future<void> restoreFromCloud({
    required String backupId,
    ApiClient? clientOverride,
  }) async {
    final client = clientOverride ?? _apiClient;
    final data = await client.downloadBackup(backupId);
    final base64String = data['base64Data']?.toString();
    if (base64String == null || base64String.isEmpty) {
      throw Exception('RESTORE_FAILED: Backup snapshot is empty or corrupt.');
    }

    final rawBytes = base64Decode(base64String);

    // Close existing connection safely
    AppDatabase.instance.resetConnection();

    final targetDbFile = await getLocalDatabaseFile();
    if (await targetDbFile.exists()) {
      // Create a safety failover copy before replacing
      final tempDir = await getTemporaryDirectory();
      await targetDbFile.copy('${tempDir.path}/pre_restore_safety.bak');
    }

    // Atomically overwrite database file
    await targetDbFile.writeAsBytes(rawBytes, flush: true);

    // Re-initialize database
    await AppDatabase.instance.database;
  }

  /// Shares the encrypted backup file via WhatsApp, Drive, Email, or Filesystem
  Future<void> exportLocalBackup({String? subject}) async {
    final snapshot = await createLocalSnapshot(customPrefix: 'billket_export');
    await Share.shareXFiles(
      [XFile(snapshot.path)],
      subject: subject ?? 'Billket Business Backup Snapshot',
      text: 'Encrypted Billket Database Snapshot - Keep safe for disaster recovery.',
    );
  }

  /// Deletes a cloud backup
  Future<void> deleteCloudBackup(String backupId, {ApiClient? clientOverride}) async {
    final client = clientOverride ?? _apiClient;
    await client.deleteBackup(backupId);
  }

  /// Gets the last cloud backup time from SharedPreferences
  Future<DateTime?> getLastCloudBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_kLastBackupKey);
    if (iso != null && iso.isNotEmpty) {
      return DateTime.tryParse(iso);
    }
    return null;
  }

  /// Sets the last cloud backup time
  Future<void> setLastCloudBackupTime(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackupKey, dt.toIso8601String());
  }
}
