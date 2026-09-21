import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_request_body.dart';

void main() {
  test('accepts exactly the byte limit across multiple chunks', () async {
    final bytes = await readLanRequestBody(
      Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]),
      maxBytes: 4,
    );
    expect(bytes, [1, 2, 3, 4]);
  });

  test(
    'rejects and cancels before the sender finishes an oversized body',
    () async {
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final result = readLanRequestBody(stream.stream, maxBytes: 4);
      final expectation = expectLater(
        result,
        throwsA(
          isA<LanRequestBodyException>().having((e) => e.status, 'status', 413),
        ),
      );
      stream.add([1, 2, 3]);
      stream.add([4, 5]);
      await expectation;
      expect(cancelled, isTrue);
      await stream.close();
    },
  );

  test('counts UTF-8 bytes rather than characters', () async {
    await expectLater(
      readLanRequestBody(Stream.value(utf8.encode('ععع')), maxBytes: 4),
      throwsA(
        isA<LanRequestBodyException>().having((e) => e.status, 'status', 413),
      ),
    );
  });

  test(
    'total deadline cancels a body even if the sender stays connected',
    () async {
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final result = readLanRequestBody(
        stream.stream,
        deadline: const Duration(milliseconds: 30),
      );
      final expectation = expectLater(
        result,
        throwsA(
          isA<LanRequestBodyException>().having((e) => e.status, 'status', 408),
        ),
      );
      stream.add([1]);
      await expectation;
      expect(cancelled, isTrue);
      await stream.close();
    },
  );
}
