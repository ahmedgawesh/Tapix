import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'consignment_module_service.dart';

class ConsignmentReportRange {
  ConsignmentReportRange({required DateTime start, required DateTime end})
    : start = start.toUtc(),
      end = end.toUtc() {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('The report period end precedes its start.');
    }
  }

  final DateTime start;
  final DateTime end;
}

class ConsignmentSupplierReportRow {
  const ConsignmentSupplierReportRow({
    required this.supplierId,
    required this.supplierName,
    required this.currencyId,
    required this.currencyCode,
    required this.receivedQuantities,
    required this.convertedQuantities,
    required this.grossSoldQuantities,
    required this.linkedReturnedQuantities,
    required this.adjustmentReturnedQuantities,
    required this.supplierReturnQuantities,
    required this.lossQuantities,
    required this.damageQuantities,
    required this.netSoldQuantities,
    required this.remainingQuantities,
    required this.unavailableQuantities,
    required this.periodObligationCents,
    required this.unsettledObligationCents,
    required this.postedSettlementCents,
    required this.paidCents,
    required this.outstandingPayableCents,
  });

  final int supplierId;
  final String supplierName;
  final int currencyId;
  final String currencyCode;

  /// Flow quantities use the requested period. [remainingQuantities] is a
  /// closing balance reconstructed from immutable events through period end.
  /// Measurement dimensions are never added to each other.
  final Map<String, int> receivedQuantities;
  final Map<String, int> convertedQuantities;
  final Map<String, int> grossSoldQuantities;
  final Map<String, int> linkedReturnedQuantities;
  final Map<String, int> adjustmentReturnedQuantities;
  final Map<String, int> supplierReturnQuantities;
  final Map<String, int> lossQuantities;
  final Map<String, int> damageQuantities;
  final Map<String, int> netSoldQuantities;
  final Map<String, int> remainingQuantities;

  /// Supplier-owned customer returns that were damaged, scrapped or written
  /// off. They remain attributable custody but are excluded from sellable
  /// warehouse stock and inventory valuation.
  final Map<String, int> unavailableQuantities;

  /// Period activity. Settlement and payment reversals carry a negative sign.
  final int periodObligationCents;
  final int postedSettlementCents;
  final int paidCents;

  /// Closing balances through period end.
  final int unsettledObligationCents;
  final int outstandingPayableCents;

  Map<String, int> get returnedQuantities => _sumQuantityMaps([
    linkedReturnedQuantities,
    adjustmentReturnedQuantities,
  ]);
}

class ConsignmentDashboardSnapshot {
  const ConsignmentDashboardSnapshot({
    required this.agreements,
    required this.receipts,
    required this.custodyDocuments,
    required this.ownershipConversions,
    required this.statements,
    required this.payments,
    required this.suppliers,
    required this.currencyCodes,
    required this.operationsEnabled,
    required this.historicalManagementEnabled,
    required this.openCustodyAgreementIds,
    required this.reportRows,
  });

  final List<ConsignmentAgreement> agreements;
  final List<ConsignmentReceipt> receipts;
  final List<ConsignmentCustodyDocument> custodyDocuments;
  final List<ConsignmentOwnershipConversion> ownershipConversions;
  final List<ConsignmentSettlementStatement> statements;
  final List<ConsignmentSettlementPayment> payments;
  final Map<int, Supplier> suppliers;
  final Map<int, String> currencyCodes;
  final bool operationsEnabled;
  final bool historicalManagementEnabled;

  /// Agreements that still own an open physical quantity. Closed and
  /// superseded revisions remain eligible only for custody exit documents.
  final Set<String> openCustodyAgreementIds;
  final List<ConsignmentSupplierReportRow> reportRows;

  Map<String, int> get supplierOwnedQuantities =>
      _sumQuantityMaps(reportRows.map((row) => row.remainingQuantities));
  Map<String, int> get unsettledObligationsByCurrency =>
      _moneyByCurrency(reportRows, (row) => row.unsettledObligationCents);
  Map<String, int> get outstandingPayablesByCurrency =>
      _moneyByCurrency(reportRows, (row) => row.outstandingPayableCents);
}

class ConsignmentReportingService {
  ConsignmentReportingService(this._db, this._module);

  final AppDatabase _db;
  final ConsignmentModuleService _module;

  Future<ConsignmentDashboardSnapshot> load() => _db.transaction(() async {
    final access = await _module.requireViewAccess();
    final agreements = await _agreementsForScope(
      organizationId: access.scope.organizationId,
      branchId: access.scope.branchId,
      databaseId: access.scope.databaseId,
    );
    final agreementIds = agreements.map((row) => row.id).toList();
    final ownershipConversions = agreementIds.isEmpty
        ? <ConsignmentOwnershipConversion>[]
        : await (_db.select(_db.consignmentOwnershipConversions)
                ..where((row) => row.agreementId.isIn(agreementIds))
                ..orderBy([
                  (row) => OrderingTerm.desc(row.convertedAt),
                  (row) => OrderingTerm.desc(row.id),
                ]))
              .get();
    final conversionReceiptIds = ownershipConversions
        .map((row) => row.receiptId)
        .toSet();
    final receipts = agreementIds.isEmpty
        ? <ConsignmentReceipt>[]
        : await (_db.select(_db.consignmentReceipts)
                ..where(
                  (row) =>
                      row.agreementId.isIn(agreementIds) &
                      (conversionReceiptIds.isEmpty
                          ? const Constant(true)
                          : row.id.isNotIn(conversionReceiptIds)),
                )
                ..orderBy([
                  (row) => OrderingTerm.desc(row.receivedAt),
                  (row) => OrderingTerm.desc(row.createdAt),
                ]))
              .get();
    final custodyDocuments = agreementIds.isEmpty
        ? <ConsignmentCustodyDocument>[]
        : await (_db.select(_db.consignmentCustodyDocuments)
                ..where((row) => row.agreementId.isIn(agreementIds))
                ..orderBy([
                  (row) => OrderingTerm.desc(row.occurredAt),
                  (row) => OrderingTerm.desc(row.id),
                ]))
              .get();
    final statements = agreementIds.isEmpty
        ? <ConsignmentSettlementStatement>[]
        : await (_db.select(_db.consignmentSettlementStatements)
                ..where((row) => row.agreementId.isIn(agreementIds))
                ..orderBy([
                  (row) => OrderingTerm.desc(row.periodEnd),
                  (row) => OrderingTerm.desc(row.id),
                ]))
              .get();
    final statementIds = statements.map((row) => row.id).toList();
    final payments = statementIds.isEmpty
        ? <ConsignmentSettlementPayment>[]
        : await (_db.select(_db.consignmentSettlementPayments)
                ..where((row) => row.statementId.isIn(statementIds))
                ..orderBy([(row) => OrderingTerm.desc(row.paidAt)]))
              .get();
    final openCustodyAgreementIds = agreementIds.isEmpty
        ? <String>{}
        : (await (_db.select(_db.consignmentInventoryLayers)..where(
                    (layer) =>
                        layer.agreementId.isIn(agreementIds) &
                        layer.status.equals('open') &
                        layer.remainingQuantity.isBiggerThanValue(0),
                  ))
                  .get())
              .map((layer) => layer.agreementId)
              .toSet();
    final lookup = await _lookups(agreements);
    final operationsEnabled = await _module.operationsEnabled();
    final historicalManagementEnabled = await _module
        .historicalManagementEnabled();
    final rows = await _buildRows(
      agreements: agreements,
      suppliers: lookup.suppliers,
      currencyCodes: lookup.currencyCodes,
    );
    return ConsignmentDashboardSnapshot(
      agreements: agreements,
      receipts: receipts,
      custodyDocuments: custodyDocuments,
      ownershipConversions: ownershipConversions,
      statements: statements,
      payments: payments,
      suppliers: lookup.suppliers,
      currencyCodes: lookup.currencyCodes,
      operationsEnabled: operationsEnabled,
      historicalManagementEnabled: historicalManagementEnabled,
      openCustodyAgreementIds: openCustodyAgreementIds,
      reportRows: rows,
    );
  });

  /// Loads period flows and balances through the requested end. This stays separate
  /// from [load] so report filters never hide agreements or documents in the
  /// management sections of the hub.
  Future<List<ConsignmentSupplierReportRow>> loadReport({
    required ConsignmentReportRange range,
    int? supplierId,
  }) => _db.transaction(() async {
    final access = await _module.requireViewAccess();
    final agreements = await _agreementsForScope(
      organizationId: access.scope.organizationId,
      branchId: access.scope.branchId,
      databaseId: access.scope.databaseId,
      supplierId: supplierId,
    );
    final lookup = await _lookups(agreements);
    return _buildRows(
      agreements: agreements,
      suppliers: lookup.suppliers,
      currencyCodes: lookup.currencyCodes,
      range: range,
    );
  });

  Future<List<ConsignmentAgreement>> _agreementsForScope({
    required String organizationId,
    required String branchId,
    required String databaseId,
    int? supplierId,
  }) {
    final query = _db.select(_db.consignmentAgreements)
      ..where(
        (row) =>
            row.organizationId.equals(organizationId) &
            row.branchId.equals(branchId) &
            row.databaseId.equals(databaseId),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.createdAt),
        (row) => OrderingTerm.desc(row.revision),
      ]);
    if (supplierId != null) {
      query.where((row) => row.supplierId.equals(supplierId));
    }
    return query.get();
  }

  Future<({Map<int, Supplier> suppliers, Map<int, String> currencyCodes})>
  _lookups(List<ConsignmentAgreement> agreements) async {
    final supplierIds = agreements.map((row) => row.supplierId).toSet();
    final supplierRows = supplierIds.isEmpty
        ? <Supplier>[]
        : await (_db.select(
            _db.suppliers,
          )..where((row) => row.id.isIn(supplierIds))).get();
    final currencyIds = agreements.map((row) => row.currencyId).toSet();
    final currencyRows = currencyIds.isEmpty
        ? <Currency>[]
        : await (_db.select(
            _db.currencies,
          )..where((row) => row.id.isIn(currencyIds))).get();
    return (
      suppliers: {for (final row in supplierRows) row.id: row},
      currencyCodes: {for (final row in currencyRows) row.id: row.code},
    );
  }

  Future<List<ConsignmentSupplierReportRow>> _buildRows({
    required List<ConsignmentAgreement> agreements,
    required Map<int, Supplier> suppliers,
    required Map<int, String> currencyCodes,
    ConsignmentReportRange? range,
  }) async {
    final rows = <ConsignmentSupplierReportRow>[];
    for (final supplierId in agreements.map((row) => row.supplierId).toSet()) {
      final supplierAgreements = agreements
          .where((row) => row.supplierId == supplierId)
          .toList();
      for (final currencyId
          in supplierAgreements.map((row) => row.currencyId).toSet()) {
        final agreementIds = supplierAgreements
            .where((row) => row.currencyId == currencyId)
            .map((row) => row.id)
            .toList();
        final quantities = await _supplierQuantities(
          supplierId,
          agreementIds,
          range: range,
        );
        final money = await _supplierMoney(
          supplierId,
          agreementIds,
          range: range,
        );
        rows.add(
          ConsignmentSupplierReportRow(
            supplierId: supplierId,
            supplierName: suppliers[supplierId]?.name ?? '#$supplierId',
            currencyId: currencyId,
            currencyCode: currencyCodes[currencyId] ?? '#$currencyId',
            receivedQuantities: quantities.received,
            convertedQuantities: quantities.converted,
            grossSoldQuantities: quantities.grossSold,
            linkedReturnedQuantities: quantities.linkedReturned,
            adjustmentReturnedQuantities: _scaleQuantityMap(
              quantities.adjustmentSigned,
              -1,
            ),
            supplierReturnQuantities: quantities.supplierReturned,
            lossQuantities: quantities.loss,
            damageQuantities: quantities.damage,
            netSoldQuantities: _sumQuantityMaps([
              quantities.obligationSigned,
              quantities.adjustmentSigned,
            ]),
            remainingQuantities: quantities.remaining,
            unavailableQuantities: quantities.unavailable,
            periodObligationCents: money.periodObligation,
            unsettledObligationCents: money.closingUnsettled,
            postedSettlementCents: money.periodSettlement,
            paidCents: money.periodPaid,
            outstandingPayableCents: money.closingPayable,
          ),
        );
      }
    }
    rows.sort((a, b) {
      final supplier = a.supplierName.compareTo(b.supplierName);
      return supplier != 0
          ? supplier
          : a.currencyCode.compareTo(b.currencyCode);
    });
    return List.unmodifiable(rows);
  }

  Future<
    ({
      Map<String, int> received,
      Map<String, int> converted,
      Map<String, int> grossSold,
      Map<String, int> linkedReturned,
      Map<String, int> adjustmentSigned,
      Map<String, int> obligationSigned,
      Map<String, int> supplierReturned,
      Map<String, int> loss,
      Map<String, int> damage,
      Map<String, int> remaining,
      Map<String, int> unavailable,
    })
  >
  _supplierQuantities(
    int supplierId,
    List<String> agreementIds, {
    ConsignmentReportRange? range,
  }) async {
    if (agreementIds.isEmpty) {
      return (
        received: const <String, int>{},
        converted: const <String, int>{},
        grossSold: const <String, int>{},
        linkedReturned: const <String, int>{},
        adjustmentSigned: const <String, int>{},
        obligationSigned: const <String, int>{},
        supplierReturned: const <String, int>{},
        loss: const <String, int>{},
        damage: const <String, int>{},
        remaining: const <String, int>{},
        unavailable: const <String, int>{},
      );
    }
    final placeholders = List.filled(agreementIds.length, '?').join(',');
    final identityVariables = <Variable<Object>>[
      Variable.withInt(supplierId),
      ...agreementIds.map(Variable.withString),
    ];

    Future<Map<String, int>> grouped(
      String sql, {
      required String dateColumn,
      DateTime? start,
      DateTime? end,
    }) async {
      final rangeSql = _dateRangeSql(dateColumn, start: start, end: end);
      final rows = await _db
          .customSelect(
            sql.replaceFirst('/*DATE_RANGE*/', rangeSql),
            variables: [
              ...identityVariables,
              ..._dateVariables(start: start, end: end),
            ],
          )
          .get();
      return {
        for (final row in rows)
          row.read<String>('measurement_type'): row.read<int>('value'),
      };
    }

    final start = range?.start;
    final end = range?.end;
    final received = await grouped(
      '''SELECT p.measurement_type,
           COALESCE(SUM(CASE e.kind WHEN 'posted' THEN i.quantity ELSE -i.quantity END),0) AS value
         FROM consignment_receipt_events e
         JOIN consignment_receipts r ON r.id=e.receipt_id
         JOIN consignment_receipt_items i ON i.receipt_id=r.id
         JOIN products p ON p.id=i.product_id
         WHERE r.supplier_id=? AND r.agreement_id IN ($placeholders)
           AND NOT EXISTS(SELECT 1 FROM consignment_ownership_conversions c WHERE c.receipt_id=r.id)
           /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn:
          "(CASE WHEN e.kind='posted' THEN r.received_at ELSE e.created_at END)",
      start: start,
      end: end,
    );
    final converted = await grouped(
      '''SELECT p.measurement_type,
           COALESCE(SUM(CASE e.kind WHEN 'posted' THEN i.quantity ELSE -i.quantity END),0) AS value
         FROM consignment_receipt_events e
         JOIN consignment_receipts r ON r.id=e.receipt_id
         JOIN consignment_ownership_conversions c ON c.receipt_id=r.id
         JOIN consignment_receipt_items i ON i.receipt_id=r.id
         JOIN products p ON p.id=i.product_id
         WHERE r.supplier_id=? AND r.agreement_id IN ($placeholders)
           /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn:
          "(CASE WHEN e.kind='posted' THEN c.converted_at ELSE e.created_at END)",
      start: start,
      end: end,
    );
    final grossSold = await grouped(
      '''SELECT p.measurement_type, COALESCE(SUM(e.signed_quantity),0) AS value
         FROM consignment_obligation_events e
         JOIN consignment_sale_allocations a ON a.id=e.allocation_id
         JOIN consignment_inventory_layers l ON l.id=a.layer_id
         JOIN products p ON p.id=l.product_id
         WHERE e.supplier_id=? AND e.agreement_id IN ($placeholders)
           AND e.kind='sale_accrual' /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      start: start,
      end: end,
    );
    final linkedReturned = await grouped(
      '''SELECT p.measurement_type, COALESCE(SUM(-e.signed_quantity),0) AS value
         FROM consignment_obligation_events e
         JOIN consignment_sale_allocations a ON a.id=e.allocation_id
         JOIN consignment_inventory_layers l ON l.id=a.layer_id
         JOIN products p ON p.id=l.product_id
         WHERE e.supplier_id=? AND e.agreement_id IN ($placeholders)
           AND e.kind IN ('linked_return_reversal','return_void_reaccrual')
           /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      start: start,
      end: end,
    );
    final adjustmentSigned = await grouped(
      '''SELECT p.measurement_type, COALESCE(SUM(e.signed_quantity),0) AS value
         FROM consignment_adjustment_return_events e
         JOIN consignment_inventory_layers l ON l.id=e.layer_id
         JOIN products p ON p.id=l.product_id
         WHERE e.supplier_id=? AND e.agreement_id IN ($placeholders)
           /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      start: start,
      end: end,
    );
    final obligationSigned = await grouped(
      '''SELECT p.measurement_type, COALESCE(SUM(e.signed_quantity),0) AS value
         FROM consignment_obligation_events e
         JOIN consignment_sale_allocations a ON a.id=e.allocation_id
         JOIN consignment_inventory_layers l ON l.id=a.layer_id
         JOIN products p ON p.id=l.product_id
         WHERE e.supplier_id=? AND e.agreement_id IN ($placeholders)
           /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      start: start,
      end: end,
    );

    Future<Map<String, int>> custodyMovement(String type) => grouped(
      '''SELECT p.measurement_type,
           COALESCE(SUM(CASE e.kind WHEN 'posted' THEN i.quantity ELSE -i.quantity END),0) AS value
         FROM consignment_custody_events e
         JOIN consignment_custody_documents d ON d.id=e.document_id
         JOIN consignment_custody_items i ON i.document_id=d.id
         JOIN products p ON p.id=i.product_id
         WHERE d.supplier_id=? AND d.agreement_id IN ($placeholders)
           AND d.document_type='$type' /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      start: start,
      end: end,
    );
    final supplierReturned = await custodyMovement('supplier_return');
    final loss = await custodyMovement('loss');
    final damage = await custodyMovement('damage');

    // Closing stock is reconstructed to the report end, not calculated from
    // period purchases and sales. This preserves a correct opening balance.
    final receivedToEnd = await grouped(
      '''SELECT p.measurement_type,
           COALESCE(SUM(CASE e.kind WHEN 'posted' THEN i.quantity ELSE -i.quantity END),0) AS value
         FROM consignment_receipt_events e
         JOIN consignment_receipts r ON r.id=e.receipt_id
         JOIN consignment_receipt_items i ON i.receipt_id=r.id
         JOIN products p ON p.id=i.product_id
         WHERE r.supplier_id=? AND r.agreement_id IN ($placeholders)
           AND NOT EXISTS(SELECT 1 FROM consignment_ownership_conversions c WHERE c.receipt_id=r.id)
           /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn:
          "(CASE WHEN e.kind='posted' THEN r.received_at ELSE e.created_at END)",
      end: end,
    );
    final convertedToEnd = await grouped(
      '''SELECT p.measurement_type,
           COALESCE(SUM(CASE e.kind WHEN 'posted' THEN i.quantity ELSE -i.quantity END),0) AS value
         FROM consignment_receipt_events e
         JOIN consignment_receipts r ON r.id=e.receipt_id
         JOIN consignment_ownership_conversions c ON c.receipt_id=r.id
         JOIN consignment_receipt_items i ON i.receipt_id=r.id
         JOIN products p ON p.id=i.product_id
         WHERE r.supplier_id=? AND r.agreement_id IN ($placeholders)
           /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn:
          "(CASE WHEN e.kind='posted' THEN c.converted_at ELSE e.created_at END)",
      end: end,
    );
    final obligationToEnd = await grouped(
      '''SELECT p.measurement_type, COALESCE(SUM(e.signed_quantity),0) AS value
         FROM consignment_obligation_events e
         JOIN consignment_sale_allocations a ON a.id=e.allocation_id
         JOIN consignment_inventory_layers l ON l.id=a.layer_id
         JOIN products p ON p.id=l.product_id
         WHERE e.supplier_id=? AND e.agreement_id IN ($placeholders)
           AND e.restores_stock=1 /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      end: end,
    );
    final adjustmentToEnd = await grouped(
      '''SELECT p.measurement_type, COALESCE(SUM(e.signed_quantity),0) AS value
         FROM consignment_adjustment_return_events e
         JOIN consignment_inventory_layers l ON l.id=e.layer_id
         JOIN products p ON p.id=l.product_id
         WHERE e.supplier_id=? AND e.agreement_id IN ($placeholders)
           AND e.restores_stock=1 /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      end: end,
    );
    final custodyToEnd = await grouped(
      '''SELECT p.measurement_type,
           COALESCE(SUM(CASE e.kind WHEN 'posted' THEN i.quantity ELSE -i.quantity END),0) AS value
         FROM consignment_custody_events e
         JOIN consignment_custody_documents d ON d.id=e.document_id
         JOIN consignment_custody_items i ON i.document_id=d.id
         JOIN products p ON p.id=i.product_id
         WHERE d.supplier_id=? AND d.agreement_id IN ($placeholders)
           /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      end: end,
    );
    final linkedUnavailableToEnd = await grouped(
      '''SELECT p.measurement_type, COALESCE(SUM(-e.signed_quantity),0) AS value
         FROM consignment_obligation_events e
         JOIN consignment_sale_allocations a ON a.id=e.allocation_id
         JOIN consignment_inventory_layers l ON l.id=a.layer_id
         JOIN products p ON p.id=l.product_id
         WHERE e.supplier_id=? AND e.agreement_id IN ($placeholders)
           AND e.restores_stock=0 /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      end: end,
    );
    final adjustmentUnavailableToEnd = await grouped(
      '''SELECT p.measurement_type, COALESCE(SUM(-e.signed_quantity),0) AS value
         FROM consignment_adjustment_return_events e
         JOIN consignment_inventory_layers l ON l.id=e.layer_id
         JOIN products p ON p.id=l.product_id
         WHERE e.supplier_id=? AND e.agreement_id IN ($placeholders)
           AND e.restores_stock=0 /*DATE_RANGE*/
         GROUP BY p.measurement_type''',
      dateColumn: 'e.occurred_at',
      end: end,
    );
    final unavailable = _sumQuantityMaps([
      linkedUnavailableToEnd,
      adjustmentUnavailableToEnd,
    ]);
    final remaining = _sumQuantityMaps([
      receivedToEnd,
      convertedToEnd,
      _scaleQuantityMap(obligationToEnd, -1),
      _scaleQuantityMap(adjustmentToEnd, -1),
      _scaleQuantityMap(custodyToEnd, -1),
    ]);
    if (remaining.values.any((value) => value < 0) ||
        unavailable.values.any((value) => value < 0)) {
      throw StateError('Consignment custody ledger has a negative balance.');
    }

    return (
      received: received,
      converted: converted,
      grossSold: grossSold,
      linkedReturned: linkedReturned,
      adjustmentSigned: adjustmentSigned,
      obligationSigned: obligationSigned,
      supplierReturned: supplierReturned,
      loss: loss,
      damage: damage,
      remaining: remaining,
      unavailable: unavailable,
    );
  }

  Future<
    ({
      int periodObligation,
      int closingUnsettled,
      int periodSettlement,
      int periodPaid,
      int closingPayable,
    })
  >
  _supplierMoney(
    int supplierId,
    List<String> agreementIds, {
    ConsignmentReportRange? range,
  }) async {
    if (agreementIds.isEmpty) {
      return (
        periodObligation: 0,
        closingUnsettled: 0,
        periodSettlement: 0,
        periodPaid: 0,
        closingPayable: 0,
      );
    }
    final placeholders = List.filled(agreementIds.length, '?').join(',');
    final identities = <Variable<Object>>[
      Variable.withInt(supplierId),
      ...agreementIds.map(Variable.withString),
    ];
    final start = range?.start;
    final end = range?.end;

    Future<int> eventScalar(
      String table, {
      required DateTime? from,
      required DateTime? through,
    }) async {
      final sql = _dateRangeSql('occurred_at', start: from, end: through);
      final row = await _db
          .customSelect(
            '''SELECT COALESCE(SUM(signed_amount_cents),0) AS value
               FROM $table
               WHERE supplier_id=? AND agreement_id IN ($placeholders) $sql''',
            variables: [
              ...identities,
              ..._dateVariables(start: from, end: through),
            ],
          )
          .getSingle();
      return row.read<int>('value');
    }

    final periodObligation =
        await eventScalar(
          'consignment_obligation_events',
          from: start,
          through: end,
        ) +
        await eventScalar(
          'consignment_adjustment_return_events',
          from: start,
          through: end,
        ) +
        await eventScalar(
          'consignment_custody_events',
          from: start,
          through: end,
        );
    final obligationToEnd =
        await eventScalar(
          'consignment_obligation_events',
          from: null,
          through: end,
        ) +
        await eventScalar(
          'consignment_adjustment_return_events',
          from: null,
          through: end,
        ) +
        await eventScalar(
          'consignment_custody_events',
          from: null,
          through: end,
        );

    final statementTransitions = await _transitionTotal(
      table: 'consignment_settlement_statements',
      amountColumn: 'obligation_subtotal_cents',
      positiveDate: 'posted_at',
      negativeDate: 'voided_at',
      supplierId: supplierId,
      agreementIds: agreementIds,
      range: range,
    );
    final settledToEnd = await _activeStatementTotal(
      amountExpression: 'obligation_subtotal_cents',
      supplierId: supplierId,
      agreementIds: agreementIds,
      end: end,
    );
    final periodPaid = await _paymentTransitionTotal(
      supplierId: supplierId,
      agreementIds: agreementIds,
      range: range,
    );
    final payableToEnd = await _activeStatementTotal(
      amountExpression: 'total_cents',
      supplierId: supplierId,
      agreementIds: agreementIds,
      end: end,
    );
    final paymentsToEnd = await _activePaymentTotal(
      supplierId: supplierId,
      agreementIds: agreementIds,
      end: end,
    );

    return (
      periodObligation: periodObligation,
      closingUnsettled: obligationToEnd - settledToEnd,
      periodSettlement: statementTransitions,
      periodPaid: periodPaid,
      closingPayable: payableToEnd - paymentsToEnd,
    );
  }

  Future<int> _transitionTotal({
    required String table,
    required String amountColumn,
    required String positiveDate,
    required String negativeDate,
    required int supplierId,
    required List<String> agreementIds,
    required ConsignmentReportRange? range,
  }) async {
    final placeholders = List.filled(agreementIds.length, '?').join(',');
    final positiveRange = _dateRangeSql(
      positiveDate,
      start: range?.start,
      end: range?.end,
    );
    final negativeRange = _dateRangeSql(
      negativeDate,
      start: range?.start,
      end: range?.end,
    );
    final identity = <Variable<Object>>[
      Variable.withInt(supplierId),
      ...agreementIds.map(Variable.withString),
    ];
    final row = await _db
        .customSelect(
          '''SELECT
             COALESCE(SUM(CASE WHEN $positiveDate IS NOT NULL $positiveRange
               THEN $amountColumn ELSE 0 END),0) -
             COALESCE(SUM(CASE WHEN $positiveDate IS NOT NULL
               AND $negativeDate IS NOT NULL $negativeRange
               THEN $amountColumn ELSE 0 END),0) AS value
             FROM $table
             WHERE supplier_id=? AND agreement_id IN ($placeholders)''',
          variables: [
            ..._dateVariables(start: range?.start, end: range?.end),
            ..._dateVariables(start: range?.start, end: range?.end),
            ...identity,
          ],
        )
        .getSingle();
    return row.read<int>('value');
  }

  Future<int> _paymentTransitionTotal({
    required int supplierId,
    required List<String> agreementIds,
    required ConsignmentReportRange? range,
  }) async {
    final placeholders = List.filled(agreementIds.length, '?').join(',');
    final paidRange = _dateRangeSql(
      'p.paid_at',
      start: range?.start,
      end: range?.end,
    );
    final reversedRange = _dateRangeSql(
      'p.reversed_at',
      start: range?.start,
      end: range?.end,
    );
    final row = await _db
        .customSelect(
          '''SELECT
             COALESCE(SUM(CASE WHEN p.paid_at IS NOT NULL $paidRange
               THEN p.amount_cents ELSE 0 END),0) -
             COALESCE(SUM(CASE WHEN p.reversed_at IS NOT NULL $reversedRange
               THEN p.amount_cents ELSE 0 END),0) AS value
             FROM consignment_settlement_payments p
             JOIN consignment_settlement_statements s ON s.id=p.statement_id
             WHERE s.supplier_id=? AND s.agreement_id IN ($placeholders)''',
          variables: [
            ..._dateVariables(start: range?.start, end: range?.end),
            ..._dateVariables(start: range?.start, end: range?.end),
            Variable.withInt(supplierId),
            ...agreementIds.map(Variable.withString),
          ],
        )
        .getSingle();
    return row.read<int>('value');
  }

  Future<int> _activeStatementTotal({
    required String amountExpression,
    required int supplierId,
    required List<String> agreementIds,
    required DateTime? end,
  }) async {
    final placeholders = List.filled(agreementIds.length, '?').join(',');
    final endSql = end == null
        ? 'AND voided_at IS NULL'
        : '''AND julianday(posted_at)<=julianday(?)
             AND (voided_at IS NULL OR julianday(voided_at)>julianday(?))''';
    final row = await _db
        .customSelect(
          '''SELECT COALESCE(SUM($amountExpression),0) AS value
             FROM consignment_settlement_statements
             WHERE supplier_id=? AND agreement_id IN ($placeholders)
               AND posted_at IS NOT NULL $endSql''',
          variables: [
            Variable.withInt(supplierId),
            ...agreementIds.map(Variable.withString),
            if (end != null) ...[
              Variable.withString(end.toIso8601String()),
              Variable.withString(end.toIso8601String()),
            ],
          ],
        )
        .getSingle();
    return row.read<int>('value');
  }

  Future<int> _activePaymentTotal({
    required int supplierId,
    required List<String> agreementIds,
    required DateTime? end,
  }) async {
    final placeholders = List.filled(agreementIds.length, '?').join(',');
    final timeSql = end == null
        ? 'AND p.status=\'posted\' AND s.voided_at IS NULL'
        : '''AND julianday(p.paid_at)<=julianday(?)
             AND (p.reversed_at IS NULL OR julianday(p.reversed_at)>julianday(?))
             AND julianday(s.posted_at)<=julianday(?)
             AND (s.voided_at IS NULL OR julianday(s.voided_at)>julianday(?))''';
    final row = await _db
        .customSelect(
          '''SELECT COALESCE(SUM(p.amount_cents),0) AS value
             FROM consignment_settlement_payments p
             JOIN consignment_settlement_statements s ON s.id=p.statement_id
             WHERE s.supplier_id=? AND s.agreement_id IN ($placeholders)
               $timeSql''',
          variables: [
            Variable.withInt(supplierId),
            ...agreementIds.map(Variable.withString),
            if (end != null)
              for (var index = 0; index < 4; index++)
                Variable.withString(end.toIso8601String()),
          ],
        )
        .getSingle();
    return row.read<int>('value');
  }
}

String _dateRangeSql(
  String column, {
  required DateTime? start,
  required DateTime? end,
}) {
  final parts = <String>[];
  if (start != null) parts.add('julianday($column)>=julianday(?)');
  if (end != null) parts.add('julianday($column)<=julianday(?)');
  return parts.isEmpty ? '' : 'AND ${parts.join(' AND ')}';
}

List<Variable<Object>> _dateVariables({
  required DateTime? start,
  required DateTime? end,
}) => [
  if (start != null) Variable.withString(start.toIso8601String()),
  if (end != null) Variable.withString(end.toIso8601String()),
];

Map<String, int> _sumQuantityMaps(Iterable<Map<String, int>> values) {
  final result = <String, int>{};
  for (final value in values) {
    for (final entry in value.entries) {
      result.update(
        entry.key,
        (current) => current + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }
  result.removeWhere((_, value) => value == 0);
  return Map.unmodifiable(result);
}

Map<String, int> _scaleQuantityMap(Map<String, int> value, int factor) =>
    Map.unmodifiable(
      Map.fromEntries(
        value.entries
            .map((entry) => MapEntry(entry.key, entry.value * factor))
            .where((entry) => entry.value != 0),
      ),
    );

Map<String, int> _moneyByCurrency(
  Iterable<ConsignmentSupplierReportRow> rows,
  int Function(ConsignmentSupplierReportRow row) select,
) {
  final result = <String, int>{};
  for (final row in rows) {
    result.update(
      row.currencyCode,
      (current) => current + select(row),
      ifAbsent: () => select(row),
    );
  }
  return Map.unmodifiable(result);
}
