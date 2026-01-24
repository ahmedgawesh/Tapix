# TAPIX ERP - Technical Inventory (Detailed)

> **Companion Document to**: TAPIX_REBUILD_SPECIFICATION.md  
> **Purpose**: Exhaustive technical details for implementation  
> **Status**: REFERENCE - Use alongside main specification

---

## TABLE OF CONTENTS

1. [Database Tables (Complete Schema)](#1-database-tables-complete-schema)
2. [Providers Inventory](#2-providers-inventory)
3. [Models Inventory](#3-models-inventory)
4. [Financial Calculation Rules](#4-financial-calculation-rules)
5. [Widgets Inventory](#5-widgets-inventory)
6. [Localization Keys](#6-localization-keys)
7. [PDF Templates](#7-pdf-templates)
8. [Navigation Structure](#8-navigation-structure)

---

## 1. DATABASE TABLES (COMPLETE SCHEMA)

### 1.1 User & Auth Tables

#### `users`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key, auto-increment |
| username | TEXT | NO | Unique username |
| password_hash | TEXT | NO | Hashed password |
| role | TEXT | NO | owner/manager/cashier/salesperson |
| employee_id | INTEGER | YES | FK to employees |
| is_active | INTEGER | NO | 1=active, 0=inactive |
| created_at | INTEGER | NO | Timestamp (ms) |
| updated_at | INTEGER | NO | Timestamp (ms) |
| last_login_at | INTEGER | YES | Last login timestamp |

### 1.2 Product Tables

#### `products`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Product name |
| name_ar | TEXT | YES | Arabic name |
| name_fr | TEXT | YES | French name |
| sku | TEXT | YES | Stock keeping unit |
| barcode | TEXT | YES | Barcode value |
| category_id | INTEGER | YES | FK to product_categories |
| cost_cents | INTEGER | NO | Cost price in cents |
| price_cents | INTEGER | NO | Selling price in cents |
| wholesale_price_cents | INTEGER | YES | Wholesale price |
| quantity | INTEGER | NO | Current stock |
| min_quantity | INTEGER | NO | Minimum stock alert |
| is_active | INTEGER | NO | 1=active |
| is_taxable | INTEGER | NO | 1=taxable |
| tax_rate_bps | INTEGER | NO | Tax rate in basis points |
| image_path | TEXT | YES | Product image |
| description | TEXT | YES | Description |
| currency_id | INTEGER | YES | FK to currencies |
| supplier_id | INTEGER | YES | Default supplier |
| created_at | INTEGER | NO | Timestamp |
| updated_at | INTEGER | NO | Timestamp |

#### `product_variants`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| product_id | INTEGER | NO | FK to products |
| color_id | INTEGER | YES | FK to product_colors |
| size_id | INTEGER | YES | FK to sizes |
| sku | TEXT | YES | Variant SKU |
| barcode | TEXT | YES | Variant barcode |
| quantity | INTEGER | NO | Stock for this variant |
| price_adjustment_cents | INTEGER | NO | Price +/- from base |
| is_active | INTEGER | NO | 1=active |

#### `product_categories`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Category name |
| name_ar | TEXT | YES | Arabic name |
| name_fr | TEXT | YES | French name |
| parent_id | INTEGER | YES | FK to self (hierarchy) |
| is_active | INTEGER | NO | 1=active |

#### `product_colors`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Color name |
| hex_code | TEXT | YES | Hex color code |
| is_active | INTEGER | NO | 1=active |

#### `sizes`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Size name |
| sort_order | INTEGER | NO | Display order |
| is_active | INTEGER | NO | 1=active |

#### `product_batches`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| product_id | INTEGER | NO | FK to products |
| batch_number | TEXT | NO | Batch identifier |
| quantity | INTEGER | NO | Quantity in batch |
| cost_cents | INTEGER | NO | Cost for this batch |
| expiry_date | INTEGER | YES | Expiry timestamp |
| purchase_id | INTEGER | YES | FK to purchases |
| created_at | INTEGER | NO | Timestamp |

### 1.3 Customer Tables

#### `customers`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Customer name |
| phone | TEXT | YES | Phone number |
| email | TEXT | YES | Email |
| address | TEXT | YES | Address |
| tax_id | TEXT | YES | Tax identification |
| credit_limit_cents | INTEGER | NO | Credit limit |
| balance_cents | INTEGER | NO | Current balance (positive=owes us) |
| notes | TEXT | YES | Notes |
| is_active | INTEGER | NO | 1=active |
| currency_id | INTEGER | YES | FK to currencies |
| created_at | INTEGER | NO | Timestamp |
| updated_at | INTEGER | NO | Timestamp |

#### `customer_transactions` (Ledger)
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| customer_id | INTEGER | NO | FK to customers |
| transaction_type | TEXT | NO | sale/payment/return/adjustment |
| reference_id | INTEGER | YES | FK to source (sale_id, etc.) |
| amount_cents | INTEGER | NO | Transaction amount |
| currency_id | INTEGER | YES | FK to currencies |
| balance_after_cents | INTEGER | NO | Balance after this transaction |
| notes | TEXT | YES | Notes |
| request_id | TEXT | YES | Idempotency key |
| created_at | INTEGER | NO | Timestamp |

### 1.4 Supplier Tables

#### `suppliers`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Supplier name |
| contact_person | TEXT | YES | Contact person |
| phone | TEXT | YES | Phone |
| email | TEXT | YES | Email |
| address | TEXT | YES | Address |
| tax_id | TEXT | YES | Tax ID |
| balance_cents | INTEGER | NO | Current balance (positive=we owe them) |
| payment_terms | TEXT | YES | Payment terms |
| notes | TEXT | YES | Notes |
| is_active | INTEGER | NO | 1=active |
| currency_id | INTEGER | YES | FK to currencies |
| created_at | INTEGER | NO | Timestamp |
| updated_at | INTEGER | NO | Timestamp |

#### `supplier_transactions` (Ledger)
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| supplier_id | INTEGER | NO | FK to suppliers |
| transaction_type | TEXT | NO | purchase/payment/return/adjustment |
| reference_id | INTEGER | YES | FK to source |
| amount_cents | INTEGER | NO | Transaction amount |
| currency_id | INTEGER | YES | FK to currencies |
| balance_after_cents | INTEGER | NO | Balance after |
| notes | TEXT | YES | Notes |
| created_at | INTEGER | NO | Timestamp |

### 1.5 Sales Tables

#### `sales`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| invoice_number | TEXT | NO | Unique invoice number |
| customer_id | INTEGER | YES | FK to customers (nullable for cash) |
| employee_id | INTEGER | YES | FK to employees (salesperson) |
| sale_date | INTEGER | NO | Sale date timestamp |
| subtotal_cents | INTEGER | NO | Sum of line items before discount |
| discount_amount_cents | INTEGER | NO | Invoice-level discount |
| discount_type | TEXT | YES | 'percentage' or 'fixed' |
| discount_percentage | REAL | YES | Discount percentage if applicable |
| tax_amount_cents | INTEGER | NO | Total tax |
| total_amount_cents | INTEGER | NO | Grand total |
| paid_amount_cents | INTEGER | NO | Amount paid |
| change_amount_cents | INTEGER | NO | Change given |
| overpayment_cents | INTEGER | NO | Overpayment credited |
| payment_method | TEXT | NO | cash/card/bank/credit/split |
| status | TEXT | NO | pending/confirmed/voided |
| notes | TEXT | YES | Notes |
| currency_id | INTEGER | YES | FK to currencies |
| total_items | INTEGER | NO | Total item count |
| discount_timing | TEXT | YES | before_tax/after_tax |
| tax_calculation_base | TEXT | YES | on_subtotal/on_net |
| created_at | INTEGER | NO | Timestamp |
| updated_at | INTEGER | NO | Timestamp |

#### `sale_items`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| sale_id | INTEGER | NO | FK to sales |
| product_id | INTEGER | NO | FK to products |
| variant_id | INTEGER | YES | FK to product_variants |
| quantity | INTEGER | NO | Quantity sold |
| unit_price_cents | INTEGER | NO | Price per unit |
| cost_cents | INTEGER | NO | Cost at time of sale |
| discount_cents | INTEGER | NO | Line discount amount |
| discount_type | TEXT | YES | percentage/fixed |
| discount_percentage | REAL | YES | Discount % |
| tax_cents | INTEGER | NO | Line tax |
| tax_rate_bps | INTEGER | YES | Tax rate in basis points |
| total_cents | INTEGER | NO | Line total |
| notes | TEXT | YES | Line notes |

#### `sale_tax_bands`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| sale_id | INTEGER | NO | FK to sales |
| tax_rate_bps | INTEGER | NO | Tax rate (basis points) |
| tax_cents | INTEGER | NO | Tax amount for this band |

### 1.6 Sale Returns Tables

#### `sale_returns`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| return_number | TEXT | NO | Unique return number |
| sale_id | INTEGER | YES | FK to original sale (optional) |
| customer_id | INTEGER | YES | FK to customers |
| return_date | INTEGER | NO | Return date |
| subtotal_cents | INTEGER | NO | Subtotal |
| tax_amount_cents | INTEGER | NO | Tax |
| total_amount_cents | INTEGER | NO | Total |
| refund_method | TEXT | NO | cash/credit |
| refund_amount_cents | INTEGER | NO | Amount refunded |
| credit_to_account_cents | INTEGER | NO | Amount credited to customer |
| reason | TEXT | YES | Return reason |
| status | TEXT | NO | pending/confirmed/voided |
| notes | TEXT | YES | Notes |
| currency_id | INTEGER | YES | FK to currencies |
| created_at | INTEGER | NO | Timestamp |
| updated_at | INTEGER | NO | Timestamp |

#### `sale_return_items`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| sale_return_id | INTEGER | NO | FK to sale_returns |
| product_id | INTEGER | NO | FK to products |
| variant_id | INTEGER | YES | FK to product_variants |
| sale_item_id | INTEGER | YES | FK to original sale_item |
| quantity | INTEGER | NO | Quantity returned |
| unit_price_cents | INTEGER | NO | Price per unit |
| total_cents | INTEGER | NO | Line total |
| reason | TEXT | YES | Item-level reason |

### 1.7 Purchase Tables

#### `purchases`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| invoice_number | TEXT | NO | Supplier invoice number |
| supplier_id | INTEGER | NO | FK to suppliers |
| purchase_date | INTEGER | NO | Purchase date |
| subtotal_cents | INTEGER | NO | Subtotal |
| discount_amount_cents | INTEGER | NO | Discount |
| tax_amount_cents | INTEGER | NO | Tax |
| total_amount_cents | INTEGER | NO | Total |
| paid_amount_cents | INTEGER | NO | Amount paid |
| payment_method | TEXT | YES | Payment method |
| status | TEXT | NO | pending/confirmed/voided |
| notes | TEXT | YES | Notes |
| currency_id | INTEGER | YES | FK to currencies |
| discount_timing | TEXT | YES | before_tax/after_tax |
| tax_calculation_base | TEXT | YES | on_subtotal/on_net |
| created_at | INTEGER | NO | Timestamp |
| updated_at | INTEGER | NO | Timestamp |

#### `purchase_items`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| purchase_id | INTEGER | NO | FK to purchases |
| product_id | INTEGER | NO | FK to products |
| variant_id | INTEGER | YES | FK to product_variants |
| quantity | INTEGER | NO | Quantity purchased |
| unit_cost_cents | INTEGER | NO | Cost per unit |
| discount_cents | INTEGER | NO | Line discount |
| tax_cents | INTEGER | NO | Line tax |
| total_cents | INTEGER | NO | Line total |

### 1.8 Purchase Returns Tables

#### `purchase_returns`
Similar structure to `sale_returns` but for supplier returns.

#### `purchase_return_items`
Similar structure to `sale_return_items`.

### 1.9 Employee Tables

#### `employees`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Full name |
| position | TEXT | YES | Job title |
| phone | TEXT | YES | Phone |
| email | TEXT | YES | Email |
| hire_date | INTEGER | YES | Hire date |
| salary_cents | INTEGER | YES | Salary |
| commission_rate_bps | INTEGER | NO | Commission % in basis points |
| monthly_target_cents | INTEGER | YES | Monthly sales target |
| is_active | INTEGER | NO | 1=active |
| created_at | INTEGER | NO | Timestamp |
| updated_at | INTEGER | NO | Timestamp |

#### `commissions`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| employee_id | INTEGER | NO | FK to employees |
| sale_id | INTEGER | NO | FK to sales |
| sale_amount_cents | INTEGER | NO | Sale total |
| commission_rate_bps | INTEGER | NO | Rate applied |
| commission_cents | INTEGER | NO | Commission earned |
| status | TEXT | NO | pending/paid |
| paid_date | INTEGER | YES | When paid |
| created_at | INTEGER | NO | Timestamp |

### 1.10 Expense Tables

#### `expenses`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| category_id | INTEGER | NO | FK to expense_categories |
| amount_cents | INTEGER | NO | Amount |
| expense_date | INTEGER | NO | Date |
| description | TEXT | YES | Description |
| payment_method | TEXT | YES | Payment method |
| receipt_path | TEXT | YES | Receipt image path |
| is_recurring | INTEGER | NO | 1=recurring |
| currency_id | INTEGER | YES | FK to currencies |
| created_at | INTEGER | NO | Timestamp |

#### `expense_categories`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Category name |
| is_active | INTEGER | NO | 1=active |

### 1.11 Accounting Tables

#### `accounts` (Chart of Accounts)
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| code | TEXT | NO | Account code (e.g., 1000) |
| name | TEXT | NO | Account name |
| type | TEXT | NO | asset/liability/equity/revenue/expense |
| parent_id | INTEGER | YES | FK to self (hierarchy) |
| is_system | INTEGER | NO | 1=system account (no delete) |
| is_active | INTEGER | NO | 1=active |
| normal_balance | TEXT | NO | debit/credit |
| currency_id | INTEGER | YES | FK to currencies |

#### `journal_entries`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| entry_number | TEXT | NO | Unique entry number |
| entry_date | INTEGER | NO | Entry date |
| description | TEXT | NO | Entry description |
| reference_type | TEXT | YES | sale/purchase/payment/manual |
| reference_id | INTEGER | YES | FK to source document |
| is_auto_generated | INTEGER | NO | 1=system generated |
| is_posted | INTEGER | NO | 1=posted |
| period_id | INTEGER | YES | FK to accounting_periods |
| created_at | INTEGER | NO | Timestamp |
| created_by | INTEGER | YES | FK to users |

#### `journal_entry_lines`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| journal_entry_id | INTEGER | NO | FK to journal_entries |
| account_id | INTEGER | NO | FK to accounts |
| debit_cents | INTEGER | NO | Debit amount |
| credit_cents | INTEGER | NO | Credit amount |
| description | TEXT | YES | Line description |
| currency_id | INTEGER | YES | FK to currencies |

#### `accounting_periods`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| name | TEXT | NO | Period name (e.g., "January 2026") |
| start_date | INTEGER | NO | Period start |
| end_date | INTEGER | NO | Period end |
| is_closed | INTEGER | NO | 1=closed |
| closed_at | INTEGER | YES | When closed |
| closed_by | INTEGER | YES | FK to users |

### 1.12 Settings Tables

#### `app_settings`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| key | TEXT | NO | Setting key |
| value | TEXT | YES | Setting value |
| updated_at | INTEGER | NO | Timestamp |

#### `store_logos`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| file_path | TEXT | NO | Logo file path |
| is_active | INTEGER | NO | 1=current logo |
| created_at | INTEGER | NO | Timestamp |

#### `currencies`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| code | TEXT | NO | ISO code (SAR, USD, EUR) |
| name | TEXT | NO | Currency name |
| symbol | TEXT | NO | Symbol (ر.س, $, €) |
| symbol_position | TEXT | NO | before/after |
| decimal_places | INTEGER | NO | Decimal digits |
| is_default | INTEGER | NO | 1=default currency |
| exchange_rate | REAL | NO | Rate to base currency |
| is_active | INTEGER | NO | 1=active |

### 1.13 Audit Tables

#### `audit_log`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| user_id | INTEGER | YES | FK to users |
| action | TEXT | NO | Action performed |
| table_name | TEXT | NO | Affected table |
| record_id | INTEGER | YES | Affected record ID |
| old_values | TEXT | YES | JSON of old values |
| new_values | TEXT | YES | JSON of new values |
| ip_address | TEXT | YES | IP if applicable |
| created_at | INTEGER | NO | Timestamp |

#### `void_logs`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| document_type | TEXT | NO | sale/purchase/return |
| document_id | INTEGER | NO | FK to document |
| document_number | TEXT | NO | Document number |
| original_total_cents | INTEGER | NO | Original total |
| void_reason | TEXT | YES | Reason for void |
| voided_by | INTEGER | NO | FK to users |
| voided_at | INTEGER | NO | Timestamp |

#### `notifications`
| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key |
| type | TEXT | NO | low_stock/payment_due/etc |
| title | TEXT | NO | Notification title |
| message | TEXT | NO | Notification body |
| reference_type | TEXT | YES | Related entity type |
| reference_id | INTEGER | YES | Related entity ID |
| is_read | INTEGER | NO | 1=read |
| created_at | INTEGER | NO | Timestamp |

---

## 2. PROVIDERS INVENTORY

### 2.1 Sales Providers

| Provider | File | Purpose |
|----------|------|---------|
| `salesProvider` | sales_provider.dart | Basic sales operations |
| `paginatedSalesProvider` | paginated_sales_provider.dart | Paginated sales list |
| `reactiveSalesProvider` | reactive_sales_provider.dart | Real-time sales stream |
| `saleReturnsProvider` | sale_returns_provider.dart | Sale returns operations |
| `saleReturnFormProvider` | sale_return_form_provider.dart | Return form state |

### 2.2 Purchase Providers

| Provider | File | Purpose |
|----------|------|---------|
| `purchasesProvider` | purchases_provider.dart | Purchase operations |
| `purchaseReturnsProvider` | purchase_returns_provider.dart | Purchase returns |
| `deletedPurchasesProvider` | deleted_purchases_provider.dart | Deleted purchases audit |

### 2.3 Product Providers

| Provider | File | Purpose |
|----------|------|---------|
| `productsProvider` | products_provider.dart | Product operations |
| `paginatedProductsProvider` | paginated_products_provider.dart | Paginated product list |
| `productBatchesProvider` | product_batches_provider.dart | Batch management |
| `colorsProvider` | colors_provider.dart | Color management |
| `sizesProvider` | sizes_provider.dart | Size management |

### 2.4 Report Providers

| Provider | File | Purpose |
|----------|------|---------|
| `customerReportsProvider` | customer_reports_provider.dart | All customer reports |
| `supplierReportsProvider` | supplier_reports_provider.dart | All supplier reports |
| `inventoryReportsProvider` | inventory_reports_provider.dart | Inventory reports |
| `profitLossReportsProvider` | profit_loss_reports_provider.dart | P&L report |
| `balanceSheetReportsProvider` | balance_sheet_reports_provider.dart | Balance sheet |
| `trialBalanceReportsProvider` | trial_balance_reports_provider.dart | Trial balance |
| `generalLedgerReportsProvider` | general_ledger_reports_provider.dart | General ledger |
| `cashFlowReportsProvider` | cash_flow_reports_provider.dart | Cash flow |
| `taxReportsProvider` | tax_reports_provider.dart | Tax report |
| `expenseReportsProvider` | expense_reports_provider.dart | Expense report |
| `salesSummaryReportsProvider` | sales_summary_reports_provider.dart | Sales summary |
| `salespeopleReportsProvider` | salespeople_reports_provider.dart | Salespeople performance |
| `productMovementReportsProvider` | product_movement_reports_provider.dart | Stock movements |
| `voidLogsProvider` | void_logs_provider.dart | Void logs |
| `reconciliationDiagnosticsProvider` | reconciliation_diagnostics_provider.dart | Data checks |
| `supplierBalanceBreakdownProvider` | supplier_balance_breakdown_provider.dart | Balance drilldown |
| `paginatedAuditLogProvider` | paginated_audit_log_provider.dart | Audit log |

---

## 3. MODELS INVENTORY

### 3.1 Sales Models

| Model | File | Purpose |
|-------|------|---------|
| `SaleItemModel` | sale_item_model.dart | Sale line item DTO |
| `SaleReturnItemModel` | sale_return_item_model.dart | Return line item DTO |
| `CommissionDeductionModel` | commission_deduction_model.dart | Commission calculation |

### 3.2 Report Models

| Model | File | Purpose |
|-------|------|---------|
| `CustomerAgingModel` | customer_aging_model.dart | Aging buckets (0-30, 31-60, etc.) |
| `CustomerAnalysisModel` | customer_analysis_model.dart | Customer analytics |
| `CustomerPaymentModel` | customer_payment_model.dart | Payment history |
| `CustomerSalesModel` | customer_sales_model.dart | Sales by customer |
| `CustomerSalesReturnModel` | customer_sales_return_model.dart | Returns by customer |
| `CustomerStatementModel` | customer_statement_model.dart | Account statement |
| `TopCustomersModel` | top_customers_model.dart | Top customers ranking |
| `SupplierAgingModel` | supplier_aging_model.dart | Supplier aging |
| `SupplierAnalysisModel` | supplier_analysis_model.dart | Supplier analytics |
| `SupplierBalanceModel` | supplier_balance_model.dart | Balance details |
| `SupplierStatementModel` | supplier_statement_model.dart | Account statement |
| `SupplierStocktakeModel` | supplier_stocktake_report_model.dart | Stock by supplier |
| `InventoryReportModel` | inventory_report_model.dart | Stock levels |
| `ProductMovementReportModel` | product_movement_report_model.dart | Movement history |
| `CategoryStocktakeReportModel` | category_stocktake_report_model.dart | Stock by category |
| `ProfitLossReportModel` | profit_loss_report_model.dart | P&L data |
| `BalanceSheetReportModel` | balance_sheet_report_model.dart | Balance sheet data |
| `TrialBalanceReportModel` | trial_balance_report_model.dart | Trial balance data |
| `GeneralLedgerReportModel` | general_ledger_report_model.dart | Ledger entries |
| `CashFlowReportModel` | cash_flow_report_model.dart | Cash flow data |
| `TaxReportModel` | tax_report_model.dart | Tax summary |
| `ExpenseReportModel` | expense_report_model.dart | Expense breakdown |
| `SalesSummaryReportModel` | sales_summary_report_model.dart | Sales summary |
| `SalespeopleReportModel` | salespeople_report_model.dart | Salespeople metrics |

---

## 4. FINANCIAL CALCULATION RULES

### 4.1 Core Calculation Services

| Service/Class | File | Purpose |
|---------------|------|---------|
| `MoneyCalculationService` | money_calculation_service.dart | Central calculation engine |
| `SaleDraftTotalsCalculator` | sale_draft_totals_calculator.dart | Sale totals |
| `SaleReturnTotalsCalculator` | sale_return_totals_calculator.dart | Return totals |
| `PurchaseDraftTotalsCalculator` | purchase_draft_totals_calculator.dart | Purchase totals |
| `PurchaseReturnTotalsCalculator` | purchase_return_totals_calculator.dart | Return totals |
| `CustomerBalanceCalculator` | customer_balance_calculator.dart | Customer balance |
| `BalanceDueCalculator` | balance_due_calculator.dart | Balance calculations |

### 4.2 Calculation Inputs/Outputs

| Class | File | Purpose |
|-------|------|---------|
| `DocumentLineInput` | document_line_input.dart | Line item input DTO |
| `InvoiceDiscountInput` | invoice_discount_input.dart | Discount configuration |
| `DocumentAdjustmentInput` | document_adjustment_input.dart | Adjustment input |
| `DocumentTotalsBreakdown` | document_totals_breakdown.dart | Calculated totals |
| `TaxBandTotal` | tax_band_total.dart | Tax by rate band |

### 4.3 Configuration

| Class | File | Purpose |
|-------|------|---------|
| `DiscountTimingConfig` | config/discount_timing_config.dart | Before/after tax |
| `RoundingRule` | rounding_rule.dart | Rounding behavior |

### 4.4 Calculation Formula Reference

**Subtotal Calculation:**
```
line_subtotal = quantity * unit_price_cents
subtotal = SUM(line_subtotal for all lines)
```

**Discount Calculation (Before Tax):**
```
if discount_type == 'percentage':
    discount_cents = subtotal * (discount_percentage / 100)
else:
    discount_cents = discount_amount_cents

net_amount = subtotal - discount_cents
```

**Tax Calculation:**
```
if discount_timing == 'before_tax':
    taxable_amount = net_amount
else:
    taxable_amount = subtotal

tax_cents = taxable_amount * (tax_rate_bps / 10000)
```

**Total Calculation:**
```
if discount_timing == 'before_tax':
    total = net_amount + tax_cents
else:
    total = subtotal + tax_cents - discount_cents
```

---

## 5. WIDGETS INVENTORY

### 5.1 Core Widgets (lib/core/widgets/)

| Widget | File | Purpose |
|--------|------|---------|
| `MainNavigationDrawer` | main_navigation_drawer.dart | App sidebar navigation |
| `GlobalAppBar` | global_app_bar.dart | Consistent app bar with actions |
| `DateRangeFilter` | date_range_filter.dart | Date range picker for reports |
| `ReportActionButtons` | report_action_buttons.dart | PDF/Excel/Share buttons |
| `BusinessRuleErrorDialog` | business_rule_error_dialog.dart | Validation error display (Red/Error theme) |
| `VoidReturnDialog` | void_return_dialog.dart | Void confirmation (Red/Destructive theme) |
| `PermissionWidgets` | permission_widgets.dart | Role-based visibility |
| `AppButton` | app_button.dart | Styled button (supports Success/Green, Warning/Orange, Error/Red) |
| `LogoHelper` | logo_helper.dart | Logo display utilities |

### 5.2 Sales Widgets (lib/features/sales/widgets/)

| Widget | File | Purpose |
|--------|------|---------|
| `SaleProductSelectionDialog` | sale_product_selection_dialog.dart | Product picker |
| `SaleProductEditDialog` | sale_product_edit_dialog.dart | Edit line item |
| `CustomerPaymentDialog` | customer_payment_dialog.dart | Record payment |
| `InvoiceSplitPaymentDialog` | invoice_split_payment_dialog.dart | Split payment |
| `CustomerSettlementDialog` | customer_settlement_dialog.dart | Settle balance |
| `VoidInvoiceDialog` | void_invoice_dialog.dart | Void invoice |
| `SaleInvoicePrintDialog` | sale_invoice_print_dialog.dart | Print options |
| `SaleReturnPrintDialog` | sale_return_print_dialog.dart | Print return |
| `QuickSaleSummaryDialog` | quick_sale_summary_dialog.dart | Quick sale checkout |
| `SaleTotalsPanel` | sale_totals_panel.dart | Totals display |

### 5.3 Purchase Widgets (lib/features/purchases/widgets/)

| Widget | File | Purpose |
|--------|------|---------|
| `ProductSelectionDialog` | product_selection_dialog.dart | Product picker |
| `ProductEditDialog` | product_edit_dialog.dart | Edit line item |
| `SupplierPaymentDialog` | supplier_payment_dialog.dart | Pay supplier |
| `SupplierRefundDialog` | supplier_refund_dialog.dart | Refund from supplier |
| `PurchaseBarcodeScanner` | purchase_barcode_scanner.dart | Scan products |
| `PurchaseReturnFormWidgets` | purchase_return_form_widgets.dart | Return form helpers |
| `PurchaseOtherDialogs` | purchase_other_dialogs.dart | Misc dialogs |

### 5.4 Supplier Widgets (lib/features/suppliers/widgets/)

| Widget | File | Purpose |
|--------|------|---------|
| `SupplierDiscountDialog` | supplier_discount_dialog.dart | Add discount |
| `SupplierPaymentDialog` | supplier_payment_dialog.dart | Pay supplier |
| `SupplierReturnDialog` | supplier_return_dialog.dart | Return to supplier |

### 5.5 Customer Widgets (lib/features/customers/widgets/)

| Widget | File | Purpose |
|--------|------|---------|
| `CustomerPaymentDialog` | customer_payment_dialog.dart | Record payment |

---

## 6. LOCALIZATION KEYS

### 6.1 Key Categories

All localization keys are in `lib/l10n/app_*.arb` files:
- `app_en.arb` - English (primary)
- `app_ar.arb` - Arabic
- `app_fr.arb` - French

### 6.2 Key Naming Convention

```
{module}_{component}_{element}

Examples:
- sales_form_addProduct
- reports_customer_agingTitle
- settings_currency_defaultCurrency
```

### 6.3 Required Key Categories

- **Common**: save, cancel, delete, edit, add, search, filter, refresh, loading, error
- **Auth**: login, logout, username, password, createAdmin
- **Dashboard**: dashboard, todaysSales, lowStock, recentTransactions
- **Products**: products, addProduct, editProduct, category, sku, barcode, price, cost, quantity
- **Customers**: customers, addCustomer, customerBalance, creditLimit
- **Suppliers**: suppliers, addSupplier, supplierBalance
- **Sales**: sales, newSale, invoice, payment, discount, tax, total, paid, change
- **Purchases**: purchases, newPurchase, supplier
- **Returns**: saleReturns, purchaseReturns, returnReason, refund
- **Reports**: reports, financialReports, inventoryReports, exportToPdf, exportToExcel
- **Settings**: settings, currency, language, theme, security, printing

---

## 7. PDF TEMPLATES

### 7.1 Invoice Template Structure

```
┌─────────────────────────────────────────────────────────────┐
│ [LOGO]          COMPANY NAME                    INVOICE     │
│                 Address Line 1                  #INV-00001  │
│                 Phone: +966...                  Date: ...   │
├─────────────────────────────────────────────────────────────┤
│ Bill To:                                                    │
│ Customer Name                                               │
│ Customer Address                                            │
│ Tax ID: ...                                                 │
├───────┬──────────────────┬────────┬──────────┬──────────────┤
│ # │ Item                 │ Qty    │ Price    │ Total        │
├───────┼──────────────────┼────────┼──────────┼──────────────┤
│ 1 │ Product 1            │ 2      │ 100.00   │ 200.00       │
│ 2 │ Product 2            │ 1      │ 50.00    │ 50.00        │
├───────┴──────────────────┴────────┼──────────┼──────────────┤
│                           Subtotal│          │ 250.00       │
│                           Discount│ 10%      │ -25.00       │
│                           Tax 15% │          │ 33.75        │
│                           TOTAL   │          │ 258.75       │
├─────────────────────────────────────────────────────────────┤
│ Payment Method: Cash                                        │
│ Amount Paid: 300.00                                         │
│ Change: 41.25                                               │
├─────────────────────────────────────────────────────────────┤
│ Notes: Thank you for your business!                         │
│                                                             │
│ Terms and Conditions...                                     │
├─────────────────────────────────────────────────────────────┤
│ Page 1 of 1                           Generated by Tapix    │
└─────────────────────────────────────────────────────────────┘
```

### 7.2 Report Template Structure

```
┌─────────────────────────────────────────────────────────────┐
│ COMPANY NAME                                                │
│ REPORT TITLE                                                │
│ Date Range: From ... To ...                                 │
│ Generated: ...                                              │
├─────────────────────────────────────────────────────────────┤
│ Summary:                                                    │
│ • Total Records: X                                          │
│ • Total Amount: X.XX                                        │
├───────┬──────────────────┬──────────┬──────────┬────────────┤
│ # │ Column 1           │ Column 2 │ Column 3 │ Column 4    │
├───────┼──────────────────┼──────────┼──────────┼────────────┤
│ DATA ROWS...                                                │
├───────┴──────────────────┴──────────┴──────────┴────────────┤
│ TOTALS ROW                                                  │
├─────────────────────────────────────────────────────────────┤
│ Page X of Y                           Generated by Tapix    │
└─────────────────────────────────────────────────────────────┘
```

### 7.3 Thermal Receipt Template (80mm)

```
================================
       COMPANY NAME
      Address Line 1
       Tel: +966...
================================
INV: #INV-00001
Date: 2026-01-23 17:00
Customer: Walk-in
--------------------------------
Item           Qty   Price   Amt
--------------------------------
Product 1        2  100.00  200.00
Product 2        1   50.00   50.00
--------------------------------
Subtotal:              250.00
Discount (10%):        -25.00
Tax (15%):              33.75
================================
TOTAL:                 258.75
================================
Paid (Cash):           300.00
Change:                 41.25
================================
    Thank you!
    Visit again!
================================
```

---

## 8. NAVIGATION STRUCTURE

### 8.1 Main Navigation (Drawer)

```
├── Dashboard
├── Products
│   ├── Product List
│   ├── Add Product
│   ├── Bulk Add
│   ├── Categories
│   ├── Colors
│   ├── Sizes
│   ├── Import
│   ├── Export
│   └── Barcode Design
├── Customers
├── Sales
├── Sale Returns
├── Reports
│   ├── Financial Reports
│   │   ├── Financial Statements
│   │   ├── Profit & Loss
│   │   ├── Balance Sheet
│   │   ├── Trial Balance
│   │   ├── General Ledger
│   │   ├── Cash Flow
│   │   ├── Tax Report
│   │   ├── Expense Report
│   │   ├── Sales Summary
│   │   ├── Journal Entries
│   │   └── Void Logs
│   ├── Inventory Reports
│   │   ├── Stock Report
│   │   ├── Low Stock
│   │   ├── Out of Stock
│   │   ├── Dead Stock
│   │   ├── Category Stocktake
│   │   └── Product Movement
│   ├── Customer Reports
│   │   ├── Aging Report
│   │   ├── Statement
│   │   ├── Analysis
│   │   ├── Payment Report
│   │   ├── Sales Report
│   │   ├── Sales Returns
│   │   └── Top Customers
│   ├── Supplier Reports
│   │   ├── Balance Report
│   │   ├── Debit Balances
│   │   ├── Credit Balances
│   │   ├── Analysis
│   │   ├── Aging
│   │   ├── Statement
│   │   └── Stocktake
│   └── Salespeople Reports
│       ├── Performance
│       └── Commissions
├── Notifications
├── ─── DIVIDER ───
├── Inventory
├── Purchases
├── Purchase Returns
├── Suppliers
├── Employees
├── Users
├── Expenses
├── ─── DIVIDER ───
├── Settings
│   ├── General
│   ├── Currency
│   ├── Security
│   ├── Printing
│   └── Database Health
└── ─── FOOTER ───
    ├── Language Selector (AR/EN/FR)
    └── Logout Button
```

### 8.2 Route Definitions

All routes use GoRouter with named routes for type-safety:

```dart
// Main routes
'/dashboard'
'/products' → '/products/list', '/products/add', '/products/edit/:id'
'/customers' → '/customers/add', '/customers/edit/:id', '/customers/profile/:id'
'/suppliers' → '/suppliers/add', '/suppliers/edit/:id', '/suppliers/:id'
'/sales' → '/sales/add', '/sales/edit/:id'
'/sales-returns' → '/sales-returns/new', '/sales-returns/edit/:id'
'/purchases' → '/purchases/add', '/purchases/edit/:id', '/purchases/:id'
'/purchases/returns' → '/purchases/returns/new', '/purchases/returns/:id'
'/reports' → '/reports/{report-type}'
'/expenses' → '/expenses/add', '/expenses/edit/:id', '/expenses/categories'
'/employees' → '/employees/add', '/employees/edit/:id'
'/users' → '/users/new', '/users/edit/:id'
'/settings' → '/settings/currency', '/settings/security', '/settings/printing'
'/journal-entries' → '/journal-entries/new', '/journal-entries/:id'
'/notifications'
```

---

## DOCUMENT END

**This document supplements the main specification.**  
**Use both documents together for complete implementation guidance.**

**Last Updated**: January 2026
