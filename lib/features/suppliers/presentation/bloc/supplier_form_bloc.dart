import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../domain/repositories/supplier_repository.dart';

/// Events for SupplierFormBloc
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

/// States for SupplierFormBloc
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
    String? email,
    String? phone,
    String? address,
    String? balance,
    int? currencyId,
    bool? isEditing,
    Map<String, String>? errors,
    bool? isSubmitting,
  }) {
    return SupplierFormReady(
      supplierId: supplierId ?? this.supplierId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      balance: balance ?? this.balance,
      currencyId: currencyId ?? this.currencyId,
      isEditing: isEditing ?? this.isEditing,
      errors: errors ?? this.errors,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  bool get isValid => name.isNotEmpty && errors.isEmpty;
}

class SupplierFormSuccess extends SupplierFormState {
  final int supplierId;
  final bool isNew;

  const SupplierFormSuccess({
    required this.supplierId,
    required this.isNew,
  });
}

class SupplierFormError extends SupplierFormState {
  final String message;
  final SupplierFormReady previousState;

  const SupplierFormError({
    required this.message,
    required this.previousState,
  });
}

/// Bloc for supplier form (create/edit)
class SupplierFormBloc extends Bloc<SupplierFormEvent, SupplierFormState> {
  final SupplierRepository _repository;

  // Phase 8 — sole source of truth for text→cents conversion.
  // Replaces the legacy `(double.parse(...) * 100).round()` pattern.
  final MoneyInputParser _moneyParser;

  SupplierFormBloc(
    this._repository, {
    MoneyInputParser? moneyParser,
  })  : _moneyParser = moneyParser ?? sl<MoneyInputParser>(),
        super(const SupplierFormInitial()) {
    on<SupplierFormLoadRequested>(_onLoadRequested);
    on<SupplierFormNameChanged>(_onNameChanged);
    on<SupplierFormEmailChanged>(_onEmailChanged);
    on<SupplierFormPhoneChanged>(_onPhoneChanged);
    on<SupplierFormAddressChanged>(_onAddressChanged);
    on<SupplierFormBalanceChanged>(_onBalanceChanged);
    on<SupplierFormSubmitted>(_onSubmitted);
  }

  Future<void> _onLoadRequested(
    SupplierFormLoadRequested event,
    Emitter<SupplierFormState> emit,
  ) async {
    emit(const SupplierFormLoading());

    try {
      if (event.supplierId != null) {
        final supplier = await _repository.getSupplier(event.supplierId!);
        if (supplier != null) {
          emit(SupplierFormReady(
            supplierId: supplier.id,
            name: supplier.name,
            email: supplier.email ?? '',
            phone: supplier.phone ?? '',
            address: supplier.address ?? '',
            balance: (supplier.balanceCents.toBigInt().toInt() / 100).toStringAsFixed(2),
            currencyId: supplier.currencyId,
            isEditing: true,
          ));
        } else {
          emit(const SupplierFormReady());
        }
      } else {
        emit(const SupplierFormReady());
      }
    } catch (e) {
      emit(SupplierFormError(
        message: e.toString(),
        previousState: const SupplierFormReady(),
      ));
    }
  }

  void _onNameChanged(
    SupplierFormNameChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    if (state is SupplierFormReady) {
      final currentState = state as SupplierFormReady;
      final errors = Map<String, String>.from(currentState.errors);

      if (event.name.isEmpty) {
        errors['name'] = 'suppliers.name_required';
      } else {
        errors.remove('name');
      }

      emit(currentState.copyWith(name: event.name, errors: errors));
    }
  }

  void _onEmailChanged(
    SupplierFormEmailChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    if (state is SupplierFormReady) {
      final currentState = state as SupplierFormReady;
      final errors = Map<String, String>.from(currentState.errors);

      if (event.email.isNotEmpty && !_isValidEmail(event.email)) {
        errors['email'] = 'suppliers.email_invalid';
      } else {
        errors.remove('email');
      }

      emit(currentState.copyWith(email: event.email, errors: errors));
    }
  }

  void _onPhoneChanged(
    SupplierFormPhoneChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    if (state is SupplierFormReady) {
      final currentState = state as SupplierFormReady;
      emit(currentState.copyWith(phone: event.phone));
    }
  }

  void _onAddressChanged(
    SupplierFormAddressChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    if (state is SupplierFormReady) {
      final currentState = state as SupplierFormReady;
      emit(currentState.copyWith(address: event.address));
    }
  }

  void _onBalanceChanged(
    SupplierFormBalanceChanged event,
    Emitter<SupplierFormState> emit,
  ) {
    if (state is SupplierFormReady) {
      final currentState = state as SupplierFormReady;
      emit(currentState.copyWith(balance: event.balance));
    }
  }

  Future<void> _onSubmitted(
    SupplierFormSubmitted event,
    Emitter<SupplierFormState> emit,
  ) async {
    if (state is! SupplierFormReady) return;

    final currentState = state as SupplierFormReady;

    // Validate
    final errors = <String, String>{};
    if (currentState.name.isEmpty) {
      errors['name'] = 'suppliers.name_required';
    }
    if (currentState.email.isNotEmpty && !_isValidEmail(currentState.email)) {
      errors['email'] = 'suppliers.email_invalid';
    }

    // Check for duplicate name
    if (currentState.name.isNotEmpty) {
      final existing = await _repository.searchSuppliers(currentState.name);
      final duplicate = existing.any((s) =>
          s.name.trim().toLowerCase() == currentState.name.trim().toLowerCase() &&
          s.id != currentState.supplierId);
      if (duplicate) {
        errors['name'] = 'suppliers.name_duplicate';
      }
    }

    if (errors.isNotEmpty) {
      emit(currentState.copyWith(errors: errors));
      return;
    }

    emit(currentState.copyWith(isSubmitting: true));

    try {
      final balanceCents = _parseBalance(currentState.balance);

      if (currentState.isEditing && currentState.supplierId != null) {
        final existingSupplier = await _repository.getSupplier(currentState.supplierId!);
        if (existingSupplier != null) {
          final updatedSupplier = existingSupplier.copyWith(
            name: currentState.name,
            email: Value(currentState.email.isEmpty ? null : currentState.email),
            phone: Value(currentState.phone.isEmpty ? null : currentState.phone),
            address: Value(currentState.address.isEmpty ? null : currentState.address),
            updatedAt: DateTime.now(),
          );
          await _repository.updateSupplier(updatedSupplier);

          // Phase 1.4: read-current → compute-delta → recordTransaction is
          // now a single atomic repository call. No-op when balance unchanged.
          await _repository.adjustOpeningBalance(
            supplierId: existingSupplier.id,
            desiredBalanceCents: balanceCents.toBigInt().toInt(),
          );

          emit(SupplierFormSuccess(
            supplierId: currentState.supplierId!,
            isNew: false,
          ));
        }
      } else {
        final supplierId = await _repository.createSupplier(
          name: currentState.name,
          email: currentState.email.isEmpty ? null : currentState.email,
          phone: currentState.phone.isEmpty ? null : currentState.phone,
          address: currentState.address.isEmpty ? null : currentState.address,
          currencyId: currentState.currencyId,
          initialBalance: balanceCents,
        );
        emit(SupplierFormSuccess(supplierId: supplierId, isNew: true));
      }
    } catch (e) {
      emit(SupplierFormError(
        message: e.toString(),
        previousState: currentState.copyWith(isSubmitting: false),
      ));
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // Phase 8 — delegates to the canonical signed-text parser. The supplier
  // opening-balance field legitimately accepts a negative magnitude (a
  // prepaid advance on file), which is why we use the signed variant
  // rather than [MoneyInputParser.parseOrZero].
  Decimal _parseBalance(String balance) =>
      Decimal.fromInt(_moneyParser.parseSignedOrZero(balance));
}
