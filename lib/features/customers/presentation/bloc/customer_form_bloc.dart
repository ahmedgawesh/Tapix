import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/customer_repository.dart';

/// Events for CustomerFormBloc
abstract class CustomerFormEvent {
  const CustomerFormEvent();
}

class CustomerFormLoadRequested extends CustomerFormEvent {
  final int? customerId;
  const CustomerFormLoadRequested({this.customerId});
}

class CustomerFormNameChanged extends CustomerFormEvent {
  final String name;
  const CustomerFormNameChanged(this.name);
}

class CustomerFormEmailChanged extends CustomerFormEvent {
  final String email;
  const CustomerFormEmailChanged(this.email);
}

class CustomerFormPhoneChanged extends CustomerFormEvent {
  final String phone;
  const CustomerFormPhoneChanged(this.phone);
}

class CustomerFormAddressChanged extends CustomerFormEvent {
  final String address;
  const CustomerFormAddressChanged(this.address);
}

class CustomerFormSegmentChanged extends CustomerFormEvent {
  final String segment;
  const CustomerFormSegmentChanged(this.segment);
}

class CustomerFormBalanceChanged extends CustomerFormEvent {
  final String balance;
  const CustomerFormBalanceChanged(this.balance);
}

class CustomerFormLoyaltyEnabledChanged extends CustomerFormEvent {
  final bool loyaltyEnabled;
  const CustomerFormLoyaltyEnabledChanged(this.loyaltyEnabled);
}

class CustomerFormSubmitted extends CustomerFormEvent {
  const CustomerFormSubmitted();
}

/// States for CustomerFormBloc
abstract class CustomerFormState {
  const CustomerFormState();
}

class CustomerFormInitial extends CustomerFormState {
  const CustomerFormInitial();
}

class CustomerFormLoading extends CustomerFormState {
  const CustomerFormLoading();
}

class CustomerFormReady extends CustomerFormState {
  final int? customerId;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String segment;
  final String balance;
  final bool loyaltyEnabled;
  final int currencyId;
  final bool isEditing;
  final Map<String, String> errors;
  final bool isSubmitting;

  const CustomerFormReady({
    this.customerId,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.segment = 'retail',
    this.balance = '0.00',
    this.loyaltyEnabled = true,
    this.currencyId = 1,
    this.isEditing = false,
    this.errors = const {},
    this.isSubmitting = false,
  });

  CustomerFormReady copyWith({
    int? customerId,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? segment,
    String? balance,
    bool? loyaltyEnabled,
    int? currencyId,
    bool? isEditing,
    Map<String, String>? errors,
    bool? isSubmitting,
  }) {
    return CustomerFormReady(
      customerId: customerId ?? this.customerId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      segment: segment ?? this.segment,
      balance: balance ?? this.balance,
      loyaltyEnabled: loyaltyEnabled ?? this.loyaltyEnabled,
      currencyId: currencyId ?? this.currencyId,
      isEditing: isEditing ?? this.isEditing,
      errors: errors ?? this.errors,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  bool get isValid => name.isNotEmpty && errors.isEmpty;
}

class CustomerFormSuccess extends CustomerFormState {
  final int customerId;
  final bool isNew;

  const CustomerFormSuccess({
    required this.customerId,
    required this.isNew,
  });
}

class CustomerFormError extends CustomerFormState {
  final String message;
  final CustomerFormReady previousState;

  const CustomerFormError({
    required this.message,
    required this.previousState,
  });
}

/// Bloc for customer form (create/edit)
class CustomerFormBloc extends Bloc<CustomerFormEvent, CustomerFormState> {
  final CustomerRepository _repository;

  CustomerFormBloc(this._repository) : super(const CustomerFormInitial()) {
    on<CustomerFormLoadRequested>(_onLoadRequested);
    on<CustomerFormNameChanged>(_onNameChanged);
    on<CustomerFormEmailChanged>(_onEmailChanged);
    on<CustomerFormPhoneChanged>(_onPhoneChanged);
    on<CustomerFormAddressChanged>(_onAddressChanged);
    on<CustomerFormSegmentChanged>(_onSegmentChanged);
    on<CustomerFormBalanceChanged>(_onBalanceChanged);
    on<CustomerFormLoyaltyEnabledChanged>(_onLoyaltyEnabledChanged);
    on<CustomerFormSubmitted>(_onSubmitted);
  }

  Future<void> _onLoadRequested(
    CustomerFormLoadRequested event,
    Emitter<CustomerFormState> emit,
  ) async {
    emit(const CustomerFormLoading());

    try {
      if (event.customerId != null) {
        final customer = await _repository.getCustomer(event.customerId!);
        if (customer != null) {
          emit(CustomerFormReady(
            customerId: customer.id,
            name: customer.name,
            email: customer.email ?? '',
            phone: customer.phone ?? '',
            address: customer.address ?? '',
            segment: customer.segment,
            balance: (customer.balanceCents.toBigInt().toInt() / 100).toStringAsFixed(2),
            loyaltyEnabled: customer.loyaltyEnabled,
            currencyId: customer.currencyId,
            isEditing: true,
          ));
        } else {
          emit(const CustomerFormReady());
        }
      } else {
        emit(const CustomerFormReady());
      }
    } catch (e) {
      emit(CustomerFormError(
        message: e.toString(),
        previousState: const CustomerFormReady(),
      ));
    }
  }

  void _onNameChanged(
    CustomerFormNameChanged event,
    Emitter<CustomerFormState> emit,
  ) {
    if (state is CustomerFormReady) {
      final currentState = state as CustomerFormReady;
      final errors = Map<String, String>.from(currentState.errors);
      
      if (event.name.isEmpty) {
        errors['name'] = 'customers.name_required';
      } else {
        errors.remove('name');
      }

      emit(currentState.copyWith(name: event.name, errors: errors));
    }
  }

  void _onEmailChanged(
    CustomerFormEmailChanged event,
    Emitter<CustomerFormState> emit,
  ) {
    if (state is CustomerFormReady) {
      final currentState = state as CustomerFormReady;
      final errors = Map<String, String>.from(currentState.errors);
      
      if (event.email.isNotEmpty && !_isValidEmail(event.email)) {
        errors['email'] = 'customers.email_invalid';
      } else {
        errors.remove('email');
      }

      emit(currentState.copyWith(email: event.email, errors: errors));
    }
  }

  void _onPhoneChanged(
    CustomerFormPhoneChanged event,
    Emitter<CustomerFormState> emit,
  ) {
    if (state is CustomerFormReady) {
      final currentState = state as CustomerFormReady;
      emit(currentState.copyWith(phone: event.phone));
    }
  }

  void _onAddressChanged(
    CustomerFormAddressChanged event,
    Emitter<CustomerFormState> emit,
  ) {
    if (state is CustomerFormReady) {
      final currentState = state as CustomerFormReady;
      emit(currentState.copyWith(address: event.address));
    }
  }

  void _onSegmentChanged(
    CustomerFormSegmentChanged event,
    Emitter<CustomerFormState> emit,
  ) {
    if (state is CustomerFormReady) {
      final currentState = state as CustomerFormReady;
      emit(currentState.copyWith(segment: event.segment));
    }
  }

  void _onBalanceChanged(
    CustomerFormBalanceChanged event,
    Emitter<CustomerFormState> emit,
  ) {
    if (state is CustomerFormReady) {
      final currentState = state as CustomerFormReady;
      emit(currentState.copyWith(balance: event.balance));
    }
  }

  void _onLoyaltyEnabledChanged(
    CustomerFormLoyaltyEnabledChanged event,
    Emitter<CustomerFormState> emit,
  ) {
    if (state is CustomerFormReady) {
      final currentState = state as CustomerFormReady;
      emit(currentState.copyWith(loyaltyEnabled: event.loyaltyEnabled));
    }
  }

  Future<void> _onSubmitted(
    CustomerFormSubmitted event,
    Emitter<CustomerFormState> emit,
  ) async {
    if (state is! CustomerFormReady) return;

    final currentState = state as CustomerFormReady;
    
    // Validate
    final errors = <String, String>{};
    if (currentState.name.isEmpty) {
      errors['name'] = 'customers.name_required';
    }
    if (currentState.email.isNotEmpty && !_isValidEmail(currentState.email)) {
      errors['email'] = 'customers.email_invalid';
    }

    if (errors.isNotEmpty) {
      emit(currentState.copyWith(errors: errors));
      return;
    }

    emit(currentState.copyWith(isSubmitting: true));

    try {
      final desiredBalanceCentsDecimal = _parseBalance(currentState.balance);
      final desiredBalanceCents = desiredBalanceCentsDecimal.toBigInt().toInt();

      if (currentState.isEditing && currentState.customerId != null) {
        // Update existing customer
        final existingCustomer = await _repository.getCustomer(currentState.customerId!);
        if (existingCustomer != null) {
          final updatedCustomer = existingCustomer.copyWith(
            name: currentState.name,
            email: Value(currentState.email.isEmpty ? null : currentState.email),
            phone: Value(currentState.phone.isEmpty ? null : currentState.phone),
            address: Value(currentState.address.isEmpty ? null : currentState.address),
            segment: currentState.segment,
            loyaltyEnabled: currentState.loyaltyEnabled,
            updatedAt: DateTime.now(),
          );
          await _repository.updateCustomer(updatedCustomer);

          final currentBalanceCents = existingCustomer.balanceCents.toBigInt().toInt();
          if (desiredBalanceCents != currentBalanceCents) {
            final deltaCents = desiredBalanceCents - currentBalanceCents;
            await _repository.recordTransaction(
              customerId: existingCustomer.id,
              transactionType: 'adjustment',
              amountCents: deltaCents,
              currencyId: existingCustomer.currencyId,
              description: null,
            );
          }

          emit(CustomerFormSuccess(
            customerId: currentState.customerId!,
            isNew: false,
          ));
        }
      } else {
        // Create new customer
        final customerId = await _repository.createCustomer(
          name: currentState.name,
          email: currentState.email.isEmpty ? null : currentState.email,
          phone: currentState.phone.isEmpty ? null : currentState.phone,
          address: currentState.address.isEmpty ? null : currentState.address,
          currencyId: currentState.currencyId,
          initialBalance: desiredBalanceCentsDecimal,
          segment: currentState.segment,
          loyaltyEnabled: currentState.loyaltyEnabled,
        );
        emit(CustomerFormSuccess(customerId: customerId, isNew: true));
      }
    } catch (e) {
      emit(CustomerFormError(
        message: e.toString(),
        previousState: currentState.copyWith(isSubmitting: false),
      ));
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  Decimal _parseBalance(String balance) {
    try {
      final value = double.parse(balance.replaceAll(',', '.'));
      final cents = (value * 100).round();
      return Decimal.fromInt(cents);
    } catch (_) {
      return Decimal.zero;
    }
  }
}
