import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'api_client.dart';
import 'subscription_service.dart';

class RazorpayCheckoutResult {
  const RazorpayCheckoutResult({
    required this.success,
    this.message,
    this.orderId,
    this.paymentId,
    this.signature,
    this.tier,
  });

  final bool success;
  final String? message;
  final String? orderId;
  final String? paymentId;
  final String? signature;
  final SubscriptionTier? tier;
}

class RazorpayService {
  RazorpayService._() {
    _initRazorpay();
  }

  static final RazorpayService instance = RazorpayService._();

  Razorpay? _razorpay;
  Completer<RazorpayCheckoutResult>? _pendingCompleter;
  String? _activeOrderId;
  String? _activeBusinessId;
  int? _activeLocalBusinessId;
  SubscriptionTier? _activeTier;
  String? _activeAuthToken;

  void _initRazorpay() {
    if (kIsWeb) return;
    // Native Razorpay SDK operates on Android & iOS
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!isMobile) return;

    try {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    } catch (e) {
      debugPrint('[RazorpayService] init error: $e');
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint('[RazorpayService] Payment Success: ${response.paymentId}');
    final orderId = response.orderId ?? _activeOrderId;
    final paymentId = response.paymentId;
    final signature = response.signature;

    if (orderId == null || paymentId == null || signature == null) {
      _pendingCompleter?.complete(
        const RazorpayCheckoutResult(
          success: false,
          message: 'Incomplete payment response from gateway.',
        ),
      );
      return;
    }

    try {
      // Cryptographic verification on backend server
      final res = await ApiClient.instance.post(
        '/api/v1/subscription/verify-payment',
        {
          'businessId': _activeBusinessId ?? '',
          'orderId': orderId,
          'paymentId': paymentId,
          'signature': signature,
        },
        token: _activeAuthToken,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tier = _activeTier ?? SubscriptionTier.silver;
        final expiresAt = data['expiresAt'] != null
            ? (DateTime.tryParse(data['expiresAt']) ??
                DateTime.now().add(const Duration(days: 365)))
            : DateTime.now().add(const Duration(days: 365));

        await SubscriptionService.instance.setSubscription(
          tier: tier,
          expiresAt: expiresAt,
          status: 'active',
          businessId: _activeLocalBusinessId,
        );

        _pendingCompleter?.complete(
          RazorpayCheckoutResult(
            success: true,
            orderId: orderId,
            paymentId: paymentId,
            signature: signature,
            tier: tier,
            message: 'Subscription successfully upgraded to ${tier.displayName}!',
          ),
        );
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Payment verification failed.';
        _pendingCompleter?.complete(
          RazorpayCheckoutResult(
            success: false,
            message: 'Server verification rejected: $err',
          ),
        );
      }
    } catch (e) {
      _pendingCompleter?.complete(
        RazorpayCheckoutResult(
          success: false,
          message: 'Network error during verification: $e',
        ),
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('[RazorpayService] Payment Failure: ${response.code} - ${response.message}');
    _pendingCompleter?.complete(
      RazorpayCheckoutResult(
        success: false,
        message: response.message ?? 'Payment cancelled or failed.',
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('[RazorpayService] External Wallet: ${response.walletName}');
  }

  /// Initiates plan purchase flow with Razorpay.
  /// Generates verified backend order, opens payment checkout UI, and verifies signature.
  Future<RazorpayCheckoutResult> checkout({
    required SubscriptionTier tier,
    required String cloudBusinessId,
    required String businessName,
    int? localBusinessId,
    String? email,
    String? phone,
    String? token,
  }) async {
    if (tier == SubscriptionTier.free) {
      return const RazorpayCheckoutResult(
        success: false,
        message: 'Free plan does not require checkout.',
      );
    }

    _activeBusinessId = cloudBusinessId;
    _activeLocalBusinessId = localBusinessId;
    _activeTier = tier;
    _activeAuthToken = token;
    _pendingCompleter = Completer<RazorpayCheckoutResult>();

    try {
      // 1. Create order on backend with tamper-proof server-side pricing
      final res = await ApiClient.instance.post(
        '/api/v1/subscription/create-order',
        {
          'businessId': cloudBusinessId,
          'tier': tier.key,
        },
        token: token,
      );

      if (res.statusCode != 201) {
        final err = jsonDecode(res.body)['error'] ?? 'Could not create order';
        return RazorpayCheckoutResult(
          success: false,
          message: 'Order creation failed: $err',
        );
      }

      final orderData = jsonDecode(res.body);
      final orderId = orderData['orderId'] as String;
      final keyId = orderData['keyId'] as String? ?? 'rzp_test_TlVBcJ5F1D187V';
      final amount = orderData['amount'] as int;
      _activeOrderId = orderId;

      final isMobile = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);

      if (!isMobile || _razorpay == null) {
        // Desktop or test environment bridge:
        // Automatically simulates or provides test token completion for local desktop testing
        debugPrint('[RazorpayService] Running on non-mobile platform or test runner. Simulating verified test checkout.');
        return await _simulateDesktopTestPayment(
          cloudBusinessId: cloudBusinessId,
          orderId: orderId,
          tier: tier,
          localBusinessId: localBusinessId,
          token: token,
        );
      }

      // 2. Open Razorpay Gateway Modal
      final options = {
        'key': keyId,
        'amount': amount,
        'name': businessName.isNotEmpty ? businessName : 'PricePilot Enterprise',
        'description': 'Annual Subscription - ${tier.displayName}',
        'order_id': orderId,
        'timeout': 300,
        'prefill': {
          'contact': phone ?? '',
          'email': email ?? '',
        },
        'theme': {
          'color': '#0F172A',
        },
      };

      _razorpay!.open(options);
      return await _pendingCompleter!.future;
    } catch (e) {
      return RazorpayCheckoutResult(
        success: false,
        message: 'Checkout encountered an error: $e',
      );
    }
  }

  /// Internal bridge for desktop/test suite runs to simulate verified test transactions
  Future<RazorpayCheckoutResult> _simulateDesktopTestPayment({
    required String cloudBusinessId,
    required String orderId,
    required SubscriptionTier tier,
    int? localBusinessId,
    String? token,
  }) async {
    // In desktop test environment, we directly invoke verify-payment with mock test token
    final fakePaymentId = 'pay_sim_${DateTime.now().millisecondsSinceEpoch}';
    const fakeSignature = 'sim_test_sig';

    try {
      final res = await ApiClient.instance.post(
        '/api/v1/subscription/verify-payment',
        {
          'businessId': cloudBusinessId,
          'orderId': orderId,
          'paymentId': fakePaymentId,
          'signature': fakeSignature,
        },
        token: token,
      );

      // If backend accepted or if it rejected signature because of real HMAC check:
      if (res.statusCode == 200) {
        final expiresAt = DateTime.now().add(const Duration(days: 365));
        await SubscriptionService.instance.setSubscription(
          tier: tier,
          expiresAt: expiresAt,
          status: 'active',
          businessId: localBusinessId,
        );
        return RazorpayCheckoutResult(
          success: true,
          orderId: orderId,
          paymentId: fakePaymentId,
          tier: tier,
          message: 'Subscription upgraded to ${tier.displayName}',
        );
      } else {
        return const RazorpayCheckoutResult(
          success: false,
          message: 'Test checkout requires valid Razorpay native interface.',
        );
      }
    } catch (e) {
      return RazorpayCheckoutResult(
        success: false,
        message: 'Simulation error: $e',
      );
    }
  }

  void dispose() {
    _razorpay?.clear();
  }
}
