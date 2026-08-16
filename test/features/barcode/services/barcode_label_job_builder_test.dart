import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart' hide Product;
import 'package:tapix/features/barcode/data/models/invoice_print_data.dart';
import 'package:tapix/features/barcode/domain/models/barcode_design_state.dart';
import 'package:tapix/features/barcode/services/barcode_label_job_builder.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() => db.close());

  test(
    'length variants keep color and size in the shared preview/PDF jobs',
    () async {
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Measured fabric',
              costCents: Decimal.fromInt(1200),
              priceCents: Decimal.fromInt(2500),
              hasVariants: const Value(true),
              measurementType: const Value('length'),
            ),
          );
      final colorId = await db
          .into(db.productColors)
          .insert(ProductColorsCompanion.insert(name: 'Blue'));
      final sizeId = await db
          .into(db.sizes)
          .insert(SizesCompanion.insert(name: 'Double width'));
      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value('FABRIC-BLUE-2W'),
              barcode: const Value('2900000000261'),
              colorId: Value(colorId),
              sizeId: Value(sizeId),
              costCents: Decimal.fromInt(1200),
              priceCents: Decimal.fromInt(2500),
              stockQuantity: const Value(15500),
            ),
          );

      final jobs = await BarcodeLabelJobBuilder(db.productVariantDao).build(
        selectedProducts: [
          Product(
            id: productId,
            name: 'Measured fabric',
            costCents: Decimal.fromInt(1200),
            priceCents: Decimal.fromInt(2500),
            stockQuantity: 15500,
            minQuantity: 0,
            hasVariants: true,
            isTaxable: false,
            purchaseTaxRateBps: 0,
            salesTaxRateBps: 0,
            isActive: true,
            trackInventory: true,
            measurementType: 'length',
          ),
        ],
        settings: const BarcodeDesignSettings(
          includeVariantInfo: true,
          quantityMode: QuantityMode.single,
        ),
        selectedVariantIds: {variantId},
      );

      expect(jobs, hasLength(1));
      expect(jobs.single.product.sku, 'FABRIC-BLUE-2W');
      expect(jobs.single.product.barcode, '2900000000261');
      expect(jobs.single.variantInfo, 'Double width / Blue');
    },
  );

  test(
    'invoice labels recover measured variant info when the invoice DTO omits it',
    () async {
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Weighted product',
              costCents: Decimal.fromInt(1200),
              priceCents: Decimal.fromInt(2500),
              hasVariants: const Value(true),
              measurementType: const Value('weight'),
            ),
          );
      final colorId = await db
          .into(db.productColors)
          .insert(ProductColorsCompanion.insert(name: 'Brown'));
      final sizeId = await db
          .into(db.sizes)
          .insert(SizesCompanion.insert(name: 'Large'));
      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              barcode: const Value('2900000000230'),
              colorId: Value(colorId),
              sizeId: Value(sizeId),
              costCents: Decimal.fromInt(1200),
              priceCents: Decimal.fromInt(2500),
            ),
          );

      final jobs = await BarcodeLabelJobBuilder(db.productVariantDao).build(
        selectedProducts: const [],
        settings: const BarcodeDesignSettings(
          includeVariantInfo: true,
          quantityMode: QuantityMode.invoiceQuantity,
        ),
        invoiceData: InvoicePrintData(
          lines: [
            InvoiceLinePrintData(
              variantId: variantId,
              quantity: 1,
              productName: 'Weighted product',
              // Deliberately absent: this is the regression seen on device.
              colorName: null,
              sizeName: null,
              barcode: '2900000000230',
              sku: 'WEIGHT-BROWN-L',
              unitPriceCents: 2500,
              isActive: true,
            ),
          ],
          invoiceType: 'purchase',
          invoiceId: 7,
          invoiceNumber: 'PI-202608-000007',
          invoiceDate: DateTime(2026, 8, 16),
        ),
      );

      expect(jobs, hasLength(1));
      expect(jobs.single.variantInfo, 'Large / Brown');
    },
  );

  test(
    'one-label mode keeps invoice variant identity and its color and size',
    () async {
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Measured fabric',
              costCents: Decimal.fromInt(1200),
              priceCents: Decimal.fromInt(2500),
              hasVariants: const Value(false),
              measurementType: const Value('length'),
            ),
          );
      final colorId = await db
          .into(db.productColors)
          .insert(ProductColorsCompanion.insert(name: 'Purple'));
      final sizeId = await db
          .into(db.sizes)
          .insert(SizesCompanion.insert(name: 'Double width'));
      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value('KR1'),
              barcode: const Value('2057373895281'),
              colorId: Value(colorId),
              sizeId: Value(sizeId),
              costCents: Decimal.fromInt(1200),
              priceCents: Decimal.fromInt(2500),
            ),
          );
      final invoice = InvoicePrintData(
        lines: [
          InvoiceLinePrintData(
            variantId: variantId,
            quantity: 1000,
            productName: 'Measured fabric',
            colorName: null,
            sizeName: null,
            barcode: '2057373895281',
            sku: 'KR1',
            unitPriceCents: 2500,
            isActive: true,
          ),
        ],
        invoiceType: 'purchase',
        invoiceId: 13,
        invoiceNumber: 'PI-202608-000005',
        invoiceDate: DateTime(2026, 8, 16),
      );

      // This is exactly the state produced after opening an invoice and then
      // switching from "invoice quantity" to "one label per type".
      final jobs = await BarcodeLabelJobBuilder(db.productVariantDao).build(
        selectedProducts: invoice.lines
            .map(BarcodeLabelJobBuilder.productFromInvoiceLine)
            .toList(),
        settings: const BarcodeDesignSettings(
          includeVariantInfo: true,
          quantityMode: QuantityMode.single,
        ),
        invoiceData: invoice,
      );

      expect(jobs, hasLength(1));
      expect(jobs.single.copies, 1);
      expect(jobs.single.product.barcode, '2057373895281');
      expect(jobs.single.variantInfo, 'Double width / Purple');
    },
  );
}
