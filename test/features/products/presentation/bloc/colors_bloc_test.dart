import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/product_color_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_color_repository.dart';
import 'package:tapix/features/products/data/models/product_color_model.dart';
import 'package:tapix/features/products/presentation/bloc/colors_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/colors_event.dart';

class MockProductColorRepository extends Mock implements ProductColorRepository {}

void main() {
  late MockProductColorRepository mockRepository;

  setUp(() {
    mockRepository = MockProductColorRepository();

    registerFallbackValue(
      const ProductColorModel(
        id: 0,
        name: 'fallback',
        hexCode: null,
        isActive: true,
      ),
    );

    when(() => mockRepository.watchAllColors())
        .thenAnswer((_) => const Stream.empty());
    when(() => mockRepository.watchColorsBySearch(any()))
        .thenAnswer((_) => const Stream.empty());
  });

  group('ColorsBloc', () {
    const tColor1 = ProductColorModel(
      id: 1,
      name: 'Red',
      hexCode: '#FF0000',
      isActive: true,
    );

    const tColor2 = ProductColorModel(
      id: 2,
      name: 'Blue',
      hexCode: '#0000FF',
      isActive: true,
    );

    final tColors = <ProductColor>[tColor1, tColor2];

    test('initial state is RealtimeLoading', () {
      final bloc = ColorsBloc(mockRepository);
      addTearDown(bloc.close);

      expect(bloc.state, isA<RealtimeLoading<List<ProductColor>>>());
    });

    blocTest<ColorsBloc, RealtimeState<List<ProductColor>>>(
      'emits colors when LoadColors is added',
      build: () {
        when(() => mockRepository.watchAllColors())
            .thenAnswer((_) => Stream.value(tColors));
        return ColorsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadColors()),
      expect: () => [
        isA<RealtimeSuccess<List<ProductColor>>>(),
        isA<RealtimeLoading<List<ProductColor>>>(),
        isA<RealtimeSuccess<List<ProductColor>>>(),
      ],
      verify: (_) {
        verify(() => mockRepository.watchAllColors()).called(greaterThanOrEqualTo(1));
      },
    );

    blocTest<ColorsBloc, RealtimeState<List<ProductColor>>>(
      'emits filtered colors when SearchColors is added',
      build: () {
        when(() => mockRepository.watchAllColors())
            .thenAnswer((_) => const Stream.empty());
        when(() => mockRepository.watchColorsBySearch(any()))
            .thenAnswer((_) => Stream.value(<ProductColor>[tColor1]));
        return ColorsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const SearchColors('Red')),
      expect: () => [
        isA<RealtimeLoading<List<ProductColor>>>(),
        isA<RealtimeSuccess<List<ProductColor>>>(),
      ],
      verify: (_) {
        verify(() => mockRepository.watchColorsBySearch('Red')).called(1);
      },
    );

    blocTest<ColorsBloc, RealtimeState<List<ProductColor>>>(
      'creates color when CreateColor is added',
      build: () {
        when(() => mockRepository.createColor(any()))
            .thenAnswer((_) async => 1);
        when(() => mockRepository.watchAllColors())
            .thenAnswer((_) => Stream.value(tColors));
        return ColorsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const CreateColor(
        name: 'Green',
        hexCode: '#00FF00',
      )),
      verify: (_) {
        verify(() => mockRepository.createColor(any())).called(1);
      },
    );

    blocTest<ColorsBloc, RealtimeState<List<ProductColor>>>(
      'updates color when UpdateColor is added',
      build: () {
        when(() => mockRepository.updateColor(any()))
            .thenAnswer((_) async => true);
        when(() => mockRepository.watchAllColors())
            .thenAnswer((_) => Stream.value(tColors));
        return ColorsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const UpdateColor(tColor1)),
      verify: (_) {
        verify(() => mockRepository.updateColor(tColor1)).called(1);
      },
    );

    blocTest<ColorsBloc, RealtimeState<List<ProductColor>>>(
      'deletes color when DeleteColor is added and color has no products',
      build: () {
        when(() => mockRepository.hasProducts(any()))
            .thenAnswer((_) async => false);
        when(() => mockRepository.deleteColor(any()))
            .thenAnswer((_) async {});
        when(() => mockRepository.watchAllColors())
            .thenAnswer((_) => Stream.value(tColors));
        return ColorsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const DeleteColor(1)),
      verify: (_) {
        verify(() => mockRepository.hasProducts(1)).called(1);
        verify(() => mockRepository.deleteColor(1)).called(1);
      },
    );

    blocTest<ColorsBloc, RealtimeState<List<ProductColor>>>(
      'emits error when DeleteColor is added and color has products',
      build: () {
        when(() => mockRepository.hasProducts(any()))
            .thenAnswer((_) async => true);
        when(() => mockRepository.watchAllColors())
            .thenAnswer((_) => Stream.value(tColors));
        return ColorsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const DeleteColor(1)),
      expect: () => [
        isA<RealtimeSuccess<List<ProductColor>>>(),
        isA<RealtimeError<List<ProductColor>>>()
            .having(
              (state) => state.error,
              'error',
              contains('Cannot delete color with assigned products'),
            ),
      ],
      verify: (_) {
        verify(() => mockRepository.hasProducts(1)).called(1);
        verifyNever(() => mockRepository.deleteColor(any()));
      },
    );

    test('getProductCounts returns correct counts', () async {
      final bloc = ColorsBloc(mockRepository);
      addTearDown(bloc.close);

      when(() => mockRepository.getProductCountByColor(1))
          .thenAnswer((_) async => 5);
      when(() => mockRepository.getProductCountByColor(2))
          .thenAnswer((_) async => 3);

      final counts = await bloc.getProductCounts(tColors);

      expect(counts[1], 5);
      expect(counts[2], 3);
      verify(() => mockRepository.getProductCountByColor(1)).called(1);
      verify(() => mockRepository.getProductCountByColor(2)).called(1);
    });
  });
}
