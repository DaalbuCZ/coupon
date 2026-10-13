import 'package:coupon_pocket/coupon_card.dart';

import 'dart:convert';
import 'dart:async';

import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/main.dart';
import 'package:coupon_pocket/wire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
  });
  setUpAll(() async {
    await initializeDateFormatting();
  });
  testWidgets('one column fits narrow screens with large text and rotation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
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
    final client = Client(
      store,
      send: (_, url, _, _, _) async => url.host == 'profile.lidlplus.com'
          ? Reply(200, '"00123"')
          : Reply(
              200,
              jsonEncode({
                'sections': [
                  {
                    'promotions': [
                      for (var i = 0; i < 4; i++)
                        {
                          'id': '$i',
                          'title': 'Long product coupon title $i',
                          'isActivated': i == 0,
                          'discount': {'title': '20%'},
                          'validity': {'end': '2030-10-13T00:00:00Z'},
                        },
                    ],
                  },
                ],
              }),
            ),
    );
    await tester.pumpWidget(PocketApp(client: client, worker: SerialQueue()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.dragFrom(const Offset(160, 200), const Offset(0, -280));
    await tester.pumpAndSettle();
    expect(find.text('Long product coupon title 0'), findsOneWidget);
    tester.view.physicalSize = const Size(700, 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Accounts'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Account 1'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Account 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account 1'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'favourites persist and promote a returning coupon with a new ID',
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
      var returning = false;
      final client = Client(
        store,
        send: (_, _, _, _, _) async => Reply(
          200,
          jsonEncode({
            'sections': [
              {
                'promotions': [
                  {
                    'id': returning ? 'new' : 'old',
                    'title': returning ? ' Coffee ' : 'Coffee',
                    'discount': {'title': '10%'},
                  },
                  {
                    'id': 'fruit',
                    'title': 'Fruit',
                    'discount': {'title': '50%'},
                  },
                ],
              },
            ],
          }),
        ),
      );
      await tester.pumpWidget(PocketApp(client: client, worker: SerialQueue()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favourite coupon').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove favourite'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Coffee')).dy,
        lessThan(tester.getTopLeft(find.text('Fruit')).dy),
      );
      expect(
        jsonDecode((await store.read('favourites'))!)['entries'][0]['title'],
        'Coffee',
      );
      await tester.pumpWidget(const SizedBox());
      returning = true;
      await tester.pumpWidget(PocketApp(client: client, worker: SerialQueue()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove favourite'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(' Coffee ')).dy,
        lessThan(tester.getTopLeft(find.text('Fruit')).dy),
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'fruit');
      await tester.pumpAndSettle();
      expect(find.text(' Coffee '), findsNothing);
      expect(find.text('Fruit'), findsOneWidget);
    },
  );
  testWidgets(
    'unsupported login explains callback limitation without creating a pending profile',
    (tester) async {
      final store = MemoryStore();
      await tester.pumpWidget(
        PocketApp(
          client: Client(store),
          worker: SerialQueue(),
          loginSupported: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Accounts'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();
      expect(find.text('Account login unavailable here'), findsOneWidget);
      expect(
        (jsonDecode((await store.read('accounts'))!) as Map)['profiles'],
        isEmpty,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'selecting another coupon never replays an uncertain activation',
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
      final posts = <String>[];
      final coupons = [
        for (final id in ['A', 'B'])
          {'id': id, 'title': id, 'isActivated': false},
      ];
      final client = Client(
        store,
        send: (method, url, _, _, _) async {
          if (method == 'POST') {
            final id = url.pathSegments[url.pathSegments.length - 2];
            posts.add(id);
            if (id == 'A') throw TimeoutException('uncertain');
            coupons.last['isActivated'] = true;
            return Reply(200, '{}');
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
              coupons.firstWhere((c) => c['id'] == url.pathSegments.last),
            ),
          );
        },
      );
      await tester.pumpWidget(PocketApp(client: client, worker: SerialQueue()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(posts, ['A']);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'B');
      final next = find.text('B', findRichText: false).first;
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(posts, ['A', 'B']);
      expect(find.text('Confirm'), findsNothing);
    },
  );
  testWidgets('automatic selection waits for a required product choice', (
    tester,
  ) async {
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
    var active = false;
    var posts = 0;
    final client = Client(
      store,
      send: (method, url, _, body, _) async {
        final coupon = {'id': 'a', 'title': 'Coffee', 'isActivated': active};
        if (method == 'POST') {
          posts++;
          expect(jsonDecode(body!)['articleSelection'], [
            {'groupId': 'g', 'articleId': 'large'},
          ]);
          active = true;
          return Reply(200, '{}');
        }
        if (url.path.endsWith('promotionslist')) {
          return Reply(
            200,
            jsonEncode({
              'sections': [
                {
                  'promotions': [coupon],
                },
              ],
            }),
          );
        }
        return Reply(
          200,
          jsonEncode({
            ...coupon,
            'groups': [
              {
                'id': 'g',
                'title': 'Pack size',
                'articles': [
                  {'id': 'large', 'title': 'Large pack'},
                ],
              },
            ],
          }),
        );
      },
    );
    await tester.pumpWidget(PocketApp(client: client, worker: SerialQueue()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save product choices'),
          )
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.byType(DropdownButton<String>),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large pack').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save product choices'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(
      tester.widget<CouponCard>(find.byType(CouponCard).first).selected,
      isTrue,
    );
  });
  testWidgets('saved coupons cannot mutate after failed refresh', (
    tester,
  ) async {
    final store = MemoryStore();
    await store.write(
      'coupons',
      jsonEncode({
        'country': 'CZ',
        'language': 'cs-CZ',
        'store': '',
        'body': jsonEncode({
          'sections': [
            {
              'promotions': [
                {'id': 'a', 'title': 'Saved coupon', 'isActivated': false},
              ],
            },
          ],
        }),
      }),
    );
    final calls = <String>[];
    final api = Client(
      store,
      send: (method, _, _, _, _) async {
        calls.add(method);
        return Reply(503, '');
      },
    );
    await tester.pumpWidget(PocketApp(client: api, worker: SerialQueue()));
    await tester.pumpAndSettle();
    expect(find.text('Saved coupon'), findsOneWidget);
    await tester.tap(find.text('Saved coupon'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });
}
