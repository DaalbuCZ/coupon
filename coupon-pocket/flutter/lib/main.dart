import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accounts.dart';
import 'coupon_view.dart';
import 'coupon_information.dart';
import 'client.dart';
import 'models.dart';
import 'pictures.dart';
import 'favourites.dart';
import 'shopping.dart';
import 'coupon_card.dart';
import 'coupon_deck.dart';
import 'cover_scroll.dart';
import 'offer_cover.dart';
import 'wire.dart' show CardUnavailableException;

const ink = Color(0xff171713),
    paper = Color(0xfff5f6f2),
    acid = Color(0xffdcebbf);
const outline = BorderSide(color: Color(0xffdce0d6), width: 1);

TextTheme expressiveTextTheme([bool dark = false]) {
  final typography = Typography.material2021();
  final base = (dark ? typography.white : typography.black).apply(
    fontFamily: 'GoogleSansFlex',
  );
  TextStyle? round(TextStyle? style) => style?.copyWith(
    fontVariations: const [FontVariation('ROND', 100)],
    fontWeight: style.fontWeight == FontWeight.w400
        ? FontWeight.w500
        : style.fontWeight,
  );
  return TextTheme(
    displayLarge: round(base.displayLarge),
    displayMedium: round(base.displayMedium),
    displaySmall: round(base.displaySmall),
    headlineLarge: round(base.headlineLarge),
    headlineMedium: round(base.headlineMedium),
    headlineSmall: round(base.headlineSmall),
    titleLarge: round(base.titleLarge),
    titleMedium: round(base.titleMedium),
    titleSmall: round(base.titleSmall),
    bodyLarge: round(base.bodyLarge),
    bodyMedium: round(base.bodyMedium),
    bodySmall: round(base.bodySmall),
    labelLarge: round(base.labelLarge),
    labelMedium: round(base.labelMedium),
    labelSmall: round(base.labelSmall),
  );
}

enum PocketPage {
  coupons,
  checkout,
  settings,
  favourites,
  accounts,
  account,
  filters,
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Google Sans Flex',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  await initializeDateFormatting();
  runApp(PocketApp(client: Client(defaultStore())));
}

class PocketApp extends StatefulWidget {
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
  State<PocketApp> createState() => _PocketAppState();
}

class _PocketAppState extends State<PocketApp> {
  bool dark = false;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    widget.client
        .load('appearance')
        .then((value) {
          if (mounted) setState(() => dark = value['dark'] == true);
        })
        .catchError((Object _) {});
  }

  Future<void> changeDark(bool value) async {
    setState(() => dark = value);
    try {
      await widget.client.store.write(
        'appearance',
        jsonEncode({'dark': value}),
      );
    } catch (_) {
      messenger.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Could not save the appearance setting.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = dark ? const Color(0xff151915) : paper;
    final foreground = dark ? const Color(0xffedf1e8) : ink;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff64834e),
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: foreground,
          onPrimary: background,
          surface: dark ? const Color(0xff222822) : Colors.white,
        );
    return MaterialApp(
      scaffoldMessengerKey: messenger,
      title: 'Coupon Pocket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'GoogleSansFlex',
        textTheme: expressiveTextTheme(dark),
        brightness: dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: background,
        colorScheme: scheme,
        appBarTheme: AppBarTheme(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontVariations: [FontVariation('ROND', 100)],
              fontWeight: FontWeight.w800,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: outline,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontVariations: [FontVariation('ROND', 100)],
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          backgroundColor: scheme.surface,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
        chipTheme: const ChipThemeData(
          shape: RoundedRectangleBorder(),
          side: outline,
        ),
      ),
      home: PocketHome(
        client: widget.client,
        worker: widget.worker,
        loginSupported: widget.loginSupported,
        dark: dark,
        onDarkChanged: changeDark,
      ),
    );
  }
}

class PocketHome extends StatefulWidget {
  final bool dark;
  final ValueChanged<bool>? onDarkChanged;
  final Client client;
  final SerialQueue? worker;
  final bool? loginSupported;
  const PocketHome({
    super.key,
    this.dark = false,
    this.onDarkChanged,
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
  String search = '';
  bool searching = false;
  final searchInput = TextEditingController();
  final expandedAccounts = <String>{};
  late final favouriteBook = FavouriteBook(widget.client.store);
  Map<String, String> get favourites => favouriteBook.names;
  final attempted = <String>{};
  final assigned = <String, OwnedCoupon>{};
  final selectionCache = <String, OwnedCoupon>{};
  bool qrOpen = false;
  Account? openedAccount;
  bool refreshing = false;
  final activating = <String>{};
  final deactivating = <String>{};
  final pendingRemovals = <String, CouponOffer>{};
  bool selectionChanged = false;
  String? latestSelection;
  PocketPage page = PocketPage.coupons;
  final scroll = ScrollController();
  bool hideOnline = false, busy = false, batching = false, cancelled = false;
  int pendingWork = 0;
  StreamSubscription<Uri>? links;
  Timer? loginExpiry;
  bool get canLogin =>
      widget.loginSupported ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));
  List<OwnedCoupon> get visible => couponView(
    combined(book.accounts, accountId: accountFilter, hideOnline: hideOnline),
    favourites,
    search,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    work(() async {
      await book.init();
      hideOnline = (await widget.client.load('view'))['hideOnline'] == true;
      await favouriteBook.load();
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
    scroll.dispose();
    searchInput.dispose();
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
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (value.isEmpty) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(value),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> work(Future<void> Function() action) async {
    pendingWork++;
    if (mounted) {
      setState(() {
        busy = true;
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
    if (mounted) setState(() => refreshing = true);
    final failures = <String>[];
    for (final a in book.accounts) {
      if (!a.signedIn) continue;
      try {
        await book.refresh(a);
      } catch (_) {
        failures.add('${a.label}: ${a.error}');
      }
    }
    assigned.addAll(checkoutPlan(allOffers, selected));
    if (failures.isNotEmpty) notice(failures.join('\n'));
    if (mounted) setState(() {});
    if (mounted) setState(() => refreshing = false);
  }

  Future<void> loadCard(Account a) async {
    final imported = await a.api.load('import');
    a.importedCard =
        imported['country'] == a.api.country &&
        (string(imported['id']).isNotEmpty || a.cardImage != null);
    final id = await a.api.card();
    a.card = a.importedCard && string(imported['id']).isNotEmpty
        ? string(imported['id'])
        : id;
  }

  Future<void> completeLogin(Uri uri) async {
    final a = await book.finishLogin(uri);
    clearAccountSelection(a);
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
    if (mounted) setState(() => page = PocketPage.accounts);
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
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final kind = android
        ? await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Import your account card'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, 'image'),
                  child: const Text('Choose a cropped QR image'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, 'text'),
                  child: const Text('Paste QR text'),
                ),
              ],
            ),
          )
        : 'text';
    if (kind == null) return;
    Uint8List? image;
    String? value;
    if (kind == 'image') {
      try {
        image = await const MethodChannel('coupon_pocket/card_import')
            .invokeMethod<Uint8List>('pick');
      } catch (_) {
        notice('Could not open that image. Choose a cropped QR image.');
        return;
      }
      if (image == null) return;
    } else {
      value = await input('Import card QR text');
      if (value == null) return;
      if (value.isEmpty || value.length > 2048) {
        notice('Invalid QR text.');
        return;
      }
    }
    await work(() async {
      final a = account ?? await book.add('');
      await a.api.store.write(
        'import',
        jsonEncode({
          'id': ?value,
          if (image != null) 'image': base64Encode(image),
          'country': a.api.country,
        }),
      );
      a.card = value ?? '';
      a.cardImage = image;
      a.importedCard = true;
      if (account == null) page = PocketPage.accounts;
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
        page = PocketPage.accounts;
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
  Future<void> showDetail(
    OwnedCoupon entry, {
    bool chooseProducts = false,
  }) async {
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
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => Scaffold(
            body: CoverScroll(
              title: detail.title,
              parallax: true,
              onBack: () => Navigator.pop(ctx),
              cover: a.api.pictures && detail.image.isNotEmpty
                  ? OfferCover(
                      url: detail.image,
                      topInset: MediaQuery.paddingOf(ctx).top + 32,
                    )
                  : const Center(
                      child: Icon(Icons.local_offer_outlined, size: 64),
                    ),
              coverHeight:
                  MediaQuery.sizeOf(ctx).width +
                  MediaQuery.paddingOf(ctx).top +
                  32,
              content: CouponInformation(
                detail: detail,
                locale: a.api.language,
                choices: !chooseProducts
                    ? null
                    : Column(
                        children: [
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
                              onChanged: (v) =>
                                  update(() => choices[g['id']] = v!),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            bottomNavigationBar: chooseProducts && detail.groups.isNotEmpty
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                        onPressed:
                            choices.length != detail.groups.length ||
                                !a.fresh ||
                                detail.processing
                            ? null
                            : () => Navigator.pop(ctx, true),
                        child: const Text('Save product choices'),
                      ),
                    ),
                  )
                : null,
          ),
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
        attempted.remove(entry.key);
        assigned.addAll(checkoutPlan(allOffers, selected));
      } finally {
        try {
          await book.refresh(a);
        } catch (_) {}
      }
    });
  }

  void reconcileSelection() {
    final copies = {for (final e in combined(book.accounts)) e.key: e};
    for (final key in selected.toList()) {
      final old = assigned[key] ?? selectionCache[key];
      final latest = copies[old?.key];
      if (old == null ||
          latest == null ||
          occurrenceKey(old) != occurrenceKey(latest))
        continue;
      final next = offerKey(latest);
      if (next == key) continue;
      selected.remove(key);
      selected.add(next);
      assigned.remove(key);
      selectionCache.remove(key);
      assigned[next] = latest;
      selectionCache[next] = latest;
      if (latestSelection == key) latestSelection = next;
    }
  }

  List<CouponOffer> get allOffers => aggregateCoupons(combined(book.accounts));
  Map<String, OwnedCoupon> get plan => checkoutPlan(allOffers, selected);
  List<OwnedCoupon> get basket {
    final current = plan;
    final refreshed = {for (final e in combined(book.accounts)) e.key: e};
    final result = <String, OwnedCoupon>{};
    for (final key in selected) {
      final retained = assigned[key] ?? selectionCache[key];
      final entry = current[key] ?? refreshed[retained?.key] ?? retained;
      if (entry != null) result.putIfAbsent(offerKey(entry), () => entry);
    }
    return result.values.toList();
  }

  void clearAccountSelection(Account a) {
    final affected = selected
        .where(
          (key) => (assigned[key] ?? selectionCache[key])?.account.id == a.id,
        )
        .toList();
    for (final key in affected) {
      selected.remove(key);
      assigned.remove(key);
      selectionCache.remove(key);
    }
  }

  void back() {
    if (batching) cancelled = true;
    setState(
      () => page = switch (page) {
        PocketPage.favourites ||
        PocketPage.accounts ||
        PocketPage.filters => PocketPage.settings,
        PocketPage.account => PocketPage.accounts,
        _ => PocketPage.coupons,
      },
    );
  }

  Future<void> selectOffer(CouponOffer offer) async {
    if (busy && !batching) return;
    FocusScope.of(context).unfocus();
    final inFlight = batching;
    cancelled = false;
    latestSelection = offer.key;
    if (selected.contains(offer.key)) {
      setState(() {
        selected.remove(offer.key);
        pendingRemovals[offer.key] = offer;
        assigned.remove(offer.key);
        selectionCache.remove(offer.key);
      });
      if (inFlight) {
        selectionChanged = true;
        return;
      }
      await activateSelection();
      return;
    }
    setState(() {
      pendingRemovals.remove(offer.key);
      selected.add(offer.key);
      selectionCache[offer.key] = offer.preview;
    });
    if (inFlight) {
      selectionChanged = true;
      return;
    }
    if (!offer.copies.any(usableCopy)) await work(refreshAll);
    if (!mounted || cancelled) return;
    await activateSelection(latestKey: offer.key);
  }

  Future<void> deactivateRemoved() async {
    while (pendingRemovals.isNotEmpty) {
      final entry = pendingRemovals.entries.first;
      // Consume the intent before sending: a failed DELETE is never replayed.
      pendingRemovals.remove(entry.key);
      if (selected.contains(entry.key)) continue;
      deactivating.add(entry.key);
      if (mounted) setState(() {});
      final seen = <String>{};
      try {
        for (final copy in entry.value.copies) {
          final a = copy.account;
          if (!book.accounts.contains(a) || !seen.add(copy.key)) continue;
          if (!a.fresh) await book.refresh(a);
          final detail = await a.api.detail(
            copy.coupon.id,
            copy.coupon.section,
          );
          if (!detail.activated) continue;
          a.fresh = false;
          try {
            await a.api.mutate(detail, false, {});
            attempted.remove(copy.key);
          } finally {
            try {
              await book.refresh(a);
            } catch (_) {}
          }
        }
      } catch (_) {
        pendingRemovals.clear();
        rethrow;
      } finally {
        deactivating.remove(entry.key);
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> activateSelection({String? latestKey}) async {
    final latestRetained = assigned[latestKey] ?? selectionCache[latestKey];
    reconcileSelection();
    if (latestRetained != null) {
      final matches = combined(book.accounts)
          .where((e) => e.key == latestRetained.key);
      if (matches.isNotEmpty &&
          occurrenceKey(matches.first) == occurrenceKey(latestRetained)) {
        latestKey = offerKey(matches.first);
      }
    }
    if (pendingRemovals.isNotEmpty) {
      var completed = false;
      await work(() async {
        await deactivateRemoved();
        completed = true;
      });
      if (!completed || !mounted) return;
    }
    final assignment = plan;
    assigned.addAll(assignment);
    final targets = assignment.values
        .where((e) => !e.coupon.activated && !attempted.contains(e.key))
        .toList();
    if (targets.isEmpty) {
      if (latestKey != null && !assignment.containsKey(latestKey)) {
        notice(
          'This coupon needs a refresh or account login before activation.',
        );
      }
      return;
    }
    // Never replay an uncertain mutation when another coupon is selected.

    activating.addAll(targets.map(offerKey));
    BatchResult? result;
    await work(() async {
      batching = true;
      if (mounted) setState(() {});
      try {
        result = await activateSelected(
          targets,
          false,
          () => cancelled,
          onAttempt: (entry) => attempted.add(entry.key),
        );
      } finally {
        batching = false;
        // Refresh only affected accounts, retaining the list and pictures.
        for (final a in targets.map((e) => e.account).toSet()) {
          try {
            await book.refresh(a);
          } catch (_) {}
        }
        for (final a in targets.map((e) => e.account).toSet()) {
          a.coupons = [
            for (final c in a.coupons)
              if (result?.confirmed.contains(a.key(c)) == true)
                Coupon({...c.raw, 'isActivated': true}, c.section)
              else
                c,
          ];
        }
        reconcileSelection();
        assigned.addAll(plan);
        activating.clear();
        if (mounted && page == PocketPage.checkout) prepareCheckoutCard();
      }
      final confirmed = combined(book.accounts)
          .where((e) => e.account.fresh && e.coupon.activated)
          .map((e) => e.key)
          .toSet();
      attempted.removeWhere(confirmed.contains);
      if (result?.failure != null) {
        notice(safeError(result!.failure!));
      } else if (result?.cancelled == true) {
        notice('Activation stopped. Review the remaining coupons in checkout.');
      } else if ((result?.choices ?? 0) > 0) {
        notice('Choose products to finish activating these coupons.');
      }
    });
    if (selectionChanged && mounted && !cancelled && result?.failure == null) {
      selectionChanged = false;
      await activateSelection(latestKey: latestSelection);
      return;
    }
    final latest = plan[latestKey];
    if (mounted &&
        (result?.choices ?? 0) > 0 &&
        latest != null &&
        !latest.coupon.activated) {
      await showDetail(latest, chooseProducts: true);
    }
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
        clearAccountSelection(a);
        api.pictures = pictures;
        clearPictures();
        await api.settings();
        await api.store.delete('coupons');
        if (oldCountry != api.country) {
          await api.store.delete('loyalty');
          await api.store.delete('import');
          a.card = '';
          a.cardImage = null;
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
    reconcileSelection();
    final home = page == PocketPage.coupons;
    final offers = aggregateCoupons(visible);
    final ordered = browseRows(offers).whereType<CouponOffer>().toList();
    return PopScope(
      canPop: home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: Scaffold(
        appBar: page == PocketPage.account
            ? null
            : AppBar(
                toolbarHeight: 64,
                leading: home ? null : BackButton(onPressed: back),
                title: home && searching
                    ? TextField(
                        controller: searchInput,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search coupons',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) => setState(() => search = value),
                      )
                    : Text(
                        switch (page) {
                          PocketPage.coupons => 'Coupon Pocket',
                          PocketPage.checkout => 'Checkout',
                          PocketPage.settings => 'Settings',
                          PocketPage.favourites => 'Favourites',
                          PocketPage.accounts => 'Accounts',
                          PocketPage.account =>
                            openedAccount?.label ?? 'Account',
                          PocketPage.filters => 'Coupon filters',
                        },
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.6,
                        ),
                      ),
                actions: [
                  if (batching)
                    IconButton(
                      tooltip: 'Stop activation',
                      onPressed: () => cancelled = true,
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  if (busy && !refreshing && !batching)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (home) ...[
                    IconButton(
                      tooltip: searching ? 'Close search' : 'Search',
                      icon: Icon(
                        searching ? Icons.close_rounded : Icons.search_rounded,
                      ),
                      onPressed: () {
                        setState(() {
                          searching = !searching;
                          if (!searching) {
                            search = '';
                            searchInput.clear();
                          }
                        });
                        if (!searching) FocusScope.of(context).unfocus();
                      },
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () =>
                          setState(() => page = PocketPage.settings),
                    ),
                  ],
                ],
              ),
        body: page == PocketPage.account && openedAccount != null
            ? CoverScroll(
                title: openedAccount!.label,
                onBack: back,
                titleAction: IconButton(
                  tooltip: 'Rename account',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: busy
                      ? null
                      : () => accountAction(openedAccount!, 'rename'),
                ),
                coverHeight: 160,
                cover: ColoredBox(
                  color: accountColor(openedAccount!).withValues(alpha: .18),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 88,
                    color: accountColor(openedAccount!),
                  ),
                ),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: accountPage(),
                ),
              )
            : Column(
                children: [
                  SizedBox(
                    height: 2,
                    child: refreshing
                        ? const LinearProgressIndicator(
                            minHeight: 2,
                            color: ink,
                            backgroundColor: acid,
                          )
                        : null,
                  ),
                  Expanded(
                    key: const ValueKey('page-content'),
                    child: RefreshIndicator(
                      onRefresh: busy || (!home && page != PocketPage.checkout)
                          ? () async {}
                          : () => work(refreshAll),
                      child: home
                          ? ordered.isEmpty
                                ? ListView(
                                    children: [
                                      emptyState(
                                        'No coupons found.',
                                        book.accounts.isEmpty
                                            ? 'Connect an account in Settings.'
                                            : 'Try another search or pull to refresh.',
                                      ),
                                    ],
                                  )
                                : CouponDeck(
                                    count: ordered.length,
                                    identity: (i) => ordered[i].key,
                                    builder: (i) => offerTile(ordered[i]),
                                  )
                          : ListView(
                              key: PageStorageKey(page),
                              controller: home ? scroll : null,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              children: switch (page) {
                                PocketPage.coupons => const [],
                                PocketPage.checkout => checkout(),
                                PocketPage.settings => settingsPage(),
                                PocketPage.favourites => favouritePage(),
                                PocketPage.accounts => accountsPage(),
                                PocketPage.account => accountPage(),
                                PocketPage.filters => filtersPage(),
                              },
                            ),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: home
            ? SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      textStyle: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: selected.isEmpty
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            setState(() => page = PocketPage.checkout);
                            prepareCheckoutCard();
                          },
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_bag_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selected.isEmpty
                                ? 'Continue'
                                : 'Continue · ${selected.length}',
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded),
                      ],
                    ),
                  ),
                ),
              )
            : batching
            ? SafeArea(
                child: TextButton(
                  onPressed: () => cancelled = true,
                  child: const Text('Stop activation'),
                ),
              )
            : null,
      ),
    );
  }

  Future<void> toggleFavourite(
    OwnedCoupon entry, {
    bool replace = false,
  }) async {
    if (busy) return;
    final c = entry.coupon;
    await work(() async {
      if (!replace && favourites.containsKey(favouriteName(c.title))) {
        await favouriteBook.remove(c.title);
        return;
      }
      var snapshot = c.raw;
      final previous = favouriteBook.entries[favouriteName(c.title)];
      var complete = false;
      try {
        final d = await entry.account.api.detail(c.id, c.section);
        snapshot = {...c.raw, ...d.raw};
        complete = true;
      } catch (_) {
        /* Keep the list preview when details cannot be read. */
      }
      if (replace && previous?.hasDetails == true && !complete) {
        notice('Could not update the preview. Your saved favourite is kept.');
        return;
      }
      Uint8List? bytes;
      if (entry.account.api.pictures && c.image.isNotEmpty) {
        try {
          bytes = await snapshotPicture(c.image);
        } catch (_) {}
      }
      if (bytes == null && previous?.coupon.image == c.image) {
        bytes = previous?.image;
      }
      await favouriteBook.put(
        SavedFavourite(
          title: c.title,
          snapshot: snapshot,
          image: bytes,
          locale: entry.account.api.language,
          section: c.section,
          hasDetails: complete,
          savedAt: widget.client.clock(),
        ),
      );
      if (!complete ||
          (entry.account.api.pictures && c.image.isNotEmpty && bytes == null)) {
        notice(
          'Favourite saved. Some preview content was unavailable; you can update it in Settings.',
        );
      }
    });
  }

  Future<void> openFavourites() async {
    setState(() => page = PocketPage.favourites);
    if (busy) return;
    for (final saved in favouriteBook.entries.values.toList()) {
      if (!mounted || page != PocketPage.favourites) break;
      if (saved.coupon.id != 'saved') continue;
      final matches = combined(book.accounts).where(
        (e) => favouriteName(e.coupon.title) == favouriteName(saved.title),
      );
      if (matches.isNotEmpty) {
        await toggleFavourite(matches.first, replace: true);
      }
    }
  }

  List<Widget> favouritePage() => [
    if (favouriteBook.entries.isEmpty)
      emptyState('No favourites yet.', 'Tap the star on a coupon to save it.'),
    for (final saved in favouriteBook.entries.values)
      Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surface,
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          leading: SizedBox(
            width: 60,
            height: 60,
            child: saved.image == null
                ? const Icon(Icons.local_offer_outlined)
                : Image.memory(
                    saved.image!,
                    cacheWidth: 120,
                    fit: BoxFit.contain,
                  ),
          ),
          title: Text(
            saved.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: IconButton(
            tooltip: 'Remove favourite',
            icon: const Icon(Icons.star_rounded),
            onPressed: busy
                ? null
                : () => work(() => favouriteBook.remove(saved.title)),
          ),
        ),
      ),
  ];

  List<Widget> filtersPage() => [
    const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        'Accounts',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: RadioGroup<String>(
        groupValue: accountFilter ?? '',
        onChanged: (value) =>
            setState(() => accountFilter = value == '' ? null : value),
        child: Column(
          children: [
            const RadioListTile<String>(
              controlAffinity: ListTileControlAffinity.trailing,
              value: '',
              title: Text('All accounts'),
              contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            ),
            for (final a in book.accounts) ...[
              const Divider(height: 1, indent: 18, endIndent: 18),
              RadioListTile<String>(
                controlAffinity: ListTileControlAffinity.trailing,
                value: a.id,
                title: Text(a.label),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 4,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    const SizedBox(height: 24),
    const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        'Offers',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        title: const Text('Include online offers'),
        value: !hideOnline,
        onChanged: busy
            ? null
            : (value) => work(() async {
                hideOnline = !value;
                await widget.client.store.write(
                  'view',
                  jsonEncode({'hideOnline': hideOnline}),
                );
              }),
      ),
    ),
    const SizedBox(height: 24),
    OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      onPressed: busy || (accountFilter == null && !hideOnline)
          ? null
          : () => work(() async {
              accountFilter = null;
              hideOnline = false;
              await widget.client.store.write(
                'view',
                jsonEncode({'hideOnline': false}),
              );
            }),
      icon: const Icon(Icons.restart_alt_rounded),
      label: const Text('Reset filters'),
    ),
  ];

  Widget emptyState(String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shopping_bag_outlined, size: 40),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 14),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -.3,
      ),
    ),
  );
  List<Object> browseRows(List<CouponOffer> offers) {
    final names = favourites;
    final starred = <CouponOffer>[], rest = <CouponOffer>[];
    for (final offer in offers) {
      (names.containsKey(favouriteName(offer.copies.first.coupon.title))
              ? starred
              : rest)
          .add(offer);
    }
    return [
      if (book.accounts.any((a) => a.coupons.isNotEmpty && !a.fresh) &&
          !batching)
        'Saved coupons',
      if (starred.isNotEmpty) 'Favourites',
      ...starred,
      if (starred.isNotEmpty && rest.isNotEmpty) 'More coupons',
      ...rest,
    ];
  }

  Widget pictureFor(OwnedCoupon e) =>
      e.account.api.pictures && e.coupon.image.isNotEmpty
      ? CouponPicture(
          key: ValueKey('${e.account.api.country}:${e.coupon.image}'),
          url: e.coupon.image,
        )
      : const Icon(Icons.local_offer_outlined, size: 40, color: Colors.grey);
  Widget offerTile(CouponOffer offer) {
    final account = assigned[offer.key]?.account.id;
    final e = offer.copies.firstWhere(
      (copy) => copy.account.id == account,
      orElse: () => offer.copies.first,
    );
    return CouponCard(
      key: ValueKey(offer.key),
      coupon: e.coupon,
      locale: e.account.api.language,
      image: pictureFor(e),
      selected: selected.contains(offer.key),
      favourite: favourites.containsKey(favouriteName(e.coupon.title)),
      onFavourite: busy ? null : () => toggleFavourite(e),
      onDetails: busy ? null : () => showDetail(e),
      onSelect: () {
        if (!busy || batching) selectOffer(offer);
      },
    );
  }

  Future<void> showQr(Account a) async {
    if (qrOpen) return;
    qrOpen = true;
    final requestedPage = page;
    try {
      if (a.card.isEmpty && a.cardImage == null && a.signedIn) {
        var loaded = false;
        Object? cardError;
        await work(() async {
          try {
            await loadCard(a);
            loaded = true;
          } catch (e) {
            cardError = e;
            rethrow;
          }
        });
        if (!loaded) {
          if (cardError is! CardUnavailableException ||
              !mounted ||
              page != requestedPage) {
            return;
          }
          final import = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Use your existing card'),
              content: const Text(
                'Lidl’s card service returned 404. Import your account’s cropped QR image or QR text to scan it here.',
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
          if (import != true || !mounted) return;
          await importCard(a);
          if (a.card.isEmpty && a.cardImage == null) return;
          notice('');
        }
      }
      if (!mounted || page != requestedPage) return;
      if (a.card.isEmpty && a.cardImage == null) {
        notice(
          'No card available. Connect or import this account’s card in Settings.',
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              leading: CloseButton(onPressed: () => Navigator.pop(ctx)),
              title: Text(a.label),
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code_2_rounded, size: 28),
                      const SizedBox(height: 16),
                      Text(
                        'Scan ${a.label}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        a.api.country,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: a.cardImage != null
                            ? Image.memory(
                                a.cardImage!,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.none,
                              )
                            : QrImageView(
                                key: ValueKey('qr-${a.id}'),
                                data: a.card,
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.all(20),
                              ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      qrOpen = false;
    }
  }

  final loadingCards = <String>{};
  final cardErrors = <String, String>{};

  Future<void> ensureCard(Account a) async {
    if (a.card.isNotEmpty ||
        a.cardImage != null ||
        !a.signedIn ||
        loadingCards.contains(a.id))
      return;
    setState(() {
      loadingCards.add(a.id);
      cardErrors.remove(a.id);
    });
    try {
      await queue.run(() => loadCard(a));
    } catch (e) {
      cardErrors[a.id] = safeError(e);
      notice(
        'Card could not be loaded. Try again or import your existing card.',
      );
    } finally {
      if (mounted) setState(() => loadingCards.remove(a.id));
    }
  }

  void prepareCheckoutCard() {
    final accounts = basket.map((e) => e.account).toSet();
    if (accounts.length == 1) ensureCard(accounts.single);
  }

  Widget cardArtwork(Account a, {double size = 260}) => SizedBox(
    width: size,
    height: size,
    child: a.cardImage != null
        ? Image.memory(
            a.cardImage!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          )
        : QrImageView(
            key: ValueKey('inline-qr-${a.id}'),
            data: a.card,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.all(12),
          ),
  );

  Widget inlineCard(Account a, {bool showName = true}) => Card(
    color: Theme.of(context).colorScheme.surface,
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (showName)
            Text(
              a.label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: accountColor(a),
              ),
            ),
          if (showName) const SizedBox(height: 12),
          if (a.card.isNotEmpty || a.cardImage != null) ...[
            cardArtwork(a),
            const SizedBox(height: 8),
            const Text('Scan this card at checkout'),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: loadingCards.contains(a.id)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2_rounded),
              title: Text(
                loadingCards.contains(a.id) ? 'Loading card…' : 'Account card',
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (a.signedIn)
                  TextButton(
                    onPressed: loadingCards.contains(a.id)
                        ? null
                        : () => ensureCard(a),
                    child: const Text('Load card'),
                  ),
                OutlinedButton(
                  onPressed: loadingCards.contains(a.id)
                      ? null
                      : () async {
                          await importCard(a);
                          if (mounted) setState(() {});
                        },
                  child: const Text('Import card'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> resolveCheckoutItem(OwnedCoupon entry) async {
    if (busy) {
      notice('Please wait for the current selection to finish.');
      return;
    }
    Detail? detail;
    await work(() async {
      if (!entry.account.fresh) await book.refresh(entry.account);
      detail = await entry.account.api.detail(
        entry.coupon.id,
        entry.coupon.section,
      );
      entry.account.coupons = [
        for (final c in entry.account.coupons)
          if (c.id == entry.coupon.id)
            Coupon({
              ...c.raw,
              'isActivated': detail!.activated,
              'isProcessing': detail!.processing,
            }, c.section)
          else
            c,
      ];
    });
    if (detail == null || !mounted || page != PocketPage.checkout) return;
    reconcileSelection();
    final updated = OwnedCoupon(entry.account, detail!);
    if (detail!.activated) {
      attempted.remove(entry.key);
      await showDetail(updated);
      return;
    }
    if (!await confirm('Activate ${detail!.title}?')) return;
    if (!mounted || page != PocketPage.checkout) return;
    // The user explicitly retries after a fresh read; never replay automatically.
    attempted.remove(entry.key);
    await activateSelection(
      latestKey: offerKey(
        OwnedCoupon(
          entry.account,
          entry.account.coupons.firstWhere(
            (c) => c.id == entry.coupon.id,
            orElse: () => entry.coupon,
          ),
        ),
      ),
    );
  }

  Widget checkoutItem(OwnedCoupon e) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 52, height: 52, child: pictureFor(e)),
    ),
    title: Text(
      e.coupon.title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      !e.account.fresh
          ? 'Refresh to verify'
          : e.coupon.processing
          ? 'Processing…'
          : e.coupon.activated
          ? e.coupon.benefit
          : 'Needs activation',
    ),
    trailing: Icon(
      e.account.fresh && e.coupon.activated
          ? Icons.check_circle_outline
          : Icons.chevron_right_rounded,
      color: e.coupon.activated ? const Color(0xff65824c) : null,
    ),
    onTap: () => resolveCheckoutItem(e),
  );

  List<Widget> checkout() {
    final grouped = <Account, List<OwnedCoupon>>{};
    for (final e in basket) {
      (grouped[e.account] ??= []).add(e);
    }
    final single = grouped.length == 1;
    return [
      if (grouped.isEmpty)
        emptyState(
          'Choose your coupons first.',
          'Select offers for this shop.',
        ),
      if (single) ...[
        inlineCard(grouped.keys.single),
        heading('${grouped.values.single.length} selected offers'),
        Card(
          color: Theme.of(context).colorScheme.surface,
          elevation: 0,
          child: Column(
            children: [for (final e in grouped.values.single) checkoutItem(e)],
          ),
        ),
      ] else
        for (final group in grouped.entries)
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: accountColor(group.key).withValues(alpha: .3),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: accountColor(group.key)
                        .withValues(alpha: .15),
                    child: Icon(
                      Icons.person_outline_rounded,
                      color: accountColor(group.key),
                    ),
                  ),
                  title: Text(
                    group.key.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${group.value.length} ${group.value.length == 1 ? 'coupon' : 'coupons'}',
                  ),
                  trailing: Icon(
                    expandedAccounts.contains(group.key.id)
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  onTap: () => setState(() {
                    if (!expandedAccounts.add(group.key.id))
                      expandedAccounts.remove(group.key.id);
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accountColor(group.key),
                      ),
                      onPressed: busy ? null : () => showQr(group.key),
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('Show QR code'),
                    ),
                  ),
                ),
                if (expandedAccounts.contains(group.key.id)) ...[
                  const Divider(height: 1),
                  for (final e in group.value) checkoutItem(e),
                ],
              ],
            ),
          ),
      if (grouped.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffa43e3e),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: busy
                ? null
                : () => setState(() {
                    selected.clear();
                    pendingRemovals.clear();
                    assigned.clear();
                    selectionCache.clear();
                    page = PocketPage.coupons;
                  }),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Clear shopping list'),
          ),
        ),
    ];
  }

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
            clearAccountSelection(a);
            if (accountFilter == a.id) accountFilter = null;
            clearPictures();
          });
        }
    }
  }

  Color accountColor(Account a) {
    const palette = [
      Color(0xff527caa),
      Color(0xff9271a8),
      Color(0xff409080),
      Color(0xffbd8052),
      Color(0xffb2637b),
      Color(0xff6e8749),
    ];
    final index = book.accounts.indexOf(a);
    return palette[(index < 0 ? 0 : index) % palette.length];
  }

  Widget actionLink(
    String title,
    IconData icon,
    VoidCallback? onTap, {
    String? subtitle,
    Color? color,
  }) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: (color ?? Theme.of(context).colorScheme.onSurface).withValues(
            alpha: .08,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: color ?? Theme.of(context).colorScheme.onSurface,
          size: 23,
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 13, height: 1.5)),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: color ?? const Color(0xff8b9188),
      ),
      onTap: onTap,
    ),
  );

  List<Widget> settingsPage() => [
    Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        secondary: const Icon(Icons.dark_mode_outlined),
        title: const Text('Dark mode'),
        value: widget.dark,
        onChanged: widget.onDarkChanged,
      ),
    ),
    actionLink(
      'Coupon filters',
      Icons.tune_rounded,
      () => setState(() => page = PocketPage.filters),
    ),
    actionLink(
      'Favourites',
      Icons.star_outline_rounded,
      openFavourites,
      subtitle: 'Saved coupons, pictures and details',
    ),
    actionLink(
      'Accounts',
      Icons.person_outline_rounded,
      () => setState(() => page = PocketPage.accounts),
      subtitle: 'Manage your connected accounts',
    ),
  ];

  List<Widget> accountsPage() => [
    for (final a in book.accounts)
      actionLink(
        a.label,
        Icons.person_outline_rounded,
        () {
          setState(() {
            openedAccount = a;
            page = PocketPage.account;
          });
          ensureCard(a);
        },
        color: accountColor(a),
        subtitle: a.awaitingLogin
            ? 'Finish login'
            : !a.signedIn || a.sessionExpired
            ? 'Sign in needed'
            : null,
      ),
    actionLink('Add account', Icons.add_rounded, busy ? null : addAccount),
    if (!canLogin)
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Connect accounts in the mobile app. Card imports are available here.',
        ),
      ),
  ];

  List<Widget> accountPage() {
    final a = openedAccount;
    if (a == null || !book.accounts.contains(a)) return [];
    final color = accountColor(a);
    return [
      heading('Lidl Plus card'),
      inlineCard(a, showName: false),
      ExpansionTile(
        title: const Text('Card options'),
        children: [
          if (a.signedIn)
            actionLink(
              'Refresh card',
              Icons.refresh_rounded,
              busy ? null : () => work(() => loadCard(a)),
              color: color,
            ),
          actionLink(
            'Replace with existing card',
            Icons.qr_code_scanner_rounded,
            busy ? null : () => importCard(a),
            color: color,
          ),
        ],
      ),
      heading('Account preferences'),
      actionLink(
        'Preferences',
        Icons.tune_rounded,
        busy ? null : () => settings(a),
        subtitle: 'Region, language and pictures',
        color: color,
      ),
      heading('Connection'),
      if (a.awaitingLogin) ...[
        actionLink(
          'Finish browser login',
          Icons.open_in_browser_rounded,
          null,
          subtitle: 'Return from the browser to connect this account.',
          color: color,
        ),
        actionLink(
          'Cancel login',
          Icons.close_rounded,
          busy ? null : () => work(() => book.cancelLogin(a)),
          color: color,
        ),
      ] else if (canLogin)
        actionLink(
          a.signedIn && !a.sessionExpired ? 'Reconnect account' : 'Log in',
          Icons.login_rounded,
          busy ? null : () => work(() => login(a)),
          color: color,
        ),
      const SizedBox(height: 12),
      actionLink(
        'Remove account',
        Icons.delete_outline_rounded,
        busy
            ? null
            : () async {
                await accountAction(a, 'remove');
                if (mounted && !book.accounts.contains(a)) {
                  setState(() => page = PocketPage.accounts);
                }
              },
        color: const Color(0xffa54e4e),
      ),
    ];
  }
}

class CouponPicture extends StatefulWidget {
  final String url;
  const CouponPicture({super.key, required this.url});
  @override
  State<CouponPicture> createState() => _CouponPictureState();
}

class _CouponPictureState extends State<CouponPicture> {
  late var data = picture(widget.url);
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: data,
    builder: (ctx, snapshot) => snapshot.connectionState != ConnectionState.done
        ? const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : snapshot.data == null
        ? Center(
            child: IconButton(
              tooltip: 'Retry image',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => data = picture(widget.url)),
            ),
          )
        : Image.memory(snapshot.data!, fit: BoxFit.contain, cacheWidth: 600),
  );
}
