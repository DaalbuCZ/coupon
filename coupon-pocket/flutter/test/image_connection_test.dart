import 'dart:async';
import 'dart:io';

import 'package:coupon_pocket/image_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pinned image connection starts TLS and rejects a plaintext server', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final hello = Completer<List<int>>();
    final subscription = server.listen((peer) {
      peer.listen((bytes) {
        if (!hello.isCompleted) hello.complete(bytes);
        peer.destroy();
      });
    });
    try {
      final raw = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final result = imageTls(raw, 'cdn.example.test');
      final failure = expectLater(result, throwsA(isA<HandshakeException>()));
      final bytes = await hello.future.timeout(const Duration(seconds: 3));
      // TLS handshake record and TLS major version, rather than plaintext GET.
      expect(bytes.take(2), [22, 3]);
      expect(String.fromCharCodes(bytes), isNot(startsWith('GET')));
      await failure;
    } finally {
      await subscription.cancel();
      await server.close();
    }
  });
}
