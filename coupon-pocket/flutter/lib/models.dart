import 'dart:convert';

import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;
Json object(dynamic value) => value is Map<String, dynamic> ? value : {};
String string(dynamic value, [String fallback = '']) =>
    value is String ? value : fallback;

class Coupon {
  final Json raw;
  final String section;
  Coupon(this.raw, [this.section = 'Coupons']) {
    if (id.isEmpty) {
      throw const FormatException('Coupon is missing its identifier.');
    }
  }
  String get id => string(raw['id']);
  String get title => string(raw['title'], 'Coupon');
  bool get activated => raw['isActivated'] == true;
  bool finished(DateTime now) {
    if (raw['isRedeemed'] == true) return true;
    final end = string(
      object(raw['validity'])['end'],
      string(
        object(raw['validity'])['endDate'],
        string(raw['endValidityDate']),
      ),
    );
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(end)) return false;
    final time = DateTime.tryParse(end);
    return time != null && now.isAfter(time);
  }

  bool get processing => raw['isProcessing'] == true;
  bool get online {
    final channel = string(raw['channel']).trim().toUpperCase();
    if (channel.isNotEmpty) return channel == 'ONLINESHOP';
    final channels = raw['channels'];
    if (channels is List && channels.isNotEmpty) {
      return channels.every(
        (c) => string(c).trim().toUpperCase() == 'ONLINESHOP',
      );
    }
    return section.trim().toUpperCase() == 'ONLINESHOP';
  }

  String get benefit {
    final d = object(raw['discount']);
    final title = string(d['title']).trim();
    return title.isNotEmpty && d['hasAsterisk'] == true && !title.endsWith('*')
        ? '$title*'
        : title;
  }

  String get benefitDescription =>
      string(object(raw['discount'])['description']);
  String expiry(String locale) {
    final v = object(raw['validity']);
    final text = string(
      v['end'],
      string(v['endDate'], string(raw['endValidityDate'])),
    );
    if (text.isEmpty) return '';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:T|$)').firstMatch(text);
    if (match == null) return 'Expiry date unavailable';
    final date = DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    if (date.month != int.parse(match[2]!) ||
        date.day != int.parse(match[3]!)) {
      return 'Expiry date unavailable';
    }
    return 'Valid until ${DateFormat.yMMMd(locale.replaceAll('-', '_')).format(date)}';
  }

  String get image {
    final images = raw['images'];
    return string(
      object(
        raw['image'] ??
            (images is List && images.isNotEmpty ? images.first : null),
      )['url'],
    );
  }

  static List<Coupon> parse(String body) {
    final root = object(jsonDecode(body));
    if (root['sections'] is! List) {
      throw const FormatException(
        'Coupon response format changed (missing sections).',
      );
    }
    return [
      for (final section in root['sections'])
        for (final p
            in object(section)['promotions'] is List
                ? object(section)['promotions']
                : [])
          Coupon(object(p), string(object(section)['name'], 'Coupons')),
    ];
  }
}

class Detail extends Coupon {
  Detail(super.raw, String expectedId, [super.section]) {
    if (id != expectedId || raw['isActivated'] is! bool) {
      throw const FormatException('Coupon details do not match.');
    }
    if (raw['groups'] != null && raw['groups'] is! List) {
      throw const FormatException('Unsupported product groups.');
    }
    final ids = <String>{};
    for (final g in groups) {
      final gid = string(g['id']);
      if (gid.isEmpty ||
          !ids.add(gid) ||
          g['articles'] is! List ||
          (g['articles'] as List).isEmpty) {
        throw const FormatException('Unsupported product group.');
      }
      final articles = <String>{};
      for (final a in g['articles']) {
        final aid = string(object(a)['id']);
        if (aid.isEmpty || !articles.add(aid)) {
          throw const FormatException('Unsupported product choices.');
        }
      }
    }
  }
  List<Json> get groups => [for (final g in raw['groups'] ?? []) object(g)];
  void available(DateTime now) {
    if (raw['isRedeemed'] == true ||
        processing ||
        object(raw['availability'])['apologizeStatus'] == true) {
      throw const FormatException(
        'Coupon is unavailable, redeemed or processing.',
      );
    }
    final v = object(raw['validity']);
    for (final key in ['start', 'end']) {
      final value = string(v[key]);
      if (value.isEmpty) continue;
      if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
        throw const FormatException('Cannot verify coupon validity.');
      }
      final time = DateTime.tryParse(value);
      if (time == null) {
        throw const FormatException('Cannot verify coupon validity.');
      }
      if (key == 'start' ? now.isBefore(time) : now.isAfter(time)) {
        throw const FormatException('Coupon is outside its validity period.');
      }
    }
  }

  String selection(Map<String, String> choices) {
    if (choices.length != groups.length) {
      throw const FormatException('Choose one product in every group.');
    }
    return jsonEncode({
      'articleSelection': [for (final g in groups) _choice(g, choices)],
    });
  }

  Json _choice(Json g, Map<String, String> choices) {
    final id = choices[g['id']];
    if (!(g['articles'] as List).any((a) => object(a)['id'] == id)) {
      throw const FormatException('Choose one valid product in every group.');
    }
    return {'groupId': g['id'], 'articleId': id};
  }

  String get terms {
    final parts = <String>[string(raw['description'])];
    for (final key in ['conditions', 'characteristics', 'articles']) {
      final value = raw[key];
      for (final v in value is List ? value : [value]) {
        final o = object(v);
        parts.add('${string(o['title'])}\n${string(o['description'])}'.trim());
      }
    }
    final availability = object(raw['availability']);
    parts.add(
      '${string(availability['title'])}\n${string(availability['text'])}'
          .trim(),
    );
    return parts.where((p) => p.isNotEmpty).join('\n\n');
  }
}

String loyalty(String body) {
  final text = body.trim();
  final value = text.startsWith('"') ? jsonDecode(text) : text;
  if (value is! String ||
      value.isEmpty ||
      value.length > 256 ||
      !RegExp(r'^[\x21-\x7E]+$').hasMatch(value) ||
      (!text.startsWith('"') && !RegExp(r'^\d+$').hasMatch(value))) {
    throw const FormatException(
      'Unsupported loyalty response. Import your existing card.',
    );
  }
  return value;
}
