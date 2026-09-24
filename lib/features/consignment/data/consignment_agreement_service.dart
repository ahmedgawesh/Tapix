import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import 'consignment_module_service.dart';

class ConsignmentAgreementTermInput {
  const ConsignmentAgreementTermInput.fixedCost({
    required this.productId,
    this.variantId,
    required int amountCents,
  }) : settlementBasis = 'fixed_unit_cost',
       unitCostCents = amountCents,
       supplierShareBps = null,
       includeLineDiscount = true,
       includeInvoiceDiscount = true,
       includeSalesTax = false;

  const ConsignmentAgreementTermInput.salesPercentage({
    required this.productId,
    this.variantId,
    required int shareBps,
    this.includeLineDiscount = true,
    this.includeInvoiceDiscount = true,
    this.includeSalesTax = false,
  }) : settlementBasis = 'net_sales_percentage',
       unitCostCents = null,
       supplierShareBps = shareBps;

  final int productId;
  final int? variantId;
  final String settlementBasis;
  final int? unitCostCents;
  final int? supplierShareBps;
  final bool includeLineDiscount;
  final bool includeInvoiceDiscount;
  final bool includeSalesTax;
}

class ResolvedConsignmentTerm {
  const ResolvedConsignmentTerm({required this.agreement, required this.term});

  final ConsignmentAgreement agreement;
  final ConsignmentAgreementItem term;
}

/// CRUD for immutable, versioned commercial terms. It deliberately has no
/// stock, supplier-balance, journal or settlement writer.
class ConsignmentAgreementService {
  ConsignmentAgreementService(this._db, this._module);

  final AppDatabase _db;
  final ConsignmentModuleService _module;

  static const _frequencies = {
    'immediate',
    'daily',
    'weekly',
    'monthly',
    'manual',
  };

  /// Creates the first supplier agreement, or a new revision when an active
  /// agreement already exists in the same branch and currency.
  Future<ConsignmentAgreement> createDraftOrRevision({
    required int supplierId,
    required int currencyId,
    required String agreementNumber,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    String settlementFrequency = 'monthly',
    int paymentTermsDays = 0,
    int settlementTaxRateBps = 0,
    bool settlementTaxInclusive = false,
    String notes = '',
    required List<ConsignmentAgreementTermInput> terms,
  }) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    final active =
        await (_db.select(_db.consignmentAgreements)..where(
              (agreement) =>
                  agreement.organizationId.equals(access.scope.organizationId) &
                  agreement.branchId.equals(access.scope.branchId) &
                  agreement.databaseId.equals(access.scope.databaseId) &
                  agreement.supplierId.equals(supplierId) &
                  agreement.currencyId.equals(currencyId) &
                  agreement.status.equals('active'),
            ))
            .getSingleOrNull();
    if (active == null) {
      return createDraft(
        supplierId: supplierId,
        currencyId: currencyId,
        agreementNumber: agreementNumber,
        effectiveFrom: effectiveFrom,
        effectiveTo: effectiveTo,
        settlementFrequency: settlementFrequency,
        paymentTermsDays: paymentTermsDays,
        settlementTaxRateBps: settlementTaxRateBps,
        settlementTaxInclusive: settlementTaxInclusive,
        notes: notes,
        terms: terms,
      );
    }
    final currentTerms = await (_db.select(
      _db.consignmentAgreementItems,
    )..where((item) => item.agreementId.equals(active.id))).get();
    final mergedTerms = <(int, int?), ConsignmentAgreementTermInput>{
      for (final item in currentTerms)
        (item.productId, item.variantId): _toInput(item),
    };
    for (final term in terms) {
      mergedTerms[(term.productId, term.variantId)] = term;
    }
    return revise(
      activeAgreementId: active.id,
      agreementNumber: agreementNumber,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
      settlementFrequency: settlementFrequency,
      paymentTermsDays: paymentTermsDays,
      settlementTaxRateBps: settlementTaxRateBps,
      settlementTaxInclusive: settlementTaxInclusive,
      notes: notes,
      terms: mergedTerms.values.toList(growable: false),
    );
  });

  Future<ConsignmentAgreement> createDraft({
    required int supplierId,
    required int currencyId,
    required String agreementNumber,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    String settlementFrequency = 'monthly',
    int paymentTermsDays = 0,
    int settlementTaxRateBps = 0,
    bool settlementTaxInclusive = false,
    String notes = '',
    required List<ConsignmentAgreementTermInput> terms,
  }) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    final number = agreementNumber.trim();
    final cleanNotes = notes.trim();
    _validateHeader(
      number: number,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
      frequency: settlementFrequency,
      paymentTermsDays: paymentTermsDays,
      settlementTaxRateBps: settlementTaxRateBps,
      notes: cleanNotes,
    );
    if (terms.isEmpty || terms.length > 500) {
      throw ArgumentError('An agreement requires 1 to 500 product terms.');
    }
    await _validateSupplierCurrency(
      supplierId: supplierId,
      currencyId: currencyId,
    );

    final id = const Uuid().v4();
    await _db
        .into(_db.consignmentAgreements)
        .insert(
          ConsignmentAgreementsCompanion.insert(
            id: id,
            agreementKey: const Uuid().v4(),
            organizationId: access.scope.organizationId,
            branchId: access.scope.branchId,
            databaseId: access.scope.databaseId,
            supplierId: supplierId,
            currencyId: currencyId,
            agreementNumber: number,
            effectiveFrom: effectiveFrom.toUtc(),
            effectiveTo: Value(effectiveTo?.toUtc()),
            settlementFrequency: Value(settlementFrequency),
            paymentTermsDays: Value(paymentTermsDays),
            settlementTaxRateBps: Value(settlementTaxRateBps),
            settlementTaxInclusive: Value(settlementTaxInclusive),
            notes: Value(cleanNotes),
            createdBy: access.actorId,
          ),
        );
    await _insertTerms(id, terms);
    return (_db.select(
      _db.consignmentAgreements,
    )..where((a) => a.id.equals(id))).getSingle();
  });

  Future<ConsignmentAgreement> revise({
    required String activeAgreementId,
    required String agreementNumber,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    String? settlementFrequency,
    int? paymentTermsDays,
    int? settlementTaxRateBps,
    bool? settlementTaxInclusive,
    String? notes,
    List<ConsignmentAgreementTermInput>? terms,
  }) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    final active =
        await (_db.select(_db.consignmentAgreements)..where(
              (a) => a.id.equals(activeAgreementId) & a.status.equals('active'),
            ))
            .getSingle();

    final nextNumber = agreementNumber.trim();
    final nextFrequency = settlementFrequency ?? active.settlementFrequency;
    final nextTermsDays = paymentTermsDays ?? active.paymentTermsDays;
    final nextTaxRateBps = settlementTaxRateBps ?? active.settlementTaxRateBps;
    final nextTaxInclusive =
        settlementTaxInclusive ?? active.settlementTaxInclusive;
    final nextNotes = (notes ?? active.notes).trim();
    _validateHeader(
      number: nextNumber,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
      frequency: nextFrequency,
      paymentTermsDays: nextTermsDays,
      settlementTaxRateBps: nextTaxRateBps,
      notes: nextNotes,
    );

    final inputs =
        terms ??
        (await (_db.select(
              _db.consignmentAgreementItems,
            )..where((i) => i.agreementId.equals(active.id))).get())
            .map(_toInput)
            .toList();
    if (inputs.isEmpty || inputs.length > 500) {
      throw StateError('An agreement revision requires product terms.');
    }

    final id = const Uuid().v4();
    await _db
        .into(_db.consignmentAgreements)
        .insert(
          ConsignmentAgreementsCompanion.insert(
            id: id,
            agreementKey: active.agreementKey,
            revision: Value(active.revision + 1),
            organizationId: access.scope.organizationId,
            branchId: access.scope.branchId,
            databaseId: access.scope.databaseId,
            supplierId: active.supplierId,
            currencyId: active.currencyId,
            agreementNumber: nextNumber,
            effectiveFrom: effectiveFrom.toUtc(),
            effectiveTo: Value(effectiveTo?.toUtc()),
            settlementFrequency: Value(nextFrequency),
            paymentTermsDays: Value(nextTermsDays),
            settlementTaxRateBps: Value(nextTaxRateBps),
            settlementTaxInclusive: Value(nextTaxInclusive),
            notes: Value(nextNotes),
            createdBy: access.actorId,
          ),
        );
    await _insertTerms(id, inputs);
    return (_db.select(
      _db.consignmentAgreements,
    )..where((a) => a.id.equals(id))).getSingle();
  });

  Future<void> replaceDraftTerms(
    String agreementId,
    List<ConsignmentAgreementTermInput> terms,
  ) => _db.transaction(() async {
    await _module.requireManageAccess();
    if (terms.isEmpty || terms.length > 500) {
      throw ArgumentError('An agreement requires 1 to 500 product terms.');
    }
    final draft =
        await (_db.select(_db.consignmentAgreements)..where(
              (a) => a.id.equals(agreementId) & a.status.equals('draft'),
            ))
            .getSingle();
    await (_db.delete(
      _db.consignmentAgreementItems,
    )..where((i) => i.agreementId.equals(draft.id))).go();
    await _insertTerms(draft.id, terms);
  });

  Future<ConsignmentAgreement> activate(
    String agreementId,
  ) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    final draft =
        await (_db.select(_db.consignmentAgreements)..where(
              (a) => a.id.equals(agreementId) & a.status.equals('draft'),
            ))
            .getSingle();

    final now = DateTime.now().toUtc();
    if (draft.effectiveFrom.toUtc().isAfter(now)) {
      throw StateError(
        'A future agreement revision cannot be activated before its effective date.',
      );
    }

    final current =
        await (_db.select(_db.consignmentAgreements)..where(
              (a) =>
                  a.branchId.equals(draft.branchId) &
                  a.supplierId.equals(draft.supplierId) &
                  a.currencyId.equals(draft.currencyId) &
                  a.status.equals('active'),
            ))
            .getSingleOrNull();
    if (current != null) {
      if (current.agreementKey != draft.agreementKey ||
          draft.revision != current.revision + 1) {
        throw StateError(
          'Activate a revision of the current supplier agreement.',
        );
      }
      await (_db.update(
        _db.consignmentAgreements,
      )..where((a) => a.id.equals(current.id))).write(
        ConsignmentAgreementsCompanion(
          status: const Value('superseded'),
          endedBy: Value(access.actorId),
          endedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    } else if (draft.revision != 1) {
      throw StateError('The previous agreement revision is not active.');
    }

    await (_db.update(
      _db.consignmentAgreements,
    )..where((a) => a.id.equals(draft.id))).write(
      ConsignmentAgreementsCompanion(
        status: const Value('active'),
        activatedBy: Value(access.actorId),
        activatedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return (_db.select(
      _db.consignmentAgreements,
    )..where((a) => a.id.equals(draft.id))).getSingle();
  });

  Future<void> close(String agreementId) => _db.transaction(() async {
    final access = await _module.requireHistoricalManageAccess();
    final now = DateTime.now().toUtc();
    final changed =
        await (_db.update(_db.consignmentAgreements)..where(
              (a) => a.id.equals(agreementId) & a.status.equals('active'),
            ))
            .write(
              ConsignmentAgreementsCompanion(
                status: const Value('closed'),
                endedBy: Value(access.actorId),
                endedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
    if (changed != 1) throw StateError('Active agreement not found.');
  });

  Future<void> setSupplierDefaultMode(int supplierId, String mode) =>
      _db.transaction(() async {
        if (!{'standard', 'consignment', 'mixed'}.contains(mode)) {
          throw ArgumentError('Invalid supplier supply mode.');
        }
        if (mode == 'standard') {
          await _module.requireRoleAccess();
        } else {
          await _module.requireManageAccess();
        }
        final changed =
            await (_db.update(
              _db.suppliers,
            )..where((s) => s.id.equals(supplierId))).write(
              SuppliersCompanion(
                defaultSupplyMode: Value(mode),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
        if (changed != 1) throw StateError('Supplier not found.');
      });

  Future<ResolvedConsignmentTerm?> resolveActiveTerm({
    required int supplierId,
    required int currencyId,
    required int productId,
    required int variantId,
    required DateTime at,
  }) => _db.transaction(() async {
    await _module.requireManageAccess();
    // Drift's typed SQLite DateTime comparison can use a numeric encoded
    // value while databases upgraded from older releases contain canonical ISO
    // text. Read the small set of active candidates and compare UTC instants in
    // Dart so both storage generations follow the same effective-date rule.
    final candidates =
        await (_db.select(_db.consignmentAgreements)..where(
              (a) =>
                  a.supplierId.equals(supplierId) &
                  a.currencyId.equals(currencyId) &
                  a.status.equals('active'),
            ))
            .get();
    final instant = at.toUtc();
    final effective = candidates.where((row) {
      final starts = row.effectiveFrom.toUtc();
      final ends = row.effectiveTo?.toUtc();
      return !starts.isAfter(instant) &&
          (ends == null || !ends.isBefore(instant));
    }).toList();
    if (effective.length > 1) {
      throw StateError('More than one active consignment agreement applies.');
    }
    final agreement = effective.singleOrNull;
    if (agreement == null) return null;
    final term =
        await (_db.select(_db.consignmentAgreementItems)..where(
              (i) =>
                  i.agreementId.equals(agreement.id) &
                  i.productId.equals(productId) &
                  (i.variantId.equals(variantId) | i.variantId.isNull()),
            ))
            .getSingleOrNull();
    return term == null
        ? null
        : ResolvedConsignmentTerm(agreement: agreement, term: term);
  });

  Future<void> _validateSupplierCurrency({
    required int supplierId,
    required int currencyId,
  }) async {
    final supplier = await (_db.select(
      _db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingleOrNull();
    if (supplier == null || !supplier.isActive) {
      throw StateError('A consignment agreement requires an active supplier.');
    }
    if (supplier.currencyId != currencyId) {
      throw StateError('Consignment agreement currency must match supplier.');
    }
  }

  void _validateHeader({
    required String number,
    required DateTime effectiveFrom,
    required DateTime? effectiveTo,
    required String frequency,
    required int paymentTermsDays,
    required int settlementTaxRateBps,
    required String notes,
  }) {
    if (number.isEmpty || number.length > 64) {
      throw ArgumentError('Agreement number is required.');
    }
    if (!_frequencies.contains(frequency)) {
      throw ArgumentError('Invalid settlement frequency.');
    }
    if (effectiveTo != null && effectiveTo.isBefore(effectiveFrom)) {
      throw ArgumentError('Agreement end precedes its start.');
    }
    if (paymentTermsDays < 0 || paymentTermsDays > 3650) {
      throw ArgumentError('Invalid payment terms.');
    }
    if (settlementTaxRateBps < 0 || settlementTaxRateBps > 10000) {
      throw ArgumentError('Invalid settlement tax rate.');
    }
    if (notes.length > 2000) throw ArgumentError('Agreement notes too long.');
  }

  Future<void> _insertTerms(
    String agreementId,
    List<ConsignmentAgreementTermInput> terms,
  ) async {
    final agreement = await (_db.select(
      _db.consignmentAgreements,
    )..where((row) => row.id.equals(agreementId))).getSingle();
    final supplier = await (_db.select(
      _db.suppliers,
    )..where((row) => row.id.equals(agreement.supplierId))).getSingle();
    if (!supplier.isActive) {
      throw StateError('A consignment agreement requires an active supplier.');
    }
    if (supplier.currencyId != agreement.currencyId) {
      throw StateError('Consignment agreement currency must match supplier.');
    }

    final exactKeys = <String>{};
    final allVariantProducts = <int>{};
    final specificVariantProducts = <int>{};
    for (final term in terms) {
      if (term.productId <= 0 ||
          (term.variantId != null && term.variantId! <= 0)) {
        throw ArgumentError('Invalid consignment product term.');
      }
      if (term.settlementBasis == 'fixed_unit_cost') {
        if (term.unitCostCents == null ||
            term.unitCostCents! < 0 ||
            term.supplierShareBps != null) {
          throw ArgumentError('Invalid fixed-cost consignment term.');
        }
      } else if (term.settlementBasis == 'net_sales_percentage') {
        if (term.unitCostCents != null ||
            term.supplierShareBps == null ||
            term.supplierShareBps! < 0 ||
            term.supplierShareBps! > 10000) {
          throw ArgumentError('Invalid percentage consignment term.');
        }
      } else {
        throw ArgumentError('Invalid consignment settlement basis.');
      }

      final product = await (_db.select(
        _db.products,
      )..where((row) => row.id.equals(term.productId))).getSingleOrNull();
      if (product == null || !product.trackInventory) {
        throw StateError(
          'A consignment term requires an inventory-tracked product.',
        );
      }
      if (product.currencyId != agreement.currencyId) {
        throw StateError(
          'Consignment product currency differs from agreement.',
        );
      }
      if (term.variantId != null) {
        final variant =
            await (_db.select(_db.productVariants)..where(
                  (row) =>
                      row.id.equals(term.variantId!) &
                      row.productId.equals(term.productId),
                ))
                .getSingleOrNull();
        if (variant == null) {
          throw StateError('Consignment variant does not belong to product.');
        }
      }

      final key = '${term.productId}:${term.variantId ?? '*'}';
      if (!exactKeys.add(key)) {
        throw ArgumentError('Duplicate consignment product term.');
      }
      if (term.variantId == null) {
        if (specificVariantProducts.contains(term.productId)) {
          throw ArgumentError(
            'An all-variants term cannot overlap variant-specific terms.',
          );
        }
        allVariantProducts.add(term.productId);
      } else {
        if (allVariantProducts.contains(term.productId)) {
          throw ArgumentError(
            'A variant-specific term cannot overlap an all-variants term.',
          );
        }
        specificVariantProducts.add(term.productId);
      }

      await _db
          .into(_db.consignmentAgreementItems)
          .insert(
            ConsignmentAgreementItemsCompanion.insert(
              id: const Uuid().v4(),
              agreementId: agreementId,
              productId: term.productId,
              variantId: Value(term.variantId),
              settlementBasis: term.settlementBasis,
              unitCostCents: Value(term.unitCostCents),
              supplierShareBps: Value(term.supplierShareBps),
              includeLineDiscount: Value(term.includeLineDiscount),
              includeInvoiceDiscount: Value(term.includeInvoiceDiscount),
              includeSalesTax: Value(term.includeSalesTax),
            ),
          );
    }
  }

  ConsignmentAgreementTermInput _toInput(ConsignmentAgreementItem item) {
    if (item.settlementBasis == 'fixed_unit_cost') {
      return ConsignmentAgreementTermInput.fixedCost(
        productId: item.productId,
        variantId: item.variantId,
        amountCents: item.unitCostCents!,
      );
    }
    return ConsignmentAgreementTermInput.salesPercentage(
      productId: item.productId,
      variantId: item.variantId,
      shareBps: item.supplierShareBps!,
      includeLineDiscount: item.includeLineDiscount,
      includeInvoiceDiscount: item.includeInvoiceDiscount,
      includeSalesTax: item.includeSalesTax,
    );
  }
}
