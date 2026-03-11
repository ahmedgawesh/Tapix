import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/purchases/domain/entities/purchase_entity.dart';

void main() {
  group('PurchaseReturnEntity', () {
    test('has correct default values', () {
      final returnEntity = PurchaseReturnEntity(
        id: 1,
        purchaseId: 1,
        returnNumber: 'PR-202601-0001',
        totalCents: Decimal.fromInt(5500),
        currencyId: 1,
        returnDate: DateTime(2026, 1, 15),
        createdAt: DateTime(2026, 1, 15),
      );

      expect(returnEntity.status, equals('draft'));
      expect(returnEntity.dispositionType, equals('restock'));
      expect(returnEntity.refundMethod, equals('credit'));
      expect(returnEntity.subtotalCents, equals(Decimal.zero));
      expect(returnEntity.discountCents, equals(Decimal.zero));
      expect(returnEntity.taxCents, equals(Decimal.zero));
    });

    test('has correct properties when fully specified', () {
      final returnEntity = PurchaseReturnEntity(
        id: 1,
        purchaseId: 1,
        returnNumber: 'PR-202601-0001',
        supplierName: 'Supplier A',
        subtotalCents: Decimal.fromInt(5000),
        discountCents: Decimal.zero,
        taxCents: Decimal.fromInt(500),
        totalCents: Decimal.fromInt(5500),
        currencyId: 1,
        status: 'completed',
        dispositionType: 'restock',
        refundMethod: 'cash',
        returnDate: DateTime(2026, 1, 15),
        createdAt: DateTime(2026, 1, 15),
      );

      expect(returnEntity.id, equals(1));
      expect(returnEntity.purchaseId, equals(1));
      expect(returnEntity.returnNumber, equals('PR-202601-0001'));
      expect(returnEntity.supplierName, equals('Supplier A'));
      expect(returnEntity.totalCents, equals(Decimal.fromInt(5500)));
      expect(returnEntity.status, equals('completed'));
    });

    test('isDraft returns true for draft status', () {
      final draftReturn = PurchaseReturnEntity(
        id: 1,
        purchaseId: 1,
        returnNumber: 'PR-001',
        totalCents: Decimal.fromInt(1000),
        currencyId: 1,
        status: 'draft',
        returnDate: DateTime(2026, 1, 15),
        createdAt: DateTime(2026, 1, 15),
      );

      expect(draftReturn.isDraft, isTrue);
      expect(draftReturn.isPosted, isFalse);
      expect(draftReturn.isVoided, isFalse);
    });

    test('isPosted returns true for posted status', () {
      final postedReturn = PurchaseReturnEntity(
        id: 1,
        purchaseId: 1,
        returnNumber: 'PR-001',
        totalCents: Decimal.fromInt(1000),
        currencyId: 1,
        status: 'posted',
        returnDate: DateTime(2026, 1, 15),
        createdAt: DateTime(2026, 1, 15),
      );

      expect(postedReturn.isDraft, isFalse);
      expect(postedReturn.isPosted, isTrue);
      expect(postedReturn.isVoided, isFalse);
    });

    test('isVoided returns true for voided status', () {
      final voidedReturn = PurchaseReturnEntity(
        id: 1,
        purchaseId: 1,
        returnNumber: 'PR-001',
        totalCents: Decimal.fromInt(1000),
        currencyId: 1,
        status: 'voided',
        returnDate: DateTime(2026, 1, 15),
        createdAt: DateTime(2026, 1, 15),
      );

      expect(voidedReturn.isDraft, isFalse);
      expect(voidedReturn.isPosted, isFalse);
      expect(voidedReturn.isVoided, isTrue);
    });

    test('calculates totals correctly', () {
      final returnEntity = PurchaseReturnEntity(
        id: 2,
        purchaseId: 2,
        returnNumber: 'PR-202601-0002',
        subtotalCents: Decimal.fromInt(10000),
        discountCents: Decimal.fromInt(500),
        taxCents: Decimal.fromInt(950),
        totalCents: Decimal.fromInt(10450),
        currencyId: 1,
        status: 'pending',
        returnDate: DateTime(2026, 1, 16),
        createdAt: DateTime(2026, 1, 16),
      );

      // subtotal: 10000, discount: 500, tax: 950, total: 10450
      expect(returnEntity.subtotalCents, equals(Decimal.fromInt(10000)));
      expect(returnEntity.discountCents, equals(Decimal.fromInt(500)));
      expect(returnEntity.taxCents, equals(Decimal.fromInt(950)));
      expect(returnEntity.totalCents, equals(Decimal.fromInt(10450)));
    });
  });
}
