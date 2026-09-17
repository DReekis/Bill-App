import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

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
      'dashboard': 'Dashboard',
      'transactions': 'Transactions',
      'parties': 'Parties',
      'items': 'Items',
      'more': 'More',
      
      // Quick Actions
      'quick_actions': 'Quick Actions',
      'new_sale': 'New Sale',
      'new_bill': 'New Bill',
      'estimate': 'Estimate / Quotation',
      'purchase': 'Purchase',
      'payment_in': 'Payment In',
      'payment_out': 'Payment Out',
      'expenses': 'Expenses',
      'delivery_challan': 'Delivery Challan',
      'add_product': 'Add Product',
      'gst_center': 'GST Center',
      'cash_bank': 'Cash & Bank',
      'reports': 'Reports',
      
      // Document Builder & Checkout
      'invoice': 'Invoice',
      'invoice_number': 'Invoice #',
      'date': 'Date',
      'due_date': 'Due Date',
      'customer': 'Customer',
      'supplier': 'Supplier',
      'select_customer': 'Select Customer',
      'select_supplier': 'Select Supplier',
      'item': 'Item',
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
      'balance_due': 'Balance Due',
      'payment_mode': 'Payment Mode',
      'cash': 'Cash',
      'upi': 'UPI / QR',
      'card': 'Card',
      'cheque': 'Cheque',
      'bank_transfer': 'Bank Transfer',
      'credit': 'Credit',
      'save_invoice': 'Save & Print Invoice',
      
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
      'screen_security': 'Screen Security (Block Screenshots)',
      'screen_security_desc': 'Prevent screen capture and recent task preview',
      'biometric_unlock': 'Biometric Unlock (Fingerprint/Face)',
      'app_lock': 'App Lock (PIN)',
      'app_locked': 'App locked',
      'lock': 'Lock',
      'logout': 'Sign Out',
      'delete_account': 'Delete Business Data',
      'delete_account_warning': 'Permanently erase local business records and audit trail',
    },
    'hi': {
      // Shell & Tabs
      'app_name': 'बिलकेट',
      'dashboard': 'डैशबोर्ड',
      'transactions': 'लेन-देन',
      'parties': 'पार्टियां',
      'items': 'सामान / उत्पाद',
      'more': 'अधिक',
      
      // Quick Actions
      'quick_actions': 'त्वरित कार्य',
      'new_sale': 'नई बिक्री',
      'new_bill': 'नया बिल बनाएं',
      'estimate': 'कोटेशन / अनुमान',
      'purchase': 'खरीद बिल',
      'payment_in': 'भुगतान प्राप्त',
      'payment_out': 'भुगतान दिया',
      'expenses': 'खर्चे',
      'delivery_challan': 'डिलीवरी चालान',
      'add_product': 'नया आइटम जोड़ें',
      'gst_center': 'जीएसटी केंद्र',
      'cash_bank': 'कैश व बैंक',
      'reports': 'रिपोर्ट्स व विश्लेषण',
      
      // Document Builder & Checkout
      'invoice': 'चालान / बिल',
      'invoice_number': 'बिल संख्या',
      'date': 'तारीख',
      'due_date': 'भुगतान तिथि',
      'customer': 'ग्राहक',
      'supplier': 'आपूर्तिकर्ता',
      'select_customer': 'ग्राहक चुनें',
      'select_supplier': 'आपूर्तिकर्ता चुनें',
      'item': 'आइटम',
      'add_items': 'सामान जोड़ें',
      'scan_barcode': 'बारकोड स्कैन करें',
      'quantity': 'मात्रा',
      'rate': 'दर (रेट)',
      'price': 'कीमत',
      'discount': 'छूट (डिस्काउंट)',
      'tax': 'कर (जीएसटी)',
      'taxable': 'कर योग्य मूल्य',
      'subtotal': 'उप-योग',
      'round_off': 'राउंड ऑफ',
      'total': 'कुल राशि',
      'total_amount': 'कुल देय राशि',
      'amount_paid': 'प्राप्त राशि',
      'balance_due': 'बकाया राशि',
      'payment_mode': 'भुगतान माध्यम',
      'cash': 'नकद (Cash)',
      'upi': 'यूपीआई / क्यूआर',
      'card': 'कार्ड',
      'cheque': 'चेक',
      'bank_transfer': 'बैंक ट्रांसफर',
      'credit': 'उधार (क्रेडिट)',
      'save_invoice': 'बिल सहेजें व प्रिंट करें',
      
      // GST Compliance
      'gst_compliance_center': 'जीएसटी अनुपालन केंद्र',
      'gstr1': 'जीएसटीआर-1 (बिक्री रिपोर्ट)',
      'gstr2b': 'जीएसटीआर-2B (मिलान)',
      'gstr3b': 'जीएसटीआर-3B (मासिक रिटर्न)',
      'hsn_summary': 'एचएसएन सारांश',
      'cgst': 'सीजीएसटी',
      'sgst': 'एसजीएसटी',
      'igst': 'आईजीएसटी',
      'itc': 'इनपुट टैक्स क्रेडिट (ITC)',
      'tax_liability': 'शुद्ध जीएसटी देयता',
      
      // Cash & Bank
      'liquid_assets': 'कुल तरल पूंजी',
      'cash_in_hand': 'हाथ में नकद',
      'bank_accounts': 'बैंक खाते',
      'passbook': 'पासबुक व स्टेटमेंट',
      'cheque_register': 'चेक रजिस्टर',
      'transfer_funds': 'फंड ट्रांसफर',
      'bounced': 'बाउंस हुआ',
      'cleared': 'पास हुआ',
      'pending': 'लंबित',
      
      // Common & Settings
      'search': 'खोजें...',
      'save': 'सहेजें',
      'cancel': 'रद्द करें',
      'delete': 'हटाएं',
      'edit': 'संपादित करें',
      'share': 'साझा करें',
      'print': 'प्रिंट करें',
      'export': 'निर्यात करें',
      'import': 'आयात करें',
      'sync_now': 'अभी सिंक करें',
      'online': 'ऑनलाइन',
      'offline': 'ऑफ़लाइन',
      'settings': 'सेटिंग्स',
      'language': 'भाषा (Language)',
      'screen_security': 'स्क्रीन सुरक्षा (स्क्रीनशॉट ब्लॉक)',
      'screen_security_desc': 'स्क्रीनशॉट और स्क्रीन रिकॉर्डिंग रोकें',
      'biometric_unlock': 'बायोमेट्रिक अनलॉक (फिंगरप्रिंट/चेहरा)',
      'app_lock': 'ऐप लॉक (पिन)',
      'app_locked': 'ऐप लॉक है',
      'lock': 'लॉक करें',
      'logout': 'साइन आउट',
      'delete_account': 'व्यापार डेटा हटाएं',
      'delete_account_warning': 'स्थानीय व्यापार रिकॉर्ड और ऑडिट लॉग स्थायी रूप से हटाएं',
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
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
