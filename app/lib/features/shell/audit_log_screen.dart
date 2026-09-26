import 'package:flutter/material.dart';

import '../reports/audit_trail_screen.dart';

/// Backward-compatible wrapper that directs to the MCA Audit Trail Screen.
class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context) => const AuditTrailScreen();
}