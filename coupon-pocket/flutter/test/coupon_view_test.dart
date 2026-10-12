import 'package:coupon_pocket/accounts.dart';
import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/coupon_view.dart';
import 'package:coupon_pocket/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'favourites match returning titles, then discounts sort within units',
    () async {
      final book = AccountBook(Client(MemoryStore()));
      await book.init();
      final a = await book.add('A');
      final b = await book.add('B');
      Coupon coupon(String id, String title, String benefit) => Coupon({
        'id': id,
        'title': title,
        'discount': {'title': benefit},
      });
      a.coupons = [
        coupon('a', 'Coffee', '−15%'),
        coupon('b', 'Fruit', '−40%'),
        coupon('c', 'Milk', '10 Kč'),
        coupon('d', 'Bread', '25 Kč'),
        coupon('e', 'Mystery', 'Special price'),
        coupon('f', 'Euro deal', '5 €'),
      ];
      b.coupons = [coupon('new-id', ' COFFEE  ', '−20%')];
      final favourites = {favouriteName('Coffee'): 'Coffee'};
      expect(
        couponView(
          combined(book.accounts),
          favourites,
          '',
        ).map((e) => e.coupon.id),
        ['new-id', 'a', 'b', 'd', 'c', 'f', 'e'],
      );
      expect(
        couponView(combined(book.accounts), favourites, ' COFFEE ').length,
        2,
      );
      expect(sale(coupon('x', 'Decimal', '−12,5%*')).amount, 12.5);
      expect(sale(coupon('x', 'Price', 'Only 10')).unit, '~');
    },
  );
}
