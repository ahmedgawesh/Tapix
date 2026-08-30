import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../barcode/services/barcode_generation_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/free_quota_service.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/database/daos/pharmacy_dao.dart';
import '../../../../core/services/pharmacy/medicine_normalization_service.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/product_variant_repository.dart';

// Events
abstract class ProductFormEvent extends Equatable {
  const ProductFormEvent();

  @override
  List<Object?> get props => [];
}

class ProductFormInitialized extends ProductFormEvent {
  final int? productId;
  final String? initialBarcode;
  // Global inventory settings for new products
  final bool defaultTrackInventory;
  final int defaultMinQuantity;
  final bool enablePharmacyFeatures;

  const ProductFormInitialized({
    this.productId,
    this.initialBarcode,
    this.defaultTrackInventory = true,
    this.defaultMinQuantity = 0,
    this.enablePharmacyFeatures = false,
  });

  @override
  List<Object?> get props => [
    productId,
    initialBarcode,
    defaultTrackInventory,
    defaultMinQuantity,
    enablePharmacyFeatures,
  ];
}

class ProductFormFieldChanged extends ProductFormEvent {
  final String field;
  final dynamic value;

  const ProductFormFieldChanged({required this.field, required this.value});

  @override
  List<Object?> get props => [field, value];
}

class ProductFormSubmitted extends ProductFormEvent {
  const ProductFormSubmitted();
}

class ProductFormValidationRequested extends ProductFormEvent {
  const ProductFormValidationRequested();
}

// State
class ProductFormState extends Equatable {
  final bool isLoading;
  final bool isSubmitting;
  final bool isEditing;
  final int? productId;
  final String? error;
  final bool isSuccess;

  // Form fields
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? description;
  final String? sku;
  final String? barcode;
  final Decimal costCents;
  final Decimal priceCents;
  final Decimal? wholesalePriceCents;
  final int stockQuantity;
  final int minQuantity;
  final int? categoryId;
  final int? supplierId;
  final int? currencyId;
  final String? imagePath;
  final bool hasVariants;
  final bool isTaxable;
  final int purchaseTaxRateBps;
  final int salesTaxRateBps;
  final bool isActive;
  final bool trackInventory;
  final String measurementType;

  // Optional pharmacy profile. It belongs to the parent product, never to a
  // colour/size/package variant.
  final bool pharmacyEditorEnabled;
  final bool isMedicine;
  final String medicineDosageForm;
  final String medicineRoute;
  final bool medicineSubstitutionEligible;
  final String medicineNotes;
  final List<MedicineIngredientDraft> medicineIngredients;

  /// `null` when [inventoryTrackingType] is editable, otherwise one of:
  ///   - `'has_stock'`        → on-hand stock > 0 prevents the change.
  ///   - `'has_consumptions'` → at least one batch consumption exists.
  /// Computed in `_onInitialized` for existing products.
  ///
  /// The legacy name is preserved (`costingMethodLockReason`) because the DAO
  /// surface — `getCostingMethodLockReason` — pre-dates Phase B; the lock
  /// itself now governs `inventoryTrackingType` in the UI. Phase F removed
  /// the per-product FIFO/WAC selector; the underlying `costing_method`
  /// column is mirrored automatically by `setInventoryTrackingType`.
  final String? costingMethodLockReason;

  /// Per-product inventory tracking type — Layer 2 of the two-layer inventory
  /// architecture. One of `'standard'` (default) | `'batch'` | `'batch_expiry'`.
  /// Locked when [costingMethodLockReason] is non-null.
  final String inventoryTrackingType;

  final int? selectedColorId;
  final int? selectedSizeId;

  // Validation errors (block submission)
  final Map<String, String> fieldErrors;
  // Validation warnings (informational — do not block submission)
  final Map<String, String> fieldWarnings;

  ProductFormState({
    this.isLoading = false,
    this.isSubmitting = false,
    this.isEditing = false,
    this.productId,
    this.error,
    this.isSuccess = false,
    this.name = '',
    this.nameAr,
    this.nameFr,
    this.description,
    this.sku,
    this.barcode,
    Decimal? costCents,
    Decimal? priceCents,
    this.wholesalePriceCents,
    this.stockQuantity = 0,
    this.minQuantity = 0,
    this.categoryId,
    this.supplierId,
    this.currencyId,
    this.imagePath,
    this.hasVariants = false,
    this.isTaxable = false,
    this.purchaseTaxRateBps = 0,
    this.salesTaxRateBps = 0,
    this.isActive = true,
    this.trackInventory = true,
    this.measurementType = 'piece',
    this.pharmacyEditorEnabled = false,
    this.isMedicine = false,
    this.medicineDosageForm = 'tablet',
    this.medicineRoute = 'oral',
    this.medicineSubstitutionEligible = true,
    this.medicineNotes = '',
    this.medicineIngredients = const [],
    this.costingMethodLockReason,
    this.inventoryTrackingType = 'standard',
    this.selectedColorId,
    this.selectedSizeId,
    this.fieldErrors = const {},
    this.fieldWarnings = const {},
  }) : costCents = costCents ?? Decimal.zero,
       priceCents = priceCents ?? Decimal.zero;

  static final ProductFormState initial = ProductFormState();

  bool get isValid => fieldErrors.isEmpty && name.isNotEmpty;

  Decimal get margin => priceCents - costCents;

  double get marginPercent {
    if (costCents == Decimal.zero) return 0.0;
    final marginRatio = margin / costCents;
    return (marginRatio.toDouble() * 100);
  }

  ProductFormState copyWith({
    bool? isLoading,
    bool? isSubmitting,
    bool? isEditing,
    int? productId,
    String? error,
    bool? isSuccess,
    String? name,
    String? nameAr,
    String? nameFr,
    String? description,
    String? sku,
    String? barcode,
    Decimal? costCents,
    Decimal? priceCents,
    Decimal? wholesalePriceCents,
    int? stockQuantity,
    int? minQuantity,
    int? categoryId,
    int? supplierId,
    int? currencyId,
    String? imagePath,
    bool? hasVariants,
    bool? isTaxable,
    int? purchaseTaxRateBps,
    int? salesTaxRateBps,
    bool? isActive,
    bool? trackInventory,
    String? measurementType,
    bool? pharmacyEditorEnabled,
    bool? isMedicine,
    String? medicineDosageForm,
    String? medicineRoute,
    bool? medicineSubstitutionEligible,
    String? medicineNotes,
    List<MedicineIngredientDraft>? medicineIngredients,
    Object? costingMethodLockReason = _unset,
    String? inventoryTrackingType,
    int? selectedColorId,
    int? selectedSizeId,
    Map<String, String>? fieldErrors,
    Map<String, String>? fieldWarnings,
  }) {
    return ProductFormState(
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isEditing: isEditing ?? this.isEditing,
      productId: productId ?? this.productId,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      nameFr: nameFr ?? this.nameFr,
      description: description ?? this.description,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      costCents: costCents ?? this.costCents,
      priceCents: priceCents ?? this.priceCents,
      wholesalePriceCents: wholesalePriceCents ?? this.wholesalePriceCents,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minQuantity: minQuantity ?? this.minQuantity,
      categoryId: categoryId ?? this.categoryId,
      supplierId: supplierId ?? this.supplierId,
      currencyId: currencyId ?? this.currencyId,
      imagePath: imagePath ?? this.imagePath,
      hasVariants: hasVariants ?? this.hasVariants,
      isTaxable: isTaxable ?? this.isTaxable,
      purchaseTaxRateBps: purchaseTaxRateBps ?? this.purchaseTaxRateBps,
      salesTaxRateBps: salesTaxRateBps ?? this.salesTaxRateBps,
      isActive: isActive ?? this.isActive,
      trackInventory: trackInventory ?? this.trackInventory,
      measurementType: measurementType ?? this.measurementType,
      pharmacyEditorEnabled:
          pharmacyEditorEnabled ?? this.pharmacyEditorEnabled,
      isMedicine: isMedicine ?? this.isMedicine,
      medicineDosageForm: medicineDosageForm ?? this.medicineDosageForm,
      medicineRoute: medicineRoute ?? this.medicineRoute,
      medicineSubstitutionEligible:
          medicineSubstitutionEligible ?? this.medicineSubstitutionEligible,
      medicineNotes: medicineNotes ?? this.medicineNotes,
      medicineIngredients: medicineIngredients ?? this.medicineIngredients,
      costingMethodLockReason: identical(costingMethodLockReason, _unset)
          ? this.costingMethodLockReason
          : costingMethodLockReason as String?,
      inventoryTrackingType:
          inventoryTrackingType ?? this.inventoryTrackingType,
      selectedColorId: selectedColorId ?? this.selectedColorId,
      selectedSizeId: selectedSizeId ?? this.selectedSizeId,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      fieldWarnings: fieldWarnings ?? this.fieldWarnings,
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isSubmitting,
    isEditing,
    productId,
    error,
    isSuccess,
    name,
    nameAr,
    nameFr,
    description,
    sku,
    barcode,
    costCents,
    priceCents,
    wholesalePriceCents,
    stockQuantity,
    minQuantity,
    categoryId,
    supplierId,
    currencyId,
    imagePath,
    hasVariants,
    isTaxable,
    purchaseTaxRateBps,
    salesTaxRateBps,
    isActive,
    trackInventory,
    measurementType,
    pharmacyEditorEnabled,
    isMedicine,
    medicineDosageForm,
    medicineRoute,
    medicineSubstitutionEligible,
    medicineNotes,
    medicineIngredients,
    costingMethodLockReason,
    inventoryTrackingType,
    selectedColorId,
    selectedSizeId,
    fieldErrors,
    fieldWarnings,
  ];
}

/// Sentinel used by [ProductFormState.copyWith] to distinguish "caller did
/// not pass a value" from "caller passed null explicitly". Required for
/// [ProductFormState.costingMethodLockReason] which is legitimately
/// nullable (null = unlocked).
const Object _unset = Object();

// Bloc
class ProductFormBloc extends Bloc<ProductFormEvent, ProductFormState> {
  final ProductRepository _repository;
  final ProductVariantRepository _variantRepository;
  final PharmacyDao? _pharmacyDao;
  static const _medicineNormalization = MedicineNormalizationService();

  /// Tracks the value of `hasVariants` as originally loaded from the DB for
  /// the product currently being edited. Used in [_onSubmitted] to detect a
  /// true → false transition and soft-delete dimensional variants atomically.
  bool _originalHasVariants = false;

  /// Tracks the inventory tracking type as loaded from DB so `_onSubmitted`
  /// can detect a real change and route it through
  /// [ProductRepository.setInventoryTrackingType] (which enforces the lock
  /// AND atomically mirrors the legacy `costing_method` column). Cached
  /// because the form's `inventoryTrackingType` state is the *desired*
  /// value, not necessarily the persisted one.
  String _originalInventoryTrackingType = 'standard';
  String _originalMeasurementType = 'piece';
  bool _originalTrackInventory = true;

  ProductFormBloc(
    this._repository,
    this._variantRepository, [
    this._pharmacyDao,
  ]) : super(ProductFormState()) {
    on<ProductFormInitialized>(_onInitialized);
    on<ProductFormFieldChanged>(_onFieldChanged);
    on<ProductFormSubmitted>(_onSubmitted);
    on<ProductFormValidationRequested>(_onValidationRequested);
  }

  Future<void> _onInitialized(
    ProductFormInitialized event,
    Emitter<ProductFormState> emit,
  ) async {
    if (event.productId == null) {
      // New product - set initial state with barcode and global settings
      final newState = state.copyWith(
        isEditing: false,
        barcode: event.initialBarcode,
        trackInventory: event.defaultTrackInventory,
        minQuantity: event.defaultMinQuantity,
        pharmacyEditorEnabled: event.enablePharmacyFeatures,
      );
      emit(newState.copyWith(fieldWarnings: _computeWarningsFor(newState)));
      return;
    }

    emit(
      state.copyWith(
        isLoading: true,
        isEditing: true,
        productId: event.productId,
      ),
    );

    try {
      final product = await _repository.watchProduct(event.productId!).first;
      if (product != null) {
        final medicine = await _pharmacyDao?.getMedicineProfile(product.id);
        _originalHasVariants = product.hasVariants;
        _originalInventoryTrackingType = product.inventoryTrackingType;
        _originalMeasurementType = product.measurementType;
        _originalTrackInventory = product.trackInventory;
        final lockReason = await _repository.getCostingMethodLockReason(
          product.id,
        );
        final referenceCount = await _repository.countProductReferences(
          product.id,
        );
        final effectiveLockReason =
            lockReason ?? (referenceCount > 0 ? 'has_transactions' : null);
        // Display the SUPPLIER REFERENCE PRICE (gross of trade discounts)
        // rather than the IAS-2 inventory cost basis. The user-typed "آخر
        // سعر شراء" is what merchants expect to see on the product card —
        // they don't want a one-off line discount to silently re-anchor
        // the displayed cost. Fallback to `costCents` keeps legacy
        // products (no purchase posted after migration 10055) showing
        // the same value as before. On save, the original net `costCents`
        // is preserved from the DB via `_repository.updateProduct` (the
        // cost field is read-only on edit anyway), so this only affects
        // what the user sees, never what is persisted as the cost basis.
        Decimal costCents = product.lastPurchasePriceCents ?? product.costCents;
        Decimal priceCents = product.priceCents;
        int stockQuantity = product.stockQuantity;
        int? selectedColorId;
        int? selectedSizeId;

        if (!product.hasVariants) {
          final defaultVariant = await _variantRepository
              .getDefaultVariantByProduct(product.id);
          if (defaultVariant != null) {
            costCents =
                defaultVariant.lastPurchasePriceCents ??
                defaultVariant.costCents;
            priceCents = defaultVariant.priceCents;
            stockQuantity = defaultVariant.stockQuantity;
            selectedColorId = defaultVariant.colorId;
            selectedSizeId = _normalizeOptionalId(defaultVariant.sizeId);
          }
        }

        final loaded = state.copyWith(
          isLoading: false,
          error: null,
          fieldErrors: const {},
          name: product.name,
          nameAr: product.nameAr,
          nameFr: product.nameFr,
          description: product.description,
          sku: product.sku,
          barcode: product.barcode,
          costCents: costCents,
          priceCents: priceCents,
          wholesalePriceCents: product.wholesalePriceCents,
          stockQuantity: stockQuantity,
          minQuantity: product.minQuantity,
          categoryId: product.categoryId,
          supplierId: product.supplierId,
          currencyId: product.currencyId,
          imagePath: product.imagePath,
          hasVariants: product.hasVariants,
          isTaxable: product.isTaxable,
          purchaseTaxRateBps: product.purchaseTaxRateBps,
          salesTaxRateBps: product.salesTaxRateBps,
          isActive: product.isActive,
          trackInventory: product.trackInventory,
          measurementType: product.measurementType,
          pharmacyEditorEnabled:
              event.enablePharmacyFeatures || medicine != null,
          isMedicine: medicine != null,
          medicineDosageForm: medicine?.profile.dosageForm ?? 'tablet',
          medicineRoute: medicine?.profile.administrationRoute ?? 'oral',
          medicineSubstitutionEligible:
              medicine?.profile.substitutionEligible ?? true,
          medicineNotes: medicine?.profile.notes ?? '',
          medicineIngredients:
              medicine?.ingredients
                  .map(
                    (row) => MedicineIngredientDraft(
                      ingredientId: row.ingredient.id,
                      displayName:
                          row.ingredient.nameAr?.trim().isNotEmpty == true
                          ? row.ingredient.nameAr
                          : row.ingredient.canonicalName,
                      value: _medicineNormalization.editableValue(
                        row.strength.normalizedStrengthValueMicros,
                      ),
                      unit: row.strength.normalizedStrengthUnit,
                      basisValue:
                          row.strength.normalizedBasisValueMicros == null
                          ? null
                          : _medicineNormalization.editableValue(
                              row.strength.normalizedBasisValueMicros!,
                            ),
                      basisUnit: row.strength.normalizedBasisUnit,
                    ),
                  )
                  .toList() ??
              const [],
          costingMethodLockReason: effectiveLockReason,
          inventoryTrackingType: product.inventoryTrackingType,
          selectedColorId: product.hasVariants ? null : selectedColorId,
          selectedSizeId: product.hasVariants ? null : selectedSizeId,
        );
        emit(loaded.copyWith(fieldWarnings: _computeWarningsFor(loaded)));
      } else {
        emit(state.copyWith(isLoading: false, error: 'Product not found'));
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onFieldChanged(
    ProductFormFieldChanged event,
    Emitter<ProductFormState> emit,
  ) {
    final newErrors = Map<String, String>.from(state.fieldErrors);
    newErrors.remove(event.field);

    switch (event.field) {
      case 'name':
        emit(
          state.copyWith(name: event.value as String, fieldErrors: newErrors),
        );
        break;
      case 'nameAr':
        emit(
          state.copyWith(
            nameAr: event.value as String?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'nameFr':
        emit(
          state.copyWith(
            nameFr: event.value as String?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'description':
        emit(
          state.copyWith(
            description: event.value as String?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'sku':
        emit(
          state.copyWith(sku: event.value as String?, fieldErrors: newErrors),
        );
        break;
      case 'barcode':
        emit(
          state.copyWith(
            barcode: event.value as String?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'costCents':
        {
          final newCost = event.value as Decimal;
          final next = state.copyWith(
            costCents: newCost,
            fieldErrors: newErrors,
          );
          emit(next.copyWith(fieldWarnings: _computeWarningsFor(next)));
        }
        break;
      case 'priceCents':
        {
          final newPrice = event.value as Decimal;
          final next = state.copyWith(
            priceCents: newPrice,
            fieldErrors: newErrors,
          );
          emit(next.copyWith(fieldWarnings: _computeWarningsFor(next)));
        }
        break;
      case 'wholesalePriceCents':
        emit(
          state.copyWith(
            wholesalePriceCents: event.value as Decimal?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'stockQuantity':
        emit(
          state.copyWith(
            stockQuantity: event.value as int,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'minQuantity':
        emit(
          state.copyWith(
            minQuantity: event.value as int,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'categoryId':
        emit(
          state.copyWith(
            categoryId: event.value as int?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'supplierId':
        emit(
          state.copyWith(
            supplierId: event.value as int?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'currencyId':
        emit(
          state.copyWith(
            currencyId: event.value as int?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'imagePath':
        emit(
          state.copyWith(
            imagePath: event.value as String?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'hasVariants':
        final hasVariants = event.value as bool;
        emit(
          state.copyWith(
            hasVariants: hasVariants,
            selectedColorId: hasVariants ? null : state.selectedColorId,
            selectedSizeId: hasVariants ? null : state.selectedSizeId,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'isTaxable':
        emit(
          state.copyWith(
            isTaxable: event.value as bool,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'purchaseTaxRateBps':
        emit(
          state.copyWith(
            purchaseTaxRateBps: event.value as int,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'salesTaxRateBps':
        emit(
          state.copyWith(
            salesTaxRateBps: event.value as int,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'isActive':
        emit(
          state.copyWith(isActive: event.value as bool, fieldErrors: newErrors),
        );
        break;
      case 'isMedicine':
        emit(
          state.copyWith(
            isMedicine: event.value as bool,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'medicineDosageForm':
        emit(
          state.copyWith(
            medicineDosageForm: event.value as String,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'medicineRoute':
        emit(
          state.copyWith(
            medicineRoute: event.value as String,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'medicineSubstitutionEligible':
        emit(
          state.copyWith(
            medicineSubstitutionEligible: event.value as bool,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'medicineNotes':
        emit(
          state.copyWith(
            medicineNotes: event.value as String,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'medicineIngredients':
        emit(
          state.copyWith(
            medicineIngredients: List<MedicineIngredientDraft>.unmodifiable(
              event.value as List<MedicineIngredientDraft>,
            ),
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'trackInventory':
        if (state.costingMethodLockReason != null &&
            event.value as bool != state.trackInventory) {
          break;
        }
        emit(
          state.copyWith(
            trackInventory: event.value as bool,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'measurementType':
        {
          final next = MeasurementType.fromDb(event.value as String);
          final current = MeasurementType.fromDb(state.measurementType);
          if (state.costingMethodLockReason != null && next != current) {
            break;
          }
          // A unit-system change reinterprets the raw integer quantity. For
          // a new product reset opening/reorder stock explicitly instead of
          // silently turning 5 pieces into 0.005 kg (or vice versa).
          emit(
            state.copyWith(
              measurementType: next.dbValue,
              stockQuantity: next.quantityScale == current.quantityScale
                  ? state.stockQuantity
                  : 0,
              minQuantity: next.quantityScale == current.quantityScale
                  ? state.minQuantity
                  : 0,
              fieldErrors: newErrors,
            ),
          );
        }
        break;
      case 'selectedColorId':
        emit(
          state.copyWith(
            selectedColorId: event.value as int?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'selectedSizeId':
        emit(
          state.copyWith(
            selectedSizeId: event.value as int?,
            fieldErrors: newErrors,
          ),
        );
        break;
      case 'inventoryTrackingType':
        {
          final next = (event.value as String).toLowerCase();
          // Lock semantics mirror SAP B1 / Odoo: a method/category change is
          // refused once stock or batch consumptions exist for the product.
          if (state.costingMethodLockReason != null &&
              next != state.inventoryTrackingType) {
            break;
          }
          if (next != 'standard' && next != 'batch' && next != 'batch_expiry') {
            break;
          }
          // The DAO `setInventoryTrackingType` mirrors `costing_method`
          // (`standard → wac`, otherwise `fifo`) on the persisted row at
          // submit time, so we do not duplicate that mapping here.
          emit(
            state.copyWith(inventoryTrackingType: next, fieldErrors: newErrors),
          );
        }
        break;
    }
  }

  void _onValidationRequested(
    ProductFormValidationRequested event,
    Emitter<ProductFormState> emit,
  ) {
    final errors = _validate();
    final warnings = _computeWarnings();
    emit(state.copyWith(fieldErrors: errors, fieldWarnings: warnings));
  }

  /// Blocking validations only. Zero cost/price are legitimate (free samples,
  /// promos, pre-purchase products whose cost will be set on first receipt),
  /// matching the behavior of QuickBooks/Odoo/Shopify. Price below cost is
  /// surfaced as a warning via [_computeWarnings] rather than a hard error
  /// (loss-leader / clearance scenarios).
  Map<String, String> _validate() {
    final errors = <String, String>{};

    if (state.name.isEmpty) {
      errors['name'] = 'products.validation_name_required';
    }

    if (state.costCents < Decimal.zero) {
      errors['costCents'] = 'products.validation_cost_negative';
    }

    if (state.priceCents < Decimal.zero) {
      errors['priceCents'] = 'products.validation_price_negative';
    }

    if (state.stockQuantity < 0) {
      errors['stockQuantity'] = 'products.validation_stock_negative';
    }

    if (state.minQuantity < 0) {
      errors['minQuantity'] = 'products.validation_min_qty_negative';
    }

    if (state.isTaxable &&
        state.purchaseTaxRateBps <= 0 &&
        state.salesTaxRateBps <= 0) {
      errors['purchaseTaxRateBps'] = 'products.validation_tax_rate_required';
    }

    if (state.isMedicine) {
      if (state.medicineDosageForm.trim().isEmpty) {
        errors['medicineDosageForm'] =
            'pharmacy.validation.dosage_form_required';
      }
      if (state.medicineRoute.trim().isEmpty) {
        errors['medicineRoute'] = 'pharmacy.validation.route_required';
      }
      if (state.medicineIngredients.isEmpty) {
        errors['medicineIngredients'] =
            'pharmacy.validation.ingredient_required';
      } else {
        try {
          for (final ingredient in state.medicineIngredients) {
            _medicineNormalization.normalizeStrength(
              value: ingredient.value,
              unit: ingredient.unit,
              basisValue: ingredient.basisValue,
              basisUnit: ingredient.basisUnit,
            );
          }
        } on PharmacyValidationException {
          errors['medicineStrength'] = 'pharmacy.validation.strength_invalid';
        }
      }
    }

    return errors;
  }

  /// Non-blocking informational warnings shown beside fields (current state).
  Map<String, String> _computeWarnings() => _computeWarningsFor(state);

  /// Pure helper: computes warnings for an arbitrary [s]. Kept static-style to
  /// allow recomputation against a prospective state during field updates.
  Map<String, String> _computeWarningsFor(ProductFormState s) {
    final warnings = <String, String>{};

    if (s.costCents > Decimal.zero &&
        s.priceCents > Decimal.zero &&
        s.priceCents < s.costCents) {
      warnings['priceCents'] = 'products.warning_price_below_cost';
    }

    if (s.costCents == Decimal.zero) {
      warnings['costCents'] = 'products.warning_cost_zero';
    }

    if (s.priceCents == Decimal.zero) {
      warnings['priceCents'] = 'products.warning_price_zero';
    }

    return warnings;
  }

  Future<Map<String, String>> _validateNameUniqueness() async {
    final errors = <String, String>{};
    final name = state.name.trim();
    if (name.isEmpty) return errors;

    final existingProduct = await _repository.findByName(name);
    if (existingProduct != null && existingProduct.id != state.productId) {
      errors['name'] = 'products.validation_name_exists';
    }
    return errors;
  }

  int? _normalizeOptionalId(int? id) {
    if (id == null) return null;
    if (id == 0) return null;
    return id;
  }

  /// Generate a valid EAN-13 barcode via the central [BarcodeGenerationService].
  /// Kept as a thin wrapper so call-sites in this bloc stay unchanged.
  String _generateBarcode() =>
      sl<BarcodeGenerationService>().generateRandomEan13();

  Future<void> _onSubmitted(
    ProductFormSubmitted event,
    Emitter<ProductFormState> emit,
  ) async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      emit(state.copyWith(fieldErrors: errors));
      return;
    }

    emit(state.copyWith(fieldErrors: const {}, error: null));

    // Validate name uniqueness
    final nameErrors = await _validateNameUniqueness();
    if (nameErrors.isNotEmpty) {
      emit(state.copyWith(fieldErrors: {...state.fieldErrors, ...nameErrors}));
      return;
    }

    // Auto-generate barcode if empty
    String? effectiveBarcode = state.barcode;
    if (effectiveBarcode == null || effectiveBarcode.trim().isEmpty) {
      effectiveBarcode = _generateBarcode();
      emit(state.copyWith(barcode: effectiveBarcode));
    }

    // SKU + barcode uniqueness are NOT pre-checked here on purpose.
    //
    // Both fields carry a DB-level UNIQUE constraint (`products.sku`,
    // `products.barcode`, `product_variants.sku`, `product_variants.barcode`),
    // which is the only race-free authority on duplicates. A pre-check
    // would issue an extra `SELECT` round-trip that:
    //   * cannot prevent races (another writer may insert the same value
    //     between the check and the INSERT),
    //   * adds latency to every single save,
    //   * duplicates logic the DB already enforces.
    //
    // Instead we attempt the write optimistically and translate the
    // `UNIQUE constraint failed: ...` exception into a per-field error in
    // the catch block below — the standard "trust the DB" pattern used by
    // production-grade ERP/POS systems.
    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      int? savedProductId = state.productId;
      // Entire product + variant orchestration runs inside a single DB
      // transaction. If any inner operation throws (UNIQUE conflict, FK
      // violation, etc.) the whole save rolls back — the product row and
      // its default/dimensional variants never end up out of sync.
      await _repository.runInTransaction(() async {
        if (state.isEditing && state.productId != null) {
          final productId = state.productId!;
          // Ledger-controlled fields (stockQuantity, costCents) MUST NOT be
          // overwritten from the form state on edit. They are driven by
          // purchase / sale / return / inventory-adjustment documents that
          // post matching journal entries. Overwriting them here would
          // silently revert any adjustment that was posted between the form
          // being opened and submitted (e.g. a shrinkage dialog launched
          // from the same screen), leaving the general ledger credited for
          // stock that is still physically on the books. Read the current
          // values fresh from the DB and preserve them.
          final currentProduct = await _repository.getProductById(productId);
          final preservedStockQuantity =
              currentProduct?.stockQuantity ?? state.stockQuantity;
          final preservedCostCents =
              currentProduct?.costCents ?? state.costCents;

          // Unit and stock-tracking changes are semantic inventory changes,
          // not ordinary product metadata. Route them through DAO setters
          // that re-check the lock inside this same transaction, closing the
          // race where a sale/purchase is posted after the form was opened.
          if (currentProduct != null &&
              state.measurementType != currentProduct.measurementType) {
            final reason = await _repository.setMeasurementType(
              productId: productId,
              measurementType: state.measurementType,
            );
            if (reason != null) throw _CostingMethodLockedException(reason);
          }
          if (currentProduct != null &&
              state.trackInventory != currentProduct.trackInventory) {
            final reason = await _repository.setTrackInventory(
              productId: productId,
              trackInventory: state.trackInventory,
            );
            if (reason != null) throw _CostingMethodLockedException(reason);
          }
          final product = Product(
            id: productId,
            name: state.name,
            nameAr: state.nameAr,
            nameFr: state.nameFr,
            description: state.description,
            sku: state.sku,
            barcode: state.barcode,
            costCents: preservedCostCents,
            priceCents: state.priceCents,
            wholesalePriceCents: state.wholesalePriceCents,
            stockQuantity: preservedStockQuantity,
            minQuantity: state.minQuantity,
            categoryId: state.categoryId,
            supplierId: state.supplierId,
            currencyId: state.currencyId,
            imagePath: state.imagePath,
            hasVariants: state.hasVariants,
            isTaxable: state.isTaxable,
            purchaseTaxRateBps: state.purchaseTaxRateBps,
            salesTaxRateBps: state.salesTaxRateBps,
            isActive: state.isActive,
            trackInventory: state.trackInventory,
            measurementType: state.measurementType,
          );
          await _repository.updateProduct(product);

          // Persist an inventory-tracking-type change (Phase B/C) through
          // the lock-checked setter. The DAO atomically keeps the legacy
          // `costing_method` column in sync (`standard → wac`, otherwise
          // `fifo`), so a single call covers both Layer 1 and Layer 2.
          // `updateProduct` above intentionally never rewrites either of
          // these columns — mirroring the SAP B1 / Odoo separation between
          // "metadata edit" and "method change".
          if (state.inventoryTrackingType != _originalInventoryTrackingType) {
            final lockReason = await _repository.setInventoryTrackingType(
              productId: productId,
              trackingType: state.inventoryTrackingType,
            );
            if (lockReason != null) {
              // Roll the entire transaction back so the product save and
              // tracking-type change stay atomic — mirrors the rest of the
              // submit pipeline (UNIQUE / FK errors propagate the same way).
              throw _CostingMethodLockedException(lockReason);
            }
          }

          // has-variants → single-variant transition: soft-delete every
          // dimensional variant so POS, stock reports and the default
          // variant sync stay consistent. Historical invoice references
          // remain pointed at the (now inactive) variants — preserves
          // audit trail + COGS integrity.
          if (_originalHasVariants && !state.hasVariants) {
            await _variantRepository.deactivateDimensionalVariants(productId);
          }

          if (!state.hasVariants) {
            // Seed opening stock only when the default variant does not yet
            // exist (first save). Subsequent edits must NEVER re-seed stock,
            // otherwise any posted purchase/sale/adjustment since the row
            // was created would be silently overwritten.
            final existingDefault = await _variantRepository
                .getDefaultVariantByProduct(productId);
            await _variantRepository.ensureDefaultVariantForProduct(
              productId: productId,
              costCents: existingDefault?.costCents ?? state.costCents,
              priceCents: state.priceCents,
              stockQuantity:
                  existingDefault?.stockQuantity ?? state.stockQuantity,
            );

            final defaultVariant =
                existingDefault ??
                await _variantRepository.getDefaultVariantByProduct(productId);
            if (defaultVariant != null) {
              // Ledger-controlled fields (stockQuantity, costCents) are
              // preserved from the freshly-read variant row — identical
              // rationale as the product-level preservation above.
              final updated = defaultVariant.copyWith(
                sku: (state.sku?.trim().isNotEmpty ?? false) ? state.sku : null,
                barcode: (state.barcode?.trim().isNotEmpty ?? false)
                    ? state.barcode
                    : null,
                costCents: defaultVariant.costCents,
                priceCents: state.priceCents,
                stockQuantity: defaultVariant.stockQuantity,
                colorId: state.selectedColorId,
                sizeId: _normalizeOptionalId(state.selectedSizeId),
              );
              await _variantRepository.updateVariant(updated);
            }
          }
        } else {
          final createdProductId = await _repository.createProduct(
            name: state.name,
            nameAr: state.nameAr,
            nameFr: state.nameFr,
            description: state.description,
            sku: state.sku,
            barcode: state.barcode,
            costCents: state.costCents,
            priceCents: state.priceCents,
            wholesalePriceCents: state.wholesalePriceCents,
            stockQuantity: state.stockQuantity,
            minQuantity: state.minQuantity,
            categoryId: state.categoryId,
            supplierId: state.supplierId,
            currencyId: state.currencyId,
            imagePath: state.imagePath,
            hasVariants: state.hasVariants,
            isTaxable: state.isTaxable,
            purchaseTaxRateBps: state.purchaseTaxRateBps,
            salesTaxRateBps: state.salesTaxRateBps,
            isActive: state.isActive,
            trackInventory: state.trackInventory,
            measurementType: state.measurementType,
            // Mirror Layer-1 (`costing_method`) from the chosen Layer-2
            // tracking type at create-time. The DAO `createProduct` signature
            // still requires the legacy column for one release window
            // (offline-installed apps + migration backfills); a future Phase
            // can drop the parameter once that window closes.
            costingMethod: state.inventoryTrackingType == 'standard'
                ? 'wac'
                : 'fifo',
            // Layer 2: persist the user-selected tracking type in the INSERT
            // itself. Previously omitted — the DB fell back to its default
            // ('standard') and the first save silently lost the choice for
            // `batch` / `batch_expiry` selections, forcing the user to
            // reopen + re-select + re-save (which routed through
            // `setInventoryTrackingType` in the edit path).
            inventoryTrackingType: state.inventoryTrackingType,
          );
          savedProductId = createdProductId;

          if (!state.hasVariants) {
            await _variantRepository.ensureDefaultVariantForProduct(
              productId: createdProductId,
              costCents: state.costCents,
              priceCents: state.priceCents,
              stockQuantity: state.stockQuantity,
            );

            final defaultVariant = await _variantRepository
                .getDefaultVariantByProduct(createdProductId);
            if (defaultVariant != null) {
              final updated = defaultVariant.copyWith(
                sku: (state.sku?.trim().isNotEmpty ?? false) ? state.sku : null,
                barcode: (state.barcode?.trim().isNotEmpty ?? false)
                    ? state.barcode
                    : null,
                costCents: state.costCents,
                priceCents: state.priceCents,
                stockQuantity: state.stockQuantity,
                colorId: state.selectedColorId,
                sizeId: _normalizeOptionalId(state.selectedSizeId),
              );
              await _variantRepository.updateVariant(updated);
            }
          }
        }

        final medicineProductId = savedProductId;
        if (_pharmacyDao != null &&
            medicineProductId != null &&
            state.pharmacyEditorEnabled) {
          if (state.isMedicine) {
            await _pharmacyDao.saveMedicineProfile(
              MedicineProfileDraft(
                productId: medicineProductId,
                dosageForm: state.medicineDosageForm,
                administrationRoute: state.medicineRoute,
                substitutionEligible: state.medicineSubstitutionEligible,
                notes: state.medicineNotes,
                ingredients: state.medicineIngredients,
              ),
            );
          } else if (state.isEditing) {
            await _pharmacyDao.deleteMedicineProfile(medicineProductId);
          }
        }
      });

      _originalHasVariants = state.hasVariants;
      _originalInventoryTrackingType = state.inventoryTrackingType;
      _originalMeasurementType = state.measurementType;
      _originalTrackInventory = state.trackInventory;
      emit(
        state.copyWith(
          productId: savedProductId,
          isSubmitting: false,
          isSuccess: true,
        ),
      );
    } on FreeQuotaExceededException catch (e) {
      // Free-tier cumulative cap reached. Surface a recognizable code so the
      // screen can present the paywall instead of a generic error.
      emit(
        state.copyWith(
          isSubmitting: false,
          error: 'quota_exceeded:products:${e.limit}',
        ),
      );
      return;
    } on PharmacyValidationException {
      emit(
        state.copyWith(
          isSubmitting: false,
          fieldErrors: {
            ...state.fieldErrors,
            'medicineStrength': 'pharmacy.validation.strength_invalid',
          },
        ),
      );
      return;
    } on _CostingMethodLockedException catch (e) {
      final key = switch (e.lockReason) {
        'has_consumptions' => 'products.costing_method_locked_consumptions',
        'has_transactions' => 'products.costing_method_locked_transactions',
        _ => 'products.costing_method_locked_stock',
      };
      // Refresh the lock reason from the DB so the form reflects reality
      // even if the lock formed between load and submit (e.g. a sale was
      // posted on another device).
      String? freshLock;
      if (state.productId != null) {
        try {
          freshLock = await _repository.getCostingMethodLockReason(
            state.productId!,
          );
        } catch (_) {
          freshLock = e.lockReason;
        }
      } else {
        freshLock = e.lockReason;
      }
      emit(
        state.copyWith(
          isSubmitting: false,
          inventoryTrackingType: _originalInventoryTrackingType,
          measurementType: _originalMeasurementType,
          trackInventory: _originalTrackInventory,
          costingMethodLockReason: freshLock,
          fieldErrors: {
            ...state.fieldErrors,
            // Surface under the tracking-type key (the only selector still
            // rendered post-Phase F). The legacy `'costingMethod'` key is
            // also kept so any older test or screen that still inspects
            // `state.fieldErrors['costingMethod']` continues to work.
            'costingMethod': key,
            'inventoryTrackingType': key,
            'measurementType': key,
            'trackInventory': key,
          },
        ),
      );
      return;
    } on VariantStockConflictException catch (e) {
      // The DAO rejected a race-safe attempt to hide dimensional variants
      // that still carry quantity. The enclosing product transaction rolls
      // back, including the earlier has_variants/product metadata update.
      emit(
        state.copyWith(
          isSubmitting: false,
          hasVariants: true,
          error: 'variant_stock_conflict:${e.variantCount}',
        ),
      );
      return;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('UNIQUE constraint failed: product_variants.barcode') ||
          msg.contains('UNIQUE constraint failed: products.barcode')) {
        emit(
          state.copyWith(
            isSubmitting: false,
            fieldErrors: {
              ...state.fieldErrors,
              'barcode': 'import_products.validation_barcode_exists',
            },
          ),
        );
        return;
      }

      if (msg.contains('UNIQUE constraint failed: product_variants.sku') ||
          msg.contains('UNIQUE constraint failed: products.sku')) {
        emit(
          state.copyWith(
            isSubmitting: false,
            fieldErrors: {
              ...state.fieldErrors,
              'sku': 'import_products.validation_sku_exists',
            },
          ),
        );
        return;
      }
      final missingColumnMatch = RegExp(
        r'no column named ([a-zA-Z0-9_]+)',
      ).firstMatch(msg);
      if (missingColumnMatch != null) {
        final missingColumn = missingColumnMatch.group(1);
        emit(
          state.copyWith(
            isSubmitting: false,
            error:
                'Database schema is out of date (missing column: $missingColumn). Since you said there is no important data, the fastest fix is: close the app, delete tapix.db (desktop local database), reopen the app, then retry. Original error: $msg',
          ),
        );
        return;
      }
      emit(state.copyWith(isSubmitting: false, error: msg));
    }
  }
}

/// Internal sentinel thrown inside the submit transaction when the
/// costing-method change is refused by the lock check. Mirroring the way
/// other UNIQUE/FK errors are caught above keeps rollback semantics
/// uniform — the whole save is undone, never half-applied.
class _CostingMethodLockedException implements Exception {
  final String lockReason; // 'has_stock' | 'has_consumptions'
  _CostingMethodLockedException(this.lockReason);
  @override
  String toString() => 'CostingMethodLocked($lockReason)';
}
