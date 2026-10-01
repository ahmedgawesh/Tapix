import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/online/online_configuration_policy.dart';
import 'package:tapix/core/services/online/online_sync_gateway.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';

class Session extends Fake implements SessionService {
  bool valid = true;
  @override
  Future<bool> isSessionValid() async => valid;
  @override
  Future<int?> getCurrentUserId() async => 77;
}

class License implements WarehouseSetupEntitlement {
  bool allowed = true;
  @override
  Future<bool> permits(WarehouseOperationScope scope) async => allowed;
}

void main() {
  test(
    'requires active owner, valid session, Pro and an independent device',
    () async {
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(db.close);
      await db.customStatement(
        "INSERT INTO users(id,username,password_hash,role,is_active,created_at,updated_at) VALUES(77,'owner','x','owner',1,0,0)",
      );
      final session = Session(), license = License();
      var dependent = false;
      final policy = OnlineConfigurationPolicy(
        db,
        session,
        license,
        isDependentClient: () => dependent,
      );
      await policy.authorize();
      for (final role in [
        'manager',
        'accountant',
        'cashier',
        'seller',
        'warehouse_keeper',
      ]) {
        await db.customStatement('UPDATE users SET role=? WHERE id=77', [role]);
        await expectLater(
          policy.authorize(),
          throwsA(isA<OnlineSyncException>()),
        );
      }
      await db.customStatement(
        "UPDATE users SET role='owner',is_active=0 WHERE id=77",
      );
      await expectLater(
        policy.authorize(),
        throwsA(isA<OnlineSyncException>()),
      );
      await db.customStatement('UPDATE users SET is_active=1 WHERE id=77');
      session.valid = false;
      await expectLater(
        policy.authorize(),
        throwsA(isA<OnlineSyncException>()),
      );
      session.valid = true;
      license.allowed = false;
      await expectLater(
        policy.authorize(),
        throwsA(isA<OnlineSyncException>()),
      );
      license.allowed = true;
      dependent = true;
      await expectLater(
        policy.authorize(),
        throwsA(isA<OnlineSyncException>()),
      );
    },
  );
}
