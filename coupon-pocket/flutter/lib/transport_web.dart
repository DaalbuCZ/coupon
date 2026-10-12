import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'wire.dart';

Future<Reply> send(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
  String? contentType,
) async {
  allow(url);
  final h = web.Headers();
  h.set('Accept', 'application/json');
  headers.forEach((name, value) => h.set(name, value));
  if (body != null) h.set('Content-Type', contentType!);
  final controller = web.AbortController();
  try {
    final response = await web.window
        .fetch(
          url.toString().toJS,
          web.RequestInit(
            method: method,
            headers: h,
            body: body?.toJS,
            credentials: 'omit',
            redirect: 'error',
            referrerPolicy: 'no-referrer',
            signal: controller.signal,
          ),
        )
        .toDart
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            controller.abort();
            throw const FormatException(
              'Request timed out. Refresh before retrying.',
            );
          },
        );
    final text = (await response.text().toDart).toDart;
    if (text.length > 4 * 1024 * 1024) {
      throw const FormatException('Response is too large.');
    }
    return Reply(response.status, text);
  } catch (_) {
    throw const FormatException(
      'Browser request failed. The service must permit this origin through CORS. No change was confirmed.',
    );
  }
}
