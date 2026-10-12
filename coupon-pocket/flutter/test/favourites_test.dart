import 'dart:typed_data';

import 'package:coupon_pocket/client.dart';
import 'package:coupon_pocket/favourites.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('disk');
    await super.write(key, value);
  }
}

void main() {
  test('name-only favourites migrate and snapshots survive disappearance and reopening', () async {
    final store = MemoryStore();
    await store.write('favourites', '{"titles":["Coffee"]}');
    final book = FavouriteBook(store);
    await book.load();
    expect(book.names, {'coffee': 'Coffee'});
    await book.put(
      SavedFavourite(
        title: 'Coffee',
        snapshot: {
          'id': 'old',
          'title': 'Coffee',
          'discount': {'title': '20%'},
          'description': 'Full saved details',
          'isActivated': false,
        },
        image: Uint8List.fromList([1, 2, 3]),
        hasDetails: true,
      ),
    );
    final restored = FavouriteBook(store);
    await restored.load();
    final saved = restored.entries['coffee']!;
    expect(saved.coupon.benefit, '20%');
    expect(saved.detail.raw['description'], 'Full saved details');
    expect(saved.image, [1, 2, 3]);
    expect(saved.hasDetails, isTrue);
  });
  test('failed snapshot writes preserve the existing favourite', () async {
    final store = FailingStore(), book = FavouriteBook(FailingStore());
    final target = FavouriteBook(store);
    await target.put(
      SavedFavourite(title: 'Tea', snapshot: {'id': 'a', 'title': 'Tea'}),
    );
    store.fail = true;
    await expectLater(target.remove('Tea'), throwsStateError);
    expect(target.entries.containsKey('tea'), isTrue);
    expect(book.entries, isEmpty);
  });
}
