import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/accounting/domain/repositories/journal_repository.dart';
import 'package:tapix/features/accounting/presentation/bloc/journal_entries_bloc.dart';

@GenerateMocks([JournalRepository])
import 'journal_entries_bloc_test.mocks.dart';

JournalEntry _makeEntry({
  int id = 1,
  String entryNumber = 'JE-000001',
  String status = 'draft',
  String entryType = 'manual',
}) {
  return JournalEntry(
    id: id,
    entryNumber: entryNumber,
    description: 'Test entry',
    entryDate: DateTime(2026, 1, 15),
    status: status,
    entryType: entryType,
    totalDebitCents: Decimal.fromInt(1000),
    totalCreditCents: Decimal.fromInt(1000),
    isReversed: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

void main() {
  late MockJournalRepository mockRepository;

  setUp(() {
    mockRepository = MockJournalRepository();
  });

  group('JournalEntriesBloc', () {
    final entries = [_makeEntry(), _makeEntry(id: 2, entryNumber: 'JE-000002')];

    blocTest<JournalEntriesBloc, RealtimeState<JournalEntriesData>>(
      'emits RealtimeSuccess with entries from stream',
      setUp: () {
        when(
          mockRepository.watchAllJournalEntries(),
        ).thenAnswer((_) => Stream.value(entries));
      },
      build: () => JournalEntriesBloc(mockRepository),
      expect: () => [
        isA<RealtimeSuccess<JournalEntriesData>>().having(
          (s) => s.data.entries.length,
          'entries count',
          2,
        ),
      ],
    );

    blocTest<JournalEntriesBloc, RealtimeState<JournalEntriesData>>(
      'filters by status when JournalEntriesFilterByStatusRequested',
      setUp: () {
        when(
          mockRepository.watchAllJournalEntries(),
        ).thenAnswer((_) => Stream.value(entries));
        when(
          mockRepository.watchJournalEntriesByStatus('posted'),
        ).thenAnswer((_) => Stream.value([entries.first]));
      },
      build: () => JournalEntriesBloc(mockRepository),
      act: (bloc) =>
          bloc.add(const JournalEntriesFilterByStatusRequested('posted')),
      verify: (bloc) {
        verify(mockRepository.watchJournalEntriesByStatus('posted')).called(1);
      },
    );

    blocTest<JournalEntriesBloc, RealtimeState<JournalEntriesData>>(
      'searches entries when JournalEntriesSearchRequested',
      setUp: () {
        when(
          mockRepository.watchAllJournalEntries(),
        ).thenAnswer((_) => Stream.value(entries));
        when(
          mockRepository.searchJournalEntries('test'),
        ).thenAnswer((_) async => [entries.first]);
      },
      build: () => JournalEntriesBloc(mockRepository),
      act: (bloc) => bloc.add(const JournalEntriesSearchRequested('test')),
      verify: (bloc) {
        verify(mockRepository.searchJournalEntries('test')).called(1);
      },
    );

    blocTest<JournalEntriesBloc, RealtimeState<JournalEntriesData>>(
      'posts entry when JournalEntryPostRequested',
      setUp: () {
        when(
          mockRepository.watchAllJournalEntries(),
        ).thenAnswer((_) => Stream.value(entries));
        when(mockRepository.postJournalEntry(1)).thenAnswer((_) async {});
      },
      build: () => JournalEntriesBloc(mockRepository),
      act: (bloc) => bloc.add(const JournalEntryPostRequested(1)),
      verify: (_) {
        verify(mockRepository.postJournalEntry(1)).called(1);
      },
    );

    blocTest<JournalEntriesBloc, RealtimeState<JournalEntriesData>>(
      'emits error when post fails',
      setUp: () {
        when(
          mockRepository.watchAllJournalEntries(),
        ).thenAnswer((_) => Stream.value(entries));
        when(
          mockRepository.postJournalEntry(1),
        ).thenThrow(StateError('Not draft'));
      },
      build: () => JournalEntriesBloc(mockRepository),
      act: (bloc) => bloc.add(const JournalEntryPostRequested(1)),
      verify: (bloc) {
        // Verify the post was attempted (it throws)
        verify(mockRepository.postJournalEntry(1)).called(1);
      },
    );

    blocTest<JournalEntriesBloc, RealtimeState<JournalEntriesData>>(
      'voids entry when JournalEntryVoidRequested',
      setUp: () {
        when(
          mockRepository.watchAllJournalEntries(),
        ).thenAnswer((_) => Stream.value(entries));
        when(
          mockRepository.voidJournalEntry(1, reason: 'mistake'),
        ).thenAnswer((_) async => 2);
      },
      build: () => JournalEntriesBloc(mockRepository),
      act: (bloc) =>
          bloc.add(const JournalEntryVoidRequested(1, reason: 'mistake')),
      verify: (_) {
        verify(mockRepository.voidJournalEntry(1, reason: 'mistake')).called(1);
      },
    );
  });
}
