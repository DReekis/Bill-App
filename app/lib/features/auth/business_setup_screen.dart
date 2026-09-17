import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/business_service.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../data/repositories.dart';
import '../../data/seed_data.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import '../shell/app_shell.dart';

class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key, required this.phone});
  final String phone;
  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final owner = TextEditingController();
  final gstin = TextEditingController();
  final stateController = TextEditingController();
  final city = TextEditingController();
  final prefix = TextEditingController(text: 'INV');
  String? industry;
  bool taxRegistered = true;
  bool loadSample = true;

  @override
  void dispose() {
    for (final c in [name, owner, gstin, stateController, city, prefix]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!formKey.currentState!.validate()) return;

    final session = context.read<Session>();

    try {
      final business = Business(
        name: name.text.trim(),
        ownerName: owner.text.trim().isEmpty ? null : owner.text.trim(),
        gstin:
            gstin.text.trim().isEmpty ? null : gstin.text.trim().toUpperCase(),
        state: stateController.text.trim().isEmpty
            ? null
            : stateController.text.trim(),
        city: city.text.trim().isEmpty ? null : city.text.trim(),
        industry: industry,
        invoicePrefix: prefix.text.trim().isEmpty ? 'INV' : prefix.text.trim(),
        taxRegistered: taxRegistered,
      );

      if (session.token != null && session.token!.isNotEmpty) {
        final client = ApiClient()..setToken(session.token!);
        try {
          await BusinessService(client).createBusiness(
            name: business.name,
            ownerName: business.ownerName,
            gstin: business.gstin,
            city: business.city,
            state: business.state,
          ).timeout(const Duration(seconds: 2));
        } catch (_) {
          if (kDebugMode) {
            debugPrint(
                'Backend business creation unavailable; local flow continues.');
          }
        }
      }

      final businessId = await Repository.instance.createBusiness(business);

      if (loadSample) {
        try {
          await seedDemoData(Repository.instance, businessId);
        } catch (seedError) {
          if (kDebugMode) {
            debugPrint('Seed data error (non-blocking): $seedError');
          }
        }
      }

      await session.completeOnboarding(businessId);

      if (mounted) {
        showAppMessage(context, 'Business created successfully!');
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AppShell()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppMessage(context, 'Error: ${e.toString()}', error: true);
        if (kDebugMode) debugPrint('Business creation error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business Setup')),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Set up your store profile',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('These details appear on your GST invoices.',
                  style: TextStyle(
                      fontSize: 13, color: StitchColors.textSecondary)),
              const SizedBox(height: 24),
              AppTextField(
                  controller: name,
                  label: 'Business name',
                  hint: 'e.g. Modern Retail Store',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Business name is required'
                      : null),
              const SizedBox(height: 14),
              AppTextField(
                  controller: owner,
                  label: 'Owner name',
                  icon: Icons.person_outline_rounded),
              const SizedBox(height: 14),
              AppTextField(
                  controller: gstin,
                  label: 'GSTIN (Optional)',
                  hint: 'e.g. 29AAAAA0000A1Z5',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return RegExp(
                                r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[Z]{1}[0-9A-Z]{1}$')
                            .hasMatch(v.trim())
                        ? null
                        : 'Invalid GSTIN format';
                  }),
              const SizedBox(height: 14),
              AppTextField(
                  controller: stateController,
                  label: 'State',
                  hint: 'e.g. Karnataka'),
              const SizedBox(height: 14),
              AppTextField(controller: city, label: 'City'),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: industry,
                decoration: const InputDecoration(labelText: 'Industry'),
                items: businessIndustries
                    .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                    .toList(),
                onChanged: (v) => setState(() => industry = v),
              ),
              const SizedBox(height: 14),
              AppTextField(
                  controller: prefix, label: 'Invoice prefix', hint: 'INV'),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('GST registered'),
                subtitle: const Text('Enables CGST/SGST/IGST on bills'),
                value: taxRegistered,
                onChanged: (v) => setState(() => taxRegistered = v),
                activeThumbColor: StitchColors.primary,
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Load sample data'),
                subtitle:
                    const Text('Pre-fill products, customers and invoices'),
                value: loadSample,
                onChanged: (v) => setState(() => loadSample = v),
                activeThumbColor: StitchColors.primary,
              ),
              const SizedBox(height: 24),
              AsyncButton(
                  label: 'Create business',
                  onPressed: _create,
                  icon: Icons.check_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
