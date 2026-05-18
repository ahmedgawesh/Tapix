import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../domain/repositories/expense_repository.dart';
import '../bloc/expense_form_bloc.dart';
import '../bloc/expense_categories_bloc.dart';

/// Screen for creating or editing an expense
class ExpenseFormScreen extends StatelessWidget {
  final int? expenseId;

  const ExpenseFormScreen({super.key, this.expenseId});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) {
            final bloc = ExpenseFormBloc(sl<ExpenseRepository>());
            if (expenseId != null) {
              bloc.add(ExpenseFormLoadRequested(expenseId: expenseId));
            }
            return bloc;
          },
        ),
        BlocProvider(
          create: (context) => ExpenseCategoriesBloc(sl<ExpenseRepository>()),
        ),
      ],
      child: _ExpenseFormContent(expenseId: expenseId),
    );
  }
}

class _ExpenseFormContent extends StatefulWidget {
  final int? expenseId;

  const _ExpenseFormContent({this.expenseId});

  @override
  State<_ExpenseFormContent> createState() => _ExpenseFormContentState();
}

class _ExpenseFormContentState extends State<_ExpenseFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  int? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  bool _isEditing = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _populateForm(Expense expense) {
    if (_isEditing) return;
    _isEditing = true;
    _descriptionController.text = expense.description;
    final cs = sl<CurrencyService>();
    _amountController.text = cs.centsToDecimalString(expense.amountCents.toBigInt().toInt());
    _selectedCategoryId = expense.categoryId;
    _selectedDate = expense.expenseDate;
    setState(() {});
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('expenses.select_category_error'.tr())),
      );
      return;
    }

    // Phase 8 — MoneyInputParser is the SoT for text→cents conversion;
    // currency-aware (e.g. 3-digit JOD/KWD) and Decimal-based (no
    // IEEE-754 cent-drop on edges like `99999.99 * 100`).
    final amountCentsInt =
        sl<MoneyInputParser>().parseOrZero(_amountController.text);
    final amountCents = Decimal.fromInt(amountCentsInt);

    context.read<ExpenseFormBloc>().add(
          ExpenseFormSubmitRequested(
            categoryId: _selectedCategoryId!,
            description: _descriptionController.text.trim(),
            amountCents: amountCents,
            currencyId: 1, // Default currency
            expenseDate: _selectedDate,
          ),
        );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEdit = widget.expenseId != null;

    return BlocListener<ExpenseFormBloc, RealtimeState<ExpenseFormData>>(
      listener: (context, state) {
        if (state is RealtimeSuccess<ExpenseFormData>) {
          if (state.data.existingExpense != null && !_isEditing) {
            _populateForm(state.data.existingExpense!);
          }
          if (state.data.isSubmitted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isEdit
                      ? 'expenses.updated_success'.tr()
                      : 'expenses.created_success'.tr(),
                ),
                backgroundColor: colorScheme.primary,
              ),
            );
            context.pop();
          }
          if (state.data.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.data.errorMessage!),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/expenses');
              }
            },
          ),
          title: Text(
            isEdit ? 'expenses.edit'.tr() : 'expenses.add'.tr(),
          ),
        ),
        body: BlocBuilder<ExpenseFormBloc, RealtimeState<ExpenseFormData>>(
          builder: (context, formState) {
            if (formState is RealtimeLoading<ExpenseFormData>) {
              return const Center(child: CircularProgressIndicator());
            }

            final isSubmitting = formState is RealtimeSuccess<ExpenseFormData> &&
                formState.data.isSubmitting;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Category selector
                        BlocBuilder<ExpenseCategoriesBloc,
                            RealtimeState<List<ExpenseCategory>>>(
                          builder: (context, catState) {
                            final categories = catState
                                    is RealtimeSuccess<List<ExpenseCategory>>
                                ? catState.data
                                : <ExpenseCategory>[];

                            return DropdownButtonFormField<int>(
                              // ignore: deprecated_member_use
                              value: _selectedCategoryId,
                              decoration: InputDecoration(
                                labelText: 'expenses.category'.tr(),
                                prefixIcon: const Icon(LucideIcons.tag),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: categories
                                  .map((cat) => DropdownMenuItem(
                                        value: cat.id,
                                        child: Text(cat.name),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _selectedCategoryId = value);
                              },
                              validator: (value) {
                                if (value == null) {
                                  return 'expenses.category_required'.tr();
                                }
                                return null;
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Description
                        TextFormField(
                          controller: _descriptionController,
                          decoration: InputDecoration(
                            labelText: 'expenses.description'.tr(),
                            prefixIcon: const Icon(LucideIcons.fileText),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          maxLines: 2,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'expenses.description_required'.tr();
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Amount and Date row
                        if (isWide)
                          Row(
                            children: [
                              Expanded(child: _buildAmountField()),
                              const SizedBox(width: 16),
                              Expanded(child: _buildDateField()),
                            ],
                          )
                        else ...[
                          _buildAmountField(),
                          const SizedBox(height: 16),
                          _buildDateField(),
                        ],

                        const SizedBox(height: 32),

                        // Submit button
                        FilledButton.icon(
                          onPressed: isSubmitting ? null : _submitForm,
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(isEdit
                                  ? LucideIcons.save
                                  : LucideIcons.plus),
                          label: Text(
                            isEdit
                                ? 'common.save'.tr()
                                : 'expenses.add'.tr(),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const ui.Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    final cs = sl<CurrencyService>();

    return TextFormField(
      controller: _amountController,
      decoration: InputDecoration(
        labelText: 'expenses.amount'.tr(),
        prefixIcon: const Icon(LucideIcons.banknote),
        suffixText: cs.currencySymbol,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onTap: () => selectAllText(_amountController),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'expenses.amount_required'.tr();
        }
        final parsed = double.tryParse(value);
        if (parsed == null || parsed <= 0) {
          return 'expenses.amount_invalid'.tr();
        }
        return null;
      },
    );
  }

  Widget _buildDateField() {
    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'expenses.date'.tr(),
          prefixIcon: const Icon(LucideIcons.calendar),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(dateStr),
      ),
    );
  }
}
