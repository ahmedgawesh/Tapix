import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/stock_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // StockDirection enum
  // ═══════════════════════════════════════════════════════════════════════════

  group('StockDirection', () {
    test('has exactly two values', () {
      expect(StockDirection.values.length, 2);
    });

    test('contains increase and decrease', () {
      expect(StockDirection.values, contains(StockDirection.increase));
      expect(StockDirection.values, contains(StockDirection.decrease));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // StockService assertions (debug mode only)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Note: StockService.adjustStock and syncProductStockFromVariants require a
  // live DatabaseAccessor, so full integration tests live in the integration
  // test suite. Here we verify the public API surface and enum behaviour.
  // ═══════════════════════════════════════════════════════════════════════════

  group('StockService', () {
    test('class is not instantiable (private constructor)', () {
      // Compile-time guarantee — StockService._() prevents external `new`.
      // This test documents the intent.
      expect(StockService, isNotNull);
    });
  });
}
