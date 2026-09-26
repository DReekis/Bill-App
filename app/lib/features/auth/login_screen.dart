import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_service.dart';
import '../../core/session.dart';
import '../../theme/stitch_theme.dart';
import '../../utils/widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.isModal = false,
    this.onSuccess,
    this.onOffline,
  });

  final bool isModal;
  final VoidCallback? onSuccess;
  final VoidCallback? onOffline;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = CloudAuthService();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _busy = false;
  bool _showPhoneSection = false;
  bool _otpSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final session = context.read<Session>();
    final apiClient = ApiClient();

    try {
      final result = await _authService.signInWithGoogle(
        apiClient: apiClient,
        businessName: session.currentUser,
      );

      await session.linkCloudSession(result);

      if (!mounted) return;
      showAppMessage(context, 'Signed in as ${result.user.displayName}');
      widget.onSuccess?.call();
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('SIGN_IN_CANCELLED')) {
        // User voluntarily dismissed the Google picker
        setState(() => _busy = false);
        return;
      }

      // If Google Play Services is missing (desktop/emulator), allow 1-tap simulation
      setState(() {
        _busy = false;
        _errorMessage = 'Google Sign-In failed on this device. Would you like to use Quick Demo Sign-In?';
      });
    }
  }

  Future<void> _handleDemoSignIn() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final session = context.read<Session>();
    final apiClient = ApiClient();

    try {
      final result = await _authService.mockSignInWithGoogle(
        email: 'business.owner@gmail.com',
        name: 'Rahul Sharma',
        apiClient: apiClient,
        businessName: session.currentUser,
      );

      await session.linkCloudSession(result);

      if (!mounted) return;
      showAppMessage(context, 'Signed in with Google (Demo)');
      widget.onSuccess?.call();
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Cloud server connection failed. Please ensure the backend is running.';
      });
    }
  }

  Future<void> _handlePhoneAuth() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      showAppMessage(context, 'Please enter a valid 10-digit mobile number', error: true);
      return;
    }

    if (!_otpSent) {
      setState(() {
        _busy = true;
        _errorMessage = null;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpSent = true;
      });
      showAppMessage(context, 'OTP sent (Use 1234 for testing)');
      return;
    }

    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      showAppMessage(context, 'Please enter the OTP received', error: true);
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final session = context.read<Session>();
      final result = await _authService.signInWithPhone(
        phone: phone,
        otp: otp,
      );

      await session.linkCloudSession(result);

      if (!mounted) return;
      showAppMessage(context, 'Signed in via mobile number');
      widget.onSuccess?.call();
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.isModal
            ? IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF1E293B)),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),

              // Cloud Sync Brand Hero
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5B4DBC), Color(0xFF7E72D6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5B4DBC).withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 20),

              const Text(
                'Connect to Billket Cloud',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Multi-user access, encrypted cloud backups, and automatic device sync across all your phones & tablets.',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Benefits pill list
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Column(
                  children: [
                    _FeatureRow(
                      icon: Icons.lock_outline_rounded,
                      title: 'AES-256 Cloud Backup',
                      subtitle: 'Never lose transactions even if your phone breaks',
                    ),
                    Divider(height: 20, color: Color(0xFFEDF2F7)),
                    _FeatureRow(
                      icon: Icons.sync_rounded,
                      title: 'On-Demand Multi-User Sync',
                      subtitle: 'Sync staff bills on-demand without WebSocket battery drain',
                    ),
                    Divider(height: 20, color: Color(0xFFEDF2F7)),
                    _FeatureRow(
                      icon: Icons.verified_user_outlined,
                      title: 'Role-Based Operational Security',
                      subtitle: 'Safeguard purchase costs, profits, and bank balances',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF991B1B), fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_errorMessage!.contains('Quick Demo'))
                        TextButton(
                          onPressed: _busy ? null : _handleDemoSignIn,
                          child: const Text('Simulate', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Primary Action: Google Sign-In Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _busy ? null : _handleGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 1,
                    shadowColor: Colors.black.withValues(alpha: 0.04),
                  ),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Official Google G Logo
                            _GoogleGLogo(),
                            const SizedBox(width: 12),
                            const Text(
                              'Sign in with Google',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Upgradable Mobile Phone Authentication Expansion
              InkWell(
                onTap: () => setState(() => _showPhoneSection = !_showPhoneSection),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showPhoneSection ? Icons.keyboard_arrow_up_rounded : Icons.phone_android_rounded,
                        size: 16,
                        color: const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showPhoneSection ? 'Hide Phone Login' : 'Or sign in with Mobile Number',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_showPhoneSection) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mobile Number Sign-In (Upgradable)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: 'Enter 10-digit mobile number',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                      if (_otpSent) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          decoration: InputDecoration(
                            hintText: 'Enter 4-digit OTP (e.g. 1234)',
                            prefixIcon: const Icon(Icons.lock_clock_outlined, size: 20),
                            filled: true,
                            fillColor: Colors.white,
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _handlePhoneAuth,
                          style: FilledButton.styleFrom(
                            backgroundColor: StitchColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(_otpSent ? 'Verify OTP & Continue' : 'Get OTP'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // Non-blocking Sovereign Local SQLite Option
              TextButton(
                onPressed: () {
                  widget.onOffline?.call();
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context, false);
                  }
                },
                child: const Text(
                  'Continue Offline (Keep Local SQLite Sovereign)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFF5B4DBC).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF5B4DBC), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoogleGLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      child: CustomPaint(
        size: const Size(20, 20),
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final paintBlue = Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.fill;
    final paintRed = Paint()..color = const Color(0xFFEA4335)..style = PaintingStyle.fill;
    final paintYellow = Paint()..color = const Color(0xFFFBBC05)..style = PaintingStyle.fill;
    final paintGreen = Paint()..color = const Color(0xFF34A853)..style = PaintingStyle.fill;

    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    // Draw Google 4-color arcs cleanly
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -0.785, 1.57, true, paintBlue);
    canvas.drawArc(rect, 0.785, 1.57, true, paintGreen);
    canvas.drawArc(rect, 2.355, 1.57, true, paintYellow);
    canvas.drawArc(rect, 3.925, 1.57, true, paintRed);

    // Inner cutout
    final innerPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.58, innerPaint);

    // Crossbar
    final barRect = Rect.fromLTWH(center.dx - 1, center.dy - (radius * 0.22), radius + 1, radius * 0.44);
    canvas.drawRect(barRect, paintBlue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
