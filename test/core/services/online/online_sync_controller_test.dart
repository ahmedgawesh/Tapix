import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_models.dart';
import 'package:tapix/core/services/online/online_branch_sync_service.dart';
import 'package:tapix/core/services/online/online_sync_controller.dart';
import 'package:tapix/core/services/online/online_sync_gateway.dart';

void main() {
  OnlineConnectionSummary connection({bool enabled = true}) =>
      OnlineConnectionSummary(
        endpoint: Uri.parse('https://example.test'),
        name: 'Branch',
        role: 'writer',
        enabled: enabled,
      );
  const done = LanBranchSyncRunResult(uploaded: 0, downloaded: 0);

  testWidgets(
    'retries connection failures with backoff and resets after success',
    (tester) async {
      var count = 0;
      final controller = OnlineSyncController(
        inspect: () async => connection(),
        canRun: () => true,
        synchronize: () async {
          count++;
          if (count < 3) {
            throw const OnlineSyncException('online_connection_unavailable');
          }
          return done;
        },
      );
      addTearDown(controller.dispose);
      controller.start();
      await tester.pump();
      expect(controller.state, OnlineSyncState.retrying);
      expect(count, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(count, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(count, 2);
      await tester.pump(const Duration(seconds: 9));
      expect(count, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(count, 3);
      expect(controller.state, OnlineSyncState.healthy);
      await tester.pump(const Duration(seconds: 15));
      expect(count, 4);
      controller.stop();
    },
  );
  testWidgets(
    'app stop cancels retries and resume performs one immediate exchange',
    (tester) async {
      var count = 0;
      final controller = OnlineSyncController(
        inspect: () async => connection(),
        canRun: () => true,
        synchronize: () async {
          count++;
          return done;
        },
      );
      addTearDown(controller.dispose);
      controller.start();
      await tester.pump();
      controller.stop();
      await tester.pump(const Duration(minutes: 5));
      expect(count, 1);
      controller.start();
      await tester.pump();
      expect(count, 2);
      controller.stop();
    },
  );
  testWidgets('dependent devices and saved pause perform no requests', (
    tester,
  ) async {
    var allowed = false, enabled = true, count = 0;
    final controller = OnlineSyncController(
      inspect: () async => connection(enabled: enabled),
      canRun: () => allowed,
      synchronize: () async {
        count++;
        return done;
      },
    );
    addTearDown(controller.dispose);
    controller.start();
    await tester.pump();
    expect(controller.state, OnlineSyncState.paused);
    allowed = true;
    enabled = false;
    await controller.refresh();
    expect(count, 0);
    enabled = true;
    await controller.refresh();
    expect(count, 1);
    controller.stop();
  });
  testWidgets(
    'permanent identity and entitlement errors stop automatic retries',
    (tester) async {
      for (final code in [
        'online_identity_mismatch',
        'online_entitlement_required',
        'unauthorized',
      ]) {
        var count = 0;
        final controller = OnlineSyncController(
          inspect: () async => connection(),
          canRun: () => true,
          synchronize: () async {
            count++;
            throw OnlineSyncException(code);
          },
        );
        controller.start();
        await tester.pump();
        expect(controller.state, OnlineSyncState.blocked);
        await tester.pump(const Duration(minutes: 10));
        expect(count, 1);
        controller.dispose();
      }
    },
  );
  testWidgets('refreshes coalesce and disposal during exchange is safe', (
    tester,
  ) async {
    var count = 0;
    final completer = Completer<LanBranchSyncRunResult>();
    final controller = OnlineSyncController(
      inspect: () async => connection(),
      canRun: () => true,
      synchronize: () {
        count++;
        return completer.future;
      },
    );
    controller.start();
    await tester.pump();
    final first = controller.refresh(), second = controller.refresh();
    expect(count, 1);
    controller.dispose();
    completer.complete(done);
    await Future.wait([first, second]);
    await tester.pump(const Duration(minutes: 5));
    expect(count, 1);
  });
}
