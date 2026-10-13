import 'dart:convert';

import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/coupon_card.dart';
import 'package:coupon_pocket/coupon_deck.dart';
import 'package:coupon_pocket/wide_coupon_card.dart';
import 'package:coupon_pocket/cover_scroll.dart';
import 'package:coupon_pocket/main.dart';
import 'package:coupon_pocket/wire.dart';
import 'package:coupon_pocket/transport_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<MemoryStore> signedIn() async {
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
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android card transport preserves the exact read and rejects mutations',
    () async {
      const channel = MethodChannel('coupon_pocket/loyalty');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            expect(call.method, 'get');
            expect(
              call.arguments['url'],
              'https://profile.lidlplus.com/api/v1/CZ/loyalty',
            );
            expect(call.arguments['country'], 'CZ');
            expect(call.arguments['authorization'], 'Bearer fake');
            return {'status': 200, 'body': '"0012345"'};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final url = Uri.parse('https://profile.lidlplus.com/api/v1/CZ/loyalty');
      final reply = await nativeLoyaltyRead('GET', url, {
        'Authorization': 'Bearer fake',
        'Country': 'CZ',
        'Accept-Language': 'cs-CZ',
      }, null);
      expect(reply.body, '"0012345"');
      await expectLater(
        nativeLoyaltyRead('POST', url, {}, '{}'),
        throwsFormatException,
      );
      expect(calls, 1);
    },
  );
  test(
    'card 404 tries only the known alternate route and retains leading zeros',
    () async {
      final store = await signedIn(), paths = <String>[];
      final api = Client(
        store,
        send: (method, url, headers, body, type) async {
          expect(method, 'GET');
          expect(body, isNull);
          expect(url.host, 'profile.lidlplus.com');
          expect(headers['Authorization'], 'Bearer fake');
          paths.add(url.path);
          return paths.length == 1 ? Reply(404, '') : Reply(200, '"0012345"');
        },
      );
      expect(await api.card(), '0012345');
      expect(paths, ['/api/v1/CZ/loyalty', '/profile/api/v1/CZ/loyalty']);
      expect((await api.load('loyalty'))['id'], '0012345');
    },
  );
  test(
    'card fallback does not mask failures or write invented card data',
    () async {
      final store = await signedIn();
      var calls = 0;
      final api = Client(
        store,
        send: (_, _, _, _, _) async {
          calls++;
          return Reply(403, 'private');
        },
      );
      await expectLater(api.card(), throwsA(isA<ServiceException>()));
      expect(calls, 1);
      expect(await store.read('loyalty'), isNull);
    },
  );
  testWidgets('lazy stack, immediate search and single-account checkout', (
    tester,
  ) async {
    await initializeDateFormatting();
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final store = await signedIn();
    final coupons = [
      for (var i = 0; i < 100; i++)
        {
          'id': '$i',
          'title': 'Sample ${i.toString().padLeft(3, '0')}',
          'isActivated': false,
        },
    ];
    var posts = 0, deletes = 0;
    var laggingRead = false;
    final api = Client(
      store,
      send: (method, url, _, _, _) async {
        if (method == 'DELETE') {
          deletes++;
          expect(await store.read('coupons'), isNull);
          coupons.last['isActivated'] = false;
          return Reply(204, '');
        }
        if (method == 'POST') {
          posts++;
          coupons.last['isActivated'] = true;
          coupons.last['discount'] = {'title': '20%'};
          laggingRead = true;
          return Reply(204, '');
        }
        if (url.path.endsWith('promotionslist')) {
          final shown = laggingRead
              ? [
                  for (final c in coupons) {...c, 'isActivated': false},
                ]
              : coupons;
          laggingRead = false;
          return Reply(
            200,
            jsonEncode({
              'sections': [
                {'promotions': shown},
              ],
            }),
          );
        }
        if (url.host == 'profile.lidlplus.com') return Reply(200, '"0012345"');
        return Reply(200, jsonEncode(coupons.last));
      },
    );
    await tester.pumpWidget(
      PocketApp(client: api, worker: SerialQueue(), loginSupported: false),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CouponCard).evaluate().length, lessThan(5));
    await tester.drag(find.byType(CouponDeck), const Offset(0, -250));
    await tester.pumpAndSettle();
    final scroller = tester.widget<ListView>(
      find.descendant(
        of: find.byType(CouponDeck),
        matching: find.byType(ListView),
      ),
    );
    expect(scroller.controller!.offset, greaterThan(0));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '099');
    await tester.pumpAndSettle();
    expect(find.text('Sample 099'), findsOneWidget);
    expect(find.text('Sample 000'), findsNothing);
    final beforeSelection = tester.getRect(find.byType(CouponCard));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Sample 099'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(tester.getRect(find.byType(CouponCard)), beforeSelection);
    expect(
      tester.widget<CouponCard>(find.byType(CouponCard).first).selected,
      isTrue,
    );
    await tester.tap(find.text('Sample 099'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(coupons.last['isActivated'], false);
    expect(tester.getRect(find.byType(CouponCard)), beforeSelection);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Offer details'));
    await tester.pumpAndSettle();
    expect(find.byType(CoverScroll), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Sample 099'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Activate'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Deactivate'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample 099'));
    await tester.pumpAndSettle();
    expect(posts, 2);
    expect(find.text('Active'), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wide cards'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    final appearance = jsonDecode((await store.read('appearance'))!);
    expect(appearance['layout'], 'wide');
    expect(appearance['dark'], true);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(CouponDeck), findsNothing);
    expect(
      tester.widget<WideCouponCard>(find.byType(WideCouponCard)).selected,
      true,
    );
    await tester.tap(find.text('Continue · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Scan this card at checkout'), findsOneWidget);
    expect(find.text('Needs activation'), findsNothing);
    expect(find.text('1 selected offer'), findsOneWidget);
    expect(find.text('Sample 099'), findsOneWidget);
    await tester.tap(find.text('Sample 099'));
    await tester.pumpAndSettle();
    expect(find.byType(CoverScroll), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Sample 099'), findsWidgets);
    expect(find.byType(BackButton), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
