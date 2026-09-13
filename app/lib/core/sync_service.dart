import 'dart:convert';
import 'api_client.dart';
import 'models.dart';

class SyncService {
  const SyncService(this._client);

  final ApiClient _client;

  Future<void> push(SyncRecord record) async {
    final response = await _client.post('/api/v1/sync/push', {
      'businessId': record.businessId.toString(),
      'entity': record.entity,
      'entityId': record.entityId,
      'op': record.op,
      'payload': record.payload,
    });

    if (response.statusCode >= 400) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Sync failed');
    }
  }
}
