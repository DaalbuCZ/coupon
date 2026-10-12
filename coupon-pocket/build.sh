#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
sdk_path="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/opt/android-sdk}}"
tools_path="$sdk_path/build-tools/36.0.0"
android_jar="$sdk_path/platforms/android-36/android.jar"
for binary in aapt d8 zipalign apksigner; do
  [[ -x "$tools_path/$binary" ]] || { echo "Missing Android SDK tool: $tools_path/$binary" >&2; exit 1; }
done
mkdir -p build/classes build/dex dist .local
find app/src/main/java -name '*.java' -print | sort > build/sources.txt
javac --release 8 -Xlint:deprecation -Xlint:-options -cp "$android_jar" -d build/classes @build/sources.txt
jar cf build/classes.jar -C build/classes .
"$tools_path/d8" --lib "$android_jar" --min-api 28 --output build/dex build/classes.jar
"$tools_path/aapt" package -f -M app/src/main/AndroidManifest.xml -S app/src/main/res -A app/src/main/assets -I "$android_jar" -F build/resources.apk
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
with ZipFile('build/resources.apk') as source, ZipFile('build/unsigned.apk','w',ZIP_DEFLATED) as target:
    for item in source.infolist(): target.writestr(item,source.read(item.filename))
    for path in Path('build/dex').glob('*.dex'): target.write(path,path.name)
PY
"$tools_path/zipalign" -f 4 build/unsigned.apk build/aligned.apk
if [[ ! -f .local/development.p12 ]]; then
  keytool -genkeypair -keystore .local/development.p12 -storetype PKCS12 -storepass android -alias development -keypass android -keyalg RSA -keysize 3072 -validity 3650 -dname 'CN=Coupon Pocket Local Development' >/dev/null 2>&1
  chmod 600 .local/development.p12
fi
"$tools_path/apksigner" sign --ks .local/development.p12 --ks-pass pass:android --key-pass pass:android --ks-key-alias development --out dist/coupon-pocket-dev.apk build/aligned.apk
"$tools_path/apksigner" verify --verbose dist/coupon-pocket-dev.apk
printf '\nBuilt %s/dist/coupon-pocket-dev.apk\n' "$PWD"
