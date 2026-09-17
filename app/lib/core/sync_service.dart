import 'dart:convert';
import 'api_client.dart';
import 'models.dart';

class SyncService {
  const SyncService(this._client);

  final ApiClient _client;
  ApiClient get client => _client;

  Future<bool> checkHealth() async {
    return await _client.ping();
  }

  Future<void> push(SyncRecord record) async {
    final response = await _client.post('/api/v1/sync/push', {
      'businessId': record.businessId.toString(),
      'entity': record.entity,
      'entityId': record.entityId.toString(),
      'op': record.op.isEmpty ? 'upsert' : record.op,
      'payload': record.payload,
      'idempotencyKey': record.idempotencyKey,
    });

    if (response.statusCode >= 400) {
      try {
        final body = jsonDecode(response.body);
        throw Exception(body['error'] ?? 'Sync push failed with status ${response.statusCode}');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Sync push failed with status ${response.statusCode}');
      }
    }
  }

  Future<Map<String, dynamic>> pull(int businessId, {String? since, int limit = 100}) async {
    final query = since != null && since.isNotEmpty ? '?since=$since&limit=$limit' : '?limit=$limit';
    final response = await _client.get(
      '/api/v1/sync/pull$query',
      headers: {'X-Business-Id': businessId.toString()},
    );

    if (response.statusCode >= 400) {
      try {
        final body = jsonDecode(response.body);
        throw Exception(body['error'] ?? 'Sync pull failed with status ${response.statusCode}');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Sync pull failed with status ${response.statusCode}');
      }
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'changes': (data['changes'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[],
      'serverTime': data['serverTime'] as String? ?? DateTime.now().toIso8601String(),
    };
  }
}
