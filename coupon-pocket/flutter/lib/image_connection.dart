import 'dart:io';

// The caller pins the TCP socket to a checked public IP. Upgrade that same
// socket, keeping the URL hostname for TLS SNI and certificate verification.
Future<SecureSocket> imageTls(Socket socket, String host) async {
  try {
    return await SecureSocket.secure(
      socket,
      host: host,
    ).timeout(const Duration(seconds: 10));
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}
