import 'dart:async';
import '../../../../core/services/business/warehouse_document_reader.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_operation_scope.dart';
import '../../../../core/services/business/warehouse_read_scope.dart';
import 'dart:developer' as developer;
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/cheque_confirmation_dao.dart';
import '../../../../core/database/daos/cheque_instrument_dao.dart';
import '../../../../core/database/daos/sale_dao.dart' hide SaleDashboardStats;
import '../../../../core/database/migrations/consignment_return_liability.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/payments/return_settlement_service.dart';
import '../../../../core/pricing/pricing_snapshot.dart';
import '../../../../core/promotions/promotion_engine.dart';
import '../../../../core/promotions/promotion_repository.dart';
import '../../../../core/promotions/promotion_return_policy.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/cashier_shift_service.dart';
import '../../../../core/services/cheque_source_void_service.dart';
import '../../../../core/services/commissions/commission_service.dart';
import '../../../../core/services/einvoice/einvoice_dispatch_service.dart';
import '../../../../core/services/einvoice/einvoice_document.dart';
import '../../../../core/services/free_quota_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/loyalty/loyalty_points_service.dart';
import '../../../../core/services/return_calculation_service.dart';
import '../../../../core/services/sync/offline_sync_event_store.dart';
import '../../../../core/services/sync/sale_sync_contract.dart';
import '../../../../core/services/sync/sync_entity_identity_store.dart';
import '../../../../core/services/void_impact_analyzer.dart';
import '../../../auth/data/services/session_service.dart';
import '../../../consignment/data/consignment_sale_accounting_service.dart';
import '../../../customers/domain/repositories/loyalty_repository.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';
import '../datasources/sale_local_datasource.dart';

class SaleRepositoryImpl implements SaleRepository {
  static final Object _commitEffectsKey = Object();

  Future<void> _afterCommit(Future<void> Function() effect) async {
    final pending =
        Zone.current[_commitEffectsKey] as List<Future<void> Function()>?;
    if (pending != null) {
      pending.add(effect);
    } else {
      await effect();
    }
  }

  final SaleLocalDatasource _datasource;
  final SaleDao _dao;
  final WarehouseOperationScope? warehouseScope;
  late final _reader = WarehouseDocumentReader(_dao.db, scope: warehouseScope);
  final JournalEntryService _journalService;
  final AuditLogService _audit;
  final SessionService _sessionService;
  final LoyaltyRepository _loyaltyRepository;
  // Phase 6 — commission + loyalty math live in their own services.
  // This repository is now a pure consumer; no inline arithmetic.
  final CommissionService _commissionService;
  final LoyaltyPointsService _loyaltyPointsService;

  /// Optional — e-invoice dispatcher. Never throws; any failure is logged
  /// and persisted on the `einvoice_documents` row (status=`rejected`)
  /// so the sale/return is never rolled back for an e-invoicing issue.
  /// When null (old tests) dispatch is a silent no-op.
  final EInvoiceDispatchService? _einvoiceDispatch;

  /// Phase B4 — free-tier cumulative quota guard. Optional so existing tests
  /// that construct the repository without DI keep working. When provided,
  /// `createSale` calls `guardSaleCreation()` (may throw
  /// [FreeQuotaExceededException]) and `incrementSalesCreated()` after a
  /// successful transaction.
  final FreeQuotaService? _freeQuotaService;
  final CashierShiftService? _cashierShiftService;
  final OfflineSyncEventStore? _syncEvents;
  final SyncEntityIdentityStore? _syncIdentities;

  OfflineSyncEventStore get _effectiveSyncEvents =>
      _syncEvents ?? OfflineSyncEventStore(_dao.db);

  SyncEntityIdentityStore get _effectiveSyncIdentities =>
      _syncIdentities ?? SyncEntityIdentityStore(_dao.db);

  SaleRepositoryImpl(
    this._datasource,
    this._dao,
    this._journalService,
    this._audit,
    this._sessionService,
    this._loyaltyRepository,
    this._commissionService,
    this._loyaltyPointsService, {
    this.warehouseScope,
    EInvoiceDispatchService? einvoiceDispatch,
    FreeQuotaService? freeQuotaService,
    CashierShiftService? cashierShiftService,
    OfflineSyncEventStore? syncEvents,
    SyncEntityIdentityStore? syncIdentities,
  }) : _einvoiceDispatch = einvoiceDispatch,
       _freeQuotaService = freeQuotaService,
       _cashierShiftService = cashierShiftService,
       _syncEvents = syncEvents,
       _syncIdentities = syncIdentities;

  Future<int?> _currentUserId() => _sessionService.getCurrentUserId();

  Future<void> _appendPostedSaleEvent(
    OfflineSyncTransaction transaction, {
    required int saleId,
    required int? actorUserId,
  }) async {
    if (!await transaction.isWriterRecordingEnabled()) return;
    final sale = await _dao.getSaleById(saleId);
    if (sale == null) {
      throw StateError('Posted sale is missing from the local database.');
    }
    final payload = await SaleSyncContractBuilder(
      _dao.db,
      _effectiveSyncIdentities,
    ).buildPostedSale(sale: sale, actorUserId: actorUserId);
    await transaction.appendOnce(
      producerKey: 'sale:posted:$saleId',
      eventType: 'sale.posted.v1',
      aggregateType: 'sale',
      aggregateId: payload['documentId']! as String,
      contractVersion: 1,
      occurredAt: sale.updatedAt,
      payload: payload,
    );
  }

  Future<void> _appendPostedLinkedReturnEvent(
    OfflineSyncTransaction transaction, {
    required int returnId,
    required int? actorUserId,
  }) async {
    if (!await transaction.isWriterRecordingEnabled()) return;
    final saleReturn = await _dao.getSaleReturnById(returnId);
    if (saleReturn == null) {
      throw StateError(
        'Posted sale return is missing from the local database.',
      );
    }
    final payload = await SaleSyncContractBuilder(
      _dao.db,
      _effectiveSyncIdentities,
    ).buildPostedLinkedReturn(saleReturn: saleReturn, actorUserId: actorUserId);
    await transaction.appendOnce(
      producerKey: 'sale_return:posted:$returnId',
      eventType: 'sale_return.posted.v1',
      aggregateType: 'sale_return',
      aggregateId: payload['documentId']! as String,
      contractVersion: 1,
      occurredAt: saleReturn.returnDate,
      payload: payload,
    );
  }

  @override
  Future<String> generateInvoiceNumber() => _datasource.generateInvoiceNumber();

  @override
  Stream<List<SaleEntity>> watchAllSales() =>
      _datasource.watchAllSales().asyncMap(
        (rows) => _reader.filter(
          rows,
          (_) => InventoryPostingDocument.sale,
          (r) => r.id,
        ),
      );

  @override
  Stream<List<SaleEntity>> watchCustomerSales(int customerId) => _datasource
      .watchCustomerSales(customerId)
      .asyncMap(
        (rows) => _reader.filter(
          rows,
          (_) => InventoryPostingDocument.sale,
          (r) => r.id,
        ),
      );

  @override
  Future<SaleEntity?> getSaleById(int id) async =>
      await _reader.contains(InventoryPostingDocument.sale, id)
      ? _datasource.getSaleById(id)
      : null;

  @override
  Future<List<SaleItemEntity>> getSaleItems(int saleId) async =>
      await _reader.contains(InventoryPostingDocument.sale, saleId)
      ? _datasource.getSaleItemsWithDetails(saleId)
      : [];

  @override
  Stream<List<SaleItemEntity>> watchSaleItems(int saleId) => _reader.gate(
    InventoryPostingDocument.sale,
    saleId,
    _datasource.watchSaleItems(saleId),
    <SaleItemEntity>[],
  );

  @override
  Future<int> createSale({
    int? customerId,
    int? employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
    bool allowNegativeStock = false,
    String? idempotencyKey,
    int? actorUserId,
    bool taxInclusiveAtPost = false,
    List<AppliedPromotion> appliedPromotions = const [],
    List<CheckoutPaymentAllocation> initialPayments = const [],
  }) async {
    final settlement = CheckoutSettlement(initialPayments);
    final isPureCheque =
        initialPayments.isEmpty &&
        (paymentMethod == 'cheque' || paymentMethod == 'check');
    if (initialPayments.isNotEmpty) {
      settlement.validate(invoiceTotalCents: totalCents.toBigInt().toInt());
      if (settlement.totalSettledCents != paidAmountCents.toBigInt().toInt()) {
        throw ArgumentError('settlement_total_mismatch');
      }
      if (customerId == null &&
          (initialPayments.any((payment) => payment.isCheque) ||
              settlement.totalAllocatedCents < totalCents.toBigInt().toInt())) {
        throw ArgumentError('customer_required_for_deferred_settlement');
      }
    }
    if (isPureCheque && dueDate == null) {
      throw ArgumentError('cheque_due_date_required');
    }
    if (isPureCheque && customerId == null) {
      throw ArgumentError('customer_required_for_cheque_settlement');
    }
    final normalizedIdempotencyKey = idempotencyKey?.trim();
    if (normalizedIdempotencyKey != null &&
        normalizedIdempotencyKey.isNotEmpty) {
      final existing =
          await (_dao.db.select(_dao.db.sales)..where(
                (row) => row.idempotencyKey.equals(normalizedIdempotencyKey),
              ))
              .getSingleOrNull();
      if (existing != null) {
        await DocumentPostingScope.validate(
          _dao.db,
          InventoryPostingDocument.sale,
          existing.id,
          scope: warehouseScope,
        );
        return existing.id;
      }
    }

    // Phase B4 — enforce free-tier cumulative cap BEFORE opening the tx.
    // Pro users bypass; free users at or past the cap get
    // [FreeQuotaExceededException]. Done up-front so we don't waste a tx
    // and a row-lock just to fail the quota check.
    _freeQuotaService?.guardSaleCreation();

    final userId = actorUserId ?? await _currentUserId();
    final cashierShiftId = await _cashierShiftService?.resolveOpenShiftId(
      userId,
    );

    // Invoice number is generated INSIDE the transaction (see below)
    // to prevent race conditions when two sales are created concurrently.

    final saleCompanion = db.SalesCompanion(
      invoiceNumber: const Value.absent(), // placeholder, set inside tx
      customerId: customerId != null ? Value(customerId) : const Value.absent(),
      employeeId: employeeId != null ? Value(employeeId) : const Value.absent(),
      cashierShiftId: cashierShiftId != null
          ? Value(cashierShiftId)
          : const Value.absent(),
      subtotalCents: Value(subtotalCents),
      taxCents: Value(taxCents),
      discountCents: Value(discountCents),
      totalCents: Value(totalCents),
      // Structured settlements are posted through AR one leg at a time below.
      paidAmountCents: Value(
        initialPayments.isEmpty && !isPureCheque
            ? paidAmountCents
            : Decimal.zero,
      ),
      currencyId: Value(currencyId),
      paymentMethod: Value(paymentMethod),
      status: const Value('draft'),
      notes: notes != null ? Value(notes) : const Value.absent(),
      idempotencyKey:
          normalizedIdempotencyKey != null &&
              normalizedIdempotencyKey.isNotEmpty
          ? Value(normalizedIdempotencyKey)
          : const Value.absent(),
      saleDate: saleDate != null ? Value(saleDate) : Value(DateTime.now()),
      dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

    final itemCompanions = items
        .map(
          (i) => db.SaleItemsCompanion(
            productId: Value(i.productId),
            variantId: i.variantId != null
                ? Value(i.variantId!)
                : const Value.absent(),
            supplierIdentityId: i.supplierIdentityId != null
                ? Value(i.supplierIdentityId!)
                : const Value.absent(),
            consignmentLayerId: i.consignmentLayerId != null
                ? Value(i.consignmentLayerId!)
                : const Value.absent(),
            employeeId: i.employeeId != null
                ? Value(i.employeeId!)
                : const Value.absent(),
            quantity: Value(i.quantity),
            quantityScale: Value(i.quantityScale),
            measurementType: Value(i.measurementType),
            unitPriceCents: Value(i.unitPriceCents),
            subtotalCents: Value(i.subtotalCents),
            discountCents: Value(i.discountCents),
            itemDiscountAtPostCents: i.itemDiscountAtPostCents == null
                ? const Value.absent()
                : Value(i.itemDiscountAtPostCents!),
            invoiceDiscountAtPostCents: i.invoiceDiscountAtPostCents == null
                ? const Value.absent()
                : Value(i.invoiceDiscountAtPostCents!),
            taxCents: Value(i.taxCents),
            totalCents: Value(i.totalCents),
          ),
        )
        .toList();

    // ATOMIC: Wrap sale creation, stock deduction, customer balance,
    // journal entries, and commissions in a single transaction.
    // If any step fails, everything rolls back — preventing GL ↔ sub-ledger drift.
    final effectiveSaleDate = saleDate ?? DateTime.now();

    const maxRetries = 3;
    late int saleId;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        saleId = await _effectiveSyncEvents.transaction((
          syncTransaction,
        ) async {
          // Generate invoice number INSIDE the transaction for atomicity
          final invoiceNumber = await _dao.generateInvoiceNumber();
          final companionWithNumber = saleCompanion.copyWith(
            invoiceNumber: Value(invoiceNumber),
          );
          final id = await _dao.createSaleWithItems(
            companionWithNumber,
            itemCompanions,
            scope: warehouseScope,
          );

          await _persistPromotionSnapshots(
            saleId: id,
            inputs: items,
            applications: appliedPromotions,
          );

          // Auto-post: deduct stock and update customer balance
          await _dao.postSale(
            id,
            allowNegativeStock: allowNegativeStock,
            scope: warehouseScope,
            beforeCompletion: (saleId) => ConsignmentSaleAccountingService(
              _dao.db,
              _journalService,
            ).postPendingAccruals(saleId, userId: userId),
          );

          // Create journal entries — MANDATORY, errors propagate
          await _journalService.recordSaleJournalEntry(
            saleId: id,
            totalCents: totalCents.toBigInt().toInt(),
            paidAmountCents: initialPayments.isEmpty && !isPureCheque
                ? paidAmountCents.toBigInt().toInt()
                : 0,
            currencyId: currencyId,
            taxCents: taxCents.toBigInt().toInt(),
            paymentMethod: initialPayments.isEmpty && !isPureCheque
                ? paymentMethod
                : 'credit',
            userId: userId,
          );

          for (final allocation in initialPayments) {
            if (allocation.isCheque) {
              await ChequeInstrumentDao(_dao.db).create(
                direction: ChequeDirectionValue.incoming,
                sourceTable: ChequeSourceTables.sale,
                sourceId: id,
                amountCents: allocation.amountCents,
                currencyId: currencyId,
                dueDate: allocation.dueDate!,
                partyType: 'customer',
                partyId: customerId,
                chequeNumber: allocation.reference,
                bankName: allocation.bankName,
                issueDate: allocation.issueDate ?? effectiveSaleDate,
                userId: userId,
                note: allocation.note,
              );
              continue;
            }
            final paymentId = await _dao.recordPayment(
              db.SalePaymentsCompanion.insert(
                saleId: id,
                cashierShiftId: Value(cashierShiftId),
                amountCents: Decimal.fromInt(allocation.amountCents),
                currencyId: currencyId,
                paymentMethod: allocation.method,
                reference: Value(allocation.reference),
                notes: Value(allocation.note ?? 'Initial invoice settlement'),
                paymentDate: Value(allocation.issueDate ?? effectiveSaleDate),
              ),
            );
            await _journalService.recordCustomerPaymentJournalEntry(
              paymentId: paymentId,
              amountCents: allocation.amountCents,
              currencyId: currencyId,
              paymentMethod: allocation.method,
              userId: userId,
            );
          }

          if (isPureCheque && dueDate != null) {
            await ChequeInstrumentDao(_dao.db).ensurePrimary(
              direction: ChequeDirectionValue.incoming,
              sourceTable: ChequeSourceTables.sale,
              sourceId: id,
              amountCents: totalCents.toBigInt().toInt(),
              currencyId: currencyId,
              dueDate: dueDate,
              partyType: customerId == null ? null : 'customer',
              partyId: customerId,
              userId: userId,
            );
          }

          // COGS journal entry — MANDATORY (Dr COGS, Cr Inventory)
          final costCents = await _dao.computeSaleCostCents(id);
          await _journalService.recordSaleCOGSJournalEntry(
            saleId: id,
            costCents: costCents,
            currencyId: currencyId,
            userId: userId,
          );

          await _recordSaleCommissions(id);

          if (customerId != null) {
            await _loyaltyPointsService.awardForSale(
              customerId: customerId,
              saleId: id,
              totalCents: totalCents.toBigInt().toInt(),
              strict: true,
            );
          }
          await _appendPostedSaleEvent(
            syncTransaction,
            saleId: id,
            actorUserId: userId,
          );
          return id;
        });
        break; // success
      } catch (e) {
        if (normalizedIdempotencyKey != null &&
            normalizedIdempotencyKey.isNotEmpty &&
            e.toString().contains('UNIQUE constraint failed')) {
          final existing =
              await (_dao.db.select(_dao.db.sales)..where(
                    (row) =>
                        row.idempotencyKey.equals(normalizedIdempotencyKey),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            await DocumentPostingScope.validate(
              _dao.db,
              InventoryPostingDocument.sale,
              existing.id,
              scope: warehouseScope,
            );
            return existing.id;
          }
        }
        // Retry on UNIQUE constraint violation (concurrent invoice number)
        final isUniqueViolation = e.toString().contains(
          'UNIQUE constraint failed',
        );
        if (isUniqueViolation && attempt < maxRetries) {
          developer.log(
            'Invoice number collision on attempt $attempt, retrying...',
            name: 'SaleRepository',
          );
          continue;
        }
        rethrow;
      }
    }

    await _afterCommit(() async {
      // Phase B4 — bump the cumulative counter ONLY after a successful tx.
      // Pro users still increment so that, if their subscription lapses, the
      // free-tier counter accurately reflects lifetime usage.
      await _freeQuotaService?.incrementSalesCreated();

      // Audit log outside transaction (non-critical, fire-and-forget)
      _audit.logSaleCreated(
        saleId: saleId,
        totalCents: totalCents.toBigInt().toInt(),
        paymentMethod: paymentMethod,
        customerId: customerId,
        userId: userId,
      );

      // Phase 4 — e-invoice dispatch (fire-and-forget, swallows errors).
      // Outside the accounting tx on purpose: a failed ZATCA/ETA/PEPPOL
      // submission must never roll back a posted sale. The dispatcher
      // records its own artifact row so operators can retry from the UI.
      await _dispatchSaleEInvoice(
        saleId: saleId,
        customerId: customerId,
        currencyId: currencyId,
        subtotalCents: subtotalCents.toBigInt().toInt(),
        taxCents: taxCents.toBigInt().toInt(),
        totalCents: totalCents.toBigInt().toInt(),
        issueDate: effectiveSaleDate,
        items: items,
      );
    });

    return saleId;
  }

  Future<void> _recordSaleCommissions(int id) async {
    final sale = await _dao.getSaleById(id);
    if (sale == null) throw StateError('Sale missing for commission posting');
    final items = await _dao.getSaleItems(id);
    final employeeId = sale.employeeId;
    final subtotalCents = sale.subtotalCents;
    final discountCents = sale.discountCents;
    final currencyId = sale.currencyId;
    final effectiveSaleDate = sale.saleDate;
    // Create commission records for assigned salesperson(s) via the
    // CommissionService (Phase 6 SoT).
    final totalItemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
    if (employeeId != null) {
      await _commissionService.createForSale(
        saleId: id,
        employeeId: employeeId,
        subtotalCents: subtotalCents.toBigInt().toInt(),
        discountCents: discountCents.toBigInt().toInt(),
        itemCount: totalItemCount,
        currencyId: currencyId,
        saleDate: effectiveSaleDate,
      );
    } else {
      // Per-item salesperson commissions: aggregate subtotal, discount and
      // item count per employee so percentage commission is computed on the
      // post-discount base per salesperson.
      final perEmployeeSubtotals = <int, int>{};
      final perEmployeeDiscounts = <int, int>{};
      final perEmployeeItemCounts = <int, int>{};
      for (final item in items) {
        if (item.employeeId != null) {
          perEmployeeSubtotals[item.employeeId!] =
              (perEmployeeSubtotals[item.employeeId!] ?? 0) +
              item.subtotalCents.toBigInt().toInt();
          perEmployeeDiscounts[item.employeeId!] =
              (perEmployeeDiscounts[item.employeeId!] ?? 0) +
              item.discountCents.toBigInt().toInt();
          perEmployeeItemCounts[item.employeeId!] =
              (perEmployeeItemCounts[item.employeeId!] ?? 0) + item.quantity;
        }
      }
      for (final empId in perEmployeeSubtotals.keys) {
        await _commissionService.createForSale(
          saleId: id,
          employeeId: empId,
          subtotalCents: perEmployeeSubtotals[empId]!,
          discountCents: perEmployeeDiscounts[empId] ?? 0,
          itemCount: perEmployeeItemCounts[empId]!,
          currencyId: currencyId,
          saleDate: effectiveSaleDate,
        );
      }
    }
  }

  Future<void> _persistPromotionSnapshots({
    required int saleId,
    required List<SaleItemInput> inputs,
    required List<AppliedPromotion> applications,
  }) async {
    if (applications.isEmpty) return;
    final lineIds = inputs.map((row) => row.lineId).toList(growable: false);
    if (lineIds.any((id) => id.trim().isEmpty) ||
        lineIds.toSet().length != lineIds.length) {
      throw StateError('Promotion snapshot contains invalid sale line IDs.');
    }
    final storedItems =
        await (_dao.db.select(_dao.db.saleItems)
              ..where((row) => row.saleId.equals(saleId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    if (storedItems.length != inputs.length) {
      throw StateError('Promotion snapshot sale line count mismatch.');
    }
    final storedByLine = <String, db.SaleItem>{};
    final inputByLine = <String, SaleItemInput>{};
    for (var index = 0; index < inputs.length; index++) {
      storedByLine[inputs[index].lineId] = storedItems[index];
      inputByLine[inputs[index].lineId] = inputs[index];
    }

    final allocatedByLine = <String, int>{};
    for (final application in applications) {
      final allocationTotal = application.allocations.fold<int>(
        0,
        (sum, row) => sum + row.discount.cents,
      );
      if (allocationTotal <= 0 ||
          allocationTotal != application.totalDiscount.cents) {
        throw StateError('Promotion snapshot discount total mismatch.');
      }
      final applicationId = await _dao.db
          .into(_dao.db.salePromotionApplications)
          .insert(
            db.SalePromotionApplicationsCompanion.insert(
              saleId: saleId,
              promotionId: application.promotionId,
              promotionCode: application.code,
              promotionName: application.name,
              promotionVersion: application.version,
              promotionType: _promotionTypeToDb(application.type),
              concurrencyMode: _promotionConcurrencyToDb(
                application.concurrencyMode,
              ),
              applicationCount: Value(application.applicationCount),
              discountCents: Decimal.fromInt(application.totalDiscount.cents),
              promotionEngineVersion: PromotionEngineVersion.current,
              calculationSnapshotJson: jsonEncode(application.toSnapshotMap()),
            ),
          );
      for (final allocation in application.allocations) {
        final stored = storedByLine[allocation.lineId];
        final input = inputByLine[allocation.lineId];
        if (stored == null || input == null || allocation.discount.cents <= 0) {
          throw StateError(
            'Promotion snapshot references an invalid sale line.',
          );
        }
        allocatedByLine.update(
          allocation.lineId,
          (value) => value + allocation.discount.cents,
          ifAbsent: () => allocation.discount.cents,
        );
        await _dao.db
            .into(_dao.db.saleItemPromotionAllocations)
            .insert(
              db.SaleItemPromotionAllocationsCompanion.insert(
                applicationId: applicationId,
                saleItemId: stored.id,
                discountCents: Decimal.fromInt(allocation.discount.cents),
                appliedQuantity: allocation.appliedQuantity,
                quantityScale: Value(allocation.quantityScale),
                originalUnitPriceCents: input.unitPriceCents,
                rewardType: _promotionRewardToDb(allocation.rewardType),
              ),
            );
      }
    }
    for (final entry in allocatedByLine.entries) {
      final storedDiscount = inputByLine[entry.key]!.discountCents
          .toBigInt()
          .toInt();
      if (entry.value > storedDiscount) {
        throw StateError(
          'Promotion allocation exceeds persisted line discount.',
        );
      }
    }
  }

  static String _promotionTypeToDb(PromotionType type) => switch (type) {
    PromotionType.simple => 'simple',
    PromotionType.quantity => 'quantity',
    PromotionType.fixedBundle => 'fixed_bundle',
    PromotionType.buyXGetY => 'buy_x_get_y',
    PromotionType.threshold => 'threshold',
  };

  static String _promotionConcurrencyToDb(PromotionConcurrencyMode mode) =>
      switch (mode) {
        PromotionConcurrencyMode.exclusive => 'exclusive',
        PromotionConcurrencyMode.bestPrice => 'best_price',
        PromotionConcurrencyMode.compound => 'compound',
      };

  static String _promotionRewardToDb(PromotionRewardType type) =>
      switch (type) {
        PromotionRewardType.percentageOff => 'percentage_off',
        PromotionRewardType.amountOff => 'amount_off',
        PromotionRewardType.fixedBundlePrice => 'fixed_bundle_price',
        PromotionRewardType.freeQuantity => 'free_quantity',
      };

  @override
  Future<bool> updateSale({
    required int saleId,
    int? customerId,
    int? employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
    bool taxInclusiveAtPost = false,
  }) async {
    // Guard: only draft/pending sales can be edited.
    // Posted/voided sales have journal entries that would become stale.
    final existing = await getSaleById(saleId);
    if (existing == null) throw StateError('Sale not found in this warehouse.');
    if (existing.status != 'draft' && existing.status != 'pending') {
      throw Exception(
        'Cannot edit a ${existing.status} sale. Void it and create a new one instead.',
      );
    }

    // Phase 11.2 — the snapshot is re-stamped on edit because the
    // engine just recomputed the totals; the new triple is the
    // authoritative record of the run that produced this row.
    final saleCompanion = db.SalesCompanion(
      customerId: customerId != null ? Value(customerId) : const Value.absent(),
      employeeId: employeeId != null ? Value(employeeId) : const Value.absent(),
      subtotalCents: Value(subtotalCents),
      taxCents: Value(taxCents),
      discountCents: Value(discountCents),
      totalCents: Value(totalCents),
      paidAmountCents: Value(paidAmountCents),
      currencyId: Value(currencyId),
      paymentMethod: Value(paymentMethod),
      notes: notes != null ? Value(notes) : const Value.absent(),
      saleDate: saleDate != null ? Value(saleDate) : const Value.absent(),
      dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

    final itemCompanions = items
        .map(
          (i) => db.SaleItemsCompanion(
            productId: Value(i.productId),
            variantId: i.variantId != null
                ? Value(i.variantId!)
                : const Value.absent(),
            supplierIdentityId: i.supplierIdentityId != null
                ? Value(i.supplierIdentityId!)
                : const Value.absent(),
            consignmentLayerId: i.consignmentLayerId != null
                ? Value(i.consignmentLayerId!)
                : const Value.absent(),
            employeeId: i.employeeId != null
                ? Value(i.employeeId!)
                : const Value.absent(),
            quantity: Value(i.quantity),
            quantityScale: Value(i.quantityScale),
            measurementType: Value(i.measurementType),
            unitPriceCents: Value(i.unitPriceCents),
            subtotalCents: Value(i.subtotalCents),
            discountCents: Value(i.discountCents),
            itemDiscountAtPostCents: i.itemDiscountAtPostCents == null
                ? const Value.absent()
                : Value(i.itemDiscountAtPostCents!),
            invoiceDiscountAtPostCents: i.invoiceDiscountAtPostCents == null
                ? const Value.absent()
                : Value(i.invoiceDiscountAtPostCents!),
            taxCents: Value(i.taxCents),
            totalCents: Value(i.totalCents),
          ),
        )
        .toList();

    // Resolve userId once before entering the transaction.
    final userId = await _currentUserId();

    // Remove legacy draft accounting and update the draft atomically.
    // Revenue, COGS and commissions are recognized only when posted.
    final ok = await _dao.db.transaction(() async {
      await DocumentPostingScope.validate(
        _dao.db,
        InventoryPostingDocument.sale,
        saleId,
        scope: warehouseScope,
      );
      final current = await _dao.getSaleById(saleId);
      if (current == null ||
          (current.status != 'draft' && current.status != 'pending')) {
        throw StateError('Only draft or pending sales can be edited.');
      }
      // 1. Void old journal entries
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'Sale updated',
        userId: userId,
      );

      // 2. Update sale data and items
      final updated = await _dao.updateSaleWithItems(
        saleId,
        saleCompanion,
        itemCompanions,
      );

      if (updated) {
        // A draft has no stock movement, revenue, COGS or earned commissions.
        await _commissionService.deleteForSale(saleId);
      }

      return updated;
    });

    // Audit log outside transaction (non-critical, must not block sale update)
    if (ok) {
      _audit.log(
        entityType: 'sale',
        entityId: saleId,
        action: 'update',
        newValue: {
          'totalCents': totalCents.toString(),
          'itemCount': items.length,
        },
        userId: userId,
      );
    }

    return ok;
  }

  @override
  Future<void> postSale(int saleId, {bool allowNegativeStock = false}) async {
    _freeQuotaService?.guardSaleCreation();
    final posted = await _effectiveSyncEvents.transaction((
      syncTransaction,
    ) async {
      await DocumentPostingScope.validate(
        _dao.db,
        InventoryPostingDocument.sale,
        saleId,
        scope: warehouseScope,
      );
      final sale = await _dao.getSaleById(saleId);
      if (sale == null ||
          (sale.status != 'draft' && sale.status != 'pending')) {
        throw StateError('Only a draft or pending sale can be posted');
      }
      if ((await _dao.getSalePayments(saleId)).isNotEmpty) {
        throw StateError('Review legacy draft payments before posting');
      }
      final userId = await _currentUserId();
      final cheque =
          sale.paymentMethod == 'cheque' || sale.paymentMethod == 'check';
      if (cheque &&
          (sale.customerId == null ||
              sale.dueDate == null ||
              sale.paidAmountCents != Decimal.zero)) {
        throw StateError(
          'Cheque sales require a customer, due date and no premature settlement',
        );
      }
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'Replace legacy draft accounting on posting',
        userId: userId,
      );
      await _commissionService.deleteForSale(saleId);
      await _dao.postSale(
        saleId,
        allowNegativeStock: allowNegativeStock,
        scope: warehouseScope,
        beforeCompletion: (postedSaleId) => ConsignmentSaleAccountingService(
          _dao.db,
          _journalService,
        ).postPendingAccruals(postedSaleId, userId: userId),
      );
      final payments = await _dao.getSalePayments(saleId);
      await _journalService.recordSaleJournalEntry(
        saleId: saleId,
        totalCents: sale.totalCents.toBigInt().toInt(),
        paidAmountCents: sale.customerId == null
            ? sale.paidAmountCents.toBigInt().toInt()
            : 0,
        currencyId: sale.currencyId,
        taxCents: sale.taxCents.toBigInt().toInt(),
        paymentMethod: sale.customerId == null ? sale.paymentMethod : 'credit',
        userId: userId,
      );
      for (final payment in payments) {
        await _journalService.recordCustomerPaymentJournalEntry(
          paymentId: payment.id,
          amountCents: payment.amountCents.toBigInt().toInt(),
          currencyId: payment.currencyId,
          paymentMethod: payment.paymentMethod,
          userId: userId,
        );
      }
      if (cheque) {
        await ChequeInstrumentDao(_dao.db).ensurePrimary(
          direction: ChequeDirectionValue.incoming,
          sourceTable: ChequeSourceTables.sale,
          sourceId: saleId,
          amountCents: sale.totalCents.toBigInt().toInt(),
          currencyId: sale.currencyId,
          dueDate: sale.dueDate!,
          partyType: 'customer',
          partyId: sale.customerId,
          userId: userId,
        );
      }
      await _journalService.recordSaleCOGSJournalEntry(
        saleId: saleId,
        costCents: await _dao.computeSaleCostCents(saleId),
        currencyId: sale.currencyId,
        userId: userId,
      );
      await _recordSaleCommissions(saleId);
      if (sale.customerId != null) {
        await _loyaltyPointsService.awardForSale(
          customerId: sale.customerId!,
          saleId: saleId,
          totalCents: sale.totalCents.toBigInt().toInt(),
          strict: true,
        );
      }
      await _audit.log(
        entityType: 'sale',
        entityId: saleId,
        action: 'post',
        userId: userId,
      );
      await _appendPostedSaleEvent(
        syncTransaction,
        saleId: saleId,
        actorUserId: userId,
      );
      return (sale, await _dao.getSaleItems(saleId));
    });
    await _afterCommit(() async {
      await _freeQuotaService?.incrementSalesCreated();
      await _dispatchSaleEInvoice(
        saleId: saleId,
        customerId: posted.$1.customerId,
        currencyId: posted.$1.currencyId,
        subtotalCents: posted.$1.subtotalCents.toBigInt().toInt(),
        taxCents: posted.$1.taxCents.toBigInt().toInt(),
        totalCents: posted.$1.totalCents.toBigInt().toInt(),
        issueDate: posted.$1.saleDate,
        items: posted.$2
            .map(
              (i) => SaleItemInput(
                lineId: '${i.id}',
                productId: i.productId,
                variantId: i.variantId,
                supplierIdentityId: i.supplierIdentityId,
                employeeId: i.employeeId,
                quantity: i.quantity,
                quantityScale: i.quantityScale,
                measurementType: i.measurementType,
                unitPriceCents: i.unitPriceCents,
                subtotalCents: i.subtotalCents,
                discountCents: i.discountCents,
                taxCents: i.taxCents,
                totalCents: i.totalCents,
              ),
            )
            .toList(),
      );
    });
  }

  @override
  Future<void> voidSale(int saleId, {int? actorUserId}) async {
    await _dao.db.transaction(() async {
      final resolvedUserId = actorUserId ?? await _currentUserId();
      // 2026-05-13 — pre-flight integrity guard. The analyzer is a side-
      // effect-free SoT that surfaces every condition that would corrupt
      // the books if the void went through (entangled adjustment returns,
      // negative-stock projections). On a hard blocker we throw
      // `VoidBlockedByImpactException` carrying the full report so the UI
      // can render an actionable dialog instead of silently producing GL
      // drift like the one diagnosed in `tapix_backup_20260513_121448.db`.
      final report = await VoidImpactAnalyzer(
        _dao.db,
        warehouseScope: warehouseScope == null
            ? null
            : await WarehouseReadScope.resolve(
                _dao.db,
                warehouseId: warehouseScope!.warehouseId,
              ),
      ).analyzeSaleVoid(saleId);
      if (report.hasBlockers) {
        throw VoidBlockedByImpactException(report);
      }

      final linkedReturns =
          await (_dao.db.select(_dao.db.saleReturns)..where(
                (row) =>
                    row.saleId.equals(saleId) & row.status.isNotValue('voided'),
              ))
              .get();
      for (final saleReturn in linkedReturns) {
        await ChequeSourceVoidService.voidForSource(
          db: _dao.db,
          journalService: _journalService,
          sourceTable: ChequeSourceTables.saleReturn,
          sourceId: saleReturn.id,
          reason: 'Sale voided — linked return cheque cancelled',
          userId: resolvedUserId,
        );
      }
      await ChequeSourceVoidService.voidForSource(
        db: _dao.db,
        journalService: _journalService,
        sourceTable: ChequeSourceTables.sale,
        sourceId: saleId,
        reason: 'Sale voided — cheque cancelled',
        userId: resolvedUserId,
      );

      // Void journal entries BEFORE voiding the sale (so we can still read the data).
      // This MUST succeed — if it fails the entire void is aborted to prevent GL drift.
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'Sale voided',
        userId: resolvedUserId,
      );

      // 2026-05-18 — Phase 15.2 — Reverse the GL journal entry for EVERY
      // payment row attached to this sale (cash, cheque-cleared, card,
      // mixed tender, customer-credit reapplications). The DAO records a
      // `payment_reversal` customer_transaction so the sub-ledger zeroes
      // out, but the GL payment leg (Dr Cash|Bank / Cr AR) must be reversed
      // here or AR and Cash drift by the cleared payment amount. Symmetric
      // to the purchase side; same root-cause class as the AP drift = 89991¢
      // reproduced in `tapix_backup_20260518_051956.db`.
      final paymentsForVoid = await _reader.read(
        InventoryPostingDocument.sale,
        saleId,
        () => _datasource.getSalePayments(saleId),
        <SalePaymentEntity>[],
      );
      for (final p in paymentsForVoid) {
        await _journalService.voidJournalEntriesForSource(
          sourceTable: 'sale_payments',
          sourceId: p.id,
          reason: 'Sale voided — payment JE reversed',
          userId: resolvedUserId,
        );
      }

      // Void commissions linked to this sale
      await _commissionService.deleteForSale(saleId);

      // Loyalty effects must roll back with the sale and its journal entries.
      final sale = await getSaleById(saleId);

      // 2026-05-13 — pass the journal service so the DAO's cascade-void of
      // linked sale_returns also reverses their JEs (root-cause #3 fix).
      final consignmentAccounting = ConsignmentSaleAccountingService(
        _dao.db,
        _journalService,
      );
      await _dao.voidSale(
        saleId,
        journalEntryService: _journalService,
        userId: resolvedUserId,
        scope: warehouseScope,
        beforeReturnCompletion: (returnId) => consignmentAccounting
            .postPendingReturnVoidReaccruals(returnId, userId: resolvedUserId),
        beforeCompletion: (id) => consignmentAccounting
            .postPendingSaleVoidReversals(id, userId: resolvedUserId),
      );
      if (sale != null && sale.customerId != null) {
        await _reverseLoyaltyPointsForSale(saleId, sale.customerId!);
      }
      // Audit: log sale void (CRITICAL)
      await _audit.logSaleVoided(
        saleId: saleId,
        reason: 'voided',
        userId: resolvedUserId,
      );
    });
  }

  /// Reverse all loyalty point transactions linked to a sale
  Future<void> _reverseLoyaltyPointsForSale(int saleId, int customerId) async {
    final transactions = await _loyaltyRepository.getPointsTransactions(
      customerId,
    );

    for (final tx in transactions) {
      if (tx.referenceId == saleId) {
        if (tx.transactionType == 'earn' && tx.referenceType == 'sale') {
          // Points were earned from this sale — deduct them
          final pointsToDeduct = tx.points;
          if (pointsToDeduct > 0) {
            await _loyaltyRepository.redeemPoints(
              customerId: customerId,
              points: pointsToDeduct,
              reason: 'Reversed earned points for voided sale #$saleId',
              referenceId: saleId,
              referenceType: 'sale_void',
            );
          }
        } else if (tx.transactionType == 'redeem' &&
            tx.referenceType == 'sale_redemption') {
          // Points were redeemed during this sale — return them
          final pointsToReturn = tx.points.abs();
          if (pointsToReturn > 0) {
            await _loyaltyRepository.addPoints(
              customerId: customerId,
              points: pointsToReturn,
              source: 'sale_void',
              referenceId: saleId,
              referenceType: 'sale_void',
              description: 'Returned redeemed points for voided sale #$saleId',
            );
          }
        }
      }
    }
  }

  @override
  Future<int> editPostedSale({
    required int originalSaleId,
    int? customerId,
    int? employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
    bool allowNegativeStock = false,
    bool taxInclusiveAtPost = false,
  }) async {
    final effects = <Future<void> Function()>[];
    final result = await runZoned(
      () => _dao.db.transaction(() async {
        // 1. Fetch original sale to validate
        final originalSale = await getSaleById(originalSaleId);
        if (originalSale == null) {
          throw StateError('Sale #$originalSaleId not found');
        }

        // 2. Check accounting period is open for the original sale date
        final txDate = originalSale.saleDate;
        final periodRows = await _dao.db
            .customSelect(
              '''SELECT id, is_closed FROM accounting_periods
         WHERE start_date <= ? AND end_date >= ?
         ORDER BY start_date DESC LIMIT 1''',
              variables: [
                Variable.withDateTime(txDate),
                Variable.withDateTime(txDate),
              ],
              readsFrom: {_dao.db.accountingPeriods},
            )
            .get();
        if (periodRows.isNotEmpty && periodRows.first.read<bool>('is_closed')) {
          throw StateError(
            'Cannot edit sale: the accounting period containing this '
            'sale has been closed.',
          );
        }

        // 3. Check if sale has any non-voided returns - cannot edit if returns exist
        final returns = await _dao.db
            .customSelect(
              'SELECT COUNT(*) as cnt FROM sale_returns WHERE sale_id = ? AND status != ?',
              variables: [
                Variable.withInt(originalSaleId),
                Variable.withString('voided'),
              ],
              readsFrom: {_dao.db.saleReturns},
            )
            .getSingle();
        if (returns.read<int>('cnt') > 0) {
          throw StateError(
            'Cannot edit sale: it has associated returns. '
            'Void the returns first or create a new sale.',
          );
        }

        final userId = await _currentUserId();

        // 4. Void the original sale (this restores stock and reverses accounting)
        await voidSale(originalSaleId);

        // 5. Create new sale with the edited data
        final newSaleId = await createSale(
          customerId: customerId,
          employeeId: employeeId,
          currencyId: currencyId,
          subtotalCents: subtotalCents,
          discountCents: discountCents,
          taxCents: taxCents,
          totalCents: totalCents,
          paidAmountCents: paidAmountCents,
          paymentMethod: paymentMethod,
          items: items,
          notes: notes != null
              ? '$notes\n[Edited from ${originalSale.invoiceNumber}]'
              : '[Edited from ${originalSale.invoiceNumber}]',
          saleDate: saleDate ?? originalSale.saleDate,
          dueDate: dueDate,
          allowNegativeStock: allowNegativeStock,
          taxInclusiveAtPost: taxInclusiveAtPost,
        );

        // 6. Audit log
        await _audit.log(
          entityType: 'sale',
          entityId: newSaleId,
          action: 'edit_posted_sale',
          oldValue: {
            'originalSaleId': originalSaleId,
            'originalInvoiceNumber': originalSale.invoiceNumber,
            'originalTotalCents': originalSale.totalCents.toString(),
          },
          newValue: {
            'newSaleId': newSaleId,
            'newTotalCents': totalCents.toString(),
            'itemCount': items.length,
          },
          userId: userId,
        );

        return newSaleId;
      }),
      zoneValues: {_commitEffectsKey: effects},
    );
    // No external submission or usage increment occurs for a rolled-back edit.
    for (final effect in effects) {
      await effect();
    }
    return result;
  }

  @override
  Future<void> deleteSale(int saleId) => _dao.db.transaction(() async {
    await DocumentPostingScope.validate(
      _dao.db,
      InventoryPostingDocument.sale,
      saleId,
      scope: warehouseScope,
    );
    // Void any journal entries BEFORE deleting the sale record.
    // This MUST succeed — if it fails the entire delete is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sales',
      sourceId: saleId,
      reason: 'Sale deleted',
      userId: await _currentUserId(),
    );

    // Delete commissions linked to this sale
    await _commissionService.deleteForSale(saleId);

    await _dao.deleteSale(saleId);
  });

  @override
  Stream<List<SaleReturnEntity>> watchAllSaleReturns() =>
      _datasource.watchAllSaleReturns().asyncMap(
        (rows) => _reader.filter(
          rows,
          (r) => r.isAdjustment
              ? InventoryPostingDocument.saleAdjustment
              : InventoryPostingDocument.saleReturn,
          (r) => r.id,
        ),
      );

  @override
  Future<SaleReturnEntity?> getSaleReturnById(int id) => _reader.read(
    InventoryPostingDocument.saleReturn,
    id,
    () => _datasource.getSaleReturnById(id),
    null,
  );

  @override
  Stream<List<SaleReturnItemEntity>> watchSaleReturnItemsWithDetails(
    int returnId,
  ) => _reader.gate(
    InventoryPostingDocument.saleReturn,
    returnId,
    _datasource.watchSaleReturnItemsWithDetails(returnId),
    <SaleReturnItemEntity>[],
  );

  @override
  Stream<List<SaleReturnEntity>> watchSaleReturnsBySale(int saleId) =>
      _datasource
          .watchSaleReturnsBySale(saleId)
          .asyncMap(
            (rows) => _reader.filter(
              rows,
              (_) => InventoryPostingDocument.saleReturn,
              (r) => r.id,
            ),
          );

  @override
  Stream<Set<int>> watchSaleIdsWithReturns() => _datasource
      .watchSaleIdsWithReturns()
      .asyncMap((rows) => _reader.ids(InventoryPostingDocument.sale, rows));

  @override
  Future<int> createSaleReturn({
    required int saleId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required List<SaleReturnItemInput> items,
    String? reason,
    String? dispositionType,
    String consignmentLiabilityResponsibility = 'review',
    String? consignmentLiabilityReason,
    String? refundMethod,
    DateTime? returnDate,
    DateTime? dueDate,
    String? idempotencyKey,
    int? actorUserId,
    bool taxInclusiveAtPost = false,
    List<CheckoutPaymentAllocation> settlementAllocations = const [],
  }) async {
    final structuredSettlement = settlementAllocations.isNotEmpty;
    final effectiveRefundMethod = structuredSettlement
        ? 'mixed'
        : (refundMethod ?? 'cash');
    final isChequeRefund =
        !structuredSettlement &&
        (effectiveRefundMethod == 'cheque' || effectiveRefundMethod == 'check');
    if (isChequeRefund && dueDate == null) {
      throw ArgumentError('cheque_due_date_required');
    }

    // Phase 14.0 — only persist dueDate when refund method is cheque.
    // For cash/credit refunds the column stays NULL so the dashboard
    // reminder cannot accidentally surface a non-cheque refund.
    final effectiveDueDate = isChequeRefund ? dueDate : null;

    // ATOMIC: Wrap return creation, stock restoration, journal entries,
    // and commission reversal in a single transaction.
    final userId = actorUserId ?? await _currentUserId();
    final cashierShiftId = await _cashierShiftService?.resolveOpenShiftId(
      userId,
    );
    final effectiveReturnDate = returnDate ?? DateTime.now();
    late int postedSubtotalCents;
    late int postedDiscountCents;
    late int postedTaxCents;
    late int postedTotalCents;
    late List<SaleReturnItemInput> postedItems;

    final returnId = await _effectiveSyncEvents.transaction((
      syncTransaction,
    ) async {
      final returnNumber = await _datasource.generateSaleReturnNumber();
      final originalSale = await _dao.getSaleById(saleId);
      if (originalSale == null) throw Exception('Sale not found');
      if (structuredSettlement) {
        if (originalSale.customerId == null) {
          throw ArgumentError('customer_required_for_deferred_settlement');
        }
      }
      if (isChequeRefund && originalSale.customerId == null) {
        throw ArgumentError('customer_required_for_cheque_return');
      }
      final inclusive = originalSale.taxInclusiveAtPost ?? false;
      final originalItems = await _datasource.getSaleItems(saleId);
      final originalById = {for (final item in originalItems) item.id: item};
      final histories = <int, LinkedReturnHistory>{};
      final calculatedItems = <SaleReturnItemInput>[];

      final requestedQuantities = <int, int>{};
      for (final input in items) {
        if (!originalById.containsKey(input.saleItemId)) {
          throw Exception(
            'Sale item #${input.saleItemId} does not belong to sale #$saleId',
          );
        }
        requestedQuantities.update(
          input.saleItemId,
          (quantity) => quantity + input.quantity,
          ifAbsent: () => input.quantity,
        );
      }

      final promotionApplications = await PromotionRepository(
        _dao.db,
        _audit,
      ).loadSaleApplications(saleId);
      final protectedSaleItemIds = promotionApplications
          .expand((application) => application.allocations)
          .map((allocation) => allocation.saleItemId)
          .toSet();
      for (final saleItemId in protectedSaleItemIds) {
        histories[saleItemId] = await _dao.getLinkedReturnHistory(saleItemId);
      }
      final bundleViolation = PromotionReturnPolicy.validateLinkedReturn(
        promotionApplications: promotionApplications,
        previouslyReturnedQuantityBySaleItemId: {
          for (final entry in histories.entries)
            entry.key: entry.value.quantity,
        },
        requestedQuantityBySaleItemId: requestedQuantities,
      );
      if (bundleViolation != null) {
        throw PromotionBundleReturnException(bundleViolation);
      }

      for (final input in items) {
        final original = originalById[input.saleItemId]!;
        final history =
            histories[input.saleItemId] ??
            await _dao.getLinkedReturnHistory(input.saleItemId);
        final calculated = ReturnCalculationService.computeProportionalReturn(
          originalQuantity: original.quantity,
          returnQuantity: input.quantity,
          originalSubtotalCents: original.subtotalCents.toBigInt().toInt(),
          originalDiscountCents: original.discountCents.toBigInt().toInt(),
          originalTaxCents: original.taxCents.toBigInt().toInt(),
          previousLinkedHistory: history,
          taxInclusivePricing: inclusive,
        );
        histories[input.saleItemId] = history.add(calculated, input.quantity);
        calculatedItems.add(
          input.withCalculatedAmounts(
            calculated,
            sourceQuantityScale: original.quantityScale,
            sourceMeasurementType: original.measurementType,
          ),
        );
      }

      postedItems = calculatedItems;
      postedSubtotalCents = calculatedItems.fold(
        0,
        (sum, item) => sum + item.subtotalCents.toBigInt().toInt(),
      );
      postedDiscountCents = calculatedItems.fold(
        0,
        (sum, item) => sum + item.discountCents.toBigInt().toInt(),
      );
      postedTaxCents = calculatedItems.fold(
        0,
        (sum, item) => sum + item.taxCents.toBigInt().toInt(),
      );
      postedTotalCents = calculatedItems.fold(
        0,
        (sum, item) => sum + item.refundCents.toBigInt().toInt(),
      );

      final returnCompanion = db.SaleReturnsCompanion(
        saleId: Value(saleId),
        cashierShiftId: cashierShiftId != null
            ? Value(cashierShiftId)
            : const Value.absent(),
        returnNumber: Value(returnNumber),
        subtotalCents: Value(Decimal.fromInt(postedSubtotalCents)),
        discountCents: Value(Decimal.fromInt(postedDiscountCents)),
        taxCents: Value(Decimal.fromInt(postedTaxCents)),
        totalCents: Value(Decimal.fromInt(postedTotalCents)),
        currencyId: Value(currencyId),
        reason: reason != null ? Value(reason) : const Value.absent(),
        dispositionType: dispositionType != null
            ? Value(dispositionType)
            : const Value.absent(),
        refundMethod: Value(effectiveRefundMethod),
        returnDate: Value(effectiveReturnDate),
        dueDate: Value(effectiveDueDate),
        idempotencyKey: Value(idempotencyKey),
      ).withPricingSnapshot(taxInclusive: inclusive);

      final itemCompanions = calculatedItems
          .map(
            (item) => db.SaleReturnItemsCompanion(
              saleItemId: Value(item.saleItemId),
              quantity: Value(item.quantity),
              quantityScale: Value(item.quantityScale),
              measurementType: Value(item.measurementType),
              subtotalCents: Value(item.subtotalCents),
              discountCents: Value(item.discountCents),
              taxCents: Value(item.taxCents),
              refundCents: Value(item.refundCents),
              reason: item.reason != null
                  ? Value(item.reason!)
                  : const Value.absent(),
            ),
          )
          .toList();
      final id = await _dao.createSaleReturn(returnCompanion, itemCompanions);

      final effectiveDisposition = dispositionType ?? 'restock';
      if (const {
        'write_off',
        'damaged',
        'scrap',
      }.contains(effectiveDisposition)) {
        final consignmentItems = await _dao.db
            .customSelect(
              'SELECT ri.id FROM sale_return_items ri '
              'WHERE ri.return_id=? AND EXISTS('
              'SELECT 1 FROM consignment_sale_allocations a '
              'WHERE a.sale_item_id=ri.sale_item_id)',
              variables: [Variable.withInt(id)],
            )
            .get();
        if (consignmentItems.isNotEmpty) {
          final responsibility =
              ConsignmentReturnLiabilityResponsibility.fromWire(
                consignmentLiabilityResponsibility,
              );
          if (responsibility ==
              ConsignmentReturnLiabilityResponsibility.review) {
            throw const ConsignmentReturnLiabilityException(
              ConsignmentReturnLiabilityException.decisionRequired,
            );
          }
          for (final row in consignmentItems) {
            await ConsignmentReturnLiabilityStore.record(
              _dao,
              sourceTable: 'sale_returns',
              sourceId: id,
              sourceItemId: row.read<int>('id'),
              dispositionType: effectiveDisposition,
              decision: ConsignmentReturnLiabilityDecision(
                responsibility: responsibility,
                reason: consignmentLiabilityReason ?? '',
                decidedBy: userId,
              ),
            );
          }
        }
      }

      // Auto-post return: restore stock immediately
      await _dao.postSaleReturn(
        id,
        scope: warehouseScope,
        beforeCompletion: (returnId) => ConsignmentSaleAccountingService(
          _dao.db,
          _journalService,
        ).postPendingReturnReversals(returnId, userId: userId),
      );

      // Create journal entries — MANDATORY.
      // `postingDate` flows through so `ReturnPostingService` enforces
      // the Phase 2.5 fiscal-period guard; `partyId` flows through so
      // the credit-note sub-ledger (Phase 2.3) can auto-issue when the
      // customer takes an on-account refund.
      final sale = await _dao.getSaleById(saleId);
      await _journalService.recordSaleReturnJournalEntry(
        returnId: id,
        totalCents: postedTotalCents,
        currencyId: currencyId,
        taxCents: postedTaxCents,
        refundMethod: structuredSettlement ? 'credit' : effectiveRefundMethod,
        partyId: sale?.customerId,
        userId: userId,
        postingDate: effectiveReturnDate,
      );

      if (structuredSettlement) {
        await ReturnSettlementService.apply(
          db: _dao.db,
          journalService: _journalService,
          side: ReturnSettlementSide.sale,
          sourceTable: ChequeSourceTables.saleReturn,
          sourceId: id,
          partyId: originalSale.customerId!,
          totalCents: postedTotalCents,
          currencyId: currencyId,
          allocations: settlementAllocations,
          documentDate: effectiveReturnDate,
          userId: userId,
        );
      } else if (effectiveDueDate != null &&
          (effectiveRefundMethod == 'cheque' ||
              effectiveRefundMethod == 'check')) {
        await ChequeInstrumentDao(_dao.db).ensurePrimary(
          direction: ChequeDirectionValue.outgoing,
          sourceTable: ChequeSourceTables.saleReturn,
          sourceId: id,
          amountCents: postedTotalCents,
          currencyId: currencyId,
          dueDate: effectiveDueDate,
          partyType: sale?.customerId == null ? null : 'customer',
          partyId: sale?.customerId,
          userId: userId,
        );
      }

      // COGS reversal journal entry — MANDATORY (Dr Inventory, Cr COGS)
      final returnCostCents = await _dao.computeSaleReturnCostCents(id);
      await _journalService.recordSaleReturnCOGSReversalJournalEntry(
        returnId: id,
        costCents: returnCostCents,
        currencyId: currencyId,
        userId: userId,
      );

      // Reverse commission for the returned amount via the
      // CommissionService (Phase 6 SoT). The service requires the
      // original sale's subtotal + total item count so it can prorate
      // against the ORIGINAL commission amount (rate-change safe).
      final returnedItemCount = calculatedItems.fold<int>(
        0,
        (sum, i) => sum + i.quantity,
      );
      final saleSubtotalCents = originalSale.subtotalCents.toBigInt().toInt();
      final totalSaleItems = originalItems.fold<int>(
        0,
        (sum, i) => sum + i.quantity,
      );
      await _commissionService.reverseForReturn(
        saleId: saleId,
        saleReturnId: id,
        saleSubtotalCents: saleSubtotalCents,
        totalSaleItemCount: totalSaleItems,
        returnSubtotalCents: postedSubtotalCents,
        returnedItemCount: returnedItemCount,
        currencyId: currencyId,
        returnDate: effectiveReturnDate,
      );

      await _loyaltyPointsService.reverseForReturn(
        saleId: saleId,
        returnId: id,
        returnTotalCents: postedTotalCents,
        strict: true,
      );

      await _appendPostedLinkedReturnEvent(
        syncTransaction,
        returnId: id,
        actorUserId: userId,
      );

      return id;
    });

    // Audit log outside transaction (non-critical)
    _audit.logSaleReturnCreated(
      returnId: returnId,
      saleId: saleId,
      totalCents: postedTotalCents,
      userId: userId,
    );

    // Phase 4 — e-invoice credit-note dispatch (fire-and-forget).
    final sale = await _dao.getSaleById(saleId);
    await _dispatchSaleReturnEInvoice(
      sourceTable: 'sale_returns',
      returnId: returnId,
      customerId: sale?.customerId,
      currencyId: currencyId,
      subtotalCents: postedSubtotalCents,
      taxCents: postedTaxCents,
      totalCents: postedTotalCents,
      issueDate: effectiveReturnDate,
      items: postedItems,
      originalInvoiceNumber: sale?.invoiceNumber,
    );

    return returnId;
  }

  @override
  Future<void> voidSaleReturn(
    int returnId, {
    bool allowNegativeStock = false,
  }) async {
    final userId = await _currentUserId();
    await _dao.db.transaction(() async {
      await ChequeSourceVoidService.voidForSource(
        db: _dao.db,
        journalService: _journalService,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: returnId,
        reason: 'Sale return voided — cheque cancelled',
        userId: userId,
      );
      await ReturnSettlementService.voidImmediate(
        db: _dao.db,
        journalService: _journalService,
        side: ReturnSettlementSide.sale,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: returnId,
        reason: 'Sale return settlement voided',
        userId: userId,
      );
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'sale_returns',
        sourceId: returnId,
        reason: 'Sale return voided',
        userId: userId,
      );
      await _datasource.voidSaleReturn(
        returnId,
        scope: warehouseScope,
        allowNegativeStock: allowNegativeStock,
        beforeCompletion: (id) => ConsignmentSaleAccountingService(
          _dao.db,
          _journalService,
        ).postPendingReturnVoidReaccruals(id, userId: userId),
      );
    });
    // Audit: log sale return void (CRITICAL)
    _audit.logVoid(
      entityType: 'sale_return',
      entityId: returnId,
      reason: 'voided',
      userId: await _currentUserId(),
    );
  }

  // ==================== SALE PAYMENTS ====================

  @override
  Stream<List<SalePaymentEntity>> watchSalePayments(int saleId) => _reader.gate(
    InventoryPostingDocument.sale,
    saleId,
    _datasource.watchSalePayments(saleId),
    <SalePaymentEntity>[],
  );

  @override
  Future<List<SalePaymentEntity>> getSalePayments(int saleId) => _reader.read(
    InventoryPostingDocument.sale,
    saleId,
    () => _datasource.getSalePayments(saleId),
    <SalePaymentEntity>[],
  );

  @override
  Future<int> recordPayment({
    required int saleId,
    required Decimal amountCents,
    required int currencyId,
    required String paymentMethod,
    String? reference,
    String? notes,
    DateTime? paymentDate,
  }) async {
    final userId = await _currentUserId();
    final cashierShiftId = await _cashierShiftService?.resolveOpenShiftId(
      userId,
    );
    final companion = db.SalePaymentsCompanion(
      saleId: Value(saleId),
      cashierShiftId: cashierShiftId != null
          ? Value(cashierShiftId)
          : const Value.absent(),
      amountCents: Value(amountCents),
      currencyId: Value(currencyId),
      paymentMethod: Value(paymentMethod),
      reference: reference != null ? Value(reference) : const Value.absent(),
      notes: notes != null ? Value(notes) : const Value.absent(),
      paymentDate: paymentDate != null
          ? Value(paymentDate)
          : Value(DateTime.now()),
    );
    // ATOMIC: Wrap payment recording (which updates customer balance)
    // and journal entry creation in a single transaction.
    final paymentId = await _dao.db.transaction(() async {
      await DocumentPostingScope.validate(
        _dao.db,
        InventoryPostingDocument.sale,
        saleId,
        scope: warehouseScope,
      );
      final source = await (_dao.db.select(
        _dao.db.sales,
      )..where((d) => d.id.equals(saleId))).getSingle();
      if (source.status != 'completed') {
        throw StateError('Payments require a posted sale');
      }
      if (cashierShiftId != null) {
        final shift = await (_dao.db.select(
          _dao.db.cashierShifts,
        )..where((s) => s.id.equals(cashierShiftId))).getSingle();
        if (shift.status != 'open' ||
            shift.currencyId != currencyId ||
            shift.cashierUserId != userId) {
          throw StateError(
            'Payment shift must be open for this cashier and currency',
          );
        }
      }
      if (source.currencyId != currencyId ||
          amountCents <= Decimal.zero ||
          Decimal.fromBigInt(amountCents.toBigInt()) != amountCents) {
        throw StateError(
          'Payment must use positive whole minor units in the invoice currency',
        );
      }
      final id = await _datasource.recordPayment(companion);

      // Post journal entry: Dr Cash/Bank, Cr Accounts Receivable
      await _journalService.recordCustomerPaymentJournalEntry(
        paymentId: id,
        amountCents: amountCents.toBigInt().toInt(),
        currencyId: currencyId,
        paymentMethod: paymentMethod,
        userId: userId,
      );

      return id;
    });

    return paymentId;
  }

  @override
  Future<void> deletePayment(int paymentId) => _dao.db.transaction(() async {
    final payment = await (_dao.db.select(
      _dao.db.salePayments,
    )..where((p) => p.id.equals(paymentId))).getSingleOrNull();
    if (payment == null) throw StateError('Payment not found');
    await DocumentPostingScope.validate(
      _dao.db,
      InventoryPostingDocument.sale,
      payment.saleId,
      scope: warehouseScope,
    );

    // Void journal entries BEFORE deleting the payment
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sale_payments',
      sourceId: paymentId,
      reason: 'Sale payment deleted',
      userId: await _currentUserId(),
    );

    await _datasource.deletePayment(paymentId);
  });

  @override
  Future<int> getReturnedQuantity(int saleItemId) => _reader.readItem(
    InventoryPostingDocument.sale,
    saleItemId,
    () => _datasource.getReturnedQuantity(saleItemId),
    0,
  );

  @override
  Future<LinkedReturnHistory> getLinkedReturnHistory(int saleItemId) =>
      _reader.readItem(
        InventoryPostingDocument.sale,
        saleItemId,
        () => _dao.getLinkedReturnHistory(saleItemId),
        LinkedReturnHistory.zero,
      );

  @override
  Stream<SaleDashboardStats> watchDashboardStats() => _reader.changes.asyncMap(
    (_) => _reader.snapshot((scope) async {
      final stats = await _dao.getDashboardStats(warehouseScope: scope);
      return SaleDashboardStats(
        totalCount: stats.totalCount,
        completedCount: stats.completedCount,
        voidedCount: stats.voidedCount,
        totalSalesCents: stats.totalSalesCents,
        returnsCount: stats.returnsCount,
        totalReturnsCents: stats.totalReturnsCents,
        todaySalesCents: stats.todaySalesCents,
        todayCount: stats.todayCount,
      );
    }),
  );

  @override
  Stream<Map<int, List<String>>> watchSaleProductSearchTerms() =>
      _datasource.watchSaleProductSearchTerms().asyncMap(
        (rows) => _reader.searchTerms(InventoryPostingDocument.sale, rows),
      );

  @override
  Stream<Map<String, List<String>>> watchSaleReturnProductSearchTerms() =>
      _datasource.watchSaleReturnProductSearchTerms().asyncMap(
        _reader.returnSearchTerms,
      );

  // ==================== PRIVATE HELPERS ====================
  //
  // Phase 6 (May 2026) — commission + loyalty arithmetic has been
  // extracted into `CommissionService` and `LoyaltyPointsService`. The
  // legacy `_createCommissionForSale`, `_reverseCommissionForReturn`,
  // `_awardLoyaltyPointsForSale`, and `_reverseLoyaltyPointsForReturn`
  // helpers that used to live here are GONE. Do not reintroduce them.
  // Any new commission/loyalty math belongs in the corresponding
  // service; this repository stays a pure consumer.

  // ────────────────────────── Phase 4 — e-invoice ──────────────────────────
  //
  // The two helpers below are the ONLY place in this repository that knows
  // anything about e-invoicing. They build an [EInvoiceSubject] snapshot
  // from the freshly-posted sale/return and hand it to the dispatcher.
  // All jurisdiction routing, chain context (ICV/PIH), signing and
  // submission live behind [EInvoiceDispatchService] — keeping the
  // accounting path free of country-specific logic.

  Future<void> _dispatchSaleEInvoice({
    required int saleId,
    int? customerId,
    required int currencyId,
    required int subtotalCents,
    required int taxCents,
    required int totalCents,
    required DateTime issueDate,
    required List<SaleItemInput> items,
  }) async {
    final dispatcher = _einvoiceDispatch;
    if (dispatcher == null) return;
    try {
      final sale = await _dao.getSaleById(saleId);
      final subject = EInvoiceSubject(
        sourceTable: 'sales',
        sourceId: saleId,
        documentNumber: sale?.invoiceNumber ?? 'SALE-$saleId',
        documentType: 'invoice',
        subtotalCents: subtotalCents,
        taxCents: taxCents,
        totalCents: totalCents,
        currencyId: currencyId,
        issueDate: issueDate,
        lines: items
            .map(
              (i) => <String, Object?>{
                'productId': i.productId,
                'variantId': i.variantId,
                'quantity': i.quantity,
                'unitPriceCents': i.unitPriceCents.toBigInt().toInt(),
                'discountCents': i.discountCents.toBigInt().toInt(),
                'taxCents': i.taxCents.toBigInt().toInt(),
                'totalCents': i.totalCents.toBigInt().toInt(),
              },
            )
            .toList(growable: false),
      );
      await dispatcher.dispatch(subject);
    } catch (e, st) {
      // E-invoicing must NEVER break a posted sale.
      developer.log(
        'E-invoice dispatch failed for sale #$saleId: $e',
        name: 'SaleRepository',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _dispatchSaleReturnEInvoice({
    required String sourceTable,
    required int returnId,
    int? customerId,
    required int currencyId,
    required int subtotalCents,
    required int taxCents,
    required int totalCents,
    required DateTime issueDate,
    required List<SaleReturnItemInput> items,
    String? originalInvoiceNumber,
  }) async {
    final dispatcher = _einvoiceDispatch;
    if (dispatcher == null) return;
    try {
      final subject = EInvoiceSubject(
        sourceTable: sourceTable,
        sourceId: returnId,
        documentNumber: 'CN-$returnId',
        documentType: 'credit_note',
        subtotalCents: subtotalCents,
        taxCents: taxCents,
        totalCents: totalCents,
        currencyId: currencyId,
        issueDate: issueDate,
        lines: items
            .map(
              (i) => <String, Object?>{
                'saleItemId': i.saleItemId,
                'quantity': i.quantity,
                'subtotalCents': i.subtotalCents.toBigInt().toInt(),
                'discountCents': i.discountCents.toBigInt().toInt(),
                'taxCents': i.taxCents.toBigInt().toInt(),
                'refundCents': i.refundCents.toBigInt().toInt(),
              },
            )
            .toList(growable: false),
        originalInvoiceNumber: originalInvoiceNumber,
      );
      await dispatcher.dispatch(subject);
    } catch (e, st) {
      developer.log(
        'E-invoice dispatch failed for return #$returnId: $e',
        name: 'SaleRepository',
        error: e,
        stackTrace: st,
      );
    }
  }
}
