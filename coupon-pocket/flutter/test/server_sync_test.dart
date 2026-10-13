import 'dart:async';
import 'dart:convert';

import 'package:coupon_pocket/accounts.dart';
import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/main.dart';
import 'package:coupon_pocket/wire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets('clear deactivates all account copies; uncertain stop=$fail', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final rows = <String, List<Map<String, dynamic>>>{
        'A': [
          {'id': 'one', 'title': 'Shared', 'isActivated': true},
        ],
        'B': [
          {'id': 'two', 'title': 'Shared', 'isActivated': true},
          {'id': 'three', 'title': 'Other', 'isActivated': true},
        ],
      };
      final deletes = <String>[];
      final clearingGate = Completer<void>();
      final store = MemoryStore();
      final client = Client(
        store,
        send: (method, url, headers, body, type) async {
          final account = headers['Authorization']!.split(' ').last;
          if (url.host == 'profile.lidlplus.com') return Reply(200, '"00123"');
          if (url.path.endsWith('promotionslist'))
            return Reply(
              200,
              jsonEncode({
                'sections': [
                  {'promotions': rows[account]},
                ],
              }),
            );
          final id = method == 'DELETE'
              ? url.pathSegments[url.pathSegments.length - 2]
              : url.pathSegments.last;
          final row = rows[account]!.firstWhere((e) => e['id'] == id);
          if (method == 'DELETE') {
            expect(body, isNull);
            deletes.add('$account:$id');
            if (!fail && deletes.length == 1) await clearingGate.future;
            if (fail && deletes.length == 2)
              throw TimeoutException('uncertain');
            row['isActivated'] = false;
            return Reply(204, '');
          }
          expect(method, 'GET');
          return Reply(200, jsonEncode(row));
        },
      );
      final book = AccountBook(client);
      await book.init();
      for (final name in ['A', 'B']) {
        final account = await book.add(name);
        await account.api.store.write(
          'session',
          jsonEncode({
            'access_token': name,
            'expires': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
          }),
        );
      }
      await tester.pumpWidget(
        PocketApp(client: client, worker: SerialQueue(), loginSupported: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue · 2'), findsOneWidget);
      await tester.tap(find.text('Continue · 2'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Clear shopping list'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Clear shopping list'));
      if (!fail) {
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Clearing shopping list'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Clearing shopping list'), findsOneWidget);
        clearingGate.complete();
      }
      await tester.pumpAndSettle();
      expect(find.text('Clearing shopping list'), findsNothing);
      expect(
        deletes,
        fail ? ['A:one', 'B:two'] : ['A:one', 'B:two', 'B:three'],
      );
      if (!fail) expect(find.text('Continue · 2'), findsNothing);
      final before = deletes.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(deletes.length, before);
      if (fail) expect(rows['B']!.every((e) => e['isActivated'] == true), true);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'reload imports external activation and removes external deactivation without writes',
    (tester) async {
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
      var writes = 0;
      final client = Client(
        store,
        send: (method, url, headers, body, type) async {
          if (method != 'GET') writes++;
          return Reply(
            200,
            jsonEncode({
              'sections': [
                {
                  'promotions': [
                    {'id': 'a', 'title': 'Coffee', 'isActivated': active},
                  ],
                },
              ],
            }),
          );
        },
      );
      await tester.pumpWidget(
        PocketApp(client: client, worker: SerialQueue(), loginSupported: false),
      );
      await tester.pumpAndSettle();
      Future<void> reload() async {
        final future = tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show();
        await tester.pumpAndSettle();
        await future;
      }

      active = true;
      await reload();
      expect(find.text('Continue · 1'), findsOneWidget);
      active = false;
      await reload();
      expect(find.text('Continue · 1'), findsNothing);
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sideways predictive back moves without scaling and cancels or commits',
    (tester) async {
      await tester.pumpWidget(
        PocketApp(
          client: Client(MemoryStore()),
          worker: SerialQueue(),
          loginSupported: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      Future<void> gesture(String method, [double? progress]) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/backgesture',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(
              method,
              progress == null
                  ? null
                  : {
                      'touchOffset': [5.0, 300.0],
                      'progress': progress,
                      'swipeEdge': 0,
                    },
            ),
          ),
          (_) {},
        );
        await tester.pump();
      }

      final before = tester.getRect(find.text('Settings'));
      await gesture('startBackGesture', 0);
      await gesture('updateBackGestureProgress', .4);
      final during = tester.getRect(find.text('Settings'));
      expect(during.left, greaterThan(before.left + 50));
      expect(during.size, before.size);
      await gesture('cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.getRect(find.text('Settings')), before);
      Navigator.of(tester.element(find.byType(PocketHome))).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Detail page')),
        ),
      );
      await tester.pumpAndSettle();
      await gesture('startBackGesture', 0);
      await gesture('updateBackGestureProgress', .7);
      await gesture('commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Detail page'), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
      await gesture('startBackGesture', 0);
      await gesture('updateBackGestureProgress', .7);
      final beforeCommit = tester.getRect(find.text('Settings'));
      await gesture('commitBackGesture');
      expect(
        tester.getRect(find.text('Settings')).left,
        greaterThanOrEqualTo(beforeCommit.left - .5),
      );
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Lidl++'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
