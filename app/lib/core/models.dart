import 'money.dart';

class Business {
  Business({
    this.id,
    required this.name,
    this.ownerName,
    this.phone,
    this.email,
    this.address,
    this.state,
    this.city,
    this.pinCode,
    this.country = 'India',
    this.logoPath,
    this.signaturePath,
    this.website,
    this.gstin,
    this.pan,
    this.industry,
    this.upiId,
    this.taxRegistered = false,
    this.isComposition = false,
    this.invoicePrefix = 'INV',
    this.invoiceSequence = 0,
    this.allowNegativeStock = false,
    this.fyStart = '2026-04-01',
    this.currency = 'INR',
    this.decimalPlaces = 2,
  });

  final int? id;
  String name;
  String? ownerName;
  String? phone;
  String? email;
  String? address;
  String? state;
  String? city;
  String? pinCode;
  String country;
  String? logoPath;
  String? signaturePath;
  String? website;
  String? gstin;
  String? pan;
  String? industry;
  String? upiId;
  bool taxRegistered;
  bool isComposition;
  String invoicePrefix;
  int invoiceSequence;
  bool allowNegativeStock;
  String fyStart;
  String currency;
  int decimalPlaces;

  int get nextSequence => invoiceSequence + 1;

  Map<String, Object?> toMap() => {
        'name': name,
        'owner_name': ownerName,
        'business_phone': phone,
        'email': email,
        'address': address,
        'state': state,
        'city': city,
        'pin_code': pinCode,
        'country': country,
        'logo': logoPath,
        'signature': signaturePath,
        'website': website,
        'gstin': gstin,
        'pan': pan,
        'industry': industry,
        'upi_id': upiId,
        'tax_registered': taxRegistered ? 1 : 0,
        'composition_scheme': isComposition ? 1 : 0,
        'invoice_prefix': invoicePrefix,
        'invoice_sequence': invoiceSequence,
        'allow_negative_stock': allowNegativeStock ? 1 : 0,
        'fy_start': fyStart,
        'currency': currency,
      };

  static Business fromMap(Map<String, Object?> map) => Business(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        ownerName: map['owner_name'] as String?,
        phone: map['business_phone'] as String?,
        email: map['email'] as String?,
        address: map['address'] as String?,
        state: map['state'] as String?,
        city: map['city'] as String?,
        pinCode: map['pin_code'] as String?,
        country: map['country'] as String? ?? 'India',
        logoPath: map['logo'] as String?,
        signaturePath: map['signature'] as String?,
        website: map['website'] as String?,
        gstin: map['gstin'] as String?,
        pan: map['pan'] as String?,
        industry: map['industry'] as String?,
        upiId: map['upi_id'] as String?,
        taxRegistered: (map['tax_registered'] as int? ?? 0) == 1,
        isComposition: (map['composition_scheme'] as int? ?? 0) == 1,
        invoicePrefix: map['invoice_prefix'] as String? ?? 'INV',
        invoiceSequence: (map['invoice_sequence'] as num?)?.toInt() ?? 0,
        allowNegativeStock: (map['allow_negative_stock'] as int? ?? 0) == 1,
        fyStart: map['fy_start'] as String? ?? '2026-04-01',
        currency: map['currency'] as String? ?? 'INR',
      );
}

class Customer {
  Customer({
    this.id,
    required this.name,
    this.phone,
    this.whatsapp,
    this.email,
    this.billingAddress,
    this.shippingAddress,
    this.gstin,
    this.pan,
    this.state,
    this.city,
    this.pin,
    this.openingBalance = 0,
    this.creditLimit = 0,
    this.paymentTermsDays = 0,
    this.type = 'Retail',
    this.group,
    this.notes,
    this.loyaltyPoints = 0,
    this.inactive = false,
  });
  final int? id;
  String name;
  String? phone;
  String? whatsapp;
  String? email;
  String? billingAddress;
  String? shippingAddress;
  String? gstin;
  String? pan;
  String? state;
  String? city;
  String? pin;
  int openingBalance;
  int creditLimit;
  int paymentTermsDays;
  String type;
  String? group;
  String? notes;
  int loyaltyPoints = 0;
  bool inactive;

  Map<String, Object?> toMap() => {
        'name': name,
        'phone': phone,
        'whatsapp': whatsapp,
        'email': email,
        'billing_address': billingAddress,
        'shipping_address': shippingAddress,
        'gstin': gstin,
        'pan': pan,
        'state': state,
        'city': city,
        'pin': pin,
        'opening_balance': openingBalance,
        'credit_limit': creditLimit,
        'payment_terms': paymentTermsDays,
        'notes': notes,
        'loyalty_points': loyaltyPoints,
        'inactive': inactive ? 1 : 0,
      };

  static Customer fromMap(Map<String, Object?> map) => Customer(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String?,
        whatsapp: map['whatsapp'] as String?,
        email: map['email'] as String?,
        billingAddress: map['billing_address'] as String?,
        shippingAddress: map['shipping_address'] as String?,
        gstin: map['gstin'] as String?,
        pan: map['pan'] as String?,
        state: map['state'] as String?,
        city: map['city'] as String?,
        pin: map['pin'] as String?,
        openingBalance: (map['opening_balance'] as num?)?.toInt() ?? 0,
        creditLimit: (map['credit_limit'] as num?)?.toInt() ?? 0,
        paymentTermsDays: (map['payment_terms'] as num?)?.toInt() ?? 0,
        notes: map['notes'] as String?,
        loyaltyPoints: (map['loyalty_points'] as num?)?.toInt() ?? 0,
        inactive: (map['inactive'] as int? ?? 0) == 1,
      );
}

class Supplier {
  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.whatsapp,
    this.email,
    this.address,
    this.gstin,
    this.pan,
    this.state,
    this.openingBalance = 0,
    this.creditPeriodDays = 0,
    this.group,
    this.notes,
    this.inactive = false,
  });
  final int? id;
  String name;
  String? phone;
  String? whatsapp;
  String? email;
  String? address;
  String? gstin;
  String? pan;
  String? state;
  int openingBalance;
  int creditPeriodDays;
  String? group;
  String? notes;
  bool inactive;

  Map<String, Object?> toMap() => {
        'name': name,
        'phone': phone,
        'whatsapp': whatsapp,
        'email': email,
        'address': address,
        'gstin': gstin,
        'pan': pan,
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
        whatsapp: map['whatsapp'] as String?,
        email: map['email'] as String?,
        address: map['address'] as String?,
        gstin: map['gstin'] as String?,
        pan: map['pan'] as String?,
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
    this.itemCode,
    this.barcode,
    this.category,
    this.brand,
    this.hsn,
    this.unit = 'pc',
    this.gstRate = 0,
    this.purchasePrice = 0,
    this.salePrice = 0,
    this.wholesalePrice = 0,
    this.retailPrice = 0,
    this.mrp = 0,
    this.minSellingPrice = 0,
    this.stock = 0,
    this.costAverage = 0,
    this.lowStockThreshold = 5,
    this.taxIncluded = false,
    this.hasBatch = false,
    this.hasSerial = false,
    this.imagePath,
    this.description,
    this.inactive = false,
  });
  final int? id;
  String name;
  String? sku;
  String? itemCode;
  String? barcode;
  String? category;
  String? brand;
  String? hsn;
  String unit;
  int gstRate;
  int purchasePrice;
  int salePrice;
  int wholesalePrice;
  int retailPrice;
  int mrp;
  int minSellingPrice;
  int stock;
  int costAverage;
  int lowStockThreshold;
  bool taxIncluded;
  bool hasBatch;
  bool hasSerial;
  String? imagePath;
  String? description;
  bool inactive;

  bool get low => stock > 0 && stock <= lowStockThreshold;
  bool get outOfStock => stock <= 0;

  Map<String, Object?> toMap() => {
        'name': name,
        'sku': sku,
        'item_code': itemCode,
        'category': category,
        'brand': brand,
        'hsn': hsn,
        'barcode': barcode,
        'unit': unit,
        'gst_rate': gstRate,
        'purchase_price': purchasePrice,
        'sale_price': salePrice,
        'wholesale_price': wholesalePrice,
        'retail_price': retailPrice,
        'mrp': mrp,
        'min_selling_price': minSellingPrice,
        'stock': stock,
        'cost_average': costAverage,
        'low_stock_threshold': lowStockThreshold,
        'tax_included': taxIncluded ? 1 : 0,
        'has_batch': hasBatch ? 1 : 0,
        'has_serial': hasSerial ? 1 : 0,
        'image_path': imagePath,
        'description': description,
        'inactive': inactive ? 1 : 0,
      };

  static Product fromMap(Map<String, Object?> map) => Product(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        sku: map['sku'] as String?,
        itemCode: map['item_code'] as String?,
        barcode: map['barcode'] as String?,
        category: map['category'] as String?,
        brand: map['brand'] as String?,
        hsn: map['hsn'] as String?,
        unit: map['unit'] as String? ?? 'pc',
        gstRate: (map['gst_rate'] as num?)?.toInt() ?? 0,
        purchasePrice: (map['purchase_price'] as num?)?.toInt() ?? 0,
        salePrice: (map['sale_price'] as num?)?.toInt() ?? 0,
        wholesalePrice: (map['wholesale_price'] as num?)?.toInt() ?? 0,
        retailPrice: (map['retail_price'] as num?)?.toInt() ?? 0,
        mrp: (map['mrp'] as num?)?.toInt() ?? 0,
        minSellingPrice: (map['min_selling_price'] as num?)?.toInt() ?? 0,
        stock: (map['stock'] as num?)?.toInt() ?? 0,
        costAverage: (map['cost_average'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (map['low_stock_threshold'] as num?)?.toInt() ?? 5,
        taxIncluded: (map['tax_included'] as int? ?? 0) == 1,
        hasBatch: (map['has_batch'] as int? ?? 0) == 1,
        hasSerial: (map['has_serial'] as int? ?? 0) == 1,
        imagePath: map['image_path'] as String?,
        description: map['description'] as String?,
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
    this.unit,
    this.batchNumber,
    this.serialNumber,
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
  String? unit;
  String? batchNumber;
  String? serialNumber;

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
        'unit': unit,
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
        unit: map['unit'] as String?,
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
        unit: unit,
        batchNumber: batchNumber,
        serialNumber: serialNumber,
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
    this.isProforma = false,
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
  bool isProforma = false;
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
        'is_proforma': isProforma ? 1 : 0,
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
        isProforma: (map['is_proforma'] as int? ?? 0) == 1,
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
    this.irn,
    this.isRecurring = false,
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
  String? irn;
  bool isRecurring = false;
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
        'irn': irn,
        'is_recurring': isRecurring ? 1 : 0,
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
        irn: map['irn'] as String?,
        isRecurring: (map['is_recurring'] as int? ?? 0) == 1,
      );
}

class SalesOrder {
  SalesOrder({
    this.id,
    this.businessId,
    required this.number,
    this.customerId,
    this.customerName,
    required this.date,
    this.dueDate,
    this.status = 'Pending',
    this.total = 0,
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
  String status;
  int total;
  String? notes;
  List<InvoiceLine> lines;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'number': number,
        'customer_id': customerId,
        'customer_name': customerName,
        'date': date,
        'due_date': dueDate,
        'status': status,
        'total': total,
        'notes': notes,
      };

  static SalesOrder fromMap(Map<String, Object?> map) => SalesOrder(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        number: map['number'] as String? ?? '',
        customerId: map['customer_id'] as int?,
        customerName: map['customer_name'] as String?,
        date: map['date'] as String? ?? '',
        dueDate: map['due_date'] as String?,
        status: map['status'] as String? ?? 'Pending',
        total: (map['total'] as num?)?.toInt() ?? 0,
        notes: map['notes'] as String?,
      );
}

class PurchaseOrder {
  PurchaseOrder({
    this.id,
    this.businessId,
    required this.number,
    this.supplierId,
    this.supplierName,
    required this.date,
    this.expectedDate,
    this.status = 'Draft',
    this.total = 0,
    this.notes,
    this.lines = const [],
  });
  final int? id;
  final int? businessId;
  String number;
  int? supplierId;
  String? supplierName;
  String date;
  String? expectedDate;
  String status;
  int total;
  String? notes;
  List<InvoiceLine> lines;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'number': number,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'date': date,
        'expected_date': expectedDate,
        'status': status,
        'total': total,
        'notes': notes,
      };

  static PurchaseOrder fromMap(Map<String, Object?> map) => PurchaseOrder(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        number: map['number'] as String? ?? '',
        supplierId: map['supplier_id'] as int?,
        supplierName: map['supplier_name'] as String?,
        date: map['date'] as String? ?? '',
        expectedDate: map['expected_date'] as String?,
        status: map['status'] as String? ?? 'Draft',
        total: (map['total'] as num?)?.toInt() ?? 0,
        notes: map['notes'] as String?,
      );
}

class DeliveryChallan {
  DeliveryChallan({
    this.id,
    this.businessId,
    required this.number,
    this.customerId,
    this.customerName,
    required this.date,
    this.address,
    this.transportDetails,
    this.status = 'Pending',
    this.lines = const [],
  });
  final int? id;
  final int? businessId;
  String number;
  int? customerId;
  String? customerName;
  String date;
  String? address;
  String? transportDetails;
  String status;
  List<InvoiceLine> lines;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'number': number,
        'customer_id': customerId,
        'customer_name': customerName,
        'date': date,
        'address': address,
        'transport_details': transportDetails,
        'status': status,
      };

  static DeliveryChallan fromMap(Map<String, Object?> map) => DeliveryChallan(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        number: map['number'] as String? ?? '',
        customerId: map['customer_id'] as int?,
        customerName: map['customer_name'] as String?,
        date: map['date'] as String? ?? '',
        address: map['address'] as String?,
        transportDetails: map['transport_details'] as String?,
        status: map['status'] as String? ?? 'Pending',
      );
}

class BankAccount {
  BankAccount({
    this.id,
    this.businessId,
    required this.bankName,
    this.accountName,
    this.accountNumber,
    this.ifsc,
    this.accountType = 'Current',
    this.openingBalance = 0,
    this.inactive = false,
  });
  final int? id;
  final int? businessId;
  String bankName;
  String? accountName;
  String? accountNumber;
  String? ifsc;
  String accountType;
  int openingBalance;
  bool inactive;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'bank_name': bankName,
        'account_name': accountName,
        'account_number': accountNumber,
        'ifsc': ifsc,
        'account_type': accountType,
        'opening_balance': openingBalance,
        'inactive': inactive ? 1 : 0,
      };

  static BankAccount fromMap(Map<String, Object?> map) => BankAccount(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        bankName: map['bank_name'] as String? ?? '',
        accountName: map['account_name'] as String?,
        accountNumber: map['account_number'] as String?,
        ifsc: map['ifsc'] as String?,
        accountType: map['account_type'] as String? ?? 'Current',
        openingBalance: (map['opening_balance'] as num?)?.toInt() ?? 0,
        inactive: (map['inactive'] as int? ?? 0) == 1,
      );
}

class UnitConversion {
  UnitConversion({
    this.id,
    this.businessId,
    required this.productId,
    required this.fromUnit,
    required this.toUnit,
    required this.multiplier,
  });
  final int? id;
  final int? businessId;
  int productId;
  String fromUnit;
  String toUnit;
  double multiplier;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'product_id': productId,
        'from_unit': fromUnit,
        'to_unit': toUnit,
        'multiplier': multiplier,
      };

  static UnitConversion fromMap(Map<String, Object?> map) => UnitConversion(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        productId: (map['product_id'] as num?)?.toInt() ?? 0,
        fromUnit: map['from_unit'] as String? ?? '',
        toUnit: map['to_unit'] as String? ?? '',
        multiplier: (map['multiplier'] as num?)?.toDouble() ?? 1,
      );
}

class Batch {
  Batch({
    this.id,
    this.businessId,
    required this.productId,
    required this.batchNumber,
    this.mfgDate,
    this.expiryDate,
    this.quantity = 0,
    this.purchasePrice = 0,
    this.salePrice = 0,
  });
  final int? id;
  final int? businessId;
  int productId;
  String batchNumber;
  String? mfgDate;
  String? expiryDate;
  double quantity;
  int purchasePrice;
  int salePrice;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'product_id': productId,
        'batch_number': batchNumber,
        'mfg_date': mfgDate,
        'expiry_date': expiryDate,
        'quantity': quantity,
        'purchase_price': purchasePrice,
        'sale_price': salePrice,
      };

  static Batch fromMap(Map<String, Object?> map) => Batch(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        productId: (map['product_id'] as num?)?.toInt() ?? 0,
        batchNumber: map['batch_number'] as String? ?? '',
        mfgDate: map['mfg_date'] as String?,
        expiryDate: map['expiry_date'] as String?,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        purchasePrice: (map['purchase_price'] as num?)?.toInt() ?? 0,
        salePrice: (map['sale_price'] as num?)?.toInt() ?? 0,
      );
}

class SerialNumber {
  SerialNumber({
    this.id,
    this.businessId,
    required this.productId,
    required this.serialNumber,
    this.status = 'Available',
    this.purchaseRef,
    this.saleRef,
  });
  final int? id;
  final int? businessId;
  int productId;
  String serialNumber;
  String status;
  String? purchaseRef;
  String? saleRef;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'product_id': productId,
        'serial_number': serialNumber,
        'status': status,
        'purchase_ref': purchaseRef,
        'sale_ref': saleRef,
      };

  static SerialNumber fromMap(Map<String, Object?> map) => SerialNumber(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        productId: (map['product_id'] as num?)?.toInt() ?? 0,
        serialNumber: map['serial_number'] as String? ?? '',
        status: map['status'] as String? ?? 'Available',
        purchaseRef: map['purchase_ref'] as String?,
        saleRef: map['sale_ref'] as String?,
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

class ReminderTemplate {
  ReminderTemplate({this.id, required this.name, required this.message});
  final int? id;
  final String name;
  final String message;
}

class Cheque {
  Cheque({
    this.id,
    required this.businessId,
    required this.chequeNumber,
    this.bankName,
    this.bankAccountId,
    this.partyType,
    this.partyId,
    this.partyName,
    required this.amount,
    required this.date,
    this.clearingDate,
    required this.type,
    this.status = 'Pending',
    this.bounceReason,
    this.notes,
  });

  final int? id;
  final int businessId;
  String chequeNumber;
  String? bankName;
  int? bankAccountId;
  String? partyType;
  int? partyId;
  String? partyName;
  int amount;
  String date;
  String? clearingDate;
  String type;
  String status;
  String? bounceReason;
  String? notes;

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'cheque_number': chequeNumber,
        'bank_name': bankName,
        'bank_account_id': bankAccountId,
        'party_type': partyType,
        'party_id': partyId,
        'party_name': partyName,
        'amount': amount,
        'date': date,
        'clearing_date': clearingDate,
        'type': type,
        'status': status,
        'bounce_reason': bounceReason,
        'notes': notes,
      };

  static Cheque fromMap(Map<String, Object?> map) => Cheque(
        id: map['id'] as int?,
        businessId: (map['business_id'] as num?)?.toInt() ?? 0,
        chequeNumber: map['cheque_number'] as String? ?? '',
        bankName: map['bank_name'] as String?,
        bankAccountId: (map['bank_account_id'] as num?)?.toInt(),
        partyType: map['party_type'] as String?,
        partyId: (map['party_id'] as num?)?.toInt(),
        partyName: map['party_name'] as String?,
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        date: map['date'] as String? ?? '',
        clearingDate: map['clearing_date'] as String?,
        type: map['type'] as String? ?? 'inward',
        status: map['status'] as String? ?? 'Pending',
        bounceReason: map['bounce_reason'] as String?,
        notes: map['notes'] as String?,
      );
}

class BankAccountWithBalance {
  BankAccountWithBalance({
    required this.account,
    required this.currentBalance,
  });
  final BankAccount account;
  final int currentBalance;
}

class CashBankSummary {
  CashBankSummary({
    required this.totalLiquidAssets,
    required this.cashInHand,
    required this.totalBankBalance,
    required this.pendingChequesInward,
    required this.pendingChequesOutward,
    required this.accounts,
  });
  final int totalLiquidAssets;
  final int cashInHand;
  final int totalBankBalance;
  final int pendingChequesInward;
  final int pendingChequesOutward;
  final List<BankAccountWithBalance> accounts;
}

class GstTaxSummary {
  GstTaxSummary({
    required this.totalSalesTaxable,
    required this.totalOutputCgst,
    required this.totalOutputSgst,
    required this.totalOutputIgst,
    required this.totalOutputTax,
    required this.totalPurchasesTaxable,
    required this.totalInputCgst,
    required this.totalInputSgst,
    required this.totalInputIgst,
    required this.totalInputTaxCredit,
    required this.netCgstPayable,
    required this.netSgstPayable,
    required this.netIgstPayable,
    required this.netTaxPayable,
    required this.totalInvoices,
    required this.b2bCount,
    required this.b2cCount,
    required this.hsnCount,
  });

  final int totalSalesTaxable;
  final int totalOutputCgst;
  final int totalOutputSgst;
  final int totalOutputIgst;
  final int totalOutputTax;
  final int totalPurchasesTaxable;
  final int totalInputCgst;
  final int totalInputSgst;
  final int totalInputIgst;
  final int totalInputTaxCredit;
  final int netCgstPayable;
  final int netSgstPayable;
  final int netIgstPayable;
  final int netTaxPayable;
  final int totalInvoices;
  final int b2bCount;
  final int b2cCount;
  final int hsnCount;
}

class Gstr1Section {
  Gstr1Section({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.taxableAmount,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.totalTax,
    required this.totalValue,
    required this.items,
  });

  final String code;
  final String title;
  final String subtitle;
  final int count;
  final int taxableAmount;
  final int cgst;
  final int sgst;
  final int igst;
  final int totalTax;
  final int totalValue;
  final List<Map<String, dynamic>> items;
}

class HsnTaxSummaryItem {
  HsnTaxSummaryItem({
    required this.hsn,
    required this.description,
    required this.uqc,
    required this.totalQuantity,
    required this.taxableValue,
    required this.gstRate,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.totalTax,
    required this.totalValue,
  });

  final String hsn;
  final String description;
  final String uqc;
  final double totalQuantity;
  final int taxableValue;
  final int gstRate;
  final int cgst;
  final int sgst;
  final int igst;
  final int totalTax;
  final int totalValue;
}

class Gstr2bEntry {
  Gstr2bEntry({
    required this.id,
    required this.supplierGstin,
    required this.supplierName,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.invoiceValue,
    required this.taxableValue,
    required this.igst,
    required this.cgst,
    required this.sgst,
    required this.itcEligibility,
    required this.matchStatus,
    this.expenseId,
    this.diffTax = 0,
    this.diffValue = 0,
  });

  final int id;
  final String supplierGstin;
  final String supplierName;
  final String invoiceNumber;
  final String invoiceDate;
  final int invoiceValue;
  final int taxableValue;
  final int igst;
  final int cgst;
  final int sgst;
  final String itcEligibility;
  final String matchStatus;
  final int? expenseId;
  final int diffTax;
  final int diffValue;
}

class Gstr3bSummary {
  Gstr3bSummary({
    required this.period,
    required this.outwardTaxableSupplies,
    required this.outwardIgst,
    required this.outwardCgst,
    required this.outwardSgst,
    required this.outwardCess,
    required this.itcAvailableIgst,
    required this.itcAvailableCgst,
    required this.itcAvailableSgst,
    required this.itcAvailableCess,
    required this.itcIneligible,
    required this.exemptSupplies,
    required this.netTaxPayableIgst,
    required this.netTaxPayableCgst,
    required this.netTaxPayableSgst,
    required this.totalTaxPayableCash,
  });

  final String period;
  final int outwardTaxableSupplies;
  final int outwardIgst;
  final int outwardCgst;
  final int outwardSgst;
  final int outwardCess;
  final int itcAvailableIgst;
  final int itcAvailableCgst;
  final int itcAvailableSgst;
  final int itcAvailableCess;
  final int itcIneligible;
  final int exemptSupplies;
  final int netTaxPayableIgst;
  final int netTaxPayableCgst;
  final int netTaxPayableSgst;
  final int totalTaxPayableCash;
}

enum TransactionType {
  sale,
  purchase,
  paymentIn,
  paymentOut,
  expense,
  quotation,
  salesOrder,
  purchaseOrder,
  deliveryChallan,
  saleReturn,
}

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.type,
    required this.number,
    this.partyName,
    required this.date,
    required this.amount,
    required this.status,
    this.paymentMode,
    this.notes,
    this.refId,
  });

  final int id;
  final TransactionType type;
  final String number;
  final String? partyName;
  final String date;
  final int amount; // in paise
  final String status;
  final String? paymentMode;
  final String? notes;
  final int? refId;

  bool get isInflow =>
      type == TransactionType.sale || type == TransactionType.paymentIn;

  String get typeLabel => switch (type) {
        TransactionType.sale => 'Sale',
        TransactionType.purchase => 'Purchase',
        TransactionType.paymentIn => 'Payment In',
        TransactionType.paymentOut => 'Payment Out',
        TransactionType.expense => 'Expense',
        TransactionType.quotation => 'Estimate',
        TransactionType.salesOrder => 'Sales Order',
        TransactionType.purchaseOrder => 'Purchase Order',
        TransactionType.deliveryChallan => 'Challan',
        TransactionType.saleReturn => 'Sale Return',
      };
}

class TrendInfo {
  const TrendInfo({
    required this.percent,
    required this.isNegative,
    required this.formatted,
  });

  final double percent;
  final bool isNegative;
  final String formatted;

  static TrendInfo compute(num current, num previous) {
    if (previous == 0) {
      if (current > 0) return const TrendInfo(percent: 100.0, isNegative: false, formatted: '+100%');
      if (current < 0) return const TrendInfo(percent: -100.0, isNegative: true, formatted: '-100%');
      return const TrendInfo(percent: 0.0, isNegative: false, formatted: '0.0%');
    }
    final diff = current - previous;
    final change = (diff / previous.abs()) * 100.0;
    final isNeg = change < 0;
    final sign = change > 0 ? '+' : '';
    return TrendInfo(
      percent: change,
      isNegative: isNeg,
      formatted: '$sign${change.toStringAsFixed(1)}%',
    );
  }
}

class DashboardPerformance {
  const DashboardPerformance({
    required this.totals,
    required this.salesTrend,
    required this.purchasesTrend,
    required this.expensesTrend,
    required this.revenueTrend,
    required this.profitTrend,
    required this.comparisonLabel,
    required this.salesHistory,
    required this.profitHistory,
  });

  final Map<String, int> totals;
  final TrendInfo salesTrend;
  final TrendInfo purchasesTrend;
  final TrendInfo expensesTrend;
  final TrendInfo revenueTrend;
  final TrendInfo profitTrend;
  final String comparisonLabel;
  final List<double> salesHistory;
  final List<double> profitHistory;
}

