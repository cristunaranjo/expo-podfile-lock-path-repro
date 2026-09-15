# Repro: precompiled `ExpoModulesCore` makes the iOS `Podfile.lock` checksum path-dependent

Minimal reproducible example for an Expo SDK 57 bug: with precompiled Expo modules enabled (the iOS
default since SDK 56), `ExpoModulesCore`'s entry in `SPEC CHECKSUMS` depends on the project's
absolute path on disk. The same project in two directories produces two different checksums, so a
committed `Podfile.lock` is not reproducible and `pod install --deployment` can never pass.

This project is an untouched `npx create-expo-app@latest --template blank` scaffold. Nothing here
has been modified — the bug reproduces on the stock template, and `npx expo-doctor@latest` reports
21/21 checks passing.

## Reproduce

Requires macOS with Xcode and CocoaPods.

```bash
git clone https://github.com/cristunaranjo/expo-podfile-lock-path-repro /tmp/aaa/app
cd /tmp/aaa/app && npm install

# same project, second location — the absolute path is the only variable
mkdir -p /tmp/bbbbbbbbbb && cp -R /tmp/aaa/app /tmp/bbbbbbbbbb/app

for d in /tmp/aaa/app /tmp/bbbbbbbbbb/app; do
  (cd "$d" && npx expo prebuild --platform ios --clean --no-install && cd ios && pod install)
done

diff <(sed -n '/^SPEC CHECKSUMS:/,$p' /tmp/aaa/app/ios/Podfile.lock) \
     <(sed -n '/^SPEC CHECKSUMS:/,$p' /tmp/bbbbbbbbbb/app/ios/Podfile.lock)
```

Or just run `./repro.sh`, which does the above and prints every diff below.

## Expected

Identical `SPEC CHECKSUMS` in both directories.

## Actual

Exactly one line differs:

```
10c10
<   ExpoModulesCore: c78995311af49c8329d11030e281ab339e2716f8
---
>   ExpoModulesCore: ba041556a6d0bf963bf1c22d0bd99f00af2c305c
```

Copying one lock into the other checkout and running `--deployment` there:

```bash
cp /tmp/aaa/app/ios/Podfile.lock /tmp/bbbbbbbbbb/app/ios/Podfile.lock
cd /tmp/bbbbbbbbbb/app/ios && pod install --deployment
```

```
Verifying no changes
[!] There were changes to the lockfile in deployment mode:
SPEC CHECKSUMS:
  ExpoModulesCore:
    New Lockfile: ba041556a6d0bf963bf1c22d0bd99f00af2c305c
    Old Lockfile: c78995311af49c8329d11030e281ab339e2716f8
```

## Why only `ExpoModulesCore`

That install precompiles four modules:

```
[Expo-precompiled] Precompiled modules:
[Expo-precompiled]   📦 ExpoFileSystem (57.0.7)
[Expo-precompiled]   📦 ExpoFont (57.0.4)
[Expo-precompiled]   📦 ExpoModulesCore (57.0.18)
[Expo-precompiled]   📦 ExpoModulesWorklets (57.0.18)
```

Only `ExpoModulesCore` drifts. Diffing the evaluated podspecs CocoaPods stored shows two fields
carrying the absolute path:

```
$ diff "/tmp/aaa/app/ios/Pods/Local Podspecs/ExpoModulesCore.podspec.json" \
       "/tmp/bbbbbbbbbb/app/ios/Pods/Local Podspecs/ExpoModulesCore.podspec.json"
16c16
<     "http": "file:///private/tmp/aaa/app/node_modules/expo-modules-core/prebuilds/output/debug/xcframeworks/ExpoModulesCore.tar.gz",
---
>     "http": "file:///private/tmp/bbbbbbbbbb/app/node_modules/expo-modules-core/prebuilds/output/debug/xcframeworks/ExpoModulesCore.tar.gz",
```

(`prepare_command` differs too, embedding the same tarball path.)

`ExpoModulesCore.podspec` is the only podspec that calls `try_link_with_prebuilt_xcframework` on
itself, which rewrites its own `source` to an absolute local file URI. Every other precompiled
module is patched through the `Pod::Sandbox#store_podspec` override in
`expo-modules-autolinking/scripts/ios/cocoapods/sandbox.rb`, which puts the original checksum back
after patching — which is what keeps those stable.

## Workaround

`ios.usePrecompiledModules: false` in `expo-build-properties` restores a reproducible lock, at the
cost of the feature.

## Environment

- `expo` ~57.0.22, `expo-modules-core` 57.0.18, `expo-modules-autolinking` 57.0.13
- `react-native` 0.86.3, Hermes, New Architecture
- CocoaPods 1.16.2, Ruby 3.2.2, macOS 26.6.2, Xcode 26.6 (Apple silicon)
