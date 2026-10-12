import 'dart:convert';
import 'dart:io';

import 'wire.dart';

Future<Reply> send(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
  String? contentType,
) async {
  allow(url);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.openUrl(method, url);
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    request.headers.set('User-Agent', 'CouponPocket/0.5.1');
    if (body != null) {
      request.headers.set('Content-Type', contentType!);
      request.add(utf8.encode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.isRedirect) {
      throw const FormatException('Service redirect blocked.');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) {
        throw const FormatException('Response is too large.');
      }
    }
    return Reply(response.statusCode, utf8.decode(bytes));
  } finally {
    client.close(force: true);
  }
}
