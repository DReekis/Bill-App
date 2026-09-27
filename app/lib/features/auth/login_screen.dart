import 'package:flutter/foundation.dart';
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

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _businessNameController = TextEditingController();

  bool _isRegister = false;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _errorMessage;
  bool _isUnregisteredSha1Error = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  String _friendlyAuthError(Object e, String serverUrl) {
    final msg = e.toString();
    _isUnregisteredSha1Error = false;

    if (msg.contains('SIGN_IN_CANCELLED') ||
        msg.contains('canceled') ||
        msg.contains('cancelled')) {
      return 'cancelled';
    }

    if (msg.contains('USER_EXISTS')) {
      return 'An account with this email already exists. Please sign in instead.';
    }

    if (msg.contains('INVALID_CREDENTIALS')) {
      return 'Invalid email or password. Please verify and try again.';
    }

    if (msg.contains('UNREGISTERED_ON_API_CONSOLE') ||
        msg.contains('providerConfigurationError') ||
        msg.contains('Account reauth failed') ||
        msg.contains('ApiException: 10') ||
        msg.contains('ApiException: 16') ||
        msg.contains('DEVELOPER_ERROR') ||
        msg.contains('[16]') ||
        msg.contains('[10]')) {
      _isUnregisteredSha1Error = true;
      return 'Google Sign-In is not registered yet for this Android build in Google Cloud Console. You can register with Email/Password or use Quick Test Sign-In below.';
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
      return 'Google Sign-In is not supported directly on this platform. Please sign in with Email & Password or use Quick Test Sign-In.';
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

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final businessName = _businessNameController.text.trim();

    if (_isRegister && name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
      _isUnregisteredSha1Error = false;
    });

    final apiClient = SyncEngine.instance.apiClient;

    try {
      await apiClient.ensureReady();
      final AuthSessionResult result;
      if (_isRegister) {
        result = await _authService.register(
          name: name,
          email: email,
          password: password,
          businessName: businessName.isNotEmpty ? businessName : null,
          apiClient: apiClient,
        );
        await _finishLogin(result, 'Account created! Welcome, ${result.user.displayName}');
      } else {
        result = await _authService.login(
          email: email,
          password: password,
          apiClient: apiClient,
        );
        await _finishLogin(result, 'Welcome back, ${result.user.displayName}!');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = _friendlyAuthError(e, apiClient.baseUrl);
      });
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

  Future<void> _handleDemoSignIn() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _isUnregisteredSha1Error = false;
    });

    final session = context.read<Session>();
    final apiClient = SyncEngine.instance.apiClient;

    try {
      await apiClient.ensureReady();
      final result = await _authService.mockSignInWithGoogle(
        email: 'business.owner@gmail.com',
        name: 'Rahul Sharma',
        apiClient: apiClient,
        businessName: session.currentUser,
      );
      await _finishLogin(result, 'Signed in to AWS Cloud (Quick Test Account)');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = _friendlyAuthError(e, apiClient.baseUrl);
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
                  const Text(
                    'Welcome to Billket',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Smart billing, GST invoices & inventory management for your business.',
                    style: TextStyle(
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
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (_isUnregisteredSha1Error)
                                TextButton.icon(
                                  onPressed: _showSha1Sheet,
                                  icon: const Icon(Icons.copy_rounded, size: 15),
                                  label: const Text('View SHA-1'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF2563EB),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              TextButton(
                                onPressed: _busy ? null : _handleDemoSignIn,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF4F46E5),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text(
                                  'Quick Test Sign-In',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Segmented Mode Switcher: Sign In vs Create Account
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (_isRegister) {
                                setState(() {
                                  _isRegister = false;
                                  _errorMessage = null;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(11),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !_isRegister ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: !_isRegister
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: !_isRegister
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (!_isRegister) {
                                setState(() {
                                  _isRegister = true;
                                  _errorMessage = null;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(11),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _isRegister ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: _isRegister
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _isRegister
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Form Fields
                  if (_isRegister) ...[
                    AppTextField(
                      controller: _nameController,
                      label: 'Your Name *',
                      hint: 'e.g. Rahul Sharma',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _businessNameController,
                      label: 'Store / Business Name',
                      hint: 'e.g. Modern Retail Store',
                      icon: Icons.storefront_outlined,
                    ),
                    const SizedBox(height: 14),
                  ],

                  AppTextField(
                    controller: _emailController,
                    label: 'Email Address *',
                    hint: 'e.g. merchant@gmail.com',
                    keyboardType: TextInputType.emailAddress,
                    icon: Icons.alternate_email_rounded,
                  ),
                  const SizedBox(height: 14),

                  AppTextField(
                    controller: _passwordController,
                    label: 'Password *',
                    hint: 'Minimum 6 characters',
                    obscure: _obscurePassword,
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: const Color(0xFF94A3B8),
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _handleEmailAuth,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isRegister ? Icons.cloud_upload_rounded : Icons.login_rounded,
                                  size: 19,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _isRegister ? 'Create Account & Sync' : 'Sign In to Cloud',
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF94A3B8),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Secondary Action: Google Sign-In Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _handleGoogleSignIn,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _GoogleGLogo(),
                          const SizedBox(width: 12),
                          const Text(
                            'Sign in with Google',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Quick AWS Demo Sign-In
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _handleDemoSignIn,
                      icon: const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFF4F46E5)),
                      label: const Text(
                        '1-Click Quick Test (Connects to AWS)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFEEF2FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Offline First Option
                  TextButton.icon(
                    onPressed: _continueOffline,
                    icon: const Icon(Icons.offline_bolt_outlined, size: 16, color: Color(0xFF64748B)),
                    label: const Text(
                      'Continue Offline (Local Storage)',
                      style: TextStyle(
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
                        const Expanded(
                          child: Text(
                            'Each user account has its own isolated database space on AWS Cloud. Multi-device sync happens automatically in real time.',
                            style: TextStyle(
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
