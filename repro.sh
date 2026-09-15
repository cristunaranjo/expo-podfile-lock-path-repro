#!/usr/bin/env bash
# Reproduces the path-dependent ExpoModulesCore checksum.
# Installs this project at two different absolute paths and diffs the results.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A=/tmp/aaa/app
B=/tmp/bbbbbbbbbb/app

rm -rf /tmp/aaa /tmp/bbbbbbbbbb
mkdir -p /tmp/aaa /tmp/bbbbbbbbbb

# Install once, then copy, so both trees are byte-identical and only the path differs.
cp -R "$HERE" "$A"
rm -rf "$A/.git" "$A/ios" "$A/android" "$A/node_modules"
(cd "$A" && npm install)
cp -R "$A" "$B"

for d in "$A" "$B"; do
  echo "==> prebuild + pod install in $d"
  (cd "$d" && npx expo prebuild --platform ios --clean --no-install >/dev/null && cd ios && pod install >pod.log 2>&1)
done

echo
echo "########## precompiled modules ##########"
grep -A 6 "Precompiled modules:" "$A/ios/pod.log" | head -7

echo
echo "########## SPEC CHECKSUMS diff ##########"
diff <(sed -n '/^SPEC CHECKSUMS:/,$p' "$A/ios/Podfile.lock") \
     <(sed -n '/^SPEC CHECKSUMS:/,$p' "$B/ios/Podfile.lock") || true

echo
echo "########## evaluated podspec diff ##########"
diff "$A/ios/Pods/Local Podspecs/ExpoModulesCore.podspec.json" \
     "$B/ios/Pods/Local Podspecs/ExpoModulesCore.podspec.json" || true

echo
echo "########## pod install --deployment ##########"
cp "$A/ios/Podfile.lock" "$B/ios/Podfile.lock"
(cd "$B/ios" && pod install --deployment 2>&1 | tail -10) || true
