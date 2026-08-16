import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/currency_service.dart';

class MoneyInputWidget extends StatefulWidget {
  final Decimal value;
  final ValueChanged<Decimal> onChanged;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool enabled;
  final int decimalPlaces;

  const MoneyInputWidget({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.errorText,
    this.enabled = true,
    this.decimalPlaces = 2,
  });

  @override
  State<MoneyInputWidget> createState() => _MoneyInputWidgetState();
}

class _MoneyInputWidgetState extends State<MoneyInputWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  // Need to initialize controller in didChangeDependencies to access context for CurrencyService if needed
  // But actually formatting happens in _formatValue which we can access context in
  // However, initState cannot access context.
  // We'll initialize controller with current value and symbol in didChangeDependencies or just use what we have.
  // Actually, let's keep it simple. We can access context in build.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!mounted) return;
    // We might want to re-format if currency changes, but the input value is just numbers.
    // The prefix is where the symbol is shown.
    if (!hasInitializedController) {
      _controller = TextEditingController(text: _formatValue(widget.value));
      hasInitializedController = true;
    }
  }

  bool hasInitializedController = false;

  @override
  void didUpdateWidget(MoneyInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_hasFocus) {
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _hasFocus = _focusNode.hasFocus;
    });

    if (_focusNode.hasFocus) {
      // Select all text on focus for easy editing
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      // Format on blur
      final currencyService = context.read<CurrencyService>();
      final symbol = currencyService.currencySymbol;
      final parsed = _parseValue(_controller.text, symbol);
      _controller.text = _formatValue(parsed);
      widget.onChanged(parsed);
    }
  }

  String _formatValue(Decimal cents) {
    // Convert cents to display value (e.g., 1500 cents -> 15.00)
    final displayValue = cents / Decimal.fromInt(100);
    return displayValue.toDouble().toStringAsFixed(widget.decimalPlaces);
  }

  Decimal _parseValue(String text, String symbol) {
    if (text.isEmpty) return Decimal.zero;

    // Remove currency symbol and whitespace
    final cleaned = text.replaceAll(symbol, '').trim();

    try {
      // Parse as decimal and convert to cents
      final parsed = Decimal.parse(cleaned);
      return parsed * Decimal.fromInt(100);
    } catch (e) {
      return widget.value;
    }
  }

  void _onChanged(String text) {
    // We need the symbol here. Since we can't easily get context in this callback without storing it,
    // let's assume the controller text is what we are parsing.
    // Actually, we can just get the symbol from the current context if we are in a callback that has access to it,
    // or we can store the current symbol in the state during build.
    // For simplicity, let's just parse whatever numbers we can find, ignoring non-numeric except decimal point.

    // Better approach: Use the formatValue logic which is consistent.
    // But _parseValue removed the symbol.
    // Let's rely on the controller text which we know contains the symbol from the build method if we enforced it.
    // BUT, the user might delete the symbol.

    // Simplest robust way: remove all non-numeric characters except the first decimal point.
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    try {
      final parsed = Decimal.parse(cleaned);
      widget.onChanged(parsed * Decimal.fromInt(100));
    } catch (e) {
      // Invalid format, ignore or handle
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyService = context.watch<CurrencyService>();
    final symbol = currencyService.currencySymbol;

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: _onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint ?? '0.00',
        errorText: widget.errorText,
        prefixText: '$symbol ',
        prefixStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        border: const OutlineInputBorder(),
        filled: true,
      ),
      style: theme.textTheme.bodyLarge?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      textAlign: TextAlign.end,
    );
  }
}

class MoneyDisplayWidget extends StatelessWidget {
  final Decimal cents;
  final TextStyle? style;
  final int decimalPlaces;

  const MoneyDisplayWidget({
    super.key,
    required this.cents,
    this.style,
    this.decimalPlaces = 2,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyService = context.watch<CurrencyService>();

    return Text(
      currencyService.format(cents.toBigInt().toInt()),
      style:
          style ??
          theme.textTheme.bodyLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );
  }
}

class MarginDisplayWidget extends StatelessWidget {
  final Decimal costCents;
  final Decimal priceCents;

  const MarginDisplayWidget({
    super.key,
    required this.costCents,
    required this.priceCents,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = context.watch<CurrencyService>();

    final margin = priceCents - costCents;
    final marginPercent = costCents > Decimal.zero
        ? ((margin / costCents).toDouble() * 100)
        : 0.0;

    final isPositive = margin >= Decimal.zero;
    final color = isPositive ? colorScheme.primary : colorScheme.error;

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          currencyService.format(margin.toBigInt().toInt()),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${marginPercent.toStringAsFixed(1)}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
