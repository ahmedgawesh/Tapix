import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/business/warehouse_transfer_preflight.dart';
import '../../../core/services/lan/lan_network_service.dart';
import 'warehouse_transfer_access_service.dart';
import 'warehouse_transfer_dispatch_service.dart';
import 'warehouse_transfer_receipt_service.dart';
import 'warehouse_transfer_recall_service.dart';
import 'warehouse_transfer_repository.dart';

class WarehouseTransferAppWarehouse {
  const WarehouseTransferAppWarehouse({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;
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

  int parseQuantity(String input) {
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
    if (amount <= BigInt.zero || amount > BigInt.from(quantity)) {
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
  });

  final int productId;
  final int variantId;
  final int quantity;
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
  });

  final String id;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final String status;
  final int lineCount;
  final String notes;
  final bool recalled;
}

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
  });

  final String allocationId;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int lostQuantity;
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
              id: row.id,
              code: row.code,
              name: row.name,
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
  const RemoteWarehouseTransferApplicationService(this._network);

  final LanNetworkService _network;

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
            ),
          )
          .toList(growable: false);

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async => (await _network.fetchRemoteWarehouseTransfers(
    statuses: statuses,
    limit: limit,
  )).map(_document).toList(growable: false);

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
  }) async => _document(
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
            ),
        ],
      ),
    ),
  );

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

class AdaptiveWarehouseTransferApplicationService
    implements WarehouseTransferApplicationService {
  const AdaptiveWarehouseTransferApplicationService({
    required WarehouseTransferApplicationService local,
    required WarehouseTransferApplicationService remote,
    required LanNetworkService network,
  }) : _local = local,
       _remote = remote,
       _network = network;

  final WarehouseTransferApplicationService _local;
  final WarehouseTransferApplicationService _remote;
  final LanNetworkService _network;

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
  }) => _delegate.list(statuses: statuses, limit: limit);

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
