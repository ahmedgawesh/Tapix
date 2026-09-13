import 'dart:async';
import 'dart:typed_data';

import '../../database/daos/settings_dao.dart';
import '../localization_service.dart';
import 'lan_business_models.dart';
import 'lan_models.dart';

/// Web placeholder. Browser LAN access will be enabled in the web phase after
/// HTTPS and browser local-network permission handling are available.
class LanNetworkService {
  LanNetworkService(
    this._settingsDao, {
    LanMasterAuthGateway? authGateway,
    LanMasterBusinessGateway? businessGateway,
    LocalizationService? localizationService,
  });

  final SettingsDao _settingsDao;
  final _controller = StreamController<LanNetworkSnapshot>.broadcast();
  // Singleton service: the stream stays alive across LAN role changes.
  // ignore: close_sinks
  final _masterActivityController =
      StreamController<LanMasterActivityEvent>.broadcast();
  LanNetworkSnapshot _snapshot = const LanNetworkSnapshot();

  LanNetworkSnapshot get snapshot => _snapshot;
  LanRemoteUser? get remoteUser => null;
  bool get hasRemoteUserSession => false;
  Stream<LanNetworkSnapshot> get changes => _controller.stream;
  Stream<LanMasterActivityEvent> get masterActivityEvents =>
      _masterActivityController.stream;

  Future<void> initialize() async {
    final mode = await _settingsDao.getSetting('lan.mode');
    if (mode != null && mode != LanMode.standalone.name) {
      _snapshot = _snapshot.copyWith(
        status: LanConnectionStatus.error,
        error: 'LAN hosting is not available in the web build yet.',
      );
      _controller.add(_snapshot);
    }
  }

  Future<void> setStandalone() async {
    await _settingsDao.saveSetting('lan.mode', LanMode.standalone.name);
    _snapshot = const LanNetworkSnapshot();
    _controller.add(_snapshot);
  }

  Future<void> startMaster({int port = 45820}) async => _unsupported();

  Future<LanPairResult> pairWithMaster({
    required String host,
    required int port,
    required String pairingCode,
    required String deviceName,
  }) async {
    return const LanPairResult.failure('LAN is not available on web yet.');
  }

  Future<LanRemoteLoginResult> loginToMaster({
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    return const LanRemoteLoginResult.failure(
      'LAN authentication is not available on web yet.',
    );
  }

  Future<void> logoutFromMaster() async {}

  Future<bool> validateRemoteSession() async => false;

  Future<LanCatalogPage> fetchRemoteCatalog({
    String query = '',
    int offset = 0,
    int limit = 100,
    bool management = false,
  }) async => _unsupported();

  Future<LanMedicineAlternativesResult> fetchRemoteMedicineAlternatives(
    int productId,
  ) async => _unsupported();

  Future<Uint8List?> fetchRemoteProductImage(int productId) async =>
      _unsupported();

  Future<LanSalesPage> fetchRemoteSales({int limit = 500}) async =>
      _unsupported();

  Future<LanSaleDetails> fetchRemoteSaleDetails(int saleId) async =>
      _unsupported();

  Future<LanSaleVoidResult> voidRemoteSale(int saleId) async => _unsupported();

  Future<List<LanCustomerSummary>> fetchRemoteCustomers({
    String query = '',
    int limit = 100,
  }) async => _unsupported();

  Future<List<LanEmployeeSummary>> fetchRemoteSalespeople({
    String query = '',
    int limit = 100,
  }) async => _unsupported();

  Future<LanReturnableSalesPage> fetchRemoteReturnableSales({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async => _unsupported();

  Future<LanReturnableSaleDetails> fetchRemoteReturnableSale(
    int saleId,
  ) async => _unsupported();

  Future<LanSaleReturnsPage> fetchRemoteSaleReturns({
    String query = '',
    int offset = 0,
    int limit = 100,
  }) async => _unsupported();

  Future<LanSaleReturnDetails> fetchRemoteSaleReturnDetails({
    required int returnId,
    required bool adjustment,
  }) async => _unsupported();

  Future<LanSaleReturnResult> submitRemoteSaleReturn(
    LanSaleReturnRequest saleReturn,
  ) async => _unsupported();

  Future<LanSaleReturnResult> submitRemoteSaleAdjustmentReturn(
    LanSaleAdjustmentReturnRequest saleReturn,
  ) async => _unsupported();

  Future<List<LanSupplierSummary>> fetchRemoteSuppliers({
    String query = '',
    int limit = 100,
  }) async => _unsupported();

  Future<LanReturnablePurchasesPage> fetchRemoteReturnablePurchases({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async => _unsupported();

  Future<LanReturnablePurchaseDetails> fetchRemoteReturnablePurchase(
    int purchaseId,
  ) async => _unsupported();

  Future<LanPurchaseReturnsPage> fetchRemotePurchaseReturns({
    String query = '',
    int offset = 0,
    int limit = 100,
  }) async => _unsupported();

  Future<LanPurchaseReturnDetails> fetchRemotePurchaseReturnDetails({
    required int returnId,
    required bool adjustment,
  }) async => _unsupported();

  Future<LanPurchaseReturnResult> submitRemotePurchaseReturn(
    LanPurchaseReturnRequest purchaseReturn,
  ) async => _unsupported();

  Future<LanPurchaseReturnResult> submitRemotePurchaseAdjustmentReturn(
    LanPurchaseAdjustmentReturnRequest purchaseReturn,
  ) async => _unsupported();

  Future<void> voidRemotePurchaseReturn({
    required int returnId,
    required bool adjustment,
  }) async => _unsupported();

  Future<LanCashierShiftSnapshot?> fetchOwnRemoteShift() async =>
      _unsupported();

  Future<LanCashierShiftSnapshot> openOwnRemoteShift({
    required int openingCashCents,
    String? notes,
  }) async => _unsupported();

  Future<LanCashierShiftSnapshot> closeOwnRemoteShift({
    required int countedCashCents,
    String? notes,
  }) async => _unsupported();

  Future<LanSaleResult> submitRemoteSale(LanSaleRequest sale) async =>
      _unsupported();

  Future<bool> testConnection({String? host, int? port}) async => false;

  Future<void> refreshMasterNetwork() async {}

  Future<void> regeneratePairingCode() async => _unsupported();

  List<LanMasterDeviceInfo> getMasterDevices() => const [];

  Future<bool> logoutMasterDevice({
    required String deviceId,
    required int actorUserId,
    required String actorUsername,
    required String reason,
  }) async => _unsupported();

  Future<bool> renameMasterDevice({
    required String deviceId,
    required String name,
    required int actorUserId,
    required String actorUsername,
  }) async => _unsupported();

  Future<bool> revokeMasterDevice({
    required String deviceId,
    required int actorUserId,
    required String actorUsername,
    required String reason,
  }) async => _unsupported();

  Future<void> stop() async {}

  Never _unsupported() =>
      throw UnsupportedError('LAN is not available on web yet.');
}
