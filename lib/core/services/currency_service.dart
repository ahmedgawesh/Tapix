import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SymbolPosition { before, after }

class Currency {
  final String code;
  final String symbol;
  final String name;
  final SymbolPosition symbolPosition;
  final int decimalDigits;

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    this.symbolPosition = SymbolPosition.before,
    this.decimalDigits = 2,
  });

  static const List<Currency> supportedCurrencies = [
    Currency(code: 'USD', symbol: '\$', name: 'US Dollar'),
    Currency(code: 'EUR', symbol: '€', name: 'Euro', symbolPosition: SymbolPosition.after),
    Currency(code: 'GBP', symbol: '£', name: 'British Pound'),
    Currency(code: 'JPY', symbol: '¥', name: 'Japanese Yen', decimalDigits: 0),
    Currency(code: 'SAR', symbol: '﷼', name: 'Saudi Riyal', symbolPosition: SymbolPosition.after),
    Currency(code: 'AED', symbol: 'د.إ', name: 'UAE Dirham', symbolPosition: SymbolPosition.after),
    Currency(code: 'EGP', symbol: 'E£', name: 'Egyptian Pound'),
  ];

  static Currency fromCode(String code) {
    return supportedCurrencies.firstWhere(
      (c) => c.code == code,
      orElse: () => supportedCurrencies.first,
    );
  }
}

class CurrencyService {
  final SharedPreferences _prefs;
  static const String _currencyKey = 'currency_code';
  final _currencyController = StreamController<Currency>.broadcast();

  CurrencyService(this._prefs);

  Stream<Currency> get currencyStream => _currencyController.stream;

  Currency getCurrency() {
    final code = _prefs.getString(_currencyKey);
    return Currency.fromCode(code ?? 'USD');
  }

  Future<void> setCurrency(String code) async {
    await _prefs.setString(_currencyKey, code);
    _currencyController.add(Currency.fromCode(code));
  }

  String format(int cents, {bool showSymbol = true}) {
    final currency = getCurrency();
    final value = cents / 100.0;

    // Always use the app's current locale for digit rendering so that
    // selecting EGP (or SAR/AED) does not switch digits to Arabic-Indic
    // when the UI language is English or French.
    final appLocale = Intl.getCurrentLocale();
    final numberFormatter = NumberFormat.decimalPatternDigits(
      locale: appLocale,
      decimalDigits: currency.decimalDigits,
    );
    final formatted = numberFormatter.format(value);

    if (!showSymbol) return formatted;

    // Place symbol according to the currency's defined position
    if (currency.symbolPosition == SymbolPosition.after) {
      return '$formatted ${currency.symbol}';
    }
    return '${currency.symbol}$formatted';
  }
  
  /// Format cents as a display string with currency symbol
  String formatCents(int cents, {bool showSymbol = true}) => format(cents, showSymbol: showSymbol);

  /// Convert cents to a decimal string for form fields (e.g. 1999 → "19.99")
  String centsToDecimalString(int cents) {
    final value = cents / 100.0;
    return value.toStringAsFixed(2);
  }

  /// Convert a decimal string from form fields to cents (e.g. "19.99" → 1999)
  int decimalStringToCents(String decimalString) {
    final parsed = double.tryParse(decimalString) ?? 0.0;
    return (parsed * 100).round();
  }

  // Expose current properties
  String get currencyCode => getCurrency().code;
  String get currencySymbol => getCurrency().symbol;
  SymbolPosition get symbolPosition => getCurrency().symbolPosition;

  Future<void> dispose() async {
    await _currencyController.close();
  }
}
