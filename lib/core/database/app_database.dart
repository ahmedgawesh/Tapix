import 'package:drift/drift.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'tables/settings.dart';
import 'tables/users.dart';
import 'tables/products.dart';
import 'tables/parties.dart';
import 'tables/loyalty.dart';
import 'tables/people.dart';
import 'tables/transactions.dart';
import 'tables/accounting.dart';
import 'tables/audit.dart';
import 'tables/barcode.dart';
import 'converters/money_converter.dart';
import 'converters/json_converter.dart';
import 'converters/timestamp_converter.dart';
import 'daos/product_dao.dart';
import 'daos/product_variant_dao.dart';
import 'daos/product_color_dao.dart';
import 'daos/category_dao.dart';
import 'daos/size_dao.dart';
import 'daos/sale_dao.dart';
import 'daos/customer_dao.dart';
import 'daos/accounting_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/barcode_template_dao.dart';
import 'daos/purchase_dao.dart';

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
    LoyaltyTiers,
    LoyaltyPointTransactions,
    LoyaltyRewards,
    CustomerRewardRedemptions,
    LoyaltySettingsTable,
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
    BarcodeTemplates,
    PrintHistories,
  ],
  daos: [
    ProductDao,
    ProductVariantDao,
    ProductColorDao,
    CategoryDao,
    SizeDao,
    SaleDao,
    CustomerDao,
    AccountingDao,
    SettingsDao,
    BarcodeTemplateDao,
    PurchaseDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  
  AppDatabase.connect(DatabaseConnection connection) : super.connect(connection);

  Future<void> _dedupeUniqueSkuBarcodeIfNeeded() async {
    await customStatement(
      'UPDATE product_variants SET sku = NULL WHERE sku IS NOT NULL AND id NOT IN (SELECT MIN(id) FROM product_variants WHERE sku IS NOT NULL GROUP BY sku)',
    );
    await customStatement(
      'UPDATE product_variants SET barcode = NULL WHERE barcode IS NOT NULL AND id NOT IN (SELECT MIN(id) FROM product_variants WHERE barcode IS NOT NULL GROUP BY barcode)',
    );
    await customStatement(
      'UPDATE products SET sku = NULL WHERE sku IS NOT NULL AND id NOT IN (SELECT MIN(id) FROM products WHERE sku IS NOT NULL GROUP BY sku)',
    );
    await customStatement(
      'UPDATE products SET barcode = NULL WHERE barcode IS NOT NULL AND id NOT IN (SELECT MIN(id) FROM products WHERE barcode IS NOT NULL GROUP BY barcode)',
    );
  }

  Future<void> _repairProductVariantsSkuNullabilityIfNeeded() async {
    var foreignKeysDisabled = false;
    try {
      // Some SQLite builds are picky about the `pragma_table_info(...).notnull` column name.
      // To keep this repair robust across platforms, inspect the CREATE TABLE DDL instead.
      final ddlRow = await customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'product_variants'",
      ).getSingleOrNull();

      final ddl = ddlRow?.readNullable<String>('sql') ?? '';
      if (ddl.isEmpty) {
        return;
      }

      final skuNotNull = RegExp(
        r'\bsku\b[^,]*\bNOT\s+NULL\b',
        caseSensitive: false,
      ).hasMatch(ddl);
      final barcodeNotNull = RegExp(
        r'\bbarcode\b[^,]*\bNOT\s+NULL\b',
        caseSensitive: false,
      ).hasMatch(ddl);

      if (!skuNotNull && !barcodeNotNull) {
        return;
      }

      debugPrint('DB schema fix: rebuilding product_variants to relax NOT NULL constraints');
      await _ensureSchemaIntegrity();

      await customStatement('PRAGMA foreign_keys = OFF');
      foreignKeysDisabled = true;
      await customStatement('ALTER TABLE product_variants RENAME TO product_variants__old');

      final wholesaleColumnRow = await customSelect(
        "SELECT COUNT(*) as cnt FROM pragma_table_info('product_variants__old') WHERE name = 'wholesale_price_cents'",
      ).getSingle();
      final hasWholesalePriceCents = wholesaleColumnRow.read<int>('cnt') > 0;

      await customStatement('''
CREATE TABLE product_variants (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  sku TEXT UNIQUE,
  barcode TEXT UNIQUE,
  color_id INTEGER REFERENCES product_colors (id) ON DELETE RESTRICT,
  size_id INTEGER REFERENCES sizes (id) ON DELETE RESTRICT,
  cost_cents INTEGER NOT NULL,
  price_cents INTEGER NOT NULL,
  wholesale_price_cents INTEGER,
  price_adjustment_cents INTEGER NOT NULL DEFAULT 0,
  stock_quantity INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
)
''');

      if (hasWholesalePriceCents) {
        await customStatement('''
INSERT INTO product_variants (
  id,
  product_id,
  sku,
  barcode,
  color_id,
  size_id,
  cost_cents,
  price_cents,
  wholesale_price_cents,
  price_adjustment_cents,
  stock_quantity,
  is_active,
  created_at,
  updated_at
)
SELECT
  id,
  product_id,
  NULLIF(sku, ''),
  NULLIF(barcode, ''),
  color_id,
  size_id,
  COALESCE(cost_cents, 0),
  COALESCE(price_cents, 0),
  wholesale_price_cents,
  COALESCE(price_adjustment_cents, 0),
  COALESCE(stock_quantity, 0),
  COALESCE(is_active, 1),
  COALESCE(created_at, CURRENT_TIMESTAMP),
  COALESCE(updated_at, CURRENT_TIMESTAMP)
FROM product_variants__old
''');
      } else {
        await customStatement('''
INSERT INTO product_variants (
  id,
  product_id,
  sku,
  barcode,
  color_id,
  size_id,
  cost_cents,
  price_cents,
  wholesale_price_cents,
  price_adjustment_cents,
  stock_quantity,
  is_active,
  created_at,
  updated_at
)
SELECT
  id,
  product_id,
  NULLIF(sku, ''),
  NULLIF(barcode, ''),
  color_id,
  size_id,
  COALESCE(cost_cents, 0),
  COALESCE(price_cents, 0),
  NULL,
  COALESCE(price_adjustment_cents, 0),
  COALESCE(stock_quantity, 0),
  COALESCE(is_active, 1),
  COALESCE(created_at, CURRENT_TIMESTAMP),
  COALESCE(updated_at, CURRENT_TIMESTAMP)
FROM product_variants__old
''');
      }

      await customStatement('DROP TABLE product_variants__old');
      await customStatement('PRAGMA foreign_keys = ON');
      foreignKeysDisabled = false;
    } catch (e, st) {
      debugPrint('DB schema fix failed (product_variants rebuild): $e');
      debugPrint('$st');
    } finally {
      if (foreignKeysDisabled) {
        try {
          await customStatement('PRAGMA foreign_keys = ON');
        } catch (_) {
          // ignore
        }
      }
    }
  }

  Future<void> _safeAddColumn(String table, String column, String type) async {
    final result = await customSelect(
      "SELECT COUNT(*) as cnt FROM pragma_table_info('$table') WHERE name = '$column'",
    ).getSingle();
    
    final exists = result.read<int>('cnt') > 0;
    if (!exists) {
      debugPrint('DB schema fix: adding missing column $table.$column ($type)');
      await customStatement('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _ensureSchemaIntegrity() async {
    debugPrint('Ensuring schema integrity...');
    await _safeAddColumn('products', 'barcode', 'TEXT');
    await _safeAddColumn('products', 'name_ar', 'TEXT');
    await _safeAddColumn('products', 'name_fr', 'TEXT');
    await _safeAddColumn('products', 'supplier_id', 'INTEGER REFERENCES suppliers(id)');
    await _safeAddColumn('products', 'wholesale_price_cents', 'INTEGER');
    await _safeAddColumn('products', 'min_quantity', 'INTEGER DEFAULT 0');

    // Ensure boolean-ish and tax fields exist for older DBs.
    // Drift stores booleans as INTEGER 0/1.
    await _safeAddColumn('products', 'has_variants', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('products', 'is_taxable', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('products', 'tax_rate_bps', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('products', 'track_inventory', 'INTEGER NOT NULL DEFAULT 1');
    await _safeAddColumn('products', 'stock_quantity', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('products', 'image_path', 'TEXT');
    await _safeAddColumn('products', 'is_active', 'INTEGER NOT NULL DEFAULT 1');

    await _safeAddColumn('product_variants', 'barcode', 'TEXT');
    await _safeAddColumn('product_variants', 'price_adjustment_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('product_variants', 'cost_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('product_variants', 'price_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('product_variants', 'wholesale_price_cents', 'INTEGER');
    
    await _safeAddColumn('sizes', 'sort_order', 'INTEGER NOT NULL DEFAULT 0');

    // Customers advanced fields (segmentation + loyalty + analytics)
    await _safeAddColumn('customers', 'segment', "TEXT NOT NULL DEFAULT 'retail'");
    await _safeAddColumn('customers', 'loyalty_tier_id', 'INTEGER REFERENCES loyalty_tiers(id)');
    await _safeAddColumn('customers', 'loyalty_points_balance', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('customers', 'total_spent_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('customers', 'total_transactions', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('customers', 'last_transaction_at', 'TEXT');

    // Loyalty program tables (if missing)
    await customStatement('''
CREATE TABLE IF NOT EXISTS loyalty_tiers (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  name_ar TEXT,
  name_fr TEXT,
  min_points INTEGER NOT NULL DEFAULT 0,
  max_points INTEGER,
  points_multiplier REAL NOT NULL DEFAULT 1.0,
  discount_percent REAL NOT NULL DEFAULT 0.0,
  color TEXT NOT NULL DEFAULT '#CD7F32',
  icon TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''');

    await customStatement('''
CREATE TABLE IF NOT EXISTS loyalty_point_transactions (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  transaction_type TEXT NOT NULL,
  points INTEGER NOT NULL,
  balance_after INTEGER NOT NULL,
  source TEXT,
  reference_id INTEGER,
  reference_type TEXT,
  description TEXT,
  expires_at TEXT,
  transaction_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''');

    await customStatement('''
CREATE TABLE IF NOT EXISTS loyalty_rewards (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  name_ar TEXT,
  name_fr TEXT,
  description TEXT,
  description_ar TEXT,
  description_fr TEXT,
  reward_type TEXT NOT NULL,
  points_cost INTEGER NOT NULL,
  value_cents INTEGER,
  value_percent REAL,
  product_id INTEGER,
  min_tier_id INTEGER REFERENCES loyalty_tiers(id) ON DELETE SET NULL,
  max_redemptions_per_customer INTEGER,
  total_redemptions INTEGER NOT NULL DEFAULT 0,
  max_total_redemptions INTEGER,
  valid_from TEXT,
  valid_until TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''');

    await customStatement('''
CREATE TABLE IF NOT EXISTS customer_reward_redemptions (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  reward_id INTEGER NOT NULL REFERENCES loyalty_rewards(id) ON DELETE RESTRICT,
  points_spent INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  sale_id INTEGER,
  used_at TEXT,
  expires_at TEXT,
  redeemed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''');

    await customStatement('''
CREATE TABLE IF NOT EXISTS loyalty_settings (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  points_per_currency_unit INTEGER NOT NULL DEFAULT 1,
  min_spend_for_points INTEGER NOT NULL DEFAULT 0,
  points_expiry_days INTEGER,
  referral_bonus_points INTEGER NOT NULL DEFAULT 100,
  signup_bonus_points INTEGER NOT NULL DEFAULT 50,
  review_bonus_points INTEGER NOT NULL DEFAULT 10,
  is_enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''');

    debugPrint('Schema integrity check completed.');
  }

  @override
  int get schemaVersion => 10009;

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

        // Migration from 10000 to 10001: Add barcode, name_ar, name_fr columns to products and product_variants
        if (from < 10001) {
          await _safeAddColumn('products', 'barcode', 'TEXT');
          await _safeAddColumn('product_variants', 'barcode', 'TEXT');
          await _safeAddColumn('products', 'name_ar', 'TEXT');
          await _safeAddColumn('products', 'name_fr', 'TEXT');

          await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL');
          await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_barcode ON product_variants(barcode) WHERE barcode IS NOT NULL');
        }

        // Migration from 10001 to 10002: Add supplier_id and wholesale_price_cents columns to products
        if (from < 10002) {
          await _safeAddColumn('products', 'supplier_id', 'INTEGER REFERENCES suppliers(id)');
          await _safeAddColumn('products', 'wholesale_price_cents', 'INTEGER');
        }

        // Migration from 10002 to 10003: Ensure all columns exist (fix for failed migrations)
        if (from < 10003) {
          await _ensureSchemaIntegrity();
        }
        
        // Migration 10003 -> 10004: Force integrity check again to ensure variants/sizes support
        if (from < 10004) {
          await _ensureSchemaIntegrity();
        }
        if (from < 10006) {
          await _repairProductVariantsSkuNullabilityIfNeeded();
        }

        // Migration 10006 -> 10007: Add barcode templates and print history tables
        if (from < 10007) {
          await m.createTable(barcodeTemplates);
          await m.createTable(printHistories);
          await _seedDefaultBarcodeTemplates();
        }

        // Migration 10007 -> 10008: Add wholesale_price_cents to product_variants
        if (from < 10008) {
          await _safeAddColumn('product_variants', 'wholesale_price_cents', 'INTEGER');
        }

        // Migration 10008 -> 10009: Customers advanced fields + loyalty tables
        if (from < 10009) {
          await _safeAddColumn('customers', 'segment', "TEXT NOT NULL DEFAULT 'retail'");
          await _safeAddColumn('customers', 'loyalty_tier_id', 'INTEGER REFERENCES loyalty_tiers(id)');
          await _safeAddColumn('customers', 'loyalty_points_balance', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('customers', 'total_spent_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('customers', 'total_transactions', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('customers', 'last_transaction_at', 'TEXT');

          // Create loyalty tables for existing DBs
          await m.createTable(loyaltyTiers);
          await m.createTable(loyaltyPointTransactions);
          await m.createTable(loyaltyRewards);
          await m.createTable(customerRewardRedemptions);
          await m.createTable(loyaltySettingsTable);
        }

        await _createIndexes();
        await _seedInitialData();
      },
      beforeOpen: (details) async {
        debugPrint(
          'DB open: wasCreated=${details.wasCreated} hadUpgrade=${details.hadUpgrade} versionBefore=${details.versionBefore} versionNow=${details.versionNow}',
        );
        await customStatement('PRAGMA foreign_keys = ON');
        await _ensureSchemaIntegrity();
        await _repairProductVariantsSkuNullabilityIfNeeded();
        await _dedupeUniqueSkuBarcodeIfNeeded();
        try {
          await _seedDefaultBarcodeTemplates();
        } catch (e, st) {
          debugPrint('DB seed skipped (barcode templates): $e');
          debugPrint('$st');
        }
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
    await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL');
    await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_barcode ON product_variants(barcode) WHERE barcode IS NOT NULL');
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_product_color_size_unique '
      'ON product_variants(product_id, IFNULL(color_id, -1), IFNULL(size_id, -1))',
    );
    await customStatement('CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(is_active)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_suppliers_active ON suppliers(is_active)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_currency_active ON currencies(is_active)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_barcode_templates_default ON barcode_templates(is_default)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_print_history_product ON print_histories(product_id, print_date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_print_history_date ON print_histories(print_date)');
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

    await _seedDefaultColors();
    await _seedStandardSizes();
    try {
      await _seedDefaultBarcodeTemplates();
    } catch (e, st) {
      debugPrint('DB seed skipped (barcode templates): $e');
      debugPrint('$st');
    }
  }

  Future<void> _seedDefaultColors() async {
    Future<void> upsertColor({
      required String name,
      String? hexCode,
    }) async {
      final existing = await (select(productColors)
            ..where((c) => c.name.equals(name)))
          .getSingleOrNull();

      if (existing == null) {
        await into(productColors).insert(
          ProductColorsCompanion.insert(
            name: name,
            hexCode: Value(hexCode),
          ),
        );
      }
    }

    // Seed common colors
    await upsertColor(name: 'Red', hexCode: '#FF0000');
    await upsertColor(name: 'Green', hexCode: '#00FF00');
    await upsertColor(name: 'Blue', hexCode: '#0000FF');
    await upsertColor(name: 'Yellow', hexCode: '#FFFF00');
    await upsertColor(name: 'Orange', hexCode: '#FFA500');
    await upsertColor(name: 'Purple', hexCode: '#800080');
    await upsertColor(name: 'Pink', hexCode: '#FFC0CB');
    await upsertColor(name: 'Brown', hexCode: '#964B00');
    await upsertColor(name: 'Gray', hexCode: '#808080');
    await upsertColor(name: 'Black', hexCode: '#000000');
    await upsertColor(name: 'White', hexCode: '#FFFFFF');
  }

  Future<void> _seedStandardSizes() async {
    Future<void> upsertSize({
      required String name,
      String? description,
      required int sortOrder,
    }) async {
      final existing = await (select(sizes)
            ..where((s) => s.name.equals(name)))
          .getSingleOrNull();

      if (existing == null) {
        await into(sizes).insert(
          SizesCompanion.insert(
            name: name,
            description: Value(description),
            sortOrder: Value(sortOrder),
          ),
        );
      }
    }

    await upsertSize(name: 'Extra Small', description: 'XS', sortOrder: 1);
    await upsertSize(name: 'Small', description: 'S', sortOrder: 2);
    await upsertSize(name: 'Medium', description: 'M', sortOrder: 3);
    await upsertSize(name: 'Large', description: 'L', sortOrder: 4);
    await upsertSize(name: 'Extra Large', description: 'XL', sortOrder: 5);
    await upsertSize(name: 'Double Extra Large', description: 'XXL', sortOrder: 6);
  }

  Future<void> _seedDefaultBarcodeTemplates() async {
    Future<void> upsertTemplate({
      required String name,
      required String description,
      required String paperSize,
      required double widthMm,
      required double heightMm,
      required bool isDefault,
    }) async {
      final existing = await (select(barcodeTemplates)
            ..where((t) => t.name.equals(name)))
          .getSingleOrNull();

      if (existing == null) {
        await into(barcodeTemplates).insert(
          BarcodeTemplatesCompanion.insert(
            name: name,
            description: Value(description),
            layoutConfig: '{}',
            paperSize: Value(paperSize),
            widthMm: Value(widthMm),
            heightMm: Value(heightMm),
            includeName: const Value(true),
            includePrice: const Value(true),
            includeSku: const Value(false),
            includeCompanyName: const Value(false),
            includeVariantInfo: const Value(false),
            barcodeType: const Value('auto'),
            isDefault: Value(isDefault),
          ),
        );
      }
    }

    await upsertTemplate(
      name: 'Small Label (58mm)',
      description: 'Small thermal label for 58mm printers',
      paperSize: '58mm',
      widthMm: 58,
      heightMm: 40,
      isDefault: true,
    );

    await upsertTemplate(
      name: 'Medium Label (80mm)',
      description: 'Medium thermal label for 80mm printers',
      paperSize: '80mm',
      widthMm: 80,
      heightMm: 50,
      isDefault: false,
    );

    await upsertTemplate(
      name: 'Adjustable Label',
      description: 'Adjustable A4 sheet label',
      paperSize: 'A4',
      widthMm: 100,
      heightMm: 70,
      isDefault: false,
    );
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    return openDatabase();
  });
}
