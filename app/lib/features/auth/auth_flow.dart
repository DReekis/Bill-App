import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import 'business_setup_screen.dart';
import 'login_screen.dart';

class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  bool _proceedToSetup = false;
  String _phone = '';

  @override
  Widget build(BuildContext context) {
    if (_proceedToSetup) {
      return BusinessSetupScreen(phone: _phone);
    }

    return LoginScreen(
      isModal: false,
      onOffline: () {
        if (mounted) setState(() => _proceedToSetup = true);
      },
      onSuccess: () {
        final session = context.read<Session>();
        if (session.businessId == null) {
          if (mounted) {
            setState(() {
              _phone = session.mobile ?? '';
              _proceedToSetup = true;
            });
          }
        }
      },
    );
  }
}
