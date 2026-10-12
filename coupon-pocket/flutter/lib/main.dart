import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accounts.dart';
import 'client.dart';
import 'models.dart';
import 'pictures.dart';
import 'navigation.dart';

const ink = Color(0xff171713),
    paper = Color(0xfff3f0e8),
    acid = Color(0xffd5fa43);
const outline = BorderSide(color: ink, width: 1.5);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  runApp(PocketApp(client: Client(defaultStore())));
}

class PocketApp extends StatelessWidget {
  final Client client;
  final SerialQueue? worker;
  final bool? loginSupported;
  const PocketApp({
    super.key,
    required this.client,
    this.worker,
    this.loginSupported,
  });
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Coupon Pocket',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: const ColorScheme.light(
        primary: ink,
        onPrimary: paper,
        secondary: acid,
        surface: paper,
        onSurface: ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w800,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: outline,
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(side: outline),
        backgroundColor: paper,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.zero),
      ),
      chipTheme: const ChipThemeData(
        shape: RoundedRectangleBorder(),
        side: outline,
      ),
    ),
    home: PocketHome(
      client: client,
      worker: worker,
      loginSupported: loginSupported,
    ),
  );
}

class PocketHome extends StatefulWidget {
  final Client client;
  final SerialQueue? worker;
  final bool? loginSupported;
  const PocketHome({
    super.key,
    required this.client,
    this.worker,
    this.loginSupported,
  });
  @override
  State<PocketHome> createState() => _PocketHomeState();
}

class _PocketHomeState extends State<PocketHome> with WidgetsBindingObserver {
  late final book = AccountBook(widget.client);
  late final queue = widget.worker ?? Client.worker;
  final selected = <String>{};
  String? accountFilter;
  bool hideOnline = false, busy = false, batching = false, cancelled = false;
  int tab = 0, pendingWork = 0;
  String message = '';
  StreamSubscription<Uri>? links;
  Timer? loginExpiry;
  bool get canLogin =>
      widget.loginSupported ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));
  List<OwnedCoupon> get visible => combined(
    book.accounts,
    accountId: accountFilter,
    activatedOnly: tab == 1,
    hideOnline: hideOnline,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    work(() async {
      await book.init();
      hideOnline = (await widget.client.load('view'))['hideOnline'] == true;
      if (book.accounts.length == 1 && !hideOnline) {
        hideOnline = book.accounts.first.api.hideOnline;
      }
      await refreshAll();
    });
    loginExpiry = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!busy &&
          book.accounts.any(
            (a) =>
                a.pendingSince != null &&
                widget.client.clock().difference(a.pendingSince!) >
                    const Duration(minutes: 10),
          )) {
        work(book.expirePending);
      }
    });
    if (canLogin) {
      links = AppLinks().uriLinkStream.listen(
        (uri) => work(() => completeLogin(uri)),
        onError: (_) => notice('Could not receive login callback.'),
      );
    }
  }

  @override
  void dispose() {
    cancelled = true;
    links?.cancel();
    loginExpiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      cancelled = true;
    } else {
      work(book.expirePending);
    }
  }

  String safeError(Object e) => e is FormatException
      ? e.message
      : 'Request failed. No change was confirmed. Refresh before retrying.';
  void notice(String value) {
    if (mounted) setState(() => message = value);
  }

  Future<void> work(Future<void> Function() action) async {
    pendingWork++;
    if (mounted) {
      setState(() {
        busy = true;
        message = '';
      });
    }
    try {
      await queue.run(action);
    } catch (e) {
      notice(safeError(e));
    } finally {
      pendingWork--;
      if (mounted) setState(() => busy = pendingWork > 0);
    }
  }

  Future<void> refreshAll() async {
    final failures = <String>[];
    for (final a in book.accounts) {
      if (!a.signedIn) continue;
      try {
        await book.refresh(a);
      } catch (_) {
        failures.add('${a.label}: ${a.error}');
      }
    }
    // Selection is bound to account + coupon and cleared when eligibility changes.
    final available = combined(book.accounts)
        .where(
          (e) => e.account.fresh && !e.coupon.activated && !e.coupon.processing,
        )
        .map((e) => e.key)
        .toSet();
    selected.removeWhere((key) => !available.contains(key));
    if (failures.isNotEmpty) notice(failures.join('\n'));
    if (mounted) setState(() {});
  }

  Future<void> loadCard(Account a) async {
    final id = await a.api.card(), imported = await a.api.load('import');
    a.importedCard =
        imported['country'] == a.api.country &&
        string(imported['id']).isNotEmpty;
    a.card = imported['country'] == a.api.country
        ? string(imported['id'], id)
        : id;
  }

  Future<void> completeLogin(Uri uri) async {
    final a = await book.finishLogin(uri);
    selected.removeWhere((key) => key.startsWith('${a.id}:'));
    clearPictures();
    if (mounted) setState(() {});
    await book.refresh(a);
    try {
      await loadCard(a);
    } catch (_) {
      notice('${a.label} connected. Load its card from Checkout.');
    }
  }

  Future<void> login(Account a) async {
    if (!canLogin) {
      throw const FormatException(
        'Browser login requires the Android or iOS app.',
      );
    }
    final uri = await book.beginLogin(a);
    if (mounted) setState(() => tab = 2);
    try {
      if (!await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      ).timeout(const Duration(seconds: 15))) {
        throw const FormatException('Could not open browser.');
      }
    } catch (_) {
      await book.cancelLogin(a);
      a.error = 'Browser did not open. Try logging in again.';
      rethrow;
    }
    notice('Finish browser login for ${a.label}, then return here.');
  }

  Future<void> importCard(Account? account) async {
    final value = await input('Import card QR text');
    if (value == null) return;
    await work(() async {
      if (value.isEmpty || value.length > 2048) {
        throw const FormatException('Invalid QR text.');
      }
      final a = account ?? await book.add('');
      await a.api.store.write(
        'import',
        jsonEncode({'id': value, 'country': a.api.country}),
      );
      a.card = value;
      a.importedCard = true;
      tab = 2;
    });
  }

  Future<void> addAccount() async {
    if (!canLogin) {
      final import = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Account login unavailable here'),
          content: const Text(
            'Lidl returns login to its native app callback. This web build cannot receive it. Connect accounts in the Android or iOS app. You can import a card here; imported cards do not retrieve coupons.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import card'),
            ),
          ],
        ),
      );
      if (import == true) await importCard(null);
      return;
    }
    await work(() async {
      await book.expirePending();
      if (book.accounts.any((a) => a.awaitingLogin)) {
        tab = 2;
        notice('A login is already waiting. Finish or cancel it in Checkout.');
        return;
      }
      final drafts = book.accounts.where((a) => !a.signedIn && a.card.isEmpty);
      await login(drafts.isEmpty ? await book.add('') : drafts.first);
    });
  }

  Future<String?> input(String title, [String initial = '']) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, maxLines: 3),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    return value;
  }

  Future<bool> confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> showDetail(OwnedCoupon entry) async {
    final a = entry.account;
    Detail? d;
    await work(() async {
      d = await a.api.detail(entry.coupon.id, entry.coupon.section);
    });
    if (d == null || !mounted) return;
    final detail = d!, choices = <String, String>{};
    for (final g in detail.groups) {
      final existing = (g['articles'] as List)
          .where((v) => object(v)['selected'] == true)
          .toList();
      if (existing.length == 1) {
        choices[g['id']] = object(existing.single)['id'];
      }
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('${a.label}\n${detail.title}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.benefit,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(detail.benefitDescription),
                  const SizedBox(height: 12),
                  Text(detail.terms),
                  for (final g in detail.groups) ...[
                    Text(string(g['title'], 'Choose a product')),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: choices[g['id']],
                      hint: const Text('Choose a product'),
                      items: [
                        for (final v in g['articles'])
                          DropdownMenuItem(
                            value: string(object(v)['id']),
                            child: Text(
                              string(
                                object(v)['title'],
                                string(object(v)['id']),
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => update(() => choices[g['id']] = v!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            if (a.fresh && !detail.processing)
              FilledButton(
                onPressed:
                    detail.groups.isNotEmpty &&
                        choices.length != detail.groups.length
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(
                  detail.activated
                      ? detail.groups.isEmpty
                            ? 'Deactivate'
                            : 'Update selection'
                      : 'Activate',
                ),
              ),
            if (a.fresh && detail.activated && detail.groups.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Deactivate'),
              ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await work(() async {
      if (!a.fresh) {
        throw const FormatException(
          'Refresh this account before changing coupons.',
        );
      }
      a.fresh = false;
      try {
        await a.api.mutate(
          detail,
          result && (!detail.activated || detail.groups.isNotEmpty),
          choices,
        );
        selected.remove(entry.key);
      } finally {
        try {
          await book.refresh(a);
        } catch (_) {}
      }
    });
  }

  Future<void> activateCoupons({bool all = false}) async {
    final entries =
        (all ? visible : combined(book.accounts, hideOnline: hideOnline))
            .where(
              (e) =>
                  !e.coupon.activated &&
                  !e.coupon.processing &&
                  (all || selected.contains(e.key)),
            )
            .toList();
    if (entries.isEmpty) return;
    final count = entries.map((e) => e.key).toSet().length;
    if (!await confirm(
      'Activate $count coupons across ${entries.map((e) => e.account.id).toSet().length} accounts? Coupons needing product choices will be skipped.',
    )) {
      return;
    }
    await work(() async {
      cancelled = false;
      batching = true;
      if (mounted) setState(() {});
      final result = await activateSelected(
        entries,
        hideOnline,
        () => cancelled,
        progress: (a) => notice('Activating for ${a.label}…'),
      );
      batching = false;
      await refreshAll();
      notice(
        '${result.activated} activated · ${result.skipped} skipped · ${result.choices} need choices.${result.cancelled ? ' Cancelled.' : ''}${result.failure == null ? '' : ' ${safeError(result.failure!)}'}',
      );
    });
  }

  Future<void> settings(Account a) async {
    final api = a.api;
    final country = TextEditingController(text: api.country),
        language = TextEditingController(text: api.language),
        store = TextEditingController(text: api.storeId);
    bool pictures = api.pictures;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('${a.label} settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: country,
                  decoration: const InputDecoration(labelText: 'Country (CZ)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: language,
                  decoration: const InputDecoration(
                    labelText: 'Language (cs-CZ)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: store,
                  decoration: const InputDecoration(
                    labelText: 'Store ID (optional)',
                  ),
                ),
                if (!kIsWeb)
                  SwitchListTile(
                    title: const Text('Product pictures'),
                    value: pictures,
                    onChanged: (v) => update(() => pictures = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await work(() async {
        final oldCountry = api.country,
            oldLanguage = api.language,
            oldStore = api.storeId;
        api.country = country.text.trim().toUpperCase();
        api.language = language.text.trim();
        api.storeId = store.text.trim();
        try {
          api.validateLocale();
        } catch (_) {
          api.country = oldCountry;
          api.language = oldLanguage;
          api.storeId = oldStore;
          rethrow;
        }
        a.fresh = false;
        a.coupons = [];
        selected.removeWhere((key) => key.startsWith('${a.id}:'));
        api.pictures = pictures;
        clearPictures();
        await api.settings();
        await api.store.delete('coupons');
        if (oldCountry != api.country) {
          await api.store.delete('loyalty');
          await api.store.delete('import');
          a.card = '';
        }
        if (a.signedIn) await book.refresh(a);
      });
    }
    Future.delayed(const Duration(seconds: 1), () {
      country.dispose();
      language.dispose();
      store.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = visible;
    final targets =
        (selected.isEmpty
                ? entries
                : combined(
                    book.accounts,
                    hideOnline: hideOnline,
                  ).where((e) => selected.contains(e.key)))
            .where((e) => !e.coupon.activated && !e.coupon.processing)
            .toList();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: InkWell(
          onTap: busy ? null : () => work(refreshAll),
          child: const Text(
            'COUPON POCKET',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '${book.accounts.where((a) => a.signedIn).length}/${book.accounts.length} CONNECTED',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: Divider(height: 2, thickness: 2, color: ink),
        ),
      ),
      body: Column(
        children: [
          if (busy)
            const LinearProgressIndicator(
              minHeight: 3,
              color: ink,
              backgroundColor: acid,
            ),
          if (message.isNotEmpty)
            Container(
              width: double.infinity,
              color: acid,
              padding: const EdgeInsets.all(12),
              child: Text(message),
            ),
          if (tab != 2) accountPicker(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => work(refreshAll),
              child: ListView(
                key: ValueKey('tab-$tab'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
                children: tab == 2
                    ? checkout()
                    : [
                        sectionTitle(
                          tab == 0
                              ? 'Good deals.\nYour pick.'
                              : 'Ready to scan.',
                          '${entries.length.toString().padLeft(2, '0')} / ${book.accounts.length} ACCOUNTS',
                        ),
                        if (entries.isEmpty)
                          emptyState(
                            tab == 0
                                ? 'Your pocket is waiting.'
                                : 'Nothing activated yet.',
                            book.accounts.isEmpty
                                ? 'Add an account to bring your coupons here.'
                                : 'Pull to refresh, or choose another account.',
                          ),
                        if (tab == 0) ...couponRows(entries),
                        if (tab == 1)
                          for (final a in book.accounts.where(
                            (a) =>
                                accountFilter == null || a.id == accountFilter,
                          )) ...[
                            if (entries.any((e) => e.account.id == a.id)) ...[
                              accountHeading(a),
                              cardPanel(a),
                              const SizedBox(height: 14),
                              ...couponRows(
                                entries
                                    .where((e) => e.account.id == a.id)
                                    .toList(),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ],
                      ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: tab == 2
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (batching)
                  action('CANCEL REMAINING', () => cancelled = true),
                if (tab == 0 && !batching)
                  action(
                    selected.isEmpty
                        ? 'ACTIVATE ALL'
                        : 'ACTIVATE ${targets.length} SELECTED',
                    busy ||
                            targets.isEmpty ||
                            targets.any((e) => !e.account.fresh)
                        ? null
                        : () => activateCoupons(all: selected.isEmpty),
                    accent: true,
                  ),
                const SizedBox(height: 8),
                action(
                  hideOnline ? 'ONLINESHOP / HIDDEN' : 'ONLINESHOP / SHOWN',
                  busy
                      ? null
                      : () => work(() async {
                          hideOnline = !hideOnline;
                          if (hideOnline) {
                            final hidden = combined(book.accounts)
                                .where((e) => e.coupon.online)
                                .map((e) => e.key)
                                .toSet();
                            selected.removeWhere(hidden.contains);
                          }
                          await widget.client.store.write(
                            'view',
                            jsonEncode({'hideOnline': hideOnline}),
                          );
                        }),
                ),
              ],
            ),
      bottomNavigationBar: PocketNavigation(
        selected: tab,
        counts: [
          combined(book.accounts).length,
          combined(book.accounts, activatedOnly: true).length,
          book.accounts.length,
        ],
        onChanged: (v) {
          if (batching) cancelled = true;
          setState(() => tab = v);
        },
      ),
    );
  }

  Widget accountPicker() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
    child: Row(
      children: [
        ChoiceChip(
          label: const Text('ALL ACCOUNTS'),
          selected: accountFilter == null,
          selectedColor: acid,
          onSelected: (_) => setState(() => accountFilter = null),
        ),
        for (final a in book.accounts)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(a.label),
              selected: accountFilter == a.id,
              selectedColor: acid,
              onSelected: (_) => setState(() => accountFilter = a.id),
            ),
          ),
      ],
    ),
  );
  Widget sectionTitle(String title, String meta) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meta,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.5,
          ),
        ),
      ],
    ),
  );
  Widget emptyState(String title, String subtitle) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(border: Border.all(color: ink, width: 1.5)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.north_east, size: 44),
        const SizedBox(height: 24),
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(subtitle),
        const SizedBox(height: 20),
        if (book.accounts.isEmpty)
          FilledButton(
            onPressed: busy ? null : addAccount,
            child: const Text('ADD ACCOUNT'),
          ),
      ],
    ),
  );
  List<Widget> couponRows(List<OwnedCoupon> entries) => [
    for (var i = 0; i < entries.length; i += 2)
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tile(entries[i])),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < entries.length
                    ? tile(entries[i + 1])
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
  ];
  Widget tile(OwnedCoupon e) {
    final c = e.coupon, a = e.account, picked = selected.contains(e.key);
    return Container(
      key: ValueKey(e.key),
      decoration: BoxDecoration(
        color: picked ? acid : Colors.white,
        border: Border.all(color: ink, width: 1.5),
        boxShadow: const [BoxShadow(color: ink, offset: Offset(3, 3))],
      ),
      child: Stack(
        children: [
          if (a.api.pictures && c.image.isNotEmpty)
            Positioned(
              top: 20,
              right: 0,
              width: 115,
              height: 110,
              child: CouponPicture(
                key: ValueKey('${a.id}:${a.api.country}:${c.image}'),
                url: c.image,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.label.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: busy ? null : () => showDetail(e),
                  child: Text(
                    c.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  c.benefit,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  c.benefitDescription,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text(
                  c.expiry(a.api.language),
                  style: const TextStyle(fontSize: 11),
                ),
                if (!a.fresh)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Saved · refresh first',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: ink),
                const SizedBox(height: 8),
                if (tab == 0 && !c.activated)
                  OutlinedButton(
                    onPressed: busy || !a.fresh || c.processing
                        ? null
                        : () => setState(() {
                            if (picked) {
                              selected.remove(e.key);
                            } else {
                              selected.add(e.key);
                            }
                          }),
                    child: Text(
                      c.processing
                          ? 'Processing'
                          : picked
                          ? 'Selected'
                          : 'Select +',
                    ),
                  ),
                if (c.activated)
                  TextButton(
                    onPressed: busy ? null : () => showDetail(e),
                    child: const Text('ACTIVATED ↗'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget action(String label, VoidCallback? onPressed, {bool accent = false}) =>
      DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: ink, offset: Offset(3, 3))],
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: accent ? acid : paper,
            foregroundColor: ink,
            side: outline,
            disabledBackgroundColor: const Color(0xffdedcd4),
          ),
          child: Text(label),
        ),
      );
  Widget accountHeading(Account a) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            a.label,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          a.api.country,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
  Widget cardPanel(Account a) => Container(
    key: ValueKey('qr-${a.id}'),
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border.fromBorderSide(outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${a.label} / CHECKOUT',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const Icon(Icons.qr_code_2),
          ],
        ),
        const SizedBox(height: 12),
        if (a.card.isNotEmpty)
          Center(
            child: SizedBox(
              width: 220,
              child: QrImageView(
                data: a.card,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        if (a.card.isEmpty)
          Text(
            a.signedIn
                ? 'Load this account’s card before checkout.'
                : 'Connect this account or import its card.',
          ),
        if (a.card.isNotEmpty)
          Center(
            child: SelectableText(
              a.card,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        if (a.signedIn && a.card.isEmpty)
          TextButton(
            onPressed: busy ? null : () => work(() => loadCard(a)),
            child: Text(
              a.card.isEmpty ? 'LOAD ACCOUNT CARD ↗' : 'REFRESH CARD ↗',
            ),
          ),
      ],
    ),
  );
  Future<void> accountAction(Account a, String action) async {
    switch (action) {
      case 'settings':
        await settings(a);
      case 'rename':
        final value = await input('Account name', a.label);
        if (value != null) await work(() => book.rename(a, value));
      case 'import':
        await importCard(a);
      case 'card':
        await work(() => loadCard(a));
      case 'login':
        await work(() => login(a));
      case 'callback':
        final value = await input('Complete login: paste callback URL');
        if (value != null) await work(() => completeLogin(Uri.parse(value)));
      case 'remove':
        if (await confirm(
          'Remove ${a.label} and its locally saved session, coupons and card?',
        )) {
          await work(() async {
            await book.remove(a);
            selected.removeWhere((key) => key.startsWith('${a.id}:'));
            if (accountFilter == a.id) accountFilter = null;
            clearPictures();
          });
        }
    }
  }

  List<Widget> checkout() => [
    sectionTitle(
      'Accounts & cards.',
      '${book.accounts.where((a) => a.signedIn).length} CONNECTED / ${book.accounts.length} SAVED',
    ),
    FilledButton(
      onPressed: busy ? null : addAccount,
      child: const Text('+ ADD ACCOUNT'),
    ),
    if (!canLogin)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Web: card imports available. Account login requires the mobile app.',
        ),
      ),
    for (final a in book.accounts) ...[
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: Text(
              a.label,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '${a.label} options',
            enabled: !busy,
            onSelected: (value) => accountAction(a, value),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'import', child: Text('Import card')),
              if (a.signedIn)
                const PopupMenuItem(value: 'card', child: Text('Refresh card')),
              if (canLogin)
                PopupMenuItem(
                  value: 'login',
                  child: Text(a.signedIn ? 'Reconnect' : 'Log in'),
                ),
              if (canLogin && a.awaitingLogin)
                const PopupMenuItem(
                  value: 'callback',
                  child: Text('Complete callback manually'),
                ),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove account'),
              ),
            ],
          ),
        ],
      ),
      Text(a.status, style: const TextStyle(fontWeight: FontWeight.w800)),
      Text(
        '${a.api.country} / ${a.api.language} · Last sync: ${a.lastSync == null ? 'never' : '${a.lastSync!.toLocal().day}/${a.lastSync!.toLocal().month} ${a.lastSync!.toLocal().hour.toString().padLeft(2, '0')}:${a.lastSync!.toLocal().minute.toString().padLeft(2, '0')}'}',
      ),
      const SizedBox(height: 10),
      Text(
        '${a.coupons.length} coupons · ${a.coupons.where((c) => c.activated).length} activated · ${selected.where((key) => key.startsWith('${a.id}:')).length} selected',
      ),
      Text(
        a.card.isEmpty
            ? 'Card missing'
            : a.importedCard
            ? 'Imported card · QR ready'
            : 'Account card · QR ready',
      ),
      if (a.awaitingLogin) ...[
        const Text(
          'Waiting for the browser to return. Login expires after 10 minutes.',
        ),
        TextButton(
          onPressed: busy ? null : () => work(() => book.cancelLogin(a)),
          child: const Text('Cancel login'),
        ),
      ],
      if (a.error.isNotEmpty) Text(a.error),
      if (canLogin && !a.awaitingLogin && (!a.signedIn || a.sessionExpired))
        TextButton(
          onPressed: busy ? null : () => work(() => login(a)),
          child: const Text('Log in'),
        ),
      const SizedBox(height: 12),
      cardPanel(a),
    ],
  ];
}

class CouponPicture extends StatefulWidget {
  final String url;
  const CouponPicture({super.key, required this.url});
  @override
  State<CouponPicture> createState() => _CouponPictureState();
}

class _CouponPictureState extends State<CouponPicture> {
  late final data = picture(widget.url);
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: data,
    builder: (ctx, snapshot) => snapshot.data == null
        ? const SizedBox()
        : ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Colors.white70, Colors.transparent],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              cacheWidth: 240,
              cacheHeight: 220,
            ),
          ),
  );
}
