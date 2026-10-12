# Additional protocol evidence and implementation (Coupon Pocket 0.2)

These findings come from the supplied Lidl Plus 17.11.6 / 1470410092 APK. They establish paths and native behavior in that APK; they are not captured production responses or live compatibility results. The independent client implements these observations without bundling original classes or SDKs.

## Loyalty card

- `k63`, factory case 12: production base URL `https://profile.lidlplus.com/api/`, constructing `len`.
- `len.a`: constructs `ovj` using interface `udn`.
- `udn.d`: GET `v1/{country}/loyalty`, response type `i1p<String>`. `analysis/udn.smali` provides the original DEX evidence.
- `ovj.c`: reads the response string, rejects a blank loyalty ID with `Empty loyaltyId`.
- `dqc.a`: retrieves this value for an authenticated user and caches it as `jkh` / `LoyaltyIdDTO`. DTO aliases `loyaltyId` / `mLoyaltyId` are **local-storage fields**, not evidence for an HTTP object response.
- `smc.f`: receives a payment basket ID, loads the loyalty ID from `dif.D()` / `xqg.b`, and passes it into card state.
- `smc.a(boolean eTicketEnabled, boolean eTicketActive)`: returns loyalty ID, then `1`/`0` only if the eTicket module is enabled, then the basket suffix. `r2i.j` is plain string concatenation.
- `DigitalCardActivity`: reads optional Intent field `baskedId` (spelled this way in the original) and defaults it to the empty string.

Implementation: fetch the authenticated server-issued loyalty ID; encrypt it with the country in private storage; encode the ID verbatim for an ordinary loyalty QR with eTicket and basket suffixes disabled. Do not infer a QR from OAuth claims. Reject unobserved response objects. Keep explicit card import as a fallback. Clear cached cards on new login and country change.

Limit: this is a legacy native card path. The APK also has a React Native / Axion customer-card path. The current checkout's required format and market-specific receipt flags still need live validation. No claim of verified checkout acceptance is made.

### Flutter 0.8.0 routing investigation

The user reports authenticated HTTP 404 from the original loyalty route. The alternate exact GET path `https://profile.lidlplus.com/profile/api/v1/{country}/loyalty` is present in [Andre0512's client source](https://github.com/Andre0512/lidl-plus/blob/master/lidlplus/api.py). Flutter tries it only after 404 from the original path, without broadening the host or inventing response formats. This source establishes a known route, not present-day availability; workstation unauthenticated probes could not connect. Both routes returning 404 leads to an existing-card import offer. Native Android image imports display a re-encoded cropped image, not a fabricated QR payload. No OAuth subject or other claim is used as a card ID.

## Coupon product groups

Observed models in `es.lidlplus.features.coupons.data.api.coupons.model`:

- `PromotionDetailModel`: `id`, `isActivated`, `isProcessing`, `isRedeemed`, `validity`, `availability`, `groups`, `conditions`, `characteristics`, `articles`.
- `PromotionGroupModel`: `id`, `title`, `articles`.
- `PromotionGroupArticle`: `id`, `title`, `selected`, optional image.
- `PromotionArticleSelected`: `groupId`, `articleId`.
- `ArticleSelection`: `articleSelection`, a list of `PromotionArticleSelected`.
- `PromotionValidityModel`: `start`, `end` offset date-times.
- `PromotionAvailabilityModel`: `apologizeStatus`, `title`, `text`.

`x17.a` collects selected articles and requires the selection count to match the group count. `p57.invokeSuspend` and `n8i.w0` convert a map of group ID to article ID to selections. This supports one choice per group.

`ajn.d` declares POST `v2/promotions/{id}/activation` with `ArticleSelection`; `ajn.f` declares PATCH `v4/overrides/discount/{id}` with the same body. DELETE activation remains `ajn.c`. These annotations are also in `analysis/coupon-api.smali` and `analysis/http-methods.json`. `n8i.v0` constructs the actual serialized selection body. `ams.A` / `c0b.J` use the override route to change choices.

Implementation: show server choices in radio groups, preselect only an unambiguous server selection, require every group, validate IDs and membership, re-fetch details after confirmation, POST activation or PATCH existing choices exactly once, invalidate persisted coupon cache before a mutation. Never automatically replay mutations after timeout/401. Render coupon rules as text and omit remote images and original telemetry events.

## Validation boundary

Fake-server tests cover paths, authorization, payloads, membership, changed groups, unsupported schemas, state guards, cache invalidation, account-switch clearing, malformed loyalty responses and no automatic mutation replay. QR output is independently decoded using test identifiers. APK compilation/signature verification is local. Device UI, Android Keystore, provider login acceptance, live mutations and checkout scans remain unverified.

## Token authentication correction (0.2.1)

The initial implementation incorrectly assumed a public-client token exchange. Following the complete native token path establishes HTTP Basic client authentication:

- `ko0.f` is `new bhj((byte) 24)`; `ko0.e` passes it to `k81.b` for authorization-code exchange. `ko0.b` uses the same authenticator for refresh.
- `i81.doInBackground` sets token HTTP request headers from `bhj.p(request.clientId)`.
- `bhj.p` returns an Authorization Basic header constructed from the URL-encoded client ID and the fixed string `secret`. This is the original APK's shared client value, not a personal account password.
- `u9v.a` includes grant type, redirect URI, code, code verifier, refresh token and optional scope; it omits client ID because authentication is in the header.

Version 0.2.1 follows this format for code exchange and refresh only. Coupon/profile requests continue to use the user's Bearer token. State, PKCE, callback expiry and one-use exchanges are unchanged. Standard recognized OAuth error codes are shown; arbitrary response fields are never displayed or logged. Offline tests verify this format, but no live token request was made during the fix.

## Coupon base URL correction (0.2.2)

The initial inspection identified the server host and relative Retrofit methods but missed the full factory base path. `fg7.invoke` calls `j2g.f0(environment)`, then concatenates `app/api/`, passing this as constructor parameter 15 to `tf7`. `tf7` stores that parameter in field `n`; `tf7.b` constructs the Retrofit base from `n` and creates `ajn`. Therefore the list URL is `https://coupons.lidlplus.com/app/api/v4/promotionslist`, and the same `/app/api/` prefix applies to details, activation, deactivation and selection overrides. The nearby separate `app/api/tracking/` base is not used by Coupon Pocket.

The original instructions are preserved in `analysis/coupon-factory.smali` and `analysis/coupon-client-factory.smali` outside the independent app's source/archive. On 12 October 2026, two read-only unauthenticated probes with Country CZ and Accept-Language cs-CZ returned HTTP 404 for `/v4/promotionslist` and HTTP 401 for `/app/api/v4/promotionslist`. No authorization header was sent. This verifies a routing difference without proving the authenticated response schema or coupon eligibility. Offline tests now assert complete literal URLs, independently of the base constant, for list, details and mutations.

Version 0.2.2 also removes FLAG_SECURE entirely per the user's explicit request. Screenshots are allowed throughout the app.

## Activation body and image fields (0.2.3)

`wd.b` converts the selection list with `n8i.v0` before activation. `n8i.v0` always constructs an `ArticleSelection` from a newly created article list; an empty input becomes `{"articleSelection":[]}` rather than no body. `c0b.c` passes this body to `ajn.d`. The independent client incorrectly omitted the body for basic activations, causing its transport also to omit Content-Type. Version 0.2.3 sends the observed empty JSON selection and application/json. Product selection/override requests retain their populated JSON. The user's reported HTTP 415 provides live evidence of the old request rejection, not yet of corrected activation acceptance.

`PromotionModel` uses a single `image`; `PromotionDetailModel` has an `images` list; group articles have `image`. `PromotionImageModel` fields are `url` and `altText`. Images are now read from these explicit fields, with no HTML/WebView image loading. Downloads use a separate token-free client with HTTPS/public-destination checks, no redirects, bounded image decoding and memory cache, and no added identifiers or telemetry. The user can disable image loading. The image model DEX evidence is preserved in `analysis/coupon-image-model.smali`.

## Discount labels (0.2.5)

`PromotionDiscountModel` supplies the JSON string fields `title`, `description`, `scope`, `purchaseType`, `posType`, plus boolean `hasAsterisk`. Display uses the supplied `title` and `description` rather than inferring numeric amount/type or currency. Conditional asterisks are retained. The DEX model is preserved in `analysis/coupon-discount-model.smali`. Coupon dates use `validity.end` (offset date-time) or the legacy end-validity field, formatted as a calendar date using the selected language. Formatting does not alter eligibility validation.

## Flutter 0.9.0 card transport investigation

Reinspection of the user-supplied 17.11.6 APK confirms `udn.d` GET `v1/{country}/loyalty` returning a string and `k63`'s production base `https://profile.lidlplus.com/api/`. Its React Native bundle exposes a loyalty-ID accessor; a different current card endpoint has not been established by this static inspection. No new endpoint or JWT card payload is inferred.

The user reports that both the official app and Java Coupon Pocket display a working card for the same account. Flutter and Java construct the same original URL and explicit request fields. Flutter 0.9.0 changes Android card reads from Dart HttpClient to the Java app's HttpsURLConnection implementation, keeping normal platform TLS, no redirects, bounded responses and the exact allowlist. This targets the remaining transport difference; it does not prove the root cause of the reported 404. Offline checks verify bridge request fields and rejection of mutations; live card retrieval still requires phone confirmation.
