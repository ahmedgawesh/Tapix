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
import 'daos/employee_dao.dart';
import 'daos/supplier_dao.dart';

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
    Roles,
    Employees,
    Commissions,
    Attendances,
    LeaveRequests,
    Payrolls,
    PayrollDeductions,
    ShiftSchedules,
    EmployeeDocuments,
    OvertimeRules,
    PerformanceMetrics,
    Sales,
    SaleItems,
    SaleTaxBands,
    SaleReturns,
    SaleReturnItems,
    SalePayments,
    Purchases,
    PurchaseItems,
    PurchaseReturns,
    PurchaseReturnItems,
    PurchasePayments,
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
    PurchaseDao,
    AccountingDao,
    SettingsDao,
    BarcodeTemplateDao,
    EmployeeDao,
    SupplierDao,
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

  /// Converts any integer (Unix epoch seconds) DateTime columns to ISO 8601 text.
  /// This is needed after switching Drift from storeDateTimeAsText: false → true.
  /// SQLite's typeof() returns 'integer' for numeric values and 'text' for strings.
  Future<void> _convertIntegerTimestampsToText() async {
    debugPrint('Converting integer timestamps to ISO 8601 text...');

    // Map of table → list of DateTime column names that may contain integer timestamps
    const tableColumns = <String, List<String>>{
      'products': ['created_at', 'updated_at'],
      'product_variants': ['created_at', 'updated_at'],
      'product_batches': ['expiry_date', 'created_at'],
      'sales': ['sale_date', 'due_date', 'created_at', 'updated_at'],
      'sale_items': ['created_at'],
      'sale_returns': ['return_date', 'created_at'],
      'sale_return_items': ['created_at'],
      'sale_payments': ['payment_date', 'created_at'],
      'purchases': ['purchase_date', 'expected_delivery_date', 'due_date', 'created_at', 'updated_at'],
      'purchase_payments': ['payment_date', 'created_at'],
      'purchase_items': ['created_at'],
      'purchase_returns': ['return_date', 'created_at'],
      'purchase_return_items': ['created_at'],
      'customers': ['last_transaction_at', 'created_at', 'updated_at'],
      'customer_transactions': ['created_at'],
      'suppliers': ['created_at', 'updated_at'],
      'supplier_transactions': ['created_at'],
      'employees': ['hire_date', 'termination_date', 'created_at', 'updated_at'],
      'commissions': ['created_at'],
      'attendances': ['attendance_date', 'check_in_time', 'check_out_time', 'created_at', 'updated_at'],
      'leave_requests': ['start_date', 'end_date', 'approved_at', 'created_at', 'updated_at'],
      'payrolls': ['period_start', 'period_end', 'processed_at', 'created_at', 'updated_at'],
      'payroll_deductions': ['created_at'],
      'shift_schedules': ['shift_date', 'start_time', 'end_time', 'created_at', 'updated_at'],
      'employee_documents': ['expiry_date', 'created_at'],
      'overtime_rules': ['created_at', 'updated_at'],
      'performance_metrics': ['created_at', 'updated_at'],
      'accounts': ['created_at'],
      'journal_entries': ['entry_date', 'created_at'],
      'journal_entry_lines': ['created_at'],
      'accounting_periods': ['start_date', 'end_date', 'created_at'],
      'expenses': ['expense_date', 'created_at'],
      'audit_logs': ['created_at'],
      'void_logs': ['voided_at'],
      'notifications': ['created_at'],
      'barcode_templates': ['created_at', 'updated_at'],
      'print_histories': ['print_date'],
      'currencies': ['created_at', 'updated_at'],
      'app_settings': ['created_at', 'updated_at'],
      'users': ['created_at', 'updated_at'],
      'roles': ['created_at', 'updated_at'],
      'loyalty_tiers': ['created_at', 'updated_at'],
      'loyalty_point_transactions': ['expires_at', 'transaction_date', 'created_at'],
      'loyalty_rewards': ['valid_from', 'valid_until', 'created_at', 'updated_at'],
      'customer_reward_redemptions': ['used_at', 'expires_at', 'redeemed_at', 'created_at'],
      'loyalty_settings': ['created_at', 'updated_at'],
    };

    for (final entry in tableColumns.entries) {
      final table = entry.key;
      final columns = entry.value;

      // Check if table exists
      final tableExists = await customSelect(
        "SELECT COUNT(*) as cnt FROM sqlite_master WHERE type = 'table' AND name = '$table'",
      ).getSingle();
      if (tableExists.read<int>('cnt') == 0) continue;

      for (final col in columns) {
        // Check if column exists
        final colExists = await customSelect(
          "SELECT COUNT(*) as cnt FROM pragma_table_info('$table') WHERE name = '$col'",
        ).getSingle();
        if (colExists.read<int>('cnt') == 0) continue;

        // Convert integer timestamps to ISO 8601 text using SQLite's datetime() function.
        // Handle both Unix seconds and milliseconds:
        //   - Values > 10000000000 are likely milliseconds → divide by 1000
        //   - Otherwise treat as seconds
        // Use COALESCE to guarantee NOT NULL columns don't get set to NULL.
        try {
          final sql = 'UPDATE $table SET $col = COALESCE('
              "CASE WHEN $col > 10000000000 THEN datetime($col / 1000, 'unixepoch') "
              "ELSE datetime($col, 'unixepoch') END, "
              "datetime('now')"
              ") WHERE $col IS NOT NULL AND typeof($col) = 'integer'";
          await customStatement(sql);
        } catch (e) {
          debugPrint('Warning: could not convert $table.$col: $e');
        }
      }
    }
    debugPrint('Integer timestamp conversion completed.');
  }

  static const _kSettingIntegerTimestampsConverted =
      'db.integer_timestamps_converted_to_text_v2';

  Future<bool> _appSettingsTableExists() async {
    final result = await customSelect(
      "SELECT COUNT(*) as cnt FROM sqlite_master WHERE type = 'table' AND name = 'app_settings'",
    ).getSingle();
    return result.read<int>('cnt') > 0;
  }

  Future<bool> _getBoolSetting(String key) async {
    if (!await _appSettingsTableExists()) return false;
    final result = await (select(appSettings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return (result?.value ?? '').toLowerCase() == 'true';
  }

  Future<void> _setBoolSetting(String key, bool value, {String? description}) async {
    if (!await _appSettingsTableExists()) return;
    await into(appSettings).insert(
      AppSettingsCompanion(
        key: Value(key),
        value: Value(value ? 'true' : 'false'),
        description:
            description == null ? const Value.absent() : Value(description),
        updatedAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> _convertIntegerTimestampsToTextOnce() async {
    final alreadyConverted = await _getBoolSetting(_kSettingIntegerTimestampsConverted);
    if (alreadyConverted) return;

    await _convertIntegerTimestampsToText();
    await _setBoolSetting(
      _kSettingIntegerTimestampsConverted,
      true,
      description:
          'One-time migration: convert legacy integer DateTime columns to text',
    );
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

    // Employee payroll configuration columns
    await _safeAddColumn('employees', 'pay_period_type', "TEXT NOT NULL DEFAULT 'monthly'");
    await _safeAddColumn('employees', 'working_days_per_period', 'INTEGER NOT NULL DEFAULT 26');
    await _safeAddColumn('employees', 'working_hours_per_day', 'INTEGER NOT NULL DEFAULT 8');
    await _safeAddColumn('employees', 'absence_deduction_rate_bps', 'INTEGER NOT NULL DEFAULT 10000');
    await _safeAddColumn('employees', 'late_deduction_rate_bps', 'INTEGER NOT NULL DEFAULT 2500');

    // Customers advanced fields (segmentation + loyalty + analytics)
    await _safeAddColumn('customers', 'segment', "TEXT NOT NULL DEFAULT 'retail'");
    await _safeAddColumn('customers', 'loyalty_enabled', 'INTEGER NOT NULL DEFAULT 1');
    await _safeAddColumn('customers', 'loyalty_tier_id', 'INTEGER REFERENCES loyalty_tiers(id)');
    await _safeAddColumn('customers', 'loyalty_points_balance', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('customers', 'total_spent_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('customers', 'total_transactions', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('customers', 'last_transaction_at', 'TEXT');

    // Loyalty tiers hybrid benefits columns (for older DBs)
    await _safeAddColumn('loyalty_tiers', 'free_shipping', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('loyalty_tiers', 'free_shipping_min_order_cents', 'INTEGER');
    await _safeAddColumn('loyalty_tiers', 'priority_support', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('loyalty_tiers', 'early_access_days', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('loyalty_tiers', 'exclusive_offers', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('loyalty_tiers', 'birthday_bonus', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('loyalty_tiers', 'birthday_bonus_points', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('loyalty_tiers', 'birthday_discount_percent', 'REAL NOT NULL DEFAULT 0.0');
    await _safeAddColumn('loyalty_tiers', 'badge_text', 'TEXT');

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
  free_shipping INTEGER NOT NULL DEFAULT 0,
  free_shipping_min_order_cents INTEGER,
  priority_support INTEGER NOT NULL DEFAULT 0,
  early_access_days INTEGER NOT NULL DEFAULT 0,
  exclusive_offers INTEGER NOT NULL DEFAULT 0,
  birthday_bonus INTEGER NOT NULL DEFAULT 0,
  birthday_bonus_points INTEGER NOT NULL DEFAULT 0,
  birthday_discount_percent REAL NOT NULL DEFAULT 0.0,
  color TEXT NOT NULL DEFAULT '#CD7F32',
  icon TEXT,
  badge_text TEXT,
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

    // Purchase enhancements (v10015)
    await _safeAddColumn('purchases', 'discount_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('purchases', 'paid_amount_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('purchases', 'payment_method', 'TEXT');
    await _safeAddColumn('purchases', 'supplier_invoice_ref', 'TEXT');
    await _safeAddColumn('purchases', 'notes', 'TEXT');
    await _safeAddColumn('purchases', 'due_date', 'TEXT');
    await _safeAddColumn('purchase_returns', 'status', "TEXT NOT NULL DEFAULT 'draft'");
    await _safeAddColumn('purchase_returns', 'disposition_type', "TEXT NOT NULL DEFAULT 'restock'");
    // Purchase returns accounting totals (v10018)
    await _safeAddColumn('purchase_returns', 'subtotal_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('purchase_returns', 'tax_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('purchase_return_items', 'reason', 'TEXT');

    await customStatement('''
CREATE TABLE IF NOT EXISTS purchase_payments (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  purchase_id INTEGER NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  amount_cents INTEGER NOT NULL,
  currency_id INTEGER NOT NULL REFERENCES currencies(id) ON DELETE RESTRICT,
  payment_method TEXT NOT NULL,
  reference TEXT,
  notes TEXT,
  payment_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''');

    // Sale enhancements (v10016)
    await _safeAddColumn('sales', 'paid_amount_cents', 'INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn('sales', 'notes', 'TEXT');
    await _safeAddColumn('sales', 'due_date', 'TEXT');
    await _safeAddColumn('sale_returns', 'status', "TEXT NOT NULL DEFAULT 'draft'");
    await _safeAddColumn('sale_returns', 'disposition_type', "TEXT NOT NULL DEFAULT 'restock'");
    await _safeAddColumn('sale_returns', 'refund_method', "TEXT NOT NULL DEFAULT 'cash'");
    await _safeAddColumn('sale_return_items', 'reason', 'TEXT');

    await customStatement('''
CREATE TABLE IF NOT EXISTS sale_payments (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  amount_cents INTEGER NOT NULL,
  currency_id INTEGER NOT NULL REFERENCES currencies(id) ON DELETE RESTRICT,
  payment_method TEXT NOT NULL,
  reference TEXT,
  notes TEXT,
  payment_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''');

    debugPrint('Schema integrity check completed.');
  }

  @override
  int get schemaVersion => 10022;

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

        // Migration 10009 -> 10010: Employee management system tables
        if (from < 10010) {
          // Add new columns to employees table
          await _safeAddColumn('employees', 'employee_code', 'TEXT UNIQUE');
          await _safeAddColumn('employees', 'user_id', 'INTEGER REFERENCES users(id) ON DELETE SET NULL');
          await _safeAddColumn('employees', 'name_ar', 'TEXT');
          await _safeAddColumn('employees', 'name_fr', 'TEXT');
          await _safeAddColumn('employees', 'department', 'TEXT');
          await _safeAddColumn('employees', 'role_id', 'INTEGER');
          await _safeAddColumn('employees', 'manager_id', 'INTEGER');
          await _safeAddColumn('employees', 'default_commission_rate_bps', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('employees', 'termination_date', 'TEXT');
          await _safeAddColumn('employees', 'notes', 'TEXT');

          // Add new columns to commissions table
          await _safeAddColumn('commissions', 'period', 'TEXT');
          await _safeAddColumn('commissions', 'status', "TEXT NOT NULL DEFAULT 'pending'");

          // Create new employee management tables
          await m.createTable(roles);
          await m.createTable(attendances);
          await m.createTable(leaveRequests);
          await m.createTable(payrolls);
          await m.createTable(payrollDeductions);
          await m.createTable(shiftSchedules);
          await m.createTable(employeeDocuments);
          await m.createTable(overtimeRules);
          await m.createTable(performanceMetrics);

          // Seed default roles
          await _seedDefaultRoles();
        }

        // Migration 10010 -> 10011: Loyalty tier hybrid benefits columns
        if (from < 10011) {
          await _safeAddColumn('loyalty_tiers', 'free_shipping', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('loyalty_tiers', 'free_shipping_min_order_cents', 'INTEGER');
          await _safeAddColumn('loyalty_tiers', 'priority_support', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('loyalty_tiers', 'early_access_days', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('loyalty_tiers', 'exclusive_offers', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('loyalty_tiers', 'birthday_bonus', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('loyalty_tiers', 'birthday_bonus_points', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('loyalty_tiers', 'birthday_discount_percent', 'REAL NOT NULL DEFAULT 0.0');
          await _safeAddColumn('loyalty_tiers', 'badge_text', 'TEXT');
          
          // Seed default loyalty tiers with hybrid benefits
          await _seedDefaultLoyaltyTiers();
        }

        // Migration 10011 -> 10012: Per-customer loyalty enable/disable
        if (from < 10012) {
          await _safeAddColumn('customers', 'loyalty_enabled', 'INTEGER NOT NULL DEFAULT 1');
        }

        // Migration 10012 -> 10013: Employee payroll configuration columns
        if (from < 10013) {
          await _safeAddColumn('employees', 'pay_period_type', "TEXT NOT NULL DEFAULT 'monthly'");
          await _safeAddColumn('employees', 'working_days_per_period', 'INTEGER NOT NULL DEFAULT 26');
          await _safeAddColumn('employees', 'working_hours_per_day', 'INTEGER NOT NULL DEFAULT 8');
          await _safeAddColumn('employees', 'absence_deduction_rate_bps', 'INTEGER NOT NULL DEFAULT 10000');
          await _safeAddColumn('employees', 'late_deduction_rate_bps', 'INTEGER NOT NULL DEFAULT 2500');
        }

        // Migration 10013 -> 10014: Switch DateTime storage from integer to text (ISO 8601)
        if (from < 10014) {
          await _convertIntegerTimestampsToText();
        }

        // Migration 10014 -> 10015: Enhanced purchase invoices & returns
        if (from < 10015) {
          // Purchases: new columns
          await _safeAddColumn('purchases', 'discount_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('purchases', 'paid_amount_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('purchases', 'payment_method', 'TEXT');
          await _safeAddColumn('purchases', 'supplier_invoice_ref', 'TEXT');
          await _safeAddColumn('purchases', 'notes', 'TEXT');
          await _safeAddColumn('purchases', 'due_date', 'TEXT');

          // PurchaseReturns: status + disposition
          await _safeAddColumn('purchase_returns', 'status', "TEXT NOT NULL DEFAULT 'draft'");
          await _safeAddColumn('purchase_returns', 'disposition_type', "TEXT NOT NULL DEFAULT 'restock'");

          // PurchaseReturnItems: per-item reason
          await _safeAddColumn('purchase_return_items', 'reason', 'TEXT');

          // PurchasePayments table
          await m.createTable(purchasePayments);
        }

        // Migration 10015 -> 10016: Enhanced sales & sale returns
        if (from < 10016) {
          // Sales: new columns
          await _safeAddColumn('sales', 'paid_amount_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('sales', 'notes', 'TEXT');
          await _safeAddColumn('sales', 'due_date', 'TEXT');

          // SaleReturns: status + disposition
          await _safeAddColumn('sale_returns', 'status', "TEXT NOT NULL DEFAULT 'draft'");
          await _safeAddColumn('sale_returns', 'disposition_type', "TEXT NOT NULL DEFAULT 'restock'");

          // SaleReturnItems: per-item reason
          await _safeAddColumn('sale_return_items', 'reason', 'TEXT');

          // SalePayments table
          await m.createTable(salePayments);
        }

        // Migration 10016 -> 10017: Purchase-specific permissions in roles
        if (from < 10017) {
          await _updateRolesWithPurchasePermissions();
        }

        // Migration 10017 -> 10018: Purchase return subtotal/tax totals
        if (from < 10018) {
          await _safeAddColumn('purchase_returns', 'subtotal_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('purchase_returns', 'tax_cents', 'INTEGER NOT NULL DEFAULT 0');
        }

        // Migration 10018 -> 10019: Purchase item discount + expiry date
        if (from < 10019) {
          await _safeAddColumn('purchase_items', 'discount_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('purchase_items', 'expiry_date', 'TEXT');
        }

        // Migration 10019 -> 10020: Purchase return refund method
        if (from < 10020) {
          await _safeAddColumn('purchase_returns', 'refund_method', "TEXT NOT NULL DEFAULT 'credit'");
        }

        // Migration 10020 -> 10021: ERP accounting breakdown on return items & headers
        if (from < 10021) {
          // Purchase return items: proportional breakdown
          await _safeAddColumn('purchase_return_items', 'subtotal_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('purchase_return_items', 'discount_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('purchase_return_items', 'tax_cents', 'INTEGER NOT NULL DEFAULT 0');
          // Purchase returns header: discount breakdown
          await _safeAddColumn('purchase_returns', 'discount_cents', 'INTEGER NOT NULL DEFAULT 0');
          // Sale return items: proportional breakdown
          await _safeAddColumn('sale_return_items', 'subtotal_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('sale_return_items', 'discount_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('sale_return_items', 'tax_cents', 'INTEGER NOT NULL DEFAULT 0');
          // Sale returns header: subtotal, discount, tax breakdown
          await _safeAddColumn('sale_returns', 'subtotal_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('sale_returns', 'discount_cents', 'INTEGER NOT NULL DEFAULT 0');
          await _safeAddColumn('sale_returns', 'tax_cents', 'INTEGER NOT NULL DEFAULT 0');
        }

        // Migration 10021 -> 10022: Supplier transaction number + discount type
        if (from < 10022) {
          await _safeAddColumn('supplier_transactions', 'transaction_number', 'TEXT');
          await _safeAddColumn('supplier_transactions', 'discount_type', 'TEXT');
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
        await _convertIntegerTimestampsToTextOnce();
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
    
    // Employee management indexes
    await customStatement('CREATE INDEX IF NOT EXISTS idx_employees_active ON employees(is_active)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_employees_role ON employees(role_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_employees_manager ON employees(manager_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_employees_department ON employees(department)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_attendances_employee_date ON attendances(employee_id, attendance_date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_attendances_date ON attendances(attendance_date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests(employee_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_payrolls_employee ON payrolls(employee_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_payrolls_period ON payrolls(period_start, period_end)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_payrolls_status ON payrolls(status)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_commissions_employee ON commissions(employee_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_commissions_period ON commissions(period)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_shift_schedules_employee_date ON shift_schedules(employee_id, shift_date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_performance_metrics_employee ON performance_metrics(employee_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_performance_metrics_period ON performance_metrics(period_identifier)');

    // Purchase enhancement indexes
    await customStatement('CREATE INDEX IF NOT EXISTS idx_purchases_status ON purchases(status)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON purchases(supplier_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_purchases_due_date ON purchases(due_date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_purchase_payments_purchase ON purchase_payments(purchase_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_purchase_returns_purchase ON purchase_returns(purchase_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_purchase_returns_status ON purchase_returns(status)');

    // Sale enhancement indexes
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sales_status ON sales(status)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sales_due_date ON sales(due_date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sale_payments_sale ON sale_payments(sale_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sale_returns_sale ON sale_returns(sale_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sale_returns_status ON sale_returns(status)');
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
    try {
      await _seedDefaultLoyaltyTiers();
    } catch (e, st) {
      debugPrint('DB seed skipped (default loyalty tiers): $e');
      debugPrint('$st');
    }
    try {
      await _seedDefaultRoles();
    } catch (e, st) {
      debugPrint('DB seed skipped (default roles): $e');
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

  Future<void> _seedDefaultRoles() async {
    Future<void> upsertRole({
      required String name,
      String? nameAr,
      String? nameFr,
      String? description,
      required String permissions,
      bool isSystemRole = false,
    }) async {
      final existing = await (select(roles)
            ..where((r) => r.name.equals(name)))
          .getSingleOrNull();

      if (existing == null) {
        await into(roles).insert(
          RolesCompanion.insert(
            name: name,
            nameAr: Value(nameAr),
            nameFr: Value(nameFr),
            description: Value(description),
            permissions: Value(permissions),
            isSystemRole: Value(isSystemRole),
          ),
        );
      }
    }

    // Admin role - full access (includes all purchase permissions)
    await upsertRole(
      name: 'admin',
      nameAr: 'مدير النظام',
      nameFr: 'Administrateur',
      description: 'Full system access with all permissions',
      permissions: '["employees.view","employees.create","employees.edit","employees.delete","employees.manage_permissions","payroll.view","payroll.create","payroll.approve","payroll.process","attendance.view","attendance.manage","attendance.approve","performance.view","performance.manage","reports.view","reports.export","settings.view","settings.manage","system.admin","purchases.view","purchases.create","purchases.edit","purchases.delete","purchases.post","purchases.void","purchases.approve","purchases.returns","purchases.payments"]',
      isSystemRole: true,
    );

    // Manager role - team management + purchase management
    await upsertRole(
      name: 'manager',
      nameAr: 'مدير',
      nameFr: 'Gestionnaire',
      description: 'Team management with limited admin access',
      permissions: '["employees.view","employees.edit","attendance.view","attendance.manage","attendance.approve","performance.view","performance.manage","payroll.view","reports.view","reports.team","purchases.view","purchases.create","purchases.edit","purchases.post","purchases.approve","purchases.returns","purchases.payments"]',
      isSystemRole: true,
    );

    // Staff role - basic access + view purchases
    await upsertRole(
      name: 'staff',
      nameAr: 'موظف',
      nameFr: 'Employé',
      description: 'Basic employee access',
      permissions: '["profile.view","profile.edit","attendance.view","attendance.self","performance.view","payslip.view","purchases.view"]',
      isSystemRole: true,
    );

    // Cashier role - POS access + view purchases
    await upsertRole(
      name: 'cashier',
      nameAr: 'كاشير',
      nameFr: 'Caissier',
      description: 'Point of sale and basic operations',
      permissions: '["profile.view","attendance.view","attendance.self","sales.view","sales.create","products.view","customers.view","purchases.view"]',
      isSystemRole: true,
    );

    // Salesperson role - sales focused
    await upsertRole(
      name: 'salesperson',
      nameAr: 'مندوب مبيعات',
      nameFr: 'Vendeur',
      description: 'Sales operations with commission tracking',
      permissions: '["profile.view","attendance.view","attendance.self","sales.view","sales.create","products.view","customers.view","customers.create","performance.view","commission.view","purchases.view"]',
      isSystemRole: true,
    );
  }

  /// Update existing roles with purchase-specific permissions (migration 10017)
  Future<void> _updateRolesWithPurchasePermissions() async {
    // Permission mappings: role name -> purchase permissions to add
    const rolePermissions = <String, List<String>>{
      'admin': [
        'purchases.view', 'purchases.create', 'purchases.edit',
        'purchases.delete', 'purchases.post', 'purchases.void',
        'purchases.approve', 'purchases.returns', 'purchases.payments',
      ],
      'manager': [
        'purchases.view', 'purchases.create', 'purchases.edit',
        'purchases.post', 'purchases.approve',
        'purchases.returns', 'purchases.payments',
      ],
      'staff': ['purchases.view'],
      'cashier': ['purchases.view'],
      'salesperson': ['purchases.view'],
    };

    for (final entry in rolePermissions.entries) {
      final roleName = entry.key;
      final newPerms = entry.value;

      final role = await (select(roles)..where((r) => r.name.equals(roleName))).getSingleOrNull();
      if (role == null) continue;

      // Parse existing permissions JSON array
      final existingPerms = role.permissions;
      // Simple approach: check if purchase permissions already present
      if (existingPerms.contains('purchases.view')) continue;

      // Build new permissions string by inserting before the closing bracket
      final newPermsStr = newPerms.map((p) => '"$p"').join(',');
      final updatedPerms = existingPerms.endsWith(']')
          ? '${existingPerms.substring(0, existingPerms.length - 1)},$newPermsStr]'
          : existingPerms;

      await (update(roles)..where((r) => r.name.equals(roleName)))
          .write(RolesCompanion(permissions: Value(updatedPerms)));
    }
  }

  Future<void> _seedDefaultLoyaltyTiers() async {
    Future<void> upsertTier({
      required String name,
      String? nameAr,
      String? nameFr,
      required int minPoints,
      int? maxPoints,
      required double pointsMultiplier,
      required double discountPercent,
      required bool freeShipping,
      int? freeShippingMinOrderCents,
      required bool prioritySupport,
      required int earlyAccessDays,
      required bool exclusiveOffers,
      required bool birthdayBonus,
      required int birthdayBonusPoints,
      required double birthdayDiscountPercent,
      required String color,
      String? icon,
      String? badgeText,
      required int sortOrder,
    }) async {
      final existing = await (select(loyaltyTiers)
            ..where((t) => t.name.equals(name)))
          .getSingleOrNull();

      if (existing == null) {
        await into(loyaltyTiers).insert(
          LoyaltyTiersCompanion.insert(
            name: name,
            nameAr: Value(nameAr),
            nameFr: Value(nameFr),
            minPoints: Value(minPoints),
            maxPoints: Value(maxPoints),
            pointsMultiplier: Value(pointsMultiplier),
            discountPercent: Value(discountPercent),
            freeShipping: Value(freeShipping),
            freeShippingMinOrderCents: Value(freeShippingMinOrderCents),
            prioritySupport: Value(prioritySupport),
            earlyAccessDays: Value(earlyAccessDays),
            exclusiveOffers: Value(exclusiveOffers),
            birthdayBonus: Value(birthdayBonus),
            birthdayBonusPoints: Value(birthdayBonusPoints),
            birthdayDiscountPercent: Value(birthdayDiscountPercent),
            color: Value(color),
            icon: Value(icon),
            badgeText: Value(badgeText),
            sortOrder: Value(sortOrder),
          ),
        );
      }
    }

    // Bronze Tier - Entry level, basic benefits
    await upsertTier(
      name: 'Bronze',
      nameAr: 'برونزي',
      nameFr: 'Bronze',
      minPoints: 0,
      maxPoints: 499,
      pointsMultiplier: 1.0,
      discountPercent: 0.0,
      freeShipping: false,
      freeShippingMinOrderCents: null,
      prioritySupport: false,
      earlyAccessDays: 0,
      exclusiveOffers: false,
      birthdayBonus: false,
      birthdayBonusPoints: 0,
      birthdayDiscountPercent: 0.0,
      color: '#CD7F32',
      icon: 'medal',
      badgeText: null,
      sortOrder: 1,
    );

    // Silver Tier - 5% discount, 1.25x points
    await upsertTier(
      name: 'Silver',
      nameAr: 'فضي',
      nameFr: 'Argent',
      minPoints: 500,
      maxPoints: 1499,
      pointsMultiplier: 1.25,
      discountPercent: 5.0,
      freeShipping: false,
      freeShippingMinOrderCents: 10000, // Free shipping on orders > $100
      prioritySupport: false,
      earlyAccessDays: 0,
      exclusiveOffers: false,
      birthdayBonus: true,
      birthdayBonusPoints: 50,
      birthdayDiscountPercent: 5.0,
      color: '#C0C0C0',
      icon: 'medal',
      badgeText: '★',
      sortOrder: 2,
    );

    // Gold Tier - 10% discount, 1.5x points, free shipping
    await upsertTier(
      name: 'Gold',
      nameAr: 'ذهبي',
      nameFr: 'Or',
      minPoints: 1500,
      maxPoints: 4999,
      pointsMultiplier: 1.5,
      discountPercent: 10.0,
      freeShipping: true,
      freeShippingMinOrderCents: 5000, // Free shipping on orders > $50
      prioritySupport: true,
      earlyAccessDays: 1,
      exclusiveOffers: true,
      birthdayBonus: true,
      birthdayBonusPoints: 100,
      birthdayDiscountPercent: 10.0,
      color: '#FFD700',
      icon: 'crown',
      badgeText: '★★',
      sortOrder: 3,
    );

    // Premium Tier - 15% discount, 2x points, all benefits
    await upsertTier(
      name: 'Premium',
      nameAr: 'مميز',
      nameFr: 'Premium',
      minPoints: 5000,
      maxPoints: null, // Unlimited
      pointsMultiplier: 2.0,
      discountPercent: 15.0,
      freeShipping: true,
      freeShippingMinOrderCents: null, // Always free shipping
      prioritySupport: true,
      earlyAccessDays: 3,
      exclusiveOffers: true,
      birthdayBonus: true,
      birthdayBonusPoints: 200,
      birthdayDiscountPercent: 20.0,
      color: '#9B59B6',
      icon: 'gem',
      badgeText: 'VIP',
      sortOrder: 4,
    );
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
