import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/size_dao.dart';
import 'package:tapix/features/products/data/repositories/size_repository_impl.dart';
import 'package:tapix/features/products/domain/entities/size_entity.dart'
    as domain;

class MockAppDatabase extends Mock implements AppDatabase {}

class MockSizeDao extends Mock implements SizeDao {}

class _FakeDriftSize extends Fake implements Size {}

class _FakeSizesCompanion extends Fake implements SizesCompanion {}

void main() {
  late SizeRepositoryImpl repository;
  late MockAppDatabase mockDatabase;
  late MockSizeDao mockSizeDao;

  setUpAll(() {
    registerFallbackValue(_FakeDriftSize());
    registerFallbackValue(_FakeSizesCompanion());
  });

  setUp(() {
    mockDatabase = MockAppDatabase();
    mockSizeDao = MockSizeDao();
    when(() => mockDatabase.sizeDao).thenReturn(mockSizeDao);
    repository = SizeRepositoryImpl(mockDatabase);
  });

  final tDriftSize = Size(
    id: 1,
    name: 'Small',
    description: 'S',
    sortOrder: 1,
    isActive: true,
    createdAt: DateTime(2024, 1, 1),
  );

  const tSizeEntity = domain.Size(
    id: 1,
    name: 'Small',
    description: 'S',
    sortOrder: 1,
    isActive: true,
  );

  group('SizeRepositoryImpl', () {
    group('watchAllSizes', () {
      test('returns stream of sizes from DAO', () async {
        when(
          () => mockSizeDao.watchAllSizes(),
        ).thenAnswer((_) => Stream.value([tDriftSize]));

        final result = repository.watchAllSizes();

        await expectLater(
          result,
          emits(isA<List<domain.Size>>().having((l) => l.length, 'length', 1)),
        );
        verify(() => mockSizeDao.watchAllSizes()).called(1);
      });
    });

    group('watchSizesBySearch', () {
      test('filters sizes by search query', () async {
        when(
          () => mockSizeDao.watchAllSizes(),
        ).thenAnswer((_) => Stream.value([tDriftSize]));

        final result = repository.watchSizesBySearch('Small');

        await expectLater(
          result,
          emits(isA<List<domain.Size>>().having((l) => l.length, 'length', 1)),
        );
      });

      test('returns empty list when no sizes match', () async {
        when(
          () => mockSizeDao.watchAllSizes(),
        ).thenAnswer((_) => Stream.value([tDriftSize]));

        final result = repository.watchSizesBySearch('XL');

        await expectLater(
          result,
          emits(isA<List<domain.Size>>().having((l) => l.length, 'length', 0)),
        );
      });
    });

    group('getAllSizes', () {
      test('returns list of sizes from DAO', () async {
        when(
          () => mockSizeDao.getAllSizes(),
        ).thenAnswer((_) async => [tDriftSize]);

        final result = await repository.getAllSizes();

        expect(result, isA<List<domain.Size>>());
        expect(result.length, 1);
        verify(() => mockSizeDao.getAllSizes()).called(1);
      });
    });

    group('getSizeById', () {
      test('returns size when found', () async {
        when(
          () => mockSizeDao.getSizeById(1),
        ).thenAnswer((_) async => tDriftSize);

        final result = await repository.getSizeById(1);

        expect(result, isNotNull);
        expect(result?.id, 1);
        verify(() => mockSizeDao.getSizeById(1)).called(1);
      });

      test('returns null when size not found', () async {
        when(() => mockSizeDao.getSizeById(999)).thenAnswer((_) async => null);

        final result = await repository.getSizeById(999);

        expect(result, isNull);
        verify(() => mockSizeDao.getSizeById(999)).called(1);
      });
    });

    group('createSize', () {
      test('creates size successfully', () async {
        when(() => mockSizeDao.createSize(any())).thenAnswer((_) async => 1);

        final result = await repository.createSize(tSizeEntity);

        expect(result, 1);
        verify(() => mockSizeDao.createSize(any())).called(1);
      });
    });

    group('updateSize', () {
      test('updates size successfully', () async {
        when(
          () => mockSizeDao.getSizeById(1),
        ).thenAnswer((_) async => tDriftSize);
        when(() => mockSizeDao.updateSize(any())).thenAnswer((_) async => true);

        final result = await repository.updateSize(tSizeEntity);

        expect(result, true);
        verify(() => mockSizeDao.getSizeById(1)).called(1);
        verify(() => mockSizeDao.updateSize(any())).called(1);
      });

      test('returns false when size not found', () async {
        when(() => mockSizeDao.getSizeById(999)).thenAnswer((_) async => null);

        final result = await repository.updateSize(
          const domain.Size(
            id: 999,
            name: 'Test',
            sortOrder: 1,
            isActive: true,
          ),
        );

        expect(result, false);
        verify(() => mockSizeDao.getSizeById(999)).called(1);
        verifyNever(() => mockSizeDao.updateSize(any()));
      });
    });

    group('deleteSize', () {
      test('deletes size successfully', () async {
        when(() => mockSizeDao.deleteSize(1)).thenAnswer((_) async => 1);

        final result = await repository.deleteSize(1);

        expect(result, 1);
        verify(() => mockSizeDao.deleteSize(1)).called(1);
      });
    });

    group('hasProducts', () {
      test('returns true when size has products', () async {
        when(
          () => mockSizeDao.getProductCountBySize(1),
        ).thenAnswer((_) async => 5);
        final result = await repository.hasProducts(1);
        expect(result, true);
      });

      test('returns false when size has no products', () async {
        when(
          () => mockSizeDao.getProductCountBySize(1),
        ).thenAnswer((_) async => 0);
        final result = await repository.hasProducts(1);
        expect(result, false);
      });
    });

    group('getProductCountBySize', () {
      test('returns correct product count', () async {
        when(
          () => mockSizeDao.getProductCountBySize(1),
        ).thenAnswer((_) async => 10);
        final result = await repository.getProductCountBySize(1);
        expect(result, 10);
      });
    });
  });
}
