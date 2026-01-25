import 'package:drift/drift.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'tables/settings.dart';
import 'tables/users.dart';
import 'tables/products.dart';
import 'tables/parties.dart';
import 'tables/people.dart';
import 'tables/transactions.dart';
import 'tables/accounting.dart';
import 'tables/audit.dart';
import 'converters/money_converter.dart';
import 'converters/json_converter.dart';
import 'converters/timestamp_converter.dart';
import 'daos/product_dao.dart';
import 'daos/product_variant_dao.dart';
import 'daos/product_color_dao.dart';
import 'daos/size_dao.dart';
import 'daos/sale_dao.dart';
import 'daos/customer_dao.dart';
import 'daos/accounting_dao.dart';

import 'database_native.dart' if (dart.library.html) 'database_web.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    Currencies,
    AppSettings,
    StoreLogos,
    ExpenseCategories,
    ProductCategories,
    ProductColors,
    Sizes,
    Products,
    ProductVariants,
    ProductBatches,
    Customers,
    CustomerTransactions,
    Suppliers,
    SupplierTransactions,
    Employees,
    Commissions,
    Sales,
    SaleItems,
    SaleTaxBands,
    SaleReturns,
    SaleReturnItems,
    Purchases,
    PurchaseItems,
    PurchaseReturns,
    PurchaseReturnItems,
    Accounts,
    JournalEntries,
    JournalEntryLines,
    AccountingPeriods,
    Expenses,
    AuditLogs,
    VoidLogs,
    Notifications,
  ],
  daos: [
    ProductDao,
    ProductVariantDao,
    ProductColorDao,
    SizeDao,
    SaleDao,
    CustomerDao,
    AccountingDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  
  AppDatabase.connect(DatabaseConnection connection) : super.connect(connection);

  @override
  int get schemaVersion => 10000;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await _createIndexes();
        await _seedInitialData();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from == to) {
          return;
        }

        await _createIndexes();
        await _seedInitialData();
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  @visibleForTesting
  Future<void> seedInitialDataForTest() => _seedInitialData();

  @visibleForTesting
  Future<void> createIndexesForTest() => _createIndexes();

  Future<void> _createIndexes() async {
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sales_customer_date ON sales(customer_id, sale_date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active, name)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_journal_entry_date ON journal_entries(entry_date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_audit_table_record ON audit_logs(target_table, record_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(is_active)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_suppliers_active ON suppliers(is_active)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_currency_active ON currencies(is_active)');
  }

  Future<void> _seedInitialData() async {
    Future<void> upsertCurrency({
      required String code,
      required String name,
      required String symbol,
      required Decimal exchangeRate,
      bool? isBase,
    }) async {
      final updated = await (update(currencies)
            ..where((c) => c.code.equals(code)))
          .write(
        CurrenciesCompanion(
          name: Value(name),
          symbol: Value(symbol),
          exchangeRate: Value(exchangeRate),
          isBase: isBase == null ? const Value.absent() : Value(isBase),
        ),
      );

      if (updated == 0) {
        await into(currencies).insert(
          CurrenciesCompanion.insert(
            code: code,
            name: name,
            symbol: symbol,
            exchangeRate: exchangeRate,
            isBase: isBase == null ? const Value(false) : Value(isBase),
          ),
        );
      }
    }

    Future<void> upsertAccount({
      required String accountCode,
      required String accountName,
      required String accountType,
      required int currencyId,
    }) async {
      final updated = await (update(accounts)
            ..where((a) => a.accountCode.equals(accountCode)))
          .write(
        AccountsCompanion(
          accountName: Value(accountName),
          accountType: Value(accountType),
          currencyId: Value(currencyId),
        ),
      );

      if (updated == 0) {
        await into(accounts).insert(
          AccountsCompanion.insert(
            accountCode: accountCode,
            accountName: accountName,
            accountType: accountType,
            currencyId: currencyId,
          ),
        );
      }
    }

    Future<void> upsertSetting({
      required String key,
      required String value,
      String? description,
    }) async {
      final updated = await (update(appSettings)
            ..where((s) => s.key.equals(key)))
          .write(
        AppSettingsCompanion(
          value: Value(value),
          description: description == null ? const Value.absent() : Value(description),
        ),
      );

      if (updated == 0) {
        await into(appSettings).insert(
          AppSettingsCompanion.insert(
            key: key,
            value: value,
            description: description == null ? const Value.absent() : Value(description),
          ),
        );
      }
    }

    await upsertCurrency(
      code: 'USD',
      name: 'US Dollar',
      symbol: '\$',
      exchangeRate: Decimal.fromInt(1),
      isBase: true,
    );

    final usd = await (select(currencies)..where((c) => c.code.equals('USD'))).getSingle();
    final usdId = usd.id;

    await upsertCurrency(
      code: 'EUR',
      name: 'Euro',
      symbol: '€',
      exchangeRate: Decimal.parse('0.85'),
    );

    await upsertCurrency(
      code: 'DZD',
      name: 'Algerian Dinar',
      symbol: 'د.ج',
      exchangeRate: Decimal.parse('135.0'),
    );

    await upsertAccount(
      accountCode: '1000',
      accountName: 'Cash',
      accountType: 'Asset',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '1100',
      accountName: 'Accounts Receivable',
      accountType: 'Asset',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '2000',
      accountName: 'Accounts Payable',
      accountType: 'Liability',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '3000',
      accountName: 'Equity',
      accountType: 'Equity',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '4000',
      accountName: 'Sales Revenue',
      accountType: 'Revenue',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '5000',
      accountName: 'Cost of Goods Sold',
      accountType: 'Expense',
      currencyId: usdId,
    );

    await upsertSetting(
      key: 'app_version',
      value: '1.0.0',
      description: 'Application version',
    );

    await upsertSetting(
      key: 'default_currency_id',
      value: usdId.toString(),
      description: 'Default currency ID',
    );
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    return openDatabase();
  });
}
