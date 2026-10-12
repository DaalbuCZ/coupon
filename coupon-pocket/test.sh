#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p build/tests
src=app/src/main/java/local/couponpocket
javac --release 8 -Xlint:-options -cp tests/json-test-runtime.jar -d build/tests \
  "$src/Protocol.java" "$src/OAuthError.java" "$src/Storage.java" "$src/Transport.java" "$src/RequestClient.java" "$src/Coupon.java" "$src/ImageUrl.java" "$src/CouponDetail.java" "$src/LoyaltyCard.java" "$src/Api.java" \
  app/src/main/java/io/nayuki/qrcodegen/*.java tests/ClientTest.java
java -ea -cp build/tests:tests/json-test-runtime.jar local.couponpocket.ClientTest
python3 tests/verify.py
