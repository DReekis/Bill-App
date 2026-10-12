import 'package:billket/core/models.dart';
import 'package:billket/core/session.dart';
import 'package:billket/data/app_database.dart';
import 'package:billket/data/repositories.dart';
import 'package:billket/features/more/more_screen.dart';
import 'package:billket/l10n/app_localizations.dart';
import 'package:billket/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MoreTab Settings and Search Bar Tests', () {
    late Database db;
    late Session session;
    late int bizId;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: AppDatabase.instance.createSchema,
        ),
      );
      AppDatabase.instance.useDatabaseForTesting(db);

      session = Session();
      bizId = await Repository.instance.createBusiness(Business(
        name: 'Apex Supermart',
        state: 'West Bengal',
        gstin: '19ABCDE1234F1Z5',
        taxRegistered: true,
      ));
      session.businessId = bizId;
      session.setRole(UserRole.owner);
    });

    tearDown(() async {
      await db.close();
    });

    Widget createTestApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<SyncEngine>.value(value: SyncEngine.instance),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [
            Locale('en'),
            Locale('hi'),
            Locale('bn'),
          ],
          home: Scaffold(body: MoreTab()),
        ),
      );
    }

    testWidgets('GSTIN Autofill API Key and Data sync options are completely removed', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('GSTIN Autofill API Key'), findsNothing);
      expect(find.text('Data sync'), findsNothing);
      expect(find.byIcon(Icons.gpp_good_rounded), findsNothing);
      expect(find.byIcon(Icons.cloud_sync_rounded), findsNothing);
    });

    testWidgets('Search bar is present and filters settings dynamically', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Search bar exists
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Search for 'invoice'
      await tester.enterText(searchField, 'invoice');
      await tester.pumpAndSettle();

      expect(find.text('Invoice settings'), findsOneWidget);
      // Non-matching tiles like MCA Audit Trail should not be displayed
      expect(find.text('MCA Audit Trail'), findsNothing);

      // Search for unknown keyword
      await tester.enterText(searchField, 'nonexistentquery123');
      await tester.pumpAndSettle();

      expect(find.text('No settings found'), findsOneWidget);
      expect(find.text('Clear search'), findsWidgets);

      // Tap clear search
      await tester.tap(find.text('Clear search').first);
      await tester.pumpAndSettle();

      // Verify normal view is restored
      expect(find.text('No settings found'), findsNothing);
    });
  });
}
