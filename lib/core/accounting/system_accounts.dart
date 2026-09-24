/// Canonical Chart of Accounts required by posting policies.
///
/// Both database startup repair and the accounting repository seed from this
/// list so legacy databases cannot miss a newly introduced system account.
const systemAccountDefinitions = <Map<String, Object>>[
  // ── Assets (1xxx) ──
  {'code': '1000', 'name': 'Cash', 'type': 'asset', 'system': true, 'order': 1},
  {'code': '1010', 'name': 'Bank', 'type': 'asset', 'system': true, 'order': 2},
  {
    'code': '1020',
    'name': 'Cheques in Hand',
    'type': 'asset',
    'system': true,
    'order': 3,
  },
  {
    'code': '1030',
    'name': 'Dishonoured Cheques Receivable',
    'type': 'asset',
    'system': true,
    'order': 4,
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
  {
    'code': '1210',
    'name': 'Inventory in Transit',
    'type': 'asset',
    'system': true,
    'order': 5,
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
    'code': '2020',
    'name': 'Cheques Issued',
    'type': 'liability',
    'system': true,
    'order': 11,
  },
  {
    'code': '2050',
    'name': 'Accrued Consignment Payable',
    'type': 'liability',
    'system': true,
    'order': 12,
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
  {
    'code': '6200',
    'name': 'Bad Debt Expense',
    'type': 'expense',
    'system': true,
    'order': 50,
  },
];
