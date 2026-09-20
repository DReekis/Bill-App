import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'party_form.dart';

export 'party_form.dart' show PartyFormSheet;

class CustomerFormSheet extends StatelessWidget {
  const CustomerFormSheet({
    super.key,
    required this.onSaved,
    required this.businessId,
    this.customer,
    this.onSavedCustomer,
  });

  final Future<void> Function() onSaved;
  final int businessId;
  final Customer? customer;
  final ValueChanged<Customer>? onSavedCustomer;

  @override
  Widget build(BuildContext context) {
    return PartyFormSheet(
      businessId: businessId,
      onSaved: onSaved,
      customer: customer,
      initialPartyType: 'customer',
      onSavedParty: (p) {
        if (p is Customer) {
          onSavedCustomer?.call(p);
        }
      },
    );
  }
}