import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'client.dart';
import 'models.dart';

class Account {
  final String id;
  String label;
  final Client api;
  List<Coupon> coupons = [];
  bool fresh = false, signedIn = false;
  String card = '', error = '';
  DateTime? pendingSince, lastSync;
  bool importedCard = false, sessionExpired = false;
  Uint8List? cardImage;
  bool get awaitingLogin => pendingSince != null;
  String get status => awaitingLogin
      ? 'Waiting for browser'
      : !signedIn
      ? 'Not connected'
      : sessionExpired
      ? 'Session expired'
      : fresh
      ? 'Connected · up to date'
      : 'Connected · saved data';
  Account(this.id, this.label, this.api);
  String key(Coupon coupon) => '$id:${coupon.id}';
}

/// All profile values live inside one encrypted native vault entry. A write
/// queue also protects read/modify/write transactions independently of the UI.
class AccountBook {
  final Client template;
  final SerialQueue storageQueue = SerialQueue();
  final List<Account> accounts = [];
  AccountBook(this.template);
  Store get root => template.store;
  Future<Json> _read() async =>
      object(jsonDecode(await root.read('accounts') ?? '{"profiles":[]}'));
  List<Json> _profiles(Json doc) => [
    for (final p in doc['profiles'] ?? []) object(p),
  ];
  Future<T> _edit<T>(T Function(Json doc) edit) => storageQueue.run(() async {
    final doc = await _read();
    final result = edit(doc);
    await root.write('accounts', jsonEncode(doc));
    return result;
  });
  Account _account(Json p) => Account(
    string(p['id']),
    string(p['label'], 'Account'),
    Client(
      ProfileStore(this, string(p['id'])),
      send: template.send,
      clock: template.clock,
    ),
  );
  Future<void> init() async {
    var doc = await _read();
    if (doc['migrated'] != true) {
      // Copy first, commit the book, then remove old single-account entries.
      // Repeating after an interrupted cleanup is safe.
      final data = <String, String>{};
      for (final key in ProfileStore.keys) {
        final value = await root.read(key);
        if (value != null) data[key] = value;
      }
      if (_profiles(doc).isEmpty && data.isNotEmpty) {
        doc['profiles'] = [
          {'id': _id(), 'label': 'Account 1', 'data': data},
        ];
        if (data.containsKey('pending')) {
          doc['pendingId'] = object((doc['profiles'] as List).first)['id'];
        }
      }
      doc['migrated'] = true;
      await root.write('accounts', jsonEncode(doc));
    }
    for (final key in ProfileStore.keys) {
      await root.delete(key);
    }
    doc = await _read();
    accounts.clear();
    for (final p in _profiles(doc)) {
      if (!RegExp(r'^[a-z]{16}$').hasMatch(string(p['id'])) ||
          accounts.any((a) => a.id == p['id'])) {
        throw const FormatException('Saved account data is invalid.');
      }
      final account = _account(p);
      await hydrate(account);
      accounts.add(account);
    }
    await expirePending();
  }

  String _id() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => String.fromCharCode(97 + random.nextInt(26)),
    ).join();
  }

  Future<Account> add(String label) async {
    final id = _id();
    final p = {
      'id': id,
      'label': label.trim().isEmpty
          ? 'Account ${accounts.length + 1}'
          : label.trim(),
      'data': <String, String>{},
    };
    await _edit((doc) {
      doc['profiles'] = [..._profiles(doc), p];
    });
    final account = _account(p);
    await account.api.init();
    accounts.add(account);
    return account;
  }

  Future<void> rename(Account account, String label) async {
    if (label.trim().isEmpty || label.length > 80) {
      throw const FormatException('Use an account name of 1–80 characters.');
    }
    await _edit((doc) {
      for (final p in doc['profiles']) {
        if (p['id'] == account.id) p['label'] = label.trim();
      }
    });
    account.label = label.trim();
  }

  Future<void> remove(Account account) async {
    await _edit((doc) {
      doc['profiles'] = _profiles(doc)
          .where((p) => p['id'] != account.id)
          .toList();
      if (doc['pendingId'] == account.id) doc.remove('pendingId');
    });
    accounts.removeWhere((a) => a.id == account.id);
  }

  Future<void> hydrate(Account a) async {
    await a.api.init();
    a.signedIn = string((await a.api.load('session'))['access_token'])
        .isNotEmpty;
    final session = await a.api.load('session');
    a.sessionExpired =
        a.signedIn &&
        (session['expires'] as int? ?? 0) <=
            template.clock().millisecondsSinceEpoch;
    final pending = await a.api.load('pending');
    final created = pending['created'];
    a.pendingSince = created is int && created > 0
        ? DateTime.fromMillisecondsSinceEpoch(created)
        : null;
    final imported = await a.api.load('import'),
        saved = await a.api.load('loyalty');
    a.cardImage = null;
    final image = string(imported['image']);
    if (imported['country'] == a.api.country &&
        image.isNotEmpty &&
        image.length <= 720000) {
      try {
        a.cardImage = base64Decode(image);
      } on FormatException {
        /* Ignore a damaged import. */
      }
    }
    a.importedCard =
        imported['country'] == a.api.country &&
        (string(imported['id']).isNotEmpty || a.cardImage != null);
    a.card = string(
      a.importedCard
          ? imported['id']
          : saved['country'] == a.api.country
          ? saved['id']
          : null,
    );
    final cache = await a.api.load('coupons');
    a.lastSync = cache['saved'] is int
        ? DateTime.fromMillisecondsSinceEpoch(cache['saved'])
        : null;
    a.coupons = [];
    a.fresh = false;
    if (cache['country'] == a.api.country &&
        cache['language'] == a.api.language &&
        cache['store'] == a.api.storeId) {
      a.coupons = Coupon.parse(string(cache['body']));
    }
  }

  Future<Uri> beginLogin(Account a) async {
    final doc = await _read();
    final previous = string(doc['pendingId']);
    if (previous.isNotEmpty && previous != a.id) {
      final pending = accounts.where((p) => p.id == previous);
      if (pending.isNotEmpty) await cancelLogin(pending.first);
    }
    final uri = await a.api.beginLogin(chooseAccount: true);
    a.pendingSince = template.clock();
    a.error = '';
    await _edit((doc) {
      doc['pendingId'] = a.id;
    });
    return uri;
  }

  Future<Account> finishLogin(Uri uri) async {
    final id = string((await _read())['pendingId']);
    final matches = accounts.where((a) => a.id == id);
    if (matches.isEmpty) {
      throw const FormatException(
        'No pending account login. Start Add account first.',
      );
    }
    final a = matches.single;
    try {
      await a.api.finishLogin(uri);
    } catch (e) {
      if ((await a.api.load('pending')).isEmpty) {
        a.pendingSince = null;
        await _edit((doc) {
          doc.remove('pendingId');
        });
      }
      a.error = e is FormatException ? e.message : 'Login failed. Start again.';
      rethrow;
    }
    await _edit((doc) {
      doc.remove('pendingId');
    });
    await hydrate(a);
    return a;
  }

  Future<void> refresh(Account a) async {
    a.fresh = false;
    a.error = '';
    try {
      a.coupons = await a.api.list();
      a.fresh = true;
      a.signedIn = true;
      a.sessionExpired = false;
      a.lastSync = template.clock();
    } catch (e) {
      a.signedIn = string((await a.api.load('session'))['access_token'])
          .isNotEmpty;
      a.error = e is FormatException
          ? e.message
          : 'Could not refresh. No change was confirmed.';
      rethrow;
    }
  }

  Future<void> cancelLogin(Account a) async {
    await a.api.store.delete('pending');
    await _edit((doc) {
      if (doc['pendingId'] == a.id) doc.remove('pendingId');
    });
    a.pendingSince = null;
  }

  Future<void> expirePending() async {
    for (final a in accounts) {
      if (a.pendingSince != null &&
          (template.clock().isBefore(a.pendingSince!) ||
              template.clock().difference(a.pendingSince!) >
                  const Duration(minutes: 10))) {
        await cancelLogin(a);
        a.error = 'Login expired. Start again.';
      }
    }
  }
}

class ProfileStore implements Store {
  static const keys = [
    'session',
    'pending',
    'coupons',
    'loyalty',
    'import',
    'settings',
  ];
  final AccountBook book;
  final String id;
  ProfileStore(this.book, this.id);
  Json _data(Json doc) {
    final profiles = book._profiles(doc).where((p) => p['id'] == id);
    if (profiles.isEmpty) throw const FormatException('Account was removed.');
    return object(profiles.single['data']);
  }

  @override
  Future<String?> read(String key) async =>
      _data(await book._read())[key] as String?;
  @override
  Future<void> write(String key, String value) => book._edit((doc) {
    _data(doc)[key] = value;
  });
  @override
  Future<void> delete(String key) => book._edit((doc) {
    _data(doc).remove(key);
  });
  @override
  Future<void> clear() => book._edit((doc) {
    _data(doc).clear();
  });
}

class OwnedCoupon {
  final Account account;
  final Coupon coupon;
  OwnedCoupon(this.account, this.coupon);
  String get key => account.key(coupon);
}

List<OwnedCoupon> combined(
  List<Account> accounts, {
  String? accountId,
  bool activatedOnly = false,
  bool hideOnline = false,
}) {
  final seen = <String>{};
  return [
    for (final a in accounts)
      if (accountId == null || a.id == accountId)
        for (final c in a.coupons)
          if (!c.finished(a.api.clock()) &&
              (!activatedOnly || c.activated) &&
              (!hideOnline || !c.online) &&
              seen.add(a.key(c)))
            OwnedCoupon(a, c),
  ];
}

Future<BatchResult> activateSelected(
  List<OwnedCoupon> selected,
  bool hideOnline,
  bool Function() cancelled, {
  void Function(Account)? progress,
  void Function(OwnedCoupon)? onAttempt,
}) async {
  final total = BatchResult();
  final grouped = <Account, List<Coupon>>{};
  for (final entry in selected) {
    (grouped[entry.account] ??= []).add(entry.coupon);
  }
  for (final group in grouped.entries) {
    if (cancelled()) {
      total.cancelled = true;
      break;
    }
    if (!group.key.fresh) {
      total.failure = const FormatException(
        'Refresh the account before activating selected coupons.',
      );
      break;
    }
    group.key.fresh = false;
    progress?.call(group.key);
    final result = await bulk(
      group.key.api,
      group.value,
      hideOnline,
      cancelled,
      onAttempt: (id) => onAttempt?.call(
        OwnedCoupon(group.key, group.value.firstWhere((c) => c.id == id)),
      ),
    );
    total.confirmed.addAll(result.confirmed.map((id) => '${group.key.id}:$id'));
    total.activated += result.activated;
    total.skipped += result.skipped;
    total.choices += result.choices;
    total.cancelled = result.cancelled;
    total.failure = result.failure;
    if (total.cancelled || total.failure != null) break;
  }
  return total;
}
