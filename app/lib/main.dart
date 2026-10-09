import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/business_service.dart';
import 'core/inventory_service.dart';
import 'core/models.dart';
import 'core/session.dart';
import 'data/repositories.dart';
import 'l10n/app_localizations.dart';
import 'core/subscription_service.dart';
import 'sync/sync_engine.dart';
import 'features/auth/auth_flow.dart';
import 'features/auth/pin_lock_screen.dart';
import 'features/shell/app_shell.dart';
import 'theme/stitch_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Repository.instance.session.load();
  await SubscriptionService.instance.init(businessId: Repository.instance.session.businessId);
  runApp(const BillApp());
}

class BillApp extends StatelessWidget {
  const BillApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: Repository.instance.session),
        ChangeNotifierProvider.value(value: SyncEngine.instance),
        ChangeNotifierProvider.value(value: SubscriptionService.instance),
      ],
      child: Consumer<Session>(
        builder: (context, session, _) => MaterialApp(
          title: 'Billket',
          debugShowCheckedModeBanner: false,
          theme: buildStitchTheme(),
          locale: session.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AppGate(),
        ),
      ),
    );
  }
}

class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  String? _hydratedToken;
  bool _isHydrating = false;

  Future<void> _hydrateServerData(Session session) async {
    final token = session.token;
    if (token == null || token.isEmpty || _isHydrating || _hydratedToken == token) {
      return;
    }
    // If local database already has an active business, local data is sovereign;
    // do not block startup or wait for remote network calls.
    if (session.businessId != null) {
      _hydratedToken = token;
      return;
    }
    _hydratedToken = token;
    _isHydrating = true;

    final client = ApiClient()..setToken(token);

    try {
      final isOnline = await client.ping();
      if (!isOnline) {
        _isHydrating = false;
        return;
      }

      final businesses = await BusinessService(client).fetchBusinesses();
      if (businesses.isNotEmpty) {
        final existing = await Repository.instance.allBusinesses();
        for (final dto in businesses) {
          final normalized = dto.name.trim();
          final duplicate = existing.any(
            (business) =>
                business.name.toLowerCase() == normalized.toLowerCase(),
          );
          if (!duplicate && normalized.isNotEmpty) {
            final created = Business(
              name: dto.name,
              ownerName: dto.ownerName,
              currency: dto.currency,
            );
            final businessId =
                await Repository.instance.createBusiness(created);
            if (session.businessId == null) {
              await session.completeOnboarding(businessId);
            }
            existing.add(created);
          }
        }
      }
    } catch (_) {
      _isHydrating = false;
      return;
    }

    if (session.businessId == null) {
      _isHydrating = false;
      return;
    }

    try {
      final products = await InventoryService(client).fetchProducts();
      for (final dto in products) {
        final product = Product(
          name: dto.name,
          unit: 'pc',
          gstRate: dto.gstRate.toInt(),
          purchasePrice: 0,
          salePrice: dto.salePrice.toInt(),
          stock: dto.stock.toInt(),
        );
        await Repository.instance.upsertProduct(
          product,
          businessIdOverride: session.businessId!,
        );
      }
    } catch (_) {
      // Keep local data flow if the backend is unavailable.
    } finally {
      _isHydrating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    final token = session.token;
    if (token == null || token.isEmpty) {
      _hydratedToken = null;
    } else if (token != _hydratedToken && !_isHydrating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _hydrateServerData(session);
        }
      });
    }

    if (session.locked) return const PinLockScreen();
    if (session.businessId == null) return const AuthFlow();
    return const AppShell();
  }
}
