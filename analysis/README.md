# Lidl Plus server communication walkthrough

Analyzed artifact: `Lidl.Plus.ver.17.11.6.build.1470410092.apk`, Android package `com.lidl.eci.lidlplus`, version 17.11.6, build 1470410092.

This initial walkthrough is static inspection of the APK. Subsequent client fixes and public route checks are documented in `missing-features.md`. The app was not launched, no account was used, and no requests were sent to Lidl. Runtime configuration, actual responses, and server-side behavior remain unverified. Many compiled class names were shortened by R8; the `.smali` files are disassembled instructions, not the original Kotlin source.

## How a request works

A useful model is: screen action → application data layer → API interface → HTTP client and request interceptors → HTTPS server → response parsing → screen update. This is an architectural explanation, not a complete UI-to-server call trace.

The native networking code includes Retrofit-style annotated API interfaces and OkHttp-style request interceptors. React Native and a compiled Hermes JavaScript bundle are also present. Their presence does not establish that every feature uses the same networking stack.

## Separate services

Bundled production-style base addresses include:

| Feature | Address |
|---|---|
| Coupons | https://coupons.lidlplus.com/app/api/ |
| Home screen | https://home.lidlplus.com/api/ |
| Home configuration | https://home.lidlplus.com/configuration/ |
| Offers | https://offers.lidlplus.com/app/api/ |
| Receipts | https://tickets.lidlplus.com/api/ |
| Accounts | https://accounts.lidl.com/ |

Staging and UAT alternatives are present too. A bundled address is evidence of supported configuration, not proof that this device or market will contact it. The coupon host is selected in `j2g.smali`, method `f0`; the full base appends `app/api/` in `coupon-factory.smali` (`fg7`) before creating the coupon Retrofit client.

## Concrete coupon request definitions

`coupon-api.smali` defines:

- GET `v4/promotionslist`: retrieve a coupon list.
- GET `v4/promotionslist/anonymous`: anonymous variant.
- GET `v4/promotionsdetails/{id}`: retrieve one promotion's details.
- POST `v2/promotions/{id}/activation`: activate a promotion, with an optional ArticleSelection body and additional context.
- DELETE `v2/promotions/{id}/activation`: remove the activation.

These verbs were verified against the annotation-to-HTTP-method dispatcher in `uje.smali`; the annotation names themselves are obfuscated.

The list definition has headers named `Accept-Language`, `Country`, `Segment-Ids`, `Store-Id`, `UserLevel`, `World`, and `Tags`. These provide locale, store, and selection/segmentation context; the precise meaning of user levels and segment IDs requires further tracing. Nullable parameters can be omitted. Authentication is also added by interceptor code.

Illustrative request, with invented placeholder values:

```http
GET /app/api/v4/promotionslist HTTP/1.1
Host: coupons.lidlplus.com
Country: CZ
Accept-Language: cs-CZ
Authorization: Bearer <access-token>
Store-Id: <selected-store-id>
```

This is an explanation of the request shape, not a traffic capture. `coupon-list-model.smali` shows a JSON-mapped `sections` property in PromotionListModel; a model turns response fields into typed objects the app can use.

## Login and tokens

The account code constructs `connect/authorize` and `connect/token` URLs (`ft.smali`). The request builder (`ko0.smali`) uses client ID `LidlPlusNativeClient`, scopes `openid profile offline_access lpprofile lpapis`, and a PKCE challenge using SHA-256/S256, with a fallback branch for unavailable SHA-256.

The manifest registers AppAuth's redirect receiver for `com.lidlplus.app://callback`. Taken together, this supports an authorization-code/PKCE login flow: the account service handles login, redirects into the app, and the app exchanges the code and verifier for tokens. PKCE ties the exchange to the app instance that started login. Refresh-token handling is present in the bundled authentication code; exact application refresh/retry policy was not traced.

Interceptor code in `p71.smali` and `cov.smali` builds `Authorization: Bearer ...` and forwards the constructed request. An access token is the credential presented to the API; the client ID identifies the application and is not a user's credential.

## Other requests and security

`home-api.smali` defines POST requests to `v2/{country}/home/logged` and `v2/{country}/home/anonymous`, with a HomeBodyRequest. `request-examples.json` also includes the receipt interface and its GET `v3/{country}/tickets` and GET `v3/{country}/tickets/{id}` definitions.

Telemetry is separately configured: the APK contains an OpenTelemetry exporter endpoint at `https://mobile-otel.lidlplus.com:4417/v1/traces`. This supports diagnostic traffic, but does not reveal what is actually transmitted in a running session.

`network-security.txt` decodes the manifest-referenced Android network security configuration. It trusts system certificates and declares two SHA-256 public-key pins for `storetools.lidlplus.com`, including subdomains, with TrustKit pin enforcement. This does not prove pinning is enabled for every other host; additional code-level configuration would need to be traced.

## Evidence files

- `coupon-api.smali`: coupon endpoints and parameter annotations.
- `home-api.smali`: logged-in and anonymous home requests.
- `coupon-list-model.smali`: response model and JSON field mapping.
- `ft.smali`, `ko0.smali`: account endpoint construction and authorization builder.
- `p71.smali`, `cov.smali`: shared request/interceptor code.
- `network-security.txt`, `AndroidManifest.xml`: decoded security configuration and callback registration.
- `http-methods.json`: 350 extracted GET/POST/DELETE/PATCH/PUT method definitions across the APK, including third-party integrations. This is not a count of Lidl services or unique live endpoints.
- `inspect_dex.py`: local extraction script for the API annotations.

The included Hermes bytecode could not be disassembled by the locally available compiler because its supported bytecode version differs. Findings above come from native DEX code and Android resources, not a full JavaScript reconstruction.
