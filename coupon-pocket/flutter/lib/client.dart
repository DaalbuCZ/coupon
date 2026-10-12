import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'wire.dart';
import 'transport.dart' as transport;

abstract class Store {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clear();
}

class MemoryStore implements Store {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> clear() async {
    values.clear();
  }
}

class SecureStore implements Store {
  final storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
  @override
  Future<void> clear() => storage.deleteAll();
}

class SerialQueue {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }
}

class Client {
  static final worker = SerialQueue();
  static const callback = 'com.lidlplus.app://callback';
  static const base = 'https://coupons.lidlplus.com/app/api/';
  final Store store;
  final Send send;
  final DateTime Function() clock;
  Client(this.store, {Send? send, DateTime Function()? clock})
    : send = send ?? transport.send,
      clock = clock ?? DateTime.now;
  Future<Json> load(String key) async =>
      object(jsonDecode(await store.read(key) ?? '{}'));
  String country = 'CZ', language = 'cs-CZ', storeId = '';
  bool hideOnline = false, pictures = true;
  void validateLocale() {
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country) ||
        !RegExp(r'^[a-z]{2,3}(-[A-Z]{2})?$').hasMatch(language)) {
      throw const FormatException(
        'Use a country such as CZ and a language such as cs-CZ.',
      );
    }
  }

  Future<void> init() async {
    final p = await load('settings');
    country = string(p['country'], 'CZ');
    language = string(p['language'], 'cs-CZ');
    storeId = string(p['store']);
    hideOnline = p['hideOnline'] == true;
    pictures = p['pictures'] != false;
    validateLocale();
  }

  Future<void> settings() async {
    validateLocale();
    await store.write(
      'settings',
      jsonEncode({
        'country': country,
        'language': language,
        'store': storeId,
        'hideOnline': hideOnline,
        'pictures': pictures,
      }),
    );
  }

  String random() => base64Url
      .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');
  Future<Uri> beginLogin({bool chooseAccount = false}) async {
    validateLocale();
    final verifier = random(), state = random();
    await store.write(
      'pending',
      jsonEncode({
        'verifier': verifier,
        'state': state,
        'created': clock().millisecondsSinceEpoch,
      }),
    );
    return Uri.https('accounts.lidl.com', '/connect/authorize', {
      'client_id': 'LidlPlusNativeClient',
      'response_type': 'code',
      'redirect_uri': callback,
      'scope': 'openid profile offline_access lpprofile lpapis',
      'state': state,
      'nonce': random(),
      'code_challenge': base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', ''),
      'code_challenge_method': 'S256',
      'country_code': country,
      'language': language,
      if (chooseAccount) 'prompt': 'login',
    });
  }

  Future<void> finishLogin(Uri uri) async {
    final pending = await load('pending');
    final age =
        clock().millisecondsSinceEpoch -
        (pending['created'] is int ? pending['created'] as int : 0);
    if (uri.scheme != 'com.lidlplus.app' ||
        uri.host != 'callback' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasFragment ||
        uri.query.length > 20000 ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        string(pending['state']).isEmpty ||
        uri.queryParameters['state'] != pending['state'] ||
        age < 0 ||
        age > 600000) {
      throw const FormatException(
        'Callback does not match a recent login started here.',
      );
    }
    await store.delete('pending');
    if (uri.queryParameters.containsKey('error')) {
      throw const FormatException('Login was cancelled or rejected.');
    }
    final code = uri.queryParameters['code'] ?? '';
    if (code.isEmpty ||
        code.length > 8192 ||
        string(pending['verifier']).isEmpty) {
      throw const FormatException('Invalid login code.');
    }
    final reply = await token({
      'grant_type': 'authorization_code',
      'redirect_uri': callback,
      'code': code,
      'code_verifier': pending['verifier'],
    });
    for (final key in ['session', 'coupons', 'loyalty', 'import']) {
      await store.delete(key);
    }
    await saveTokens(reply.body, '');
  }

  Future<Reply> token(Map<String, String> fields) async {
    final reply = await send(
      'POST',
      Uri.parse('https://accounts.lidl.com/connect/token'),
      {
        'Authorization':
            'Basic ${base64Encode(ascii.encode('LidlPlusNativeClient:secret'))}',
      },
      fields.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&'),
      'application/x-www-form-urlencoded',
    );
    if (!reply.ok) {
      if (fields['grant_type'] == 'refresh_token' &&
          (reply.status == 400 || reply.status == 401)) {
        for (final key in ['session', 'coupons', 'loyalty']) {
          await store.delete(key);
        }
      }
      String code = '';
      try {
        code = string(object(jsonDecode(reply.body))['error']);
      } catch (_) {}
      const errors = {
        'invalid_grant': 'Session expired. Log in again.',
        'invalid_client': 'Client authentication was rejected.',
        'access_denied': 'Login was rejected.',
        'temporarily_unavailable': 'Login service is temporarily unavailable.',
      };
      throw FormatException(
        errors[code] ?? 'Account request failed (HTTP ${reply.status}).',
      );
    }
    return reply;
  }

  Future<void> saveTokens(String body, String oldRefresh) async {
    final result = object(jsonDecode(body));
    final seconds = result['expires_in'] ?? 300;
    if (string(result['access_token']).isEmpty ||
        string(result['token_type']).toLowerCase() != 'bearer' ||
        seconds is! int ||
        seconds <= 0 ||
        seconds > 31536000) {
      throw const FormatException('Unsupported token response.');
    }
    await store.write(
      'session',
      jsonEncode({
        'access_token': result['access_token'],
        'refresh_token': string(result['refresh_token'], oldRefresh),
        'expires': clock().millisecondsSinceEpoch + seconds * 1000,
      }),
    );
  }

  Future<String> access([bool force = false]) async {
    var s = await load('session');
    if (string(s['access_token']).isEmpty) {
      throw const FormatException('Log in first.');
    }
    if (force ||
        (s['expires'] as int? ?? 0) < clock().millisecondsSinceEpoch + 60000) {
      final refresh = string(s['refresh_token']);
      if (refresh.isEmpty) {
        throw const FormatException('Session expired. Log in again.');
      }
      await saveTokens(
        (await token({'grant_type': 'refresh_token', 'refresh_token': refresh}))
            .body,
        refresh,
      );
      s = await load('session');
    }
    return s['access_token'];
  }

  Future<String> request(String method, String url, [String? body]) async {
    validateLocale();
    final headers = {
      'Authorization': 'Bearer ${await access()}',
      'Country': country,
      'Accept-Language': language,
    };
    if (storeId.isNotEmpty && url == '${base}v4/promotionslist') {
      headers['Store-Id'] = storeId;
    }
    var reply = await send(
      method,
      Uri.parse(url),
      headers,
      body,
      body == null ? null : 'application/json',
    );
    if (reply.status == 401 && method == 'GET') {
      headers['Authorization'] = 'Bearer ${await access(true)}';
      reply = await send(method, Uri.parse(url), headers, body, null);
    }
    if (!reply.ok) {
      throw FormatException(
        'Service request failed (HTTP ${reply.status}). No change was confirmed. Refresh before retrying.',
      );
    }
    return reply.body;
  }

  Future<List<Coupon>> list() async {
    final body = await request('GET', '${base}v4/promotionslist');
    final coupons = Coupon.parse(body);
    await store.write(
      'coupons',
      jsonEncode({
        'body': body,
        'saved': clock().millisecondsSinceEpoch,
        'country': country,
        'language': language,
        'store': storeId,
      }),
    );
    return coupons;
  }

  Future<Detail> detail(String id, [String section = 'Coupons']) async =>
      Detail(
        object(
          jsonDecode(
            await request(
              'GET',
              '${base}v4/promotionsdetails/${Uri.encodeComponent(id)}',
            ),
          ),
        ),
        id,
        section,
      );
  Future<void> mutate(
    Detail confirmed,
    bool activate,
    Map<String, String> choices,
  ) async {
    final fresh = await detail(confirmed.id, confirmed.section);
    fresh.available(clock());
    if (fresh.activated != confirmed.activated) {
      throw const FormatException('Coupon state changed. Refresh first.');
    }
    final body = activate ? fresh.selection(choices) : null;
    await store.delete('coupons');
    final override = activate && fresh.activated;
    await request(
      override
          ? 'PATCH'
          : activate
          ? 'POST'
          : 'DELETE',
      override
          ? '${base}v4/overrides/discount/${Uri.encodeComponent(fresh.id)}'
          : '${base}v2/promotions/${Uri.encodeComponent(fresh.id)}/activation',
      activate ? body : null,
    );
  }

  Future<String> card() async {
    final id = loyalty(
      await request(
        'GET',
        'https://profile.lidlplus.com/api/v1/$country/loyalty',
      ),
    );
    await store.write('loyalty', jsonEncode({'id': id, 'country': country}));
    return id;
  }
}

class BatchResult {
  int activated = 0, skipped = 0, choices = 0;
  bool cancelled = false;
  Object? failure;
}

Future<BatchResult> bulk(
  Client api,
  List<Coupon> confirmed,
  bool hideOnline,
  bool Function() cancelled,
) async {
  final result = BatchResult();
  final ids = confirmed
      .where((c) => !c.activated && !c.processing && (!hideOnline || !c.online))
      .map((c) => c.id)
      .toSet();
  final seen = <String>{};
  try {
    if (cancelled()) {
      result.cancelled = true;
      return result;
    }
    if (ids.isEmpty) return result;
    for (final c in await api.list()) {
      if (!ids.contains(c.id) || !seen.add(c.id)) continue;
      if (cancelled()) {
        result.cancelled = true;
        break;
      }
      if (c.activated || c.processing || (hideOnline && c.online)) {
        result.skipped++;
        continue;
      }
      final d = await api.detail(c.id, c.section);
      if (d.activated || (hideOnline && d.online)) {
        result.skipped++;
        continue;
      }
      try {
        d.available(api.clock());
      } on FormatException {
        result.skipped++;
        continue;
      }
      if (d.groups.isNotEmpty) {
        result.skipped++;
        result.choices++;
        continue;
      }
      if (cancelled()) {
        result.cancelled = true;
        break;
      }
      await api.store.delete('coupons');
      await api.request(
        'POST',
        '${Client.base}v2/promotions/${Uri.encodeComponent(d.id)}/activation',
        '{"articleSelection":[]}',
      );
      result.activated++;
    }
    if (!result.cancelled) result.skipped += ids.length - seen.length;
  } catch (e) {
    result.failure = e;
  }
  return result;
}

class AndroidStore implements Store {
  static const channel = MethodChannel('coupon_pocket/vault');
  @override
  Future<String?> read(String key) =>
      channel.invokeMethod<String>('read', {'key': key});
  @override
  Future<void> write(String key, String value) =>
      channel.invokeMethod<void>('write', {'key': key, 'value': value});
  @override
  Future<void> delete(String key) =>
      channel.invokeMethod<void>('delete', {'key': key});
  @override
  Future<void> clear() => channel.invokeMethod<void>('clear');
}

Store defaultStore() => kIsWeb
    ? MemoryStore()
    : defaultTargetPlatform == TargetPlatform.android
    ? AndroidStore()
    : SecureStore();
