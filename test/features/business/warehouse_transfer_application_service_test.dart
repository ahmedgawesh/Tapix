import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_application_service.dart';

class _Network extends Fake implements LanNetworkService {
  final requests = <Set<String>>[];
  LanMode mode = LanMode.client;
  String? assigned = 'cairo-warehouse';
  @override
  LanNetworkSnapshot get snapshot =>
      LanNetworkSnapshot(mode: mode, assignedWarehouseId: assigned);

  @override
  Future<List<LanWarehouseTransferDocument>> fetchRemoteWarehouseTransfers({
    required Set<String> statuses,
    int limit = 100,
  }) async {
    requests.add(Set.unmodifiable(statuses));
    return const [
      LanWarehouseTransferDocument(
        id: '683c002a-feaf-44ed-9e90-e07534ea0671',
        sourceWarehouseId: 'cairo-floor',
        destinationWarehouseId: 'cairo-warehouse',
        status: 'in_transit',
        lineCount: 2,
        notes: '',
        recalled: false,
      ),
    ];
  }
}

void main() {
  test(
    'same database transfer has opposite device perspectives without changing transport',
    () async {
      final network = _Network();
      final delegate = RemoteWarehouseTransferApplicationService(network);
      final service = AdaptiveWarehouseTransferApplicationService(
        local: delegate,
        remote: delegate,
        network: network,
        localWarehouseId: () async => 'cairo-floor',
      );
      final inbound = (await service.list(statuses: {'in_transit'})).single;
      expect(inbound.viewpoint, WarehouseTransferViewpoint.receiver);
      expect(inbound.receiverActions, isTrue);
      expect(inbound.senderActions, isFalse);
      expect(inbound.flow, WarehouseTransferDocumentFlow.local);
      network.mode = LanMode.master;
      final outbound = (await service.list(statuses: {'in_transit'})).single;
      expect(outbound.viewpoint, WarehouseTransferViewpoint.sender);
      expect(outbound.senderActions, isTrue);
      expect(outbound.receiverActions, isFalse);
      expect(outbound.id, inbound.id);
      expect(outbound.flow, WarehouseTransferDocumentFlow.local);
      network.mode = LanMode.client;
      network.assigned = 'unrelated-warehouse';
      final observer = (await service.list(statuses: {'in_transit'})).single;
      expect(observer.senderActions, isFalse);
      expect(observer.receiverActions, isFalse);
    },
  );

  test(
    'remote transfer list sends only native server lifecycle states',
    () async {
      final network = _Network();
      var observed = 0;
      final service = RemoteWarehouseTransferApplicationService(
        network,
        onTransfersLoaded: (rows) async => observed += rows.length,
      );

      final active = await service.list(
        statuses: const {
          'draft',
          'in_transit',
          'recall_pending',
          'partially_received',
          'conflict',
        },
      );

      expect(active.map((row) => row.id), [
        '683c002a-feaf-44ed-9e90-e07534ea0671',
      ]);
      expect(network.requests.single, {
        'draft',
        'in_transit',
        'partially_received',
      });
      expect(observed, 1);

      final distributedOnly = await service.list(
        statuses: const {'recall_pending', 'conflict', 'recalled'},
      );
      expect(distributedOnly, isEmpty);
      expect(network.requests, hasLength(1));
    },
  );
}
