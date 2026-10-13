import 'dart:convert';

import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/main.dart';
import 'package:coupon_pocket/coupon_card.dart';
import 'package:coupon_pocket/wire.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'server activations survive restart; resume removes redeemed and missing copies without mutations',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final store = MemoryStore();
      await store.write(
        'session',
        jsonEncode({
          'access_token': 'fake',
          'expires': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        }),
      );
      var rows = <Map<String, dynamic>>[
        {'id': 'a', 'title': 'Apples', 'isActivated': true},
        {'id': 'b', 'title': 'Bread', 'isActivated': true},
        {'id': 'c', 'title': 'Coffee', 'isActivated': false},
        {
          'id': 'd',
          'title': 'Online',
          'channel': 'ONLINESHOP',
          'isActivated': false,
        },
      ];
      var fail = false, reads = 0, mutations = 0;
      final client = Client(
        store,
        send: (method, url, headers, body, type) async {
          if (method != 'GET') {
            mutations++;
            throw StateError('Unexpected mutation');
          }
          if (url.host == 'profile.lidlplus.com') return Reply(200, '"00123"');
          reads++;
          if (fail) return Reply(503, '');
          return Reply(
            200,
            jsonEncode({
              'sections': [
                {'promotions': rows},
              ],
            }),
          );
        },
      );
      Future<void> launch() async {
        await tester.pumpWidget(
          PocketApp(
            client: client,
            worker: SerialQueue(),
            loginSupported: false,
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> resume() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      }

      await launch();
      expect(find.text('Continue · 2'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
      expect(
        tester.widget<CouponCard>(find.byType(CouponCard).first).selected,
        true,
      );
      await tester.pumpWidget(const SizedBox());
      await launch();
      expect(find.text('Continue · 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      fail = true;
      await launch();
      expect(find.text('Continue · 2'), findsNothing);
      fail = false;
      await resume();
      expect(find.text('Continue · 2'), findsOneWidget);
      await tester.tap(find.text('Continue · 2'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected offers'), findsOneWidget);
      final polling = reads;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(reads, greaterThan(polling));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = reads;
      await tester.pump(const Duration(seconds: 35));
      expect(reads, paused);
      final before = reads;
      fail = true;
      await resume();
      expect(reads, greaterThan(before));
      expect(find.text('2 selected offers'), findsOneWidget);
      fail = false;
      rows = [
        for (final row in rows)
          if (row['id'] != 'b')
            {...row, if (row['id'] == 'a') 'isRedeemed': true},
      ];
      await resume();
      expect(find.text('Apples'), findsNothing);
      expect(find.text('Bread'), findsNothing);
      expect(find.text('Choose your coupons first.'), findsOneWidget);
      expect(mutations, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
