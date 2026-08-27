import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/services/party_transaction_localizer.dart';

String _resolve(String key, List<String> args) => '$key[${args.join('|')}]';

void main() {
  test('localizes every void and payment reversal transaction type', () {
    expect(
      localizedPartyTransactionType('sale_void', resolver: _resolve),
      'reports.txn_type_sale_void[]',
    );
    expect(
      localizedPartyTransactionType('purchase_void', resolver: _resolve),
      'reports.txn_type_purchase_void[]',
    );
    expect(
      localizedPartyTransactionType('payment_reversal', resolver: _resolve),
      'reports.txn_type_payment_reversal[]',
    );
  });

  test(
    'localizes legacy sale and payment descriptions while preserving IDs',
    () {
      expect(
        localizedPartyTransactionDescription(
          'Sale SI-202608-000005',
          resolver: _resolve,
        ),
        'reports.txn_desc_sale[SI-202608-000005]',
      );
      expect(
        localizedPartyTransactionDescription(
          'Payment for INV-202608-0004',
          resolver: _resolve,
        ),
        'reports.txn_desc_payment[INV-202608-0004]',
      );
      expect(
        localizedPartyTransactionDescription(
          'Reversed payments for voided sale SI-202608-000005',
          resolver: _resolve,
        ),
        'reports.txn_desc_reversed_payments_voided_sale[SI-202608-000005]',
      );
    },
  );

  test('localizes linked and adjustment returns including payment method', () {
    expect(
      localizedPartyTransactionDescription(
        'Sale return SR-202608-000003 (cash)',
        resolver: _resolve,
      ),
      'reports.txn_desc_sale_return_method[SR-202608-000003|reports.txn_method_cash[]]',
    );
    expect(
      localizedPartyTransactionDescription(
        'Adjustment sale return SRS-202608-0004 (credit)',
        resolver: _resolve,
      ),
      'reports.txn_desc_sale_adjustment_return[SRS-202608-0004|reports.txn_method_credit[]]',
    );
    expect(
      localizedPartyTransactionDescription(
        'Voided Purchase Adjustment Return PRS-202608-0002',
        resolver: _resolve,
      ),
      'reports.txn_desc_voided_purchase_adjustment_return[PRS-202608-0002]',
    );
  });

  test('preserves unknown and user-entered descriptions', () {
    expect(
      localizedPartyTransactionDescription('Customer note', resolver: _resolve),
      'Customer note',
    );
  });
}
