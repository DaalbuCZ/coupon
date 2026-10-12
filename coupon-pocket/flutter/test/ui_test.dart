import 'dart:convert';

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
  testWidgets('two columns fit narrow screens with large text and rotation', (
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
      send: (_, _, _, _, _) async => Reply(
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
    expect(
      tester.getTopLeft(find.text('Long product coupon title 0')).dy,
      tester.getTopLeft(find.text('Long product coupon title 1')).dy,
    );
    tester.view.physicalSize = const Size(700, 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Account 1 options'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byTooltip('Account 1 options'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ ADD ACCOUNT'));
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
    expect(find.text('Saved · refresh first'), findsOneWidget);
    final activate = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Select +'),
    );
    expect(activate.onPressed, isNull);
    expect(calls, isEmpty);
  });
}
