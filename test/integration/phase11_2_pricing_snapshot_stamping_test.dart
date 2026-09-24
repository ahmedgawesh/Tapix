import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/pricing/pricing_engine_version.dart';
import 'package:tapix/core/pricing/pricing_snapshot.dart';

/// Phase 11.2 regression suite — `pricing_engine_version`,
/// `tax_inclusive_at_post`, `rounding_mode_at_post` audit-snapshot
/// columns are stamped on every NEW header insert and never become
/// silently NULL on freshly-written rows.
///
/// Closes the long-term auditability gap: an auditor reading any
/// row written after Phase 11.2 must be able to determine *exactly*
/// which engine version produced its totals — even after the engine
/// ships v2 with different rounding rules.
///
/// Invariants verified per header table (`sales`, `purchases`,
/// `sale_returns`, `purchase_returns`, `sale_return_adjustments`,
/// `purchase_return_adjustments`):
///
///   1. `withPricingSnapshot(taxInclusive: true|false)` stamps the
///      three canonical values on the companion.
///   2. The migration columns exist and are nullable for legacy rows.
///   3. Inserting via the stamped companion produces a row whose
///      three audit columns equal the canonical constants.
///   4. The flag value passed to `withPricingSnapshot` is preserved
///      verbatim — both `true` and `false` are honored.
///   5. Inserting WITHOUT calling `withPricingSnapshot` leaves the
///      three columns NULL (back-compat for legacy migrated rows).
void main() {
  late AppDatabase db;
  late int currencyId;
  late int customerId;
  late int supplierId;
  late int saleId;
  late int purchaseId;

  final zero = Decimal.zero;
  final ten = Decimal.fromInt(1000);

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    // Trigger seed migration.
    await db.customSelect('SELECT 1').get();

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Phase 11.2 Customer',
            currencyId: currencyId,
          ),
        );

    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Phase 11.2 Supplier',
            currencyId: currencyId,
          ),
        );

    // Parent sale + purchase rows so we can attach returns.
    saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-PARENT-001',
            customerId: Value(customerId),
            subtotalCents: ten,
            taxCents: zero,
            totalCents: ten,
            currencyId: currencyId,
            paymentMethod: 'cash',
          ).withPricingSnapshot(taxInclusive: false),
        );

    purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PUR-PARENT-001',
            supplierId: supplierId,
            subtotalCents: ten,
            taxCents: zero,
            totalCents: ten,
            currencyId: currencyId,
          ).withPricingSnapshot(taxInclusive: false),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 11.2 — engine-version snapshot is stamped', () {
    test('sales header — taxInclusive=false', () async {
      final id = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-A-001',
              customerId: Value(customerId),
              subtotalCents: ten,
              taxCents: zero,
              totalCents: ten,
              currencyId: currencyId,
              paymentMethod: 'cash',
            ).withPricingSnapshot(taxInclusive: false),
          );

      final row = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(id))).getSingle();
      expect(row.pricingEngineVersion, equals(PricingEngineVersion.current));
      expect(row.taxInclusiveAtPost, isFalse);
      expect(row.roundingModeAtPost, equals(RoundingModeLabel.halfUp));
    });

    test('sales header — taxInclusive=true is preserved verbatim', () async {
      final id = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-A-002',
              customerId: Value(customerId),
              subtotalCents: ten,
              taxCents: zero,
              totalCents: ten,
              currencyId: currencyId,
              paymentMethod: 'cash',
            ).withPricingSnapshot(taxInclusive: true),
          );

      final row = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(id))).getSingle();
      expect(row.taxInclusiveAtPost, isTrue);
      expect(row.pricingEngineVersion, equals(PricingEngineVersion.current));
      expect(row.roundingModeAtPost, equals(RoundingModeLabel.halfUp));
    });

    test('purchases header — snapshot stamped', () async {
      final id = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PUR-A-001',
              supplierId: supplierId,
              subtotalCents: ten,
              taxCents: zero,
              totalCents: ten,
              currencyId: currencyId,
            ).withPricingSnapshot(taxInclusive: true),
          );

      final row = await (db.select(
        db.purchases,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.pricingEngineVersion, equals(PricingEngineVersion.current));
      expect(row.taxInclusiveAtPost, isTrue);
      expect(row.roundingModeAtPost, equals(RoundingModeLabel.halfUp));
    });

    test('sale_returns header — snapshot stamped', () async {
      final id = await db
          .into(db.saleReturns)
          .insert(
            SaleReturnsCompanion.insert(
              saleId: saleId,
              returnNumber: 'SRET-A-001',
              totalCents: ten,
              currencyId: currencyId,
            ).withPricingSnapshot(taxInclusive: false),
          );

      final row = await (db.select(
        db.saleReturns,
      )..where((r) => r.id.equals(id))).getSingle();
      expect(row.pricingEngineVersion, equals(PricingEngineVersion.current));
      expect(row.taxInclusiveAtPost, isFalse);
      expect(row.roundingModeAtPost, equals(RoundingModeLabel.halfUp));
    });

    test('purchase_returns header — snapshot stamped', () async {
      final id = await db
          .into(db.purchaseReturns)
          .insert(
            PurchaseReturnsCompanion.insert(
              purchaseId: purchaseId,
              returnNumber: 'PRET-A-001',
              totalCents: ten,
              currencyId: currencyId,
            ).withPricingSnapshot(taxInclusive: false),
          );

      final row = await (db.select(
        db.purchaseReturns,
      )..where((r) => r.id.equals(id))).getSingle();
      expect(row.pricingEngineVersion, equals(PricingEngineVersion.current));
      expect(row.taxInclusiveAtPost, isFalse);
      expect(row.roundingModeAtPost, equals(RoundingModeLabel.halfUp));
    });

    test('sale_return_adjustments header — snapshot stamped', () async {
      final id = await db
          .into(db.saleReturnAdjustments)
          .insert(
            SaleReturnAdjustmentsCompanion.insert(
              returnNumber: 'SADJ-A-001',
              currencyId: currencyId,
              totalCents: ten,
            ).withPricingSnapshot(taxInclusive: false),
          );

      final row = await (db.select(
        db.saleReturnAdjustments,
      )..where((r) => r.id.equals(id))).getSingle();
      expect(row.pricingEngineVersion, equals(PricingEngineVersion.current));
      expect(row.taxInclusiveAtPost, isFalse);
      expect(row.roundingModeAtPost, equals(RoundingModeLabel.halfUp));
    });

    test('purchase_return_adjustments header — snapshot stamped', () async {
      final id = await db
          .into(db.purchaseReturnAdjustments)
          .insert(
            PurchaseReturnAdjustmentsCompanion.insert(
              returnNumber: 'PADJ-A-001',
              supplierId: supplierId,
              currencyId: currencyId,
              totalCents: ten,
            ).withPricingSnapshot(taxInclusive: true),
          );

      final row = await (db.select(
        db.purchaseReturnAdjustments,
      )..where((r) => r.id.equals(id))).getSingle();
      expect(row.pricingEngineVersion, equals(PricingEngineVersion.current));
      expect(row.taxInclusiveAtPost, isTrue);
      expect(row.roundingModeAtPost, equals(RoundingModeLabel.halfUp));
    });
  });

  group('Phase 11.2 — back-compat (legacy NULL semantics)', () {
    test('insert WITHOUT withPricingSnapshot leaves columns NULL', () async {
      // A legacy code path (or a 2024 row migrated forward) is allowed to
      // leave the three audit columns NULL. The schema declares them
      // nullable for exactly this reason — no false positives on legacy
      // data.
      final id = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-LEGACY-001',
              customerId: Value(customerId),
              subtotalCents: ten,
              taxCents: zero,
              totalCents: ten,
              currencyId: currencyId,
              paymentMethod: 'cash',
            ),
          );

      final row = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(id))).getSingle();
      expect(row.pricingEngineVersion, isNull);
      expect(row.taxInclusiveAtPost, isNull);
      expect(row.roundingModeAtPost, isNull);
    });
  });

  group('Phase 11.2 — canonical constants', () {
    test('engine version + rounding mode constants are pinned', () {
      // Bumping these constants is a deliberate, audited act. Tests pin
      // the current values so an accidental rename or version bump fails
      // CI before it can land in a release.
      expect(PricingSnapshot.engineVersion, equals('v1'));
      expect(PricingSnapshot.roundingMode, equals('halfUp'));
      expect(PricingEngineVersion.current, equals(PricingEngineVersion.v1));
    });
  });
}
