import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../customers/party_form.dart';

export '../customers/party_form.dart' show PartyFormSheet;

class SupplierFormSheet extends StatelessWidget {
  const SupplierFormSheet({
    super.key,
    required this.onSaved,
    required this.businessId,
    this.supplier,
    this.onSavedSupplier,
  });

  final Future<void> Function() onSaved;
  final int businessId;
  final Supplier? supplier;
  final ValueChanged<Supplier>? onSavedSupplier;

  @override
  Widget build(BuildContext context) {
    return PartyFormSheet(
      businessId: businessId,
      onSaved: onSaved,
      supplier: supplier,
      initialPartyType: 'supplier',
      onSavedParty: (p) {
        if (p is Supplier) {
          onSavedSupplier?.call(p);
        }
      },
    );
  }
}