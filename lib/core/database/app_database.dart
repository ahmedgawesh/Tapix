import 'dart:developer' as developer;

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
import 'tables/compliance.dart';
import 'tables/einvoice.dart';
import 'tables/accounting.dart';
import 'tables/audit.dart';
import 'tables/barcode.dart';
import 'tables/inventory.dart';
import 'tables/cheques.dart';
import 'tables/cashier_shifts.dart';
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
import 'daos/adjustment_return_dao.dart';
import 'daos/inventory_adjustment_dao.dart';
import 'daos/cheque_confirmation_dao.dart';

// Phase 1.5 (May 2026): the supplier opening-balance repair migration
// (10032) now delegates to JournalEntryService instead of hand-rolling
// INSERTs + raw `UPDATE accounts SET balance_cents` — the latter bypassed
// the single-writer invariant established in
// docs/adr/0001-pricing-engines-as-sot.md §B.
import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../services/journal_entry_service.dart';

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
    ProductPriceHistories,
    ProductBatches,
    BatchConsumptions,
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
    CashierShifts,
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
    OwnerFinanceTransactions,
    FixedAssets,
    FixedAssetDepreciations,
    AuditLogs,
    VoidLogs,
    Notifications,
    BarcodeTemplates,
    PrintHistories,
    PurchaseReturnAdjustments,
    PurchaseReturnAdjustmentItems,
    SaleReturnAdjustments,
    SaleReturnAdjustmentItems,
    InventoryAdjustments,
    // Phase 2 — compliance & period management
    FiscalPeriods,
    CustomerCreditNotes,
    CustomerCreditNoteApplications,
    // Phase 3 — normalised return reason codes
    ReturnReasonCodes,
    // Phase 4 — e-invoice artifacts (ZATCA / ETA / PEPPOL)
    EInvoiceDocuments,
    // Phase 14.0 — cheque lifecycle sidecar (pending/cleared/bounced/cancelled)
    ChequeConfirmations,
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
    AdjustmentReturnDao,
    InventoryAdjustmentDao,
    ChequeConfirmationDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.connect(DatabaseConnection connection) : super(connection);

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

      debugPrint(
        'DB schema fix: rebuilding product_variants to relax NOT NULL constraints',
      );
      await _ensureSchemaIntegrity();

      await customStatement('PRAGMA foreign_keys = OFF');
      foreignKeysDisabled = true;
      await customStatement(
        'ALTER TABLE product_variants RENAME TO product_variants__old',
      );

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
      'purchases': [
        'purchase_date',
        'expected_delivery_date',
        'due_date',
        'created_at',
        'updated_at',
      ],
      'purchase_payments': ['payment_date', 'created_at'],
      'purchase_items': ['created_at'],
      'purchase_returns': ['return_date', 'created_at'],
      'purchase_return_items': ['created_at'],
      'customers': ['last_transaction_at', 'created_at', 'updated_at'],
      'customer_transactions': ['created_at'],
      'suppliers': ['created_at', 'updated_at'],
      'supplier_transactions': ['created_at'],
      'employees': [
        'hire_date',
        'termination_date',
        'created_at',
        'updated_at',
      ],
      'commissions': ['created_at'],
      'attendances': [
        'attendance_date',
        'check_in_time',
        'check_out_time',
        'created_at',
        'updated_at',
      ],
      'leave_requests': [
        'start_date',
        'end_date',
        'approved_at',
        'created_at',
        'updated_at',
      ],
      'payrolls': [
        'period_start',
        'period_end',
        'processed_at',
        'created_at',
        'updated_at',
      ],
      'payroll_deductions': ['created_at'],
      'shift_schedules': [
        'shift_date',
        'start_time',
        'end_time',
        'created_at',
        'updated_at',
      ],
      'employee_documents': ['expiry_date', 'created_at'],
      'overtime_rules': ['created_at', 'updated_at'],
      'performance_metrics': ['created_at', 'updated_at'],
      'accounts': ['created_at'],
      'journal_entries': ['entry_date', 'created_at'],
      'journal_entry_lines': ['created_at'],
      'accounting_periods': ['start_date', 'end_date', 'created_at'],
      'expenses': ['expense_date', 'created_at'],
      'owner_finance_transactions': [
        'transaction_date',
        'created_at',
        'updated_at',
      ],
      'fixed_assets': [
        'acquisition_date',
        'in_service_date',
        'created_at',
        'updated_at',
      ],
      'fixed_asset_depreciations': ['period_start', 'period_end', 'created_at'],
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
      'loyalty_point_transactions': [
        'expires_at',
        'transaction_date',
        'created_at',
      ],
      'loyalty_rewards': [
        'valid_from',
        'valid_until',
        'created_at',
        'updated_at',
      ],
      'customer_reward_redemptions': [
        'used_at',
        'expires_at',
        'redeemed_at',
        'created_at',
      ],
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
          final sql =
              'UPDATE $table SET $col = COALESCE('
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
    final result = await (select(
      appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return (result?.value ?? '').toLowerCase() == 'true';
  }

  Future<void> _setBoolSetting(
    String key,
    bool value, {
    String? description,
  }) async {
    if (!await _appSettingsTableExists()) return;
    await into(appSettings).insert(
      AppSettingsCompanion(
        key: Value(key),
        value: Value(value ? 'true' : 'false'),
        description: description == null
            ? const Value.absent()
            : Value(description),
        updatedAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> _convertIntegerTimestampsToTextOnce() async {
    final alreadyConverted = await _getBoolSetting(
      _kSettingIntegerTimestampsConverted,
    );
    if (alreadyConverted) return;

    await _convertIntegerTimestampsToText();
    await _setBoolSetting(
      _kSettingIntegerTimestampsConverted,
      true,
      description:
          'One-time migration: convert legacy integer DateTime columns to text',
    );
  }

  /// ONE-TIME migration: create missing opening_balance journal entries for
  /// suppliers that have a non-zero balance_cents but no corresponding journal
  /// entry. Fixes the GL ↔ Suppliers mismatch caused by suppliers created
  /// before journal entries were enforced.
  ///
  /// IDEMPOTENT: only inserts entries for suppliers that are truly missing
  /// them (NOT EXISTS guard on the source_table/source_id pair).
  /// SAFE: does NOT delete or modify any existing journal entries.
  ///
  /// Phase 1.5 refactor (May 2026):
  /// Previously this method hand-rolled the entire JE (header + lines + raw
  /// `UPDATE accounts SET balance_cents`), bypassing the single-writer
  /// invariant for `accounts.balance_cents` documented in
  /// docs/adr/0001-pricing-engines-as-sot.md §B. It now delegates to
  /// JournalEntryService.recordSupplierOpeningBalanceJournalEntry, which
  /// routes through AccountingRepository.createJournalEntry — the sole
  /// sanctioned writer of `accounts.balance_cents`.
  ///
  /// Why constructing the service inline is safe here:
  ///   * AccountingRepository + JournalEntryService are pure objects with no
  ///     async init and depend only on AppDatabase.
  ///   * At the point this runs (onUpgrade, from < 10032), all schema-level
  ///     migrations have completed, so the chart-of-accounts is fully seeded.
  ///   * Drift coalesces nested transactions, so the inner
  ///     `_db.transaction()` inside `createJournalEntry` joins the outer
  ///     onUpgrade transaction cleanly.
  Future<void> _repairSupplierOpeningBalanceJournals() async {
    // Find suppliers with non-zero balance AND no opening_balance JE.
    final suppliersToFix = await customSelect(
      'SELECT s.id, s.balance_cents, s.currency_id FROM suppliers s '
      'WHERE s.balance_cents != 0 '
      'AND NOT EXISTS ('
      '  SELECT 1 FROM journal_entries je '
      "  WHERE je.source_table = 'suppliers' "
      '  AND je.source_id = s.id '
      "  AND je.entry_type = 'opening_balance'"
      ')',
    ).get();

    if (suppliersToFix.isEmpty) {
      debugPrint('Migration 10032: no suppliers need opening balance repair');
      return;
    }

    debugPrint(
      'Migration 10032: repairing ${suppliersToFix.length} supplier '
      'opening balance journal entries via JournalEntryService (SoT)',
    );

    final accountingRepo = AccountingRepository(this);
    final journalService = JournalEntryService(accountingRepo);

    for (final s in suppliersToFix) {
      final supplierId = s.read<int>('id');
      final balanceCents = s.read<int>('balance_cents');
      final currencyId = s.read<int>('currency_id');

      // JournalEntryService resolves AP (2000) + OBE (3100), chooses the
      // correct Dr/Cr sides from the sign, creates the JE through
      // AccountingRepository.createJournalEntry (which validates
      // double-entry and updates `accounts.balance_cents` via the single
      // sanctioned writer), and is itself idempotent on the
      // (source_table='suppliers', source_id=supplierId) key.
      await journalService.recordSupplierOpeningBalanceJournalEntry(
        supplierId: supplierId,
        amountCents: balanceCents,
        currencyId: currencyId,
      );

      debugPrint(
        'Migration 10032: created opening balance JE for Supplier #$supplierId '
        '(${balanceCents > 0 ? 'Dr OBE / Cr AP' : 'Dr AP / Cr OBE'} = '
        '${balanceCents.abs()} cents)',
      );
    }

    debugPrint(
      'Migration 10032: completed — ${suppliersToFix.length} entries created',
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
    await _safeAddColumn(
      'products',
      'supplier_id',
      'INTEGER REFERENCES suppliers(id)',
    );
    await _safeAddColumn('products', 'wholesale_price_cents', 'INTEGER');
    await _safeAddColumn('products', 'min_quantity', 'INTEGER DEFAULT 0');

    // Ensure boolean-ish and tax fields exist for older DBs.
    // Drift stores booleans as INTEGER 0/1.
    await _safeAddColumn(
      'products',
      'has_variants',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'products',
      'is_taxable',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'products',
      'purchase_tax_rate_bps',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'products',
      'sales_tax_rate_bps',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'products',
      'track_inventory',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _safeAddColumn(
      'products',
      'stock_quantity',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn('products', 'image_path', 'TEXT');
    await _safeAddColumn('products', 'is_active', 'INTEGER NOT NULL DEFAULT 1');

    await _safeAddColumn('product_variants', 'barcode', 'TEXT');
    await _safeAddColumn(
      'product_variants',
      'price_adjustment_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'product_variants',
      'cost_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'product_variants',
      'price_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'product_variants',
      'wholesale_price_cents',
      'INTEGER',
    );
    // v10055 — supplier reference price (gross of trade discounts).
    await _safeAddColumn('products', 'last_purchase_price_cents', 'INTEGER');
    await _safeAddColumn(
      'product_variants',
      'last_purchase_price_cents',
      'INTEGER',
    );

    await _safeAddColumn('sizes', 'sort_order', 'INTEGER NOT NULL DEFAULT 0');

    // Employee payroll configuration columns
    await _safeAddColumn(
      'employees',
      'pay_period_type',
      "TEXT NOT NULL DEFAULT 'monthly'",
    );
    await _safeAddColumn(
      'employees',
      'working_days_per_period',
      'INTEGER NOT NULL DEFAULT 26',
    );
    await _safeAddColumn(
      'employees',
      'working_hours_per_day',
      'INTEGER NOT NULL DEFAULT 8',
    );
    await _safeAddColumn(
      'employees',
      'absence_deduction_rate_bps',
      'INTEGER NOT NULL DEFAULT 10000',
    );
    await _safeAddColumn(
      'employees',
      'late_deduction_rate_bps',
      'INTEGER NOT NULL DEFAULT 2500',
    );
    await _safeAddColumn(
      'employees',
      'weekly_off_days',
      "TEXT NOT NULL DEFAULT '[5,6]'",
    );
    await _safeAddColumn(
      'employees',
      'annual_leave_days',
      'INTEGER NOT NULL DEFAULT 21',
    );

    // Commission economic-event date (v10058) — posting/transaction date used
    // by all commission reports. Backfilled by the 10058 migration; this guard
    // only protects DBs opened via the integrity path (fresh installs already
    // have it from the table definition).
    await _safeAddColumn('commissions', 'effective_date', 'TEXT');

    // Commission reversal link for unlinked (adjustment) sale returns
    // (v10059). Defensive guard for DBs opened via the integrity path.
    await _safeAddColumn('commissions', 'sale_return_adjustment_id', 'INTEGER');

    // Customer transactions: number + discount type
    await _safeAddColumn('customer_transactions', 'transaction_number', 'TEXT');
    await _safeAddColumn('customer_transactions', 'discount_type', 'TEXT');

    // Customers advanced fields (segmentation + loyalty + analytics)
    await _safeAddColumn(
      'customers',
      'segment',
      "TEXT NOT NULL DEFAULT 'retail'",
    );
    await _safeAddColumn(
      'customers',
      'loyalty_enabled',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _safeAddColumn(
      'customers',
      'loyalty_tier_id',
      'INTEGER REFERENCES loyalty_tiers(id)',
    );
    await _safeAddColumn(
      'customers',
      'loyalty_points_balance',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'customers',
      'total_spent_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'customers',
      'total_transactions',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn('customers', 'last_transaction_at', 'TEXT');

    // Loyalty tiers hybrid benefits columns (for older DBs)
    await _safeAddColumn(
      'loyalty_tiers',
      'free_shipping',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'loyalty_tiers',
      'free_shipping_min_order_cents',
      'INTEGER',
    );
    await _safeAddColumn(
      'loyalty_tiers',
      'priority_support',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'loyalty_tiers',
      'early_access_days',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'loyalty_tiers',
      'exclusive_offers',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'loyalty_tiers',
      'birthday_bonus',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'loyalty_tiers',
      'birthday_bonus_points',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'loyalty_tiers',
      'birthday_discount_percent',
      'REAL NOT NULL DEFAULT 0.0',
    );
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

    // Purchase item price update columns (v10023)
    await _safeAddColumn('purchase_items', 'new_sell_price_cents', 'INTEGER');
    await _safeAddColumn(
      'purchase_items',
      'new_wholesale_price_cents',
      'INTEGER',
    );

    // Purchase item original price snapshot columns (v10024)
    await _safeAddColumn('purchase_items', 'original_cost_cents', 'INTEGER');
    await _safeAddColumn('purchase_items', 'original_price_cents', 'INTEGER');
    await _safeAddColumn(
      'purchase_items',
      'original_wholesale_price_cents',
      'INTEGER',
    );

    // Previous price tracking on variants and products (v10025)
    await _safeAddColumn('product_variants', 'previous_cost_cents', 'INTEGER');
    await _safeAddColumn('product_variants', 'previous_price_cents', 'INTEGER');
    await _safeAddColumn(
      'product_variants',
      'previous_wholesale_price_cents',
      'INTEGER',
    );
    await _safeAddColumn('products', 'previous_cost_cents', 'INTEGER');
    await _safeAddColumn('products', 'previous_price_cents', 'INTEGER');
    await _safeAddColumn(
      'products',
      'previous_wholesale_price_cents',
      'INTEGER',
    );

    // Purchase enhancements (v10015)
    await _safeAddColumn(
      'purchases',
      'discount_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'purchases',
      'paid_amount_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn('purchases', 'payment_method', 'TEXT');
    await _safeAddColumn('purchases', 'supplier_invoice_ref', 'TEXT');
    await _safeAddColumn('purchases', 'notes', 'TEXT');
    await _safeAddColumn('purchases', 'due_date', 'TEXT');
    await _safeAddColumn(
      'purchase_returns',
      'status',
      "TEXT NOT NULL DEFAULT 'draft'",
    );
    await _safeAddColumn(
      'purchase_returns',
      'disposition_type',
      "TEXT NOT NULL DEFAULT 'restock'",
    );
    // Purchase returns accounting totals (v10018)
    await _safeAddColumn(
      'purchase_returns',
      'subtotal_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      'purchase_returns',
      'tax_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
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
    await _safeAddColumn(
      'sales',
      'paid_amount_cents',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn('sales', 'notes', 'TEXT');
    await _safeAddColumn('sales', 'due_date', 'TEXT');
    await _safeAddColumn(
      'sale_returns',
      'status',
      "TEXT NOT NULL DEFAULT 'draft'",
    );
    await _safeAddColumn(
      'sale_returns',
      'disposition_type',
      "TEXT NOT NULL DEFAULT 'restock'",
    );
    await _safeAddColumn(
      'sale_returns',
      'refund_method',
      "TEXT NOT NULL DEFAULT 'cash'",
    );
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

    // Adjustment return unified flow columns (v10038)
    await _safeAddColumn(
      'purchase_return_adjustments',
      'refund_method',
      "TEXT NOT NULL DEFAULT 'credit'",
    );
    await _safeAddColumn('purchase_return_adjustments', 'return_mode', 'TEXT');
    await _safeAddColumn('purchase_return_adjustments', 'mode_reason', 'TEXT');
    await _safeAddColumn('purchase_return_adjustments', 'batch_id', 'TEXT');
    await _safeAddColumn(
      'sale_return_adjustments',
      'refund_method',
      "TEXT NOT NULL DEFAULT 'cash'",
    );
    await _safeAddColumn('sale_return_adjustments', 'return_mode', 'TEXT');
    await _safeAddColumn('sale_return_adjustments', 'mode_reason', 'TEXT');
    await _safeAddColumn('sale_return_adjustments', 'batch_id', 'TEXT');

    // COGS snapshot column (v10039)
    await _safeAddColumn('sale_items', 'cost_cents', 'INTEGER');

    // FIFO costing method per product (v10045). Defaults to 'wac' to preserve
    // existing accounting behaviour for older databases.
    await _safeAddColumn(
      'products',
      'costing_method',
      "TEXT NOT NULL DEFAULT 'wac'",
    );

    debugPrint('Schema integrity check completed.');
  }

  /// One-time seeder run as part of migration 10044 → 10045.
  ///
  /// For every active variant with `stock_quantity > 0`, insert exactly ONE
  /// opening batch carrying the full on-hand quantity at the *current*
  /// `cost_cents`. Batches are ALWAYS stored at variant level — this keeps
  /// the FIFO invariant simple (Σ remaining per variant == variant.stock).
  ///
  /// Non-variant products have a single default variant (color_id IS NULL
  /// AND size_id IS NULL) created automatically; that variant carries the
  /// stock and therefore receives the opening batch.
  ///
  /// Safe & idempotent: skips a variant that already has an active batch.
  Future<void> _seedOpeningBatchesForFifoActivation() async {
    final now = DateTime.now().toIso8601String();
    int seq = 0;
    final dateTag = now.substring(0, 10).replaceAll('-', '');

    final variantRows = await customSelect(
      'SELECT v.id AS variant_id, v.product_id AS product_id, '
      '       v.stock_quantity AS qty, v.cost_cents AS cost_cents, '
      '       p.supplier_id AS supplier_id '
      '  FROM product_variants v '
      '  JOIN products p ON p.id = v.product_id '
      ' WHERE v.is_active = 1 AND v.stock_quantity > 0 '
      '   AND NOT EXISTS ('
      '     SELECT 1 FROM product_batches b '
      '      WHERE b.variant_id = v.id AND b.is_active = 1'
      '   )',
    ).get();

    for (final r in variantRows) {
      final productId = r.read<int>('product_id');
      final variantId = r.read<int>('variant_id');
      final qty = r.read<int>('qty');
      final cost = r.read<int>('cost_cents');
      final supplierIdNullable = r.readNullable<int>('supplier_id');
      seq++;
      final batchNumber = 'OPEN-$dateTag-V$variantId';
      await customStatement(
        'INSERT INTO product_batches '
        '(product_id, variant_id, batch_number, purchase_item_id, supplier_id, '
        ' source, received_date, expiry_date, received_quantity, '
        ' remaining_quantity, unit_cost_cents, is_active, created_at, updated_at) '
        'VALUES (?, ?, ?, NULL, ?, ?, ?, NULL, ?, ?, ?, 1, ?, ?)',
        [
          productId,
          variantId,
          batchNumber,
          if (supplierIdNullable != null) supplierIdNullable else null,
          'opening',
          now,
          qty,
          qty,
          cost,
          now,
          now,
        ],
      );
    }

    debugPrint(
      'Migration 10045: created $seq opening batches for FIFO activation',
    );
  }

  /// Repairs the v10063 linked-return measurement snapshot defect.
  ///
  /// The return repositories recompute money from the source invoice before
  /// inserting the return. In v10063-v10064 that reconstruction dropped the
  /// frozen quantity scale/type, so 1000 millimetres could be valued as 1000
  /// metres in the Inventory/COGS journal even though stock moved correctly.
  Future<void> _repairMeasuredLinkedReturnScalesAndJournals() async {
    final affectedSaleRows = await customSelect(
      'SELECT DISTINCT sri.return_id AS return_id '
      'FROM sale_return_items sri '
      'JOIN sale_items si ON si.id = sri.sale_item_id '
      'WHERE sri.quantity_scale != si.quantity_scale '
      '   OR sri.measurement_type != si.measurement_type',
    ).get();
    final affectedPurchaseRows = await customSelect(
      'SELECT DISTINCT pri.return_id AS return_id '
      'FROM purchase_return_items pri '
      'JOIN purchase_items pi ON pi.id = pri.purchase_item_id '
      'WHERE pri.quantity_scale != pi.quantity_scale '
      '   OR pri.measurement_type != pi.measurement_type',
    ).get();

    if (affectedSaleRows.isEmpty && affectedPurchaseRows.isEmpty) return;

    // The parent invoice line is the immutable source of truth for a linked
    // return's quantity representation.
    await customStatement(
      'UPDATE sale_return_items '
      'SET quantity_scale = ('
      '      SELECT si.quantity_scale FROM sale_items si '
      '      WHERE si.id = sale_return_items.sale_item_id'
      '    ), '
      '    measurement_type = ('
      '      SELECT si.measurement_type FROM sale_items si '
      '      WHERE si.id = sale_return_items.sale_item_id'
      '    ) '
      'WHERE EXISTS ('
      '  SELECT 1 FROM sale_items si '
      '  WHERE si.id = sale_return_items.sale_item_id '
      '    AND (si.quantity_scale != sale_return_items.quantity_scale '
      '      OR si.measurement_type != sale_return_items.measurement_type)'
      ')',
    );
    await customStatement(
      'UPDATE purchase_return_items '
      'SET quantity_scale = ('
      '      SELECT pi.quantity_scale FROM purchase_items pi '
      '      WHERE pi.id = purchase_return_items.purchase_item_id'
      '    ), '
      '    measurement_type = ('
      '      SELECT pi.measurement_type FROM purchase_items pi '
      '      WHERE pi.id = purchase_return_items.purchase_item_id'
      '    ) '
      'WHERE EXISTS ('
      '  SELECT 1 FROM purchase_items pi '
      '  WHERE pi.id = purchase_return_items.purchase_item_id '
      '    AND (pi.quantity_scale != purchase_return_items.quantity_scale '
      '      OR pi.measurement_type != purchase_return_items.measurement_type)'
      ')',
    );

    for (final row in affectedSaleRows) {
      final returnId = row.read<int>('return_id');
      final correctCost = await saleDao.computeSaleReturnCostCents(returnId);
      final journalRows = await customSelect(
        'SELECT DISTINCT je.id AS journal_id '
        'FROM journal_entries je '
        'JOIN journal_entry_lines inv ON inv.journal_entry_id = je.id '
        'JOIN accounts inv_a ON inv_a.id = inv.account_id '
        'JOIN journal_entry_lines cogs ON cogs.journal_entry_id = je.id '
        'JOIN accounts cogs_a ON cogs_a.id = cogs.account_id '
        "WHERE je.source_table = 'sale_returns' AND je.source_id = ? "
        "  AND je.status = 'posted' "
        "  AND inv_a.account_code = '1200' AND inv.debit_cents > 0 "
        "  AND cogs_a.account_code = '5300' AND cogs.credit_cents > 0",
        variables: [Variable.withInt(returnId)],
      ).get();
      for (final journalRow in journalRows) {
        final journalId = journalRow.read<int>('journal_id');
        await customStatement(
          'UPDATE journal_entry_lines '
          'SET debit_cents = ?, credit_cents = 0 '
          'WHERE journal_entry_id = ? AND account_id = ('
          "  SELECT id FROM accounts WHERE account_code = '1200'"
          ') AND debit_cents > 0',
          [correctCost, journalId],
        );
        await customStatement(
          'UPDATE journal_entry_lines '
          'SET debit_cents = 0, credit_cents = ? '
          'WHERE journal_entry_id = ? AND account_id = ('
          "  SELECT id FROM accounts WHERE account_code = '5300'"
          ') AND credit_cents > 0',
          [correctCost, journalId],
        );
        await _syncJournalHeaderTotals(journalId);
      }
    }

    for (final row in affectedPurchaseRows) {
      final returnId = row.read<int>('return_id');
      final correctCost = await purchaseDao
          .computePurchaseReturnInventoryCostCents(returnId);
      final returnRow = await customSelect(
        'SELECT disposition_type FROM purchase_returns WHERE id = ?',
        variables: [Variable.withInt(returnId)],
      ).getSingleOrNull();
      final disposition =
          returnRow?.readNullable<String>('disposition_type') ?? 'restock';
      final offsetCode = disposition == 'send_back' ? '1290' : '4100';
      final journalRows = await customSelect(
        'SELECT DISTINCT je.id AS journal_id '
        'FROM journal_entries je '
        'JOIN journal_entry_lines inv ON inv.journal_entry_id = je.id '
        'JOIN accounts inv_a ON inv_a.id = inv.account_id '
        "WHERE je.source_table = 'purchase_returns' AND je.source_id = ? "
        "  AND je.status = 'posted' "
        "  AND inv_a.account_code = '1200' AND inv.credit_cents > 0",
        variables: [Variable.withInt(returnId)],
      ).get();
      for (final journalRow in journalRows) {
        final journalId = journalRow.read<int>('journal_id');
        await customStatement(
          'UPDATE journal_entry_lines '
          'SET debit_cents = 0, credit_cents = ? '
          'WHERE journal_entry_id = ? AND account_id = ('
          "  SELECT id FROM accounts WHERE account_code = '1200'"
          ') AND credit_cents > 0',
          [correctCost, journalId],
        );
        await customStatement(
          'UPDATE journal_entry_lines '
          'SET debit_cents = ?, credit_cents = 0 '
          'WHERE journal_entry_id = ? AND account_id = ('
          '  SELECT id FROM accounts WHERE account_code = ?'
          ') AND debit_cents > 0',
          [correctCost, journalId, offsetCode],
        );
        await _syncJournalHeaderTotals(journalId);
      }
    }

    // accounts.balance_cents is a cache. Rebuild it through the accounting
    // boundary after repairing the journal lines; raw balance writes from a
    // migration would violate the single-writer invariant.
    await AccountingRepository(
      this,
    ).rebuildCachedAccountBalancesFromPostedLedger();

    developer.log(
      'Migration 10065 repaired ${affectedSaleRows.length} sale return(s) '
      'and ${affectedPurchaseRows.length} purchase return(s) with lost '
      'measurement snapshots.',
      name: 'DB_MIGRATION',
    );
  }

  Future<void> _syncJournalHeaderTotals(int journalId) async {
    await customStatement(
      'UPDATE journal_entries SET '
      'total_debit_cents = COALESCE(('
      '  SELECT SUM(debit_cents) FROM journal_entry_lines '
      '  WHERE journal_entry_id = journal_entries.id'
      '), 0), '
      'total_credit_cents = COALESCE(('
      '  SELECT SUM(credit_cents) FROM journal_entry_lines '
      '  WHERE journal_entry_id = journal_entries.id'
      '), 0), '
      'updated_at = ? '
      'WHERE id = ?',
      [DateTime.now().toIso8601String(), journalId],
    );
  }

  /// Adds exact per-line carrying values for measured inventory and repairs
  /// the small rounded-pool drift that could be produced by the last posted
  /// unlinked purchase return on pre-10066 builds.
  Future<void> _repairMeasuredInventoryRounding10066() async {
    await customStatement(
      'UPDATE sale_items SET inventory_value_at_post_cents = '
      'CAST(ROUND(1.0 * quantity * COALESCE(cost_cents, 0) / '
      'CASE WHEN quantity_scale > 0 THEN quantity_scale ELSE 1 END) AS INTEGER) '
      'WHERE inventory_value_at_post_cents IS NULL',
    );
    await customStatement(
      'UPDATE purchase_items SET inventory_value_at_post_cents = '
      'CASE WHEN EXISTS (SELECT 1 FROM products p '
      '                  WHERE p.id = purchase_items.product_id '
      '                    AND p.track_inventory = 1) '
      'THEN MAX(total_cents - tax_cents, 0) ELSE 0 END '
      'WHERE inventory_value_at_post_cents IS NULL',
    );
    await customStatement(
      'UPDATE sale_return_items SET inventory_value_at_post_cents = '
      'CAST(ROUND(1.0 * quantity * COALESCE(unit_cost_at_post_cents, '
      '  (SELECT si.cost_cents FROM sale_items si '
      '   WHERE si.id = sale_return_items.sale_item_id), 0) / '
      'CASE WHEN quantity_scale > 0 THEN quantity_scale ELSE 1 END) AS INTEGER) '
      'WHERE inventory_value_at_post_cents IS NULL',
    );
    await customStatement(
      'UPDATE purchase_return_items SET inventory_value_at_post_cents = '
      'CAST(ROUND(1.0 * quantity * COALESCE(unit_cost_at_post_cents, '
      '  (SELECT pi.unit_cost_cents FROM purchase_items pi '
      '   WHERE pi.id = purchase_return_items.purchase_item_id), 0) / '
      'CASE WHEN quantity_scale > 0 THEN quantity_scale ELSE 1 END) AS INTEGER) '
      'WHERE inventory_value_at_post_cents IS NULL',
    );
    for (final table in <String>[
      'purchase_return_adjustment_items',
      'sale_return_adjustment_items',
    ]) {
      await customStatement(
        'UPDATE $table SET inventory_value_at_post_cents = '
        'CAST(ROUND(1.0 * quantity * '
        'COALESCE(unit_cost_at_post_cents, unit_cost_cents, 0) / '
        'CASE WHEN quantity_scale > 0 THEN quantity_scale ELSE 1 END) AS INTEGER) '
        'WHERE inventory_value_at_post_cents IS NULL',
      );
    }

    final glRow = await customSelect(
      'SELECT COALESCE(SUM(jel.debit_cents - jel.credit_cents), 0) AS value '
      'FROM journal_entry_lines jel '
      'JOIN journal_entries je ON je.id = jel.journal_entry_id '
      'JOIN accounts a ON a.id = jel.account_id '
      "WHERE je.status = 'posted' AND a.account_code = '1200'",
    ).getSingle();
    final stockRow = await customSelect('''
      SELECT
        COALESCE((
          SELECT SUM(CAST(ROUND(
            1.0 * b.remaining_quantity * b.unit_cost_cents /
            CASE WHEN p.measurement_type = 'piece' THEN 1 ELSE 1000 END
          ) AS INTEGER))
          FROM product_batches b
          JOIN products p ON p.id = b.product_id
          WHERE b.is_active = 1 AND p.track_inventory = 1
            AND (p.inventory_tracking_type IN ('batch', 'batch_expiry')
                 OR p.costing_method = 'fifo')
        ), 0)
        + COALESCE((
          SELECT SUM(CAST(ROUND(
            1.0 * v.stock_quantity * v.cost_cents /
            CASE WHEN p.measurement_type = 'piece' THEN 1 ELSE 1000 END
          ) AS INTEGER))
          FROM product_variants v
          JOIN products p ON p.id = v.product_id
          WHERE p.track_inventory = 1
            AND (NOT (p.inventory_tracking_type IN ('batch', 'batch_expiry')
                      OR p.costing_method = 'fifo')
                 OR NOT EXISTS (
                   SELECT 1 FROM product_batches b
                   WHERE b.variant_id = v.id AND b.is_active = 1
                 ))
        ), 0)
        + COALESCE((
          SELECT SUM(CAST(ROUND(
            1.0 * p.stock_quantity * p.cost_cents /
            CASE WHEN p.measurement_type = 'piece' THEN 1 ELSE 1000 END
          ) AS INTEGER))
          FROM products p
          WHERE p.track_inventory = 1
            AND NOT EXISTS (
              SELECT 1 FROM product_variants v WHERE v.product_id = p.id
            )
            AND (NOT (p.inventory_tracking_type IN ('batch', 'batch_expiry')
                      OR p.costing_method = 'fifo')
                 OR NOT EXISTS (
                   SELECT 1 FROM product_batches b
                   WHERE b.product_id = p.id AND b.is_active = 1
                 ))
        ), 0) AS value
    ''').getSingle();
    final difference = glRow.read<int>('value') - stockRow.read<int>('value');

    // A measured line can move a rounded pool by one cent more or less than
    // its independently rounded line value. Restrict the historical repair
    // to a small rounding-only difference and the latest posted measured
    // purchase adjustment; larger differences remain visible for diagnosis.
    if (difference != 0 && difference.abs() <= 100) {
      final candidate = await customSelect(
        'SELECT je.id AS journal_id, je.source_id AS return_id '
        'FROM journal_entries je '
        "WHERE je.source_table = 'purchase_return_adjustments' "
        "  AND je.status = 'posted' AND je.is_reversed = 0 "
        '  AND EXISTS (SELECT 1 FROM purchase_return_adjustment_items i '
        '              WHERE i.return_id = je.source_id '
        '                AND i.quantity_scale > 1) '
        'ORDER BY COALESCE(je.posted_at, je.created_at) DESC, je.id DESC '
        'LIMIT 1',
      ).getSingleOrNull();
      if (candidate != null) {
        final journalId = candidate.read<int>('journal_id');
        final returnId = candidate.read<int>('return_id');
        final inventoryLine = await customSelect(
          'SELECT jel.id, jel.credit_cents FROM journal_entry_lines jel '
          'JOIN accounts a ON a.id = jel.account_id '
          "WHERE jel.journal_entry_id = ? AND a.account_code = '1200' "
          '  AND jel.credit_cents > 0 LIMIT 1',
          variables: [Variable.withInt(journalId)],
        ).getSingleOrNull();
        final offsetLine = await customSelect(
          'SELECT jel.id, jel.debit_cents FROM journal_entry_lines jel '
          'JOIN accounts a ON a.id = jel.account_id '
          "WHERE jel.journal_entry_id = ? AND a.account_code = '4100' "
          '  AND jel.debit_cents > 0 LIMIT 1',
          variables: [Variable.withInt(journalId)],
        ).getSingleOrNull();
        if (inventoryLine != null && offsetLine != null) {
          final newCredit =
              inventoryLine.read<int>('credit_cents') + difference;
          final newDebit = offsetLine.read<int>('debit_cents') + difference;
          if (newCredit >= 0 && newDebit >= 0) {
            await customStatement(
              'UPDATE journal_entry_lines SET credit_cents = ? WHERE id = ?',
              [newCredit, inventoryLine.read<int>('id')],
            );
            await customStatement(
              'UPDATE journal_entry_lines SET debit_cents = ? WHERE id = ?',
              [newDebit, offsetLine.read<int>('id')],
            );
            await customStatement(
              'UPDATE purchase_return_adjustment_items '
              'SET inventory_value_at_post_cents = '
              'COALESCE(inventory_value_at_post_cents, 0) + ? '
              'WHERE id = (SELECT id FROM purchase_return_adjustment_items '
              '            WHERE return_id = ? AND quantity_scale > 1 '
              '            ORDER BY id DESC LIMIT 1)',
              [difference, returnId],
            );
            await _syncJournalHeaderTotals(journalId);
            await AccountingRepository(
              this,
            ).rebuildCachedAccountBalancesFromPostedLedger();
          }
        }
      }
    }

    developer.log(
      'Migration 10066 stored exact measured inventory movement values; '
      'pre-repair GL/stock difference=$difference cents.',
      name: 'DB_MIGRATION',
    );
  }

  /// Normalizes the price/cost audit table to its declared integer-cents
  /// contract. Pre-10067 writers divided cents by 100 before passing values
  /// through [MoneyConverter], whose integer SQL representation then
  /// truncated fractions (e.g. 1188 cents became 11). We can restore the
  /// surviving major-unit portion deterministically by multiplying it once.
  ///
  /// Purchase-origin rows are repaired further from their immutable purchase
  /// line snapshots, recovering the exact typed cost and pre-change values
  /// whenever those snapshots exist.
  Future<void> _normalizePriceHistoryCents10067() async {
    await transaction(() async {
      await customStatement(
        'UPDATE product_price_histories SET '
        'old_cost_cents = old_cost_cents * 100, '
        'new_cost_cents = new_cost_cents * 100, '
        'old_price_cents = old_price_cents * 100, '
        'new_price_cents = new_price_cents * 100, '
        'old_wholesale_price_cents = CASE '
        '  WHEN old_wholesale_price_cents IS NULL THEN NULL '
        '  ELSE old_wholesale_price_cents * 100 END, '
        'new_wholesale_price_cents = CASE '
        '  WHEN new_wholesale_price_cents IS NULL THEN NULL '
        '  ELSE new_wholesale_price_cents * 100 END',
      );

      // A purchase history reason carries the purchase id. Use its frozen
      // line snapshots to recover values that the old truncating convention
      // could not preserve.
      await customStatement('''
        UPDATE product_price_histories AS h
        SET
          old_cost_cents = COALESCE((
            SELECT pi.original_cost_cents
            FROM purchase_items pi
            WHERE pi.purchase_id =
                    CAST(substr(h.change_reason, length('purchase_post:#') + 1) AS INTEGER)
              AND pi.product_id = h.product_id
              AND ((pi.variant_id = h.variant_id)
                   OR (pi.variant_id IS NULL AND h.variant_id IS NULL))
            ORDER BY pi.id DESC LIMIT 1
          ), h.old_cost_cents),
          new_cost_cents = COALESCE((
            SELECT pi.unit_cost_cents
            FROM purchase_items pi
            WHERE pi.purchase_id =
                    CAST(substr(h.change_reason, length('purchase_post:#') + 1) AS INTEGER)
              AND pi.product_id = h.product_id
              AND ((pi.variant_id = h.variant_id)
                   OR (pi.variant_id IS NULL AND h.variant_id IS NULL))
            ORDER BY pi.id DESC LIMIT 1
          ), h.new_cost_cents),
          old_price_cents = COALESCE((
            SELECT pi.original_price_cents
            FROM purchase_items pi
            WHERE pi.purchase_id =
                    CAST(substr(h.change_reason, length('purchase_post:#') + 1) AS INTEGER)
              AND pi.product_id = h.product_id
              AND ((pi.variant_id = h.variant_id)
                   OR (pi.variant_id IS NULL AND h.variant_id IS NULL))
            ORDER BY pi.id DESC LIMIT 1
          ), h.old_price_cents),
          new_price_cents = COALESCE((
            SELECT COALESCE(pi.new_sell_price_cents, pi.original_price_cents)
            FROM purchase_items pi
            WHERE pi.purchase_id =
                    CAST(substr(h.change_reason, length('purchase_post:#') + 1) AS INTEGER)
              AND pi.product_id = h.product_id
              AND ((pi.variant_id = h.variant_id)
                   OR (pi.variant_id IS NULL AND h.variant_id IS NULL))
            ORDER BY pi.id DESC LIMIT 1
          ), h.new_price_cents),
          old_wholesale_price_cents = COALESCE((
            SELECT pi.original_wholesale_price_cents
            FROM purchase_items pi
            WHERE pi.purchase_id =
                    CAST(substr(h.change_reason, length('purchase_post:#') + 1) AS INTEGER)
              AND pi.product_id = h.product_id
              AND ((pi.variant_id = h.variant_id)
                   OR (pi.variant_id IS NULL AND h.variant_id IS NULL))
            ORDER BY pi.id DESC LIMIT 1
          ), h.old_wholesale_price_cents),
          new_wholesale_price_cents = COALESCE((
            SELECT COALESCE(
              pi.new_wholesale_price_cents,
              pi.original_wholesale_price_cents
            )
            FROM purchase_items pi
            WHERE pi.purchase_id =
                    CAST(substr(h.change_reason, length('purchase_post:#') + 1) AS INTEGER)
              AND pi.product_id = h.product_id
              AND ((pi.variant_id = h.variant_id)
                   OR (pi.variant_id IS NULL AND h.variant_id IS NULL))
            ORDER BY pi.id DESC LIMIT 1
          ), h.new_wholesale_price_cents)
        WHERE h.change_reason LIKE 'purchase_post:#%'
      ''');
    });

    developer.log(
      'Migration 10067 normalized product price history to integer cents '
      'and recovered purchase snapshots where available.',
      name: 'DB_MIGRATION',
    );
  }

  /// Repairs a short-lived v10067 regression that split some simple products
  /// into two active rows:
  ///
  /// * the original row retained SKU/barcode and optional colour/size;
  /// * a new anonymous row received stock, batches and invoice references.
  ///
  /// A simple product has exactly one operational variant row. Optional
  /// colour/size are descriptive attributes on that row and do not turn the
  /// product into a multi-variant product. We deliberately repair only the
  /// unambiguous shape (one zero-stock, unreferenced metadata row + one
  /// anonymous operational row). The operational id is retained so purchase,
  /// batch and price-history lineage never changes.
  Future<void> _reconcileSimpleProductRows10068() async {
    var repaired = 0;
    await transaction(() async {
      final rows = await customSelect('''
        SELECT
          p.id AS product_id,
          p.sku AS product_sku,
          p.barcode AS product_barcode,
          operational.id AS operational_id,
          metadata.id AS metadata_id,
          metadata.sku AS metadata_sku,
          metadata.barcode AS metadata_barcode,
          metadata.color_id AS metadata_color_id,
          metadata.size_id AS metadata_size_id
        FROM products p
        JOIN product_variants operational
          ON operational.product_id = p.id
         AND operational.is_active = 1
         AND operational.color_id IS NULL
         AND operational.size_id IS NULL
        JOIN product_variants metadata
          ON metadata.product_id = p.id
         AND metadata.is_active = 1
         AND (metadata.color_id IS NOT NULL OR metadata.size_id IS NOT NULL)
        WHERE p.has_variants = 0
          AND metadata.stock_quantity = 0
          AND (SELECT COUNT(*) FROM product_variants all_active
               WHERE all_active.product_id = p.id
                 AND all_active.is_active = 1) = 2
          AND (
            (SELECT COUNT(*) FROM sale_items WHERE variant_id = metadata.id)
            + (SELECT COUNT(*) FROM purchase_items WHERE variant_id = metadata.id)
            + (SELECT COUNT(*) FROM purchase_return_adjustment_items
               WHERE variant_id = metadata.id)
            + (SELECT COUNT(*) FROM sale_return_adjustment_items
               WHERE variant_id = metadata.id)
            + (SELECT COUNT(*) FROM inventory_adjustments
               WHERE variant_id = metadata.id)
            + (SELECT COUNT(*) FROM product_batches
               WHERE variant_id = metadata.id)
            + (SELECT COUNT(*) FROM product_price_histories
               WHERE variant_id = metadata.id)
          ) = 0
      ''').get();

      for (final row in rows) {
        final operationalId = row.read<int>('operational_id');
        final metadataId = row.read<int>('metadata_id');
        final productSku = row.readNullable<String>('product_sku');
        final productBarcode = row.readNullable<String>('product_barcode');
        final metadataSku = row.readNullable<String>('metadata_sku');
        final metadataBarcode = row.readNullable<String>('metadata_barcode');
        final colorId = row.readNullable<int>('metadata_color_id');
        final sizeId = row.readNullable<int>('metadata_size_id');

        // Printing history is non-accounting, but remapping it avoids losing
        // the audit trail when the obsolete metadata-only row is removed.
        await customStatement(
          'UPDATE print_histories SET variant_id = ? WHERE variant_id = ?',
          [operationalId, metadataId],
        );
        await customStatement('DELETE FROM product_variants WHERE id = ?', [
          metadataId,
        ]);
        await customStatement(
          'UPDATE product_variants SET sku = ?, barcode = ?, color_id = ?, '
          'size_id = ?, updated_at = ? WHERE id = ?',
          [
            productSku ?? metadataSku,
            productBarcode ?? metadataBarcode,
            colorId,
            sizeId,
            DateTime.now().toIso8601String(),
            operationalId,
          ],
        );
        repaired++;
      }
    });

    developer.log(
      'Migration 10068 reconciled $repaired split simple-product rows.',
      name: 'DB_MIGRATION',
    );
  }

  @override
  int get schemaVersion => 10069;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await _ensureDocumentSequencesTable();
        await _createIndexes();
        await _installProductBatchesIntegrityTriggers();
        await _seedInitialData();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from == to) {
          return;
        }

        developer.log(
          'DB migration starting: $from → $to',
          name: 'DB_MIGRATION',
        );

        // Create a backup before applying any migration.
        // Import is conditional (native only) so this is safe.
        try {
          // ignore: unused_local_variable
          final backup = await _createPreMigrationBackup();
        } catch (e) {
          developer.log(
            'Pre-migration backup failed (continuing): $e',
            name: 'DB_MIGRATION',
          );
        }

        // Migration from 10000 to 10001: Add barcode, name_ar, name_fr columns to products and product_variants
        if (from < 10001) {
          await _safeAddColumn('products', 'barcode', 'TEXT');
          await _safeAddColumn('product_variants', 'barcode', 'TEXT');
          await _safeAddColumn('products', 'name_ar', 'TEXT');
          await _safeAddColumn('products', 'name_fr', 'TEXT');

          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_barcode ON product_variants(barcode) WHERE barcode IS NOT NULL',
          );
        }

        // Migration from 10001 to 10002: Add supplier_id and wholesale_price_cents columns to products
        if (from < 10002) {
          await _safeAddColumn(
            'products',
            'supplier_id',
            'INTEGER REFERENCES suppliers(id)',
          );
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
          await _safeAddColumn(
            'product_variants',
            'wholesale_price_cents',
            'INTEGER',
          );
        }

        // Migration 10008 -> 10009: Customers advanced fields + loyalty tables
        if (from < 10009) {
          await _safeAddColumn(
            'customers',
            'segment',
            "TEXT NOT NULL DEFAULT 'retail'",
          );
          await _safeAddColumn(
            'customers',
            'loyalty_tier_id',
            'INTEGER REFERENCES loyalty_tiers(id)',
          );
          await _safeAddColumn(
            'customers',
            'loyalty_points_balance',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'customers',
            'total_spent_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'customers',
            'total_transactions',
            'INTEGER NOT NULL DEFAULT 0',
          );
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
          await _safeAddColumn(
            'employees',
            'user_id',
            'INTEGER REFERENCES users(id) ON DELETE SET NULL',
          );
          await _safeAddColumn('employees', 'name_ar', 'TEXT');
          await _safeAddColumn('employees', 'name_fr', 'TEXT');
          await _safeAddColumn('employees', 'department', 'TEXT');
          await _safeAddColumn('employees', 'role_id', 'INTEGER');
          await _safeAddColumn('employees', 'manager_id', 'INTEGER');
          await _safeAddColumn(
            'employees',
            'default_commission_rate_bps',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn('employees', 'termination_date', 'TEXT');
          await _safeAddColumn('employees', 'notes', 'TEXT');

          // Add new columns to commissions table
          await _safeAddColumn('commissions', 'period', 'TEXT');
          await _safeAddColumn(
            'commissions',
            'status',
            "TEXT NOT NULL DEFAULT 'pending'",
          );

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
          await _safeAddColumn(
            'loyalty_tiers',
            'free_shipping',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'loyalty_tiers',
            'free_shipping_min_order_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'loyalty_tiers',
            'priority_support',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'loyalty_tiers',
            'early_access_days',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'loyalty_tiers',
            'exclusive_offers',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'loyalty_tiers',
            'birthday_bonus',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'loyalty_tiers',
            'birthday_bonus_points',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'loyalty_tiers',
            'birthday_discount_percent',
            'REAL NOT NULL DEFAULT 0.0',
          );
          await _safeAddColumn('loyalty_tiers', 'badge_text', 'TEXT');

          // Seed default loyalty tiers with hybrid benefits
          await _seedDefaultLoyaltyTiers();
        }

        // Migration 10011 -> 10012: Per-customer loyalty enable/disable
        if (from < 10012) {
          await _safeAddColumn(
            'customers',
            'loyalty_enabled',
            'INTEGER NOT NULL DEFAULT 1',
          );
        }

        // Migration 10012 -> 10013: Employee payroll configuration columns
        if (from < 10013) {
          await _safeAddColumn(
            'employees',
            'pay_period_type',
            "TEXT NOT NULL DEFAULT 'monthly'",
          );
          await _safeAddColumn(
            'employees',
            'working_days_per_period',
            'INTEGER NOT NULL DEFAULT 26',
          );
          await _safeAddColumn(
            'employees',
            'working_hours_per_day',
            'INTEGER NOT NULL DEFAULT 8',
          );
          await _safeAddColumn(
            'employees',
            'absence_deduction_rate_bps',
            'INTEGER NOT NULL DEFAULT 10000',
          );
          await _safeAddColumn(
            'employees',
            'late_deduction_rate_bps',
            'INTEGER NOT NULL DEFAULT 2500',
          );
        }

        // Migration 10013 -> 10014: Switch DateTime storage from integer to text (ISO 8601)
        if (from < 10014) {
          await _convertIntegerTimestampsToText();
        }

        // Migration 10014 -> 10015: Enhanced purchase invoices & returns
        if (from < 10015) {
          // Purchases: new columns
          await _safeAddColumn(
            'purchases',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchases',
            'paid_amount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn('purchases', 'payment_method', 'TEXT');
          await _safeAddColumn('purchases', 'supplier_invoice_ref', 'TEXT');
          await _safeAddColumn('purchases', 'notes', 'TEXT');
          await _safeAddColumn('purchases', 'due_date', 'TEXT');

          // PurchaseReturns: status + disposition
          await _safeAddColumn(
            'purchase_returns',
            'status',
            "TEXT NOT NULL DEFAULT 'draft'",
          );
          await _safeAddColumn(
            'purchase_returns',
            'disposition_type',
            "TEXT NOT NULL DEFAULT 'restock'",
          );

          // PurchaseReturnItems: per-item reason
          await _safeAddColumn('purchase_return_items', 'reason', 'TEXT');

          // PurchasePayments table
          await m.createTable(purchasePayments);
        }

        // Migration 10015 -> 10016: Enhanced sales & sale returns
        if (from < 10016) {
          // Sales: new columns
          await _safeAddColumn(
            'sales',
            'paid_amount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn('sales', 'notes', 'TEXT');
          await _safeAddColumn('sales', 'due_date', 'TEXT');

          // SaleReturns: status + disposition
          await _safeAddColumn(
            'sale_returns',
            'status',
            "TEXT NOT NULL DEFAULT 'draft'",
          );
          await _safeAddColumn(
            'sale_returns',
            'disposition_type',
            "TEXT NOT NULL DEFAULT 'restock'",
          );

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
          await _safeAddColumn(
            'purchase_returns',
            'subtotal_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchase_returns',
            'tax_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }

        // Migration 10018 -> 10019: Purchase item discount + expiry date
        if (from < 10019) {
          await _safeAddColumn(
            'purchase_items',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn('purchase_items', 'expiry_date', 'TEXT');
        }

        // Migration 10019 -> 10020: Purchase return refund method
        if (from < 10020) {
          await _safeAddColumn(
            'purchase_returns',
            'refund_method',
            "TEXT NOT NULL DEFAULT 'credit'",
          );
        }

        // Migration 10020 -> 10021: ERP accounting breakdown on return items & headers
        if (from < 10021) {
          // Purchase return items: proportional breakdown
          await _safeAddColumn(
            'purchase_return_items',
            'subtotal_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchase_return_items',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchase_return_items',
            'tax_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          // Purchase returns header: discount breakdown
          await _safeAddColumn(
            'purchase_returns',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          // Sale return items: proportional breakdown
          await _safeAddColumn(
            'sale_return_items',
            'subtotal_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_return_items',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_return_items',
            'tax_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          // Sale returns header: subtotal, discount, tax breakdown
          await _safeAddColumn(
            'sale_returns',
            'subtotal_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_returns',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_returns',
            'tax_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }

        // Migration 10021 -> 10022: Supplier transaction number + discount type
        if (from < 10022) {
          await _safeAddColumn(
            'supplier_transactions',
            'transaction_number',
            'TEXT',
          );
          await _safeAddColumn(
            'supplier_transactions',
            'discount_type',
            'TEXT',
          );
        }

        // Migration 10022 -> 10023: Purchase item price update columns
        if (from < 10023) {
          await _safeAddColumn(
            'purchase_items',
            'new_sell_price_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'purchase_items',
            'new_wholesale_price_cents',
            'INTEGER',
          );
        }

        // Migration 10023 -> 10024: Original price snapshot columns
        if (from < 10024) {
          await _safeAddColumn(
            'purchase_items',
            'original_cost_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'purchase_items',
            'original_price_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'purchase_items',
            'original_wholesale_price_cents',
            'INTEGER',
          );
        }

        // Migration 10024 -> 10025: Previous price tracking on variants and products
        if (from < 10025) {
          await _safeAddColumn(
            'product_variants',
            'previous_cost_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'product_variants',
            'previous_price_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'product_variants',
            'previous_wholesale_price_cents',
            'INTEGER',
          );
          await _safeAddColumn('products', 'previous_cost_cents', 'INTEGER');
          await _safeAddColumn('products', 'previous_price_cents', 'INTEGER');
          await _safeAddColumn(
            'products',
            'previous_wholesale_price_cents',
            'INTEGER',
          );
        }

        // Migration 10025 -> 10026: Split taxRateBps into purchaseTaxRateBps + salesTaxRateBps
        if (from < 10026) {
          await _safeAddColumn(
            'products',
            'purchase_tax_rate_bps',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'products',
            'sales_tax_rate_bps',
            'INTEGER NOT NULL DEFAULT 0',
          );
          // Migrate old tax_rate_bps data to both new columns
          final hasTaxRateBps = await customSelect(
            "SELECT COUNT(*) as cnt FROM pragma_table_info('products') WHERE name = 'tax_rate_bps'",
          ).getSingle();
          if (hasTaxRateBps.read<int>('cnt') > 0) {
            await customStatement(
              'UPDATE products SET purchase_tax_rate_bps = tax_rate_bps, sales_tax_rate_bps = tax_rate_bps WHERE tax_rate_bps > 0',
            );
          }
        }

        // Migration 10026 -> 10027: Customer transaction number + discount type
        if (from < 10027) {
          await _safeAddColumn(
            'customer_transactions',
            'transaction_number',
            'TEXT',
          );
          await _safeAddColumn(
            'customer_transactions',
            'discount_type',
            'TEXT',
          );
        }

        // Migration 10027 -> 10028: Employee commission & sales target fields
        if (from < 10028) {
          await _safeAddColumn(
            'employees',
            'fixed_commission_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'employees',
            'commission_type',
            "TEXT NOT NULL DEFAULT 'percentage'",
          );
          await _safeAddColumn('employees', 'sales_target_cents', 'INTEGER');
          await _safeAddColumn('employees', 'target_bonus_cents', 'INTEGER');
          await _safeAddColumn(
            'employees',
            'target_period',
            "TEXT NOT NULL DEFAULT 'monthly'",
          );
        }

        // Migration 10028 -> 10029: Per-item salesperson on sale_items
        if (from < 10029) {
          await _safeAddColumn(
            'sale_items',
            'employee_id',
            'INTEGER REFERENCES employees(id) ON DELETE SET NULL',
          );
        }

        // Migration 10029 -> 10030: Loyalty points redemption settings
        if (from < 10030) {
          await _safeAddColumn(
            'loyalty_settings',
            'point_value_cents',
            'INTEGER NOT NULL DEFAULT 1',
          );
          await _safeAddColumn(
            'loyalty_settings',
            'min_redemption_points',
            'INTEGER NOT NULL DEFAULT 100',
          );
          await _safeAddColumn(
            'loyalty_settings',
            'max_redemption_percent_bps',
            'INTEGER NOT NULL DEFAULT 5000',
          );
          await _safeAddColumn(
            'loyalty_settings',
            'allow_points_redemption',
            'INTEGER NOT NULL DEFAULT 1',
          );
        }

        // Migration 10030 -> 10031: Employee weekly off-days and annual leave
        if (from < 10031) {
          await _safeAddColumn(
            'employees',
            'weekly_off_days',
            "TEXT NOT NULL DEFAULT '[5,6]'",
          );
          await _safeAddColumn(
            'employees',
            'annual_leave_days',
            'INTEGER NOT NULL DEFAULT 21',
          );
        }

        // Migration 10031 -> 10032: Auto-repair supplier opening balance journals.
        // Creates missing opening_balance journal entries for suppliers that have
        // a non-zero balance_cents but no corresponding journal entry.
        // This is a ONE-TIME, IDEMPOTENT migration. After this, the system
        // enforces that every balance change goes through journal entries.
        if (from < 10032) {
          await _repairSupplierOpeningBalanceJournals();
        }

        // Migration 10032 -> 10033: Employee overtime calculation settings
        if (from < 10033) {
          await _safeAddColumn(
            'employees',
            'overtime_calc_type',
            "TEXT NOT NULL DEFAULT 'hourly_rate'",
          );
          await _safeAddColumn(
            'employees',
            'overtime_rate_bps',
            'INTEGER NOT NULL DEFAULT 15000',
          );
        }

        // Migration 10033 -> 10034: Security question for offline password recovery
        if (from < 10034) {
          await _safeAddColumn('users', 'security_question', 'TEXT');
          await _safeAddColumn('users', 'security_answer_hash', 'TEXT');
        }

        // Migration 10035 -> 10036: Adjustment return tables (dual return system)
        if (from < 10036) {
          await m.createTable(purchaseReturnAdjustments);
          await m.createTable(purchaseReturnAdjustmentItems);
          await m.createTable(saleReturnAdjustments);
          await m.createTable(saleReturnAdjustmentItems);
        }

        // Migration 10036 -> 10037: Add unitCostCents to adjustment return items
        // for perpetual inventory GL entries (Inventory 1200 ↔ COGS 5300)
        if (from < 10037) {
          await _safeAddColumn(
            'purchase_return_adjustment_items',
            'unit_cost_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_return_adjustment_items',
            'unit_cost_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }

        // Migration 10037 -> 10038: Unified return flow — audit fields + refund method on adjustment returns
        if (from < 10038) {
          await _safeAddColumn(
            'purchase_return_adjustments',
            'refund_method',
            "TEXT NOT NULL DEFAULT 'credit'",
          );
          await _safeAddColumn(
            'purchase_return_adjustments',
            'return_mode',
            'TEXT',
          );
          await _safeAddColumn(
            'purchase_return_adjustments',
            'mode_reason',
            'TEXT',
          );
          await _safeAddColumn(
            'purchase_return_adjustments',
            'batch_id',
            'TEXT',
          );
          await _safeAddColumn(
            'sale_return_adjustments',
            'refund_method',
            "TEXT NOT NULL DEFAULT 'cash'",
          );
          await _safeAddColumn(
            'sale_return_adjustments',
            'return_mode',
            'TEXT',
          );
          await _safeAddColumn(
            'sale_return_adjustments',
            'mode_reason',
            'TEXT',
          );
          await _safeAddColumn('sale_return_adjustments', 'batch_id', 'TEXT');
        }

        // Migration 10038 -> 10039: COGS snapshot — freeze cost at sale time
        if (from < 10039) {
          await _safeAddColumn('sale_items', 'cost_cents', 'INTEGER');
        }

        // Migration 10039 -> 10040: Make customer_id nullable in sale_return_adjustments
        // to support walk-in (no customer) returns
        if (from < 10040) {
          await customStatement('PRAGMA foreign_keys = OFF');
          await customStatement('''
            CREATE TABLE sale_return_adjustments__new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              return_number TEXT NOT NULL UNIQUE,
              customer_id INTEGER REFERENCES customers(id),
              currency_id INTEGER NOT NULL REFERENCES currencies(id),
              total_cents INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'draft',
              refund_method TEXT NOT NULL DEFAULT 'cash',
              return_mode TEXT,
              mode_reason TEXT,
              batch_id TEXT,
              notes TEXT,
              return_date DATETIME NOT NULL DEFAULT (CURRENT_TIMESTAMP),
              created_at DATETIME NOT NULL DEFAULT (CURRENT_TIMESTAMP),
              updated_at DATETIME NOT NULL DEFAULT (CURRENT_TIMESTAMP)
            )
          ''');
          await customStatement('''
            INSERT INTO sale_return_adjustments__new
              (id, return_number, customer_id, currency_id, total_cents, status,
               refund_method, return_mode, mode_reason, batch_id, notes,
               return_date, created_at, updated_at)
            SELECT id, return_number, customer_id, currency_id, total_cents, status,
                   refund_method, return_mode, mode_reason, batch_id, notes,
                   return_date, created_at, updated_at
            FROM sale_return_adjustments
          ''');
          await customStatement('DROP TABLE sale_return_adjustments');
          await customStatement(
            'ALTER TABLE sale_return_adjustments__new RENAME TO sale_return_adjustments',
          );
          await customStatement('PRAGMA foreign_keys = ON');
        }

        // Migration 10040 -> 10041: Add discount/tax/subtotal/employee columns to adjustment return tables
        if (from < 10041) {
          // Sale return adjustment header
          await _safeAddColumn(
            'sale_return_adjustments',
            'employee_id',
            'INTEGER REFERENCES employees(id)',
          );
          await _safeAddColumn(
            'sale_return_adjustments',
            'subtotal_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_return_adjustments',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_return_adjustments',
            'tax_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          // Sale return adjustment items
          await _safeAddColumn(
            'sale_return_adjustment_items',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_return_adjustment_items',
            'tax_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          // Purchase return adjustment header
          await _safeAddColumn(
            'purchase_return_adjustments',
            'subtotal_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchase_return_adjustments',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchase_return_adjustments',
            'tax_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          // Purchase return adjustment items
          await _safeAddColumn(
            'purchase_return_adjustment_items',
            'discount_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchase_return_adjustment_items',
            'tax_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }

        // Migration 10041 -> 10042: Add dueDate to adjustment return tables (for cheque payments)
        if (from < 10042) {
          await _safeAddColumn(
            'sale_return_adjustments',
            'due_date',
            'DATETIME',
          );
          await _safeAddColumn(
            'purchase_return_adjustments',
            'due_date',
            'DATETIME',
          );
        }

        // Migration 10042 -> 10043: Inventory Adjustments table (manual stock
        // shrinkage / gain / revaluation with mandatory reason + journal entry).
        // Adds three new system accounts: 5800, 4200, 5900.
        if (from < 10043) {
          await m.createTable(inventoryAdjustments);
        }

        // Migration 10043 -> 10044: Price history audit trail.
        // Append-only record of price/cost changes for products & variants,
        // surfaced in the product form for operators to trace margin history.
        if (from < 10044) {
          await m.createTable(productPriceHistories);
        }

        // Migration 10044 -> 10045: FIFO/Lot tracking foundation.
        //   - Drop the legacy reserved-but-unused product_batches table and
        //     recreate it with full FIFO schema (purchase_item_id, supplier_id,
        //     source, received_quantity, remaining_quantity, unit_cost_cents,
        //     is_active, updated_at).
        //   - Create batch_consumptions append-only ledger.
        //   - Add costing_method to products (default 'wac').
        //   - Seed an opening batch for every (product, variant) with stock>0
        //     so the FIFO invariant Σ(remaining)==stock holds at boot.
        if (from < 10045) {
          // 1. Add costing_method to products (default 'wac' for all existing).
          await _safeAddColumn(
            'products',
            'costing_method',
            "TEXT NOT NULL DEFAULT 'wac'",
          );

          // 2. Drop legacy product_batches (RESERVED — guaranteed empty in
          //    production by the doc comment that lived on the old table).
          //    Use CASCADE-safe drop: disable FK, drop, re-enable.
          await customStatement('PRAGMA foreign_keys = OFF');
          try {
            await customStatement('DROP TABLE IF EXISTS product_batches');
            await m.createTable(productBatches);
            await m.createTable(batchConsumptions);
          } finally {
            await customStatement('PRAGMA foreign_keys = ON');
          }

          // 3. Seed opening batches from current on-hand stock.
          await _seedOpeningBatchesForFifoActivation();
        }

        // Migration 10034 -> 10035: Add opening_balance_cents to suppliers and customers
        // This stores the initial balance separately from the current balance for display
        // and reporting purposes. Existing balance_cents values are copied as opening balance.
        if (from < 10035) {
          await _safeAddColumn(
            'suppliers',
            'opening_balance_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'customers',
            'opening_balance_cents',
            'INTEGER NOT NULL DEFAULT 0',
          );
          // Copy existing balance_cents to opening_balance_cents for existing records
          // that were created with an opening balance (balance_cents != 0)
          await customStatement('''
            UPDATE suppliers SET opening_balance_cents = balance_cents 
            WHERE balance_cents != 0 AND opening_balance_cents = 0
          ''');
          await customStatement('''
            UPDATE customers SET opening_balance_cents = balance_cents 
            WHERE balance_cents != 0 AND opening_balance_cents = 0
          ''');
        }

        // Migration 10045 -> 10046: Reclassify return-adjustment accounts as
        // contra-accounts so the income statement presents Net Sales /
        // Net Cost of Sales without special-casing the report (IFRS/GAAP).
        //
        //   4100 Purchase Return Adjustment: revenue → expense (contra-expense)
        //   5700 Sales Return Adjustment   : expense → revenue (contra-revenue)
        //
        // Posted journal_lines remain unchanged — only the account_type is
        // flipped, which immediately corrects the P&L grouping for both
        // historical and future entries. Idempotent: repeated runs are no-op.
        if (from < 10046) {
          await customStatement(
            "UPDATE accounts SET account_type = 'expense', updated_at = ? "
            "WHERE account_code = '4100' AND account_type != 'expense'",
            [DateTime.now().toIso8601String()],
          );
          await customStatement(
            "UPDATE accounts SET account_type = 'revenue', updated_at = ? "
            "WHERE account_code = '5700' AND account_type != 'revenue'",
            [DateTime.now().toIso8601String()],
          );
          developer.log(
            'Migration 10046: reclassified 4100 (Purchase Return Adj.) as '
            'contra-expense and 5700 (Sales Return Adj.) as contra-revenue.',
            name: 'DB_MIGRATION',
          );
        }

        // Migration 10046 -> 10047: Two-Layer Inventory Architecture (Phase A).
        //
        // Introduces a *business-wide* inventory valuation method stored in
        // `app_settings('inventory_valuation_method')`. Per-product
        // `costing_method` keeps working for now (Phase B switches readers
        // to the global setting); this migration only seeds the default
        // value so the row exists when the new service first reads it.
        //
        // Default rule (mirrors SAP Business One's first-run wizard):
        //   * If ALL existing products are `wac` (or no products yet)
        //     → global = 'wac' (the IFRS-friendliest default for SMBs).
        //   * If ANY product is `fifo`
        //     → global = 'fifo' (preserves the FIFO behaviour the operator
        //                        previously chose, so no posting changes
        //                        unexpectedly when readers are flipped to
        //                        the global setting in Phase B).
        // Idempotent: skips re-inserting when the setting already exists.
        if (from < 10047) {
          final existing = await customSelect(
            "SELECT value FROM app_settings WHERE key = 'inventory_valuation_method'",
          ).getSingleOrNull();

          if (existing == null) {
            // Detect any FIFO product. This query is safe even if the
            // costing_method column is missing (older installs that skipped
            // 10045 will return 0 rows under the catch fallback below).
            int fifoCount = 0;
            try {
              final row = await customSelect(
                "SELECT COUNT(*) AS cnt FROM products WHERE costing_method = 'fifo'",
              ).getSingleOrNull();
              fifoCount = row?.read<int>('cnt') ?? 0;
            } catch (_) {
              fifoCount = 0;
            }

            final seedValue = fifoCount > 0 ? 'fifo' : 'wac';
            final nowIso = DateTime.now().toIso8601String();
            const seedDescription =
                'Business-wide inventory valuation method (IAS 2 / ASC 330). '
                'Seeded from existing per-product costing_method majority.';
            await customStatement(
              'INSERT INTO app_settings (key, value, description, created_at, updated_at) '
              'VALUES (?, ?, ?, ?, ?)',
              [
                'inventory_valuation_method',
                seedValue,
                seedDescription,
                nowIso,
                nowIso,
              ],
            );

            developer.log(
              'Migration 10047: seeded inventory_valuation_method=$seedValue '
              '(fifoProducts=$fifoCount)',
              name: 'DB_MIGRATION',
            );
          }
        }

        // Migration 10047 -> 10048: Two-Layer Inventory Architecture (Phase B).
        //
        // Adds `products.inventory_tracking_type` (`standard`/`batch`/
        // `batch_expiry`) which is the per-product knob that decides whether
        // a product needs batch-level books and expiry tracking.
        //
        // Backfill rules (idempotent — guarded by a column-existence probe):
        //   * costing_method = 'fifo' AND ∃ batch with expiry_date IS NOT NULL
        //         → 'batch_expiry' (pharmacies, dairy, cosmetics, …).
        //   * costing_method = 'fifo' (no expiry rows) → 'batch'.
        //   * costing_method = 'wac' → 'standard'.
        //
        // The legacy `costing_method` column is intentionally NOT dropped:
        // we follow the expand → migrate → contract pattern and keep it as
        // a fallback signal for one release.
        if (from < 10048) {
          final probe = await customSelect(
            "SELECT COUNT(*) AS c FROM pragma_table_info('products') "
            "WHERE name = 'inventory_tracking_type'",
          ).getSingle();
          final hasColumn = (probe.data['c'] as int? ?? 0) > 0;
          if (!hasColumn) {
            await customStatement(
              'ALTER TABLE products ADD COLUMN inventory_tracking_type '
              "TEXT NOT NULL DEFAULT 'standard'",
            );
          }

          // Backfill from costing_method + presence of expiry rows. We use
          // CASE/EXISTS so the whole UPDATE is a single statement.
          await customStatement('''
            UPDATE products
               SET inventory_tracking_type = CASE
                 WHEN costing_method = 'fifo' AND EXISTS (
                   SELECT 1 FROM product_batches b
                    WHERE b.product_id = products.id
                      AND b.expiry_date IS NOT NULL
                 ) THEN 'batch_expiry'
                 WHEN costing_method = 'fifo' THEN 'batch'
                 ELSE 'standard'
               END
             WHERE inventory_tracking_type = 'standard'
                OR inventory_tracking_type IS NULL
          ''');

          final stats = await customSelect('''
            SELECT inventory_tracking_type AS t, COUNT(*) AS c
              FROM products
             GROUP BY inventory_tracking_type
          ''').get();
          final summary = stats
              .map((r) => '${r.data['t']}=${r.data['c']}')
              .join(', ');
          developer.log(
            'Migration 10048: backfilled products.inventory_tracking_type '
            '($summary)',
            name: 'DB_MIGRATION',
          );
        }

        // Migration 10048 -> 10049: product_batches integrity triggers (I3).
        //
        // Phase I of the Two-Layer Inventory Architecture: defense-in-depth
        // CHECK constraints enforced at the DB layer via BEFORE INSERT/UPDATE
        // triggers. SQLite does not support `ALTER TABLE ADD CHECK`, so we
        // implement the same semantics with `RAISE(ABORT, ...)` triggers.
        //
        // Two invariants (mirrors INVENTORY_ARCHITECTURE.md §6 I1/I2):
        //   • remaining_quantity >= 0
        //   • remaining_quantity <= received_quantity
        //
        // Pre-migration scan: count violators FIRST. If any exist, log every
        // offending row and abort the migration with a clear, actionable
        // exception. The app refuses to boot until the data is repaired —
        // this is a deliberate fail-loud policy because silent data
        // corruption in inventory is the worst possible outcome.
        if (from < 10049) {
          final neg = await customSelect(
            'SELECT COUNT(*) AS c FROM product_batches '
            'WHERE remaining_quantity < 0',
          ).getSingle();
          final negCount = neg.data['c'] as int? ?? 0;

          final over = await customSelect(
            'SELECT COUNT(*) AS c FROM product_batches '
            'WHERE remaining_quantity > received_quantity',
          ).getSingle();
          final overCount = over.data['c'] as int? ?? 0;

          if (negCount > 0 || overCount > 0) {
            final rows = await customSelect(
              'SELECT id, product_id, variant_id, batch_number, '
              '       remaining_quantity, received_quantity '
              '  FROM product_batches '
              ' WHERE remaining_quantity < 0 '
              '    OR remaining_quantity > received_quantity '
              ' ORDER BY id',
            ).get();
            for (final r in rows) {
              developer.log(
                'Migration 10049 VIOLATOR: batch_id=${r.data['id']} '
                '(${r.data['batch_number']}) '
                'product=${r.data['product_id']} '
                'variant=${r.data['variant_id']} '
                'remaining=${r.data['remaining_quantity']} '
                'received=${r.data['received_quantity']}',
                name: 'DB_MIGRATION',
              );
            }
            throw StateError(
              'Migration 10049 aborted: '
              '$negCount row(s) with remaining_quantity<0, '
              '$overCount row(s) with remaining_quantity>received_quantity. '
              'Fix corrupt product_batches data before retrying. '
              'See DB_MIGRATION log for offending IDs.',
            );
          }

          await _installProductBatchesIntegrityTriggers();
          developer.log(
            'Migration 10049: installed product_batches integrity triggers '
            '(remaining >= 0 AND remaining <= received_quantity)',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10049 → 10050 — Phase 0 hardening for the return system.
        // ════════════════════════════════════════════════════════════════════
        // Adds:
        //   • sale_items.qty_returned_linked / qty_returned_adjustment
        //   • purchase_items.qty_returned_linked / qty_returned_adjustment
        //   • idempotency_key (TEXT NULL UNIQUE) on the four return headers:
        //       sale_returns, purchase_returns,
        //       sale_return_adjustments, purchase_return_adjustments
        //
        // Why these counters:
        //   The previous validation only checked stock at post-time. A user
        //   could legitimately have stock (from an unrelated supplier or a
        //   prior return cycle) and still over-return a given (party, product)
        //   pair across multiple invoices. The atomic counter pinned to each
        //   sale_item / purchase_item is the authoritative cap and survives
        //   reporting drift.
        //
        // Backfill strategy:
        //   • qty_returned_linked = Σ(quantity) on non-voided
        //     sale_return_items / purchase_return_items grouped by line.
        //   • qty_returned_adjustment stays at 0 — adjustment returns are
        //     not pinned to a specific invoice line, so they can't be
        //     attributed retroactively. Future returns will increment them.
        //
        // Idempotency keys are NULL by default for legacy rows so the unique
        // index does not collide. Only forward submissions set them.
        if (from < 10050) {
          // 1. Counters on sale_items / purchase_items.
          await _safeAddColumn(
            'sale_items',
            'qty_returned_linked',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'sale_items',
            'qty_returned_adjustment',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchase_items',
            'qty_returned_linked',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            'purchase_items',
            'qty_returned_adjustment',
            'INTEGER NOT NULL DEFAULT 0',
          );

          // Backfill linked counters from existing return items (non-voided).
          await customStatement(
            'UPDATE sale_items SET qty_returned_linked = COALESCE(('
            '  SELECT SUM(sri.quantity) FROM sale_return_items sri '
            '  JOIN sale_returns sr ON sr.id = sri.return_id '
            "  WHERE sri.sale_item_id = sale_items.id AND sr.status != 'voided'"
            '), 0)',
          );
          await customStatement(
            'UPDATE purchase_items SET qty_returned_linked = COALESCE(('
            '  SELECT SUM(pri.quantity) FROM purchase_return_items pri '
            '  JOIN purchase_returns pr ON pr.id = pri.return_id '
            "  WHERE pri.purchase_item_id = purchase_items.id AND pr.status != 'voided'"
            '), 0)',
          );

          // 2. Idempotency keys on the four return headers.
          await _safeAddColumn('sale_returns', 'idempotency_key', 'TEXT');
          await _safeAddColumn('purchase_returns', 'idempotency_key', 'TEXT');
          await _safeAddColumn(
            'sale_return_adjustments',
            'idempotency_key',
            'TEXT',
          );
          await _safeAddColumn(
            'purchase_return_adjustments',
            'idempotency_key',
            'TEXT',
          );

          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_sale_returns_idempotency '
            'ON sale_returns(idempotency_key) WHERE idempotency_key IS NOT NULL',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_returns_idempotency '
            'ON purchase_returns(idempotency_key) WHERE idempotency_key IS NOT NULL',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_sale_return_adjustments_idempotency '
            'ON sale_return_adjustments(idempotency_key) WHERE idempotency_key IS NOT NULL',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_return_adjustments_idempotency '
            'ON purchase_return_adjustments(idempotency_key) WHERE idempotency_key IS NOT NULL',
          );

          developer.log(
            'Migration 10050: added qty_returned_* counters + idempotency_key '
            'columns to return tables (Phase 0 hardening).',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10050 → 10051 — Phase 2 compliance & period management.
        // ════════════════════════════════════════════════════════════════════
        // Adds:
        //   • Snapshot columns on the four return-line tables:
        //       sale_return_items.tax_rate_bps_at_post,
        //                       .unit_cost_at_post_cents
        //       purchase_return_items.tax_rate_bps_at_post,
        //                            .unit_cost_at_post_cents
        //       sale_return_adjustment_items.tax_rate_bps_at_post,
        //                                   .unit_cost_at_post_cents,
        //                                   .original_invoice_id,
        //                                   .disposition_type
        //       purchase_return_adjustment_items.tax_rate_bps_at_post,
        //                                       .unit_cost_at_post_cents,
        //                                       .original_invoice_id,
        //                                       .disposition_type
        //   • fx_rate_to_base on the four return headers.
        //   • New tables: fiscal_periods, customer_credit_notes,
        //                 customer_credit_note_applications.
        //
        // Why these:
        //   - Snapshots freeze tax rate + unit cost at post-time so future
        //     rate changes / WAC drift cannot retroactively distort an
        //     already-posted return (IFRS / IAS 12 / IAS 2 compliance).
        //   - disposition_type per line lets adjustment returns mix
        //     restock / damaged / scrap and route the inventory leg to
        //     1200 vs 5800 in ReturnJournalPolicy.
        //   - fx_rate_to_base captures the booking-time rate so
        //     multi-currency returns can be revalued at base in reports.
        //   - fiscal_periods + close enforcement is a hard requirement of
        //     every world-class accounting product (QB, Odoo, NetSuite).
        //   - customer_credit_notes is the sub-ledger backing 2400
        //     Customer Credit Liability — Σ(open balances) MUST tie out
        //     to the GL.
        if (from < 10051) {
          // 1. Snapshot columns on return-line tables.
          await _safeAddColumn(
            'sale_return_items',
            'tax_rate_bps_at_post',
            'INTEGER',
          );
          await _safeAddColumn(
            'sale_return_items',
            'unit_cost_at_post_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'purchase_return_items',
            'tax_rate_bps_at_post',
            'INTEGER',
          );
          await _safeAddColumn(
            'purchase_return_items',
            'unit_cost_at_post_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'sale_return_adjustment_items',
            'tax_rate_bps_at_post',
            'INTEGER',
          );
          await _safeAddColumn(
            'sale_return_adjustment_items',
            'unit_cost_at_post_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'sale_return_adjustment_items',
            'original_invoice_id',
            'INTEGER',
          );
          await _safeAddColumn(
            'sale_return_adjustment_items',
            'disposition_type',
            "TEXT NOT NULL DEFAULT 'restock'",
          );
          await _safeAddColumn(
            'purchase_return_adjustment_items',
            'tax_rate_bps_at_post',
            'INTEGER',
          );
          await _safeAddColumn(
            'purchase_return_adjustment_items',
            'unit_cost_at_post_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'purchase_return_adjustment_items',
            'original_invoice_id',
            'INTEGER',
          );
          await _safeAddColumn(
            'purchase_return_adjustment_items',
            'disposition_type',
            "TEXT NOT NULL DEFAULT 'restock'",
          );

          // 2. FX columns on return headers.
          await _safeAddColumn('sale_returns', 'fx_rate_to_base', 'TEXT');
          await _safeAddColumn('purchase_returns', 'fx_rate_to_base', 'TEXT');
          await _safeAddColumn(
            'sale_return_adjustments',
            'fx_rate_to_base',
            'TEXT',
          );
          await _safeAddColumn(
            'purchase_return_adjustments',
            'fx_rate_to_base',
            'TEXT',
          );

          // 3. New tables: fiscal_periods, customer_credit_notes,
          //    customer_credit_note_applications.
          await customStatement('''
CREATE TABLE IF NOT EXISTS fiscal_periods (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  period_key TEXT NOT NULL UNIQUE,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  closed_by_user_id INTEGER,
  closed_at TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
)
''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_fiscal_periods_status_dates '
            'ON fiscal_periods(status, start_date, end_date)',
          );

          await customStatement('''
CREATE TABLE IF NOT EXISTS customer_credit_notes (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  note_number TEXT NOT NULL UNIQUE,
  customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
  currency_id INTEGER NOT NULL REFERENCES currencies(id) ON DELETE RESTRICT,
  original_amount_cents INTEGER NOT NULL,
  balance_cents INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  source_table TEXT NOT NULL,
  source_id INTEGER NOT NULL,
  issue_journal_entry_id INTEGER,
  expires_at TEXT,
  notes TEXT,
  issued_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
)
''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_customer_credit_notes_customer '
            'ON customer_credit_notes(customer_id, status)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_customer_credit_notes_source '
            'ON customer_credit_notes(source_table, source_id)',
          );

          await customStatement('''
CREATE TABLE IF NOT EXISTS customer_credit_note_applications (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  credit_note_id INTEGER NOT NULL REFERENCES customer_credit_notes(id) ON DELETE RESTRICT,
  sale_id INTEGER,
  amount_cents INTEGER NOT NULL,
  journal_entry_id INTEGER,
  notes TEXT,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
)
''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_credit_note_apps_note '
            'ON customer_credit_note_applications(credit_note_id)',
          );

          developer.log(
            'Migration 10051: added Phase 2 snapshot/disposition/FX columns '
            'and fiscal_periods + customer_credit_notes ledger tables.',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10051 → 10052 — Phase 3 approval workflow & audit trail.
        // ════════════════════════════════════════════════════════════════════
        // Adds on every return header (sale_returns, purchase_returns,
        // sale_return_adjustments, purchase_return_adjustments):
        //   • approval_status          TEXT NOT NULL DEFAULT 'auto_approved'
        //   • approval_required        INTEGER NOT NULL DEFAULT 0
        //   • approval_reason          TEXT
        //   • approved_by              INTEGER -> users(id) ON DELETE SET NULL
        //   • approved_at              TEXT
        //   • override_reason          TEXT
        //   • override_by              INTEGER -> users(id) ON DELETE SET NULL
        //   • posted_by                INTEGER -> users(id) ON DELETE SET NULL
        //   • posted_at                TEXT
        //   • voided_by                INTEGER -> users(id) ON DELETE SET NULL
        //   • voided_at                TEXT
        //   • void_reason              TEXT
        //   • reason_code_id           INTEGER -> return_reason_codes(id)
        //
        // Also creates the new `return_reason_codes` lookup table and
        // seeds it with system codes (`DEFECTIVE`, `WRONG_ITEM`,
        // `CUSTOMER_CHANGED_MIND`, `DAMAGED_IN_TRANSIT`, `EXPIRED`,
        // `NO_INVOICE`, `PRICE_ADJUSTMENT`, `OTHER`).
        //
        // Why these:
        //   - Approval workflow: mandatory in every world-class ERP
        //     (SAP, Odoo, QB) for returns above a threshold, returns
        //     without an original invoice, or when the operator uses
        //     `allowOverHistory` to bypass the Phase 0 quantity cap.
        //   - Audit trail: `posted_by`/`voided_by` + timestamps are
        //     regulatory minima (ZATCA, ETA, SOX). Free-text
        //     `void_reason` supports internal control narratives.
        //   - Normalised `reason_code_id` replaces free-text `reason`
        //     for analytics & e-invoice XML fields.
        //
        // NOTE — because the FK targets (`users`, `return_reason_codes`)
        // must exist before any ALTER, we create `return_reason_codes`
        // first. All new columns are nullable / defaulted so legacy
        // rows upgrade safely without data-migration.
        if (from < 10052) {
          // 1. Lookup table — seed happens in _seedInitialData() after migrate().
          await customStatement('''
CREATE TABLE IF NOT EXISTS return_reason_codes (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  label_en TEXT NOT NULL,
  label_ar TEXT NOT NULL,
  side TEXT NOT NULL DEFAULT 'both',
  is_active INTEGER NOT NULL DEFAULT 1,
  is_system INTEGER NOT NULL DEFAULT 0,
  description TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
)
''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_return_reason_codes_side_active '
            'ON return_reason_codes(side, is_active)',
          );

          // 2. Approval / audit columns on all four return headers.
          for (final table in const [
            'sale_returns',
            'purchase_returns',
            'sale_return_adjustments',
            'purchase_return_adjustments',
          ]) {
            await _safeAddColumn(
              table,
              'approval_status',
              "TEXT NOT NULL DEFAULT 'auto_approved'",
            );
            await _safeAddColumn(
              table,
              'approval_required',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _safeAddColumn(table, 'approval_reason', 'TEXT');
            await _safeAddColumn(table, 'approved_by', 'INTEGER');
            await _safeAddColumn(table, 'approved_at', 'TEXT');
            await _safeAddColumn(table, 'override_reason', 'TEXT');
            await _safeAddColumn(table, 'override_by', 'INTEGER');
            await _safeAddColumn(table, 'posted_by', 'INTEGER');
            await _safeAddColumn(table, 'posted_at', 'TEXT');
            await _safeAddColumn(table, 'voided_by', 'INTEGER');
            await _safeAddColumn(table, 'voided_at', 'TEXT');
            await _safeAddColumn(table, 'void_reason', 'TEXT');
            await _safeAddColumn(table, 'reason_code_id', 'INTEGER');
          }

          developer.log(
            'Migration 10052: added Phase 3 approval & audit columns on '
            'all four return headers + return_reason_codes table.',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10052 → 10053 — Phase 4 e-invoice infrastructure.
        // ════════════════════════════════════════════════════════════════════
        // Adds:
        //   • `einvoice_documents` — single table storing every outgoing
        //     e-invoice artifact (ZATCA Phase 2 signed XML, ETA JSON,
        //     PEPPOL UBL). One row per (source_table, source_id) UNIQUE.
        //   • `app_settings` rows consumed as jurisdiction config:
        //       - `einvoice_jurisdiction` (`NONE` | `KSA_ZATCA_PHASE2` |
        //         `EG_ETA` | `EU_PEPPOL`)
        //       - `einvoice_enabled` (`'true'` | `'false'`)
        //       - `einvoice_tax_registration_number`
        //       - `einvoice_legal_name`
        //       - `einvoice_onboarding_config_json` (provider-specific)
        //
        // The table is jurisdiction-agnostic; per-country providers read and
        // write their payload columns through the same repository.
        if (from < 10053) {
          await customStatement('''
CREATE TABLE IF NOT EXISTS e_invoice_documents (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  source_table TEXT NOT NULL,
  source_id INTEGER NOT NULL,
  jurisdiction TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft',
  icv INTEGER,
  document_uuid TEXT,
  document_hash TEXT,
  previous_hash TEXT,
  payload_xml TEXT,
  payload_json TEXT,
  qr_code_base64 TEXT,
  response_payload TEXT,
  last_error TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  prepared_at TEXT,
  submitted_at TEXT,
  cleared_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(source_table, source_id)
);
''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_einvoice_docs_status '
            'ON e_invoice_documents(status);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_einvoice_docs_icv '
            'ON e_invoice_documents(jurisdiction, icv);',
          );
          developer.log(
            'Migration 10053: created e_invoice_documents table (Phase 4).',
            name: 'DB_MIGRATION',
          );
        }

        // Migration 10053 → 10054: Phase 11.2 audit-snapshot columns on
        // every invoice / return header. Columns are nullable so legacy
        // rows continue to validate; new posts are written through the
        // DAO layer with `PricingEngineVersion.current` + the engine's
        // tax-inclusive + rounding-mode settings.
        if (from < 10054) {
          for (final table in const [
            'sales',
            'purchases',
            'sale_returns',
            'purchase_returns',
            'sale_return_adjustments',
            'purchase_return_adjustments',
          ]) {
            await _safeAddColumn(table, 'pricing_engine_version', 'TEXT');
            await _safeAddColumn(table, 'tax_inclusive_at_post', 'INTEGER');
            await _safeAddColumn(table, 'rounding_mode_at_post', 'TEXT');
          }
          developer.log(
            'Migration 10054: added audit-snapshot columns '
            '(pricing_engine_version, tax_inclusive_at_post, '
            'rounding_mode_at_post) to 6 invoice/return header tables '
            '(Phase 11.2).',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10054 → 10055 — Decouple "supplier reference price" from
        // the IAS-2 inventory cost basis.
        // ════════════════════════════════════════════════════════════════════
        // Adds nullable `last_purchase_price_cents` to `products` and
        // `product_variants`. The existing `cost_cents` stays NET of trade
        // discounts (used for COGS, inventory valuation, GL reconciliation
        // — IAS 2 §11), while `last_purchase_price_cents` stores the GROSS
        // unit cost the user typed on the most recent purchase line and is
        // displayed by the product/variant edit screens.
        //
        // Backfill is intentionally a no-op: existing rows leave the column
        // NULL, and every UI read falls back to `cost_cents` via the
        // `lastPurchasePriceCents ?? costCents` pattern. New purchases write
        // both columns going forward (see `purchase_dao.postPurchase`).
        if (from < 10055) {
          await _safeAddColumn(
            'products',
            'last_purchase_price_cents',
            'INTEGER',
          );
          await _safeAddColumn(
            'product_variants',
            'last_purchase_price_cents',
            'INTEGER',
          );
          developer.log(
            'Migration 10055: added last_purchase_price_cents (nullable) '
            'to products and product_variants. Decouples supplier reference '
            'price (gross) from IAS-2 inventory cost basis (net).',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10055 → 10056 — Phase 14.0 cheque lifecycle minimal-risk.
        // ════════════════════════════════════════════════════════════════════
        // Adds:
        //   1. `cheque_confirmations` table — sidecar for the dashboard
        //      "confirm collected / bounced / cancelled" UX. Replaces the
        //      old SharedPreferences-only dismissal that did not survive
        //      device migration nor produce an audit trail. Status values:
        //      pending | cleared | bounced | cancelled. One row per
        //      (source_table, source_id). No JE policy change in this phase
        //      — `cleared` is purely informational and the dashboard reads
        //      pending rows only.
        //   2. `sale_returns.due_date` + `purchase_returns.due_date`
        //      (nullable). Closes the gap where linked returns paid by
        //      cheque had no due-date storage and were invisible to the
        //      dashboard reminder. Symmetric to the existing columns on
        //      `sales`, `purchases`, `sale_return_adjustments`,
        //      `purchase_return_adjustments`.
        //
        // All additive, all idempotent, all nullable defaults — no risk
        // to existing rows. See `docs/ACCOUNTING_INTEGRITY_GUIDELINES.md`
        // §Phase-14 for the SoT entries.
        if (from < 10056) {
          await _safeAddColumn('sale_returns', 'due_date', 'TEXT');
          await _safeAddColumn('purchase_returns', 'due_date', 'TEXT');
          await customStatement('''
CREATE TABLE IF NOT EXISTS cheque_confirmations (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  source_table TEXT NOT NULL,
  source_id INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  confirmed_at TEXT,
  confirmed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  note TEXT,
  bounce_reason TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S.000', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S.000', 'now')),
  UNIQUE (source_table, source_id)
)
''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_cheque_confirmations_status '
            'ON cheque_confirmations(status)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_cheque_confirmations_source '
            'ON cheque_confirmations(source_table, source_id)',
          );
          developer.log(
            'Migration 10056: added sale_returns.due_date, '
            'purchase_returns.due_date, and cheque_confirmations table. '
            'Phase 14.0 minimal-risk cheque lifecycle (no JE policy change).',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10056 → 10057 — Phase 15.0 cheque lifecycle JE wiring.
        // ════════════════════════════════════════════════════════════════════
        // Adds `cheque_confirmations.cleared_payment_id` (nullable INT).
        //
        // Closes the field-reported gap where confirming a cheque as
        // `cleared` in the dashboard wrote only to `cheque_confirmations`
        // but did NOT settle the supplier/customer balance, did NOT
        // insert a `purchase_payments` / `sale_payments` row, and did NOT
        // post the corresponding Dr/Cr Bank journal entry. Phase 14 had
        // deferred the JE side to "a future phase"; this is that phase.
        //
        // The new column stores the `purchase_payments.id` (or
        // `sale_payments.id`, polymorphic via `source_table`) created by
        // the `ChequeLifecycleService.markCleared` orchestrator. A later
        // `cleared → bounced` / `cleared → cancelled` transition uses
        // that id to call `deletePayment` on the matching repo, which
        // restores the party balance, voids the JE, and zeroes
        // `purchases.paid_amount_cents` / `sales.paid_amount_cents`.
        //
        // All additive, all nullable. No existing-row migration required.
        // See `docs/ACCOUNTING_INTEGRITY_GUIDELINES.md` §Phase-15.
        if (from < 10057) {
          await _safeAddColumn(
            'cheque_confirmations',
            'cleared_payment_id',
            'INTEGER',
          );
          developer.log(
            'Migration 10057: added cheque_confirmations.cleared_payment_id. '
            'Phase 15.0 cheque-lifecycle JE wiring. Cleared cheques now '
            'post a real PurchasePayment/SalePayment (settles AP/AR + Dr/Cr '
            'Bank). Bounced/cancelled-after-cleared reverses deterministically.',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10057 → 10058 — Commission economic-event date.
        // ════════════════════════════════════════════════════════════════════
        // Adds `commissions.effective_date` (nullable ISO-text DateTime) — the
        // SAP / NetSuite / QuickBooks "posting / transaction date" convention.
        // Reports attribute each commission row by this economic-event date
        // instead of the physical `created_at` insertion timestamp, so sales
        // and returns land in their true economic period even for backdated
        // documents, and the salespeople report can filter arbitrary ranges.
        //
        // Backfill:
        //   * EARNED rows (amount ≥ 0 with a linked sale) → the sale's date.
        //   * All remaining rows (reversals + orphans) → `created_at` (the
        //     insertion time ≈ the return-post time; best available signal).
        if (from < 10058) {
          await _safeAddColumn('commissions', 'effective_date', 'TEXT');
          await customStatement(
            'UPDATE commissions '
            'SET effective_date = ('
            '  SELECT s.sale_date FROM sales s WHERE s.id = commissions.sale_id'
            ') '
            'WHERE effective_date IS NULL '
            '  AND sale_id IS NOT NULL '
            '  AND commission_amount_cents >= 0',
          );
          await customStatement(
            'UPDATE commissions SET effective_date = created_at '
            'WHERE effective_date IS NULL',
          );
          developer.log(
            'Migration 10058: added commissions.effective_date + backfilled '
            '(earned→sale_date, reversal→created_at). Commission reports now '
            'attribute by economic-event date, not physical insertion time.',
            name: 'DB_MIGRATION',
          );
        }

        // ════════════════════════════════════════════════════════════════════
        // Migration 10058 → 10059 — Commission reversal for adjustment returns.
        // ════════════════════════════════════════════════════════════════════
        // Adds `commissions.sale_return_adjustment_id` (nullable INT). An
        // unlinked (adjustment) sale return attributed to a salesperson now
        // posts a NEGATIVE commission row keyed by this id, so the employee's
        // commission is deducted symmetrically with a normal linked return.
        // Voiding the adjustment return deletes exactly that reversal row.
        //
        // Additive + nullable. No existing-row backfill required (historical
        // adjustment returns simply never had a reversal; a Ledger/commission
        // rebuild is the recovery path if a retroactive deduction is wanted).
        if (from < 10059) {
          await _safeAddColumn(
            'commissions',
            'sale_return_adjustment_id',
            'INTEGER',
          );
          developer.log(
            'Migration 10059: added commissions.sale_return_adjustment_id. '
            'Adjustment (unlinked) sale returns attributed to a salesperson '
            'now deduct commission via a negative row keyed by the return id.',
            name: 'DB_MIGRATION',
          );
        }

        // Migration 10059 -> 10060: re-prefix legacy unlinked-sale-return
        // batches so they read as `SAR-…` in the Batch Management report.
        //
        // Unlinked sale-adjustment returns materialise a batch
        // (source='sale_return'). The old naming used an `SR-YYYYMM-V…`
        // prefix which COLLIDES visually with LINKED sale-return document
        // numbers (`SR-YYYYMM-NNNN`), making the unlinked batches look like
        // linked returns in the report. New posts now embed the actual
        // `SAR-…` return number; this back-fills existing rows by swapping
        // the leading `SR-` for `SAR-`. Display-only (batch_number is never a
        // lookup key) and idempotent (the LIKE guard skips already-migrated
        // rows). The UNIQUE(batch_number) constraint holds because the
        // trailing microsecond timestamp keeps every value distinct.
        if (from < 10060) {
          await customStatement(
            'UPDATE product_batches '
            "   SET batch_number = 'SAR-' || SUBSTR(batch_number, 4), "
            '       updated_at = ? '
            " WHERE source = 'sale_return' "
            "   AND batch_number LIKE 'SR-%'",
            [DateTime.now().toIso8601String()],
          );
          developer.log(
            'Migration 10060: re-prefixed legacy sale_return batches '
            'SR- -> SAR- so unlinked sale returns are identifiable in the '
            'Batch Management report.',
            name: 'DB_MIGRATION',
          );
        }

        // Migration 10060 -> 10061: owner finance and fixed-asset sub-ledgers.
        // Additive tables only; existing business data and journal entries are
        // untouched. Required system accounts are idempotently seeded in
        // beforeOpen after the schema upgrade completes.
        if (from < 10061) {
          await m.createTable(ownerFinanceTransactions);
          await m.createTable(fixedAssets);
          await m.createTable(fixedAssetDepreciations);
          developer.log(
            'Migration 10061: added owner finance, fixed assets, and '
            'fixed-asset depreciation sub-ledgers.',
            name: 'DB_MIGRATION',
          );
        }

        // Migration 10061 -> 10062: real POS cashier sessions. Historical
        // documents stay NULL and are never guessed from timestamps.
        if (from < 10062) {
          await m.createTable(cashierShifts);
          await _safeAddColumn(
            'sales',
            'cashier_shift_id',
            'INTEGER REFERENCES cashier_shifts(id) ON DELETE SET NULL',
          );
          await _safeAddColumn(
            'sale_returns',
            'cashier_shift_id',
            'INTEGER REFERENCES cashier_shifts(id) ON DELETE SET NULL',
          );
          await _safeAddColumn(
            'sale_return_adjustments',
            'cashier_shift_id',
            'INTEGER REFERENCES cashier_shifts(id) ON DELETE SET NULL',
          );
          await _safeAddColumn(
            'sale_payments',
            'cashier_shift_id',
            'INTEGER REFERENCES cashier_shifts(id) ON DELETE SET NULL',
          );
          developer.log(
            'Migration 10062: added cashier shifts and explicit POS '
            'transaction links.',
            name: 'DB_MIGRATION',
          );
        }

        // Migration 10062 -> 10063: exact measured quantities. Existing
        // products and document lines remain count-based (scale=1), while
        // new measured products snapshot their dimension and scale on every
        // invoice/return line for reproducible historical accounting.
        if (from < 10063) {
          await _safeAddColumn(
            'products',
            'measurement_type',
            "TEXT NOT NULL DEFAULT 'piece'",
          );
          for (final table in <String>[
            'sale_items',
            'sale_return_items',
            'purchase_items',
            'purchase_return_items',
            'purchase_return_adjustment_items',
            'sale_return_adjustment_items',
          ]) {
            await _safeAddColumn(
              table,
              'quantity_scale',
              'INTEGER NOT NULL DEFAULT 1 CHECK (quantity_scale > 0)',
            );
            await _safeAddColumn(
              table,
              'measurement_type',
              "TEXT NOT NULL DEFAULT 'piece'",
            );
          }
          developer.log(
            'Migration 10063: added measured product dimensions and frozen '
            'quantity scales to invoice/return lines.',
            name: 'DB_MIGRATION',
          );
        }

        if (from < 10064) {
          await _ensureDocumentSequencesTable();
          developer.log(
            'Migration 10064: added permanent business document sequences.',
            name: 'DB_MIGRATION',
          );
        }

        if (from < 10065) {
          await _repairMeasuredLinkedReturnScalesAndJournals();
        }

        if (from < 10066) {
          for (final table in <String>[
            'sale_items',
            'purchase_items',
            'sale_return_items',
            'purchase_return_items',
            'purchase_return_adjustment_items',
            'sale_return_adjustment_items',
          ]) {
            await _safeAddColumn(
              table,
              'inventory_value_at_post_cents',
              'INTEGER',
            );
          }
          await _repairMeasuredInventoryRounding10066();
        }

        if (from < 10067) {
          await _normalizePriceHistoryCents10067();
        }

        if (from < 10068) {
          await _reconcileSimpleProductRows10068();
        }

        if (from < 10069) {
          await _safeAddColumn('sales', 'idempotency_key', 'TEXT');
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_idempotency '
            'ON sales(idempotency_key) WHERE idempotency_key IS NOT NULL',
          );
          developer.log(
            'Migration 10069: added idempotent LAN sale requests.',
            name: 'DB_MIGRATION',
          );
        }

        await _createIndexes();
        await _seedInitialData();
      },
      beforeOpen: (details) async {
        developer.log(
          'DB open: wasCreated=${details.wasCreated} hadUpgrade=${details.hadUpgrade} '
          'versionBefore=${details.versionBefore} versionNow=${details.versionNow}',
          name: 'DB_LIFECYCLE',
        );
        await customStatement('PRAGMA foreign_keys = ON');
        await customStatement('PRAGMA journal_mode = WAL');
        await customStatement('PRAGMA synchronous = NORMAL');
        await _ensureDocumentSequencesTable();
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
        try {
          await _seedDefaultLoyaltySettings();
        } catch (e, st) {
          debugPrint('DB seed skipped (loyalty settings): $e');
          debugPrint('$st');
        }
        try {
          await _seedDefaultAccounts();
        } catch (e, st) {
          debugPrint('DB seed skipped (default accounts): $e');
          debugPrint('$st');
        }
      },
    );
  }

  Future<void> _ensureDocumentSequencesTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS document_sequences (
        prefix TEXT NOT NULL PRIMARY KEY,
        last_number INTEGER NOT NULL DEFAULT 0 CHECK (last_number >= 0),
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  /// Log pre-migration backup intent.
  /// The actual file-level backup is performed by [createDatabaseBackup] in
  /// database_native.dart, which the DI layer calls before database open.
  /// This method ensures the migration log records the backup attempt.
  Future<void> _createPreMigrationBackup() async {
    developer.log(
      'Pre-migration backup requested. File-level backup handled by DI init.',
      name: 'DB_MIGRATION',
    );
  }

  @visibleForTesting
  Future<void> seedInitialDataForTest() => _seedInitialData();

  @visibleForTesting
  Future<void> createIndexesForTest() => _createIndexes();

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cashier_shifts_one_open '
      "ON cashier_shifts(cashier_user_id) WHERE status = 'open'",
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cashier_shifts_opened '
      'ON cashier_shifts(opened_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_cashier_shift '
      'ON sales(cashier_shift_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_returns_cashier_shift '
      'ON sale_returns(cashier_shift_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_return_adj_cashier_shift '
      'ON sale_return_adjustments(cashier_shift_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_payments_cashier_shift '
      'ON sale_payments(cashier_shift_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_customer_date ON sales(customer_id, sale_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active, name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_journal_entry_date ON journal_entries(entry_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_commissions_employee_effective ON commissions(employee_id, effective_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_audit_table_record ON audit_logs(target_table, record_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_barcode ON product_variants(barcode) WHERE barcode IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_product_color_size_unique '
      'ON product_variants(product_id, IFNULL(color_id, -1), IFNULL(size_id, -1))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(is_active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_active ON suppliers(is_active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_currency_active ON currencies(is_active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_barcode_templates_default ON barcode_templates(is_default)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_print_history_product ON print_histories(product_id, print_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_print_history_date ON print_histories(print_date)',
    );

    // Employee management indexes
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_employees_active ON employees(is_active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_employees_role ON employees(role_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_employees_manager ON employees(manager_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_employees_department ON employees(department)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attendances_employee_date ON attendances(employee_id, attendance_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attendances_date ON attendances(attendance_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests(employee_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_payrolls_employee ON payrolls(employee_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_payrolls_period ON payrolls(period_start, period_end)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_payrolls_status ON payrolls(status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_commissions_employee ON commissions(employee_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_commissions_period ON commissions(period)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_commissions_sale_return_adjustment ON commissions(sale_return_adjustment_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_shift_schedules_employee_date ON shift_schedules(employee_id, shift_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_performance_metrics_employee ON performance_metrics(employee_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_performance_metrics_period ON performance_metrics(period_identifier)',
    );

    // Purchase enhancement indexes
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchases_status ON purchases(status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON purchases(supplier_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchases_due_date ON purchases(due_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_payments_purchase ON purchase_payments(purchase_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_returns_purchase ON purchase_returns(purchase_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_returns_status ON purchase_returns(status)',
    );

    // Sale enhancement indexes
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_status ON sales(status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_due_date ON sales(due_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_payments_sale ON sale_payments(sale_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_returns_sale ON sale_returns(sale_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_returns_status ON sale_returns(status)',
    );

    // Dashboard aggregation indexes (covering indexes for status + totals)
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_status_total ON sales(status, total_cents)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_status_date_total ON sales(status, sale_date, total_cents)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchases_status_total ON purchases(status, total_cents, paid_amount_cents)',
    );

    // Invoice/purchase number generation (prefix LIKE + ORDER BY)
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_invoice_number ON sales(invoice_number)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchases_number ON purchases(purchase_number)',
    );

    // Journal entry source lookups (used by voidJournalEntriesForSource)
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_journal_entries_source ON journal_entries(source_table, source_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_entry ON journal_entry_lines(journal_entry_id)',
    );

    // Customer/supplier transaction lookups
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_customer_transactions_customer ON customer_transactions(customer_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_supplier_transactions_supplier ON supplier_transactions(supplier_id)',
    );

    // Product variant stock lookups (used in postSale stock validation)
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_product_variants_product_active ON product_variants(product_id, is_active)',
    );

    // FIFO batch lookup indexes (v10045) — FIFO consumption hot path:
    //   ORDER BY expiry_date ASC NULLS LAST, received_date ASC
    // filtered by product+variant+is_active+remaining_quantity>0.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_product_batches_fifo '
      'ON product_batches(product_id, variant_id, is_active, remaining_quantity, '
      'expiry_date, received_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_product_batches_purchase_item '
      'ON product_batches(purchase_item_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_batch_consumptions_batch '
      'ON batch_consumptions(batch_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_batch_consumptions_sale_item '
      'ON batch_consumptions(sale_item_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_batch_consumptions_purchase_return_item '
      'ON batch_consumptions(purchase_return_item_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_batch_consumptions_inventory_adjustment '
      'ON batch_consumptions(inventory_adjustment_id)',
    );

    // Adjustment return indexes
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_return_adj_supplier ON purchase_return_adjustments(supplier_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_return_adj_status ON purchase_return_adjustments(status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_return_adj_date ON purchase_return_adjustments(return_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_return_adj_items_return ON purchase_return_adjustment_items(return_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_return_adj_customer ON sale_return_adjustments(customer_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_return_adj_status ON sale_return_adjustments(status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_return_adj_date ON sale_return_adjustments(return_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_return_adj_items_return ON sale_return_adjustment_items(return_id)',
    );

    // Owner-finance and fixed-asset sub-ledger indexes (v10061).
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_owner_finance_date_status '
      'ON owner_finance_transactions(transaction_date, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_fixed_assets_status_date '
      'ON fixed_assets(status, acquisition_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_fixed_asset_dep_asset_status_period '
      'ON fixed_asset_depreciations(asset_id, status, period_end)',
    );
  }

  /// Defense-in-depth DB-level guards on `product_batches` (Phase I, I3).
  ///
  /// SQLite does not allow `ALTER TABLE ADD CHECK`, so we install equivalent
  /// `BEFORE INSERT/UPDATE` triggers that `RAISE(ABORT, ...)` whenever an
  /// invariant is violated. This is a fail-loud safety net layered *below*
  /// the optimistic-lock guarantees in `BatchService`: any future write path
  /// that bypasses the service is rejected at the DB layer.
  ///
  /// Invariants enforced (mirrors INVENTORY_ARCHITECTURE.md §6):
  ///   • I-DB-1: `remaining_quantity >= 0`
  ///   • I-DB-2: `remaining_quantity <= received_quantity`
  ///
  /// Idempotent: every CREATE TRIGGER uses IF NOT EXISTS.
  @visibleForTesting
  Future<void> installProductBatchesIntegrityTriggersForTest() =>
      _installProductBatchesIntegrityTriggers();

  Future<void> _installProductBatchesIntegrityTriggers() async {
    // I-DB-1: remaining_quantity must never be negative.
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_product_batches_remaining_nonneg_insert
      BEFORE INSERT ON product_batches
      FOR EACH ROW
      WHEN NEW.remaining_quantity < 0
      BEGIN
        SELECT RAISE(ABORT,
          'product_batches.remaining_quantity must be >= 0 (insert)');
      END;
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_product_batches_remaining_nonneg_update
      BEFORE UPDATE OF remaining_quantity ON product_batches
      FOR EACH ROW
      WHEN NEW.remaining_quantity < 0
      BEGIN
        SELECT RAISE(ABORT,
          'product_batches.remaining_quantity must be >= 0 (update)');
      END;
    ''');

    // I-DB-2: remaining_quantity must never exceed received_quantity. This
    // catches both restoration overflows (returns restoring more than was
    // consumed) and any future bug that fabricates extra units.
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_product_batches_remaining_le_received_insert
      BEFORE INSERT ON product_batches
      FOR EACH ROW
      WHEN NEW.remaining_quantity > NEW.received_quantity
      BEGIN
        SELECT RAISE(ABORT,
          'product_batches.remaining_quantity must be <= received_quantity (insert)');
      END;
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_product_batches_remaining_le_received_update
      BEFORE UPDATE ON product_batches
      FOR EACH ROW
      WHEN NEW.remaining_quantity > NEW.received_quantity
      BEGIN
        SELECT RAISE(ABORT,
          'product_batches.remaining_quantity must be <= received_quantity (update)');
      END;
    ''');
  }

  Future<void> _seedInitialData() async {
    Future<void> upsertCurrency({
      required String code,
      required String name,
      required String symbol,
      required Decimal exchangeRate,
      bool? isBase,
    }) async {
      final updated =
          await (update(currencies)..where((c) => c.code.equals(code))).write(
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
      final updated =
          await (update(
            accounts,
          )..where((a) => a.accountCode.equals(accountCode))).write(
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
      final updated =
          await (update(appSettings)..where((s) => s.key.equals(key))).write(
            AppSettingsCompanion(
              value: Value(value),
              description: description == null
                  ? const Value.absent()
                  : Value(description),
            ),
          );

      if (updated == 0) {
        await into(appSettings).insert(
          AppSettingsCompanion.insert(
            key: key,
            value: value,
            description: description == null
                ? const Value.absent()
                : Value(description),
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

    final usd = await (select(
      currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
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

    // ── Assets (1xxx) ──────────────────────────────────────
    await upsertAccount(
      accountCode: '1000',
      accountName: 'Cash',
      accountType: 'asset',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '1010',
      accountName: 'Bank',
      accountType: 'asset',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '1100',
      accountName: 'Accounts Receivable',
      accountType: 'asset',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '1200',
      accountName: 'Inventory',
      accountType: 'asset',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '1300',
      accountName: 'VAT Receivable',
      accountType: 'asset',
      currencyId: usdId,
    );

    // ── Liabilities (2xxx) ───────────────────────────────
    await upsertAccount(
      accountCode: '2000',
      accountName: 'Accounts Payable',
      accountType: 'liability',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '2100',
      accountName: 'VAT Payable',
      accountType: 'liability',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '2300',
      accountName: 'Loyalty Points Liability',
      accountType: 'liability',
      currencyId: usdId,
    );

    // ── Equity (3xxx) ────────────────────────────────────
    await upsertAccount(
      accountCode: '3000',
      accountName: 'Owner Capital',
      accountType: 'equity',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '3100',
      accountName: 'Opening Balance Equity',
      accountType: 'equity',
      currencyId: usdId,
    );

    // ── Income (4xxx) ────────────────────────────────────
    await upsertAccount(
      accountCode: '4000',
      accountName: 'Sales Revenue',
      accountType: 'revenue',
      currencyId: usdId,
    );

    // ── Expenses (5xxx) ──────────────────────────────────
    await upsertAccount(
      accountCode: '5100',
      accountName: 'Expenses',
      accountType: 'expense',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '5200',
      accountName: 'Salaries Expense',
      accountType: 'expense',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '5500',
      accountName: 'Discounts Given',
      accountType: 'expense',
      currencyId: usdId,
    );

    await upsertAccount(
      accountCode: '5600',
      accountName: 'Commissions Expense',
      accountType: 'expense',
      currencyId: usdId,
    );

    // 4100 is a CONTRA-EXPENSE: classified as `expense` so its credit
    // balance automatically reduces gross COGS on the income statement
    // (IFRS/GAAP "Net Cost of Sales" presentation).
    await upsertAccount(
      accountCode: '4100',
      accountName: 'Purchase Return Adjustment',
      accountType: 'expense',
      currencyId: usdId,
    );

    // 5700 is a CONTRA-REVENUE: classified as `revenue` so its debit
    // balance automatically reduces gross Sales on the income statement
    // (IFRS/GAAP "Net Sales" presentation).
    await upsertAccount(
      accountCode: '5700',
      accountName: 'Sales Return Adjustment',
      accountType: 'revenue',
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

    // Seed the global inventory valuation method for fresh installs.
    // Mirrors the migration 10047 default. WAC is the IFRS-friendliest
    // safe default for SMBs and matches Xero / QuickBooks (UK/AU).
    // Re-runs are idempotent (upsertSetting only writes once per key).
    await upsertSetting(
      key: 'inventory_valuation_method',
      value: 'wac',
      description:
          'Business-wide inventory valuation method (IAS 2 / ASC 330). '
          "Allowed values: 'wac' | 'fifo'.",
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
      await _seedDefaultLoyaltySettings();
    } catch (e, st) {
      debugPrint('DB seed skipped (default loyalty settings): $e');
      debugPrint('$st');
    }
    try {
      await _seedDefaultRoles();
    } catch (e, st) {
      debugPrint('DB seed skipped (default roles): $e');
      debugPrint('$st');
    }

    // Phase 3 — normalised reason codes + default approval settings.
    // Both are safe to re-run (UPSERT-style guards).
    try {
      await _seedReturnReasonCodes();
    } catch (e, st) {
      debugPrint('DB seed skipped (return reason codes): $e');
      debugPrint('$st');
    }

    // Default approval policy — threshold=0 (disabled), approval required
    // when no original invoice is present (the strongest defense), and
    // required when an operator uses the `allowOverHistory` override.
    // Operators may raise the threshold or soften the no-invoice rule via
    // the settings UI; defaults match the conservative world-class
    // baseline (QB Online, Xero, Odoo).
    await upsertSetting(
      key: 'return_approval_threshold_cents',
      value: '0',
      description:
          'Amount (in cents) at/above which a return requires '
          'manager approval before posting. 0 disables the threshold rule.',
    );
    await upsertSetting(
      key: 'require_approval_when_no_invoice',
      value: '1',
      description:
          'When 1, any adjustment return with no original '
          'invoice reference requires manager approval before posting.',
    );
    await upsertSetting(
      key: 'require_approval_on_override',
      value: '1',
      description:
          'When 1, any return posted with `allowOverHistory` '
          '(bypassing the Phase 0 quantity cap) requires manager '
          'approval before posting.',
    );
  }

  /// Phase 3 — seed the canonical return reason codes.
  ///
  /// Idempotent: each row is UPSERTed by `code`. `is_system=1` means the
  /// row is protected from deletion by `ReturnReasonCodeService`. Labels
  /// ship in English + Arabic; other locales read the code and translate
  /// via the app's i18n layer.
  Future<void> _seedReturnReasonCodes() async {
    const seeds = <Map<String, String>>[
      {
        'code': 'DEFECTIVE',
        'label_en': 'Defective / faulty product',
        'label_ar': 'منتج معيب',
        'side': 'both',
      },
      {
        'code': 'WRONG_ITEM',
        'label_en': 'Wrong item delivered',
        'label_ar': 'صنف خاطئ',
        'side': 'both',
      },
      {
        'code': 'CUSTOMER_CHANGED_MIND',
        'label_en': 'Customer changed their mind',
        'label_ar': 'العميل غيّر رأيه',
        'side': 'sale',
      },
      {
        'code': 'DAMAGED_IN_TRANSIT',
        'label_en': 'Damaged in transit',
        'label_ar': 'تلف أثناء النقل',
        'side': 'both',
      },
      {
        'code': 'EXPIRED',
        'label_en': 'Expired goods',
        'label_ar': 'منتج منتهي الصلاحية',
        'side': 'both',
      },
      {
        'code': 'NO_INVOICE',
        'label_en': 'Return without original invoice',
        'label_ar': 'مرتجع بدون فاتورة',
        'side': 'both',
      },
      {
        'code': 'PRICE_ADJUSTMENT',
        'label_en': 'Price adjustment / renegotiation',
        'label_ar': 'تسوية أو إعادة تفاوض سعر',
        'side': 'both',
      },
      {
        'code': 'OTHER',
        'label_en': 'Other',
        'label_ar': 'أخرى',
        'side': 'both',
      },
    ];

    for (final row in seeds) {
      final existing = await customSelect(
        'SELECT id FROM return_reason_codes WHERE code = ?',
        variables: [Variable.withString(row['code']!)],
      ).getSingleOrNull();

      if (existing == null) {
        await customStatement(
          'INSERT INTO return_reason_codes '
          '(code, label_en, label_ar, side, is_active, is_system) '
          'VALUES (?, ?, ?, ?, 1, 1)',
          [row['code']!, row['label_en']!, row['label_ar']!, row['side']!],
        );
      } else {
        // Keep existing user edits but make sure the system flag + labels
        // are in sync with the latest shipping defaults. We DO NOT touch
        // `is_active` — if an admin deactivated a code we respect that.
        await customStatement(
          'UPDATE return_reason_codes SET '
          'label_en = ?, label_ar = ?, side = ?, is_system = 1, '
          'updated_at = CURRENT_TIMESTAMP WHERE code = ?',
          [row['label_en']!, row['label_ar']!, row['side']!, row['code']!],
        );
      }
    }
  }

  Future<void> _seedDefaultColors() async {
    Future<void> upsertColor({required String name, String? hexCode}) async {
      final existing = await (select(
        productColors,
      )..where((c) => c.name.equals(name))).getSingleOrNull();

      if (existing == null) {
        await into(productColors).insert(
          ProductColorsCompanion.insert(name: name, hexCode: Value(hexCode)),
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
      final existing = await (select(
        sizes,
      )..where((s) => s.name.equals(name))).getSingleOrNull();

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
    await upsertSize(
      name: 'Double Extra Large',
      description: 'XXL',
      sortOrder: 6,
    );
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
      final existing = await (select(
        roles,
      )..where((r) => r.name.equals(name))).getSingleOrNull();

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
      permissions:
          '["employees.view","employees.create","employees.edit","employees.delete","employees.manage_permissions","payroll.view","payroll.create","payroll.approve","payroll.process","attendance.view","attendance.manage","attendance.approve","performance.view","performance.manage","reports.view","reports.export","settings.view","settings.manage","system.admin","purchases.view","purchases.create","purchases.edit","purchases.delete","purchases.post","purchases.void","purchases.approve","purchases.returns","purchases.payments"]',
      isSystemRole: true,
    );

    // Manager role - team management + purchase management
    await upsertRole(
      name: 'manager',
      nameAr: 'مدير',
      nameFr: 'Gestionnaire',
      description: 'Team management with limited admin access',
      permissions:
          '["employees.view","employees.edit","attendance.view","attendance.manage","attendance.approve","performance.view","performance.manage","payroll.view","reports.view","reports.team","purchases.view","purchases.create","purchases.edit","purchases.post","purchases.approve","purchases.returns","purchases.payments"]',
      isSystemRole: true,
    );

    // Staff role - basic access + view purchases
    await upsertRole(
      name: 'staff',
      nameAr: 'موظف',
      nameFr: 'Employé',
      description: 'Basic employee access',
      permissions:
          '["profile.view","profile.edit","attendance.view","attendance.self","performance.view","payslip.view","purchases.view"]',
      isSystemRole: true,
    );

    // Cashier role - POS access + view purchases
    await upsertRole(
      name: 'cashier',
      nameAr: 'كاشير',
      nameFr: 'Caissier',
      description: 'Point of sale and basic operations',
      permissions:
          '["profile.view","attendance.view","attendance.self","sales.view","sales.create","products.view","customers.view","purchases.view"]',
      isSystemRole: true,
    );

    // Salesperson role - sales focused
    await upsertRole(
      name: 'salesperson',
      nameAr: 'مندوب مبيعات',
      nameFr: 'Vendeur',
      description: 'Sales operations with commission tracking',
      permissions:
          '["profile.view","attendance.view","attendance.self","sales.view","sales.create","products.view","customers.view","customers.create","performance.view","commission.view","purchases.view"]',
      isSystemRole: true,
    );
  }

  /// Update existing roles with purchase-specific permissions (migration 10017)
  Future<void> _updateRolesWithPurchasePermissions() async {
    // Permission mappings: role name -> purchase permissions to add
    const rolePermissions = <String, List<String>>{
      'admin': [
        'purchases.view',
        'purchases.create',
        'purchases.edit',
        'purchases.delete',
        'purchases.post',
        'purchases.void',
        'purchases.approve',
        'purchases.returns',
        'purchases.payments',
      ],
      'manager': [
        'purchases.view',
        'purchases.create',
        'purchases.edit',
        'purchases.post',
        'purchases.approve',
        'purchases.returns',
        'purchases.payments',
      ],
      'staff': ['purchases.view'],
      'cashier': ['purchases.view'],
      'salesperson': ['purchases.view'],
    };

    for (final entry in rolePermissions.entries) {
      final roleName = entry.key;
      final newPerms = entry.value;

      final role = await (select(
        roles,
      )..where((r) => r.name.equals(roleName))).getSingleOrNull();
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

      await (update(roles)..where((r) => r.name.equals(roleName))).write(
        RolesCompanion(permissions: Value(updatedPerms)),
      );
    }
  }

  Future<void> _seedDefaultLoyaltySettings() async {
    final existing = await select(loyaltySettingsTable).getSingleOrNull();
    if (existing != null) return;

    await customStatement('''
      INSERT INTO loyalty_settings (
        points_per_currency_unit, min_spend_for_points,
        referral_bonus_points, signup_bonus_points, review_bonus_points,
        is_enabled, point_value_cents, min_redemption_points,
        max_redemption_percent_bps, allow_points_redemption,
        created_at, updated_at
      ) VALUES (1, 0, 100, 50, 10, 1, 1, 100, 5000, 1,
        datetime('now'), datetime('now'))
    ''');
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
      final existing = await (select(
        loyaltyTiers,
      )..where((t) => t.name.equals(name))).getSingleOrNull();

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
      final existing = await (select(
        barcodeTemplates,
      )..where((t) => t.name.equals(name))).getSingleOrNull();

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
            includeVariantInfo: const Value(true),
            barcodeType: const Value('auto'),
            isDefault: Value(isDefault),
          ),
        );
      } else if (!existing.includeVariantInfo) {
        await (update(
          barcodeTemplates,
        )..where((t) => t.id.equals(existing.id))).write(
          const BarcodeTemplatesCompanion(includeVariantInfo: Value(true)),
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

  /// Seed default Chart of Accounts (idempotent).
  /// These accounts are required by JournalEntryService for posting transactions.
  Future<void> _seedDefaultAccounts() async {
    final now = DateTime.now();

    // Get default currency
    final defaultCurrencyRow = await (select(
      currencies,
    )..limit(1)).getSingleOrNull();
    if (defaultCurrencyRow == null) {
      debugPrint('No currency found, skipping default accounts seed');
      return;
    }
    final currencyId = defaultCurrencyRow.id;

    // STRICT Chart of Accounts — matches JournalEntryService requirements
    final defaultAccounts = <Map<String, dynamic>>[
      // ── Assets (1xxx) ──
      {
        'code': '1000',
        'name': 'Cash',
        'type': 'asset',
        'system': true,
        'order': 1,
      },
      {
        'code': '1010',
        'name': 'Bank',
        'type': 'asset',
        'system': true,
        'order': 2,
      },
      {
        'code': '1100',
        'name': 'Accounts Receivable',
        'type': 'asset',
        'system': true,
        'order': 3,
      },
      {
        'code': '1200',
        'name': 'Inventory',
        'type': 'asset',
        'system': true,
        'order': 4,
      },
      // 1290 Returns in Transit — asset-class clearing account for the
      // `send_back` disposition on purchase returns. Goods have physically
      // left but the supplier credit memo is still pending; inventory
      // value parks here until reconciled. See seedDefaultAccounts doc.
      {
        'code': '1290',
        'name': 'Returns in Transit',
        'type': 'asset',
        'system': true,
        'order': 6,
      },
      {
        'code': '1300',
        'name': 'VAT Receivable',
        'type': 'asset',
        'system': true,
        'order': 7,
      },
      {
        'code': '1500',
        'name': 'Fixed Assets',
        'type': 'asset',
        'system': true,
        'order': 8,
      },
      {
        'code': '1510',
        'name': 'Furniture and Fixtures',
        'type': 'asset',
        'system': true,
        'order': 9,
      },
      {
        'code': '1520',
        'name': 'Equipment and Air Conditioners',
        'type': 'asset',
        'system': true,
        'order': 10,
      },
      {
        'code': '1590',
        'name': 'Accumulated Depreciation',
        'type': 'asset',
        'system': true,
        'order': 11,
      },
      // ── Liabilities (2xxx) ──
      {
        'code': '2000',
        'name': 'Accounts Payable',
        'type': 'liability',
        'system': true,
        'order': 10,
      },
      {
        'code': '2100',
        'name': 'VAT Payable',
        'type': 'liability',
        'system': true,
        'order': 11,
      },
      {
        'code': '2200',
        'name': 'Owner Loan Payable',
        'type': 'liability',
        'system': true,
        'order': 12,
      },
      {
        'code': '2300',
        'name': 'Loyalty Points Liability',
        'type': 'liability',
        'system': true,
        'order': 12,
      },
      // 2400 Customer Credit Liability — holds on-account refunds for
      // unlinked sale returns (returns without an original invoice).
      // Keeps 1100 AR clean and prevents orphaned negative-AR balances.
      {
        'code': '2400',
        'name': 'Customer Credit Liability',
        'type': 'liability',
        'system': true,
        'order': 13,
      },
      // ── Equity (3xxx) ──
      {
        'code': '3000',
        'name': 'Owner Capital',
        'type': 'equity',
        'system': true,
        'order': 20,
      },
      {
        'code': '3100',
        'name': 'Opening Balance Equity',
        'type': 'equity',
        'system': true,
        'order': 21,
      },
      {
        'code': '3200',
        'name': 'Owner Drawings',
        'type': 'equity',
        'system': true,
        'order': 22,
      },
      // ── Income (4xxx) ──
      {
        'code': '4000',
        'name': 'Sales Revenue',
        'type': 'revenue',
        'system': true,
        'order': 30,
      },
      // 5700 Sales Return Adjustment is a CONTRA-REVENUE account: classified
      // as `revenue` so its debit balance auto-reduces gross sales on the
      // income statement (IFRS/GAAP "Net Sales" presentation).
      {
        'code': '5700',
        'name': 'Sales Return Adjustment',
        'type': 'revenue',
        'system': true,
        'order': 33,
      },
      {
        'code': '4200',
        'name': 'Inventory Gain',
        'type': 'revenue',
        'system': true,
        'order': 32,
      },
      // 4900 Purchase Discounts Earned — revenue / "other income" account
      // for after-the-fact, unallocated supplier discounts recorded from
      // the supplier profile screen (transaction_type='discount'). The
      // historical posting was Dr AP / Cr Inventory which silently credited
      // Inventory without any matching stock-side movement, producing a
      // permanent GL ↔ Σ(stock×cost) drift. Routing the credit here keeps
      // Inventory equal to the on-hand carrying value and recognises the
      // discount as income in the period received (IFRS/GAAP treatment of
      // unallocated supplier rebates that cannot be allocated back to
      // specific PO lines without a landed-cost recalculation).
      {
        'code': '4900',
        'name': 'Purchase Discounts Earned',
        'type': 'revenue',
        'system': true,
        'order': 34,
      },
      // ── Expenses (5xxx) ──
      // 4100 Purchase Return Adjustment is a CONTRA-EXPENSE account:
      // classified as `expense` so its credit balance auto-reduces gross
      // COGS on the income statement (IFRS/GAAP "Net Cost of Sales").
      {
        'code': '4100',
        'name': 'Purchase Return Adjustment',
        'type': 'expense',
        'system': true,
        'order': 40,
      },
      {
        'code': '5100',
        'name': 'Expenses',
        'type': 'expense',
        'system': true,
        'order': 41,
      },
      {
        'code': '5200',
        'name': 'Salaries Expense',
        'type': 'expense',
        'system': true,
        'order': 42,
      },
      {
        'code': '5300',
        'name': 'Cost of Goods Sold',
        'type': 'expense',
        'system': true,
        'order': 43,
      },
      {
        'code': '5500',
        'name': 'Discounts Given',
        'type': 'expense',
        'system': true,
        'order': 44,
      },
      {
        'code': '5600',
        'name': 'Commissions Expense',
        'type': 'expense',
        'system': true,
        'order': 45,
      },
      {
        'code': '5800',
        'name': 'Inventory Shrinkage',
        'type': 'expense',
        'system': true,
        'order': 47,
      },
      {
        'code': '5900',
        'name': 'Inventory Revaluation',
        'type': 'expense',
        'system': true,
        'order': 48,
      },
      {
        'code': '6100',
        'name': 'Depreciation Expense',
        'type': 'expense',
        'system': true,
        'order': 49,
      },
    ];

    // Idempotent and self-healing: legacy databases may already contain the
    // required codes but with is_system_account=false (older seed versions).
    // Repair immutable metadata on every open so posting accounts cannot be
    // edited, deactivated or deleted from the Chart of Accounts screen.
    for (final acct in defaultAccounts) {
      final code = acct['code'] as String;
      final existing = await (select(
        accounts,
      )..where((a) => a.accountCode.equals(code))).getSingleOrNull();
      if (existing != null) {
        final expectedType = acct['type'] as String;
        final expectedOrder = acct['order'] as int;
        if (!existing.isSystemAccount ||
            !existing.isActive ||
            existing.accountType != expectedType ||
            existing.displayOrder != expectedOrder) {
          await (update(
            accounts,
          )..where((a) => a.id.equals(existing.id))).write(
            AccountsCompanion(
              accountType: Value(expectedType),
              isSystemAccount: const Value(true),
              isActive: const Value(true),
              displayOrder: Value(expectedOrder),
              updatedAt: Value(now),
            ),
          );
        }
        continue;
      }

      await into(accounts).insert(
        AccountsCompanion(
          accountCode: Value(code),
          accountName: Value(acct['name'] as String),
          accountType: Value(acct['type'] as String),
          currencyId: Value(currencyId),
          isSystemAccount: Value(acct['system'] as bool),
          displayOrder: Value(acct['order'] as int),
          isActive: const Value(true),
          balanceCents: Value(Decimal.zero),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }
  }

  @visibleForTesting
  Future<void> seedDefaultAccountsForTest() => _seedDefaultAccounts();
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    return openDatabase();
  });
}
