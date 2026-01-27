import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SymbolPosition { before, after }

class Currency {
  final String code;
  final String symbol;
  final String name;
  final SymbolPosition symbolPosition;
  final String locale; // For NumberFormat

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    this.symbolPosition = SymbolPosition.before,
    this.locale = 'en_US',
  });

  static const List<Currency> supportedCurrencies = [
    Currency(code: 'USD', symbol: '\$', name: 'US Dollar', locale: 'en_US'),
    Currency(code: 'EUR', symbol: '€', name: 'Euro', locale: 'de_DE'), // Euro generally uses comma decimal
    Currency(code: 'GBP', symbol: '£', name: 'British Pound', locale: 'en_GB'),
    Currency(code: 'JPY', symbol: '¥', name: 'Japanese Yen', locale: 'ja_JP'),
    Currency(code: 'SAR', symbol: '﷼', name: 'Saudi Riyal', symbolPosition: SymbolPosition.after, locale: 'ar_SA'),
    Currency(code: 'AED', symbol: 'د.إ', name: 'UAE Dirham', symbolPosition: SymbolPosition.after, locale: 'ar_AE'),
    Currency(code: 'EGP', symbol: 'E£', name: 'Egyptian Pound', locale: 'ar_EG'),
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
    
    // We can use NumberFormat for locale-aware formatting
    // But we want to strictly follow the symbol and position defined in Currency
    final formatter = NumberFormat.currency(
      locale: currency.locale,
      symbol: showSymbol ? currency.symbol : '',
      decimalDigits: 2,
    );

    // Some locales put symbol at end automatically, but we want control if needed
    // For now, let NumberFormat handle it based on locale which usually is correct
    // But if we want to enforce our SymbolPosition:
    
    // Simple approach using NumberFormat.currency which handles mostly correctly
    return formatter.format(value);
  }
  
  // Expose current properties
  String get currencyCode => getCurrency().code;
  String get currencySymbol => getCurrency().symbol;
  SymbolPosition get symbolPosition => getCurrency().symbolPosition;

  Future<void> dispose() async {
    await _currencyController.close();
  }
}
