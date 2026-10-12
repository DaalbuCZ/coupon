# Coupon Pocket Flutter port

The Dart application in this directory targets Android (API 28+, target 35), iOS (15+) and web. The existing Java Android app remains in `../app`; its packaged APK remains version 0.3.0. The Flutter app is version 0.5.1 and uses a separate Android application ID (`local.couponpocket.coupon_pocket`), so it can be evaluated alongside the original without replacing its data or signing identity. The original development key is untouched. No captured account data is included.

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
flutter build apk --debug
flutter build web --release --no-web-resources-cdn
```

The web build serves its Flutter rendering assets locally. Serve `build/web/` over HTTPS (localhost is suitable for development); do not open `index.html` as a local file. Use `--base-href /your-path/` when hosting below a subdirectory.

Android requires a complete Android SDK, the Flutter-selected NDK, accepted SDK licenses and JDK 17+. Configure `ANDROID_HOME` or `flutter config --android-sdk <path>`. The generated release configuration uses a debug signing identity for local evaluation only; configure your own release signing before distribution. Do not upload keys or `key.properties`.

On macOS with Xcode, CocoaPods/Swift Package Manager and a signing team, run:

```sh
flutter build ios --no-codesign
flutter build ipa
```

iOS compilation and signing cannot be done on this Windows workstation. The configured iOS deployment target is 15.0. Run the app on an iPhone to verify browser callback delivery and Keychain behavior before distributing it.

## Implemented behavior

- Graphic paper/black/lime surfaces, thin header, compact two-column cards, title-tap details, background pictures on mobile, Coupons / Activated / Checkout navigation.
- Pull-to-refresh and header-tap refresh, remembered ONLINESHOP filter and confirmed Activate all.
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

Native images use an independent authorization-free HTTP client, pin the checked public DNS destination for the connection, reject redirects, cap downloads at 2 MiB and source dimensions at 8192 per side / 16 million pixels, decode sampled thumbnails and bound the compressed memory cache to 12 entries. Disabling pictures or changing region/account clears cached/in-flight results. HTML terms are shown as text and never loaded as embedded resources.

## Validation and remaining checks

40 offline tests cover literal URLs/headers, PKCE callbacks, safe errors, no replay after 401/timeouts, refreshed choices, override/deactivation bodies, batch filtering/deduplication/failure/cancellation, loyalty parsing and serial ordering. Account tests verify isolation, migration, concurrent storage writes, callback ownership, identical coupon IDs across profiles and stopping subsequent accounts after mutation failure. Four widget tests exercise narrow screens with 200% text scaling, rotation/navigation, stale-cache mutation gating, selections across filters and separate QR panels. These tests do not contact Lidl. `test/design_test.dart` optionally accepts local `PREVIEW_FONT`, `PREVIEW_BOLD`, `PREVIEW_MONO` and `PREVIEW_ICONS` Dart defines to render readable synthetic previews under `build/previews`; local font files are not redistributed.

The web release build and static analysis pass. Android build was attempted but blocked by the locally missing NDK and unaccepted SDK license. No Flutter APK or IPA is claimed. Live login, image delivery, Keystore/Keychain behavior, checkout acceptance and live batch execution require device/account validation. The Java app's earlier reported successes do not establish those results for Flutter.

`../package.py` regenerates `../dist/coupon-pocket-source.zip`, an optional built web ZIP and SHA256SUMS without private keys, generated build caches, personal configuration or account responses.
