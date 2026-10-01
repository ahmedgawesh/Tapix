import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/promotions/promotion_repository.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_returns_bloc.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_return_form_bloc.dart';

class _Local extends Fake implements SaleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Local sale access forbidden');
}

class _Promotions extends Fake implements PromotionRepository {}

class _Expired extends Fake implements LanNetworkService {
  int requests = 0;
  @override
  LanNetworkSnapshot get snapshot =>
      const LanNetworkSnapshot(mode: LanMode.client);
  @override
  bool get hasRemoteUserSession => false;
  Never denied() {
    requests++;
    throw const LanBusinessException(
      'authentication_required',
      'Sign in again.',
      statusCode: 401,
    );
  }

  @override
  Future<LanSaleReturnsPage> fetchRemoteSaleReturns({
    String query = '',
    int offset = 0,
    int limit = 100,
  }) async => denied();
  @override
  Future<LanReturnableSaleDetails> fetchRemoteReturnableSale(
    int saleId,
  ) async => denied();
}

void main() {
  test(
    'expired cashier return list fails authenticated request without reading local sales',
    () async {
      final lan = _Expired();
      final bloc = SaleReturnsBloc(_Local(), lan: lan);
      final result = await bloc.stream.firstWhere((s) => s is RealtimeError);
      expect((result as RealtimeError).error, isA<LanBusinessException>());
      expect(lan.requests, 1);
      await bloc.close();
    },
  );
  test(
    'expired cashier linked return cannot load a same-ID local invoice',
    () async {
      final lan = _Expired();
      final bloc = SaleReturnFormBloc(
        _Local(),
        promotionRepository: _Promotions(),
        lan: lan,
      );
      final result = bloc.stream.firstWhere((s) => s.error != null);
      bloc.add(const SaleReturnFormInitialized(42));
      expect((await result).error, 'Sign in again.');
      expect(lan.requests, 1);
      expect(bloc.state.sale, isNull);
      await bloc.close();
    },
  );
}
