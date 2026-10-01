import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/auth/presentation/models/user_location_option.dart';

void main() {
  final createdAt = DateTime(2026, 9, 30);
  final branch = BusinessBranch(
    id: 'branch-cairo',
    organizationId: 'org',
    code: 'CAIRO',
    name: 'فرع القاهرة',
    isActive: true,
    createdAt: createdAt,
  );

  BusinessWarehouse location({
    required String id,
    required String code,
    required String name,
    required String kind,
  }) {
    return BusinessWarehouse(
      id: id,
      organizationId: 'org',
      branchId: branch.id,
      code: code,
      name: name,
      locationKind: kind,
      isActive: true,
      createdAt: createdAt,
    );
  }

  test('distinguishes branch sales floor from a same-named warehouse', () {
    final salesFloor = location(
      id: 'floor',
      code: 'CAIRO-FLOOR',
      name: 'مخزن فرع القاهرة',
      kind: 'branch_store',
    );
    final warehouse = location(
      id: 'warehouse',
      code: 'CAIRO-WH',
      name: 'مخزن فرع القاهرة',
      kind: 'warehouse',
    );

    final floorOption = UserLocationOption(
      location: salesFloor,
      branch: branch,
    );
    final warehouseOption = UserLocationOption(
      location: warehouse,
      branch: branch,
    );

    expect(
      floorOption.label(salesFloorLabel: 'الصالة', warehouseLabel: 'مخزن'),
      'فرع القاهرة (الصالة) · CAIRO-FLOOR',
    );
    expect(
      warehouseOption.label(salesFloorLabel: 'الصالة', warehouseLabel: 'مخزن'),
      'مخزن فرع القاهرة (مخزن) · CAIRO-WH',
    );
  });

  test('orders branch sales floor before independent warehouses', () {
    final warehouse = location(
      id: 'warehouse',
      code: 'A-WH',
      name: 'A warehouse',
      kind: 'warehouse',
    );
    final salesFloor = location(
      id: 'floor',
      code: 'Z-FLOOR',
      name: 'Z legacy name',
      kind: 'branch_store',
    );

    expect(
      UserLocationOption.sortLocations([
        warehouse,
        salesFloor,
      ]).map((row) => row.id),
      ['floor', 'warehouse'],
    );
  });
}
