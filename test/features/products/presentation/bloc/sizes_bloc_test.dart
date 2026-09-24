import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/size_entity.dart';
import 'package:tapix/features/products/domain/repositories/size_repository.dart';
import 'package:tapix/features/products/presentation/bloc/sizes_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/sizes_event.dart';

class MockSizeRepository extends Mock implements SizeRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Size(id: 0, name: '', sortOrder: 0, isActive: true),
    );
  });

  late MockSizeRepository mockRepository;

  const tSize1 = Size(
    id: 1,
    name: 'Small',
    description: 'S',
    sortOrder: 1,
    isActive: true,
  );

  const tSize2 = Size(
    id: 2,
    name: 'Medium',
    description: 'M',
    sortOrder: 2,
    isActive: true,
  );

  const tSizes = [tSize1, tSize2];

  setUp(() {
    mockRepository = MockSizeRepository();
  });

  group('SizesBloc', () {
    late StreamController<List<Size>> controller;

    test('initial state is RealtimeLoading', () {
      when(
        () => mockRepository.watchAllSizes(),
      ).thenAnswer((_) => const Stream<List<Size>>.empty());
      final bloc = SizesBloc(mockRepository);
      expect(bloc.state, isA<RealtimeLoading<List<Size>>>());
      bloc.close();
    });

    group('LoadSizes', () {
      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'emits success state when sizes are loaded',
        setUp: () {
          reset(mockRepository);
        },
        build: () {
          controller = StreamController<List<Size>>.broadcast();
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => controller.stream);
          addTearDown(controller.close);
          // Emit after build returns (during act) to keep ordering deterministic.
          return SizesBloc(mockRepository);
        },
        act: (bloc) async {
          bloc.add(const LoadSizes());
          await Future<void>.delayed(const Duration(milliseconds: 1));
          controller.add(tSizes);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        },
        expect: () => [
          isA<RealtimeLoading<List<Size>>>(),
          isA<RealtimeSuccess<List<Size>>>().having(
            (s) => s.data.length,
            'data length',
            2,
          ),
        ],
      );

      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'clears search query when loading sizes',
        build: () {
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => Stream.value(tSizes));
          when(
            () => mockRepository.watchSizesBySearch(any()),
          ).thenAnswer((_) => Stream.value([tSize1]));
          return SizesBloc(mockRepository);
        },
        act: (bloc) async {
          bloc.add(const SearchSizes('test'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          bloc.add(const LoadSizes());
        },
        verify: (_) {
          verify(() => mockRepository.watchAllSizes()).called(greaterThan(0));
        },
      );
    });

    group('SearchSizes', () {
      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'filters sizes by search query',
        build: () {
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => const Stream<List<Size>>.empty());
          when(
            () => mockRepository.watchSizesBySearch('Small'),
          ).thenAnswer((_) => Stream.value([tSize1]));
          return SizesBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const SearchSizes('Small')),
        expect: () => [
          isA<RealtimeLoading<List<Size>>>(),
          isA<RealtimeSuccess<List<Size>>>()
              .having((s) => s.data.length, 'data length', 1)
              .having((s) => s.data.first.name, 'first size name', 'Small'),
        ],
        verify: (_) {
          verify(() => mockRepository.watchSizesBySearch('Small')).called(1);
        },
      );
    });

    group('CreateSize', () {
      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'creates a new size successfully',
        build: () {
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => const Stream<List<Size>>.empty());
          when(
            () => mockRepository.createSize(any()),
          ).thenAnswer((_) async => 3);
          return SizesBloc(mockRepository);
        },
        act: (bloc) => bloc.add(
          const CreateSize(name: 'Large', description: 'L', sortOrder: 3),
        ),
        verify: (_) {
          verify(() => mockRepository.createSize(any())).called(1);
        },
      );

      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'emits error when create fails',
        build: () {
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => const Stream<List<Size>>.empty());
          when(
            () => mockRepository.createSize(any()),
          ).thenThrow(Exception('Create failed'));
          return SizesBloc(mockRepository);
        },
        act: (bloc) => bloc.add(
          const CreateSize(name: 'Large', description: 'L', sortOrder: 3),
        ),
        expect: () => [
          isA<RealtimeError<List<Size>>>().having(
            (s) => s.error,
            'error message',
            contains('Create failed'),
          ),
        ],
      );
    });

    group('UpdateSize', () {
      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'updates an existing size successfully',
        build: () {
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => const Stream<List<Size>>.empty());
          when(
            () => mockRepository.updateSize(any()),
          ).thenAnswer((_) async => true);
          return SizesBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const UpdateSize(tSize1)),
        verify: (_) {
          verify(() => mockRepository.updateSize(tSize1)).called(1);
        },
      );

      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'emits error when update fails',
        build: () {
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => const Stream<List<Size>>.empty());
          when(
            () => mockRepository.updateSize(any()),
          ).thenAnswer((_) async => false);
          return SizesBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const UpdateSize(tSize1)),
        expect: () => [
          isA<RealtimeError<List<Size>>>().having(
            (s) => s.error,
            'error message',
            contains('Failed to update'),
          ),
        ],
      );
    });

    group('DeleteSize', () {
      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'deletes a size when it has no products',
        build: () {
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => const Stream<List<Size>>.empty());
          when(
            () => mockRepository.hasProducts(1),
          ).thenAnswer((_) async => false);
          when(() => mockRepository.deleteSize(1)).thenAnswer((_) async => 1);
          return SizesBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const DeleteSize(1)),
        verify: (_) {
          verify(() => mockRepository.hasProducts(1)).called(1);
          verify(() => mockRepository.deleteSize(1)).called(1);
        },
      );

      blocTest<SizesBloc, RealtimeState<List<Size>>>(
        'emits error when size has products',
        build: () {
          when(
            () => mockRepository.watchAllSizes(),
          ).thenAnswer((_) => const Stream<List<Size>>.empty());
          when(
            () => mockRepository.hasProducts(1),
          ).thenAnswer((_) async => true);
          return SizesBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const DeleteSize(1)),
        expect: () => [
          isA<RealtimeError<List<Size>>>().having(
            (s) => s.error,
            'error message',
            contains('Cannot delete'),
          ),
        ],
        verify: (_) {
          verify(() => mockRepository.hasProducts(1)).called(1);
          verifyNever(() => mockRepository.deleteSize(any()));
        },
      );
    });

    group('getProductCounts', () {
      test('returns product counts for all sizes', () async {
        when(
          () => mockRepository.watchAllSizes(),
        ).thenAnswer((_) => const Stream<List<Size>>.empty());
        when(
          () => mockRepository.getProductCountBySize(1),
        ).thenAnswer((_) async => 5);
        when(
          () => mockRepository.getProductCountBySize(2),
        ).thenAnswer((_) async => 3);

        final bloc = SizesBloc(mockRepository);

        final counts = await bloc.getProductCounts(tSizes);

        expect(counts, {1: 5, 2: 3});
        verify(() => mockRepository.getProductCountBySize(1)).called(1);
        verify(() => mockRepository.getProductCountBySize(2)).called(1);

        await bloc.close();
      });
    });
  });
}
