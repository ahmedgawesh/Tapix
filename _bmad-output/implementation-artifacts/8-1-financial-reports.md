# Story 8-1: Financial Reports

## Story
**As a** Manager
**I want** to view Profit & Loss, Balance Sheet, and Trial Balance reports
**So that** I know the business health.

## Acceptance Criteria
- [ ] Reports main screen with navigation to each report type
- [ ] Trial Balance report screen with account list, debit/credit columns, balanced indicator
- [ ] Reconciliation diagnostics accessible from reports (health check)
- [ ] P&L report screen (Revenue - COGS - Expenses) with date range filtering
- [ ] Balance Sheet report screen (Assets, Liabilities, Equity)
- [ ] General Ledger report screen (transactions by account)
- [ ] PDF export for Trial Balance (already exists via JournalPdfService)
- [ ] All money displayed via CurrencyService (integer cents)
- [ ] Real-time updates via RealtimeBloc pattern where applicable
- [ ] Follows Clean Architecture (Bloc + Repository + DI)

## Technical Notes
- `AccountingHealthBloc` already wired for trial balance + reconciliation
- `JournalRepository.getTrialBalance()` and `reconcileBalances()` already implemented
- `JournalPdfService` already has trial balance PDF generation
- Reports screens go under `lib/features/accounting/presentation/screens/`
- New blocs if needed go under `lib/features/accounting/presentation/bloc/`
- Use existing `AccountsBloc` for account data streams

## Dependencies
- Epic 7 (Finance & Accounting) - DONE
- `AccountingHealthBloc` - DONE
- `JournalRepository` trial balance + reconciliation - DONE
