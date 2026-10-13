import 'dart:convert';

import 'accounts.dart';
import 'coupon_view.dart';
import 'models.dart';

String offerEnd(Coupon coupon) => string(
  object(coupon.raw['validity'])['end'],
  string(
    object(coupon.raw['validity'])['endDate'],
    string(coupon.raw['endValidityDate']),
  ),
);

// Account-specific promotion IDs identify mutations, not shared offers.
// Dates, limits and descriptions belong to each account's copy. The shopper
// selects the displayed offer once; fresh detail validation uses the real copy.
String offerKey(OwnedCoupon e) => jsonEncode([
  e.account.api.country,
  favouriteName(e.coupon.title),
  e.coupon.benefit
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('−', '-')
      .replaceAll(',', '.'),
  e.coupon.online,
]);

// A particular account campaign survives title/benefit formatting changes.
String occurrenceKey(OwnedCoupon e) => jsonEncode([
  e.account.api.country,
  e.coupon.id,
  string(object(e.coupon.raw['validity'])['start']),
  offerEnd(e.coupon),
  e.coupon.online,
]);

class CouponOffer {
  final String key;
  final List<OwnedCoupon> copies;
  CouponOffer(this.key, this.copies);
  OwnedCoupon get preview => copies.firstWhere(
    (e) => e.coupon.activated && usableCopy(e),
    orElse: () => copies.firstWhere(usableCopy, orElse: () => copies.first),
  );
}

List<CouponOffer> aggregateCoupons(List<OwnedCoupon> entries) {
  final groups = <String, List<OwnedCoupon>>{};
  for (final e in entries) {
    (groups[offerKey(e)] ??= []).add(e);
  }
  return [for (final e in groups.entries) CouponOffer(e.key, e.value)];
}

bool couponFinished(Coupon coupon, DateTime now) => coupon.finished(now);

bool usableCopy(OwnedCoupon e) {
  if (!e.account.fresh || e.coupon.processing) return false;
  final raw = e.coupon.raw;
  if (raw['isRedeemed'] == true ||
      object(raw['availability'])['apologizeStatus'] == true) {
    return false;
  }
  // List data is a preview, not a detail response. Groups and date-only
  // display values must not prevent the fresh details check before mutation.
  final validity = object(raw['validity']);
  final now = e.account.api.clock();
  for (final key in ['start', 'end']) {
    final value = string(validity[key]);
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) continue;
    final time = DateTime.tryParse(value);
    if (time != null &&
        (key == 'start' ? now.isBefore(time) : now.isAfter(time))) {
      return false;
    }
  }
  return true;
}

/// Exact set cover: first minimize QR count, then prefer confirmed activations.
/// Choices are account assignments only; product choices are never inferred.
Map<String, OwnedCoupon> checkoutPlan(
  List<CouponOffer> offers,
  Set<String> selected,
) {
  final options = <String, List<OwnedCoupon>>{
    for (final offer in offers)
      if (selected.contains(offer.key))
        offer.key: offer.copies.where(usableCopy).toList(),
  }..removeWhere((key, copies) => copies.isEmpty);
  if (options.isEmpty) return {};
  final covers = <String, Set<String>>{};
  for (final e in options.entries) {
    for (final copy in e.value) {
      (covers[copy.account.id] ??= {}).add(e.key);
    }
  }
  Set<String>? best;
  var bestMutations = options.length + 1;
  final visited = <String>{};
  void visit(Set<String> chosen, Set<String> uncovered) {
    if (best != null && chosen.length > best!.length) return;
    if (uncovered.isEmpty) {
      final mutations = options.values
          .where(
            (copies) => !copies.any(
              (e) => chosen.contains(e.account.id) && e.coupon.activated,
            ),
          )
          .length;
      if (best == null ||
          chosen.length < best!.length ||
          mutations < bestMutations) {
        best = {...chosen};
        bestMutations = mutations;
      }
      return;
    }
    if (best != null && chosen.length >= best!.length) return;
    final state = chosen.toList()..sort();
    if (!visited.add(state.join(':'))) return;
    final next = uncovered.reduce(
      (a, b) => options[a]!.length <= options[b]!.length ? a : b,
    );
    final candidates = options[next]!.map((e) => e.account.id).toSet().toList()
      ..sort(
        (a, b) => covers[b]!
            .intersection(uncovered)
            .length
            .compareTo(covers[a]!.intersection(uncovered).length),
      );
    for (final account in candidates) {
      visit({...chosen, account}, uncovered.difference(covers[account]!));
    }
  }

  visit({}, options.keys.toSet());
  return {
    for (final e in options.entries)
      e.key:
          (e.value.where((copy) => best!.contains(copy.account.id)).toList()
                ..sort(
                  (a, b) => (b.coupon.activated ? 1 : 0).compareTo(
                    a.coupon.activated ? 1 : 0,
                  ),
                ))
              .first,
  };
}
