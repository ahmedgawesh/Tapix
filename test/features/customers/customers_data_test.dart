import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/customers/presentation/bloc/customers_bloc.dart';

void main() {
  group('CustomersData', () {
    test('default values are correct', () {
      const data = CustomersData(customers: []);

      expect(data.searchQuery, isNull);
      expect(data.isSearching, isFalse);
      expect(data.customers, isEmpty);
    });

    test('copyWith preserves values correctly', () {
      const original = CustomersData(
        customers: [],
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
      const original = CustomersData(
        customers: [],
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
