import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';

/// Bootstrap the single-branch identity without rewriting a customer's stock,
/// cost, money, historical document identifiers, or subscription settings.
Future<void> initializeBusinessFoundation(AppDatabase db) async {
  await db.transaction(() async {
    final contexts = await db.select(db.businessContexts).get();
    if (contexts.isNotEmpty) {
      if (contexts.length != 1 || contexts.single.id != 1) {
        throw StateError(
          'Invalid business context; refusing to reassign data.',
        );
      }
      return;
    }
    final organizationCount = await db.select(db.businessOrganizations).get();
    final branchCount = await db.select(db.businessBranches).get();
    final warehouseCount = await db.select(db.businessWarehouses).get();
    if (organizationCount.isNotEmpty ||
        branchCount.isNotEmpty ||
        warehouseCount.isNotEmpty) {
      throw StateError(
        'Incomplete business identity; refusing to create a second owner.',
      );
    }
    const uuid = Uuid();
    final organizationId = uuid.v4();
    final branchId = uuid.v4();
    final warehouseId = uuid.v4();
    await db
        .into(db.businessOrganizations)
        .insert(BusinessOrganizationsCompanion.insert(id: organizationId));
    await db
        .into(db.businessBranches)
        .insert(
          BusinessBranchesCompanion.insert(
            id: branchId,
            organizationId: organizationId,
            code: 'MAIN',
          ),
        );
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: warehouseId,
            organizationId: organizationId,
            branchId: branchId,
            code: 'MAIN',
          ),
        );
    await db
        .into(db.businessContexts)
        .insert(
          BusinessContextsCompanion.insert(
            id: const Value(1),
            organizationId: organizationId,
            branchId: branchId,
            warehouseId: warehouseId,
            databaseId: uuid.v4(),
          ),
        );
  });
}
