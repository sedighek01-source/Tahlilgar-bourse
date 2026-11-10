#!/usr/bin/env bash
# Builds a signed, installable APK for «تحلیلگر بورس» using only the command-line Android SDK tools
# (aapt2, javac, dx/d8, zipalign, apksigner). No Gradle or internet access required.
set -euo pipefail
cd "$(dirname "$0")"

SDK_JAR="${ANDROID_JAR:-/usr/lib/android-sdk/platforms/android-23/android.jar}"
BT="${BUILD_TOOLS:-/usr/lib/android-sdk/build-tools/debian}"
VERSION_CODE=1
VERSION_NAME=1.0.0
OUT=build
APK_NAME="Tahlilgar-Bourse-v${VERSION_NAME}.apk"

rm -rf "$OUT" && mkdir -p "$OUT/gen" "$OUT/classes"

echo "[1/6] compiling resources"
aapt2 compile --dir res -o "$OUT/res.zip"

echo "[2/6] linking manifest, resources and assets"
aapt2 link -I "$SDK_JAR" --manifest AndroidManifest.xml \
  --min-sdk-version 23 --target-sdk-version 34 \
  --version-code $VERSION_CODE --version-name $VERSION_NAME \
  -A assets --java "$OUT/gen" --auto-add-overlay \
  -o "$OUT/unsigned.apk" "$OUT/res.zip"

echo "[3/6] compiling Java"
javac -nowarn -Xlint:-options -encoding UTF-8 -source 8 -target 8 -bootclasspath "$SDK_JAR" \
  -d "$OUT/classes" $(find src "$OUT/gen" -name '*.java')

echo "[4/6] dexing"
if command -v d8 >/dev/null 2>&1; then
  d8 --min-api 23 --lib "$SDK_JAR" --output "$OUT" $(find "$OUT/classes" -name '*.class')
else
  "$BT/dx" --dex --min-sdk-version=23 --output="$OUT/classes.dex" "$OUT/classes"
fi
(cd "$OUT" && zip -q -j unsigned.apk classes.dex)

echo "[5/6] aligning"
zipalign -f -p 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

echo "[6/6] signing"
KS="${KEYSTORE:-keystore/tahlilgar-release.jks}"
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -noprompt -keystore "$KS" -storetype PKCS12 -alias tahlilgar \
    -keyalg RSA -keysize 2048 -validity 10000 -storepass "${KS_PASS:-tahlilgar-bourse}" -keypass "${KS_PASS:-tahlilgar-bourse}" \
    -dname "CN=Tahlilgar Bourse, OU=Education, O=Tahlilgar, C=IR" >/dev/null 2>&1
fi
apksigner sign --ks "$KS" --ks-key-alias tahlilgar --ks-pass "pass:${KS_PASS:-tahlilgar-bourse}" \
  --min-sdk-version 23 --v1-signing-enabled true --v2-signing-enabled true \
  --out "$OUT/$APK_NAME" "$OUT/aligned.apk"
apksigner verify "$OUT/$APK_NAME"
echo "OK -> $OUT/$APK_NAME ($(du -h "$OUT/$APK_NAME" | cut -f1))"
