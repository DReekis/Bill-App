import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:billket/core/permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('shouldAskInitialPermissions defaults appropriately and can be marked', () async {
    // Should be able to mark requested and retrieve state
    await PermissionService.markInitialPermissionsRequested();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('billket_has_requested_initial_permissions_v2'), isTrue);

    // After marking, should not ask again
    final shouldAsk = await PermissionService.shouldAskInitialPermissions();
    expect(shouldAsk, isFalse);
  });
}
