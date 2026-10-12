import 'package:flutter/material.dart';

import 'models.dart';

// Display provider markup as plain text. No HTML resources or links are loaded.
String couponText(String value) {
  var text = value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</(?:p|div|h[1-6]|ul|ol)>', caseSensitive: false),
        '\n\n',
      )
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</?[a-z][^>]*>', caseSensitive: false), '');
  text = text.replaceAllMapped(
    RegExp(
      r'&(#x[0-9a-f]+|#\d+|amp|nbsp|quot|apos|lt|gt);',
      caseSensitive: false,
    ),
    (m) {
      final entity = m[1]!.toLowerCase();
      if (entity.startsWith('#')) {
        final code = entity.startsWith('#x')
            ? int.tryParse(entity.substring(2), radix: 16)
            : int.tryParse(entity.substring(1));
        if (code != null &&
            code > 0 &&
            code <= 0x10ffff &&
            !(code >= 0xd800 && code <= 0xdfff)) {
          return String.fromCharCode(code);
        }
        return m[0]!;
      }
      return {
        'amp': '&',
        'nbsp': ' ',
        'quot': '"',
        'apos': "'",
        'lt': '<',
        'gt': '>',
      }[entity]!;
    },
  );
  text = text
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return text;
}

typedef InformationItem = ({String title, String body});
typedef InformationSection = ({String title, List<InformationItem> items});

List<String> couponParagraphs(String text) => [
  for (final paragraph
      in text.split(RegExp(r'\n\s*\n')).where((p) => p.isNotEmpty))
    ...((paragraph.length > 400
            ? paragraph.replaceAllMapped(
                RegExp(r'([.!?])\s+(?=[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ])'),
                (m) => '${m[1]}\n\n',
              )
            : paragraph)
        .split('\n\n')),
];

List<InformationSection> couponInformation(Detail detail) {
  final result = <InformationSection>[];
  final seen = <String>{};
  void add(String heading, List<InformationItem> candidates) {
    final items = <InformationItem>[];
    for (final candidate in candidates) {
      final title = couponText(candidate.title),
          body = couponText(candidate.body);
      final key = '$title\n$body'.trim();
      if (key.isNotEmpty && seen.add(key)) {
        items.add((title: title, body: body));
      }
    }
    if (items.isNotEmpty) result.add((title: heading, items: items));
  }

  add('Discount & purchase limits', [
    (title: '', body: detail.benefitDescription),
  ]);
  add('About this offer', [
    (title: '', body: string(detail.raw['description'])),
  ]);
  for (final entry in {
    'conditions': 'Conditions',
    'characteristics': 'Product information',
    'articles': 'Products',
  }.entries) {
    final value = detail.raw[entry.key];
    add(entry.value, [
      for (final item in value is List ? value : [value])
        if (item is String)
          (title: '', body: item)
        else
          (
            title: string(object(item)['title']),
            body: string(object(item)['description']),
          ),
    ]);
  }
  final availability = object(detail.raw['availability']);
  add('Availability', [
    (title: string(availability['title']), body: string(availability['text'])),
  ]);
  return result;
}

class CouponInformation extends StatefulWidget {
  final Detail detail;
  final String locale;
  final Widget? choices;
  const CouponInformation({
    super.key,
    required this.detail,
    required this.locale,
    this.choices,
  });
  @override
  State<CouponInformation> createState() => _CouponInformationState();
}

class _CouponInformationState extends State<CouponInformation> {
  int limit = 8;
  String query = '';
  Widget items(List<InformationItem> values) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final item in values)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.title.isNotEmpty)
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              for (final paragraph in couponParagraphs(item.body))
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Text(
                    paragraph,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final sections = couponInformation(widget.detail);
    final products = [
      for (final s in sections)
        if (s.title == 'Products') ...s.items,
    ];
    final matches = products
        .where(
          (p) => '${p.title} ${p.body}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.detail.benefit.isNotEmpty)
                Text(
                  widget.detail.benefit,
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              if (widget.detail.expiry(widget.locale).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.detail.expiry(widget.locale),
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        for (final section in sections)
          if (section.title == 'Discount & purchase limits')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Discount & purchase limits',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                  items(section.items),
                ],
              ),
            ),
        if (widget.choices != null) widget.choices!,
        if (products.isNotEmpty) ...[
          Text(
            'Products · ${products.length}',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          if (products.length > 12)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Find a product',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                ),
                onChanged: (value) => setState(() {
                  query = value;
                  limit = 8;
                }),
              ),
            ),
          const SizedBox(height: 12),
          for (final item in matches.take(limit))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: items([item]),
            ),
          if (matches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No matching products'),
            ),
          if (matches.length > limit)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => setState(() => limit += 20),
                child: Text(
                  'Show more products (${matches.length - limit} remaining)',
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
        for (final section in sections)
          if (![
            'Discount & purchase limits',
            'Products',
            'About this offer',
            'Conditions',
          ].contains(section.title)) ...[
            Text(
              section.title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            items(section.items),
            const SizedBox(height: 20),
          ],
        for (final title in ['About this offer', 'Conditions'])
          for (final section in sections)
            if (section.title == title)
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  title: Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  children: [items(section.items)],
                ),
              ),
      ],
    );
  }
}
