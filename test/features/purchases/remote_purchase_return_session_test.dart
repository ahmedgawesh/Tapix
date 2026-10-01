import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_return_form_bloc.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_returns_bloc.dart';

class _LocalRepository extends Fake implements PurchaseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('A linked workstation must not read its local purchases');
  }
}

class _ExpiredSession extends Fake implements LanNetworkService {
  int requests = 0;

  @override
  LanNetworkSnapshot get snapshot =>
      const LanNetworkSnapshot(mode: LanMode.client);

  @override
  bool get hasRemoteUserSession => false;

  Never _denied() {
    requests++;
    throw const LanBusinessException(
      'authentication_required',
      'Sign in to the branch first.',
      statusCode: 401,
    );
  }

  @override
  Future<LanPurchaseReturnsPage> fetchRemotePurchaseReturns({
    String query = '',
    int offset = 0,
    int limit = 100,
  }) async => _denied();

  @override
  Future<LanReturnablePurchaseDetails> fetchRemoteReturnablePurchase(
    int purchaseId,
  ) async => _denied();
}

void main() {
  test(
    'return list with an expired LAN session never reads local data',
    () async {
      final lan = _ExpiredSession();
      final bloc = PurchaseReturnsBloc(_LocalRepository(), lan: lan);
      final state = await bloc.stream.firstWhere(
        (state) => state is RealtimeError,
      );
      expect((state as RealtimeError).error, isA<LanBusinessException>());
      expect(lan.requests, 1);
      await bloc.close();
    },
  );

  test(
    'linked return with an expired session fails instead of using a local invoice',
    () async {
      final lan = _ExpiredSession();
      final bloc = PurchaseReturnFormBloc(_LocalRepository(), lan: lan);
      final result = bloc.stream.firstWhere((state) => state.error != null);
      bloc.add(const PurchaseReturnFormInitialized(42));
      final state = await result;
      expect(state.error, 'Sign in to the branch first.');
      expect(lan.requests, 1);
      expect(state.purchase, isNull);
      await bloc.close();
    },
  );
}
