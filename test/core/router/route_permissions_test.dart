import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/router/route_permissions.dart';
import 'package:tapix/features/auth/domain/entities/user_entity.dart';

void main() {
  test('nested business routes inherit the closest parent roles', () {
    expect(
      RoutePermissions.rolesForPath('/sales/returns/new'),
      containsAll([UserRole.owner, UserRole.manager, UserRole.cashier]),
    );
    expect(
      RoutePermissions.rolesForPath('/sales/returns/new'),
      isNot(contains(UserRole.salesperson)),
    );
    expect(
      RoutePermissions.rolesForPath('/sales'),
      contains(UserRole.accountant),
    );
    expect(
      RoutePermissions.rolesForPath('/sales/new'),
      isNot(contains(UserRole.accountant)),
    );
    expect(
      RoutePermissions.rolesForPath('/sales/new'),
      containsAll([
        UserRole.owner,
        UserRole.manager,
        UserRole.cashier,
        UserRole.salesperson,
      ]),
    );
  });

  test('specific product routes override the broad products route', () {
    expect(
      RoutePermissions.rolesForPath('/products/new'),
      unorderedEquals([UserRole.owner, UserRole.manager]),
    );
    expect(
      RoutePermissions.rolesForPath('/products/42/edit'),
      unorderedEquals([UserRole.owner, UserRole.manager]),
    );
  });

  test('devices and network is restricted to the owner', () {
    expect(
      RoutePermissions.rolesForPath('/devices'),
      unorderedEquals([UserRole.owner]),
    );
  });
}
