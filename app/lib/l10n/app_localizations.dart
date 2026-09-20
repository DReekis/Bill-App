import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  bool get isHindi => locale.languageCode == 'hi';

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('hi'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // Shell & Tabs
      'app_name': 'Billket',
      'home': 'Home',
      'dashboard': 'Dashboard',
      'transactions': 'Transactions',
      'parties': 'Parties',
      'items': 'Items',
      'products': 'Products',
      'reports': 'Reports',
      'more': 'More',

      // Greetings & Dashboard
      'good_morning': 'Good morning',
      'good_afternoon': 'Good afternoon',
      'good_evening': 'Good evening',
      'business_summary': "Here's your business summary",
      'todays_snapshot': "Today's Snapshot",
      'snapshot': 'Snapshot',
      'today': 'Today',
      'this_week': 'This Week',
      'this_month': 'This Month',
      'this_year': 'This Year',
      'sales': 'Sales',
      'purchases': 'Purchases',
      'expenses': 'Expenses',
      'business_overview': 'Business Overview',
      'revenue': 'Revenue',
      'net_profit': 'Net Profit',
      'trend_7day': '7-day trend',
      'alerts_and_notifications': 'Alerts & Notifications',
      'view_all': 'View All',
      'view': 'View',
      'low_stock': 'Low Stock',
      'out_of_stock': 'Out of stock',
      'overdue': 'Overdue',
      'no_overdue': 'No overdue invoices',
      'recent_transactions': 'Recent Transactions',
      'no_transactions': 'No transactions recorded yet',
      'create_sale': 'Create Sale',
      'add_purchase': 'Add Purchase',
      'switch_business': 'Switch Business',
      'all_caught_up': 'All Caught Up!',
      'all_caught_up_desc': 'Stock levels healthy, no overdue invoices, and all records are synced.',

      // Quick Actions (Concise & Punchy)
      'quick_actions': 'Quick Actions',
      'sale': 'Sale',
      'purchase': 'Purchase',
      'gst': 'GST',
      'cash_bank': 'Cash/Bank',
      'item': 'Item',
      'estimate': 'Estimate',
      'order': 'Order',
      'challan': 'Challan',
      'new_sale': 'New Sale',
      'new_bill': 'New Bill',
      'payment_in': 'Payment In',
      'payment_out': 'Payment Out',
      'gst_center': 'GST Center',
      'add_product': 'Add Product',

      // Document Builder & Checkout
      'invoice': 'Invoice',
      'invoice_number': 'Invoice #',
      'date': 'Date',
      'due_date': 'Due Date',
      'customer': 'Customer',
      'supplier': 'Supplier',
      'select_customer': 'Select Customer',
      'select_supplier': 'Select Supplier',
      'party': 'Party',
      'add_party': 'Add Party',
      'edit_party': 'Edit Party',
      'billing_address': 'Billing Address',
      'shipping_address': 'Shipping Address',
      'same_as_billing': 'Shipping address same as billing address',
      'pan_number': 'PAN No',
      'add_items': 'Add Items',
      'scan_barcode': 'Scan Barcode',
      'quantity': 'Qty',
      'rate': 'Rate',
      'price': 'Price',
      'discount': 'Discount',
      'tax': 'Tax',
      'taxable': 'Taxable',
      'subtotal': 'Subtotal',
      'round_off': 'Round Off',
      'total': 'Total',
      'total_amount': 'Total Amount',
      'amount_paid': 'Amount Paid',
      'amount_paid_now': 'Amount paid now',
      'zero_for_credit': '0 for credit',
      'pay_full': 'Pay Full',
      'full': 'Full',
      'credit_zero': 'Credit: ₹0',
      'balance_due': 'Balance Due',
      'payment_mode': 'Payment Mode',
      'cash': 'Cash',
      'upi': 'UPI / QR',
      'card': 'Card',
      'cheque': 'Cheque',
      'bank_transfer': 'Bank Transfer',
      'credit': 'Credit',
      'save_invoice': 'Save Invoice',
      'save_and_finalize': 'Save & finalize',

      // GST Compliance
      'gst_compliance_center': 'GST Compliance Center',
      'gstr1': 'GSTR-1 (Outward Supplies)',
      'gstr2b': 'GSTR-2B (Reconciliation)',
      'gstr3b': 'GSTR-3B (Monthly Return)',
      'hsn_summary': 'HSN Tax Summary',
      'cgst': 'CGST',
      'sgst': 'SGST',
      'igst': 'IGST',
      'itc': 'Input Tax Credit (ITC)',
      'tax_liability': 'Net GST Liability',

      // Cash & Bank
      'liquid_assets': 'Total Liquid Funds',
      'cash_in_hand': 'Cash in Hand',
      'bank_accounts': 'Bank Accounts',
      'passbook': 'Passbook & Statement',
      'cheque_register': 'Cheque Register',
      'transfer_funds': 'Transfer Funds',
      'bounced': 'Bounced',
      'cleared': 'Cleared',
      'pending': 'Pending',

      // Common & Settings
      'search': 'Search',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'share': 'Share',
      'print': 'Print',
      'export': 'Export',
      'import': 'Import',
      'sync_now': 'Sync Now',
      'online': 'Online',
      'offline': 'Offline',
      'settings': 'Settings',
      'language': 'Language',
      'screen_security': 'Screen Security',
      'screen_security_desc': 'Prevent screen capture and recent task preview',
      'biometric_unlock': 'Biometric Unlock',
      'app_lock': 'App Lock (PIN)',
      'app_locked': 'App locked',
      'lock': 'Lock',
      'logout': 'Sign Out',
      'delete_account': 'Delete Business Data',
      'delete_account_warning': 'Permanently erase local business records and audit trail',
      'company_details': 'Company Details',
      'manage_users': 'Manage Users & Roles',
      'cloud_sync': 'Cloud Synchronization',
      'export_backup': 'Export Backup',
      'bulk_import': 'Bulk Import',
      'all': 'All',
      'paid': 'Paid',
      'unpaid': 'Unpaid',
      'partial': 'Partial',
      'audit_log': 'Audit Log',
      'invoice_settings': 'Invoice Settings',
      'role': 'Role',
      'pin_set': 'App lock · PIN set',
      'set_pin': 'App lock (set PIN)',
      'choose_language': 'Choose Language / भाषा चुनें',
    },
    'hi': {
      // Shell & Tabs (Short & Clean)
      'app_name': 'बिलकेट',
      'home': 'होम',
      'dashboard': 'डैशबोर्ड',
      'transactions': 'लेन-देन',
      'parties': 'पार्टियां',
      'items': 'सामान',
      'products': 'सामान',
      'reports': 'रिपोर्ट्स',
      'more': 'अन्य',

      // Greetings & Dashboard (Short & Crisp)
      'good_morning': 'शुभ प्रभात',
      'good_afternoon': 'शुभ दोपहर',
      'good_evening': 'शुभ संध्या',
      'business_summary': 'व्यापार सारांश',
      'todays_snapshot': 'आज का सारांश',
      'snapshot': 'सारांश',
      'today': 'आज',
      'this_week': 'इस सप्ताह',
      'this_month': 'इस महीने',
      'this_year': 'इस वर्ष',
      'sales': 'बिक्री',
      'purchases': 'खरीद',
      'expenses': 'खर्च',
      'business_overview': 'व्यापार विवरण',
      'revenue': 'राजस्व',
      'net_profit': 'शुद्ध लाभ',
      'trend_7day': '7-दिन रुझान',
      'alerts_and_notifications': 'अलर्ट व सूचनाएं',
      'view_all': 'सभी देखें',
      'view': 'देखें',
      'low_stock': 'कम स्टॉक',
      'out_of_stock': 'स्टॉक खत्म',
      'overdue': 'बकाया',
      'no_overdue': 'कोई बकाया नहीं',
      'recent_transactions': 'हालिया लेन-देन',
      'no_transactions': 'कोई लेन-देन नहीं मिला',
      'create_sale': 'बिक्री बनाएं',
      'add_purchase': 'खरीद जोड़ें',
      'switch_business': 'व्यापार बदलें',
      'all_caught_up': 'सब ठीक है!',
      'all_caught_up_desc': 'स्टॉक सुरक्षित है, कोई बकाया नहीं और डेटा सिंक है।',

      // Quick Actions (Short, Punchy, No Long Awkward Hindi)
      'quick_actions': 'त्वरित कार्य',
      'sale': 'बिक्री',
      'purchase': 'खरीद',
      'gst': 'जीएसटी',
      'cash_bank': 'कैश-बैंक',
      'item': 'सामान',
      'estimate': 'कोटेशन',
      'order': 'ऑर्डर',
      'challan': 'चालान',
      'new_sale': 'बिक्री',
      'new_bill': 'नया बिल',
      'payment_in': 'प्राप्त',
      'payment_out': 'भुगतान',
      'gst_center': 'जीएसटी',
      'add_product': 'सामान जोड़ें',

      // Document Builder & Checkout
      'invoice': 'बिल',
      'invoice_number': 'बिल नं.',
      'date': 'तारीख',
      'due_date': 'देय तिथि',
      'customer': 'ग्राहक',
      'supplier': 'सप्लायर',
      'select_customer': 'ग्राहक चुनें',
      'select_supplier': 'सप्लायर चुनें',
      'party': 'पार्टी',
      'add_party': 'पार्टी जोड़ें',
      'edit_party': 'पार्टी बदलें',
      'billing_address': 'बिलिंग पता',
      'shipping_address': 'डिलीवरी पता',
      'same_as_billing': 'डिलीवरी पता बिलिंग पते के समान है',
      'pan_number': 'पैन नंबर',
      'add_items': 'सामान जोड़ें',
      'scan_barcode': 'बारकोड',
      'quantity': 'मात्रा',
      'rate': 'दर',
      'price': 'कीमत',
      'discount': 'छूट',
      'tax': 'टैक्स',
      'taxable': 'कर योग्य',
      'subtotal': 'उप-योग',
      'round_off': 'राउंड ऑफ',
      'total': 'कुल',
      'total_amount': 'कुल राशि',
      'amount_paid': 'प्राप्त राशि',
      'amount_paid_now': 'प्राप्त राशि',
      'zero_for_credit': 'उधार के लिए 0',
      'pay_full': 'पूरा भुगतान',
      'full': 'पूर्ण',
      'credit_zero': 'उधार: ₹0',
      'balance_due': 'बकाया',
      'payment_mode': 'माध्यम',
      'cash': 'नकद',
      'upi': 'यूपीआई',
      'card': 'कार्ड',
      'cheque': 'चेक',
      'bank_transfer': 'बैंक ट्रांसफर',
      'credit': 'उधार',
      'save_invoice': 'बिल सहेजें',
      'save_and_finalize': 'सहेजें व पूरा करें',

      // GST Compliance
      'gst_compliance_center': 'जीएसटी केंद्र',
      'gstr1': 'GSTR-1 (बिक्री)',
      'gstr2b': 'GSTR-2B (मिलान)',
      'gstr3b': 'GSTR-3B (रिटर्न)',
      'hsn_summary': 'HSN सारांश',
      'cgst': 'CGST',
      'sgst': 'SGST',
      'igst': 'IGST',
      'itc': 'ITC (क्रेडिट)',
      'tax_liability': 'शुद्ध देयता',

      // Cash & Bank
      'liquid_assets': 'कुल पूंजी',
      'cash_in_hand': 'नकद राशि',
      'bank_accounts': 'बैंक खाते',
      'passbook': 'पासबुक',
      'cheque_register': 'चेक रजिस्टर',
      'transfer_funds': 'फंड ट्रांसफर',
      'bounced': 'बाउंस',
      'cleared': 'पास हुआ',
      'pending': 'लंबित',

      // Common & Settings
      'search': 'खोजें',
      'save': 'सहेजें',
      'cancel': 'रद्द करें',
      'delete': 'हटाएं',
      'edit': 'संपादित करें',
      'share': 'शेयर',
      'print': 'प्रिंट',
      'export': 'निर्यात',
      'import': 'आयात',
      'sync_now': 'सिंक करें',
      'online': 'ऑनलाइन',
      'offline': 'ऑफ़लाइन',
      'settings': 'सेटिंग्स',
      'language': 'भाषा',
      'screen_security': 'स्क्रीन सुरक्षा',
      'screen_security_desc': 'स्क्रीनशॉट और रिकॉर्डिंग रोकें',
      'biometric_unlock': 'बायोमेट्रिक अनलॉक',
      'app_lock': 'ऐप लॉक (पिन)',
      'app_locked': 'ऐप लॉक है',
      'lock': 'लॉक',
      'logout': 'साइन आउट',
      'delete_account': 'व्यापार डेटा हटाएं',
      'delete_account_warning': 'स्थानीय व्यापार रिकॉर्ड स्थायी रूप से हटाएं',
      'company_details': 'व्यापार विवरण',
      'manage_users': 'यूज़र व रोल्स',
      'cloud_sync': 'क्लाउड सिंक',
      'export_backup': 'बैकअप निर्यात',
      'bulk_import': 'डेटा आयात',
      'all': 'सभी',
      'paid': 'चुकता',
      'unpaid': 'बकाया',
      'partial': 'आंशिक',
      'audit_log': 'ऑडिट लॉग',
      'invoice_settings': 'बिल सेटिंग्स',
      'role': 'भूमिका',
      'pin_set': 'पिन सेट है',
      'set_pin': 'पिन सेट करें',
      'choose_language': 'भाषा चुनें',
      'backup_export': 'बैकअप व निर्यात',
      'data_sync': 'डेटा सिंक',
      'cash_bank_hub': 'कैश व बैंक',
      'reports_analytics': 'रिपोर्ट्स',
    },
  };

  String text(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'hi'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => true;
}

extension LocalizationExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String key) => AppLocalizations.of(this).text(key);
}
