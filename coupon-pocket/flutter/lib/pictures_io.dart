import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'image_connection.dart';

final _cache = <String, Uint8List>{};
final _inFlight = <String, Future<Uint8List?>>{};
final _waiting = Queue<Completer<void>>();
int _active = 0;
int _generation = 0;

/// Persist only a bounded, re-encoded thumbnail, never the source metadata.
Future<Uint8List?> snapshotPicture(String url) async {
  final bytes = await picture(url);
  if (bytes == null) return null;
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  try {
    final scale = math.min(
      1.0,
      400 / math.max(descriptor.width, descriptor.height),
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null || data.lengthInBytes > 512 * 1024) return null;
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

void clearPictures() {
  _generation++;
  _cache.clear();
}

bool _public(InternetAddress a) {
  final b = a.rawAddress;
  if (a.isLoopback || a.isLinkLocal || a.isMulticast) return false;
  if (b.length == 4) {
    return !(b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 198 && (b[1] == 18 || b[1] == 19)));
  }
  if ((b[0] & 254) == 252 || b.every((v) => v == 0)) return false;
  if (b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255) {
    return _public(
      InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))),
    );
  }
  return true;
}

Future<Uint8List?> picture(String url) {
  final cached = _cache.remove(url);
  if (cached != null) {
    _cache[url] = cached;
    return Future.value(cached);
  }
  final generation = _generation;
  final key = '$generation:$url';
  return _inFlight.putIfAbsent(key, () async {
    if (_active < 3) {
      _active++;
    } else {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    }
    try {
      if (generation != _generation) return null;
      return await _downloadPicture(url);
    } finally {
      _inFlight.remove(key);
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  });
}

Future<Uint8List?> _downloadPicture(String url) async {
  final generation = _generation, u = Uri.tryParse(url);
  if (u == null ||
      u.scheme != 'https' ||
      u.port != 443 ||
      u.userInfo.isNotEmpty ||
      u.hasFragment ||
      url.length > 8192 ||
      !u.host.contains('.') ||
      u.host.endsWith('.local') ||
      u.host.endsWith('.localhost')) {
    return null;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (proxyHost != null) throw const SocketException('Image proxy blocked.');
    final addresses = await InternetAddress.lookup(uri.host);
    if (addresses.isEmpty || addresses.any((a) => !_public(a))) {
      throw const SocketException('Local image destination blocked.');
    }
    final task = await Socket.startConnect(addresses.first, uri.port);
    var cancelled = false;
    Socket? connected;
    final secure = task.socket.then((socket) async {
      connected = socket;
      if (cancelled) {
        socket.destroy();
        throw const SocketException('Image connection cancelled.');
      }
      final tls = await imageTls(socket, uri.host);
      connected = tls;
      if (cancelled) {
        tls.destroy();
        throw const SocketException('Image connection cancelled.');
      }
      return tls;
    });
    return ConnectionTask.fromSocket(secure, () {
      cancelled = true;
      task.cancel();
      connected?.destroy();
    });
  };
  try {
    final request = await client.getUrl(u);
    request.headers.set('Accept', 'image/*');
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        !(response.headers.contentType?.mimeType.startsWith('image/') ??
            false)) {
      return null;
    }
    final builder = BytesBuilder();
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      builder.add(chunk);
      if (builder.length > 2 * 1024 * 1024) return null;
    }
    final bytes = builder.takeBytes();
    final encoded = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(encoded);
    final safe =
        descriptor.width <= 8192 &&
        descriptor.height <= 8192 &&
        descriptor.width * descriptor.height <= 16000000;
    descriptor.dispose();
    encoded.dispose();
    if (!safe || generation != _generation) return null;
    while (_cache.isNotEmpty &&
        (_cache.length >= 32 ||
            _cache.values.fold<int>(0, (n, b) => n + b.length) + bytes.length >
                16 * 1024 * 1024)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = bytes;
    return bytes;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
