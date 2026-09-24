import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_access_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_repository.dart';

class _Session extends SessionService {
  _Session(this.userId);
  int? userId;

  @override
  Future<int?> getCurrentUserId() async => userId;
}

class _Entitlement implements WarehouseSetupEntitlement {
  _Entitlement(this.allowed);
  bool allowed;

  @override
  Future<bool> permits(WarehouseOperationScope scope) async => allowed;
}

void main() {
  late AppDatabase db;
  late WarehouseOperationScope primary;
  late String destinationId;
  late _Session session;
  late _Entitlement entitlement;
  late bool remote;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    primary = await WarehouseOperationScope.resolve(db);
    final owner = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'transfer-access-owner',
            passwordHash: 'test',
            role: 'owner',
            createdAt: DateTime.utc(2026, 9, 24),
            updatedAt: DateTime.utc(2026, 9, 24),
          ),
        );
    session = _Session(owner);
    entitlement = _Entitlement(true);
    remote = false;
    destinationId = '77777777-7777-4777-8777-777777777777';
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: destinationId,
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: 'DST',
            name: const Value('Destination'),
          ),
        );
  });

  tearDown(() => db.close());

  WarehouseTransferAccessService service() => WarehouseTransferAccessService(
    db,
    session,
    entitlement,
    isRemoteClient: () => remote,
  );

  test('owner with Pro can use and list both local warehouses', () async {
    final access = service();

    final actor = await access.authorize(
      TransferDraftAction.dispatch,
      primary.warehouseId,
      destinationId,
    );
    final warehouses = await access.warehouses();

    expect(actor, session.userId);
    expect(warehouses.map((warehouse) => warehouse.id).toSet(), {
      primary.warehouseId,
      destinationId,
    });
  });

  test(
    'catalog searches source stock and validates quantity precision',
    () async {
      final currency = (await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle()).id;
      final product = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Transfer search shoe',
              currencyId: Value(currency),
              sku: const Value('SHOE-BASE'),
              stockQuantity: const Value(5),
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(1500),
            ),
          );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: product,
              sku: const Value('SHOE-GREEN-XS'),
              stockQuantity: const Value(5),
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(1500),
            ),
          );

      final rows = await service().catalog(primary.warehouseId, query: 'green');

      expect(rows, hasLength(1));
      expect(rows.single.name, 'Transfer search shoe');
      expect(rows.single.code, 'SHOE-GREEN-XS');
      expect(rows.single.quantity, 5);
      expect(rows.single.ownedQuantity, 5);
      expect(rows.single.parseQuantity('٢'), 2);
      expect(() => rows.single.parseQuantity('6'), throwsFormatException);
      expect(() => rows.single.parseQuantity('1.5'), throwsFormatException);
    },
  );

  test('LAN replica cannot write transfers directly', () async {
    remote = true;

    await expectLater(
      service().authorize(
        TransferDraftAction.receive,
        primary.warehouseId,
        destinationId,
      ),
      throwsA(isA<WarehouseTransferAccessDenied>()),
    );
  });

  test('inactive or non-owner session is denied', () async {
    final cashier = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'transfer-access-cashier',
            passwordHash: 'test',
            role: 'cashier',
            createdAt: DateTime.utc(2026, 9, 24),
            updatedAt: DateTime.utc(2026, 9, 24),
          ),
        );
    session.userId = cashier;

    await expectLater(
      service().authorizeWarehouse(primary.warehouseId),
      throwsA(isA<WarehouseTransferAccessDenied>()),
    );
  });

  test(
    'missing Pro entitlement denies local multi-warehouse transfer',
    () async {
      entitlement.allowed = false;

      await expectLater(
        service().authorize(
          TransferDraftAction.create,
          primary.warehouseId,
          destinationId,
        ),
        throwsA(isA<WarehouseTransferAccessDenied>()),
      );
    },
  );
}
