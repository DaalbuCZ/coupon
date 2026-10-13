import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'wire.dart';

import 'package:flutter/services.dart';

Future<Reply> send(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
  String? contentType,
) async {
  allow(url);
  if (Platform.isAndroid && url.host == 'profile.lidlplus.com') {
    return nativeLoyaltyRead(method, url, headers, body);
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.openUrl(method, url);
    request.followRedirects = false;
    request.headers.set('Accept', 'application/json');
    headers.forEach(request.headers.set);
    request.headers.set('User-Agent', 'LidlPlusPlus/0.14.2 (Android)');
    if (body != null) {
      request.headers.set('Content-Type', contentType!);
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
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
  } on HandshakeException {
    throw const FormatException(
      'Secure connection failed. Check the phone network and try again. No change was confirmed.',
    );
  } on SocketException {
    throw const FormatException(
      'Could not connect to the service. Check the phone network. No change was confirmed.',
    );
  } on TimeoutException {
    throw const FormatException(
      'The service timed out. Refresh to check coupon state before retrying.',
    );
  } finally {
    client.close(force: true);
  }
}

// Card reads use the same Android TLS/HTTP implementation as the working Java client.
Future<Reply> nativeLoyaltyRead(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
) async {
  allow(url);
  if (method != 'GET' || body != null || url.host != 'profile.lidlplus.com') {
    throw const FormatException('Unsupported account card request.');
  }
  try {
    final result = await const MethodChannel('coupon_pocket/loyalty')
        .invokeMapMethod<String, dynamic>('get', {
          'url': url.toString(),
          'authorization': headers['Authorization'],
          'country': headers['Country'],
          'language': headers['Accept-Language'],
        });
    if (result == null || result['status'] is! int || result['body'] is! String)
      throw const FormatException('Unsupported account card response.');
    return Reply(result['status'], result['body']);
  } on PlatformException {
    throw const FormatException(
      'Could not load the account card. Check the connection and retry.',
    );
  }
}
