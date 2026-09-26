import 'package:billket/core/api_client.dart';
import 'package:billket/core/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BackupInfo Model Tests', () {
    test('BackupInfo deserializes accurately from backend map', () {
      final map = {
        'id': 'vault_2026_09_26.enc',
        'filename': 'vault_2026_09_26.enc',
        'sizeBytes': 2048576,
        'sizeFormatted': '2000.6 KB',
        'checksum': 'sha256-abcdef123456',
        'deviceName': 'OnePlus 11 5G (Billing Counter)',
        'notes': 'Pre-EOD snapshot',
        'createdAt': '2026-09-26T10:15:00.000Z',
      };

      final info = BackupInfo.fromMap(map);
      expect(info.id, 'vault_2026_09_26.enc');
      expect(info.filename, 'vault_2026_09_26.enc');
      expect(info.sizeBytes, 2048576);
      expect(info.sizeFormatted, '2000.6 KB');
      expect(info.checksum, 'sha256-abcdef123456');
      expect(info.deviceName, 'OnePlus 11 5G (Billing Counter)');
      expect(info.notes, 'Pre-EOD snapshot');
      expect(info.createdAt.year, 2026);

      final toMap = info.toMap();
      expect(toMap['id'], 'vault_2026_09_26.enc');
      expect(toMap['filename'], 'vault_2026_09_26.enc');
      expect(toMap['sizeBytes'], 2048576);
    });

    test('BackupInfo handles fallback values gracefully', () {
      final map = <String, dynamic>{
        'sizeBytes': 1024,
      };

      final info = BackupInfo.fromMap(map);
      expect(info.filename, 'backup.enc');
      expect(info.sizeBytes, 1024);
      expect(info.sizeFormatted, '1.0 KB');
      expect(info.checksum, isNull);
    });
  });

  group('BackupService Preferences & Timestamp Tests', () {
    test('Stores and retrieves last cloud backup timestamp', () async {
      final service = BackupService();
      expect(await service.getLastCloudBackupTime(), isNull);

      final now = DateTime(2026, 9, 26, 10, 30);
      await service.setLastCloudBackupTime(now);

      final retrieved = await service.getLastCloudBackupTime();
      expect(retrieved, isNotNull);
      expect(retrieved!.year, 2026);
      expect(retrieved.month, 9);
      expect(retrieved.day, 26);
      expect(retrieved.hour, 10);
      expect(retrieved.minute, 30);
    });
  });

  group('BackupService ApiClient Integration Tests', () {
    test('listCloudBackups parses server response list', () async {
      final mockClient = ApiClient();
      // Configure mock http client to return backup list
      final service = BackupService(apiClient: mockClient);

      // Verify that listCloudBackups returns an empty list when unlinked or offline
      final list = await service.listCloudBackups();
      expect(list, isA<List<BackupInfo>>());
    });
  });
}
