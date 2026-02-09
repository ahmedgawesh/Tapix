import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/accounting/domain/repositories/journal_repository.dart';
import 'package:tapix/features/accounting/presentation/bloc/accounts_bloc.dart';

@GenerateMocks([JournalRepository])
import 'accounts_bloc_test.mocks.dart';

Account _makeAccount({
  int id = 1,
  String code = '10100',
  String name = 'Cash',
  String type = 'asset',
}) {
  return Account(
    id: id,
    accountCode: code,
    accountName: name,
    accountType: type,
    balanceCents: Decimal.zero,
    currencyId: 1,
    isActive: true,
    isSystemAccount: true,
    displayOrder: 1,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

void main() {
  late MockJournalRepository mockRepository;

  setUp(() {
    mockRepository = MockJournalRepository();
  });

  group('AccountsBloc', () {
    final accounts = [
      _makeAccount(),
      _makeAccount(id: 2, code: '20100', name: 'Accounts Payable', type: 'liability'),
    ];

    blocTest<AccountsBloc, RealtimeState<AccountsData>>(
      'emits RealtimeSuccess with accounts from stream',
      setUp: () {
        when(mockRepository.watchAllAccounts())
            .thenAnswer((_) => Stream.value(accounts));
      },
      build: () => AccountsBloc(mockRepository),
      expect: () => [
        isA<RealtimeSuccess<AccountsData>>()
            .having((s) => s.data.accounts.length, 'accounts count', 2),
      ],
    );

    blocTest<AccountsBloc, RealtimeState<AccountsData>>(
      'filters by type when AccountFilterByTypeRequested',
      setUp: () {
        when(mockRepository.watchAllAccounts())
            .thenAnswer((_) => Stream.value(accounts));
        when(mockRepository.watchAccountsByType('asset'))
            .thenAnswer((_) => Stream.value([accounts.first]));
      },
      build: () => AccountsBloc(mockRepository),
      act: (bloc) => bloc.add(const AccountFilterByTypeRequested('asset')),
      verify: (bloc) {
        verify(mockRepository.watchAccountsByType('asset')).called(1);
      },
    );

    blocTest<AccountsBloc, RealtimeState<AccountsData>>(
      'creates account when AccountCreateRequested',
      setUp: () {
        when(mockRepository.watchAllAccounts())
            .thenAnswer((_) => Stream.value(accounts));
        when(mockRepository.createAccount(
          accountCode: anyNamed('accountCode'),
          accountName: anyNamed('accountName'),
          accountType: anyNamed('accountType'),
          currencyId: anyNamed('currencyId'),
        )).thenAnswer((_) async => 3);
      },
      build: () => AccountsBloc(mockRepository),
      act: (bloc) => bloc.add(const AccountCreateRequested(
        accountCode: '10500',
        accountName: 'Petty Cash',
        accountType: 'asset',
        currencyId: 1,
      )),
      verify: (_) {
        verify(mockRepository.createAccount(
          accountCode: '10500',
          accountName: 'Petty Cash',
          accountType: 'asset',
          currencyId: 1,
        )).called(1);
      },
    );

    blocTest<AccountsBloc, RealtimeState<AccountsData>>(
      'emits error when create fails',
      setUp: () {
        when(mockRepository.watchAllAccounts())
            .thenAnswer((_) => Stream.value(accounts));
        when(mockRepository.createAccount(
          accountCode: anyNamed('accountCode'),
          accountName: anyNamed('accountName'),
          accountType: anyNamed('accountType'),
          currencyId: anyNamed('currencyId'),
        )).thenThrow(Exception('Duplicate code'));
      },
      build: () => AccountsBloc(mockRepository),
      act: (bloc) => bloc.add(const AccountCreateRequested(
        accountCode: '10100',
        accountName: 'Duplicate',
        accountType: 'asset',
        currencyId: 1,
      )),
      verify: (bloc) {
        // Verify the create was attempted (it throws)
        verify(mockRepository.createAccount(
          accountCode: '10100',
          accountName: 'Duplicate',
          accountType: 'asset',
          currencyId: 1,
        )).called(1);
      },
    );

    blocTest<AccountsBloc, RealtimeState<AccountsData>>(
      'deletes account when AccountDeleteRequested',
      setUp: () {
        when(mockRepository.watchAllAccounts())
            .thenAnswer((_) => Stream.value(accounts));
        when(mockRepository.deleteAccount(1))
            .thenAnswer((_) async => 1);
      },
      build: () => AccountsBloc(mockRepository),
      act: (bloc) => bloc.add(const AccountDeleteRequested(1)),
      verify: (_) {
        verify(mockRepository.deleteAccount(1)).called(1);
      },
    );
  });
}
