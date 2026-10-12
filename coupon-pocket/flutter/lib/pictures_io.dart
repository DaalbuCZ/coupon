import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

final _cache = <String, Uint8List>{};
int _generation = 0;
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

Future<Uint8List?> picture(String url) async {
  if (_cache.containsKey(url)) return _cache[url];
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
    return Socket.startConnect(addresses.first, uri.port);
  };
  try {
    final request = await client.getUrl(u);
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
    while (_cache.length >= 12) {
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
