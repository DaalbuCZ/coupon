# Coupon Pocket implementation notes

## Scope and established product choices

Flutter 0.14.2: show a fullscreen, theme-aware clearing progress screen for the entire refresh/deactivation/reconciliation operation. Block taps/back while it runs, remove it on every completion path, and preserve lifecycle cancellation and no replay.

Flutter 0.14.1 supersedes local-only Clear: Clear shopping list serially deactivates all selected real account copies after fresh checks, stops on failure/cancellation and never replays uncertain DELETEs. Every successful refresh reconciles server activations/deactivations with selection; keep unfinished local product choices and uncertain attempts separate. Use a quick horizontal predictive back transition with cancel/commit and reduced-motion support, without scaling.

Flutter 0.14.0: restore fresh server-active offers into shopping selection on startup without mutations. Refresh on foreground return and checkout entry; remove redeemed, expired or vanished selected account occurrences only after successful reads. Preserve selections on read failure and never replay uncertain mutations. Online offers default hidden while preserving explicit saved preferences. Account covers are square; dynamic offer/product counts use singular labels. Use Material route navigation with Android predictive back, reduced-motion-aware selection outlines and borderless expanded information panels. Online artwork trims a bounded decoded edge pixel.

Flutter 0.13.5: wide artwork extensions use separate median samples of the left and right image edges. Fill the left extension with the left sample and the right inset with the right sample. Use one bounded thumbnail decode; details retain top-edge sampling.

Flutter 0.13.4: group visually identical offers by country, normalized title/benefit and channel. Dates, described limits and descriptions remain account-copy metadata, not display-group identity. Prefer a usable copy for the card preview. QR planning and mutations still use each copy's real eligibility, ID and fresh details; never discard the account-specific rules.

Flutter 0.13.3: plain Lidl++ main title, no in-app logo. Shared offer identity excludes account-specific promotion IDs; match country, normalized title/benefit/discount description, calendar validity and channel. Preserve real per-account IDs for fresh detail checks and mutations. Browse/checkout show each shared offer once. Exact set cover minimizes QR/account count before preferring active copies; no automatic replay of uncertain requests.

Flutter 0.13.2: show the bundled circular L++ logo beside the main Lidl++ header title. Keep search replacing the whole title area; decode the static thumbnail at a bounded size and avoid redundant logo semantics.

Flutter 0.13.1: displayed app name is Lidl++, retaining the existing package IDs and signing identity. Wide-card star/info controls are vertically centered with 70% opaque white surfaces; square images are inset 18 logical pixels from the right. Horizontal background extensions sample the artwork's left edge. Launcher preserves the signature yellow Lidl circle with red rim and simple L++ lettering, over a separate blue adaptive background; no hexagon or extra outer outline.

Flutter 0.13.0: Settings → Appearance contains layout and theme. Preserve the frozen 3D stack as the default; optional Wide cards use ordinary lazy scrolling, square artwork aligned right with sampled background extension, and the same selection/favourite/details flow. Persist layout and theme together through serialized local writes. Switching layout must retain shopping selections and search.

Flutter 0.12.3: all exposed carousel cards accept direct selection, favourite and details taps. No off-centre IgnorePointer or tap-to-focus wrapper. Preserve transformed hit testing, frontmost-card paint/hit order, native scroll drag arbitration and bounded card reuse.

Flutter 0.12.2: single lime selection outline, no white under-border. Lower detail artwork by the system inset plus 32 logical pixels; extend its sampled top-edge colour to the screen top. Sample once through a bounded thumbnail, dispose decode resources, preserve token-free picture loading and parallax.

Flutter 0.12.1: white favourite button surface matching info, yellow saved-star icon, no favourite card glow/shadows. Offer-detail image parallax at one quarter of content movement, disabled for reduced motion and cached behind a repaint boundary. Account covers remain unchanged.

Flutter 0.12.0: centered rear cards, no browse mutation text or plus button, bright green selection outline. Full-bleed covers with floating back arrow; collapse title onto back-button row and flatten sheet corners. Reconcile selection aliases for the same account/campaign and deduplicate checkout; preserve confirmed responses across a lagging immediate list read. Mark uncertain attempts only immediately before actual send, never all planned targets. Inactive checkout rows read fresh state and require explicit retry confirmation; never automatically replay failed mutations.

Flutter 0.11.0: floating error/notice snackbars, no inline banners. Soft carousel top gradient; gently smaller rear cards; bounded reuse of nearby card widgets. Shared cover/sheet scrolling for offer and account details with pinned titles, one account name and adjacent rename pen. No account loading skeleton or reserved QR placeholder. Rounded product search. Top-level persistent Dark mode switch with theme-aware surfaces/text and white QR backgrounds. Keep release smoothness and live QR claims bounded by phone feedback.

Flutter 0.10.0: card/body taps toggle shopping selection and activate/deactivate through the serial queue; deactivation rechecks fresh details and never replays failed DELETEs. Details is an info button below the star and has no generic activation controls; explicit product choices retain a Save product choices action. Continue is always present, disabled when empty. Strong green/white selected outline; bright yellow favourite star and a cached gold shadow. No browse category text. Bigger cards and more lower spacing; capped, damped fling without carried momentum. Bundle open-licensed Google Sans Flex with ROND 100, no runtime font downloads. Account QR loading/error panels stay compact (successful QR retains a bounded square).


Flutter 0.9.2: omit the browse Coupons label (retain Favourites category), reduce lower-card tilt to 1.08 radians and gently tilt upper cards to -0.22 radians. Checkout ends with a distinct red Clear shopping list action; this only clears the local shopping selection. Filters use consistent section spacing and rounded panels: account radio choices, online-offer switch, then an outlined reset button.


Flutter 0.9.1: continuous Rolodex scrolling with native fling friction, no item counter and no snapping. Paint cards in fixed ascending order so lower cards always overlay those above. Near the bottom, lower cards pivot down from their top edge and move their hinge below the flat card, revealing it fully. Map scroll pixels directly to card translation; cache nearby artwork behind repaint boundaries and animate paint transforms rather than per-frame layout/order changes.


Flutter 0.9.0: lazy vertical Wallet-style overlapping square-card stack; remove routine Active text from browse cards. Large Continue button. Single-account checkout shows that account's QR above compact selected items; multiple accounts keep separate QR buttons. Offer details is a back-arrow page: visible discount/limits, searchable progressive product list, then expandable About and Conditions. Group account management into Card, Preferences and Connection. On Android, loyalty GETs use bounded, redirect-rejecting HttpsURLConnection via a narrow method channel to match the Java client; coupon mutations remain on the existing serial transport. Preserve server-issued IDs and account/country binding.


Flutter 0.8.1: square browse images with name/offer over a lightweight dark lower gradient, star at the top and plus/check beside the offer. No select-all-matching feature. Preserve lazy rendering, release builds and context-specific compact checkout/settings rows.

Flutter 0.8.0 supersedes earlier Flutter layout choices: lazy one-column cards with a large image, star over the image, title/offer below and a plus beside them; inline live search; account/online filters in Settings; a contrasting checkout button; account-only checkout summaries with counts and expandable compact coupon rows. Favourite settings uses compact image/name/removal rows while retaining full snapshots. Build optimized release APKs for phone use with the existing local signing identity. Do not recompute checkoutPlan per browse card or start unlimited duplicate image requests. Profile GET may try the exact `/profile/api/v1/{country}/loyalty` alternate on the same host only after the original route returns 404; do not infer card IDs from JWT claims. Android cropped QR image import uses the system picker, bounded metadata-free re-encoding and existing encrypted account/country storage.

Flutter 0.7.1: preserve list identity/scroll/images during operations; show activation progress only on affected coupons and accept additional selections during a serial batch. Settings has separate Accounts and Favourites screens, with coloured account cards and matching checkout groups. Use rounded white navigation/action cards consistently, and omit routine sync/language/status clutter. Match the working Java service transport's JSON Accept header and fixed UTF-8 body length. Keep real card-fetch errors visible without exposing provider bodies.

The Flutter app in `coupon-pocket/flutter/` is now the actively tested multi-account app. The user's 0.7.0 flow supersedes the earlier layout choices below for Flutter: one column of aggregated image-led coupon cards; sale-size sorting; favourites first; top-right Settings for account/favourite management; search-menu account/online filters and selection of all results. Selection automatically activates coupons using the exact minimum-account cover of fresh usable copies, preferring active copies on ties. A bottom Checkout action opens a separate account-grouped screen with a back arrow; show only one labelled account QR at a time. Save favourite coupon fields/details and a bounded image preview in encrypted native storage. Preserve serial, server-confirmed mutations and no replay of uncertain results. The Java app remains a separate 0.3.0 artifact.

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
