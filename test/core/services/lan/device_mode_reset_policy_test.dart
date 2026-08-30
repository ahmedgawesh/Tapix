import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/device_mode_reset_service.dart';
import 'package:tapix/core/services/lan/lan_models.dart';
import 'package:tapix/features/auth/domain/entities/user_entity.dart';

void main() {
  test('only an owner authenticated by the master may reset a client', () {
    expect(
      DeviceModeResetPolicy.canReset(
        localRole: UserRole.owner,
        remoteRole: 'owner',
        currentMode: LanMode.client,
      ),
      isTrue,
    );

    for (final role in UserRole.values.where(
      (role) => role != UserRole.owner,
    )) {
      expect(
        DeviceModeResetPolicy.canReset(
          localRole: role,
          remoteRole: role.name,
          currentMode: LanMode.client,
        ),
        isFalse,
      );
    }
  });

  test('local role cannot bypass master identity or device mode', () {
    expect(
      DeviceModeResetPolicy.canReset(
        localRole: UserRole.owner,
        remoteRole: 'manager',
        currentMode: LanMode.client,
      ),
      isFalse,
    );
    expect(
      DeviceModeResetPolicy.canReset(
        localRole: UserRole.owner,
        remoteRole: 'owner',
        currentMode: LanMode.master,
      ),
      isFalse,
    );
  });
}
