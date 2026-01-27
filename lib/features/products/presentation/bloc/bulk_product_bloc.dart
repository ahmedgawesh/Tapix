import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/product_variant_repository.dart';

part 'bulk_product_event.dart';
part 'bulk_product_state.dart';

class BulkProductBloc extends Bloc<BulkProductEvent, BulkProductState> {
  final ProductRepository _repository;
  final ProductVariantRepository _variantRepository;

  BulkProductBloc(this._repository, this._variantRepository) : super(BulkProductInitial()) {
    on<BulkProductRowAdded>(_onRowAdded);
    on<BulkProductRowRemoved>(_onRowRemoved);
    on<BulkProductRowUpdated>(_onRowUpdated);
    on<BulkProductValidationRequested>(_onValidationRequested);
    on<BulkProductSubmitRequested>(_onSubmitRequested);
    on<BulkProductReset>(_onReset);
  }

  void _onRowAdded(
    BulkProductRowAdded event,
    Emitter<BulkProductState> emit,
  ) {
    final currentState = state;
    List<BulkProductRowData> currentRows;
    Map<int, List<String>> currentErrors;

    if (currentState is BulkProductEditing) {
      currentRows = List.from(currentState.rows);
      currentErrors = Map.from(currentState.validationErrors);
    } else {
      currentRows = [BulkProductRowData.empty(0)];
      currentErrors = {};
    }

    final newRowIndex = currentRows.isEmpty ? 0 : currentRows.length;
    currentRows.add(BulkProductRowData.empty(newRowIndex));

    emit(BulkProductEditing(
      rows: currentRows,
      validationErrors: currentErrors,
    ));
  }

  void _onRowRemoved(
    BulkProductRowRemoved event,
    Emitter<BulkProductState> emit,
  ) {
    final currentState = state;
    if (currentState is! BulkProductEditing) return;
    if (currentState.rows.length <= 1) return;

    final updatedRows = List<BulkProductRowData>.from(currentState.rows);
    updatedRows.removeAt(event.rowIndex);

    final reindexedRows = updatedRows.asMap().entries.map((entry) {
      return entry.value.copyWith(rowIndex: entry.key);
    }).toList();

    final updatedErrors = <int, List<String>>{};
    currentState.validationErrors.forEach((key, value) {
      if (key < event.rowIndex) {
        updatedErrors[key] = value;
      } else if (key > event.rowIndex) {
        updatedErrors[key - 1] = value;
      }
    });

    emit(BulkProductEditing(
      rows: reindexedRows,
      validationErrors: updatedErrors,
    ));
  }

  void _onRowUpdated(
    BulkProductRowUpdated event,
    Emitter<BulkProductState> emit,
  ) {
    final currentState = state;
    if (currentState is! BulkProductEditing) return;

    final updatedRows = List<BulkProductRowData>.from(currentState.rows);
    if (event.rowIndex >= updatedRows.length) return;

    final currentRow = updatedRows[event.rowIndex];
    updatedRows[event.rowIndex] = currentRow.copyWith(
      name: event.name,
      nameAr: event.nameAr,
      nameFr: event.nameFr,
      sku: event.sku,
      barcode: event.barcode,
      costCents: event.costCents,
      priceCents: event.priceCents,
      wholesalePriceCents: event.wholesalePriceCents,
      stockQuantity: event.stockQuantity,
      minQuantity: event.minQuantity,
      categoryId: event.categoryId,
      colorId: event.colorId,
      sizeId: event.sizeId,
      hasVariants: event.hasVariants,
      isTaxable: event.isTaxable,
      taxRateBps: event.taxRateBps,
    );

    final updatedErrors = Map<int, List<String>>.from(currentState.validationErrors);
    updatedErrors.remove(event.rowIndex);

    emit(BulkProductEditing(
      rows: updatedRows,
      validationErrors: updatedErrors,
    ));
  }

  Future<void> _onValidationRequested(
    BulkProductValidationRequested event,
    Emitter<BulkProductState> emit,
  ) async {
    final currentState = state;
    if (currentState is! BulkProductEditing) return;

    final validationErrors = <int, List<String>>{};
    final skuSet = <String>{};

    for (int i = 0; i < currentState.rows.length; i++) {
      final row = currentState.rows[i];
      final errors = <String>[];

      if (row.name.trim().isEmpty) {
        errors.add('name_required');
      }

      if (row.priceCents <= Decimal.zero) {
        errors.add('price_required');
      }

      if (row.costCents < Decimal.zero) {
        errors.add('cost_invalid');
      }

      if (row.sku != null && row.sku!.isNotEmpty) {
        if (skuSet.contains(row.sku)) {
          errors.add('sku_duplicate');
        } else {
          skuSet.add(row.sku!);
          
          // Check database for existing SKU
          try {
            final existingProduct = await _repository.findBySku(row.sku!);
            if (existingProduct != null) {
              errors.add('sku_exists_in_database');
            }
          } catch (e) {
            debugPrint('SKU validation error: $e');
          }
        }
      }

      if (errors.isNotEmpty) {
        validationErrors[i] = errors;
      }
    }

    emit(BulkProductEditing(
      rows: currentState.rows,
      validationErrors: validationErrors,
    ));
  }

  Future<void> _onSubmitRequested(
    BulkProductSubmitRequested event,
    Emitter<BulkProductState> emit,
  ) async {
    final currentState = state;
    if (currentState is! BulkProductEditing) return;

    // Perform inline validation
    final validationErrors = <int, List<String>>{};
    final skuSet = <String>{};

    for (int i = 0; i < currentState.rows.length; i++) {
      final row = currentState.rows[i];
      final errors = <String>[];

      if (row.name.trim().isEmpty) {
        errors.add('name_required');
      }

      if (row.priceCents <= Decimal.zero) {
        errors.add('price_required');
      }

      if (row.costCents < Decimal.zero) {
        errors.add('cost_invalid');
      }

      if (row.sku != null && row.sku!.isNotEmpty) {
        if (skuSet.contains(row.sku)) {
          errors.add('sku_duplicate');
        } else {
          skuSet.add(row.sku!);
          
          try {
            final existingProduct = await _repository.findBySku(row.sku!);
            if (existingProduct != null) {
              errors.add('sku_exists_in_database');
            }
          } catch (e) {
            debugPrint('SKU validation error: $e');
          }
        }
      }

      if (errors.isNotEmpty) {
        validationErrors[i] = errors;
      }
    }

    if (validationErrors.isNotEmpty) {
      emit(BulkProductEditing(
        rows: currentState.rows,
        validationErrors: validationErrors,
      ));
      return;
    }

    final totalCount = currentState.rows.length;

    emit(BulkProductSubmitting(
      totalCount: totalCount,
      currentIndex: 0,
      rows: currentState.rows,
    ));

    try {
      final bulkData = currentState.rows.map((row) => BulkProductData(
        rowIndex: row.rowIndex,
        name: row.name,
        nameAr: row.nameAr,
        nameFr: row.nameFr,
        sku: row.sku,
        barcode: row.barcode,
        costCents: row.costCents,
        priceCents: row.priceCents,
        wholesalePriceCents: row.wholesalePriceCents,
        stockQuantity: row.stockQuantity,
        minQuantity: row.minQuantity,
        categoryId: row.categoryId,
        hasVariants: row.hasVariants,
        isTaxable: row.isTaxable,
        taxRateBps: row.taxRateBps,
      )).toList();

      final results = await _repository.bulkCreateProducts(bulkData);
      
      debugPrint('BulkProductBloc: Created ${results.length} products in transaction');

      for (final entry in results.entries) {
        final rowIndex = entry.key;
        final productId = entry.value;
        final row = currentState.rows.firstWhere((r) => r.rowIndex == rowIndex);

        if (row.colorId != null || row.sizeId != null) {
          await _variantRepository.createVariant(
            productId: productId,
            colorId: row.colorId,
            sizeId: row.sizeId,
            costCents: row.costCents,
            priceCents: row.priceCents,
            stockQuantity: row.stockQuantity,
          );
        } else if (!row.hasVariants) {
          await _variantRepository.ensureDefaultVariantForProduct(
            productId: productId,
            costCents: row.costCents,
            priceCents: row.priceCents,
            stockQuantity: row.stockQuantity,
          );

          final defaultVariant = await _variantRepository.getDefaultVariantByProduct(productId);
          if (defaultVariant != null) {
            final updated = defaultVariant.copyWith(
              sku: (row.sku?.trim().isNotEmpty ?? false) ? row.sku : null,
              barcode: (row.barcode?.trim().isNotEmpty ?? false) ? row.barcode : null,
              costCents: row.costCents,
              priceCents: row.priceCents,
              stockQuantity: row.stockQuantity,
              colorId: null,
              sizeId: null,
            );
            await _variantRepository.updateVariant(updated);
          }
        }
      }

      emit(BulkProductSuccess(
        successCount: results.length,
        totalCount: totalCount,
      ));
    } catch (e) {
      debugPrint('BulkProductBloc: Bulk create failed: $e');
      emit(BulkProductError(
        message: e.toString(),
        failedRows: {0: e.toString()},
        successCount: 0,
        totalCount: totalCount,
      ));
    }
  }

  void _onReset(
    BulkProductReset event,
    Emitter<BulkProductState> emit,
  ) {
    emit(BulkProductEditing(
      rows: [BulkProductRowData.empty(0)],
      validationErrors: const {},
    ));
  }
}
