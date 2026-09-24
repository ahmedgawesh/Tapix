import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../../../core/services/inventory/supplier_identity_rules.dart';
import '../../domain/repositories/supplier_repository.dart';

abstract class SupplierFormEvent {
  const SupplierFormEvent();
}

class SupplierFormLoadRequested extends SupplierFormEvent {
  final int? supplierId;
  const SupplierFormLoadRequested({this.supplierId});
}

class SupplierFormNameChanged extends SupplierFormEvent {
  final String name;
  const SupplierFormNameChanged(this.name);
}

class SupplierFormProductCodeChanged extends SupplierFormEvent {
  final String code;
  const SupplierFormProductCodeChanged(this.code);
}

class SupplierFormEmailChanged extends SupplierFormEvent {
  final String email;
  const SupplierFormEmailChanged(this.email);
}

class SupplierFormPhoneChanged extends SupplierFormEvent {
  final String phone;
  const SupplierFormPhoneChanged(this.phone);
}

class SupplierFormAddressChanged extends SupplierFormEvent {
  final String address;
  const SupplierFormAddressChanged(this.address);
}

class SupplierFormBalanceChanged extends SupplierFormEvent {
  final String balance;
  const SupplierFormBalanceChanged(this.balance);
}

class SupplierFormSubmitted extends SupplierFormEvent {
  const SupplierFormSubmitted();
}

abstract class SupplierFormState {
  const SupplierFormState();
}

class SupplierFormInitial extends SupplierFormState {
  const SupplierFormInitial();
}

class SupplierFormLoading extends SupplierFormState {
  const SupplierFormLoading();
}

class SupplierFormReady extends SupplierFormState {
  final int? supplierId;
  final String name;
  final String productCode;
  final bool productCodeLocked;
  final String email;
  final String phone;
  final String address;
  final String balance;
  final int currencyId;
  final bool isEditing;
  final Map<String, String> errors;
  final bool isSubmitting;

  const SupplierFormReady({
    this.supplierId,
    this.name = '',
    this.productCode = '',
    this.productCodeLocked = false,
    this.email = '',
    this.phone = '',
    this.address = '',
    this.balance = '0.00',
    this.currencyId = 1,
    this.isEditing = false,
    this.errors = const {},
    this.isSubmitting = false,
  });

  SupplierFormReady copyWith({
    int? supplierId,
    String? name,
    String? productCode,
    bool? productCodeLocked,
    String? email,
    String? phone,
    String? address,
    String? balance,
    int? currencyId,
    bool? isEditing,
    Map<String, String>? errors,
    bool? isSubmitting,
  }) => SupplierFormReady(
    supplierId: supplierId ?? this.supplierId,
    name: name ?? this.name,
    productCode: productCode ?? this.productCode,
    productCodeLocked: productCodeLocked ?? this.productCodeLocked,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    balance: balance ?? this.balance,
    currencyId: currencyId ?? this.currencyId,
    isEditing: isEditing ?? this.isEditing,
    errors: errors ?? this.errors,
    isSubmitting: isSubmitting ?? this.isSubmitting,
  );

  bool get isValid => name.trim().isNotEmpty && errors.isEmpty;
}

class SupplierFormSuccess extends SupplierFormState {
  final int supplierId;
  final bool isNew;
  const SupplierFormSuccess({required this.supplierId, required this.isNew});
}

class SupplierFormError extends SupplierFormState {
  final String message;
  final SupplierFormReady previousState;
  const SupplierFormError({required this.message, required this.previousState});
}

class SupplierFormBloc extends Bloc<SupplierFormEvent, SupplierFormState> {
  final SupplierRepository _repository;
  final MoneyInputParser _moneyParser;

  SupplierFormBloc(this._repository, {MoneyInputParser? moneyParser})
    : _moneyParser = moneyParser ?? sl<MoneyInputParser>(),
      super(const SupplierFormInitial()) {
    on<SupplierFormLoadRequested>(_onLoadRequested);
    on<SupplierFormNameChanged>(_onNameChanged);
    on<SupplierFormProductCodeChanged>(_onProductCodeChanged);
    on<SupplierFormEmailChanged>(_onEmailChanged);
    on<SupplierFormPhoneChanged>(_onPhoneChanged);
    on<SupplierFormAddressChanged>(_onAddressChanged);
    on<SupplierFormBalanceChanged>(_onBalanceChanged);
    on<SupplierFormSubmitted>(_onSubmitted);
  }

  SupplierFormReady? get _editableState {
    final value = switch (state) {
      SupplierFormReady ready => ready,
      SupplierFormError error => error.previousState,
      _ => null,
    };
    return value == null || value.isSubmitting ? null : value;
  }

  Future<void> _onLoadRequested(
    SupplierFormLoadRequested event,
    Emitter<SupplierFormState> emit,
  ) async {
    emit(const SupplierFormLoading());
    try {
      if (event.supplierId == null) {
        emit(const SupplierFormReady());
        return;
      }
      final supplier = await _repository.getSupplier(event.supplierId!);
      if (supplier == null) {
        emit(const SupplierFormReady());
        return;
      }
      final locked = await _repository.isProductCodeLocked(supplier.id);
      emit(
        SupplierFormReady(
          supplierId: supplier.id,
          name: supplier.name,
          productCode: supplier.productCode ?? '',
          productCodeLocked: locked,
          email: supplier.email ?? '',
          phone: supplier.phone ?? '',
          address: supplier.address ?? '',
          balance: (supplier.balanceCents.toBigInt().toInt() / 100)
              .toStringAsFixed(2),
          currencyId: supplier.currencyId,
          isEditing: true,
        ),
      );
    } catch (error) {
      emit(
        SupplierFormError(
          message: error.toString(),
          previousState: const SupplierFormReady(),
        ),
      );
    }
  }

  void _onNameChanged(
    SupplierFormNameChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    final current = _editableState;
    if (current == null) return;
    final errors = Map<String, String>.of(current.errors)..remove('name');
    if (event.name.trim().isEmpty) errors['name'] = 'suppliers.name_required';
    emit(current.copyWith(name: event.name, errors: errors));
  }

  void _onProductCodeChanged(
    SupplierFormProductCodeChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    final current = _editableState;
    if (current == null || current.productCodeLocked) return;
    final errors = Map<String, String>.of(current.errors)
      ..remove('productCode');
    try {
      SupplierIdentityRules.normalizeSupplierCode(event.code);
    } on SupplierIdentityException catch (error) {
      errors['productCode'] = error.messageKey;
    }
    // Keep the text while editing, normalize on submit (no cursor jumps).
    emit(current.copyWith(productCode: event.code, errors: errors));
  }

  void _onEmailChanged(
    SupplierFormEmailChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    final current = _editableState;
    if (current == null) return;
    final errors = Map<String, String>.of(current.errors)..remove('email');
    if (event.email.isNotEmpty && !_isValidEmail(event.email)) {
      errors['email'] = 'suppliers.email_invalid';
    }
    emit(current.copyWith(email: event.email, errors: errors));
  }

  void _onPhoneChanged(
    SupplierFormPhoneChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    final current = _editableState;
    if (current != null) emit(current.copyWith(phone: event.phone));
  }

  void _onAddressChanged(
    SupplierFormAddressChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    final current = _editableState;
    if (current != null) emit(current.copyWith(address: event.address));
  }

  void _onBalanceChanged(
    SupplierFormBalanceChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    final current = _editableState;
    if (current != null) emit(current.copyWith(balance: event.balance));
  }

  Future<void> _onSubmitted(
    SupplierFormSubmitted event,
    Emitter<SupplierFormState> emit,
  ) async {
    final current = _editableState;
    if (current == null) return;
    // Set before the first await: two rapid taps must not create two suppliers.
    emit(current.copyWith(isSubmitting: true));
    try {
      final errors = <String, String>{};
      if (current.name.trim().isEmpty) {
        errors['name'] = 'suppliers.name_required';
      }
      if (current.email.isNotEmpty && !_isValidEmail(current.email)) {
        errors['email'] = 'suppliers.email_invalid';
      }
      String? normalizedCode;
      try {
        normalizedCode = SupplierIdentityRules.normalizeSupplierCode(
          current.productCode,
        );
      } on SupplierIdentityException catch (error) {
        errors['productCode'] = error.messageKey;
      }
      if (current.name.trim().isNotEmpty) {
        final existing = await _repository.searchSuppliers(current.name.trim());
        if (existing.any(
          (s) =>
              s.name.trim().toLowerCase() ==
                  current.name.trim().toLowerCase() &&
              s.id != current.supplierId,
        )) {
          errors['name'] = 'suppliers.name_duplicate';
        }
      }
      if (normalizedCode != null &&
          !await _repository.isProductCodeAvailable(
            normalizedCode,
            excludingSupplierId: current.supplierId,
          )) {
        errors['productCode'] = 'supplier_identity.code_in_use';
      }
      if (errors.isNotEmpty) {
        emit(current.copyWith(errors: errors, isSubmitting: false));
        return;
      }
      final balanceCents = _parseBalance(current.balance);
      if (current.isEditing && current.supplierId != null) {
        final existing = await _repository.getSupplier(current.supplierId!);
        if (existing == null) {
          throw const SupplierIdentityException(
            'supplier_identity.source_mismatch',
          );
        }
        final updated = existing.copyWith(
          name: current.name,
          productCode: Value(normalizedCode),
          email: Value(current.email.isEmpty ? null : current.email),
          phone: Value(current.phone.isEmpty ? null : current.phone),
          address: Value(current.address.isEmpty ? null : current.address),
          updatedAt: DateTime.now(),
        );
        if (!await _repository.updateSupplier(updated)) {
          throw const SupplierIdentityException(
            'supplier_identity.source_mismatch',
          );
        }
        // Preserve the existing journal-backed balance API.
        await _repository.adjustOpeningBalance(
          supplierId: existing.id,
          desiredBalanceCents: balanceCents.toBigInt().toInt(),
        );
        emit(SupplierFormSuccess(supplierId: existing.id, isNew: false));
      } else {
        final id = await _repository.createSupplier(
          name: current.name,
          productCode: normalizedCode,
          email: current.email.isEmpty ? null : current.email,
          phone: current.phone.isEmpty ? null : current.phone,
          address: current.address.isEmpty ? null : current.address,
          currencyId: current.currencyId,
          initialBalance: balanceCents,
        );
        emit(SupplierFormSuccess(supplierId: id, isNew: true));
      }
    } catch (error) {
      final failure = SupplierIdentityException.fromError(error);
      if (failure != null) {
        // Includes a concurrent save that won the DB reservation after the
        // early check. No raw SQL details or another supplier's name leak.
        var savedCode = current.productCode;
        var locked = current.productCodeLocked;
        if (failure.messageKey == 'supplier_identity.code_locked' &&
            current.supplierId != null) {
          // A document may be saved while this edit form is already open.
          // Do not freeze the rejected draft value inside the text field.
          try {
            final saved = await _repository.getSupplier(current.supplierId!);
            if (saved != null) {
              savedCode = saved.productCode ?? '';
              locked = true;
            }
          } catch (_) {
            // Preserve the retryable form; the database still enforces the lock.
          }
        }
        emit(
          current.copyWith(
            productCode: savedCode,
            errors: {'productCode': failure.messageKey},
            productCodeLocked: locked,
            isSubmitting: false,
          ),
        );
      } else {
        emit(
          SupplierFormError(
            message: error.toString(),
            previousState: current.copyWith(isSubmitting: false),
          ),
        );
      }
    }
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);

  Decimal _parseBalance(String balance) =>
      Decimal.fromInt(_moneyParser.parseSignedOrZero(balance));
}
