import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coupon_pocket/accounts.dart';
import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/main.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:coupon_pocket/coupon_card.dart';
import 'package:coupon_pocket/wire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  testWidgets(
    'selection activates the minimum account cover and shows only one QR at a time',
    (tester) async {
      await initializeDateFormatting();
      // Optional local font paths make human-review previews readable without
      // redistributing system fonts. Normal regression runs need no paths.
      const previewFont = String.fromEnvironment('PREVIEW_FONT');
      const previewBold = String.fromEnvironment('PREVIEW_BOLD');
      const previewMono = String.fromEnvironment('PREVIEW_MONO');
      const previewIcons = String.fromEnvironment('PREVIEW_ICONS');
      if (previewFont.isNotEmpty) {
        await tester.runAsync(() async {
          final font = FontLoader('Roboto')
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(previewFont).readAsBytes()),
              ),
            );
          if (previewBold.isNotEmpty) {
            font.addFont(
              Future.value(
                ByteData.sublistView(await File(previewBold).readAsBytes()),
              ),
            );
          }
          await font.load();
          final testFont = FontLoader('Ahem')
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(previewFont).readAsBytes()),
              ),
            );
          if (previewBold.isNotEmpty) {
            testFont.addFont(
              Future.value(
                ByteData.sublistView(await File(previewBold).readAsBytes()),
              ),
            );
          }
          await testFont.load();
          if (previewMono.isNotEmpty) {
            await (FontLoader('monospace')..addFont(
                  Future.value(
                    ByteData.sublistView(await File(previewMono).readAsBytes()),
                  ),
                ))
                .load();
          }
          if (previewIcons.isNotEmpty) {
            await (FontLoader('MaterialIcons')..addFont(
                  Future.value(
                    ByteData.sublistView(
                      await File(previewIcons).readAsBytes(),
                    ),
                  ),
                ))
                .load();
          }
        });
      }
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final store = MemoryStore();
      final data = {
        'Home': {
          'oats': {
            'id': 'oats',
            'title': 'Oat drink',
            'discount': {'title': '25%'},
            'isActivated': false,
          },
          'coffee': {
            'id': 'coffee',
            'title': 'Ground coffee',
            'discount': {'title': '30%'},
            'isActivated': false,
          },
        },
        'Weekend': {
          'oats': {
            'id': 'oats',
            'title': 'Oat drink',
            'discount': {'title': '25%'},
            'isActivated': false,
          },
          'fruit': {
            'id': 'fruit',
            'title': 'Fresh fruit',
            'discount': {'title': '15%'},
            'isActivated': false,
          },
        },
      };
      final mutations = <String>[];
      final template = Client(
        store,
        send: (method, url, headers, body, type) async {
          final name = headers['Authorization']!.replaceFirst(
            'Bearer synthetic-',
            '',
          );
          final account = data[name]!;
          if (url.path.endsWith('promotionslist')) {
            return Reply(
              200,
              jsonEncode({
                'sections': [
                  {'promotions': account.values.toList()},
                ],
              }),
            );
          }
          final parts = url.pathSegments;
          if (method == 'POST') {
            final id = parts[parts.length - 2];
            mutations.add('$name:$id');
            account[id]!['isActivated'] = true;
            return Reply(200, '{}');
          }
          return Reply(200, jsonEncode(account[parts.last]));
        },
      );
      final book = AccountBook(template);
      await book.init();
      final a = await book.add('Home'), b = await book.add('Weekend');
      for (final account in [a, b]) {
        await account.api.store.write(
          'session',
          jsonEncode({
            'access_token': 'synthetic-${account.label}',
            'expires': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
          }),
        );
        await account.api.store.write(
          'import',
          jsonEncode({'id': 'DEMO-QR-${account.label}', 'country': 'CZ'}),
        );
      }
      const capture = Key('preview');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: PocketApp(client: template, worker: SerialQueue()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Future<void> choose(String title) async {
        final card = find.ancestor(
          of: find.text(title),
          matching: find.byType(CouponCard),
        );
        final button = find.descendant(
          of: card,
          matching: find.byTooltip('Select'),
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      Future<void> snapshot(String name) async {
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/previews').create(recursive: true);
          await File('build/previews/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(find.text('Oat drink'), findsOneWidget);
      await choose('Oat drink');
      await choose('Fresh fruit');
      expect(mutations.toSet(), {'Home:oats', 'Weekend:oats', 'Weekend:fruit'});
      await snapshot('coupons');
      await tester.tap(find.textContaining('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Weekend'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
      await snapshot('checkout');
      await tester.tap(find.text('Show QR code'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        tester.widget<QrImageView>(find.byType(QrImageView)).key,
        ValueKey('qr-${b.id}'),
      );
      await snapshot('qr');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await choose('Ground coffee');
      await tester.tap(find.textContaining('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Weekend'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      await tester.tap(find.text('Show QR code').first);
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        tester.widget<QrImageView>(find.byType(QrImageView)).key,
        ValueKey('qr-${a.id}'),
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      await snapshot('settings');
      expect(tester.takeException(), isNull);
    },
  );
}
