import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/suppliers/presentation/bloc/suppliers_bloc.dart';

void main() {
  group('SuppliersData', () {
    test('default values are correct', () {
      const data = SuppliersData(suppliers: []);

      expect(data.searchQuery, isNull);
      expect(data.isSearching, isFalse);
      expect(data.suppliers, isEmpty);
    });

    test('copyWith preserves values correctly', () {
      const original = SuppliersData(
        suppliers: [],
        searchQuery: 'test',
        isSearching: true,
      );

      final copied = original.copyWith(
        isSearching: false,
      );

      expect(copied.searchQuery, equals('test'));
      expect(copied.isSearching, isFalse);
    });

    test('copyWith can update searchQuery', () {
      const original = SuppliersData(
        suppliers: [],
        searchQuery: 'old',
        isSearching: true,
      );

      final copied = original.copyWith(
        searchQuery: 'new',
      );

      expect(copied.searchQuery, equals('new'));
      expect(copied.isSearching, isTrue);
    });
  });
}
