import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

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

  const ProductFormInitialized({this.productId, this.initialBarcode});

  @override
  List<Object?> get props => [productId, initialBarcode];
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

  final int? selectedColorId;
  final int? selectedSizeId;

  // Validation errors
  final Map<String, String> fieldErrors;

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
    this.selectedColorId,
    this.selectedSizeId,
    this.fieldErrors = const {},
  })  : costCents = costCents ?? Decimal.zero,
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
    int? selectedColorId,
    int? selectedSizeId,
    Map<String, String>? fieldErrors,
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
      selectedColorId: selectedColorId ?? this.selectedColorId,
      selectedSizeId: selectedSizeId ?? this.selectedSizeId,
      fieldErrors: fieldErrors ?? this.fieldErrors,
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
        selectedColorId,
        selectedSizeId,
        fieldErrors,
      ];
}

// Bloc
class ProductFormBloc extends Bloc<ProductFormEvent, ProductFormState> {
  final ProductRepository _repository;
  final ProductVariantRepository _variantRepository;

  ProductFormBloc(this._repository, this._variantRepository) : super(ProductFormState()) {
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
      // New product - set initial state with barcode if provided
      emit(state.copyWith(
        isEditing: false,
        barcode: event.initialBarcode,
      ));
      return;
    }

    emit(state.copyWith(isLoading: true, isEditing: true, productId: event.productId));

    try {
      final product = await _repository.watchProduct(event.productId!).first;
      if (product != null) {
        Decimal costCents = product.costCents;
        Decimal priceCents = product.priceCents;
        int stockQuantity = product.stockQuantity;
        int? selectedColorId;
        int? selectedSizeId;

        if (!product.hasVariants) {
          final defaultVariant = await _variantRepository.getDefaultVariantByProduct(product.id);
          if (defaultVariant != null) {
            costCents = defaultVariant.costCents;
            priceCents = defaultVariant.priceCents;
            stockQuantity = defaultVariant.stockQuantity;
            selectedColorId = defaultVariant.colorId;
            selectedSizeId = _normalizeOptionalId(defaultVariant.sizeId);
          }
        }

        emit(state.copyWith(
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
          selectedColorId: product.hasVariants ? null : selectedColorId,
          selectedSizeId: product.hasVariants ? null : selectedSizeId,
        ));
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
        emit(state.copyWith(name: event.value as String, fieldErrors: newErrors));
        break;
      case 'nameAr':
        emit(state.copyWith(nameAr: event.value as String?, fieldErrors: newErrors));
        break;
      case 'nameFr':
        emit(state.copyWith(nameFr: event.value as String?, fieldErrors: newErrors));
        break;
      case 'description':
        emit(state.copyWith(description: event.value as String?, fieldErrors: newErrors));
        break;
      case 'sku':
        emit(state.copyWith(sku: event.value as String?, fieldErrors: newErrors));
        break;
      case 'barcode':
        emit(state.copyWith(barcode: event.value as String?, fieldErrors: newErrors));
        break;
      case 'costCents':
        emit(state.copyWith(costCents: event.value as Decimal, fieldErrors: newErrors));
        break;
      case 'priceCents':
        emit(state.copyWith(priceCents: event.value as Decimal, fieldErrors: newErrors));
        break;
      case 'wholesalePriceCents':
        emit(state.copyWith(wholesalePriceCents: event.value as Decimal?, fieldErrors: newErrors));
        break;
      case 'stockQuantity':
        emit(state.copyWith(stockQuantity: event.value as int, fieldErrors: newErrors));
        break;
      case 'minQuantity':
        emit(state.copyWith(minQuantity: event.value as int, fieldErrors: newErrors));
        break;
      case 'categoryId':
        emit(state.copyWith(categoryId: event.value as int?, fieldErrors: newErrors));
        break;
      case 'supplierId':
        emit(state.copyWith(supplierId: event.value as int?, fieldErrors: newErrors));
        break;
      case 'currencyId':
        emit(state.copyWith(currencyId: event.value as int?, fieldErrors: newErrors));
        break;
      case 'imagePath':
        emit(state.copyWith(imagePath: event.value as String?, fieldErrors: newErrors));
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
        emit(state.copyWith(isTaxable: event.value as bool, fieldErrors: newErrors));
        break;
      case 'purchaseTaxRateBps':
        emit(state.copyWith(purchaseTaxRateBps: event.value as int, fieldErrors: newErrors));
        break;
      case 'salesTaxRateBps':
        emit(state.copyWith(salesTaxRateBps: event.value as int, fieldErrors: newErrors));
        break;
      case 'isActive':
        emit(state.copyWith(isActive: event.value as bool, fieldErrors: newErrors));
        break;
      case 'trackInventory':
        emit(state.copyWith(trackInventory: event.value as bool, fieldErrors: newErrors));
        break;
      case 'selectedColorId':
        emit(state.copyWith(selectedColorId: event.value as int?, fieldErrors: newErrors));
        break;
      case 'selectedSizeId':
        emit(state.copyWith(selectedSizeId: event.value as int?, fieldErrors: newErrors));
        break;
    }
  }

  void _onValidationRequested(
    ProductFormValidationRequested event,
    Emitter<ProductFormState> emit,
  ) {
    final errors = _validate();
    emit(state.copyWith(fieldErrors: errors));
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};

    if (state.name.isEmpty) {
      errors['name'] = 'Product name is required';
    }

    if (state.costCents < Decimal.zero) {
      errors['costCents'] = 'Cost cannot be negative';
    }

    if (state.priceCents < Decimal.zero) {
      errors['priceCents'] = 'Price cannot be negative';
    }

    if (state.priceCents < state.costCents) {
      errors['priceCents'] = 'Selling price should be greater than cost';
    }

    if (state.stockQuantity < 0) {
      errors['stockQuantity'] = 'Stock quantity cannot be negative';
    }

    if (state.minQuantity < 0) {
      errors['minQuantity'] = 'Minimum quantity cannot be negative';
    }

    if (state.isTaxable && state.purchaseTaxRateBps <= 0 && state.salesTaxRateBps <= 0) {
      errors['purchaseTaxRateBps'] = 'At least one tax rate is required when product is taxable';
    }

    return errors;
  }

  Future<Map<String, String>> _validateSkuUniqueness() async {
    final errors = <String, String>{};
    final sku = state.sku?.trim();
    if (sku == null || sku.isEmpty) return errors;

    final existingProduct = await _repository.findBySku(sku);
    if (existingProduct != null && existingProduct.id != state.productId) {
      errors['sku'] = 'import_products.validation_sku_exists';
      return errors;
    }

    if (!state.hasVariants) {
      final existingVariant = await _variantRepository.getVariantBySku(sku);

      int? allowedVariantId;
      if (state.productId != null) {
        final currentDefault = await _variantRepository.getDefaultVariantByProduct(state.productId!);
        allowedVariantId = currentDefault?.id;
      }

      if (existingVariant != null && existingVariant.id != allowedVariantId) {
        errors['sku'] = 'import_products.validation_sku_exists';
        return errors;
      }
    }

    return errors;
  }

  int? _normalizeOptionalId(int? id) {
    if (id == null) return null;
    if (id == 0) return null;
    return id;
  }

  Future<Map<String, String>> _validateBarcodeUniqueness() async {
    final errors = <String, String>{};
    final barcode = state.barcode?.trim();
    if (barcode == null || barcode.isEmpty) return errors;

    // Check product-level uniqueness
    final existingProduct = await _repository.findByBarcode(barcode);
    if (existingProduct != null && existingProduct.id != state.productId) {
      errors['barcode'] = 'import_products.validation_barcode_exists';
      return errors;
    }

    // For non-variant products, the barcode is also stored on the default variant.
    if (!state.hasVariants) {
      final existingVariant = await _variantRepository.getVariantByBarcode(barcode);

      int? allowedVariantId;
      if (state.productId != null) {
        final currentDefault = await _variantRepository.getDefaultVariantByProduct(state.productId!);
        allowedVariantId = currentDefault?.id;
      }

      if (existingVariant != null && existingVariant.id != allowedVariantId) {
        errors['barcode'] = 'import_products.validation_barcode_exists';
        return errors;
      }
    }

    return errors;
  }

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

    final barcodeErrors = await _validateBarcodeUniqueness();
    if (barcodeErrors.isNotEmpty) {
      emit(state.copyWith(fieldErrors: {...state.fieldErrors, ...barcodeErrors}));
      return;
    }

    final skuErrors = await _validateSkuUniqueness();
    if (skuErrors.isNotEmpty) {
      emit(state.copyWith(fieldErrors: {...state.fieldErrors, ...skuErrors}));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      if (state.isEditing && state.productId != null) {
        // Update existing product
        final product = Product(
          id: state.productId!,
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
        );
        await _repository.updateProduct(product);

        if (!state.hasVariants) {
          await _variantRepository.ensureDefaultVariantForProduct(
            productId: state.productId!,
            costCents: state.costCents,
            priceCents: state.priceCents,
            stockQuantity: state.stockQuantity,
          );

          final defaultVariant = await _variantRepository.getDefaultVariantByProduct(state.productId!);
          if (defaultVariant != null) {
            final updated = defaultVariant.copyWith(
              sku: (state.sku?.trim().isNotEmpty ?? false) ? state.sku : null,
              barcode: (state.barcode?.trim().isNotEmpty ?? false) ? state.barcode : null,
              costCents: state.costCents,
              priceCents: state.priceCents,
              stockQuantity: state.stockQuantity,
              colorId: state.selectedColorId,
              sizeId: _normalizeOptionalId(state.selectedSizeId),
            );
            await _variantRepository.updateVariant(updated);
          }
        }
      } else {
        // Create new product
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
        );

        if (!state.hasVariants) {
          await _variantRepository.ensureDefaultVariantForProduct(
            productId: createdProductId,
            costCents: state.costCents,
            priceCents: state.priceCents,
            stockQuantity: state.stockQuantity,
          );

          final defaultVariant = await _variantRepository.getDefaultVariantByProduct(createdProductId);
          if (defaultVariant != null) {
            final updated = defaultVariant.copyWith(
              sku: (state.sku?.trim().isNotEmpty ?? false) ? state.sku : null,
              barcode: (state.barcode?.trim().isNotEmpty ?? false) ? state.barcode : null,
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

      emit(state.copyWith(isSubmitting: false, isSuccess: true));
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
      final missingColumnMatch = RegExp(r'no column named ([a-zA-Z0-9_]+)').firstMatch(msg);
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
