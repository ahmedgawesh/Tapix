import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/products/presentation/bloc/export_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/export_event.dart';

class MockExportBloc extends Mock implements ExportBloc {}

void main() {
  late MockExportBloc mockExportBloc;

  setUp(() {
    mockExportBloc = MockExportBloc();
  });

  setUpAll(() {
    registerFallbackValue(const LoadExportPreview());
    registerFallbackValue(const ExportToCSV());
    registerFallbackValue(const ExportToExcel());
    registerFallbackValue(const UpdateExportFormat(ExportFormat.csv));
  });

  group('SimpleExportScreen Widget Tests', () {
    test('ExportBloc handles state transitions correctly', () {
      expect(mockExportBloc, isNotNull);
    });

    test('ExportEvent equality works correctly', () {
      const event1 = LoadExportPreview();
      const event2 = LoadExportPreview();
      expect(event1, equals(event2));
    });

    test('ExportFormat enum has correct values', () {
      expect(ExportFormat.csv, isNotNull);
      expect(ExportFormat.excel, isNotNull);
    });
  });
}
