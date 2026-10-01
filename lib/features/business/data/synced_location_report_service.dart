import 'company_branch_monitor_service.dart';

enum SyncedReportScopeKind { location, branch, company }

/// Explicit reporting boundary for the central read-only projection.
///
/// A location is one sales floor or warehouse, a branch includes all its
/// locations, and company includes every branch. This prevents a location
/// report from silently becoming an organization total.
class SyncedReportScope {
  const SyncedReportScope._({
    required this.kind,
    this.branchId,
    this.warehouseId,
  });

  const SyncedReportScope.location({
    required String branchId,
    required String warehouseId,
  }) : this._(
         kind: SyncedReportScopeKind.location,
         branchId: branchId,
         warehouseId: warehouseId,
       );

  const SyncedReportScope.branch(String branchId)
    : this._(kind: SyncedReportScopeKind.branch, branchId: branchId);

  const SyncedReportScope.company()
    : this._(kind: SyncedReportScopeKind.company);

  final SyncedReportScopeKind kind;
  final String? branchId;
  final String? warehouseId;

  bool matchesLocation(String candidateBranchId, String candidateWarehouseId) {
    return switch (kind) {
      SyncedReportScopeKind.location =>
        candidateBranchId == branchId && candidateWarehouseId == warehouseId,
      SyncedReportScopeKind.branch => candidateBranchId == branchId,
      SyncedReportScopeKind.company => true,
    };
  }
}

class SyncedLocationReportRow {
  const SyncedLocationReportRow({
    required this.label,
    required this.currencyCode,
    this.subtitle = '',
    this.quantity = 0,
    this.amountMinor = 0,
    this.discountMinor = 0,
    this.taxMinor = 0,
    this.costMinor = 0,
    this.documentCount = 0,
    this.documents = const [],
  });

  final String label;
  final String subtitle;
  final String currencyCode;
  final double quantity;
  final int amountMinor;
  final int discountMinor;
  final int taxMinor;
  final int costMinor;
  final int documentCount;
  final List<CompanyDocumentSnapshot> documents;

  int get profitMinor => amountMinor - costMinor;
}

class SyncedLocationReportData {
  const SyncedLocationReportData({
    required this.reportKey,
    required this.branchId,
    required this.warehouseId,
    required this.from,
    required this.toExclusive,
    required this.generatedAt,
    required this.rows,
    required this.documentCount,
    required this.hasLegacyGaps,
    required this.scope,
    this.grossTotalsByCurrency = const {},
    this.returnTotalsByCurrency = const {},
    this.grossDocumentCount = 0,
    this.returnDocumentCount = 0,
  });

  final String reportKey;
  final String branchId;
  final String warehouseId;
  final DateTime from;
  final DateTime toExclusive;
  final DateTime generatedAt;
  final List<SyncedLocationReportRow> rows;
  final int documentCount;
  final bool hasLegacyGaps;
  final SyncedReportScope scope;
  final Map<String, int> grossTotalsByCurrency;
  final Map<String, int> returnTotalsByCurrency;
  final int grossDocumentCount;
  final int returnDocumentCount;

  bool get hasFinancialFlowBreakdown =>
      grossTotalsByCurrency.isNotEmpty || returnTotalsByCurrency.isNotEmpty;

  Map<String, int> get netTotalsByCurrency {
    final currencies = <String>{
      ...grossTotalsByCurrency.keys,
      ...returnTotalsByCurrency.keys,
    };
    return {
      for (final currency in currencies)
        currency:
            (grossTotalsByCurrency[currency] ?? 0) -
            (returnTotalsByCurrency[currency] ?? 0),
    };
  }

  Map<String, int> get totalsByCurrency => _sum((row) => row.amountMinor);
  Map<String, int> get profitByCurrency => _sum((row) => row.profitMinor);

  Map<String, int> _sum(int Function(SyncedLocationReportRow row) value) {
    final result = <String, int>{};
    for (final row in rows) {
      result.update(
        row.currencyCode,
        (current) => current + value(row),
        ifAbsent: () => value(row),
      );
    }
    return result;
  }
}

/// Read-only operational reports over immutable branch synchronization events.
///
/// The coordinator never imports a remote journal or mutates remote stock.
/// LAN and the future online transport feed this same projection.
class SyncedLocationReportService {
  const SyncedLocationReportService(this.monitor);

  final CompanyBranchMonitorService monitor;

  Future<SyncedLocationReportData> load({
    required String reportKey,
    String? branchId,
    String? warehouseId,
    SyncedReportScope? scope,
    required DateTime from,
    required DateTime toExclusive,
  }) async {
    final resolvedScope =
        scope ??
        SyncedReportScope.location(
          branchId: branchId ?? (throw ArgumentError.notNull('branchId')),
          warehouseId:
              warehouseId ?? (throw ArgumentError.notNull('warehouseId')),
        );
    final snapshot = await monitor.load();
    final balance = _balance(reportKey);
    final documentFrom = balance ? DateTime.utc(2000) : from;
    final scopedDocuments = snapshot.documents
        .where(
          (document) =>
              resolvedScope.matchesLocation(
                document.branchId,
                document.warehouseId,
              ) &&
              !document.documentDate.isBefore(documentFrom) &&
              document.documentDate.isBefore(toExclusive),
        )
        .toList(growable: false);
    final selected = scopedDocuments
        .where(
          (document) =>
              _acceptDocument(reportKey, document) &&
              _paymentMatches(reportKey, document.paymentMethod),
        )
        .toList(growable: false);
    final financialFlow = _financialFlow(reportKey, scopedDocuments);

    final scopedMovements = snapshot.inventoryMovements
        .where(
          (movement) =>
              resolvedScope.matchesLocation(
                movement.branchId,
                movement.warehouseId,
              ) &&
              !movement.occurredAt.isBefore(
                balance ? DateTime.utc(2000) : from,
              ) &&
              movement.occurredAt.isBefore(toExclusive),
        )
        .toList(growable: false);

    final rows = _movement(reportKey)
        ? _movementRows(reportKey, selected, scopedMovements)
        : _documentRows(reportKey)
        ? _byDocument(reportKey, selected)
        : _grouped(reportKey, selected);
    rows.removeWhere(
      (row) =>
          row.quantity == 0 &&
          row.amountMinor == 0 &&
          row.discountMinor == 0 &&
          row.taxMinor == 0 &&
          row.costMinor == 0,
    );
    rows.sort((left, right) {
      final amount = right.amountMinor.abs().compareTo(left.amountMinor.abs());
      return amount != 0 ? amount : left.label.compareTo(right.label);
    });

    final freshness = <DateTime>[
      for (final document in snapshot.documents)
        if (resolvedScope.matchesLocation(
          document.branchId,
          document.warehouseId,
        ))
          document.occurredAt,
      for (final movement in snapshot.inventoryMovements)
        if (resolvedScope.matchesLocation(
          movement.branchId,
          movement.warehouseId,
        ))
          movement.occurredAt,
    ]..sort();

    return SyncedLocationReportData(
      reportKey: reportKey,
      branchId: resolvedScope.branchId ?? '',
      warehouseId: resolvedScope.warehouseId ?? '',
      from: from,
      toExclusive: toExclusive,
      generatedAt: freshness.isEmpty ? snapshot.generatedAt : freshness.last,
      rows: List.unmodifiable(rows),
      documentCount: selected.length,
      hasLegacyGaps: selected.any(
        (document) =>
            !document.hasFinancialBreakdown ||
            (document.itemCount > 0 && document.lines.isEmpty) ||
            (_commission(reportKey) && !document.commissionDataKnown) ||
            (_movement(reportKey) &&
                document.lines.any(
                  (line) => !line.inventoryClassificationKnown,
                )),
      ),
      scope: resolvedScope,
      grossTotalsByCurrency: financialFlow.grossTotals,
      returnTotalsByCurrency: financialFlow.returnTotals,
      grossDocumentCount: financialFlow.grossCount,
      returnDocumentCount: financialFlow.returnCount,
    );
  }

  static ({
    Map<String, int> grossTotals,
    Map<String, int> returnTotals,
    int grossCount,
    int returnCount,
  })
  _financialFlow(String key, List<CompanyDocumentSnapshot> documents) {
    final purchaseFlow =
        _purchase(key) &&
        !_cancelled(key) &&
        !_purchaseReturn(key) &&
        !key.contains('purchase_orders');
    final salesFlow =
        (_sales(key) || _salesTax(key)) &&
        !_cancelled(key) &&
        !_saleReturn(key) &&
        !_profit(key) &&
        !_discount(key) &&
        !_commission(key);
    if (!purchaseFlow && !salesFlow) {
      return (
        grossTotals: const <String, int>{},
        returnTotals: const <String, int>{},
        grossCount: 0,
        returnCount: 0,
      );
    }

    final grossTotals = <String, int>{};
    final returnTotals = <String, int>{};
    var grossCount = 0;
    var returnCount = 0;
    for (final document in documents) {
      if (document.isVoided || !_paymentMatches(key, document.paymentMethod)) {
        continue;
      }
      final gross = purchaseFlow
          ? document.kind == CompanyDocumentKind.purchase
          : document.kind == CompanyDocumentKind.sale;
      final returned = purchaseFlow
          ? document.kind == CompanyDocumentKind.purchaseReturn ||
                document.kind == CompanyDocumentKind.purchaseAdjustmentReturn
          : document.kind == CompanyDocumentKind.saleReturn ||
                document.kind == CompanyDocumentKind.saleAdjustmentReturn;
      if (!gross && !returned) continue;
      final amount = _tax(key) ? document.taxMinor : document.totalMinor;
      final target = gross ? grossTotals : returnTotals;
      target.update(
        document.currencyCode,
        (current) => current + amount,
        ifAbsent: () => amount,
      );
      if (gross) {
        grossCount++;
      } else {
        returnCount++;
      }
    }
    return (
      grossTotals: Map.unmodifiable(grossTotals),
      returnTotals: Map.unmodifiable(returnTotals),
      grossCount: grossCount,
      returnCount: returnCount,
    );
  }

  static bool _acceptDocument(String key, CompanyDocumentSnapshot document) {
    if (_cancelled(key)) {
      if (!document.isVoided) return false;
      return key.contains('purchases')
          ? document.kind == CompanyDocumentKind.purchase
          : document.kind == CompanyDocumentKind.sale;
    }
    if (document.isVoided) return false;
    if (_purchaseTax(key)) {
      return document.kind == CompanyDocumentKind.purchase ||
          document.kind == CompanyDocumentKind.purchaseReturn ||
          document.kind == CompanyDocumentKind.purchaseAdjustmentReturn;
    }
    if (_purchaseReturn(key)) {
      return document.kind == CompanyDocumentKind.purchaseReturn ||
          document.kind == CompanyDocumentKind.purchaseAdjustmentReturn;
    }
    if (_saleReturn(key)) {
      return document.kind == CompanyDocumentKind.saleReturn ||
          document.kind == CompanyDocumentKind.saleAdjustmentReturn;
    }
    if (_purchase(key)) return document.kind == CompanyDocumentKind.purchase;
    if (_sales(key) || _salesTax(key) || _profit(key) || _discount(key)) {
      if (!_salesRowsNetReturns(key)) {
        return document.kind == CompanyDocumentKind.sale;
      }
      return document.kind == CompanyDocumentKind.sale ||
          document.kind == CompanyDocumentKind.saleReturn ||
          document.kind == CompanyDocumentKind.saleAdjustmentReturn;
    }
    if (_movement(key)) {
      return document.kind == CompanyDocumentKind.sale ||
          document.kind == CompanyDocumentKind.purchase ||
          document.kind == CompanyDocumentKind.saleReturn ||
          document.kind == CompanyDocumentKind.saleAdjustmentReturn ||
          document.kind == CompanyDocumentKind.purchaseReturn ||
          document.kind == CompanyDocumentKind.purchaseAdjustmentReturn;
    }
    return document.kind == CompanyDocumentKind.sale ||
        document.kind == CompanyDocumentKind.purchase;
  }

  static bool _documentRows(String key) =>
      !_productRows(key) &&
      (key.contains('invoices') ||
          key.contains('purchases_report') ||
          key.contains('cash_purchases') ||
          key.contains('credit_purchases') ||
          key.contains('card_purchases') ||
          key.contains('cheque_purchases') ||
          key == 'reports.purchases_excel' ||
          key.contains('sales_by_period') ||
          key.contains('cash_sales') ||
          key.contains('credit_sales') ||
          key.contains('card_sales') ||
          key.contains('cheque_sales') ||
          key.contains('all_sales') ||
          key == 'reports.sales_excel' ||
          key == 'reports.sales_tax_report' ||
          key == 'reports.purchase_tax_report' ||
          key.contains('returns_report') ||
          key.contains('customer_returns') ||
          _cancelled(key) ||
          key.contains('purchase_orders'));

  static bool _productRows(String key) =>
      key.contains('excel_products') ||
      key.contains('by_product') ||
      key.contains('by_category') ||
      key.contains('by_supplier') ||
      key.contains('by_customer');

  static List<SyncedLocationReportRow> _byDocument(
    String key,
    List<CompanyDocumentSnapshot> documents,
  ) {
    final rows = <SyncedLocationReportRow>[];
    for (final document in documents) {
      final sign = _financialSign(document);
      final quantity = document.lines.fold<double>(
        0,
        (sum, line) => sum + line.quantityScaled / line.quantityScale,
      );
      final cost = document.lines.fold<int>(
        0,
        (sum, line) => sum + line.inventoryValueMinor,
      );
      rows.add(
        SyncedLocationReportRow(
          label: document.number,
          subtitle: [
            if (document.partyName?.trim().isNotEmpty == true)
              document.partyName!,
            document.documentDate.toLocal().toIso8601String().split('T').first,
          ].join(' · '),
          currencyCode: document.currencyCode,
          quantity: quantity * _inventorySign(document),
          amountMinor:
              (_tax(key) ? document.taxMinor : document.totalMinor) * sign,
          discountMinor: document.discountMinor * sign,
          taxMinor: document.taxMinor * sign,
          costMinor: cost * sign,
          documentCount: 1,
          documents: [document],
        ),
      );
    }
    return rows;
  }

  static List<SyncedLocationReportRow> _grouped(
    String key,
    List<CompanyDocumentSnapshot> documents,
  ) {
    final values = <String, _MutableReportRow>{};
    for (final document in documents) {
      final financialSign = _financialSign(document);
      if (_commission(key)) {
        _add(
          values,
          label: document.operatorLabel ?? '',
          currency: document.currencyCode,
          quantity: document.commissionMinor == 0 ? 0 : 1,
          amount: document.commissionMinor,
          document: document,
        );
        continue;
      }
      if (document.lines.isEmpty) {
        _add(
          values,
          label: _groupLabel(key, document, null),
          currency: document.currencyCode,
          amount: document.totalMinor * financialSign,
          discount: document.discountMinor * financialSign,
          tax: document.taxMinor * financialSign,
          document: document,
        );
        continue;
      }
      for (final line in document.lines) {
        if (_supplierFinancial(key) && line.supplierAllocations.isNotEmpty) {
          _addSupplierParts(
            values,
            document: document,
            line: line,
            financialSign: financialSign,
          );
          continue;
        }
        _add(
          values,
          label: _groupLabel(key, document, line),
          currency: document.currencyCode,
          quantity: (line.quantityScaled / line.quantityScale) * financialSign,
          amount: _tax(key)
              ? line.taxMinor * financialSign
              : _discount(key)
              ? line.discountMinor * financialSign
              : line.totalMinor * financialSign,
          discount: line.discountMinor * financialSign,
          tax: line.taxMinor * financialSign,
          cost: line.inventoryValueMinor * financialSign,
          document: document,
        );
      }
    }
    return _freeze(values);
  }

  static List<SyncedLocationReportRow> _movementRows(
    String key,
    List<CompanyDocumentSnapshot> documents,
    List<CompanyInventoryMovementSnapshot> movements,
  ) {
    final values = <String, _MutableReportRow>{};
    for (final document in documents) {
      final sign = _inventorySign(document);
      if (sign == 0) continue;
      for (final line in document.lines) {
        final stockQuantity =
            line.inventoryQuantityScaled ?? line.quantityScaled;
        if (stockQuantity == 0) continue;
        if (_supplierStock(key) && line.supplierAllocations.isNotEmpty) {
          final weights = [
            for (final allocation in line.supplierAllocations)
              allocation.quantityScaled.abs(),
          ];
          final quantities = _allocate(stockQuantity.abs(), weights);
          final valuesBySource = _allocate(
            line.inventoryValueMinor.abs(),
            weights,
          );
          for (var index = 0; index < weights.length; index++) {
            _add(
              values,
              label: line.supplierAllocations[index].name,
              currency: document.currencyCode,
              quantity: (quantities[index] / line.quantityScale) * sign,
              amount: valuesBySource[index] * sign,
              cost: valuesBySource[index] * sign,
              document: document,
            );
          }
          continue;
        }
        _add(
          values,
          label: _groupLabel(key, document, line),
          currency: document.currencyCode,
          quantity: (stockQuantity / line.quantityScale) * sign,
          amount: line.inventoryValueMinor * sign,
          cost: line.inventoryValueMinor * sign,
          document: document,
        );
      }
    }
    for (final movement in movements) {
      final label = _movementLabel(key, movement);
      _add(
        values,
        label: label,
        currency: movement.currencyCode,
        quantity: movement.quantityScaled / movement.quantityScale,
        amount: movement.valueMinor,
        cost: movement.valueMinor,
      );
    }
    return _freeze(values);
  }

  static void _addSupplierParts(
    Map<String, _MutableReportRow> values, {
    required CompanyDocumentSnapshot document,
    required CompanyDocumentLineSnapshot line,
    required int financialSign,
  }) {
    final weights = [
      for (final allocation in line.supplierAllocations)
        allocation.quantityScaled.abs(),
    ];
    final quantities = _allocate(line.quantityScaled.abs(), weights);
    final totals = _allocate(line.totalMinor.abs(), weights);
    final discounts = _allocate(line.discountMinor.abs(), weights);
    final taxes = _allocate(line.taxMinor.abs(), weights);
    final costs = _allocate(line.inventoryValueMinor.abs(), weights);
    for (var index = 0; index < weights.length; index++) {
      _add(
        values,
        label: line.supplierAllocations[index].name,
        currency: document.currencyCode,
        quantity: (quantities[index] / line.quantityScale) * financialSign,
        amount: totals[index] * financialSign,
        discount: discounts[index] * financialSign,
        tax: taxes[index] * financialSign,
        cost: costs[index] * financialSign,
        document: document,
      );
    }
  }

  static List<int> _allocate(int total, List<int> weights) {
    if (weights.isEmpty) return const [];
    final sum = weights.fold<int>(0, (value, weight) => value + weight);
    if (sum <= 0) return List<int>.filled(weights.length, 0);
    final result = <int>[];
    var assigned = 0;
    for (var index = 0; index < weights.length; index++) {
      final value = index == weights.length - 1
          ? total - assigned
          : (BigInt.from(total) *
                    BigInt.from(weights[index]) ~/
                    BigInt.from(sum))
                .toInt();
      result.add(value);
      assigned += value;
    }
    return result;
  }

  static void _add(
    Map<String, _MutableReportRow> values, {
    required String label,
    required String currency,
    CompanyDocumentSnapshot? document,
    double quantity = 0,
    int amount = 0,
    int discount = 0,
    int tax = 0,
    int cost = 0,
  }) {
    final groupKey = '$label\u0000$currency';
    final row = values.putIfAbsent(
      groupKey,
      () => _MutableReportRow(label, currency),
    );
    row.quantity += quantity;
    row.amount += amount;
    row.discount += discount;
    row.tax += tax;
    row.cost += cost;
    if (document != null) {
      row.documents['${document.sourceDatabaseId}:${document.documentId}'] =
          document;
    }
  }

  static List<SyncedLocationReportRow> _freeze(
    Map<String, _MutableReportRow> values,
  ) => [
    for (final row in values.values)
      SyncedLocationReportRow(
        label: row.label,
        currencyCode: row.currency,
        quantity: row.quantity,
        amountMinor: row.amount,
        discountMinor: row.discount,
        taxMinor: row.tax,
        costMinor: row.cost,
        documentCount: row.documents.length,
        documents: List.unmodifiable(row.documents.values),
      ),
  ];

  static String _groupLabel(
    String key,
    CompanyDocumentSnapshot document,
    CompanyDocumentLineSnapshot? line,
  ) {
    if (key.contains('supplier')) {
      if (document.kind == CompanyDocumentKind.purchase ||
          document.kind == CompanyDocumentKind.purchaseReturn ||
          document.kind == CompanyDocumentKind.purchaseAdjustmentReturn) {
        return document.partyName ?? document.partyGlobalId ?? '';
      }
      if (line != null && line.supplierNames.isNotEmpty) {
        return line.supplierNames.join(' + ');
      }
      return '';
    }
    if (key.contains('customer')) {
      return document.partyName ?? document.partyGlobalId ?? '';
    }
    if (key.contains('commission')) return document.operatorLabel ?? '';
    if (key.contains('category')) return line?.categoryName ?? '';
    if (key.contains('variant')) {
      return line?.variantName ?? line?.productName ?? '';
    }
    if (key.contains('invoice')) return document.number;
    if (key.contains('overall')) return key;
    return line?.productName ?? document.number;
  }

  static String _movementLabel(
    String key,
    CompanyInventoryMovementSnapshot movement,
  ) {
    if (_supplierStock(key)) {
      return movement.supplierNames.isEmpty
          ? ''
          : movement.supplierNames.join(' + ');
    }
    if (key.contains('category')) return movement.categoryName ?? '';
    if (key.contains('variant')) {
      return movement.variantName ?? movement.productName;
    }
    return movement.productName;
  }

  static int _financialSign(CompanyDocumentSnapshot document) =>
      switch (document.kind) {
        CompanyDocumentKind.sale || CompanyDocumentKind.purchase => 1,
        _ => -1,
      };

  static int _inventorySign(CompanyDocumentSnapshot document) =>
      switch (document.kind) {
        CompanyDocumentKind.purchase ||
        CompanyDocumentKind.saleReturn ||
        CompanyDocumentKind.saleAdjustmentReturn => 1,
        CompanyDocumentKind.sale ||
        CompanyDocumentKind.purchaseReturn ||
        CompanyDocumentKind.purchaseAdjustmentReturn => -1,
      };

  static bool _paymentMatches(String key, String? method) {
    if (key.contains('purchase_orders')) return method == 'purchaseOrder';
    if (method == 'purchaseOrder') return false;
    if (key.contains('cash_')) return method == 'cash';
    if (key.contains('credit_')) return method == 'credit';
    if (key.contains('card_')) return method == 'card';
    if (key.contains('cheque_')) return method == 'cheque';
    return true;
  }

  static bool _sales(String key) =>
      key.contains('sales') ||
      key.contains('customer_analysis') ||
      key.contains('customer_invoices') ||
      key.contains('top_customers') ||
      key.contains('commission');

  static bool _salesRowsNetReturns(String key) =>
      _profit(key) ||
      _discount(key) ||
      _commission(key) ||
      _salesTax(key) ||
      key == 'reports.sales_by_supplier' ||
      key == 'reports.customer_analysis' ||
      key == 'reports.customer_sales' ||
      key == 'reports.sales_by_product' ||
      key == 'reports.sales_by_category' ||
      key == 'reports.sales_by_customer' ||
      key == 'reports.top_customers';

  static bool _purchase(String key) =>
      key.contains('purchase') || key.contains('supplier_invoices');

  static bool _purchaseTax(String key) => key == 'reports.purchase_tax_report';
  static bool _salesTax(String key) =>
      key == 'reports.sales_tax_report' ||
      key == 'reports.tax_by_product' ||
      key == 'reports.tax_by_customer';

  static bool _saleReturn(String key) => key.contains('customer_returns');
  static bool _purchaseReturn(String key) =>
      key.contains('supplier_returns_report');
  static bool _profit(String key) => key.contains('profit');
  static bool _tax(String key) => key.contains('tax');
  static bool _discount(String key) => key.contains('discount');
  static bool _commission(String key) => key.contains('commission');
  static bool _cancelled(String key) => key.contains('cancelled');
  static bool _supplierFinancial(String key) =>
      key == 'reports.sales_by_supplier';
  static bool _supplierStock(String key) => key == 'reports.supplier_stocktake';
  static bool _balance(String key) =>
      key == 'reports.inventory_reports' || _supplierStock(key);
  static bool _movement(String key) =>
      key.contains('movement') ||
      key.contains('inventory_reports') ||
      key.contains('stocktake');
}

class _MutableReportRow {
  _MutableReportRow(this.label, this.currency);

  final String label;
  final String currency;
  double quantity = 0;
  int amount = 0;
  int discount = 0;
  int tax = 0;
  int cost = 0;
  final Map<String, CompanyDocumentSnapshot> documents = {};
}
