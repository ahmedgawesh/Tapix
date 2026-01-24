import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';

class TestData {
  final int id;
  final String value;

  const TestData(this.id, this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestData &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          value == other.value;

  @override
  int get hashCode => id.hashCode ^ value.hashCode;
}

class TestRealtimeBloc extends RealtimeBloc<List<TestData>, RealtimeEvent> {
  final StreamController<List<TestData>> _controller;

  TestRealtimeBloc(this._controller) : super();

  @override
  Stream<List<TestData>> get dataStream => _controller.stream;

  @override
  void registerEventHandlers() {}

  void emitData(List<TestData> data) {
    _controller.add(data);
  }

  void emitError(Object error) {
    _controller.addError(error);
  }
}

void main() {
  group('RealtimeState', () {
    test('RealtimeInitial is created correctly', () {
      const state = RealtimeInitial<List<String>>();
      expect(state, isA<RealtimeState<List<String>>>());
    });

    test('RealtimeLoading preserves previous data', () {
      const state = RealtimeLoading<List<String>>(
        previousData: ['item1', 'item2'],
      );
      expect(state.previousData, equals(['item1', 'item2']));
    });

    test('RealtimeSuccess contains data and timestamp', () {
      final state = RealtimeSuccess<String>(data: 'test');
      expect(state.data, equals('test'));
      expect(state.lastUpdated, isNotNull);
    });

    test('RealtimeError contains error and previous data', () {
      final state = RealtimeError<String>(
        error: Exception('Test error'),
        previousData: 'previous',
      );
      expect(state.error, isA<Exception>());
      expect(state.previousData, equals('previous'));
      expect(state.timestamp, isNotNull);
    });

    test('RealtimeOptimistic contains optimistic and previous data', () {
      const state = RealtimeOptimistic<String>(
        optimisticData: 'new',
        previousData: 'old',
        operationId: 'op1',
      );
      expect(state.optimisticData, equals('new'));
      expect(state.previousData, equals('old'));
      expect(state.operationId, equals('op1'));
    });
  });

  group('RealtimeBloc', () {
    late StreamController<List<TestData>> controller;
    late TestRealtimeBloc bloc;

    setUp(() {
      controller = StreamController<List<TestData>>.broadcast();
      bloc = TestRealtimeBloc(controller);
    });

    tearDown(() async {
      await bloc.close();
      await controller.close();
    });

    test('initial state is RealtimeLoading', () {
      expect(bloc.state, isA<RealtimeLoading<List<TestData>>>());
    });

    blocTest<TestRealtimeBloc, RealtimeState<List<TestData>>>(
      'emits RealtimeSuccess when stream emits data',
      build: () => bloc,
      act: (bloc) {
        bloc.emitData([const TestData(1, 'item1')]);
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<RealtimeSuccess<List<TestData>>>().having(
          (s) => s.data.length,
          'data length',
          1,
        ),
      ],
    );

    blocTest<TestRealtimeBloc, RealtimeState<List<TestData>>>(
      'emits RealtimeError when stream errors',
      build: () => bloc,
      act: (bloc) {
        bloc.emitError(Exception('Test error'));
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<RealtimeError<List<TestData>>>(),
      ],
    );

    blocTest<TestRealtimeBloc, RealtimeState<List<TestData>>>(
      'refresh triggers RealtimeLoading then resubscribes',
      build: () => bloc,
      seed: () => RealtimeSuccess<List<TestData>>(
        data: [const TestData(1, 'existing')],
      ),
      act: (bloc) {
        bloc.refresh();
      },
      expect: () => [
        isA<RealtimeLoading<List<TestData>>>().having(
          (s) => s.previousData?.length,
          'previous data length',
          1,
        ),
      ],
    );

    test('hasData returns true when in success state', () async {
      bloc.emitData([const TestData(1, 'test')]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.hasData, isTrue);
    });

    test('currentData returns data from success state', () async {
      final testData = [const TestData(1, 'test')];
      bloc.emitData(testData);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.currentData, equals(testData));
    });

    test('currentData returns null in initial state', () {
      final freshController = StreamController<List<TestData>>.broadcast();
      final freshBloc = TestRealtimeBloc(freshController);

      expect(freshBloc.currentData, isNull);

      freshBloc.close();
      freshController.close();
    });
  });

  group('Optimistic Updates', () {
    late StreamController<List<TestData>> controller;
    late TestRealtimeBloc bloc;

    setUp(() {
      controller = StreamController<List<TestData>>.broadcast();
      bloc = TestRealtimeBloc(controller);
    });

    tearDown(() async {
      await bloc.close();
      await controller.close();
    });

    blocTest<TestRealtimeBloc, RealtimeState<List<TestData>>>(
      'optimistic update emits optimistic state',
      build: () => bloc,
      seed: () => RealtimeSuccess<List<TestData>>(
        data: [const TestData(1, 'original')],
      ),
      act: (bloc) {
        bloc.add(const RealtimeOptimisticUpdate<List<TestData>>(
          optimisticData: [TestData(1, 'updated')],
          operationId: 'op1',
        ));
      },
      expect: () => [
        isA<RealtimeOptimistic<List<TestData>>>().having(
          (s) => s.optimisticData.first.value,
          'optimistic value',
          'updated',
        ),
      ],
    );

    blocTest<TestRealtimeBloc, RealtimeState<List<TestData>>>(
      'optimistic confirm emits success with optimistic data',
      build: () => bloc,
      seed: () => const RealtimeOptimistic<List<TestData>>(
        optimisticData: [TestData(1, 'updated')],
        previousData: [TestData(1, 'original')],
        operationId: 'op1',
      ),
      act: (bloc) {
        bloc.add(const RealtimeOptimisticConfirmed('op1'));
      },
      expect: () => [
        isA<RealtimeSuccess<List<TestData>>>().having(
          (s) => s.data.first.value,
          'confirmed value',
          'updated',
        ),
      ],
    );

    blocTest<TestRealtimeBloc, RealtimeState<List<TestData>>>(
      'optimistic rollback emits success with previous data',
      build: () => bloc,
      seed: () => const RealtimeOptimistic<List<TestData>>(
        optimisticData: [TestData(1, 'updated')],
        previousData: [TestData(1, 'original')],
        operationId: 'op1',
      ),
      act: (bloc) {
        bloc.add(const RealtimeOptimisticRollback('op1'));
      },
      expect: () => [
        isA<RealtimeSuccess<List<TestData>>>().having(
          (s) => s.data.first.value,
          'rolled back value',
          'original',
        ),
      ],
    );

    blocTest<TestRealtimeBloc, RealtimeState<List<TestData>>>(
      'optimistic rollback with error emits error state',
      build: () => bloc,
      seed: () => const RealtimeOptimistic<List<TestData>>(
        optimisticData: [TestData(1, 'updated')],
        previousData: [TestData(1, 'original')],
        operationId: 'op1',
      ),
      act: (bloc) {
        bloc.add(RealtimeOptimisticRollback('op1', Exception('Failed')));
      },
      expect: () => [
        isA<RealtimeError<List<TestData>>>(),
      ],
    );

    test('performOptimisticUpdate confirms on success', () async {
      bloc.emitData([const TestData(1, 'original')]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await bloc.performOptimisticUpdate(
        operationId: 'op1',
        optimisticData: [const TestData(1, 'updated')],
        operation: () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state, isA<RealtimeSuccess<List<TestData>>>());
      expect((bloc.state as RealtimeSuccess).data.first.value, equals('updated'));
    });

    test('performOptimisticUpdate rolls back on failure', () async {
      bloc.emitData([const TestData(1, 'original')]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      try {
        await bloc.performOptimisticUpdate(
          operationId: 'op1',
          optimisticData: [const TestData(1, 'updated')],
          operation: () async {
            throw Exception('Operation failed');
          },
        );
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state, isA<RealtimeError<List<TestData>>>());
    });
  });

  group('Memory and Cleanup', () {
    test('bloc closes stream subscription on close', () async {
      final controller = StreamController<List<TestData>>.broadcast();
      final bloc = TestRealtimeBloc(controller);

      await bloc.close();

      expect(bloc.isClosed, isTrue);
      await controller.close();
    });

    test('bloc handles multiple rapid updates', () async {
      final controller = StreamController<List<TestData>>.broadcast();
      final bloc = TestRealtimeBloc(controller);

      for (int i = 0; i < 100; i++) {
        bloc.emitData([TestData(i, 'item$i')]);
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(bloc.state, isA<RealtimeSuccess<List<TestData>>>());

      await bloc.close();
      await controller.close();
    });

    test('bloc ignores events after close', () async {
      final controller = StreamController<List<TestData>>.broadcast();
      final bloc = TestRealtimeBloc(controller);

      await bloc.close();

      bloc.emitData([const TestData(1, 'test')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.isClosed, isTrue);
      await controller.close();
    });
  });
}
