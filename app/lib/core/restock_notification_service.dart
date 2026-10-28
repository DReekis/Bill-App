import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/repositories.dart';

/// Item representing a restocked product that requires price/expiry review.
class RestockReviewItem {
  RestockReviewItem({
    required this.productId,
    required this.productName,
    required this.restockedQty,
    required this.unit,
    required this.oldPurchasePrice,
    required this.newPurchasePrice,
    required this.currentSalePrice,
    this.hasBatch = false,
    this.currentExpiryDate,
    required this.sourceRef,
    required this.date,
  });

  final int productId;
  final String productName;
  final double restockedQty;
  final String unit;
  final int oldPurchasePrice;
  final int newPurchasePrice;
  int currentSalePrice;
  final bool hasBatch;
  String? currentExpiryDate;
  final String sourceRef;
  final String date;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'restockedQty': restockedQty,
        'unit': unit,
        'oldPurchasePrice': oldPurchasePrice,
        'newPurchasePrice': newPurchasePrice,
        'currentSalePrice': currentSalePrice,
        'hasBatch': hasBatch,
        'currentExpiryDate': currentExpiryDate,
        'sourceRef': sourceRef,
        'date': date,
      };

  factory RestockReviewItem.fromMap(Map<String, dynamic> map) =>
      RestockReviewItem(
        productId: map['productId'] as int,
        productName: map['productName'] as String,
        restockedQty: (map['restockedQty'] as num).toDouble(),
        unit: map['unit'] as String? ?? 'pc',
        oldPurchasePrice: (map['oldPurchasePrice'] as num?)?.toInt() ?? 0,
        newPurchasePrice: (map['newPurchasePrice'] as num?)?.toInt() ?? 0,
        currentSalePrice: (map['currentSalePrice'] as num?)?.toInt() ?? 0,
        hasBatch: map['hasBatch'] as bool? ?? false,
        currentExpiryDate: map['currentExpiryDate'] as String?,
        sourceRef: map['sourceRef'] as String? ?? '',
        date: map['date'] as String? ?? '',
      );
}

/// Service that manages notifications for restocked items requiring selling price
/// adjustments and expiry date updates.
class RestockNotificationService extends ChangeNotifier {
  RestockNotificationService._();
  static final RestockNotificationService instance =
      RestockNotificationService._();

  static const String _kKeyPrefix = 'restock_pending_reviews_';

  String _storageKey(int businessId) => '$_kKeyPrefix$businessId';

  /// Records newly restocked items from Purchase Orders or Purchases.
  /// If an item already has a pending review, it is updated with the latest restock figures.
  Future<void> recordRestock({
    required int businessId,
    required String sourceRef,
    required List<RestockReviewItem> items,
  }) async {
    if (items.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _storageKey(businessId);
    final existing = await getPendingReviews(businessId);

    final map = {for (final e in existing) e.productId: e};
    for (final item in items) {
      map[item.productId] = item;
    }

    final rawList = map.values.map((i) => i.toMap()).toList();
    await prefs.setString(key, jsonEncode(rawList));
    notifyListeners();
  }

  /// Retrieves all pending restock price/expiry review items for a business.
  Future<List<RestockReviewItem>> getPendingReviews(int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(businessId));
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((m) => RestockReviewItem.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns the count of pending restock notifications.
  Future<int> getPendingCount(int businessId) async {
    final list = await getPendingReviews(businessId);
    return list.length;
  }

  /// Applies user-configured selling price and expiry date updates,
  /// updating the product in the local database and clearing the notification.
  Future<void> applyUpdates({
    required int businessId,
    required Map<int, ({int salePrice, String? expiryDate, String? batchNumber})>
        updates,
  }) async {
    if (updates.isEmpty) return;
    for (final entry in updates.entries) {
      final pid = entry.key;
      final u = entry.value;
      await Repository.instance.updateProductPricesAndExpiry(
        businessId,
        pid,
        salePrice: u.salePrice,
        expiryDate: u.expiryDate,
        batchNumber: u.batchNumber,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final key = _storageKey(businessId);
    final existing = await getPendingReviews(businessId);
    final updatedList = existing.where((i) => !updates.containsKey(i.productId)).toList();
    await prefs.setString(
        key, jsonEncode(updatedList.map((i) => i.toMap()).toList()));
    notifyListeners();
  }

  /// Dismisses a single notification without altering existing product prices.
  Future<void> dismissItem(int businessId, int productId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _storageKey(businessId);
    final existing = await getPendingReviews(businessId);
    final updatedList = existing.where((i) => i.productId != productId).toList();
    await prefs.setString(
        key, jsonEncode(updatedList.map((i) => i.toMap()).toList()));
    notifyListeners();
  }

  /// Clears all pending restock notifications for the business.
  Future<void> dismissAll(int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey(businessId));
    notifyListeners();
  }
}
