import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security_service.dart';
import '../../core/session.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/stitch_theme.dart';

class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});
  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String pin = '';
  bool get _full => pin.length == 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoBiometric();
    });
  }

  Future<void> _checkAutoBiometric() async {
    final session = context.read<Session>();
    if (session.biometricEnabled) {
      await _triggerBiometric();
    }
  }

  Future<void> _triggerBiometric() async {
    final session = context.read<Session>();
    final success = await SecurityService.instance.authenticateBiometric(
      reason: 'Unlock Billket with biometric credentials',
    );
    if (success && mounted) {
      session.unlock();
    }
  }

  void _press(String digit) {
    if (_full) return;
    setState(() => pin += digit);
    if (_full) {
      Future.delayed(const Duration(milliseconds: 150), () async {
        if (!mounted) return;
        final session = context.read<Session>();
        if (session.verifyPin(pin)) {
          session.unlock();
        } else {
          if (mounted) {
            setState(() => pin = '');
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Wrong PIN'), backgroundColor: StitchColors.error));
          }
        }
      });
    }
  }

  void _back() {
    if (pin.isEmpty) return;
    setState(() => pin = pin.substring(0, pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: StitchColors.primary, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 18),
            Text(l10n.text('app_locked'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Enter your PIN to continue',
                style: TextStyle(color: StitchColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < pin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? StitchColors.primary : Colors.transparent,
                    border: Border.all(color: filled ? StitchColors.primary : StitchColors.outlineStrong, width: 2),
                  ),
                );
              }),
            ),
            const SizedBox(height: 36),
            _padRow(['1', '2', '3']),
            _padRow(['4', '5', '6']),
            _padRow(['7', '8', '9']),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (session.biometricEnabled) _bioKey() else const SizedBox(width: 72),
                  _padKey('0'),
                  _backKey(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _padRow(List<String> keys) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: keys.map((k) => _padKey(k)).toList()),
      );

  Widget _padKey(String digit) => InkWell(
        onTap: () => _press(digit),
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Text(digit,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _backKey() => InkWell(
        onTap: _back,
        borderRadius: BorderRadius.circular(24),
        child: const SizedBox(
          width: 72,
          height: 72,
          child: Center(child: Icon(Icons.backspace_outlined, color: StitchColors.textSecondary, size: 24)),
        ),
      );

  Widget _bioKey() => InkWell(
        onTap: _triggerBiometric,
        borderRadius: BorderRadius.circular(24),
        child: const SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Icon(Icons.fingerprint_rounded, color: StitchColors.primary, size: 34),
          ),
        ),
      );
}