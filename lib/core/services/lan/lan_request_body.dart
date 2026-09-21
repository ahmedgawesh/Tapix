import 'dart:async';
import 'dart:typed_data';

class LanRequestBodyException implements Exception {
  const LanRequestBodyException(this.status, this.message);
  final int status;
  final String message;
}

/// Bounds bytes while receiving and cancels the stream on size/time violations.
Future<Uint8List> readLanRequestBody(
  Stream<List<int>> stream, {
  int maxBytes = 65536,
  Duration deadline = const Duration(seconds: 5),
}) async {
  final result = Completer<Uint8List>();
  final bytes = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? subscription;
  void fail(Object error, [StackTrace? stack]) {
    if (result.isCompleted) return;
    result.completeError(error, stack);
    unawaited(subscription?.cancel());
  }

  final timer = Timer(
    deadline,
    () => fail(const LanRequestBodyException(408, 'Request body timed out.')),
  );
  subscription = stream.listen(
    (chunk) {
      if (result.isCompleted) return;
      if (bytes.length + chunk.length > maxBytes) {
        fail(const LanRequestBodyException(413, 'Request body is too large.'));
        return;
      }
      bytes.add(chunk);
    },
    onError: fail,
    onDone: () {
      if (!result.isCompleted) result.complete(bytes.takeBytes());
    },
  );
  try {
    return await result.future;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}
