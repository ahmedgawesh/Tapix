import 'dart:async';
import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SymbolPosition { before, after }

class Currency {
  final String code;
  final String symbol;
  final String name;
  final SymbolPosition symbolPosition;
  final int decimalDigits;
  final bool isCustom;

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    this.symbolPosition = SymbolPosition.before,
    this.decimalDigits = 2,
    this.isCustom = false,
  });

  static const List<Currency> supportedCurrencies = [
    // Major currencies
    Currency(code: 'USD', symbol: '\$', name: 'US Dollar'),
    Currency(
      code: 'EUR',
      symbol: '€',
      name: 'Euro',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(code: 'GBP', symbol: '£', name: 'British Pound'),
    Currency(code: 'JPY', symbol: '¥', name: 'Japanese Yen', decimalDigits: 0),
    Currency(code: 'CHF', symbol: 'CHF', name: 'Swiss Franc'),
    Currency(code: 'CAD', symbol: 'CA\$', name: 'Canadian Dollar'),
    Currency(code: 'AUD', symbol: 'A\$', name: 'Australian Dollar'),
    Currency(code: 'NZD', symbol: 'NZ\$', name: 'New Zealand Dollar'),
    Currency(code: 'CNY', symbol: '¥', name: 'Chinese Yuan'),
    Currency(code: 'HKD', symbol: 'HK\$', name: 'Hong Kong Dollar'),
    Currency(code: 'SGD', symbol: 'S\$', name: 'Singapore Dollar'),
    Currency(
      code: 'SEK',
      symbol: 'kr',
      name: 'Swedish Krona',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'NOK',
      symbol: 'kr',
      name: 'Norwegian Krone',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'DKK',
      symbol: 'kr',
      name: 'Danish Krone',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'KRW',
      symbol: '₩',
      name: 'South Korean Won',
      decimalDigits: 0,
    ),
    Currency(code: 'INR', symbol: '₹', name: 'Indian Rupee'),
    Currency(
      code: 'RUB',
      symbol: '₽',
      name: 'Russian Ruble',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(code: 'BRL', symbol: 'R\$', name: 'Brazilian Real'),
    Currency(code: 'MXN', symbol: 'MX\$', name: 'Mexican Peso'),
    Currency(code: 'ZAR', symbol: 'R', name: 'South African Rand'),
    Currency(code: 'TRY', symbol: '₺', name: 'Turkish Lira'),
    Currency(
      code: 'PLN',
      symbol: 'zł',
      name: 'Polish Zloty',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(code: 'THB', symbol: '฿', name: 'Thai Baht'),
    Currency(
      code: 'IDR',
      symbol: 'Rp',
      name: 'Indonesian Rupiah',
      decimalDigits: 0,
    ),
    Currency(code: 'MYR', symbol: 'RM', name: 'Malaysian Ringgit'),
    Currency(code: 'PHP', symbol: '₱', name: 'Philippine Peso'),
    Currency(
      code: 'VND',
      symbol: '₫',
      name: 'Vietnamese Dong',
      decimalDigits: 0,
    ),
    Currency(
      code: 'CZK',
      symbol: 'Kč',
      name: 'Czech Koruna',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'HUF',
      symbol: 'Ft',
      name: 'Hungarian Forint',
      decimalDigits: 0,
    ),
    Currency(code: 'ILS', symbol: '₪', name: 'Israeli Shekel'),
    Currency(
      code: 'CLP',
      symbol: 'CL\$',
      name: 'Chilean Peso',
      decimalDigits: 0,
    ),
    Currency(
      code: 'COP',
      symbol: 'COL\$',
      name: 'Colombian Peso',
      decimalDigits: 0,
    ),
    Currency(code: 'ARS', symbol: 'AR\$', name: 'Argentine Peso'),
    Currency(code: 'PEN', symbol: 'S/.', name: 'Peruvian Sol'),
    Currency(code: 'NGN', symbol: '₦', name: 'Nigerian Naira'),
    Currency(code: 'KES', symbol: 'KSh', name: 'Kenyan Shilling'),
    Currency(code: 'GHS', symbol: 'GH₵', name: 'Ghanaian Cedi'),
    Currency(code: 'TWD', symbol: 'NT\$', name: 'Taiwan Dollar'),
    Currency(code: 'PKR', symbol: '₨', name: 'Pakistani Rupee'),
    Currency(code: 'BDT', symbol: '৳', name: 'Bangladeshi Taka'),
    Currency(
      code: 'RON',
      symbol: 'lei',
      name: 'Romanian Leu',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(code: 'UAH', symbol: '₴', name: 'Ukrainian Hryvnia'),
    // Middle East & North Africa
    Currency(
      code: 'SAR',
      symbol: '﷼',
      name: 'Saudi Riyal',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'AED',
      symbol: 'د.إ',
      name: 'UAE Dirham',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(code: 'EGP', symbol: 'E£', name: 'Egyptian Pound'),
    Currency(
      code: 'QAR',
      symbol: 'ر.ق',
      name: 'Qatari Riyal',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'KWD',
      symbol: 'د.ك',
      name: 'Kuwaiti Dinar',
      decimalDigits: 3,
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'BHD',
      symbol: 'د.ب',
      name: 'Bahraini Dinar',
      decimalDigits: 3,
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'OMR',
      symbol: 'ر.ع',
      name: 'Omani Rial',
      decimalDigits: 3,
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'JOD',
      symbol: 'د.ا',
      name: 'Jordanian Dinar',
      decimalDigits: 3,
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'IQD',
      symbol: 'ع.د',
      name: 'Iraqi Dinar',
      decimalDigits: 0,
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'LBP',
      symbol: 'ل.ل',
      name: 'Lebanese Pound',
      decimalDigits: 0,
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'MAD',
      symbol: 'د.م',
      name: 'Moroccan Dirham',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'TND',
      symbol: 'د.ت',
      name: 'Tunisian Dinar',
      decimalDigits: 3,
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'DZD',
      symbol: 'د.ج',
      name: 'Algerian Dinar',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'LYD',
      symbol: 'ل.د',
      name: 'Libyan Dinar',
      decimalDigits: 3,
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'SDG',
      symbol: 'ج.س',
      name: 'Sudanese Pound',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'YER',
      symbol: 'ر.ي',
      name: 'Yemeni Rial',
      symbolPosition: SymbolPosition.after,
    ),
    Currency(
      code: 'SYP',
      symbol: 'ل.س',
      name: 'Syrian Pound',
      symbolPosition: SymbolPosition.after,
    ),
  ];

  static List<Currency> _customCurrencies = [];

  static List<Currency> get allCurrencies => [
    ...supportedCurrencies,
    ..._customCurrencies,
  ];

  static void setCustomCurrencies(List<Currency> currencies) {
    _customCurrencies = currencies;
  }

  static void addCustomCurrency(Currency currency) {
    _customCurrencies.removeWhere((c) => c.code == currency.code);
    _customCurrencies.add(currency);
  }

  static Currency fromCode(String code) {
    return allCurrencies.firstWhere(
      (c) => c.code == code,
      orElse: () => supportedCurrencies.first,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'symbol': symbol,
    'name': name,
    'symbolPosition': symbolPosition == SymbolPosition.after
        ? 'after'
        : 'before',
    'decimalDigits': decimalDigits,
    'isCustom': isCustom,
  };

  factory Currency.fromJson(Map<String, dynamic> json) => Currency(
    code: json['code'] as String,
    symbol: json['symbol'] as String,
    name: json['name'] as String,
    symbolPosition: json['symbolPosition'] == 'after'
        ? SymbolPosition.after
        : SymbolPosition.before,
    decimalDigits: json['decimalDigits'] as int? ?? 2,
    isCustom: json['isCustom'] as bool? ?? true,
  );
}

class CurrencyService {
  final SharedPreferences _prefs;
  static const String _currencyKey = 'currency_code';
  static const String _customCurrenciesKey = 'custom_currencies';
  final _currencyController = StreamController<Currency>.broadcast();

  final Future<void> Function(String)? validateCurrencyChange;
  final Future<void> Function(String, int?)? validateDefinitionChange;

  CurrencyService(
    this._prefs, {
    this.validateCurrencyChange,
    this.validateDefinitionChange,
  }) {
    _loadCustomCurrencies();
  }

  void _loadCustomCurrencies() {
    final jsonStr = _prefs.getString(_customCurrenciesKey);
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
        final customs = list
            .map((e) => Currency.fromJson(e as Map<String, dynamic>))
            .toList();
        Currency.setCustomCurrencies(customs);
      } catch (_) {
        // ignore corrupt data
      }
    }
  }

  Future<void> _saveCustomCurrencies() async {
    final list = Currency._customCurrencies.map((c) => c.toJson()).toList();
    await _prefs.setString(_customCurrenciesKey, jsonEncode(list));
  }

  Future<void> addCustomCurrency(Currency currency) async {
    await validateDefinitionChange?.call(currency.code, currency.decimalDigits);
    Currency.addCustomCurrency(currency);
    await _saveCustomCurrencies();
  }

  Future<void> removeCustomCurrency(String code) async {
    await validateDefinitionChange?.call(code, null);
    Currency._customCurrencies.removeWhere((c) => c.code == code);
    await _saveCustomCurrencies();
  }

  List<Currency> get customCurrencies =>
      List.unmodifiable(Currency._customCurrencies);

  Stream<Currency> get currencyStream => _currencyController.stream;

  Currency getCurrency() {
    final code = _prefs.getString(_currencyKey);
    return Currency.fromCode(code ?? 'USD');
  }

  Future<void> setCurrency(String code) async {
    await validateCurrencyChange?.call(code);
    await _prefs.setString(_currencyKey, code);
    _currencyController.add(Currency.fromCode(code));
  }

  String format(int cents, {bool showSymbol = true}) {
    final currency = getCurrency();
    final value = cents / _minorUnitFactor(currency.decimalDigits);

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
  String formatCents(int cents, {bool showSymbol = true}) =>
      format(cents, showSymbol: showSymbol);

  /// Convert cents to a decimal string for form fields (e.g. 1999 → "19.99")
  String centsToDecimalString(int cents) {
    final digits = getCurrency().decimalDigits;
    // Use integer parts so editing an amount does not lose a minor unit to
    // floating-point conversion. The selected currency defines its scale.
    final factor = _minorUnitFactor(digits);
    final absolute = cents.abs();
    final sign = cents < 0 ? '-' : '';
    final whole = absolute ~/ factor;
    if (digits == 0) return '$sign$whole';
    final fraction = (absolute % factor).toString().padLeft(digits, '0');
    return '$sign$whole.$fraction';
  }

  static int _minorUnitFactor(int digits) {
    if (digits < 0 || digits > 6) {
      throw ArgumentError.value(
        digits,
        'decimalDigits',
        'Unsupported currency precision',
      );
    }
    var factor = 1;
    for (var i = 0; i < digits; i++) {
      factor *= 10;
    }
    return factor;
  }

  /// Convert a decimal string from form fields to cents (e.g. "19.99" → 1999).
  ///
  /// **Phase 8 — DEPRECATED.** New callers must use
  /// `MoneyInputParser.parseOrZero` (DI-injected), which is currency-aware
  /// (handles 3-decimal-digit currencies like JOD/KWD), Arabic-Indic-digit
  /// aware, and validates instead of silently rounding bad input.
  ///
  /// The implementation here is kept *only* so that legacy callers do not
  /// regress; it has been rewritten to use [Decimal] arithmetic so the
  /// previously-broken IEEE-754 edge case (`99999.99 * 100 → 9999998.999…`
  /// → drops a cent on a missed `.round()`) cannot occur even from
  /// non-migrated UI paths. Always 2-digit (currency-agnostic) — pass a
  /// currency-aware parser if you need any other scale.
  @Deprecated('Use MoneyInputParser.parseOrZero (DI-injected) instead.')
  int decimalStringToCents(String decimalString) {
    final parsed = Decimal.tryParse(decimalString.trim().replaceAll(',', '.'));
    if (parsed == null) return 0;
    final cents = (parsed * Decimal.fromInt(100));
    final big = cents.round(scale: 0).toBigInt();
    return big.isValidInt ? big.toInt() : 0;
  }

  // Expose current properties
  String get currencyCode => getCurrency().code;
  String get currencySymbol => getCurrency().symbol;
  SymbolPosition get symbolPosition => getCurrency().symbolPosition;

  Future<void> dispose() async {
    await _currencyController.close();
  }
}
