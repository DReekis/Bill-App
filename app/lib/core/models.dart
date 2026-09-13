import 'money.dart';

class Business {
  Business({
    this.id,
    required this.name,
    this.ownerName,
    this.gstin,
    this.state,
    this.city,
    this.industry,
    this.invoicePrefix = 'INV',
    this.taxRegistered = false,
    this.allowNegativeStock = false,
    this.invoiceSequence = 0,
    this.fyStart = '2026-04-01',
    this.currency = 'INR',
  });

  final int? id;
  String name;
  String? ownerName;
  String? gstin;
  String? state;
  String? city;
  String? industry;
  String invoicePrefix;
  bool taxRegistered;
  bool allowNegativeStock;
  int invoiceSequence;
  String fyStart;
  String currency;

  int get nextSequence => invoiceSequence + 1;

  Money get openingCapital => const Money(0);

  Map<String, Object?> toMap() => {
        'name': name,
        'owner_name': ownerName,
        'gstin': gstin,
        'state': state,
        'city': city,
        'industry': industry,
        'invoice_prefix': invoicePrefix,
        'tax_registered': taxRegistered ? 1 : 0,
        'allow_negative_stock': allowNegativeStock ? 1 : 0,
        'invoice_sequence': invoiceSequence,
        'fy_start': fyStart,
        'currency': currency,
      };

  static Business fromMap(Map<String, Object?> map) => Business(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        ownerName: map['owner_name'] as String?,
        gstin: map['gstin'] as String?,
        state: map['state'] as String?,
        city: map['city'] as String?,
        industry: map['industry'] as String?,
        invoicePrefix: map['invoice_prefix'] as String? ?? 'INV',
        taxRegistered: (map['tax_registered'] as int? ?? 0) == 1,
        allowNegativeStock: (map['allow_negative_stock'] as int? ?? 0) == 1,
        invoiceSequence: map['invoice_sequence'] as int? ?? 0,
        fyStart: map['fy_start'] as String? ?? '2026-04-01',
        currency: map['currency'] as String? ?? 'INR',
      );
}

class Customer {
  Customer({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.billingAddress,
    this.shippingAddress,
    this.gstin,
    this.state,
    this.openingBalance = 0,
    this.creditLimit = 0,
    this.paymentTermsDays = 0,
    this.notes,
    this.inactive = false,
  });
  final int? id;
  String name;
  String? phone;
  String? email;
  String? billingAddress;
  String? shippingAddress;
  String? gstin;
  String? state;
  int openingBalance;
  int creditLimit;
  int paymentTermsDays;
  String? notes;
  bool inactive;

  Map<String, Object?> toMap() => {
        'name': name,
        'phone': phone,
        'email': email,
        'billing_address': billingAddress,
        'shipping_address': shippingAddress,
        'gstin': gstin,
        'state': state,
        'opening_balance': openingBalance,
        'credit_limit': creditLimit,
        'payment_terms': paymentTermsDays,
        'notes': notes,
        'inactive': inactive ? 1 : 0,
      };

  static Customer fromMap(Map<String, Object?> map) => Customer(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        billingAddress: map['billing_address'] as String?,
        shippingAddress: map['shipping_address'] as String?,
        gstin: map['gstin'] as String?,
        state: map['state'] as String?,
        openingBalance: (map['opening_balance'] as num?)?.toInt() ?? 0,
        creditLimit: (map['credit_limit'] as num?)?.toInt() ?? 0,
        paymentTermsDays: (map['payment_terms'] as num?)?.toInt() ?? 0,
        notes: map['notes'] as String?,
        inactive: (map['inactive'] as int? ?? 0) == 1,
      );
}

class Supplier {
  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.gstin,
    this.state,
    this.openingBalance = 0,
    this.creditPeriodDays = 0,
    this.notes,
    this.inactive = false,
  });
  final int? id;
  String name;
  String? phone;
  String? email;
  String? address;
  String? gstin;
  String? state;
  int openingBalance;
  int creditPeriodDays;
  String? notes;
  bool inactive;

  Map<String, Object?> toMap() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'gstin': gstin,
        'state': state,
        'opening_balance': openingBalance,
        'credit_period': creditPeriodDays,
        'notes': notes,
        'inactive': inactive ? 1 : 0,
      };

  static Supplier fromMap(Map<String, Object?> map) => Supplier(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        address: map['address'] as String?,
        gstin: map['gstin'] as String?,
        state: map['state'] as String?,
        openingBalance: (map['opening_balance'] as num?)?.toInt() ?? 0,
        creditPeriodDays: (map['credit_period'] as num?)?.toInt() ?? 0,
        notes: map['notes'] as String?,
        inactive: (map['inactive'] as int? ?? 0) == 1,
      );
}

class Product {
  Product({
    this.id,
    required this.name,
    this.sku,
    this.category,
    this.hsn,
    this.barcode,
    this.unit = 'pc',
    this.gstRate = 0,
    this.purchasePrice = 0,
    this.salePrice = 0,
    this.wholesalePrice = 0,
    this.mrp = 0,
    this.stock = 0,
    this.costAverage = 0,
    this.lowStockThreshold = 5,
    this.taxIncluded = false,
    this.inactive = false,
  });
  final int? id;
  String name;
  String? sku;
  String? category;
  String? hsn;
  String? barcode;
  String unit;
  int gstRate;
  int purchasePrice;
  int salePrice;
  int wholesalePrice;
  int mrp;
  int stock;
  int costAverage;
  int lowStockThreshold;
  bool taxIncluded;
  bool inactive;

  bool get low => stock > 0 && stock <= lowStockThreshold;
  bool get outOfStock => stock <= 0;

  Map<String, Object?> toMap() => {
        'name': name,
        'sku': sku,
        'category': category,
        'hsn': hsn,
        'barcode': barcode,
        'unit': unit,
        'gst_rate': gstRate,
        'purchase_price': purchasePrice,
        'sale_price': salePrice,
        'wholesale_price': wholesalePrice,
        'mrp': mrp,
        'stock': stock,
        'cost_average': costAverage,
        'low_stock_threshold': lowStockThreshold,
        'tax_included': taxIncluded ? 1 : 0,
        'inactive': inactive ? 1 : 0,
      };

  static Product fromMap(Map<String, Object?> map) => Product(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        sku: map['sku'] as String?,
        category: map['category'] as String?,
        hsn: map['hsn'] as String?,
        barcode: map['barcode'] as String?,
        unit: map['unit'] as String? ?? 'pc',
        gstRate: (map['gst_rate'] as num?)?.toInt() ?? 0,
        purchasePrice: (map['purchase_price'] as num?)?.toInt() ?? 0,
        salePrice: (map['sale_price'] as num?)?.toInt() ?? 0,
        wholesalePrice: (map['wholesale_price'] as num?)?.toInt() ?? 0,
        mrp: (map['mrp'] as num?)?.toInt() ?? 0,
        stock: (map['stock'] as num?)?.toInt() ?? 0,
        costAverage: (map['cost_average'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (map['low_stock_threshold'] as num?)?.toInt() ?? 5,
        taxIncluded: (map['tax_included'] as int? ?? 0) == 1,
        inactive: (map['inactive'] as int? ?? 0) == 1,
      );
}

class InvoiceLine {
  InvoiceLine({
    this.productId,
    required this.name,
    this.hsn,
    this.gstRate = 0,
    required this.quantity,
    required this.price,
    this.discount = 0,
    this.discountPercent = 0,
    this.taxable = 0,
    this.tax = 0,
  });
  final int? productId;
  String name;
  String? hsn;
  int gstRate;
  double quantity;
  int price;
  int discount;
  double discountPercent;
  int taxable;
  int tax;

  Map<String, Object?> toMap() => {
        'product_id': productId,
        'name': name,
        'hsn': hsn,
        'gst_rate': gstRate,
        'quantity': quantity,
        'price': price,
        'discount': discount,
        'discount_percent': discountPercent,
        'taxable': taxable,
        'tax': tax,
      };

  static InvoiceLine fromMap(Map<String, Object?> map) => InvoiceLine(
        productId: map['product_id'] as int?,
        name: map['name'] as String? ?? '',
        hsn: map['hsn'] as String?,
        gstRate: (map['gst_rate'] as num?)?.toInt() ?? 0,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        price: (map['price'] as num?)?.toInt() ?? 0,
        discount: (map['discount'] as num?)?.toInt() ?? 0,
        discountPercent: (map['discount_percent'] as num?)?.toDouble() ?? 0,
        taxable: (map['taxable'] as num?)?.toInt() ?? 0,
        tax: (map['tax'] as num?)?.toInt() ?? 0,
      );

  InvoiceLine copyWith({double? quantity}) => InvoiceLine(
        productId: productId,
        name: name,
        hsn: hsn,
        gstRate: gstRate,
        quantity: quantity ?? this.quantity,
        price: price,
        discount: discount,
        discountPercent: discountPercent,
        taxable: taxable,
        tax: tax,
      );
}

class Quotation {
  Quotation({
    this.id,
    this.businessId,
    required this.number,
    this.customerId,
    this.customerName,
    required this.date,
    this.expiryDate,
    this.gstType = 'gst',
    this.subtotal = 0,
    this.discount = 0,
    this.taxable = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.total = 0,
    this.status = 'Open',
    this.notes,
    this.lines = const [],
  });
  final int? id;
  final int? businessId;
  String number;
  int? customerId;
  String? customerName;
  String date;
  String? expiryDate;
  String gstType;
  int subtotal;
  int discount;
  int taxable;
  int cgst;
  int sgst;
  int igst;
  int total;
  String status;
  String? notes;
  List<InvoiceLine> lines;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'number': number,
        'customer_id': customerId,
        'customer_name': customerName,
        'date': date,
        'expiry_date': expiryDate,
        'gst_type': gstType,
        'subtotal': subtotal,
        'discount': discount,
        'taxable': taxable,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'total': total,
        'status': status,
        'notes': notes,
      };

  static Quotation fromMap(Map<String, Object?> map) => Quotation(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        number: map['number'] as String? ?? '',
        customerId: map['customer_id'] as int?,
        customerName: map['customer_name'] as String?,
        date: map['date'] as String? ?? '',
        expiryDate: map['expiry_date'] as String?,
        gstType: map['gst_type'] as String? ?? 'gst',
        subtotal: (map['subtotal'] as num?)?.toInt() ?? 0,
        discount: (map['discount'] as num?)?.toInt() ?? 0,
        taxable: (map['taxable'] as num?)?.toInt() ?? 0,
        cgst: (map['cgst'] as num?)?.toInt() ?? 0,
        sgst: (map['sgst'] as num?)?.toInt() ?? 0,
        igst: (map['igst'] as num?)?.toInt() ?? 0,
        total: (map['total'] as num?)?.toInt() ?? 0,
        status: map['status'] as String? ?? 'Open',
        notes: map['notes'] as String?,
      );
}

class Invoice {
  Invoice({
    this.id,
    this.businessId,
    required this.number,
    this.customerId,
    this.customerName,
    required this.date,
    this.dueDate,
    this.gstType = 'gst',
    this.subtotal = 0,
    this.discount = 0,
    this.discountType,
    this.discountRate = 0,
    this.taxable = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.cess = 0,
    this.roundOff = 0,
    this.total = 0,
    this.amountPaid = 0,
    this.paymentMode,
    this.status = 'Finalized',
    this.notes,
    this.lines = const [],
  });
  final int? id;
  final int? businessId;
  String number;
  int? customerId;
  String? customerName;
  String date;
  String? dueDate;
  String gstType;
  int subtotal;
  int discount;
  String? discountType;
  double discountRate;
  int taxable;
  int cgst;
  int sgst;
  int igst;
  int cess;
  int roundOff;
  int total;
  int amountPaid;
  String? paymentMode;
  String status;
  String? notes;
  List<InvoiceLine> lines;

  Money get outstanding => Money(total - amountPaid);

  bool get isCredit => status == 'Unpaid' || status == 'Partially paid';

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'number': number,
        'customer_id': customerId,
        'customer_name': customerName,
        'date': date,
        'due_date': dueDate,
        'gst_type': gstType,
        'subtotal': subtotal,
        'discount': discount,
        'discount_type': discountType,
        'discount_rate': discountRate,
        'taxable': taxable,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'cess': cess,
        'round_off': roundOff,
        'total': total,
        'amount_paid': amountPaid,
        'payment_mode': paymentMode,
        'status': status,
        'notes': notes,
      };

  static Invoice fromMap(Map<String, Object?> map) => Invoice(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        number: map['number'] as String? ?? '',
        customerId: map['customer_id'] as int?,
        customerName: map['customer_name'] as String?,
        date: map['date'] as String? ?? '',
        dueDate: map['due_date'] as String?,
        gstType: map['gst_type'] as String? ?? 'gst',
        subtotal: (map['subtotal'] as num?)?.toInt() ?? 0,
        discount: (map['discount'] as num?)?.toInt() ?? 0,
        discountType: map['discount_type'] as String?,
        discountRate: (map['discount_rate'] as num?)?.toDouble() ?? 0,
        taxable: (map['taxable'] as num?)?.toInt() ?? 0,
        cgst: (map['cgst'] as num?)?.toInt() ?? 0,
        sgst: (map['sgst'] as num?)?.toInt() ?? 0,
        igst: (map['igst'] as num?)?.toInt() ?? 0,
        cess: (map['cess'] as num?)?.toInt() ?? 0,
        roundOff: (map['round_off'] as num?)?.toInt() ?? 0,
        total: (map['total'] as num?)?.toInt() ?? 0,
        amountPaid: (map['amount_paid'] as num?)?.toInt() ?? 0,
        paymentMode: map['payment_mode'] as String?,
        status: map['status'] as String? ?? 'Finalized',
        notes: map['notes'] as String?,
      );
}

class Payment {
  Payment({
    this.id,
    this.businessId,
    required this.partyType,
    required this.partyId,
    this.partyName,
    this.invoiceId,
    this.invoiceNumber,
    required this.amount,
    required this.mode,
    required this.date,
    this.reference,
    this.type,
    this.notes,
  });
  final int? id;
  final int? businessId;
  String partyType;
  int partyId;
  String? partyName;
  int? invoiceId;
  String? invoiceNumber;
  int amount;
  String mode;
  String date;
  String? reference;
  String? type;
  String? notes;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'party_type': partyType,
        'party_id': partyId,
        'party_name': partyName,
        'invoice_id': invoiceId,
        'invoice_number': invoiceNumber,
        'amount': amount,
        'mode': mode,
        'date': date,
        'reference': reference,
        'type': type,
        'notes': notes,
      };

  static Payment fromMap(Map<String, Object?> map) => Payment(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        partyType: map['party_type'] as String? ?? 'customer',
        partyId: (map['party_id'] as num?)?.toInt() ?? 0,
        partyName: map['party_name'] as String?,
        invoiceId: map['invoice_id'] as int?,
        invoiceNumber: map['invoice_number'] as String?,
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        mode: map['mode'] as String? ?? 'Cash',
        date: map['date'] as String? ?? '',
        reference: map['reference'] as String?,
        type: map['type'] as String?,
        notes: map['notes'] as String?,
      );
}

class Expense {
  Expense({
    this.id,
    this.businessId,
    required this.category,
    required this.amount,
    required this.mode,
    required this.date,
    this.description,
    this.vendor,
  });
  final int? id;
  final int? businessId;
  String category;
  int amount;
  String mode;
  String date;
  String? description;
  String? vendor;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'category': category,
        'amount': amount,
        'mode': mode,
        'date': date,
        'description': description,
        'vendor': vendor,
      };

  static Expense fromMap(Map<String, Object?> map) => Expense(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        category: map['category'] as String? ?? '',
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        mode: map['mode'] as String? ?? 'Cash',
        date: map['date'] as String? ?? '',
        description: map['description'] as String?,
        vendor: map['vendor'] as String?,
      );
}

class LedgerEntry {
  LedgerEntry({
    this.id,
    this.businessId,
    required this.date,
    required this.account,
    required this.debit,
    required this.credit,
    this.refType,
    this.refId,
    this.note,
  });
  final int? id;
  final int? businessId;
  String date;
  String account;
  int debit;
  int credit;
  String? refType;
  int? refId;
  String? note;

  int get balance => credit - debit;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'date': date,
        'account': account,
        'debit': debit,
        'credit': credit,
        'ref_type': refType,
        'ref_id': refId,
        'note': note,
      };

  static LedgerEntry fromMap(Map<String, Object?> map) => LedgerEntry(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        date: map['date'] as String? ?? '',
        account: map['account'] as String? ?? '',
        debit: (map['debit'] as num?)?.toInt() ?? 0,
        credit: (map['credit'] as num?)?.toInt() ?? 0,
        refType: map['ref_type'] as String?,
        refId: map['ref_id'] as int?,
        note: map['note'] as String?,
      );
}

class StockMove {
  StockMove({
    this.id,
    this.businessId,
    required this.productId,
    required this.changeQty,
    required this.qtyAfter,
    required this.moveType,
    this.refType,
    this.refId,
    required this.date,
  });
  final int? id;
  final int? businessId;
  int productId;
  double changeQty;
  double qtyAfter;
  String moveType;
  String? refType;
  int? refId;
  String date;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'product_id': productId,
        'change_qty': changeQty,
        'qty_after': qtyAfter,
        'move_type': moveType,
        'ref_type': refType,
        'ref_id': refId,
        'date': date,
      };

  static StockMove fromMap(Map<String, Object?> map) => StockMove(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        productId: (map['product_id'] as num?)?.toInt() ?? 0,
        changeQty: (map['change_qty'] as num?)?.toDouble() ?? 0,
        qtyAfter: (map['qty_after'] as num?)?.toDouble() ?? 0,
        moveType: map['move_type'] as String? ?? '',
        refType: map['ref_type'] as String?,
        refId: map['ref_id'] as int?,
        date: map['date'] as String? ?? '',
      );
}

class AuditEntry {
  AuditEntry({
    this.id,
    this.businessId,
    this.actor = 'owner',
    required this.action,
    required this.entity,
    this.entityId,
    this.before,
    this.after,
    required this.timestamp,
  });
  final int? id;
  final int? businessId;
  String actor;
  String action;
  String entity;
  int? entityId;
  String? before;
  String? after;
  String timestamp;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'actor': actor,
        'action': action,
        'entity': entity,
        'entity_id': entityId,
        'before': before,
        'after': after,
        'timestamp': timestamp,
      };

  static AuditEntry fromMap(Map<String, Object?> map) => AuditEntry(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        actor: map['actor'] as String? ?? 'owner',
        action: map['action'] as String? ?? '',
        entity: map['entity'] as String? ?? '',
        entityId: map['entity_id'] as int?,
        before: map['before'] as String?,
        after: map['after'] as String?,
        timestamp: map['timestamp'] as String? ?? '',
      );
}

class TransactionReturn {
  TransactionReturn({
    this.id,
    this.businessId,
    required this.number,
    this.invoiceId,
    this.partyId,
    this.partyName,
    required this.partyType,
    required this.date,
    this.subtotal = 0,
    this.taxable = 0,
    this.tax = 0,
    this.total = 0,
    this.reason,
    this.status = 'Finalized',
    this.lines = const [],
  });
  final int? id;
  final int? businessId;
  String number;
  int? invoiceId;
  int? partyId;
  String? partyName;
  String partyType; // 'customer' or 'supplier'
  String date;
  int subtotal;
  int taxable;
  int tax;
  int total;
  String? reason;
  String status;
  List<InvoiceLine> lines;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'number': number,
        'invoice_id': invoiceId,
        'party_id': partyId,
        'party_name': partyName,
        'party_type': partyType,
        'date': date,
        'subtotal': subtotal,
        'taxable': taxable,
        'tax': tax,
        'total': total,
        'reason': reason,
        'status': status,
      };

  static TransactionReturn fromMap(Map<String, Object?> map) => TransactionReturn(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        number: map['number'] as String? ?? '',
        invoiceId: map['invoice_id'] as int?,
        partyId: map['party_id'] as int?,
        partyName: map['party_name'] as String?,
        partyType: map['party_type'] as String? ?? 'customer',
        date: map['date'] as String? ?? '',
        subtotal: (map['subtotal'] as num?)?.toInt() ?? 0,
        taxable: (map['taxable'] as num?)?.toInt() ?? 0,
        tax: (map['tax'] as num?)?.toInt() ?? 0,
        total: (map['total'] as num?)?.toInt() ?? 0,
        reason: map['reason'] as String?,
        status: map['status'] as String? ?? 'Finalized',
      );
}

class SyncRecord {
  SyncRecord({
    this.id,
    this.businessId,
    required this.entity,
    required this.entityId,
    required this.op,
    this.payload,
    required this.idempotencyKey,
    this.status = 'pending',
    this.attempts = 0,
    this.lastError,
    required this.createdAt,
    this.syncedAt,
  });
  final int? id;
  final int? businessId;
  String entity;
  int entityId;
  String op;
  String? payload;
  String idempotencyKey;
  String status;
  int attempts;
  String? lastError;
  String createdAt;
  String? syncedAt;

  static SyncRecord fromMap(Map<String, Object?> map) => SyncRecord(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        entity: map['entity'] as String? ?? '',
        entityId: (map['entity_id'] as num?)?.toInt() ?? 0,
        op: map['op'] as String? ?? '',
        payload: map['payload'] as String?,
        idempotencyKey: map['idempotency_key'] as String? ?? '',
        status: map['status'] as String? ?? 'pending',
        attempts: (map['attempts'] as num?)?.toInt() ?? 0,
        lastError: map['last_error'] as String?,
        createdAt: map['created_at'] as String? ?? '',
        syncedAt: map['synced_at'] as String?,
      );

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'entity': entity,
        'entity_id': entityId,
        'op': op,
        'payload': payload,
        'idempotency_key': idempotencyKey,
        'status': status,
        'attempts': attempts,
        'last_error': lastError,
        'created_at': createdAt,
        'synced_at': syncedAt,
      };
}

const List<String> paymentModes = [
  'Cash',
  'UPI',
  'Card',
  'Bank transfer',
  'Cheque',
  'Credit',
  'Other',
];

const List<String> expenseCategories = [
  'Rent',
  'Salary',
  'Electricity',
  'Internet',
  'Transport',
  'Marketing',
  'Packaging',
  'Repairs',
  'Office',
  'Bank charges',
  'Other',
];

const List<String> businessIndustries = [
  'Retail',
  'Wholesale',
  'Distributor',
  'Manufacturer',
  'Service',
  'Restaurant',
  'Pharmacy',
  'Electronics',
  'Clothing',
  'Grocery',
  'Hardware',
  'Jewellery',
  'Freelancer',
  'Other',
];

class SearchResult {
  SearchResult({required this.type, required this.id, required this.title, this.subtitle, this.amount});
  final String type;
  final int id;
  final String title;
  final String? subtitle;
  final int? amount;
}
