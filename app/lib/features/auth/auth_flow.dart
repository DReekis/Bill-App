import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_service.dart';
import '../../core/session.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';
import 'business_setup_screen.dart';

class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});
  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  String? _phone;

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    if (phone == null) {
      return LoginOtpScreen(
        onVerified: (value) async {
          final session = SessionProvider.of(context);
          await session.savePhone(value);
          if (mounted) setState(() => _phone = value);
        },
      );
    }
    return BusinessSetupScreen(phone: phone);
  }
}

class SessionProvider {
  static Session of(BuildContext context) => context.read<Session>();
}

class LoginOtpScreen extends StatefulWidget {
  const LoginOtpScreen({super.key, required this.onVerified});
  final ValueChanged<String> onVerified;
  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  var step = 0;
  static const _demoOtp = '123456';

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  void _sendOtp() {
    final phone = phoneController.text.trim();
    if (phone.length != 10) {
      showAppMessage(context, 'Enter a 10 digit mobile number', error: true);
      return;
    }
    setState(() => step = 1);
  }

  Future<void> _verifyOtp() async {
    if (otpController.text.trim() != _demoOtp) {
      if (mounted) {
        showAppMessage(context, 'Incorrect OTP. Try again.', error: true);
      }
      return;
    }

    final phone = phoneController.text.trim();
    final session = SessionProvider.of(context);
    final email = '$phone@pricepilot.local';
    final password = 'pp${phone.substring(phone.length - 4)}';
    final client = ApiClient();
    final service = AuthService(client);

    try {
      // Fast check if backend is reachable (max 1.2s)
      final reachable = await client
          .ping()
          .timeout(const Duration(milliseconds: 1200), onTimeout: () => false);

      if (reachable) {
        try {
          final auth = await service
              .register(
                name: 'Business Owner',
                email: email,
                password: password,
              )
              .timeout(const Duration(seconds: 2));
          client.setToken(auth.token);
          await session.savePhone(phone);
          await session.saveAuthToken(auth.token);
          if (mounted) widget.onVerified(phone);
          return;
        } catch (_) {
          try {
            final auth = await service
                .login(
                  email: email,
                  password: password,
                )
                .timeout(const Duration(seconds: 2));
            client.setToken(auth.token);
            await session.savePhone(phone);
            await session.saveAuthToken(auth.token);
            if (mounted) widget.onVerified(phone);
            return;
          } catch (_) {}
        }
      }

      // If backend is offline, unreachable or timed out, proceed immediately with local flow
      await session.savePhone(phone);
      if (mounted) {
        widget.onVerified(phone);
      }
    } catch (_) {
      await session.savePhone(phone);
      if (mounted) {
        widget.onVerified(phone);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: StitchColors.primary,
                    borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(height: 24),
              const Text('Welcome to Stitch Bill',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              const SizedBox(height: 8),
              const Text(
                  'Manage your business ledger, inventory, GST bills and reports in one place.',
                  style: TextStyle(
                      fontSize: 14,
                      color: StitchColors.textSecondary,
                      height: 1.4)),
              const SizedBox(height: 36),
              if (step == 0) ...[
                const Text('Mobile Number',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: StitchColors.outline),
                      ),
                      child: const Text('+91',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: 'Enter 10 digit number',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                AsyncButton(
                  label: 'Send OTP',
                  onPressed: _sendOtp,
                  icon: Icons.sms_outlined,
                ),
                const SizedBox(height: 14),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.security_rounded,
                        color: StitchColors.success, size: 14),
                    SizedBox(width: 6),
                    Text('Mock OTP mode — no SMS backend connected',
                        style: TextStyle(
                            color: StitchColors.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ] else ...[
                const Text('Verify OTP',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('OTP sent to +91 ${phoneController.text.trim()}',
                    style: const TextStyle(
                        fontSize: 13, color: StitchColors.textSecondary)),
                const SizedBox(height: 20),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 10),
                  decoration: const InputDecoration(
                      counterText: '', hintText: '••••••'),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: StitchColors.warningSoft,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded,
                        color: StitchColors.warning, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('Demo OTP is 123456',
                            style: TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 13,
                                fontWeight: FontWeight.w600))),
                  ]),
                ),
                const SizedBox(height: 24),
                AsyncButton(
                    label: 'Verify & Continue',
                    onPressed: _verifyOtp,
                    icon: Icons.verified_rounded),
                TextButton(
                  onPressed: () => setState(() => step = 0),
                  child: const Text('Change number'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
