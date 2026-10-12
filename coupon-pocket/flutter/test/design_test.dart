import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coupon_pocket/accounts.dart';
import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/main.dart';
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
    'combined selection preserves account ownership and Activated shows each QR',
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
      final fixtures = [
        {
          'id': 'oats',
          'title': 'Oat drink',
          'discount': {'title': '−25%', 'description': 'Selected varieties'},
          'isActivated': false,
        },
        {
          'id': 'coffee',
          'title': 'Ground coffee',
          'discount': {'title': '−30%'},
          'isActivated': true,
        },
        {
          'id': 'fruit',
          'title': 'Fresh fruit',
          'discount': {'title': '−15%'},
          'isActivated': false,
        },
      ];
      final template = Client(
        store,
        send: (_, _, _, _, _) async => Reply(
          200,
          jsonEncode({
            'sections': [
              {'promotions': fixtures},
            ],
          }),
        ),
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
      await tester.tap(find.widgetWithText(OutlinedButton, 'Select +').first);
      await tester.pumpAndSettle();
      expect(find.text('ACTIVATE 1 SELECTED'), findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('build/previews');
        await output.create(recursive: true);
        await File('${output.path}/coupons.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('Activated'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('qr-${a.id}')), findsOneWidget);
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/previews/activated.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.drag(find.byType(ListView).first, const Offset(0, -580));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('qr-${b.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Coupons'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Weekend'));
      await tester.pumpAndSettle();
      expect(find.text('Selected'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Select +').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'ALL ACCOUNTS'));
      await tester.pumpAndSettle();
      expect(find.text('ACTIVATE 2 SELECTED'), findsOneWidget);
      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/previews/checkout.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );
}
