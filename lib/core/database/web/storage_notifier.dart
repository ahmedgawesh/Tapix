import 'package:flutter/foundation.dart';

/// Represents the persistence tier being used by the WASM database.
enum StorageTier {
  opfs,
  indexedDb,
  memory,
}

/// Broadcasts storage degradation notifications so the UI can inform users
/// whenever the browser falls back from OPFS to IndexedDB or in-memory storage.
class StorageNotifier {
  StorageNotifier._();

  static final ValueNotifier<StorageTier> tier =
      ValueNotifier<StorageTier>(StorageTier.opfs);

  static void update(StorageTier nextTier) {
    if (tier.value != nextTier) {
      tier.value = nextTier;
    }
  }
}
