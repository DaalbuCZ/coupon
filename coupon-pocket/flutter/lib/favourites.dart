import 'dart:convert';
import 'dart:typed_data';

import 'client.dart';
import 'coupon_view.dart';
import 'models.dart';

class SavedFavourite {
  final String title, locale, section;
  final Json snapshot;
  final Uint8List? image;
  final bool hasDetails;
  final DateTime? savedAt;
  SavedFavourite({
    required this.title,
    required this.snapshot,
    this.image,
    this.locale = 'cs-CZ',
    this.section = 'Coupons',
    this.hasDetails = false,
    this.savedAt,
  });
  Coupon get coupon => Coupon(snapshot);
  Detail get detail =>
      Detail({...snapshot, 'isActivated': false}, coupon.id, section);
  Json toJson() => {
    'title': title,
    'snapshot': snapshot,
    'locale': locale,
    'section': section,
    'hasDetails': hasDetails,
    'savedAt': savedAt?.toIso8601String(),
    if (image != null) 'image': base64Encode(image!),
  };
  factory SavedFavourite.fromJson(Json data) {
    final title = string(data['title']);
    final snapshot = object(data['snapshot']);
    Uint8List? image;
    try {
      final encoded = string(data['image']);
      if (encoded.isNotEmpty && encoded.length <= 720000) {
        image = base64Decode(encoded);
      }
    } on FormatException {
      /* Keep usable metadata if an image is damaged. */
    }
    return SavedFavourite(
      title: title,
      snapshot: snapshot['id'] is String
          ? snapshot
          : {'id': 'saved', 'title': title},
      image: image,
      locale: string(data['locale'], 'cs-CZ'),
      section: string(data['section'], 'Coupons'),
      hasDetails: data['hasDetails'] == true,
      savedAt: DateTime.tryParse(string(data['savedAt'])),
    );
  }
}

class FavouriteBook {
  final Store store;
  final entries = <String, SavedFavourite>{};
  FavouriteBook(this.store);
  Map<String, String> get names =>
      entries.map((key, value) => MapEntry(key, value.title));
  Future<void> load() async {
    final data = object(jsonDecode(await store.read('favourites') ?? '{}'));
    entries.clear();
    for (final value in data['entries'] is List ? data['entries'] : []) {
      final saved = SavedFavourite.fromJson(object(value));
      if (saved.title.trim().isNotEmpty) {
        entries[favouriteName(saved.title)] = saved;
      }
    }
    // Preserve favourites from the original name-only format.
    for (final value in data['titles'] is List ? data['titles'] : []) {
      if (value is String && value.trim().isNotEmpty) {
        entries.putIfAbsent(
          favouriteName(value),
          () => SavedFavourite(
            title: value,
            snapshot: {'id': 'saved', 'title': value},
          ),
        );
      }
    }
  }

  Future<void> put(SavedFavourite value) async {
    final next = {...entries, favouriteName(value.title): value};
    await _write(next);
  }

  Future<void> remove(String title) async {
    final next = {...entries}..remove(favouriteName(title));
    await _write(next);
  }

  Future<void> _write(Map<String, SavedFavourite> next) async {
    await store.write(
      'favourites',
      jsonEncode({
        'version': 2,
        'entries': next.values.map((v) => v.toJson()).toList(),
      }),
    );
    entries
      ..clear()
      ..addAll(next);
  }
}
