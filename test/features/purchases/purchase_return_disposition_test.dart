import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/returns/purchase_return_disposition.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_return_form_bloc.dart';

class _UnusedRepository extends Fake implements PurchaseRepository {}

void main() {
  test('replacement selects supplier credit and clears cheque date', () async {
    final bloc = PurchaseReturnFormBloc(_UnusedRepository());
    addTearDown(bloc.close);
    final cheque = bloc.stream.firstWhere((s) => s.refundMethod == 'cheque');
    bloc.add(const ReturnRefundMethodChanged('cheque'));
    await cheque;
    final dated = bloc.stream.firstWhere((s) => s.dueDate != null);
    bloc.add(PurchaseReturnDueDateChanged(DateTime(2026, 10, 2)));
    await dated;
    final replaced = bloc.stream.firstWhere(
      (s) => s.dispositionType == 'replace',
    );
    bloc.add(const ReturnDispositionChanged('replace'));
    final state = await replaced;
    expect(state.refundMethod, 'credit');
    expect(state.dueDate, isNull);
    bloc.add(const ReturnRefundMethodChanged('cash'));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.refundMethod, 'credit');
  });

  test('replacement cannot hide immediate payments behind a credit method', () {
    expect(
      PurchaseReturnDispositionPolicy.validate(
        disposition: 'replace',
        refundMethod: 'credit',
        hasSettlementAllocations: true,
      ),
      'replacement_requires_credit',
    );
  });

  test(
    'sale consignment liability labels and purchase disposition help resolve in every locale',
    () {
      for (final locale in ['ar', 'en', 'fr']) {
        final json =
            jsonDecode(
                  File('assets/translations/$locale.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        for (final key in [
          'title',
          'help',
          'supplier',
          'company',
          'reason',
          'reason_help',
        ]) {
          expect(
            json['sales']['consignment_liability_$key'],
            isA<String>().having(
              (s) => s.trim().isNotEmpty,
              '$locale.$key',
              true,
            ),
          );
        }
        for (final disposition in PurchaseReturnDispositionPolicy.supported) {
          expect(json['purchases']['disposition_$disposition'], isNotEmpty);
          expect(
            json['purchases']['disposition_${disposition}_info'],
            isNotEmpty,
          );
        }
      }
    },
  );
}
