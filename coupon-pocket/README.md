# Coupon Pocket

An independent, minimal Android client for account login, viewing/activating Lidl Plus coupons, and retrieving and displaying your account loyalty card at checkout. Source is written separately from the original app; no Lidl graphics, original classes, bundled SDKs or native libraries are repackaged.

**Status: installable experimental prototype.** The APK compiles and its local tests pass. The user reported successful login and an account-card QR with 0.2.1. The user subsequently reported that coupon retrieval worked with 0.2.2, but activation returned 415. The user reported that activation and pictures worked with 0.2.3. Checkout acceptance remains unverified by the developer. The account service may reject an independently signed app or require different client registration/parameters; coupon requests may require additional context not yet traced. This is not a verified replacement for Lidl Plus.

## 0.2.5 two-column coupons, dates and discount labels

Coupons now appear in a two-column grid with smaller pictures, compact titles and aligned action buttons. An odd final coupon keeps the same tile width. In-place activation updates and retained pictures remain supported when the list structure is unchanged.

“Valid until” parses the server's ISO offset timestamp (or ISO date-only fallback) and formats its calendar date using the selected language, without displaying the time or shifting the date to the phone's timezone. Missing dates are hidden; unreadable dates display “Expiry date unavailable”. Activation validity checks remain unchanged.

The `PromotionDiscountModel` contains `title`, `description` and `hasAsterisk`; its title supplies the percentage or money amount as server-formatted text. Tiles and details display that benefit and description, retaining the conditional asterisk. A missing benefit is omitted; the app does not guess currencies or calculate a percentage from unrelated fields. Full descriptions and coupon rules remain in Details.

## 0.2.4 smoother activation

Opening coupon details or the activation dialog no longer rebuilds the list. Confirming a change updates the affected button to “Updating…” and starts the same server validation/mutation/refresh sequence without an intermediate redraw. Refresh updates existing rows when the visible coupon IDs, order, sections and image URLs match, retaining the actual picture views and scroll position. Structural changes still rebuild the list with its scroll position restored.

Requests no longer dim every control. Button handlers ignore extra taps while busy, and form inputs are temporarily paused. Previously disabled mutation controls retain their state; failed or uncertain mutations still require refresh. The native confirmation dialog remains. This is a visual UI change verified by compilation and existing protocol regressions; a device visual check remains to be confirmed.

## 0.2.3 activation media-type fix and pictures

Basic activation previously sent no body, causing the HTTP client to omit `Content-Type`. Version 0.2.3 sends `{"articleSelection":[]}` with `application/json`, matching the APK's empty selection model. Product-selection requests keep their populated JSON body. DELETE deactivation remains bodyless. Rejected or uncertain mutations are never automatically replayed. The user reported HTTP 415 from the previous request; the corrected activation needs confirmation on the phone.

Coupon lists, details and product choices now display raster images from the returned `image.url` / `images[].url` fields. **Settings → Load coupon pictures** disables image requests. Image GETs are independent of the API client and send no account token, client-authentication header, cookie, referrer or added user/device identifier. Returned HTTPS image URLs may point to external CDNs; those servers can see the request and IP address. Only public network destinations are accepted, redirects are rejected, and decoded images stay in a bounded memory cache. Each download is limited to 2 MiB, with dimension limits and sampling before display. Failures hide the picture and do not block coupon operations. Disabling pictures, changing country, a new account login and logout clear the memory cache and invalidate pending image results. No images are stored on disk.

Install the update over your existing app, refresh coupons, then try activation again.

## 0.2.2 coupon URL fix and screenshots

The previous coupon base URL omitted `/app/api/`. The native factory `fg7` concatenates this prefix to the server host before constructing `tf7`; `tf7.b` uses that base for the `ajn` coupon interface. All coupon reads and mutations now use `https://coupons.lidlplus.com/app/api/`.

On 12 October 2026, an unauthenticated read of `/v4/promotionslist` returned 404; the observed `/app/api/v4/promotionslist` route returned 401, indicating it requires authentication. No account credentials, tokens or mutation requests were used for these checks. Authenticated coupon fetching still needs confirmation on your phone.

Screenshot protection has been removed throughout the app at the user's request. Screenshots and recent-task previews are allowed; encrypted storage and disabled backups remain in place. Install this update over the existing app, retain your login and saved card, and refresh coupons.

## 0.2.1 login fix

The 0.2.0 token exchange omitted the original native client's HTTP Basic authentication. Version 0.2.1 adds the observed header to code exchanges and refreshes, and removes `client_id` from the token form to match the original request. It continues to use PKCE and your own browser login. Known OAuth error codes such as `invalid_client` and `invalid_grant` are now shown with local explanations; server descriptions and raw bodies remain hidden.

Install the updated APK over the old build and start a new login. Previous authorization codes cannot be reused. This fixes a confirmed implementation mismatch that can cause HTTP 400; successful provider login is still unverified until tested on a real device.

## Install and use

The locally development-signed APK is `dist/coupon-pocket-dev.apk` (Android 9 or newer). Transfer it to your phone and open it to install, allowing installation from that source if Android requests it. The app has its own package name, `local.couponpocket`, and does not overwrite Lidl Plus.

1. Open **Settings** and choose your country and language; defaults are CZ / cs-CZ. Store ID is optional and must be a known store identifier, not an address.
2. Select **Log in with Lidl**. Your browser opens Lidl's account page; the app does not collect your password. If Android asks which app should receive the callback, choose Coupon Pocket **for this login**. The original app registers the same callback scheme, so a saved default can route it to the original app; adjust link defaults if needed. Only a callback matching the state of a login initiated in Coupon Pocket is accepted.
3. Refresh coupons. The app also tries to retrieve your account loyalty card if it has not been saved. Each activation/deactivation loads current details and asks for confirmation. Coupons with product groups present one choice per group; existing server choices are preselected. **Details → Change products** changes choices on an activated coupon. After confirmation, the app checks details again, sends the mutation once, then refreshes the list. Saved or uncertain state disables mutations until a successful refresh. If a request times out, its result is unknown—refresh before retrying.
4. In **Checkout card**, the app renders the loyalty ID returned by the authenticated profile service as an offline QR. **Retrieve account card** retries retrieval or refreshes it. It does not derive a card from your tokens or create an account. Cached cards are bound to the account login and country. Changing country clears saved cards to prevent showing the wrong region's card.
5. Card import remains available as a fallback: import a cropped image of your own existing loyalty card, or paste its exact QR text. An import takes display priority; remove it to show your retrieved account card. The system file picker requires no camera/photo-library permission. Image pixels are decoded and re-encoded without original metadata, then encrypted locally.
6. Show the card at checkout. It identifies your existing account; it does not mint coupons, create eligibility, or mark a coupon redeemed. Redemption and validation belong to Lidl's checkout/server systems. The ordinary native loyalty QR format is implemented; eTicket flags, payment basket codes and the current React Native card implementation have not been reproduced or validated. Checkout acceptance needs a real-world scan. Do not import an expiring payment code.

**Preview without logging in** shows clearly labeled example coupons without any network requests. Example activation controls are disabled.

## Privacy boundary

- Only `android.permission.INTERNET` is declared.
- App API HTTPS requests are limited to `accounts.lidl.com`, `coupons.lidlplus.com` and the exact `profile.lidlplus.com/api/v1/{country}/loyalty` path (no profile writes or other profile endpoints).
- No analytics, ads, push notifications, crash-reporting SDKs, background refresh, location, advertising/device IDs or screen-view events. Enabled coupon pictures use separate token-free HTTPS GETs to image URLs returned by coupon APIs; their servers see your IP and request. You can disable pictures in Settings.
- Optional segmentation, user-level and action-attribution headers are omitted. This minimises data but may affect server compatibility or available coupons.
- Account/coupon HTTP redirects are rejected; bearer tokens are never forwarded to redirected hosts. TLS uses Android's normal certificate validation.
- Tokens, pending login data, cached coupons and checkout cards are encrypted with AES-GCM and a non-exportable Android Keystore key in app-private, non-backup storage.
- Android backup is disabled. Screenshots and recent-task previews are allowed on every app screen, as requested.
- Logout deletes tokens, coupons, region settings and all saved cards. It does not delete the Lidl account, revoke remote sessions, or sign the browser out. Completing a new account login clears any previous card and coupon cache to avoid showing another account's card.
- No app logs contain credentials or API bodies. Raw server error bodies and descriptions are not displayed. Recognized OAuth error codes are shown using a fixed allowlist.

**This does not make the Lidl service tracking-free.** Lidl still sees the login, coupon requests, IP address, account identity and checkout activity necessary to provide its service. The external login page, browser and system file providers are separate processes with their own cookies/network behavior, outside this app's allowlist. The app itself adds no tracking SDK or event uploads.

## Login implementation and compatibility

The implementation follows the browser-based authorization-code/PKCE flow described by [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252) and [RFC 7636](https://www.rfc-editor.org/rfc/rfc7636). It uses SHA-256 PKCE, random state/nonce, exact callback validation, duplicate-parameter rejection, a ten-minute pending-login expiry, and consumed state to reject replays. It does not use an identity-token claim to construct a card or infer account identity.

Known production account configuration, taken from the APK: `client_id=LidlPlusNativeClient`, callback `com.lidlplus.app://callback`, authorization path `connect/authorize`, token path `connect/token`, scope `openid profile offline_access lpprofile lpapis`. This is an existing native client's identifier, not a separately registered OAuth client. The original token path (`ko0` → `i81` → `bhj.p`) uses HTTP Basic authentication with the fixed client value shipped in the APK. Version 0.2.1 matches that request instead of assuming this client accepts unauthenticated public-client token exchange. This fixed value is not a user's password and cannot authenticate a user without their browser login/code or refresh token. It is sent only to the account token endpoint. Provider acceptance remains unverified; no provider checks are bypassed.

Coupon operations use base `https://coupons.lidlplus.com/app/api/` with observed relative paths: GET `v4/promotionslist`, GET `v4/promotionsdetails/{id}`, POST/DELETE `v2/promotions/{id}/activation`. Product choices use `{"articleSelection":[{"groupId":"…","articleId":"…"}]}`; changing choices uses PATCH `v4/overrides/discount/{id}`. IDs and group membership are validated against fresh server details. Local checks block redeemed, processing, unavailable, expired, future-dated or unreadable-validity coupons. Server validation remains authoritative, including store and purchase requirements. Details display descriptions, conditions, characteristics, availability messages and applicable products as text, with coupon pictures loaded separately when enabled. Embedded HTML image URLs are not followed. Unknown special workflows may still be rejected. JSON shapes are based on the APK's models, not captured production responses.

Card retrieval uses authenticated GET `https://profile.lidlplus.com/api/v1/{country}/loyalty`. The APK's native repository expects a nonblank string loyalty ID; this implementation accepts a JSON string or plain digits, preserving leading zeroes, and rejects unexpected structures. Its legacy native card builder concatenates `loyaltyId + optional eTicket flag + optional payment basket ID`; with both optional features disabled the payload is exactly the loyalty ID. This is evidence for the implemented ordinary loyalty QR, not proof that every market or current checkout accepts this format. See the [reverse-engineering notes](docs/protocol-evidence.md).

Account service acceptance, actual response schemas, current-market card variants and checkout behavior cannot be established by offline tests. No device attestations, tracking identifiers or provider-check bypasses are added to resolve such incompatibilities.

## Build

Run from this directory:

```bash
./build.sh
./test.sh
```

`build.sh` uses JDK tools and installed Android SDK build tools 36.0.0 / platform android-36. It requires no downloads. Set `ANDROID_SDK_ROOT` if your SDK is elsewhere. A local development key is generated in `.local/development.p12`; retain it for compatible updates and do not use it as a production signing key. Development artifacts are under `build/` and the signed APK is under `dist/`.

The Gradle project can also be opened in Android Studio. It uses Android Gradle Plugin 8.13.1 (Gradle 8.13 and JDK 17 or newer are appropriate). That alternative may download build tooling; there are no runtime Maven dependencies. Gradle's default debug signing key differs from the standalone script's key, so switching signing methods requires uninstalling the old build, which erases local app data.

`test.sh` runs on a JVM with a vendored test-only org.json runtime. OpenCV in Python independently decodes generated QR images. That test jar is not included in the APK.

## Validation completed

- APK compilation, ZIP alignment and Android v3 signature verification.
- 157 checks covering the PKCE RFC vector, state/callback/replay rejection, expired state, host restrictions, header injection prevention, coupon parsing, token refresh/rotation, cache invalidation, loyalty-response validation, region binding, account switches, product selections/overrides, changed groups, validity checks, original token client authentication, safe OAuth errors, rejected-exchange replay protection, exact coupon URLs including the factory prefix, activation JSON media type/body, image fields/URL validation, local image destination rejection, locale/date parsing near midnight, server discount text/asterisks, and logout.
- Fake-server tests ensure mutations are not automatically retried after 401 or an uncertain network result; authenticated reads can retry once after refresh.
- Manifest/source dependency checks confirm the sole declared permission and the two source packages.
- Two independent QR round trips through OpenCV using non-account test payloads.

An Android emulator/device UI run, native Keystore behavior, browser callback routing, actual OAuth acceptance, live response shapes, real coupon mutations, and a checkout scan are still untested. ADB access was unavailable in this sandbox. No login attempts, coupon mutations or telemetry calls were made during development. The two unauthenticated coupon-route checks described above were the only live Lidl requests from this development environment.

## Source map

- `Protocol.java`: OAuth and destination validation rules.
- `OAuthError.java`: recognized error codes and local explanations without raw server data.
- `Api.java`: login exchange, refresh and coupon and loyalty-card operations.
- `CouponDetail.java`: server details, terms, product groups and selection validation.
- `LoyaltyCard.java`: strict server-issued loyalty payload parsing.
- `Transport.java`: the account/coupon/profile HTTP boundary.
- `Images.java`, `ImageUrl.java`: independent token-free image loading, limits and memory cache.
- `Vault.java`: encrypted local files.
- `MainActivity.java`: native UI, product selection, confirmation, account card and card import and region settings.
- `App.java`: a serial work queue shared across activity recreation.
- `QrView.java`: offline QR display.
- `tests/ClientTest.java`, `tests/verify.py`: offline protocol/API/privacy/QR checks.

The QR encoder is [Project Nayuki's MIT-licensed library](https://github.com/nayuki/QR-Code-generator). Its original license headers are retained and a notice is included in the APK assets. `vendor/SOURCES.json` records source URLs and hashes. No third-party QR service is used.
