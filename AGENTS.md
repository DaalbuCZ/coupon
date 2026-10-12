# Coupon Pocket implementation notes

## Scope and established product choices

This repository contains an independently written Android client for an existing Lidl Plus account. The app lives in `coupon-pocket/`; the repository root is not the Gradle project. Keep the implementation minimal and preserve the user's explicit choices:

- Neutral grey/white surfaces, a thin **Coupon Pocket** header, compact two-column coupon cards.
- Product pictures fade into the upper-right card background; no dedicated tall picture row.
- Bottom navigation: **Coupons**, **Activated**, **Checkout**. Settings belong inside Checkout.
- Pull-to-refresh on coupon tabs. The header tap is an accessibility alternative.
- Floating ONLINESHOP filter, with **Activate all** above it on the Coupons tab.
- Tap coupon titles for details; update unchanged rows in place to avoid activation flashes.
- Screenshots are allowed throughout the app. Do not restore `FLAG_SECURE` unless requested.
- Keep privacy explanations and implementation notes in documentation, rather than permanent UI banners.
- Design previews were separate conversation artifacts. When the user requests implementation, change/build the Android app rather than only revising a preview.

## Build, tests and artifact handling

From the repository root:

```bash
./coupon-pocket/test.sh
./coupon-pocket/build.sh
```

The standalone build needs JDK tools, SDK platform android-36 and build-tools 36.0.0. Set `ANDROID_SDK_ROOT` for another SDK location. Minimum API is 28, target API is 35. Source is Java 8-compatible and uses the Android framework, with no runtime Maven libraries except vendored QR source. Tests need the included JSON jar and Python OpenCV.

`build.sh` compiles, aligns, signs and verifies `coupon-pocket/dist/coupon-pocket-dev.apk`. Signing key: `coupon-pocket/.local/development.p12`, deliberately ignored. Preserve that existing local key for compatible updates; never commit or upload it. A clone creates a different local key. Keep versionCode/versionName synchronized in `app/build.gradle` and `AndroidManifest.xml`, and update HTTP user agents when bumping the app version.

After source/docs changes, regenerate the source archive and SHA256SUMS when delivering updated packaged artifacts. The source archive should contain only `coupon-pocket/` source/docs/test dependencies; exclude `.local`, `build`, `dist`, `.gradle`, personal configuration and signing keys. Test JSON jars must not enter the APK.

The repository excludes `.aws`, `.codex`, `.agents`, the supplied original APK, extracted DEX/JavaScript strings and smali. Do not add them with `git add -f`. `analysis/*.md` and `analysis/*.py` are retained as notes/tools. Avoid committing captured account responses, cookies, codes, tokens, loyalty IDs or user screenshots.

Run checks appropriate to the change; current baseline is 176 offline checks plus manifest checks and two independent QR round trips. Reversible UI tweaks do not need tests that merely restate the UI implementation. Protocol or mutation behavior changes need meaningful fake-server regression checks. Offline tests and successful compilation are not device/UI or live-account verification.

## Protocol facts: do not lose these corrections

See `coupon-pocket/docs/protocol-evidence.md` and the source for details.

### Browser login

- Account base: `https://accounts.lidl.com/`.
- Authorize: `connect/authorize`; token: `connect/token`.
- Client ID: `LidlPlusNativeClient`.
- Callback: `com.lidlplus.app://callback` (also registered by the original app).
- Scope: `openid profile offline_access lpprofile lpapis`.
- Use authorization code + SHA-256 PKCE, random state/nonce, exact callback shape, duplicate-parameter rejection, a ten-minute pending-login limit and consumed state.
- **HTTP 400 fix:** code exchange AND refresh use the original native client's HTTP Basic client authentication. `Protocol.tokenHeaders()` matches the APK's shared client value. It is a fixed value shipped in the original app, not a user password. Never send this header to coupon, profile or image URLs. The token form omits client_id; authentication is in the header.
- OAuth errors expose only recognized error codes with local explanations. Never display/log raw provider response bodies or descriptions. Identity tokens are not used to invent a card.

### Coupons

- **Full API base:** `https://coupons.lidlplus.com/app/api/`.
- **HTTP 404 fix:** the native factory appends `app/api/` to the host. Do not regress to the host root. Tests assert complete literal URLs independently of the base constant.
- GET `v4/promotionslist`; GET `v4/promotionsdetails/{id}`.
- POST / DELETE `v2/promotions/{id}/activation`.
- PATCH `v4/overrides/discount/{id}` changes product selections on an activated coupon.
- **HTTP 415 fix:** basic POST activation sends `{"articleSelection":[]}` with `application/json`. No JSON body meant Transport omitted Content-Type. DELETE remains bodyless.
- Product choices: `{"articleSelection":[{"groupId":"…","articleId":"…"}]}`. Require exactly one valid server-returned article per group. Re-read details after confirmation and validate membership/state against that response. Never pick arbitrary defaults.
- API requests use the account Bearer token, Country and Accept-Language. Store-Id is sent only on the observed list route. Optional Segment-Ids, UserLevel and Action-Location are omitted.
- List schema is `sections[] → promotions[]`. Server models provide title, activation/processing status, validity, availability, groups and explicit image fields.
- Discount text comes from `discount.title`, `discount.description`, `discount.hasAsterisk`. Preserve the supplied currency/percentage text and conditions; do not infer amounts from unrelated fields.
- Display `validity.end` as a locale-formatted calendar date without shifting it to the phone's timezone. Eligibility checks still use actual offset timestamps.

### Loyalty card

- Authenticated GET `https://profile.lidlplus.com/api/v1/{country}/loyalty`.
- The native repository expects a string, not a whole profile object. Accept JSON string or plain digits while retaining leading zeroes; reject unobserved response objects.
- Ordinary legacy native QR: loyaltyId + optional eTicket flag + optional payment basket suffix. With optional features disabled, this app encodes the server-issued loyaltyId verbatim.
- Bind saved cards to the account login and country. Clear cards/cache on a new login; clear cards on country changes. Explicit imports take display priority.
- eTicket/payment variants, the current React Native/Axion card path and checkout acceptance remain unverified. Do not invent a QR payload from account claims.

## Mutation and batch invariants

- All account/coupon work uses `App.worker`, a shared serial queue; preserve ordering across activity recreation and logout.
- Successful GETs can retry once after a token refresh. **Never automatically replay POST/PATCH/DELETE** after HTTP 401, timeout or another uncertain failure.
- Invalidate persisted coupon cache BEFORE mutations. Cached/stale views cannot mutate until refreshed. A successful server response, not an optimistic UI toggle, confirms an activation.
- BulkActivator uses the confirmed set of visible, inactive/nonprocessing coupon IDs, then refreshes the list and rechecks each coupon's details before its mutation.
- Bulk activation respects the saved ONLINESHOP filter. Explicit store channel wins over a section label; mixed store+online channels remain visible. A null/missing channel can fall back to the literal ONLINESHOP section. Do not infer the filter from coupon-title wording.
- Skip already active, unavailable, future, expired, redeemed, processing and product-choice coupons. Never guess group choices.
- Execute mutations serially, deduplicate IDs, stop after the first failure/uncertain result, and do not replay failed mutations. Cancellation stops remaining mutations after an in-flight request; leaving the activity also requests cancellation.
- Completion can refresh the list with a read and reports confirmed activations/skips. A timed-out mutation might have succeeded remotely; do not count it as confirmed or blindly retry it.

## Privacy and network boundaries

Only INTERNET permission is declared. No analytics/ad/crash/push SDKs, device/advertising IDs, location, background refresh jobs or telemetry uploads. These are explicit product requirements.

`Transport` handles account/coupon/profile HTTPS only, uses normal Android TLS, rejects redirects and never forwards tokens to redirected hosts. `Images` is separate: GET only, no account/client authorization, added identifiers, cookies or referrer; returned image URLs must be HTTPS and resolve to public destinations. Reject redirects, cap downloads/dimensions, sample before decoding, and use the bounded memory cache. Disabling pictures, switching region/account or logout invalidate image results and clear cache. Do not load embedded HTML URLs or use a QR web service.

`Vault` uses AES-GCM, filename AAD and a non-exportable Android Keystore key in app-private non-backup storage. Backup remains disabled. Logout is local erasure; it does not revoke Lidl/browser sessions. Never log auth values, API bodies or account identifiers.

## Source map and outstanding work

- `MainActivity`: native layout, navigation, in-place row binding, background image cards, filters, confirmations, region settings and bulk UI.
- `RefreshScroll`: pull gesture interception only at scroll top; test scrolling, tap cancellation and accessibility on a device.
- `Api`, `Protocol`, `OAuthError`: HTTP operations, OAuth rules and safe diagnostics.
- `Coupon`, `CouponDetail`: list parsing, channel filter, display dates/benefits, terms and choice validation.
- `BulkActivator`: serial batch with fresh eligibility, cancellation and stop-on-failure behavior.
- `Images`, `ImageUrl`: token-free image pipeline and public-destination validation.
- `Vault`, `App`, `LoyaltyCard`, `QrView`: encrypted state, serial work, card parsing and offline QR.
- `tests/ClientTest.java`: fake HTTP client and memory storage, no live account/network mutations.

User reports established working browser login, coupon retrieval, pictures, individual activation and account-card QR generation in earlier builds. Version 0.3.0's new native UI, pull-to-refresh and bulk flow still need phone validation. Development has not verified a checkout scan, Keystore behavior on a device, current-market QR suffixes or live batch execution. No emulator was available in the development SDK. Prior public probes only established 404 at the incorrect coupon root path versus 401 at the correct prefixed path without a token.

Known items worth investigating next: native layout/gesture behavior with larger fonts and rotation; batch stop/results across recreation; correct ONLINESHOP metadata for additional countries; current card format/eTicket feature requirements. Preserve working protocol behavior while investigating. Keep compatibility claims bounded by actual evidence.
