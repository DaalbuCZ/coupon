import 'dart:convert';

import 'package:coupon_pocket/accounts.dart';
import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/models.dart';
import 'package:coupon_pocket/shopping.dart';
import 'package:coupon_pocket/wire.dart';
import 'package:flutter_test/flutter_test.dart';

Account account(
  String name,
  List<String> ids, {
  Set<String> active = const {},
}) {
  final a = Account(name, name, Client(MemoryStore()));
  a.fresh = true;
  a.coupons = [
    for (final id in ids)
      Coupon({
        'id': id,
        'title': id,
        'isActivated': active.contains(id),
        'discount': {'title': '20%'},
      }),
  ];
  return a;
}

void main() {
  test(
    'failed batch records only sent requests and confirmed successes',
    () async {
      final storage = MemoryStore();
      await storage.write(
        'session',
        jsonEncode({
          'access_token': 'fake',
          'expires': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        }),
      );
      final attempts = <String>[];
      final coupons = [
        for (final id in ['1', '2', '3'])
          {
            'id': id,
            'title': id,
            'isActivated': false,
            'availability': {'isAvailable': true},
          },
      ];
      final api = Client(
        storage,
        send: (method, url, _, _, _) async {
          if (method == 'POST') {
            if (url.path.contains('/2/')) throw Exception('uncertain timeout');
            return Reply(204, '');
          }
          if (url.path.endsWith('promotionslist')) {
            return Reply(
              200,
              jsonEncode({
                'sections': [
                  {'promotions': coupons},
                ],
              }),
            );
          }
          return Reply(
            200,
            jsonEncode(
              coupons.firstWhere((c) => url.path.endsWith('/${c['id']}')),
            ),
          );
        },
      );
      final a = Account('A', 'A', api)..fresh = true;
      a.coupons = coupons.map((c) => Coupon(c)).toList();
      final result = await activateSelected(
        combined([a]),
        false,
        () => false,
        onAttempt: (e) => attempts.add(e.key),
      );
      expect(attempts, ['A:1', 'A:2']);
      expect(result.confirmed, {'A:1'});
      expect(result.failure, isNotNull);
    },
  );

  test(
    'list preview groups and dates do not block fresh detail validation',
    () {
      final a = account('A', ['1']);
      a.coupons.first.raw['groups'] = [
        {'title': 'Preview group'},
      ];
      a.coupons.first.raw['validity'] = {'end': '2030-10-13'};
      final offers = aggregateCoupons(combined([a]));
      expect(checkoutPlan(offers, {offers.single.key}).length, 1);
    },
  );
  test('offer identity survives validity field ordering', () {
    final a = account('A', ['1']), b = account('B', ['1']);
    a.coupons.first.raw['validity'] = {
      'start': '2026-01-01T00:00:00Z',
      'end': '2030-10-13T00:00:00Z',
    };
    b.coupons.first.raw['validity'] = {
      'end': '2030-10-13T00:00:00Z',
      'start': '2026-01-01T00:00:00Z',
    };
    expect(aggregateCoupons(combined([a, b])).length, 1);
  });
  test('exact cover beats greedy and assigns each coupon only once', () {
    final accounts = [
      account('A', ['1', '2', '3', '4']),
      account('B', ['1', '2', '5']),
      account('C', ['3', '4', '6']),
      account('D', ['5']),
      account('E', ['6']),
    ];
    for (final a in accounts) {
      for (final c in a.coupons) {
        c.raw['id'] = '${a.id}-${c.id}';
      }
    }
    final offers = aggregateCoupons(combined(accounts));
    expect(offers.length, 6);
    final plan = checkoutPlan(offers, offers.map((e) => e.key).toSet());
    expect(plan.length, 6);
    expect(plan.values.map((e) => e.account.id).toSet(), {'B', 'C'});
  });
  test(
    'shared offers retain per-account dates and limits without duplicates',
    () {
      final a = account('A', ['one']), b = account('B', ['two']);
      a.coupons.single.raw.addAll({
        'title': 'Alesto',
        'discount': {'title': '−20 %', 'description': 'Max 5 items'},
        'validity': {'end': '2000-10-13T23:59:59+02:00'},
      });
      b.coupons.single.raw.addAll({
        'title': ' ALESTO ',
        'discount': {'title': '-20%', 'description': 'Max 2 items'},
        'validity': {
          'start': '2020-10-13T00:00:00+02:00',
          'end': '2030-10-13T23:59:59+02:00',
        },
      });
      expect(combined([a, b]).length, 1);
      final offers = aggregateCoupons([
        OwnedCoupon(a, a.coupons.single),
        OwnedCoupon(b, b.coupons.single),
      ]);
      expect(offers.length, 1);
      expect(offers.single.copies.length, 2);
      final plan = checkoutPlan(offers, {offers.single.key});
      expect(plan.length, 1);
      expect(plan.values.map((e) => e.account.id).toSet().length, 1);
      expect(plan.values.single.account.id, 'B');
      expect(plan.values.single.coupon.id, 'two');
      expect(plan.values.single.coupon.benefitDescription, 'Max 2 items');
      expect(offers.single.preview.account.id, 'B');
      expect(
        offers.single.copies.first.coupon.benefitDescription,
        'Max 5 items',
      );
    },
  );
  test(
    'ties prefer active copies, stale accounts cannot receive activations',
    () {
      final a = account('A', ['1', '2']),
          b = account('B', ['1', '2'], active: {'1', '2'});
      var offers = aggregateCoupons(combined([a, b]));
      expect(
        checkoutPlan(
          offers,
          offers.map((e) => e.key).toSet(),
        ).values.map((e) => e.account.id).toSet(),
        {'B'},
      );
      b.fresh = false;
      offers = aggregateCoupons(combined([a, b]));
      expect(
        checkoutPlan(
          offers,
          offers.map((e) => e.key).toSet(),
        ).values.map((e) => e.account.id).toSet(),
        {'A'},
      );
    },
  );
  test('different prices and countries are not treated as the same offer', () {
    final a = account('A', ['1']),
        b = account('B', ['1']),
        c = account('C', ['1']);
    b.coupons.first.raw['discount'] = {'title': '30%'};
    c.api.country = 'DE';
    expect(aggregateCoupons(combined([a, b, c])).length, 3);
  });
}
