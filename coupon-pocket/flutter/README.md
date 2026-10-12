# Coupon Pocket Flutter port

The Dart application in this directory targets Android (API 28+, target 35), iOS (15+) and web. The existing Java Android app remains in `../app`; its packaged APK remains version 0.3.0. The Flutter app is version 0.12.3 and uses a separate Android application ID (`local.couponpocket.coupon_pocket`), so it can be evaluated alongside the original without replacing its data or signing identity. The original development key is untouched. No captured account data is included.

## 0.8.1: square image cards

Browse cards now use square artwork with title/offer text over a dark lower gradient, the favourite star at the top and the selection button at the bottom beside the offer. There is no extra picture padding or separate caption row. The overlay uses a simple gradient without blur or shadows; the existing lazy feed and bounded image pipeline remain. Long titles use two lines with full text available in Details. Settings filters no longer offer selection of all matching coupons; the unused UI helper is removed. This is a reversible visual change, verified by the release build without another test run.

## 0.8.0: faster browsing and simpler shopping

Phone builds now use optimized release compilation with the same local development signing identity, allowing an in-place update with existing data retained. The feed uses a lazy builder and a short prefetch range; card rendering no longer solves the account-cover problem for every offer. Pictures share in-flight requests, load at most three concurrently and use a compressed LRU cache bounded by 32 entries / 16 MiB. Image decoding is bounded to display-sized thumbnails. These remove concrete sources of unnecessary work; smoothness still needs phone validation rather than a claimed benchmark.

The magnifying glass opens an inline text box in the header. Matching results update as you type, with no results/confirm step. Account and online filters, reset and selection of all matching coupons are in Settings → Coupon filters. Browse cards have a large image, a favourite star over it, and name/benefit beneath with a plus/check action alongside. Details keep expiry and all purchase conditions. The checkout footer has a solid dark button and selected count, clearly separated from the background. Checkout initially shows only coloured account summaries, item counts and QR buttons; tap a summary to expand compact coupon rows. Favourite management uses small image/name rows with removal, while retaining the existing complete stored snapshots.

The loyalty fetch retains the original `/api/v1/{country}/loyalty` route and, only after HTTP 404, tries the independently documented `/profile/api/v1/{country}/loyalty` route on the same host. Other failures are not masked or sent to guessed services. Both responses must provide a valid server-issued string; no JWT claim is turned into a card. The alternate path is present in [this API client's source](https://github.com/Andre0512/lidl-plus/blob/master/lidlplus/api.py), which is evidence for its use, not proof of current availability. Workstation probes could not connect and live success is not claimed.

If both routes return 404, the QR flow offers import of an existing card. Android can select a cropped QR image through the system document picker without storage/camera permissions. It accepts at most 4 MiB of source data, caps source dimensions/pixel count, samples to at most 1024 pixels per side and re-encodes to a maximum 512 KiB PNG without metadata on a native worker. The image is encrypted in its account's existing import record and displayed offline with account/country binding. QR-text import remains available on all platforms; image import is currently Android-only. Imports retain display priority, are cleared on a new login/country change and never get uploaded.

Three focused offline checks cover the exact 404 fallback, non-404 failure handling, lazy feed construction, immediate search, selection and collapsed/expanded checkout. The full suite was not repeated for this update.

## 0.7.1: stable interactions and separate settings screens

The progress bar previously changed the position of the list in its parent, causing it to be recreated when work started or ended. The list now retains its identity and scroll position. Routine actions use a small header indicator; activation progress belongs to the affected coupon. Selecting further coupons during a batch updates the visible selection immediately and reconciles the new account plan after the in-flight batch, while preserving stop-on-failure and no replay.

Checkout planning now treats list data as preview data, rather than attempting to construct a validated detail model from it. List-only product groups and date-only display values no longer exclude an offer before the fresh detail eligibility check. Offer identity uses explicit validity fields, avoiding changes caused solely by JSON property order. Checkout resolves retained assignments against the latest account coupons, so a processing or unavailable copy cannot silently display its old inactive state.

Native service requests now include the Java client's JSON Accept header and a fixed UTF-8 body length instead of sending chunked activation bodies. Card errors retain the service/network error instead of being overwritten by a generic missing-card notice. An empty imported-card record no longer masks a valid saved card. These corrections require live phone validation; no remote activation or card-fetch success is claimed from offline checks.

Settings contains separate Favourites and Accounts links. Accounts appear as coloured cards, each opening its own management screen. The same colours identify checkout groups. Sync timestamps and language/status summaries are removed from account cards. Search actions, checkout and QR links share the rounded white link-card style. Four focused offline checks cover preview planning, stable offer identity, uncertain mutation no-replay and required product choices; no full suite was repeated for this update.

## 0.7.0: select, checkout and scan

The default screen shows aggregated coupons in one column of rounded white cards, with prominent pictures, discount/expiry summaries and aligned selection, favourite and details actions. Matching offers across accounts appear once; different countries, campaign IDs, prices or validity remain distinct. Favourites appear first, followed by sale-size ordering. Search contains title/account/online filters and **Select all results**. Account and favourite management live in the top-right Settings screen.

Selecting an offer automatically activates it on the account combination requiring the fewest QR codes. The exact cover considers fresh, usable copies and prefers already activated copies when account counts tie. Product choices require an explicit selection; no choice is guessed. Mutations remain serial, server-confirmed and stop on the first failed or uncertain result. An uncertain mutation is not automatically retried by selecting another offer. Reassignment can leave earlier account copies activated; Details offers explicit deactivation. Deselecting or finishing shopping clears the current selection, not remote activations. The shopping selection lasts for the current app session.

A bottom **Checkout** button opens a separate screen with a back arrow and selected coupons grouped by their assigned accounts. Each group has its own **Show QR code** button. Only one account QR can be open at a time, in a separate screen clearly labelled with the account.

Favourites now save the current coupon fields, full details when available, and a bounded PNG thumbnail when pictures are enabled. Settings displays the same card and readable details even after the offer disappears. Older name-only favourites migrate without loss and gain previews when a matching current offer is available. Snapshots use encrypted native storage and contain no account tokens or account identifiers. Saved thumbnails remain until the favourite is removed; image requests retain the existing token-free/public-destination rules. Web snapshots remain in memory and have no image capture.

Offline checks and static analysis passed before packaging. The Android update was installed over the existing app through ADB, preserving its data. The new selection/checkout flow and real checkout scanning still need the user's phone validation. Earlier version sections below describe historical layouts.

## 0.6.1: image TLS and readable details

The image client's custom connection factory previously returned a plain TCP socket on port 443. Dart's HttpClient does not automatically upgrade a custom socket to TLS, so image requests failed. The factory now upgrades the same checked, pinned public-address socket using the URL hostname for TLS SNI and normal certificate validation, without a second DNS lookup or certificate bypass. Images still receive no account headers, cookies or referrer. A loading indicator replaces the empty area while fetching; a failed download offers **Retry image**.

The favourite star is fixed in the card's upper-right corner instead of wrapping onto its own action line. Coupon rows omit the discount description (such as “sleva”, “mega cena” and maximum-per-purchase wording); the main discount and expiry remain. The full description is preserved in details under **Discount & purchase limits**.

Details use a smaller title, separate discount/expiry summary and expandable sections for the offer, conditions, product information and availability. Purchase limits open initially. Provider paragraphs and lists become spaced plain text, HTML entities are decoded, exact duplicate blocks are removed, and very long paragraphs are broken between sentences. No embedded resources are loaded and no conditions are truncated.

45 offline tests cover the existing protocol/account rules plus a local socket regression proving that the image connection starts a TLS handshake and rejects a plaintext server, preservation of limits/conditions and detail expansion. Static analysis and Android/web builds pass. Version 0.6.1 was installed through ADB with existing app data retained. Actual CDN image delivery and live coupon actions remain for phone validation.

## 0.6.0: images, search and favourites

Coupons and Activated now use one vertical column of full-width rows with prominent, unfaded product images. Account totals, the large introductory heading, top account chips, navigation counts and floating activation/online controls are removed. Ownership labels remain on coupons when several accounts are present, so actions still identify the intended profile. QR cards are available in Checkout.

The header search button opens title search, account selection, an optional online-coupon filter and batch activation. **Activate all results** targets the current search/account/filter results; **Activate selected** retains the existing selection across filters. Both require confirmation and keep the existing serial, fresh-eligibility, no-replay mutation rules. The only floating action during a batch is cancellation.

Star any coupon to save its title. Returning titles match after case and whitespace normalization, across accounts and coupon IDs, and appear in a separate **Favourites** category at the top. Manage saved names in **Checkout → Settings → Favourites** or individual account settings. Names remain saved when coupons disappear, in the existing encrypted local storage on Android/iOS (memory only on web).

Within each category, explicit percentage discounts sort largest first, followed by cash discounts grouped by currency and sorted largest first. Unrecognized discount labels follow in title order. The sorter reads only the supplied discount title, never product prices or unrelated fields; percentage and cash savings cannot be compared without a purchase price. Displayed discount text and conditions are preserved.

Static analysis, 42 offline tests, Android debug APK compilation and web release compilation pass. The update was installed over the connected phone's existing Flutter package using ADB. Device gestures, image delivery, live activation and checkout scanning remain for user testing. The packaged APK is `../dist/coupon-pocket-flutter-dev.apk`; the original Java APK remains separate.

## 0.5.1: account state and navigation

Checkout displays connection status, last successful sync, coupon/activation/selection counts and card readiness. Rename, settings, card import/refresh, reconnect and removal live in the account overflow menu. Login launch failures clear pending state; pending login survives recreation, can be cancelled and expires after ten minutes. Expiry checks only inspect local state. The navigation now uses bordered typography with destination counts.

## 0.5.0: multiple accounts and graphic UI

**Add account** creates a locally named profile and opens Lidl browser login. Repeat for each account you want to connect; rename profiles inside Checkout. The authorization request asks the provider to reauthenticate (`prompt=login`), but account chooser/provider behavior still needs live validation. Choose the intended credentials in the browser; local profile labels are not a verified provider identity and connecting the same Lidl account twice does not create another account.

Automatic remote account registration is not implemented. The observed protocol covers login, not signup. Lidl's [Czech participation terms](https://www.lidl.cz/c/podminky-ucasti-lidl-plus/s10007920) require mobile-number verification to complete registration. New registrations must use the provider's registration/verification flow, then be connected here. There is no generated-email/password service, signup API, SMS automation or invented account/card identity.

The Coupons tab combines saved accounts, shows ownership on each coupon and offers account filter chips. Select coupons while moving between accounts; **Activate selected** targets the complete selected set across account filters. **Activate all** targets the current visible account/filter view. Hiding ONLINESHOP clears hidden selections. Product-choice coupons are skipped by either bulk action; tap their titles to configure individual choices. Accounts process serially, and the first failed/uncertain mutation stops the entire multi-account batch.

Activated coupons are grouped by account with that account's own QR panel. Cards are automatically requested after successful login when possible and can be loaded/imported individually in Checkout. QR panels also appear for all saved profiles in Checkout. Region settings, card imports, coupon caches, tokens and refresh failures are separate for each profile. Removing one profile erases only that profile's local data; Erase all local data clears every profile. Neither operation deletes a Lidl account or revokes a browser session.

Existing single-account state migrates once to Account 1, committing the encrypted account book before removing legacy entries. The book is stored under the encrypted `accounts` vault entry with serialized read/modify/write transactions. One browser login can be pending at a time; starting a login for another profile invalidates the older pending login. Successful re-login clears cards/cache only in the target profile. Web still keeps the whole account book in memory.

The UI uses warm off-white surfaces, hard black borders and offset shadows, oversized typography, lime selections and small monospace account labels. Compact two-column cards, fading mobile pictures, the three navigation destinations, pull-to-refresh, accessible header refresh and Checkout settings remain. Rendered preview images use synthetic coupons and QR text, not account captures.

## Run and build

Use Flutter 3.47.5 / Dart 3.13.4 (the versions used for validation) or a compatible stable release. Dependencies are locked in `pubspec.lock`.

```sh
cd coupon-pocket/flutter
flutter pub get
flutter analyze
flutter test
flutter run -d <android-or-ios-device>
flutter run -d chrome
flutter build apk --release
flutter build web --release --no-web-resources-cdn
```

The web build serves its Flutter rendering assets locally. Serve `build/web/` over HTTPS (localhost is suitable for development); do not open `index.html` as a local file. Use `--base-href /your-path/` when hosting below a subdirectory.

Android requires a complete Android SDK, the Flutter-selected NDK, accepted SDK licenses and JDK 17+. Configure `ANDROID_HOME` or `flutter config --android-sdk <path>`. The release configuration deliberately retains the existing debug signing identity for compatible local evaluation updates; configure your own release signing before distribution. Do not upload keys or `key.properties`.

On macOS with Xcode, CocoaPods/Swift Package Manager and a signing team, run:

```sh
flutter build ios --no-codesign
flutter build ipa
```

iOS compilation and signing cannot be done on this Windows workstation. The configured iOS deployment target is 15.0. Run the app on an iPhone to verify browser callback delivery and Keychain behavior before distributing it.

## Implemented behavior

- Neutral rounded surfaces, lazy one-column image-led aggregated coupons, readable expandable details, contrasting bottom Checkout action and top-right Settings.
- Pull-to-refresh, inline live search, Settings filters, selection-triggered activation, minimum-account checkout planning, collapsible checkout summaries and compact favourite management.
- OAuth authorization-code login with SHA-256 PKCE, state/nonce, strict callback parsing, duplicate rejection, ten-minute expiry and consumed pending login.
- Original Basic token authentication for exchange/refresh; Bearer account calls use the corrected coupon API prefix and locale headers. Store ID is limited to the list route.
- Product selections use returned IDs, then re-read details and validate membership/state before POST/PATCH. DELETE remains bodyless; basic activation has a JSON selection body.
- Shared serial work queue, persisted cache invalidation before mutations, no automatic mutation retries, read-only token-refresh retry, fresh batch eligibility, deduplication, stop on first failure, cancellation after an in-flight request and confirmed-result reporting.
- Account loyalty retrieval, explicit QR-text imports with display priority, local QR generation, country/account card clearing and local logout erasure.
- Supplied discount text and calendar expiry dates are retained. No fabricated loyalty payloads, guessed product choices, optimistic activations, telemetry or background refresh.

## Platform boundaries

**Android:** the small platform bridge reuses the original `Vault` implementation: AES-GCM, filename AAD, non-exportable Android Keystore key and non-backup files. Only INTERNET is declared in the release manifest; screenshots remain allowed. The Flutter package has independent storage, with no automatic migration from the Java app. Both apps and the official app can register the same callback scheme, so Android may offer a handler chooser.

**iOS:** `flutter_secure_storage` uses device-only, unlocked Keychain storage. Keychain is a different platform mechanism from Android's filename-bound vault. Imported cards and session state use the same account/country clearing rules. The native callback scheme is registered in Info.plist. Scheme delivery, persistence across reinstall and checkout scanning are not verified on a phone.

**Web:** shared UI, model/protocol logic, settings, card-text import and offline QR rendering compile and are available. All state, including tokens and pending login, stays in memory and disappears on reload; no localStorage, cookies or persistent browser vault is used. Browser Fetch omits credentials and referrers and rejects redirects. Product pictures are disabled on web because browser APIs cannot enforce DNS/public-destination checks.

Live web account functionality is **not established**: Lidl must permit the hosting origin via CORS, and the observed OAuth client redirects to `com.lidlplus.app://callback`, not an HTTPS browser callback. The web UI therefore blocks browser login before opening an unusable authentication flow or creating a pending profile. Card import remains available. Native mobile accounts show waiting, cancellation and expiry states; manual callback completion is only offered for a pending native login. There is no backend proxy, token relay, browser security bypass or new OAuth registration in this port. A normal automatic web login needs a provider-approved web client/callback or an explicitly designed trusted backend; serving the static build alone does not solve that dependency. Reloading the page during login discards its pending state.

Native images use an independent authorization-free HTTP client, pin the checked public DNS destination for the connection, reject redirects, cap downloads at 2 MiB and source dimensions at 8192 per side / 16 million pixels, decode sampled thumbnails and bound the compressed memory cache to 32 entries / 16 MiB. At most three picture downloads run concurrently. Disabling pictures or changing region/account clears cached/in-flight results. Explicitly saved favourites additionally retain a re-encoded PNG at most 400 pixels per side and 512 KiB in encrypted storage. HTML terms are shown as text and never loaded as embedded resources.

## Validation and remaining checks

Offline checks cover protocol/account isolation, mutation no-replay and cancellation, fresh choice validation, exact account-cover planning and favourite snapshot migration/storage. Widget checks cover narrow screens and large text, stale-cache gating, automatic activation, checkout grouping and displaying one QR at a time. These checks do not contact Lidl. `test/design_test.dart` optionally accepts local `PREVIEW_FONT`, `PREVIEW_BOLD`, `PREVIEW_MONO` and `PREVIEW_ICONS` Dart defines to render readable synthetic previews under `build/previews`; local font files are not redistributed.

The web release build and Android release APK build pass. Version 0.8.0 was installed through ADB and confirmed non-debuggable; no IPA is claimed. Live login, image delivery, Keystore/Keychain behavior, checkout acceptance and live batch execution require device/account validation. The Java app's earlier reported successes do not establish those results for Flutter.

`../package.py` regenerates `../dist/coupon-pocket-source.zip`, an optional built web ZIP and SHA256SUMS without private keys, generated build caches, personal configuration or account responses.

### 0.9.0

The coupon browser uses a lazy Wallet-style vertical stack of overlapping square cards, without the routine Active label. Continue is a larger bottom action. Checkout shows a single account's card directly above its items; multiple accounts retain individual QR buttons and expandable items. Offer details opens as a separate page with visible limits, progressive/searchable products and expandable explanatory sections. Account tools are grouped into card, preferences and connection.

Android loyalty reads now use HttpsURLConnection through a narrowly scoped native bridge, matching the networking implementation in the Java app reported working by the user. Exact loyalty paths, Bearer/Country/language headers, redirect rejection, bounded responses, 401 read refresh and encrypted card binding are retained. This is a transport compatibility change; successful live card retrieval and store scanning require phone validation. No card identifier is derived from identity claims.

### 0.9.1

Removed the coupon counter. The Rolodex-style stack uses continuous native scrolling rather than page snapping. Scroll pixels map directly to card movement, lower cards always paint in front, and cards near the lower edge fold down from their top hinge to expose the flat card above. Nearby card artwork stays behind repaint boundaries; scroll animation changes only paint transforms, without sorting or repositioning layout on every frame. Smoothness still needs assessment on the phone.

### 0.9.2

Removed the browse Coupons label, softened lower-card tilt and added gentle tilt to upper cards. Checkout has a red Clear shopping list action that clears local selection. Filters use aligned account radio rows and an online-offer switch in matching panels, consistent section spacing and an outlined reset action. Reversible visual changes are checked by the release build; no additional test suite was run.

### 0.10.0

Card taps select/activate and remove/deactivate coupons, using serial fresh-detail validation and no automatic DELETE replay. Info below the star opens read-only offer details; choosing required products retains a separate Save product choices action. Continue remains visible when empty to preserve carousel geometry. Favourites use bright yellow stars and a gold shadow, without a category heading. Cards are larger, lower spacing is wider, and flick velocity/momentum is reduced. Detail typography has clearer hierarchy, a tinted offer summary and grouped product/conditions panels. Failed/loading account cards no longer reserve a full-height QR placeholder.

Google Sans Flex is bundled from the official [Google Fonts source](https://github.com/google/fonts/tree/main/ofl/googlesansflex), using its rounded axis. The included assets/fonts/OFL.txt contains the SIL Open Font License. No font requests occur at runtime. Live smoothness, activation/deactivation and card behavior still need phone assessment.

The existing focused flow check passed for lazy scrolling, immediate search, stable card geometry across selection, server-confirmed activation/deactivation and single-account checkout. Search clamps a retained scroll offset when the result list shrinks, preventing the remaining card from jumping on selection. The release APK was installed through ADB with existing data preserved; no broad suite was repeated.

### 0.11.0

Errors and notices use floating, dismissible snackbars and no longer insert a banner into the page layout. A lightweight gradient softens the carousel's top edge. Upper cards shrink gently to compensate for perspective enlargement. Nearby card widgets are reused during focus changes and retained only within a bounded range; release performance still needs phone assessment.

Offer details uses a full-width square cover followed by a rounded content sheet. The title travels with the sheet and stays pinned below the back arrow as the sheet covers the image. Account details uses the same header with one account name and a rename pen beside it. Failed or loading account cards have compact rows and actions, with no reserved QR-size or skeleton panel. Product search uses a rounded field.

A top-level Settings switch controls dark mode. The preference is stored separately in the existing root vault, without changing account/coupon settings. Surfaces, body text and detail panels follow the chosen theme; QR codes retain a white background for scanning. One existing focused flow check passed, including scrolling the new detail screen. No broad test suite was repeated. Live card fetching remains subject to phone verification.

### 0.12.0

Rear cards stay horizontally centered while scaling; the extra horizontal translation was redundant with the transform pivot. Browse cards omit mutation-status text and the plus/check button, retaining tap selection and a bright green outline. The cover image starts at the screen top beneath a floating back arrow. The sheet title collapses onto the same toolbar row as the arrow; rounded corners flatten on collapse so the image cannot show through at the top.

Selection keys reconcile presentation changes only for the same account/campaign occurrence, while distinct countries, periods and prices remain separated during aggregation. Checkout deduplicates canonical offers. Successful POST responses and fresh active detail reads remain confirmed even if the immediate list refresh lags. Only actually sent requests enter the uncertain-attempt set; skipped, cancelled or never-sent targets are not blocked. Inactive checkout rows fetch fresh state and offer an explicit confirmed retry, including required product choices. Busy rows explain the wait through an overlay rather than silently ignoring taps. Automatic mutation replay remains prohibited.

Two focused offline checks passed: the existing selection/search/checkout flow now includes changing discount presentation and a lagging list response; a fake-server batch check verifies that the third target is never attempted after an uncertain second request and only the successful first request is confirmed. Release UI feel and real account behavior still need phone validation.

### 0.12.1

Favourite stars use the same white circular button surface as the info action, keeping the yellow filled star for saved offers. Favourite card shadows/glow are removed. Offer-detail artwork moves at one quarter of the content scroll distance beneath the covering sheet, with a repaint boundary around the image. Parallax is disabled when the system requests reduced motion; account covers retain their existing behavior. This visual update is verified by release compilation without additional tests. Phone assessment remains the check for animation feel.

### 0.12.2

The offer image sits below the system inset plus 32 logical pixels, while a median sample of its top-edge colour extends its background to the screen top. Colour sampling decodes a bounded 16-pixel thumbnail once per detail view, disposes codec/image resources and uses the existing token-free picture pipeline. Parallax and the covering sheet remain. Selection now has one four-pixel lime border, with no white under-border. This visual update is checked by release compilation without additional tests; phone rendering remains for user assessment.

### 0.12.3

Every exposed carousel card accepts its own selection, favourite and info taps immediately. Removed the off-centre pointer interception and tap-to-focus wrapper; transformed hit testing and fixed front-to-back paint order select the visible card under the finger. Native drag gesture arbitration remains. Nearby cards retain their bounded reuse and repaint boundaries. Verified by release compilation without additional tests; overlapping-card touch feel remains for phone assessment.
