import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/products/presentation/bloc/bulk_product_bloc.dart';

void main() {
  group('BulkProductFormScreen', () {
    testWidgets('BulkProductRowData can be created', (tester) async {
      final rowData = BulkProductRowData.empty(0);
      
      expect(rowData.rowIndex, 0);
      expect(rowData.name, '');
    });

    testWidgets('BulkProductEditing state can be created', (tester) async {
      final state = BulkProductEditing(
        rows: [BulkProductRowData.empty(0)],
        validationErrors: const {},
      );
      
      expect(state.rows.length, 1);
      expect(state.hasValidationErrors, false);
    });

    testWidgets('BulkProductSubmitting calculates progress correctly', (tester) async {
      const state = BulkProductSubmitting(
        totalCount: 5,
        currentIndex: 2,
        rows: [],
      );
      
      expect(state.progress, 0.4);
    });
  });
}
