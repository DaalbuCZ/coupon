import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/models.dart';
import 'package:coupon_pocket/wire.dart';

final now = DateTime.utc(2026, 10, 12, 12);
Json promotion(
  String id, {
  bool active = false,
  bool processing = false,
  dynamic groups,
  String? channel,
}) => {
  'id': id,
  'title': id,
  'isActivated': active,
  'isProcessing': processing,
  'groups': ?groups,
  'channel': ?channel,
};
String listing(List<Json> coupons, [String section = 'Coupons']) => jsonEncode({
  'sections': [
    {'name': section, 'promotions': coupons},
  ],
});

class Call {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body, type;
  Call(this.method, this.url, Map<String, String> headers, this.body, this.type)
    : headers = Map.of(headers);
}

class Fake {
  final calls = <Call>[];
  final Store store;
  Future<Reply> Function(Call) handler;
  Fake(this.store, this.handler);
  Future<Reply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    String? type,
  ) async {
    final call = Call(method, uri, headers, body, type);
    calls.add(call);
    return handler(call);
  }
}

Future<MemoryStore> session() async {
  final store = MemoryStore();
  await store.write(
    'session',
    jsonEncode({
      'access_token': 'fake-access',
      'refresh_token': 'fake-refresh',
      'expires': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    }),
  );
  return store;
}

final groups = [
  {
    'id': 'g',
    'articles': [
      {'id': 'a', 'title': 'A'},
      {'id': 'b', 'title': 'B'},
    ],
  },
];
void main() {
  test(
    'literal list/detail/activation/override URLs and scoped headers',
    () async {
      final store = await session();
      final fake = Fake(store, (c) async {
        if (c.url.path.endsWith('promotionslist')) {
          return Reply(200, listing([promotion('a b')]));
        }
        if (c.method == 'GET') {
          return Reply(200, jsonEncode(promotion('a b', groups: groups)));
        }
        expect(await store.read('coupons'), isNull);
        return Reply(204, '');
      });
      final api = Client(store, send: fake.send, clock: () => now)
        ..storeId = 'store';
      await api.list();
      final d = await api.detail('a b');
      await api.mutate(d, true, {'g': 'b'});
      expect(
        fake.calls[0].url.toString(),
        'https://coupons.lidlplus.com/app/api/v4/promotionslist',
      );
      expect(
        fake.calls[1].url.toString(),
        'https://coupons.lidlplus.com/app/api/v4/promotionsdetails/a%20b',
      );
      expect(
        fake.calls.last.url.toString(),
        'https://coupons.lidlplus.com/app/api/v2/promotions/a%20b/activation',
      );
      expect(fake.calls.last.type, 'application/json');
      expect(jsonDecode(fake.calls.last.body!), {
        'articleSelection': [
          {'groupId': 'g', 'articleId': 'b'},
        ],
      });
      expect(fake.calls.first.headers['Store-Id'], 'store');
      expect(
        fake.calls.skip(1).every((c) => !c.headers.containsKey('Store-Id')),
        isTrue,
      );
      expect(
        fake.calls.every(
          (c) => c.headers['Authorization'] == 'Bearer fake-access',
        ),
        isTrue,
      );
    },
  );
  for (final method in ['POST', 'PATCH', 'DELETE']) {
    for (final uncertain in ['401', 'timeout']) {
      test('$method never replays after $uncertain', () async {
        final store = await session();
        final fake = Fake(store, (_) async {
          if (uncertain == 'timeout') throw StateError('fake timeout');
          return Reply(401, '');
        });
        final api = Client(store, send: fake.send, clock: () => now);
        await expectLater(
          api.request(
            method,
            '${Client.base}v2/promotions/a/activation',
            method == 'DELETE' ? null : '{"articleSelection":[]}',
          ),
          throwsA(anything),
        );
        expect(fake.calls.length, 1);
      });
    }
  }
  test('GET refreshes once with Basic only on token route', () async {
    final store = await session();
    var reads = 0;
    final fake = Fake(store, (c) async {
      if (c.url.host == 'accounts.lidl.com') {
        expect(
          c.headers['Authorization'],
          'Basic TGlkbFBsdXNOYXRpdmVDbGllbnQ6c2VjcmV0',
        );
        expect(Uri.splitQueryString(c.body!), {
          'grant_type': 'refresh_token',
          'refresh_token': 'fake-refresh',
        });
        return Reply(
          200,
          '{"access_token":"new","token_type":"Bearer","expires_in":3600}',
        );
      }
      reads++;
      return Reply(reads == 1 ? 401 : 200, listing([]));
    });
    await Client(store, send: fake.send, clock: () => now).list();
    expect(fake.calls.length, 3);
    expect(fake.calls.last.headers['Authorization'], 'Bearer new');
  });
  test('PKCE callback consumes state and clears prior account cache/cards', () async {
    final store = await session();
    final fake = Fake(store, (c) async {
      expect(Uri.splitQueryString(c.body!).containsKey('client_id'), isFalse);
      return Reply(
        200,
        '{"access_token":"new","token_type":"Bearer","expires_in":3600}',
      );
    });
    final api = Client(store, send: fake.send, clock: () => now);
    final authorize = await api.beginLogin();
    expect(authorize.queryParameters['code_challenge_method'], 'S256');
    expect(authorize.queryParameters['redirect_uri'], Client.callback);
    for (final key in ['coupons', 'loyalty', 'import']) {
      await store.write(key, 'old');
    }
    final callback = Uri.parse(
      '${Client.callback}?state=${authorize.queryParameters['state']}&code=fake',
    );
    await api.finishLogin(callback);
    expect(await store.read('pending'), isNull);
    for (final key in ['coupons', 'loyalty', 'import']) {
      expect(await store.read(key), isNull);
    }
    await expectLater(api.finishLogin(callback), throwsFormatException);
    expect(fake.calls.length, 1);
  });
  for (final suffix in ['&state=duplicate', '#fragment', '&code=duplicate']) {
    test('callback rejects $suffix', () async {
      final store = MemoryStore();
      final api = Client(
        store,
        send: (_, _, _, _, _) async => throw StateError('must not send'),
        clock: () => now,
      );
      final url = await api.beginLogin();
      await expectLater(
        api.finishLogin(
          Uri.parse(
            '${Client.callback}?state=${url.queryParameters['state']}&code=fake$suffix',
          ),
        ),
        throwsFormatException,
      );
    });
  }
  test('expired callback rejected without exchange', () async {
    final store = MemoryStore();
    var time = now;
    final api = Client(
      store,
      send: (_, _, _, _, _) async => throw StateError('must not send'),
      clock: () => time,
    );
    final url = await api.beginLogin();
    time = time.add(const Duration(minutes: 11));
    await expectLater(
      api.finishLogin(
        Uri.parse(
          '${Client.callback}?state=${url.queryParameters['state']}&code=fake',
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'provider diagnostics never expose descriptions or unknown codes',
    () async {
      final store = MemoryStore();
      final api = Client(
        store,
        send: (_, _, _, _, _) async => Reply(
          400,
          '{"error":"private-code","error_description":"private-secret"}',
        ),
      );
      try {
        await api.token({'grant_type': 'refresh_token'});
        fail('expected failure');
      } on FormatException catch (e) {
        expect(e.message, isNot(contains('private')));
      }
    },
  );
  test('choices validate against reread membership before mutation', () async {
    final store = await session();
    final original = Detail(promotion('a', groups: groups), 'a');
    final changed = [
      {
        'id': 'g',
        'articles': [
          {'id': 'new'},
        ],
      },
    ];
    final fake = Fake(
      store,
      (_) async => Reply(200, jsonEncode(promotion('a', groups: changed))),
    );
    await expectLater(
      Client(
        store,
        send: fake.send,
        clock: () => now,
      ).mutate(original, true, {'g': 'a'}),
      throwsFormatException,
    );
    expect(fake.calls.every((c) => c.method == 'GET'), isTrue);
  });
  test('deactivation bodyless even when coupon has choice groups', () async {
    final store = await session();
    final fake = Fake(
      store,
      (c) async => c.method == 'GET'
          ? Reply(200, jsonEncode(promotion('a', active: true, groups: groups)))
          : Reply(204, ''),
    );
    await Client(store, send: fake.send, clock: () => now).mutate(
      Detail(promotion('a', active: true, groups: groups), 'a'),
      false,
      {},
    );
    expect(fake.calls.last.method, 'DELETE');
    expect(fake.calls.last.body, isNull);
    expect(fake.calls.last.type, isNull);
  });
  test('selection update PATCH uses observed override URL', () async {
    final store = await session();
    final fake = Fake(
      store,
      (c) async => c.method == 'GET'
          ? Reply(200, jsonEncode(promotion('a', active: true, groups: groups)))
          : Reply(204, ''),
    );
    await Client(store, send: fake.send, clock: () => now).mutate(
      Detail(promotion('a', active: true, groups: groups), 'a'),
      true,
      {'g': 'a'},
    );
    expect(fake.calls.last.method, 'PATCH');
    expect(
      fake.calls.last.url.toString(),
      'https://coupons.lidlplus.com/app/api/v4/overrides/discount/a',
    );
  });
  test(
    'batch deduplicates, skips choices/online, stops after uncertain mutation',
    () async {
      final store = await session();
      final list = [
        promotion('a'),
        promotion('a'),
        promotion('choices', groups: groups),
        promotion('online', channel: 'ONLINESHOP'),
        promotion('fail'),
        promotion('after'),
      ];
      final fake = Fake(store, (c) async {
        if (c.url.path.endsWith('promotionslist')) {
          return Reply(200, listing(list));
        }
        if (c.method == 'GET') {
          return Reply(
            200,
            jsonEncode(
              list.firstWhere((p) => c.url.path.endsWith('/${p['id']}')),
            ),
          );
        }
        expect(await store.read('coupons'), isNull);
        expect(c.body, '{"articleSelection":[]}');
        expect(c.type, 'application/json');
        if (c.url.path.contains('/fail/')) throw StateError('uncertain');
        return Reply(204, '');
      });
      final result = await bulk(
        Client(store, send: fake.send, clock: () => now),
        list.map((p) => Coupon(p)).toList(),
        true,
        () => false,
      );
      expect(result.activated, 1);
      expect(result.choices, 1);
      expect(result.failure, isNotNull);
      expect(fake.calls.where((c) => c.method == 'POST').length, 2);
      expect(fake.calls.any((c) => c.url.path.contains('/after')), isFalse);
    },
  );
  test('batch cancels remaining after in-flight request', () async {
    final store = await session();
    var cancelled = false;
    final list = [promotion('a'), promotion('b')];
    final fake = Fake(store, (c) async {
      if (c.url.path.endsWith('promotionslist')) {
        return Reply(200, listing(list));
      }
      if (c.method == 'GET') return Reply(200, jsonEncode(promotion('a')));
      cancelled = true;
      return Reply(204, '');
    });
    final result = await bulk(
      Client(store, send: fake.send, clock: () => now),
      list.map((p) => Coupon(p)).toList(),
      false,
      () => cancelled,
    );
    expect(result.activated, 1);
    expect(result.cancelled, isTrue);
    expect(fake.calls.where((c) => c.method == 'POST').length, 1);
  });
  test('loyalty route parses strings and preserves zeros', () async {
    final store = await session();
    final fake = Fake(store, (c) async {
      expect(
        c.url.toString(),
        'https://profile.lidlplus.com/api/v1/CZ/loyalty',
      );
      return Reply(200, '"00123"');
    });
    expect(
      await Client(store, send: fake.send, clock: () => now).card(),
      '00123',
    );
    expect(loyalty('00123'), '00123');
    expect(() => loyalty('{"id":"00123"}'), throwsFormatException);
  });
  test('explicit store wins and mixed channel stays visible', () {
    expect(
      Coupon(promotion('a', channel: 'STORE'), 'ONLINESHOP').online,
      isFalse,
    );
    expect(
      Coupon({
        ...promotion('b'),
        'channels': ['ONLINESHOP', 'STORE'],
      }, 'ONLINESHOP').online,
      isFalse,
    );
    expect(Coupon(promotion('c'), 'ONLINESHOP').online, isTrue);
  });
  test('expiry display retains server calendar day', () {
    final c = Coupon({
      ...promotion('a'),
      'validity': {'end': '2026-10-13T00:30:00+14:00'},
    });
    expect(c.expiry('en-US'), 'Valid until Oct 13, 2026');
  });
  for (final flag in ['isRedeemed', 'isProcessing']) {
    test(
      'eligibility rejects $flag',
      () => expect(
        () => Detail({...promotion('a'), flag: true}, 'a').available(now),
        throwsFormatException,
      ),
    );
  }
  test('eligibility rejects expired, future and malformed timestamps', () {
    for (final v in [
      {'end': '2026-10-11T00:00:00Z'},
      {'start': '2026-10-13T00:00:00Z'},
      {'end': '2026-10-13'},
    ]) {
      expect(
        () => Detail({...promotion('a'), 'validity': v}, 'a').available(now),
        throwsFormatException,
      );
    }
  });
  test('serial queue continues after failure and preserves ordering', () async {
    final q = SerialQueue(), events = <int>[];
    final first = q.run(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      events.add(1);
      throw const FormatException('fake');
    });
    final second = q.run(() async {
      events.add(2);
    });
    await expectLater(first, throwsFormatException);
    await second;
    expect(events, [1, 2]);
  });
  test('network allowlist rejects credentials, redirects targets and wrong profile path', () {
    for (final url in [
      'http://accounts.lidl.com/connect/token',
      'https://evil.test/',
      'https://user@accounts.lidl.com/',
      'https://profile.lidlplus.com/api/v1/CZ/profile',
      'https://profile.lidlplus.com/api/v1/CZ/loyalty?q=x',
    ]) {
      expect(() => allow(Uri.parse(url)), throwsFormatException);
    }
  });
}
