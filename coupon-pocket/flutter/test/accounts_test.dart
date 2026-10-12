import 'dart:convert';

import 'package:coupon_pocket/accounts.dart';
import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/models.dart';
import 'package:coupon_pocket/wire.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 12);
String session(String token) => jsonEncode({
  'access_token': token,
  'refresh_token': 'refresh-$token',
  'expires': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
});
Json coupon(String id, {bool active = false}) => {
  'id': id,
  'title': id,
  'isActivated': active,
};
String list(List<Json> ps) => jsonEncode({
  'sections': [
    {'promotions': ps},
  ],
});
void main() {
  test('pending login survives recreation, expires and cannot consume a callback after cancellation', () async {
    var clock = now;
    final store = MemoryStore();
    final book = AccountBook(Client(store, clock: () => clock));
    await book.init();
    final a = await book.add('Home');
    final uri = await book.beginLogin(a);
    expect(a.status, 'Waiting for browser');
    final restored = AccountBook(Client(store, clock: () => clock));
    await restored.init();
    expect(restored.accounts.single.awaitingLogin, isTrue);
    clock = now.add(const Duration(minutes: 11));
    await restored.expirePending();
    expect(restored.accounts.single.status, 'Not connected');
    expect(await restored.accounts.single.api.store.read('pending'), isNull);
    await expectLater(
      restored.finishLogin(
        Uri.parse(
          'com.lidlplus.app://callback?code=fake&state=${uri.queryParameters['state']}',
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'dashboard retains last successful sync after a failed read and recreation',
    () async {
      var fail = false;
      final store = MemoryStore();
      final book = AccountBook(
        Client(
          store,
          clock: () => now,
          send: (_, _, _, _, _) async =>
              Reply(fail ? 503 : 200, fail ? '' : list([coupon('one')])),
        ),
      );
      await book.init();
      final a = await book.add('Home');
      await a.api.store.write('session', session('fake'));
      await book.refresh(a);
      expect(a.lastSync, now);
      fail = true;
      await expectLater(book.refresh(a), throwsFormatException);
      expect(a.lastSync, now);
      expect(a.fresh, isFalse);
      await book.init();
      expect(book.accounts.single.lastSync!.toUtc(), now);
    },
  );
  test('existing single-account state migrates once without losing cards or tokens', () async {
    final store = MemoryStore();
    await store.write('session', session('legacy'));
    await store.write('import', '{"id":"TEST-QR-LEGACY","country":"CZ"}');
    await store.write(
      'coupons',
      jsonEncode({
        'country': 'CZ',
        'language': 'cs-CZ',
        'store': '',
        'body': list([coupon('shared')]),
      }),
    );
    final book = AccountBook(Client(store, clock: () => now));
    await book.init();
    expect(book.accounts.length, 1);
    expect(book.accounts.single.card, 'TEST-QR-LEGACY');
    expect(book.accounts.single.coupons.length, 1);
    expect(await store.read('session'), isNull);
    await book.init();
    expect(book.accounts.length, 1);
    expect(
      (await book.accounts.single.api.load('session'))['access_token'],
      'legacy',
    );
  });
  test(
    'profile writes, clears, renames and removals cannot affect other profiles',
    () async {
      final book = AccountBook(Client(MemoryStore()));
      await book.init();
      final a = await book.add('Home'), b = await book.add('Other');
      await Future.wait([
        a.api.store.write('session', session('A')),
        b.api.store.write('session', session('B')),
      ]);
      expect((await a.api.load('session'))['access_token'], 'A');
      expect((await b.api.load('session'))['access_token'], 'B');
      await book.rename(a, 'Renamed');
      expect(a.label, 'Renamed');
      await a.api.store.clear();
      expect((await b.api.load('session'))['access_token'], 'B');
      await book.remove(a);
      expect(book.accounts.single.id, b.id);
      expect((await b.api.load('session'))['access_token'], 'B');
      await expectLater(
        a.api.store.write('session', session('lost')),
        throwsFormatException,
      );
    },
  );
  test('same coupon ID across accounts keeps distinct selection and activation ownership', () async {
    final calls = <String>[];
    final book = AccountBook(
      Client(
        MemoryStore(),
        clock: () => now,
        send: (method, uri, headers, body, type) async {
          final owner = headers['Authorization']!;
          calls.add('$owner:$method:${uri.path}');
          if (uri.path.endsWith('promotionslist')) {
            return Reply(200, list([coupon('shared')]));
          }
          if (method == 'GET') return Reply(200, jsonEncode(coupon('shared')));
          expect(body, '{"articleSelection":[]}');
          return Reply(204, '');
        },
      ),
    );
    await book.init();
    final a = await book.add('A'), b = await book.add('B');
    for (final account in [a, b]) {
      await account.api.store.write('session', session(account.label));
      await book.hydrate(account);
      await book.refresh(account);
    }
    final entries = combined(book.accounts);
    expect(entries.length, 2);
    expect(entries[0].key, isNot(entries[1].key));
    final result = await activateSelected([entries[1]], false, () => false);
    expect(result.activated, 1);
    expect(
      calls.where((c) => c.contains(':POST:')).single,
      startsWith('Bearer B:'),
    );
    expect(a.fresh, isTrue);
    expect(b.fresh, isFalse);
  });
  test(
    'a failing mutation stops remaining accounts and never replays',
    () async {
      final mutations = <String>[];
      final book = AccountBook(
        Client(
          MemoryStore(),
          clock: () => now,
          send: (method, uri, headers, body, type) async {
            if (uri.path.endsWith('promotionslist')) {
              return Reply(200, list([coupon('shared')]));
            }
            if (method == 'GET') {
              return Reply(200, jsonEncode(coupon('shared')));
            }
            mutations.add(headers['Authorization']!);
            return Reply(401, '');
          },
        ),
      );
      await book.init();
      for (final label in ['A', 'B']) {
        final a = await book.add(label);
        await a.api.store.write('session', session(label));
        await book.hydrate(a);
        await book.refresh(a);
      }
      final result = await activateSelected(
        combined(book.accounts),
        false,
        () => false,
      );
      expect(result.failure, isNotNull);
      expect(result.activated, 0);
      expect(mutations, ['Bearer A']);
      expect(book.accounts.last.fresh, isTrue);
    },
  );
  test('a stale account cannot activate and does not send a request', () async {
    final book = AccountBook(
      Client(
        MemoryStore(),
        send: (_, _, _, _, _) async => throw StateError('must not send'),
      ),
    );
    await book.init();
    final a = await book.add('Stale');
    a.coupons = [Coupon(coupon('a'))];
    final result = await activateSelected(
      combined(book.accounts),
      false,
      () => false,
    );
    expect(result.failure, isA<FormatException>());
    expect(result.activated, 0);
  });
  test('login callback goes to the pending profile; replay cannot cross accounts', () async {
    final store = MemoryStore();
    final book = AccountBook(
      Client(
        store,
        clock: () => now,
        send: (_, _, _, _, _) async => Reply(
          200,
          '{"access_token":"new","token_type":"Bearer","expires_in":3600}',
        ),
      ),
    );
    await book.init();
    final a = await book.add('A'), b = await book.add('B');
    await a.api.store.write('session', session('A'));
    await a.api.store.write('loyalty', '{"id":"TEST-QR-A","country":"CZ"}');
    final urlA = await book.beginLogin(a), urlB = await book.beginLogin(b);
    expect(urlB.queryParameters['prompt'], 'login');
    await expectLater(
      book.finishLogin(
        Uri.parse(
          '${Client.callback}?state=${urlA.queryParameters['state']}&code=old',
        ),
      ),
      throwsFormatException,
    );
    final callback = Uri.parse(
      '${Client.callback}?state=${urlB.queryParameters['state']}&code=new',
    );
    final connected = await book.finishLogin(callback);
    expect(connected.id, b.id);
    expect((await a.api.load('session'))['access_token'], 'A');
    expect((await a.api.load('loyalty'))['id'], 'TEST-QR-A');
    expect((await b.api.load('session'))['access_token'], 'new');
    await expectLater(book.finishLogin(callback), throwsFormatException);
    final reopened = AccountBook(Client(store, clock: () => now));
    await reopened.init();
    expect(reopened.accounts.length, 2);
  });
  test(
    'account filter and activated grouping do not blend ownership',
    () async {
      final book = AccountBook(Client(MemoryStore()));
      await book.init();
      final a = await book.add('A'), b = await book.add('B');
      a.coupons = [Coupon(coupon('a', active: true))];
      b.coupons = [Coupon(coupon('a')), Coupon(coupon('b', active: true))];
      expect(combined(book.accounts, accountId: b.id).length, 2);
      expect(
        combined(
          book.accounts,
          activatedOnly: true,
        ).map((e) => e.account.label),
        ['A', 'B'],
      );
    },
  );
}
