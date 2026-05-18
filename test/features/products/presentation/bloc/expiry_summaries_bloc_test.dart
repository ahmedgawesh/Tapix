// ─────────────────────────────────────────────────────────────────────────────
// ExpirySummariesBloc — unit tests
//
// The bloc is intentionally thin: it consumes a Drift-driven stream from the
// repository and converts each raw `(expiredQty, nextExpiry)` tuple into a
// fully-resolved `ExpirySummary` (computing `daysUntilNearestExpiry` once per
// emission). These tests pin that conversion + the loading/error contract
// inherited from `RealtimeBloc`.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/expiry_summary.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/presentation/bloc/expiry_summaries_bloc.dart';

class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late ProductRepository repo;

  // Build a "today at start-of-day" anchor that the bloc uses internally so
  // the diff math in tests matches the bloc's own clamp.
  DateTime startOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  setUp(() {
    repo = MockProductRepository();
  });

  group('ExpirySummariesBloc — stream → ExpirySummary mapping', () {
    blocTest<ExpirySummariesBloc, RealtimeState<Map<int, ExpirySummary>>>(
      'maps a healthy future expiry into nearExpiry-eligible summary',
      build: () {
        when(() => repo.watchExpirySummaries()).thenAnswer(
          (_) => Stream.value({
            42: (
              expiredQty: 0,
              nextExpiry: startOfToday().add(const Duration(days: 7)),
            ),
          }),
        );
        return ExpirySummariesBloc(repo);
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state, isA<RealtimeSuccess<Map<int, ExpirySummary>>>());
        final data =
            (bloc.state as RealtimeSuccess<Map<int, ExpirySummary>>).data;
        expect(data.keys, [42]);
        final s = data[42]!;
        expect(s.hasExpired, isFalse);
        expect(s.expiredQuantity, 0);
        expect(s.daysUntilNearestExpiry, 7);
        expect(s.statusFor(), ExpiryStatus.nearExpiry);
      },
    );

    blocTest<ExpirySummariesBloc, RealtimeState<Map<int, ExpirySummary>>>(
      'flags hasExpired=true when DAO reports expiredQty > 0',
      build: () {
        when(() => repo.watchExpirySummaries()).thenAnswer(
          (_) => Stream.value({
            7: (expiredQty: 4, nextExpiry: null),
          }),
        );
        return ExpirySummariesBloc(repo);
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final data =
            (bloc.state as RealtimeSuccess<Map<int, ExpirySummary>>).data;
        final s = data[7]!;
        expect(s.hasExpired, isTrue);
        expect(s.expiredQuantity, 4);
        expect(s.daysUntilNearestExpiry, isNull);
        expect(s.statusFor(), ExpiryStatus.expired);
      },
    );

    blocTest<ExpirySummariesBloc, RealtimeState<Map<int, ExpirySummary>>>(
      'clamps a negative day-diff to 0 (midnight rollover guard)',
      build: () {
        // Simulate the rollover-in-flight case: the SQL filtered with
        // `expiry_date >= today_iso`, but by the time the bloc receives the
        // emission `today` advanced to a later day — yielding a negative
        // diff. The bloc must clamp to 0, not propagate negatives.
        final yesterday = startOfToday().subtract(const Duration(days: 1));
        when(() => repo.watchExpirySummaries()).thenAnswer(
          (_) => Stream.value({
            9: (expiredQty: 0, nextExpiry: yesterday),
          }),
        );
        return ExpirySummariesBloc(repo);
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final data =
            (bloc.state as RealtimeSuccess<Map<int, ExpirySummary>>).data;
        final s = data[9]!;
        expect(s.daysUntilNearestExpiry, 0,
            reason: 'negative diff must be clamped to 0');
        expect(s.statusFor(), ExpiryStatus.nearExpiry);
      },
    );

    blocTest<ExpirySummariesBloc, RealtimeState<Map<int, ExpirySummary>>>(
      'preserves multiple products independently in a single emission',
      build: () {
        when(() => repo.watchExpirySummaries()).thenAnswer(
          (_) => Stream.value({
            1: (expiredQty: 2, nextExpiry: null),
            2: (
              expiredQty: 0,
              nextExpiry: startOfToday().add(const Duration(days: 90)),
            ),
            3: (
              expiredQty: 1,
              nextExpiry: startOfToday().add(const Duration(days: 5)),
            ),
          }),
        );
        return ExpirySummariesBloc(repo);
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final data =
            (bloc.state as RealtimeSuccess<Map<int, ExpirySummary>>).data;
        expect(data.length, 3);
        expect(data[1]!.statusFor(), ExpiryStatus.expired);
        expect(data[2]!.statusFor(), ExpiryStatus.healthy);
        // Product 3 has BOTH expired stock and a near future date —
        // expired must win (decision rule #1).
        expect(data[3]!.statusFor(), ExpiryStatus.expired);
      },
    );

    blocTest<ExpirySummariesBloc, RealtimeState<Map<int, ExpirySummary>>>(
      'empty stream emission yields an empty success map',
      build: () {
        when(() => repo.watchExpirySummaries()).thenAnswer(
          (_) => Stream.value(
            const <int, ({int expiredQty, DateTime? nextExpiry})>{},
          ),
        );
        return ExpirySummariesBloc(repo);
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state, isA<RealtimeSuccess<Map<int, ExpirySummary>>>());
        final data =
            (bloc.state as RealtimeSuccess<Map<int, ExpirySummary>>).data;
        expect(data, isEmpty);
      },
    );
  });

  group('ExpirySummariesBloc — RealtimeBloc contract', () {
    test('initial state is RealtimeLoading', () {
      when(() => repo.watchExpirySummaries())
          .thenAnswer((_) => const Stream.empty());
      final bloc = ExpirySummariesBloc(repo);
      expect(bloc.state, isA<RealtimeLoading<Map<int, ExpirySummary>>>());
      bloc.close();
    });

    blocTest<ExpirySummariesBloc, RealtimeState<Map<int, ExpirySummary>>>(
      're-emits when the underlying stream emits again',
      build: () {
        final ctrl = StreamController<
            Map<int, ({int expiredQty, DateTime? nextExpiry})>>();
        when(() => repo.watchExpirySummaries())
            .thenAnswer((_) => ctrl.stream);
        // Stash the controller on the bloc by wrapping it through closure.
        final bloc = ExpirySummariesBloc(repo);
        // Drive two emissions back-to-back.
        Future<void>.delayed(const Duration(milliseconds: 5), () {
          ctrl.add({1: (expiredQty: 0, nextExpiry: startOfToday())});
        });
        Future<void>.delayed(const Duration(milliseconds: 20), () {
          ctrl.add({1: (expiredQty: 3, nextExpiry: null)});
          ctrl.close();
        });
        return bloc;
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        final data =
            (bloc.state as RealtimeSuccess<Map<int, ExpirySummary>>).data;
        // Latest emission wins — product flipped from healthy/near to expired.
        expect(data[1]!.hasExpired, isTrue);
        expect(data[1]!.expiredQuantity, 3);
      },
    );
  });
}
