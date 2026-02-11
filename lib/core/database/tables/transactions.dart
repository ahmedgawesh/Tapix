import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'products.dart';
import 'parties.dart';
import 'people.dart';

@DataClassName('Sale')
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().unique()();
  IntColumn get customerId => integer().nullable().references(Customers, #id, onDelete: KeyAction.restrict)();
  IntColumn get employeeId => integer().nullable().references(Employees, #id, onDelete: KeyAction.restrict)();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get taxCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get paidAmountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get paymentMethod => text()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get saleDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleItem')
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().nullable().references(ProductVariants, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantity => integer()();
  IntColumn get unitPriceCents => integer().map(const MoneyConverter())();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleTaxBand')
class SaleTaxBands extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  TextColumn get taxName => text()();
  IntColumn get taxRateBps => integer().map(const BasisPointsConverter())();
  IntColumn get taxAmountCents => integer().map(const MoneyConverter())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleReturn')
class SaleReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.restrict)();
  TextColumn get returnNumber => text().unique()();
  IntColumn get subtotalCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  /// draft, posted, voided
  TextColumn get status => text().withDefault(const Constant('draft'))();
  /// restock, write_off, exchange, store_credit, refund
  TextColumn get dispositionType => text().withDefault(const Constant('restock'))();
  /// cash, credit, cheque
  TextColumn get refundMethod => text().withDefault(const Constant('cash'))();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleReturnItem')
class SaleReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(SaleReturns, #id, onDelete: KeyAction.cascade)();
  IntColumn get saleItemId => integer().references(SaleItems, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantity => integer()();
  IntColumn get subtotalCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get refundCents => integer().map(const MoneyConverter())();
  /// wrong_size, defective, wrong_item, changed_mind, other
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SalePayment')
class SalePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  /// cash, card, bank_transfer, mobile, credit
  TextColumn get paymentMethod => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get paymentDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Purchase')
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get purchaseNumber => text().unique()();
  IntColumn get supplierId => integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents => integer().map(const MoneyConverter())();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get paidAmountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get supplierInvoiceRef => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get purchaseDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseItem')
class PurchaseItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().nullable().references(ProductVariants, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantity => integer()();
  IntColumn get unitCostCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get taxCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get originalCostCents => integer().map(const MoneyConverter()).nullable()();
  IntColumn get originalPriceCents => integer().map(const MoneyConverter()).nullable()();
  IntColumn get originalWholesalePriceCents => integer().map(const MoneyConverter()).nullable()();
  IntColumn get newSellPriceCents => integer().map(const MoneyConverter()).nullable()();
  IntColumn get newWholesalePriceCents => integer().map(const MoneyConverter()).nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseReturn')
class PurchaseReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id, onDelete: KeyAction.restrict)();
  TextColumn get returnNumber => text().unique()();
  IntColumn get subtotalCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  /// draft, posted, voided
  TextColumn get status => text().withDefault(const Constant('draft'))();
  /// restock, write_off, repair, replace, refund
  TextColumn get dispositionType => text().withDefault(const Constant('restock'))();
  /// cash, credit, cheque
  TextColumn get refundMethod => text().withDefault(const Constant('credit'))();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseReturnItem')
class PurchaseReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(PurchaseReturns, #id, onDelete: KeyAction.cascade)();
  IntColumn get purchaseItemId => integer().references(PurchaseItems, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantity => integer()();
  IntColumn get subtotalCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get refundCents => integer().map(const MoneyConverter())();
  /// damaged, wrong_item, quality, overstock, other
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchasePayment')
class PurchasePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  /// cash, card, cheque, bank_transfer
  TextColumn get paymentMethod => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get paymentDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
