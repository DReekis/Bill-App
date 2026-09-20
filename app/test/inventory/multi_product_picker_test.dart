import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billket/core/models.dart';
import 'package:billket/features/inventory/multi_product_picker_sheet.dart';

void main() {
  final sampleProducts = [
    Product(
      id: 1,
      name: 'Basmati Rice 5kg',
      salePrice: 45000, // ₹450.00
      purchasePrice: 38000,
      stock: 25,
      category: 'Grains',
      unit: 'kg',
    ),
    Product(
      id: 2,
      name: 'Sunflower Oil 1L',
      salePrice: 16000, // ₹160.00
      purchasePrice: 13000,
      stock: 4,
      category: 'Oils',
      unit: 'L',
    ),
    Product(
      id: 3,
      name: 'Whole Wheat Atta 10kg',
      salePrice: 38000, // ₹380.00
      purchasePrice: 32000,
      stock: 0,
      category: 'Grains',
      unit: 'kg',
    ),
  ];

  testWidgets('MultiProductPickerSheet renders items, categories, and stock badges', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiProductPickerSheet(
            products: sampleProducts,
            onItemsSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Select Items'), findsOneWidget);
    expect(find.text('Basmati Rice 5kg'), findsWidgets);
    expect(find.text('Sunflower Oil 1L'), findsWidgets);
    expect(find.text('Whole Wheat Atta 10kg'), findsWidgets);

    // Stock badges
    expect(find.text('25 in stock'), findsOneWidget);
    expect(find.text('Low stock (4)'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
  });

  testWidgets('MultiProductPickerSheet allows selecting multiple items and batch adding', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    List<SelectedProductItem>? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiProductPickerSheet(
            products: sampleProducts,
            onItemsSelected: (items) => selected = items,
          ),
        ),
      ),
    );

    // Initial state: no items selected
    expect(find.text('No items selected'), findsOneWidget);

    // Add first item (Basmati Rice, id: 1)
    final addBtn1 = find.byKey(const ValueKey('add_btn_1'));
    expect(addBtn1, findsOneWidget);
    await tester.tap(addBtn1);
    await tester.pumpAndSettle();

    // Bottom summary should show 1 item
    expect(find.text('1 item (1 units)'), findsOneWidget);
    expect(find.text('₹450'), findsWidgets);

    // Tap '+' on the selected stepper to increase quantity to 2
    final plusBtn1 = find.byKey(const ValueKey('stepper_inc_1'));
    expect(plusBtn1, findsOneWidget);
    await tester.tap(plusBtn1);
    await tester.pumpAndSettle();

    expect(find.text('1 item (2 units)'), findsOneWidget);
    expect(find.text('₹900'), findsWidgets);

    // Add second item (Sunflower Oil, id: 2)
    final addBtn2 = find.byKey(const ValueKey('add_btn_2'));
    expect(addBtn2, findsOneWidget);
    await tester.tap(addBtn2);
    await tester.pumpAndSettle();

    expect(find.text('2 items (3 units)'), findsOneWidget);
    expect(find.text('₹1,060'), findsWidgets);

    // Submit selection via bottom CTA
    final submitButton = find.widgetWithText(FilledButton, 'Add to Bill (2)');
    expect(submitButton, findsOneWidget);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.length, 2);
    expect(selected![0].product.id, 1);
    expect(selected![0].quantity, 2);
    expect(selected![1].product.id, 2);
    expect(selected![1].quantity, 1);
  });

  testWidgets('MultiProductPickerSheet respects initialQuantities', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiProductPickerSheet(
            products: sampleProducts,
            initialQuantities: const {1: 3.0, 2: 2.0},
            onItemsSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('2 items (5 units)'), findsOneWidget);
    // (450 * 3) + (160 * 2) = 1350 + 320 = 1670
    expect(find.text('₹1,670'), findsWidgets);
  });
}
