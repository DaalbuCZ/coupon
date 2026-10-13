import 'package:coupon_pocket/coupon_information.dart';
import 'package:coupon_pocket/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final detail = Detail({
    'id': 'a',
    'title': 'Coffee',
    'isActivated': false,
    'discount': {'title': '20%', 'description': 'Sleva · max 2 na nákup'},
    'description': '<p>First paragraph.</p><p>Second &amp; third.</p>',
    'conditions': [
      {
        'title': 'Purchase limit',
        'description': '<ul><li>Two packs</li><li>One use</li></ul>',
      },
      {
        'title': 'Purchase limit',
        'description': '<ul><li>Two packs</li><li>One use</li></ul>',
      },
      'Only while stocks last.',
    ],
    'characteristics': {'title': 'Size', 'description': '250 g'},
    'availability': {'title': 'Stores', 'text': 'In-store only'},
  }, 'a');

  test(
    'details retain limits and conditions as readable, deduplicated sections',
    () {
      final sections = couponInformation(detail);
      expect(sections.map((s) => s.title), [
        'Discount & purchase limits',
        'About this offer',
        'Conditions',
        'Product information',
        'Availability',
      ]);
      expect(sections[0].items.single.body, 'Sleva · max 2 na nákup');
      expect(
        sections[1].items.single.body,
        'First paragraph.\n\nSecond & third.',
      );
      expect(sections[2].items.length, 2);
      expect(sections[2].items.first.body, '• Two packs\n\n• One use');
      expect(sections[3].items.single.body, '250 g');
      expect(couponText('&#268; &lt; 2 &nbsp;'), 'Č < 2');
      final long = '${'A long sentence. ' * 40}Final sentence.';
      expect(couponParagraphs(long).length, greaterThan(1));
      expect(couponParagraphs(long).join(' '), long);
    },
  );

  testWidgets('purchase limits are visible and full terms expand on demand', (
    tester,
  ) async {
    await initializeDateFormatting();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CouponInformation(detail: detail, locale: 'cs-CZ'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sleva · max 2 na nákup'), findsOneWidget);
    expect(find.text('Purchase limit'), findsNothing);
    await tester.ensureVisible(find.text('Conditions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conditions'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase limit'), findsOneWidget);
    expect(find.text('• Two packs'), findsOneWidget);
    expect(find.text('• One use'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
