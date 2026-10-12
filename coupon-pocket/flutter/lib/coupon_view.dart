import 'accounts.dart';
import 'models.dart';

String favouriteName(String title) =>
    title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

// Only explicit discounts participate. Prices and other model fields are ignored.
({String unit, double amount}) sale(Coupon coupon) {
  final text = coupon.benefit;
  final match = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(%|Kč|CZK|€|EUR|PLN|zł|£|GBP|CHF|RON|lei|Ft|HUF|SEK|NOK|DKK)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return (unit: '~', amount: 0);
  final unit = match[2]!.toUpperCase();
  return (
    unit: switch (unit) {
      'KČ' => 'CZK',
      '€' => 'EUR',
      'ZŁ' => 'PLN',
      '£' => 'GBP',
      'LEI' => 'RON',
      'FT' => 'HUF',
      _ => unit,
    },
    amount: double.parse(match[1]!.replaceAll(',', '.')),
  );
}

List<OwnedCoupon> couponView(
  List<OwnedCoupon> entries,
  Map<String, String> favourites,
  String query,
) {
  final needle = favouriteName(query);
  final order = {for (var i = 0; i < entries.length; i++) entries[i].key: i};
  final result = entries
      .where((e) => favouriteName(e.coupon.title).contains(needle))
      .toList();
  result.sort((a, b) {
    final af = favourites.containsKey(favouriteName(a.coupon.title));
    final bf = favourites.containsKey(favouriteName(b.coupon.title));
    if (af != bf) return af ? -1 : 1;
    final sa = sale(a.coupon), sb = sale(b.coupon);
    final unit = sa.unit.compareTo(sb.unit);
    if (unit != 0) return unit;
    final amount = sb.amount.compareTo(sa.amount);
    if (amount != 0) return amount;
    final title = a.coupon.title.compareTo(b.coupon.title);
    return title != 0 ? title : order[a.key]!.compareTo(order[b.key]!);
  });
  return result;
}
