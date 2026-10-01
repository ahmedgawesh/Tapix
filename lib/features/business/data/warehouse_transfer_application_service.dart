import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/business/warehouse_transfer_preflight.dart';
import '../../../core/services/lan/lan_network_service.dart';
import 'warehouse_transfer_access_service.dart';
import 'distributed_transfer_dispatch_service.dart';
import 'distributed_transfer_receipt_service.dart';
import 'warehouse_transfer_dispatch_service.dart';
import 'warehouse_transfer_receipt_service.dart';
import 'warehouse_transfer_recall_service.dart';
import 'warehouse_transfer_repository.dart';

class WarehouseTransferAppWarehouse {
  const WarehouseTransferAppWarehouse({
    required this.id,
    required this.code,
    required this.name,
    this.branchName,
    this.isLocal = true,
    this.isBranchLocation = false,
  });

  final String id;
  final String code;
  final String name;
  final String? branchName;
  final bool isLocal;
  final bool isBranchLocation;
}

class WarehouseTransferAppCatalogItem {
  const WarehouseTransferAppCatalogItem({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.code,
    required this.quantity,
    required this.supplierOwnedQuantity,
    required this.quantityScale,
    required this.measurementType,
  });

  final int productId;
  final int variantId;
  final String name;
  final String code;
  final int quantity;
  final int supplierOwnedQuantity;
  final int quantityScale;
  final String measurementType;

  int get ownedQuantity => quantity - supplierOwnedQuantity;

  int parseQuantity(String input) => parseQuantityWithin(input, quantity);

  int parseQuantityWithin(
    String input,
    int available, {
    bool allowZero = false,
  }) {
    var text = input.trim().replaceAll('\u066B', '.').replaceAll(',', '.');
    const arabic =
        '\u0660\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668\u0669';
    const persian =
        '\u06F0\u06F1\u06F2\u06F3\u06F4\u06F5\u06F6\u06F7\u06F8\u06F9';
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    if (text.length > 40 || !RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
      throw const FormatException('Invalid transfer quantity');
    }
    final parts = text.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    final digits = quantityScale == 1 ? 0 : 3;
    if (fraction.length > digits) {
      throw const FormatException('Transfer quantity precision');
    }
    final amount = BigInt.parse(parts[0] + fraction.padRight(digits, '0'));
    if ((!allowZero && amount <= BigInt.zero) ||
        amount < BigInt.zero ||
        amount > BigInt.from(available)) {
      throw const FormatException('Transfer quantity is unavailable');
    }
    return amount.toInt();
  }
}

class WarehouseTransferAppLine {
  const WarehouseTransferAppLine({
    required this.productId,
    required this.variantId,
    required this.quantity,
    this.ownedQuantity,
    this.consignmentQuantity,
  });

  final int productId;
  final int variantId;
  final int quantity;
  final int? ownedQuantity;
  final int? consignmentQuantity;

  WarehouseTransferOwnershipIntent? ownershipIntent() {
    if (ownedQuantity == null && consignmentQuantity == null) return null;
    if (ownedQuantity == null || consignmentQuantity == null) {
      throw ArgumentError('Transfer ownership selection is incomplete');
    }
    final intent = WarehouseTransferOwnershipIntent(
      ownedQuantity: ownedQuantity!,
      consignmentQuantity: consignmentQuantity!,
    );
    intent.validate(quantity);
    return intent;
  }
}

class WarehouseTransferAppDocument {
  const WarehouseTransferAppDocument({
    required this.id,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.status,
    required this.lineCount,
    required this.notes,
    required this.recalled,
    this.flow = WarehouseTransferDocumentFlow.local,
    this.viewpoint = WarehouseTransferViewpoint.management,
  });

  final String id;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final String status;
  final int lineCount;
  final String notes;
  final bool recalled;
  final WarehouseTransferDocumentFlow flow;

  /// Device perspective is separate from the database transport route.
  final WarehouseTransferViewpoint viewpoint;
  bool get senderActions =>
      viewpoint == WarehouseTransferViewpoint.sender ||
      viewpoint == WarehouseTransferViewpoint.management;
  bool get receiverActions =>
      viewpoint == WarehouseTransferViewpoint.receiver ||
      viewpoint == WarehouseTransferViewpoint.management;

  WarehouseTransferAppDocument viewedFrom(
    String? warehouseId, {
    bool management = false,
  }) => WarehouseTransferAppDocument(
    id: id,
    sourceWarehouseId: sourceWarehouseId,
    destinationWarehouseId: destinationWarehouseId,
    status: status,
    lineCount: lineCount,
    notes: notes,
    recalled: recalled,
    flow: flow,
    viewpoint: warehouseId == sourceWarehouseId
        ? WarehouseTransferViewpoint.sender
        : warehouseId == destinationWarehouseId
        ? WarehouseTransferViewpoint.receiver
        : management
        ? WarehouseTransferViewpoint.management
        : WarehouseTransferViewpoint.observer,
  );
}

enum WarehouseTransferViewpoint { sender, receiver, observer, management }

enum WarehouseTransferDocumentFlow { local, outbound, inbound }

class WarehouseTransferAppPending {
  const WarehouseTransferAppPending({
    required this.allocationId,
    required this.remainingQuantity,
    required this.quantityScale,
    required this.productName,
    required this.code,
    required this.ownerType,
  });

  final String allocationId;
  final int remainingQuantity;
  final int quantityScale;
  final String productName;
  final String code;
  final String ownerType;
}

class WarehouseTransferAppReceiptItem {
  const WarehouseTransferAppReceiptItem({
    required this.allocationId,
    this.acceptedQuantity = 0,
    this.damagedQuantity = 0,
    this.lostQuantity = 0,
    this.varianceResponsibility,
    this.liabilityUnitCents,
  });

  final String allocationId;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int lostQuantity;
  final String? varianceResponsibility;
  final int? liabilityUnitCents;
}

abstract interface class WarehouseTransferApplicationService {
  bool get remote;

  Future<List<WarehouseTransferAppWarehouse>> warehouses();

  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  });

  Future<List<WarehouseTransferAppCatalogItem>> catalog(
    String warehouseId, {
    String query = '',
    int offset = 0,
  });

  Future<WarehouseTransferAppDocument> create({
    required String requestKey,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required List<WarehouseTransferAppLine> lines,
    String notes = '',
  });

  Future<void> dispatch({
    required String transferId,
    required String requestKey,
  });

  Future<void> cancel({
    required String transferId,
    required String requestKey,
    required String reason,
  });

  Future<List<WarehouseTransferAppPending>> pending(String transferId);

  Future<void> receive({
    required String transferId,
    required String requestKey,
    required List<WarehouseTransferAppReceiptItem> items,
    String notes = '',
  });

  Future<void> recall({
    required String transferId,
    required String requestKey,
    required String reason,
  });
}

class LocalWarehouseTransferApplicationService
    implements WarehouseTransferApplicationService {
  const LocalWarehouseTransferApplicationService({
    required WarehouseTransferAccessService access,
    required WarehouseTransferRepository repository,
    required WarehouseTransferPreflight preflight,
    required WarehouseTransferDispatchService dispatch,
    required WarehouseTransferReceiptService receipt,
    required WarehouseTransferRecallService recall,
  }) : _access = access,
       _repository = repository,
       _preflight = preflight,
       _dispatch = dispatch,
       _receipt = receipt,
       _recall = recall;

  final WarehouseTransferAccessService _access;
  final WarehouseTransferRepository _repository;
  final WarehouseTransferPreflight _preflight;
  final WarehouseTransferDispatchService _dispatch;
  final WarehouseTransferReceiptService _receipt;
  final WarehouseTransferRecallService _recall;

  @override
  bool get remote => false;

  WarehouseTransferAppDocument _document(WarehouseTransferDraft draft) =>
      WarehouseTransferAppDocument(
        id: draft.header.id,
        sourceWarehouseId: draft.header.sourceWarehouseId,
        destinationWarehouseId: draft.header.destinationWarehouseId,
        status: draft.header.status,
        lineCount: draft.lines.length,
        notes: draft.header.notes,
        recalled: draft.recall != null,
      );

  @override
  Future<List<WarehouseTransferAppWarehouse>> warehouses() async =>
      (await _access.warehouses())
          .map(
            (row) => WarehouseTransferAppWarehouse(
              id: row.warehouse.id,
              code: row.warehouse.code,
              name: row.warehouse.name,
              branchName: row.branchName,
              isBranchLocation: row.warehouse.locationKind == 'branch_store',
            ),
          )
          .toList(growable: false);

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async => (await _repository.list(
    statuses: statuses,
    limit: limit,
  )).map(_document).toList(growable: false);

  @override
  Future<List<WarehouseTransferAppCatalogItem>> catalog(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) async => (await _access.catalog(warehouseId, query: query, offset: offset))
      .map(
        (row) => WarehouseTransferAppCatalogItem(
          productId: row.productId,
          variantId: row.variantId,
          name: row.name,
          code: row.code,
          quantity: row.quantity,
          supplierOwnedQuantity: row.supplierOwnedQuantity,
          quantityScale: row.quantityScale,
          measurementType: row.measurementType,
        ),
      )
      .toList(growable: false);

  @override
  Future<WarehouseTransferAppDocument> create({
    required String requestKey,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required List<WarehouseTransferAppLine> lines,
    String notes = '',
  }) async {
    final ownershipByVariant = <int, WarehouseTransferOwnershipIntent>{};
    for (final line in lines) {
      final ownership = line.ownershipIntent();
      if (ownership != null) ownershipByVariant[line.variantId] = ownership;
    }
    final source = await WarehouseOperationScope.resolve(
      _preflight.db,
      warehouseId: sourceWarehouseId,
    );
    final destination = await WarehouseOperationScope.resolve(
      _preflight.db,
      warehouseId: destinationWarehouseId,
    );
    final preview = await _preflight.preview(
      source: source,
      destination: destination,
      lines: [
        for (final line in lines)
          WarehouseTransferRequestLine(
            productId: line.productId,
            variantId: line.variantId,
            quantity: line.quantity,
          ),
      ],
    );
    return _document(
      await _repository.create(
        requestKey: requestKey,
        preview: preview,
        ownershipByVariant: ownershipByVariant,
        notes: notes,
      ),
    );
  }

  @override
  Future<void> dispatch({
    required String transferId,
    required String requestKey,
  }) async {
    await _dispatch.dispatch(transferId: transferId, requestKey: requestKey);
  }

  @override
  Future<void> cancel({
    required String transferId,
    required String requestKey,
    required String reason,
  }) async {
    await _repository.cancel(
      id: transferId,
      requestKey: requestKey,
      reason: reason,
    );
  }

  @override
  Future<List<WarehouseTransferAppPending>> pending(String transferId) async =>
      (await _receipt.pending(transferId))
          .map(
            (row) => WarehouseTransferAppPending(
              allocationId: row.allocation.id,
              remainingQuantity: row.remainingQuantity,
              quantityScale: row.line.quantityScale,
              productName: row.productName,
              code: row.code,
              ownerType: row.allocation.ownerType,
            ),
          )
          .toList(growable: false);

  @override
  Future<void> receive({
    required String transferId,
    required String requestKey,
    required List<WarehouseTransferAppReceiptItem> items,
    String notes = '',
  }) async {
    await _receipt.receive(
      transferId: transferId,
      requestKey: requestKey,
      notes: notes,
      items: [
        for (final item in items)
          WarehouseTransferReceiptRequestItem(
            allocationId: item.allocationId,
            acceptedQuantity: item.acceptedQuantity,
            damagedQuantity: item.damagedQuantity,
            lostQuantity: item.lostQuantity,
          ),
      ],
    );
  }

  @override
  Future<void> recall({
    required String transferId,
    required String requestKey,
    required String reason,
  }) async {
    await _recall.recall(
      transferId: transferId,
      requestKey: requestKey,
      reason: reason,
    );
  }
}

class RemoteWarehouseTransferApplicationService
    implements WarehouseTransferApplicationService {
  const RemoteWarehouseTransferApplicationService(
    this._network, {
    Future<void> Function(List<LanWarehouseTransferDocument> documents)?
    onTransfersLoaded,
  }) : _onTransfersLoaded = onTransfersLoaded;

  final LanNetworkService _network;
  final Future<void> Function(List<LanWarehouseTransferDocument> documents)?
  _onTransfersLoaded;

  // A workstation connected to a branch server reads that server's native
  // transfer ledger. Distributed-only lifecycle states are composed by the
  // independent branch application service and are not valid filters for the
  // authenticated LAN endpoint.
  static const _remoteStatuses = {
    'draft',
    'in_transit',
    'partially_received',
    'completed',
    'cancelled',
  };

  @override
  bool get remote => true;

  WarehouseTransferAppDocument _document(LanWarehouseTransferDocument row) =>
      WarehouseTransferAppDocument(
        id: row.id,
        sourceWarehouseId: row.sourceWarehouseId,
        destinationWarehouseId: row.destinationWarehouseId,
        status: row.status,
        lineCount: row.lineCount,
        notes: row.notes,
        recalled: row.recalled,
      );

  @override
  Future<List<WarehouseTransferAppWarehouse>> warehouses() async =>
      (await _network.fetchRemoteTransferWarehouses())
          .map(
            (row) => WarehouseTransferAppWarehouse(
              id: row.id,
              code: row.code,
              name: row.name,
              branchName: row.branchName,
              isLocal: row.canSource,
              isBranchLocation: row.isBranchLocation,
            ),
          )
          .toList(growable: false);

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async {
    final supportedStatuses = statuses.intersection(_remoteStatuses);
    if (supportedStatuses.isEmpty) return const [];
    final rows = await _network.fetchRemoteWarehouseTransfers(
      statuses: supportedStatuses,
      limit: limit,
    );
    await _onTransfersLoaded?.call(rows);
    return rows.map(_document).toList(growable: false);
  }

  @override
  Future<List<WarehouseTransferAppCatalogItem>> catalog(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) async =>
      (await _network.fetchRemoteWarehouseTransferCatalog(
            warehouseId: warehouseId,
            query: query,
            offset: offset,
          ))
          .map(
            (row) => WarehouseTransferAppCatalogItem(
              productId: row.productId,
              variantId: row.variantId,
              name: row.name,
              code: row.code,
              quantity: row.quantity,
              supplierOwnedQuantity: row.supplierOwnedQuantity,
              quantityScale: row.quantityScale,
              measurementType: row.measurementType,
            ),
          )
          .toList(growable: false);

  @override
  Future<WarehouseTransferAppDocument> create({
    required String requestKey,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required List<WarehouseTransferAppLine> lines,
    String notes = '',
  }) async {
    for (final line in lines) {
      line.ownershipIntent();
    }
    return _document(
      await _network.submitRemoteWarehouseTransfer(
        LanWarehouseTransferCreateRequest(
          requestKey: requestKey,
          sourceWarehouseId: sourceWarehouseId,
          destinationWarehouseId: destinationWarehouseId,
          notes: notes,
          lines: [
            for (final line in lines)
              LanWarehouseTransferLineRequest(
                productId: line.productId,
                variantId: line.variantId,
                quantity: line.quantity,
                ownedQuantity: line.ownedQuantity,
                consignmentQuantity: line.consignmentQuantity,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> dispatch({
    required String transferId,
    required String requestKey,
  }) async {
    await _network.dispatchRemoteWarehouseTransfer(
      transferId: transferId,
      requestKey: requestKey,
    );
  }

  @override
  Future<void> cancel({
    required String transferId,
    required String requestKey,
    required String reason,
  }) async {
    await _network.cancelRemoteWarehouseTransfer(
      transferId: transferId,
      request: LanWarehouseTransferReasonRequest(
        requestKey: requestKey,
        reason: reason,
      ),
    );
  }

  @override
  Future<List<WarehouseTransferAppPending>> pending(String transferId) async =>
      (await _network.fetchRemoteWarehouseTransferPending(transferId))
          .map(
            (row) => WarehouseTransferAppPending(
              allocationId: row.allocationId,
              remainingQuantity: row.remainingQuantity,
              quantityScale: row.quantityScale,
              productName: row.productName,
              code: row.code,
              ownerType: row.ownerType,
            ),
          )
          .toList(growable: false);

  @override
  Future<void> receive({
    required String transferId,
    required String requestKey,
    required List<WarehouseTransferAppReceiptItem> items,
    String notes = '',
  }) async {
    await _network.receiveRemoteWarehouseTransfer(
      transferId: transferId,
      request: LanWarehouseTransferReceiptRequest(
        requestKey: requestKey,
        notes: notes,
        items: [
          for (final item in items)
            LanWarehouseTransferReceiptItemRequest(
              allocationId: item.allocationId,
              acceptedQuantity: item.acceptedQuantity,
              damagedQuantity: item.damagedQuantity,
              lostQuantity: item.lostQuantity,
            ),
        ],
      ),
    );
  }

  @override
  Future<void> recall({
    required String transferId,
    required String requestKey,
    required String reason,
  }) async {
    await _network.recallRemoteWarehouseTransfer(
      transferId: transferId,
      request: LanWarehouseTransferReasonRequest(
        requestKey: requestKey,
        reason: reason,
      ),
    );
  }
}

/// Presents local and independent-branch transfers as one workflow while
/// routing every mutation to the database that owns its stock.
class BranchWarehouseTransferApplicationService
    implements WarehouseTransferApplicationService {
  const BranchWarehouseTransferApplicationService({
    required LocalWarehouseTransferApplicationService local,
    required DistributedTransferDispatchService outbound,
    required DistributedTransferReceiptService inbound,
  }) : _local = local,
       _outbound = outbound,
       _inbound = inbound;

  final LocalWarehouseTransferApplicationService _local;
  final DistributedTransferDispatchService _outbound;
  final DistributedTransferReceiptService _inbound;

  @override
  bool get remote => false;

  Future<Set<String>> _localWarehouseIds() async =>
      (await _local.warehouses()).map((row) => row.id).toSet();

  @override
  Future<List<WarehouseTransferAppWarehouse>> warehouses() async {
    final local = await _local.warehouses();
    final remote = await _outbound.remoteLocations();
    return List.unmodifiable([
      ...local,
      for (final row in remote)
        WarehouseTransferAppWarehouse(
          id: row.warehouseId,
          code: row.warehouseCode,
          name: row.warehouseName,
          branchName: row.branchName,
          isLocal: false,
          isBranchLocation: row.locationKind == 'branch_store',
        ),
    ]);
  }

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async {
    const localValid = {
      'draft',
      'in_transit',
      'partially_received',
      'completed',
      'cancelled',
    };
    const inboundValid = {
      'in_transit',
      'partially_received',
      'completed',
      'recalled',
      'conflict',
    };
    final localStatuses = statuses.intersection(localValid);
    final inboundStatuses = statuses.intersection(inboundValid);
    final result = <WarehouseTransferAppDocument>[];
    if (localStatuses.isNotEmpty) {
      result.addAll(await _local.list(statuses: localStatuses, limit: limit));
    }
    result.addAll([
      for (final row in await _outbound.list(statuses, limit: limit))
        WarehouseTransferAppDocument(
          id: row.transferId,
          sourceWarehouseId: row.sourceWarehouseId,
          destinationWarehouseId: row.destinationWarehouseId,
          status: row.status,
          lineCount: row.lineCount,
          notes: row.notes,
          recalled: row.recalled,
          flow: WarehouseTransferDocumentFlow.outbound,
        ),
    ]);
    if (inboundStatuses.isNotEmpty) {
      result.addAll([
        for (final row in await _inbound.documents(
          inboundStatuses,
          limit: limit,
        ))
          WarehouseTransferAppDocument(
            id: row.transferId,
            sourceWarehouseId: row.sourceWarehouseId,
            destinationWarehouseId: row.destinationWarehouseId,
            status: row.status,
            lineCount: row.lineCount,
            notes: '',
            recalled: row.status == 'recalled',
            flow: WarehouseTransferDocumentFlow.inbound,
          ),
      ]);
    }
    final unique = <String, WarehouseTransferAppDocument>{};
    for (final document in result) {
      unique.putIfAbsent(document.id, () => document);
    }
    return List.unmodifiable(unique.values.take(limit));
  }

  @override
  Future<List<WarehouseTransferAppCatalogItem>> catalog(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) async {
    if (!(await _localWarehouseIds()).contains(warehouseId)) {
      throw StateError('A transfer source must belong to this branch');
    }
    return _local.catalog(warehouseId, query: query, offset: offset);
  }

  @override
  Future<WarehouseTransferAppDocument> create({
    required String requestKey,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required List<WarehouseTransferAppLine> lines,
    String notes = '',
  }) async {
    final localIds = await _localWarehouseIds();
    if (!localIds.contains(sourceWarehouseId)) {
      throw StateError('A transfer source must belong to this branch');
    }
    if (localIds.contains(destinationWarehouseId)) {
      return _local.create(
        requestKey: requestKey,
        sourceWarehouseId: sourceWarehouseId,
        destinationWarehouseId: destinationWarehouseId,
        lines: lines,
        notes: notes,
      );
    }
    final row = await _outbound.create(
      requestKey: requestKey,
      sourceWarehouseId: sourceWarehouseId,
      destinationWarehouseId: destinationWarehouseId,
      notes: notes,
      lines: [
        for (final line in lines)
          DistributedTransferLineInput(
            productId: line.productId,
            variantId: line.variantId,
            quantity: line.quantity,
            ownedQuantity: line.ownedQuantity,
            consignmentQuantity: line.consignmentQuantity,
          ),
      ],
    );
    return WarehouseTransferAppDocument(
      id: row.transferId,
      sourceWarehouseId: row.sourceWarehouseId,
      destinationWarehouseId: row.destinationWarehouseId,
      status: row.status,
      lineCount: row.lineCount,
      notes: row.notes,
      recalled: row.recalled,
      flow: WarehouseTransferDocumentFlow.outbound,
    );
  }

  @override
  Future<void> dispatch({
    required String transferId,
    required String requestKey,
  }) async => await _outbound.owns(transferId)
      ? _outbound.dispatch(transferId: transferId, requestKey: requestKey)
      : _local.dispatch(transferId: transferId, requestKey: requestKey);

  @override
  Future<void> cancel({
    required String transferId,
    required String requestKey,
    required String reason,
  }) async => await _outbound.owns(transferId)
      ? _outbound.cancel(
          transferId: transferId,
          requestKey: requestKey,
          reason: reason,
        )
      : _local.cancel(
          transferId: transferId,
          requestKey: requestKey,
          reason: reason,
        );

  @override
  Future<List<WarehouseTransferAppPending>> pending(String transferId) async {
    if (!await _inbound.owns(transferId)) return _local.pending(transferId);
    return [
      for (final row in await _inbound.pending(transferId))
        WarehouseTransferAppPending(
          allocationId: row.allocationId,
          remainingQuantity: row.remainingQuantity,
          quantityScale: row.quantityScale,
          productName: row.productName,
          code: row.code,
          ownerType: row.ownerType,
        ),
    ];
  }

  @override
  Future<void> receive({
    required String transferId,
    required String requestKey,
    required List<WarehouseTransferAppReceiptItem> items,
    String notes = '',
  }) async {
    if (!await _inbound.owns(transferId)) {
      return _local.receive(
        transferId: transferId,
        requestKey: requestKey,
        items: items,
        notes: notes,
      );
    }
    await _inbound.receive(
      transferId: transferId,
      requestKey: requestKey,
      notes: notes,
      items: [
        for (final item in items)
          DistributedTransferReceiptItemRequest(
            allocationId: item.allocationId,
            acceptedQuantity: item.acceptedQuantity,
            damagedQuantity: item.damagedQuantity,
            lostQuantity: item.lostQuantity,
            varianceResponsibility: item.varianceResponsibility,
            liabilityUnitCents: item.liabilityUnitCents,
          ),
      ],
    );
  }

  @override
  Future<void> recall({
    required String transferId,
    required String requestKey,
    required String reason,
  }) async => await _outbound.owns(transferId)
      ? _outbound.recall(
          transferId: transferId,
          requestKey: requestKey,
          reason: reason,
        )
      : _local.recall(
          transferId: transferId,
          requestKey: requestKey,
          reason: reason,
        );
}

class AdaptiveWarehouseTransferApplicationService
    implements WarehouseTransferApplicationService {
  const AdaptiveWarehouseTransferApplicationService({
    required WarehouseTransferApplicationService local,
    required WarehouseTransferApplicationService remote,
    required LanNetworkService network,
    Future<String> Function()? localWarehouseId,
  }) : _local = local,
       _remote = remote,
       _network = network,
       _localWarehouseId = localWarehouseId;

  final WarehouseTransferApplicationService _local;
  final WarehouseTransferApplicationService _remote;
  final LanNetworkService _network;
  final Future<String> Function()? _localWarehouseId;

  WarehouseTransferApplicationService get _delegate =>
      _network.snapshot.mode == LanMode.client ? _remote : _local;

  @override
  bool get remote => _delegate.remote;

  @override
  Future<List<WarehouseTransferAppWarehouse>> warehouses() =>
      _delegate.warehouses();

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async {
    final rows = await _delegate.list(statuses: statuses, limit: limit);
    if (_network.snapshot.mode == LanMode.client) {
      final warehouseId = _network.snapshot.assignedWarehouseId;
      return rows
          .map((row) => row.viewedFrom(warehouseId))
          .toList(growable: false);
    }
    final resolve = _localWarehouseId;
    if (resolve == null) return rows;
    final warehouseId = await resolve();
    return rows
        .map((row) => row.viewedFrom(warehouseId, management: true))
        .toList(growable: false);
  }

  @override
  Future<List<WarehouseTransferAppCatalogItem>> catalog(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) => _delegate.catalog(warehouseId, query: query, offset: offset);

  @override
  Future<WarehouseTransferAppDocument> create({
    required String requestKey,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required List<WarehouseTransferAppLine> lines,
    String notes = '',
  }) => _delegate.create(
    requestKey: requestKey,
    sourceWarehouseId: sourceWarehouseId,
    destinationWarehouseId: destinationWarehouseId,
    lines: lines,
    notes: notes,
  );

  @override
  Future<void> dispatch({
    required String transferId,
    required String requestKey,
  }) => _delegate.dispatch(transferId: transferId, requestKey: requestKey);

  @override
  Future<void> cancel({
    required String transferId,
    required String requestKey,
    required String reason,
  }) => _delegate.cancel(
    transferId: transferId,
    requestKey: requestKey,
    reason: reason,
  );

  @override
  Future<List<WarehouseTransferAppPending>> pending(String transferId) =>
      _delegate.pending(transferId);

  @override
  Future<void> receive({
    required String transferId,
    required String requestKey,
    required List<WarehouseTransferAppReceiptItem> items,
    String notes = '',
  }) => _delegate.receive(
    transferId: transferId,
    requestKey: requestKey,
    items: items,
    notes: notes,
  );

  @override
  Future<void> recall({
    required String transferId,
    required String requestKey,
    required String reason,
  }) => _delegate.recall(
    transferId: transferId,
    requestKey: requestKey,
    reason: reason,
  );
}
