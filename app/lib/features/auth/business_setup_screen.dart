import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/business_service.dart';
import '../../core/gst_service.dart';
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

  bool fetchingGst = false;
  String? gstStatusMessage;
  bool gstValid = false;

  @override
  void dispose() {
    for (final c in [name, owner, gstin, stateController, city, prefix]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchGstDetails([String? specificGstin]) async {
    final target = (specificGstin ?? gstin.text).trim().toUpperCase();
    if (target.isEmpty) return;
    if (target.length != 15) {
      showAppMessage(context, 'GSTIN must be 15 characters', error: true);
      return;
    }

    setState(() {
      fetchingGst = true;
      gstStatusMessage = null;
    });

    try {
      final session = context.read<Session>();
      final client = session.token != null ? (ApiClient()..setToken(session.token!)) : null;
      final info = await GstService.instance.lookup(target, apiClient: client);
      if (!mounted) return;

      setState(() {
        if (info.effectiveName.isNotEmpty) {
          name.text = info.effectiveName;
        }
        if (info.effectiveOwner.isNotEmpty) {
          owner.text = info.effectiveOwner;
        }
        if (info.state != null && info.state!.isNotEmpty) {
          stateController.text = info.state!;
        }
        if (info.city != null && info.city!.isNotEmpty) {
          city.text = info.city!;
        }
        if (info.industry != null && businessIndustries.contains(info.industry)) {
          industry = info.industry;
        }
        taxRegistered = true;
        gstValid = info.valid;
        gstStatusMessage = info.isOnlineFetched
            ? '✓ Verified GSTIN (${info.status} • ${info.state ?? "India"})'
            : '✓ Identified (${info.constitution ?? "GST Registered"} • ${info.state ?? "India"})';
      });

      showAppMessage(
        context,
        info.effectiveName.isNotEmpty
            ? 'Business details auto-filled for ${info.effectiveName}'
            : 'GST location & taxpayer details auto-filled',
      );
    } catch (e) {
      if (mounted) {
        setState(() => gstStatusMessage = 'Could not auto-fill: $e');
      }
    } finally {
      if (mounted) setState(() => fetchingGst = false);
    }
  }

  Future<void> _create() async {
    if (!formKey.currentState!.validate()) return;

    final session = context.read<Session>();

    try {
      final business = Business(
        name: name.text.trim(),
        ownerName: owner.text.trim().isEmpty ? null : owner.text.trim(),
        gstin: gstin.text.trim().isEmpty ? null : gstin.text.trim().toUpperCase(),
        state: stateController.text.trim().isEmpty ? null : stateController.text.trim(),
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
            debugPrint('Backend business creation unavailable; local flow continues.');
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
              const Text('Enter your GST number for instant auto-fill, or fill manually.',
                  style: TextStyle(fontSize: 13, color: StitchColors.textSecondary)),
              const SizedBox(height: 18),

              // Prominent GST Auto-fill Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: StitchColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: StitchColors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt_rounded, size: 18, color: StitchColors.primary),
                        const SizedBox(width: 6),
                        const Text(
                          'Have a GST Number?',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StitchColors.primary),
                        ),
                        const Spacer(),
                        if (fetchingGst)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: StitchColors.primary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: gstin,
                      label: 'GSTIN (15 characters)',
                      hint: 'e.g. 29AAAAA0000A1Z5',
                      onChanged: (v) {
                        final clean = v.trim().toUpperCase();
                        if (clean.length == 15) {
                          _fetchGstDetails(clean);
                        } else if (gstStatusMessage != null) {
                          setState(() {
                            gstStatusMessage = null;
                            gstValid = false;
                          });
                        }
                      },
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        return GstService.isValidGstinFormat(v.trim()) ? null : 'Invalid GSTIN format';
                      },
                    ),
                    if (gstStatusMessage != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            gstValid ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                            size: 15,
                            color: gstValid ? StitchColors.success : StitchColors.warning,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              gstStatusMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: gstValid ? StitchColors.success : StitchColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 18),
              AppTextField(
                controller: name,
                label: 'Business name *',
                hint: 'e.g. Modern Retail Store',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Business name is required' : null,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: owner,
                label: 'Owner / Proprietor name',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: stateController,
                      label: 'State',
                      hint: 'e.g. Karnataka',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: city,
                      label: 'City',
                      hint: 'e.g. Bengaluru',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: industry,
                decoration: const InputDecoration(labelText: 'Industry / Constitution'),
                items: businessIndustries
                    .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                    .toList(),
                onChanged: (v) => setState(() => industry = v),
              ),
              const SizedBox(height: 14),
              AppTextField(controller: prefix, label: 'Invoice prefix', hint: 'INV'),
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
                subtitle: const Text('Pre-fill products, customers and invoices'),
                value: loadSample,
                onChanged: (v) => setState(() => loadSample = v),
                activeThumbColor: StitchColors.primary,
              ),
              const SizedBox(height: 24),
              AsyncButton(
                label: 'Create business',
                onPressed: _create,
                icon: Icons.check_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
