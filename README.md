# Coupon Pocket

A minimal Android client for Lidl Plus coupons and loyalty cards, without added analytics or ads.

Sign in with your existing Lidl account, activate coupons, and show your loyalty card at checkout. The app uses a compact two-column layout with product pictures in the card backgrounds, readable expiry dates, and the discount text provided by Lidl.

## Features

- Browser login with authorization-code flow and PKCE; passwords are entered in the browser.
- **Coupons**, **Activated**, and **Checkout** bottom navigation, with settings inside Checkout.
- Pull-to-refresh and in-place coupon updates that preserve pictures and scrolling where possible.
- Coupon activation/deactivation, product choices, and changing choices on activated coupons.
- A floating **ONLINESHOP** filter and **Activate all** for the visible, eligible coupons.
- Account loyalty-card retrieval, offline QR display, and optional card-image/QR-text import.
- Encrypted local tokens, coupons and cards; no Android backups. Screenshots are allowed.
- Optional coupon pictures downloaded without account authorization, stored only in memory.

**Activate all** asks for confirmation, respects the online-shop filter, and skips unavailable coupons or coupons requiring product choices. It checks the current server state, sends mutations once, and stops if a request fails or its outcome is uncertain. You can stop the remaining requests.

## Install

Download the [current Android APK](coupon-pocket/dist/coupon-pocket-dev.apk?raw=true) and install it on Android 9 or newer. Version **0.3.0** uses package `local.couponpocket`, so it installs separately from Lidl Plus.

1. Open **Checkout → Settings** to select your country and language; defaults are **CZ / cs-CZ**. Store ID is optional.
2. Select **Log in with Lidl**. When Android asks which app should receive the browser callback, choose Coupon Pocket for this login.
3. Pull down on the coupon list to refresh. Tap a coupon title for details or use **Activate**. **Activated** shows active coupons.
4. Use **Checkout** to display your account card. Card import remains available as a fallback.

The original Lidl Plus app uses the same login callback scheme. A saved Android app-link default may route the callback there instead; adjust the default if necessary.

The checked-in APK uses a local development signing key. Updates built with another key require uninstalling the old app first, which clears local data. The private signing key is **not** in this repository.

## Privacy

There are no added analytics, ads, crash-reporting SDKs, push notifications, background refresh jobs, location permissions, advertising IDs or screen-view event uploads. The only declared permission is `INTERNET`.

Account, coupon and loyalty-card requests still reach Lidl's servers, which can see your account activity and IP address. The browser login has its own cookies and privacy behavior. Enabled pictures reach the image servers specified in coupon responses, without sending your account token or added user/device identifiers; you can disable pictures in Settings.

Tokens and saved account data use AES-GCM with an Android Keystore key in private non-backup storage. Logout erases local data, but does not delete your Lidl account or sign the browser out.

## Build and check

The standalone build needs a JDK with `javac`, `jar` and `keytool`, Android SDK platform **36**, and build tools **36.0.0**. The app targets Android 35 and supports Android 28+.

```bash
cd coupon-pocket
./test.sh
./build.sh
```

Set `ANDROID_SDK_ROOT` if the SDK is not at `/opt/android-sdk`. The test runner uses a vendored test-only JSON library and Python OpenCV (`cv2`) for independent QR decoding. The standalone build downloads nothing and has no runtime Maven dependencies.

You can also open `coupon-pocket/` in Android Studio. That path uses Android Gradle Plugin 8.13.1 and may download tooling; Gradle's debug signing key differs from the standalone build's local key.

The current suite passes **176 offline checks**, including OAuth state/PKCE, exact API URLs, activation bodies, token refresh, coupon choices, image URL restrictions, online-shop filtering, and bulk cancellation/failure behavior. APK alignment and Android signature verification pass.

## Compatibility

This is an independent experimental client, not an official Lidl application. Users have reported working login, coupon retrieval, pictures, individual activation, and account-card QR generation. Version 0.3.0's new native layout, pull gesture and bulk flow still need device/live-account validation; checkout scanner acceptance is unverified. No automated live account mutations are part of the test suite.

The implementation follows observed native endpoints and models. Account-server policies or response formats may change. eTicket flags, payment QR variants and the React Native card path are not implemented. Coupons are validated and redeemed by Lidl's servers and checkout systems.

## Project layout

| Path | Purpose |
|---|---|
| [`coupon-pocket/`](coupon-pocket/) | Native Java Android app, build scripts, offline tests and packaged APK |
| [`coupon-pocket/README.md`](coupon-pocket/README.md) | Detailed behavior, privacy boundary, compatibility and change history |
| [`coupon-pocket/docs/protocol-evidence.md`](coupon-pocket/docs/protocol-evidence.md) | Endpoint/model findings behind the independent implementation |
| [`analysis/`](analysis/) | Investigation notes and scripts; the original APK and extracted code are excluded |
| [`AGENTS.md`](AGENTS.md) | Implementation context and verified constraints for future work |

The app does not repackage original Lidl classes, SDKs or graphics. The offline QR encoder is [Project Nayuki's MIT-licensed QR Code generator](https://github.com/nayuki/QR-Code-generator); its notices and source provenance are included in the project. The vendored JSON jar is used only by tests and is not included in the APK.
