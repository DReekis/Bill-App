import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/google_auth_config.dart';
import '../../core/session.dart';
import '../../sync/sync_engine.dart';
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

  bool _busy = false;
  String? _errorMessage;
  bool _isUnregisteredSha1Error = false;

  String _friendlyAuthError(Object e, String serverUrl) {
    final msg = e.toString();
    _isUnregisteredSha1Error = false;

    if (msg.contains('SIGN_IN_CANCELLED') ||
        msg.contains('canceled') ||
        msg.contains('cancelled')) {
      return 'cancelled';
    }

    if (msg.contains('28444') ||
        msg.contains('Developer console is not set up correctly') ||
        msg.contains('UNREGISTERED_ON_API_CONSOLE') ||
        msg.contains('providerConfigurationError') ||
        msg.contains('Account reauth failed') ||
        msg.contains('ApiException: 10') ||
        msg.contains('ApiException: 16') ||
        msg.contains('DEVELOPER_ERROR') ||
        msg.contains('[16]') ||
        msg.contains('[10]')) {
      _isUnregisteredSha1Error = true;
      return 'Google Cloud Console configuration issue ([28444]):\n• In OAuth consent screen, add your Google account to "Test users" (or click "Publish App").\n• Ensure package name "com.pricepilot.bill" and SHA-1 match your Android Client ID.';
    }

    if (msg.contains('SocketException') ||
        msg.contains('TimeoutException') ||
        msg.contains('Timed out') ||
        msg.contains('Failed host lookup') ||
        msg.contains('ClientException') ||
        msg.contains('Connection refused') ||
        msg.contains('Connection timed out')) {
      return 'Cannot reach Billket Cloud at $serverUrl. Please ensure the cloud server is online and your internet is connected.';
    }

    if (msg.contains('GOOGLE_SIGN_IN_UNSUPPORTED') || msg.contains('UnimplementedError')) {
      return 'Google Sign-In is not supported directly on this platform. Please continue offline or use a supported device.';
    }

    if (msg.contains('UNAUTHORIZED_CLIENT_AUDIENCE') || msg.contains('INVALID_GOOGLE_TOKEN')) {
      return 'Google token was rejected by the cloud server. Ensure GOOGLE_CLIENT_ID on AWS matches the Web client ID.';
    }

    if (msg.contains('MISSING_ID_TOKEN')) {
      return 'Google did not return an ID token. Confirm the Web client ID is configured as serverClientId.';
    }

    return msg
        .replaceAll('Exception: ', '')
        .replaceAll('PlatformException(', '')
        .replaceAll(')', '');
  }

  Future<void> _finishLogin(AuthSessionResult result, String successMessage) async {
    final session = context.read<Session>();
    await session.linkCloudSession(result);

    // Start auto sync and immediately push existing local/test records to cloud
    SyncEngine.instance.startAutoSync();
    SyncEngine.instance.syncNow(force: true);

    if (!mounted) return;
    setState(() => _busy = false);
    showAppMessage(context, successMessage);
    widget.onSuccess?.call();
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _isUnregisteredSha1Error = false;
    });

    final session = context.read<Session>();
    final apiClient = SyncEngine.instance.apiClient;

    try {
      await apiClient.ensureReady();
      final result = await _authService.signInWithGoogle(
        apiClient: apiClient,
        businessName: session.currentUser,
      );
      await _finishLogin(result, 'Signed in as ${result.user.displayName}');
    } catch (e) {
      if (!mounted) return;
      final msg = _friendlyAuthError(e, apiClient.baseUrl);
      if (msg == 'cancelled') {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = msg;
      });
    }
  }

  void _showSha1Sheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.security_rounded, color: Color(0xFF2563EB), size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Cloud Registration',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Add this SHA-1 to Google Cloud Console',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Package Name',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const SelectableText(
                  GoogleAuthConfig.appPackageName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Signing Certificate SHA-1',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const SelectableText(
                  GoogleAuthConfig.debugSha1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: GoogleAuthConfig.debugSha1));
                    Navigator.pop(ctx);
                    showAppMessage(context, 'SHA-1 fingerprint copied to clipboard!');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy SHA-1 Fingerprint', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _continueOffline() {
    widget.onOffline?.call();
    if (Navigator.canPop(context)) {
      Navigator.pop(context, false);
    }
  }

  void _showLanguageSheet(BuildContext context, Session session) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                'Choose Language / भाषा चुनें / ভাষা নির্বাচন',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.language_rounded, color: Color(0xFF4F46E5)),
              title: const Text('English', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: session.localeCode == 'en'
                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A))
                  : null,
              onTap: () {
                session.setLocale('en');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded, color: Color(0xFF4F46E5)),
              title: const Text('हिन्दी (Hindi)', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: session.localeCode == 'hi'
                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A))
                  : null,
              onTap: () {
                session.setLocale('hi');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.g_translate_rounded, color: Color(0xFF4F46E5)),
              title: const Text('বাংলা (Bengali)', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: session.localeCode == 'bn'
                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A))
                  : null,
              onTap: () {
                session.setLocale('bn');
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final isBn = session.localeCode == 'bn';
    final isHi = session.localeCode == 'hi';

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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => _showLanguageSheet(context, session),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF1F5F9),
                foregroundColor: const Color(0xFF334155),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              icon: const Icon(Icons.language_rounded, size: 16, color: Color(0xFF4F46E5)),
              label: Text(
                isBn ? 'বাংলা' : isHi ? 'हिन्दी' : 'English',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Brand Hero Emblem
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // App Title & Friendly Welcome
                  Text(
                    isBn ? 'বিলকেটে স্বাগতম' : isHi ? 'बिलकेट में आपका स्वागत है' : 'Welcome to Billket',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isBn
                        ? 'আপনার ব্যবসার জন্য স্মার্ট বিলিং, জিএসটি ইনভয়েস ও ইনভেন্টরি ম্যানেজমেন্ট।'
                        : isHi
                            ? 'आपके व्यापार के लिए स्मार्ट बिलिंग, जीएसटी इनवॉइस और स्टॉक प्रबंधन।'
                            : 'Smart billing, GST invoices & inventory management for your business.',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),

                  // Error Banner
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF991B1B),
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_isUnregisteredSha1Error) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _showSha1Sheet,
                                icon: const Icon(Icons.copy_rounded, size: 15),
                                label: const Text('View Required SHA-1'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF2563EB),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Primary Production Action: Google Sign-In Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _handleGoogleSignIn,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 1,
                        shadowColor: Colors.black.withValues(alpha: 0.05),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Color(0xFF4F46E5),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _GoogleGLogo(),
                                const SizedBox(width: 14),
                                Text(
                                  isBn ? 'গুগল দিয়ে সাইন ইন করুন' : isHi ? 'Google से साइन इन करें' : 'Sign in with Google',
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Offline First Option
                  TextButton.icon(
                    onPressed: _continueOffline,
                    icon: const Icon(Icons.offline_bolt_outlined, size: 16, color: Color(0xFF64748B)),
                    label: Text(
                      isBn ? 'অফলাইনে চালু রাখুন (লোকাল মেমোরি)' : isHi ? 'ऑफ़लाइन जारी रखें (स्थानीय मेमोरी)' : 'Continue Offline (Local Storage)',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Trust & Privacy Note
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isBn
                                ? 'প্রতিটি ব্যবহারকারীর ডেটা ক্লাউডে সুরক্ষিত ও পৃথক থাকে। রিয়েল টাইমে ডিভাইস সিঙ্ক হয়।'
                                : isHi
                                    ? 'प्रत्येक उपयोगकर्ता का डेटा क्लाउड पर अलग और सुरक्षित रहता है। सभी डिवाइस तुरंत सिंक होते हैं।'
                                    : 'Each user account has its own isolated database space on AWS Cloud. Multi-device sync happens automatically in real time.',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
