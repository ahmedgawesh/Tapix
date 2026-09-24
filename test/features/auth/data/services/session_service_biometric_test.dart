import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/features/auth/data/services/session_service.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage storage;
  late Map<String, String?> values;
  late SessionService service;

  setUp(() {
    storage = _MockSecureStorage();
    values = <String, String?>{};

    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((invocation) async {
      values[invocation.namedArguments[#key] as String] =
          invocation.namedArguments[#value] as String?;
    });
    when(() => storage.read(key: any(named: 'key'))).thenAnswer(
      (invocation) async => values[invocation.namedArguments[#key] as String],
    );
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((
      invocation,
    ) async {
      values.remove(invocation.namedArguments[#key] as String);
    });

    service = SessionService(storage: storage);
  });

  tearDown(() => service.dispose());

  test(
    'logout clears the session but preserves the last authenticated user',
    () async {
      await service.saveSession(42);
      expect(await service.getCurrentUserId(), 42);
      expect(await service.getLastAuthenticatedUserId(), 42);

      await service.clearSession();

      expect(await service.getCurrentUserId(), isNull);
      expect(await service.isSessionValid(), isFalse);
      expect(await service.getLastAuthenticatedUserId(), 42);
    },
  );

  test('logout migrates the current user from older installations', () async {
    values['current_user_id'] = '7';

    await service.clearSession();

    expect(values['current_user_id'], isNull);
    expect(await service.getLastAuthenticatedUserId(), 7);
  });
}
