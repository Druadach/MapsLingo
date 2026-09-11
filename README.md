# MapsLingo

[简体中文](README.zh.md)

A standalone injectable dylib that adds a language picker to Apple Maps on iOS 15+ without changing the system language. Inject it with TrollFools; no separate settings app, Substrate, or ElleKit is required.

> **Status: 0.1.0 prerelease.** A user reported success on iOS 15.4.1 with this code lineage. Individual languages, gestures, restoration, and other devices have not been exhaustively checked; one success report is not a complete compatibility certification. An iOS 15.0 deployment target does not establish compatibility with every newer release.

## Design notes

A prototype crashed during launch on a reported iOS 15.4.1 arm64e device: the system authenticates the superclass pointer of statically registered custom classes, and the failure occurred before any picker code ran. This build uses stock UIKit controllers and registers a separate callback class through the Objective-C runtime on the main queue. It embeds no custom classes, categories, or protocol definitions for launch-time registration, replaces no existing methods, and does not disable PAC. Preference saving and restoration are unchanged. Verification rejects static class-registration metadata as well as static CFStrings; compilation and file-signature checks alone did not catch the old defect.

Eject all other injections before adding 0.1.0. Do not clear Maps data or repeatedly change injection strategies for this failure. The detailed feature and device checks in [publishing](PUBLISHING.md) remain necessary.

## Features

- A native picker appears on first launch. Hold **two fingers still for 1.2 seconds** in Maps to reopen it.
- Languages come from the installed Maps bundle, with native names, English names, and language codes.
- Follow System removes only Maps' language override. Restore Original restores the first saved setting.
- Stores its language backup under `MapsLingo.SafeBackup.v1`.
- No method replacement, location/region/provider changes, telemetry, network requests, or access to routes and searches.

## Install

1. Eject any existing injections from Maps and verify that Maps launches without them.
2. In TrollFools' Maps advanced settings, enable **Prefer Main Executable**. Leave Lexicographic, Compatibility Fallback, and Use Weak Reference at their defaults initially.
3. Inject only **`MapsLingo-0.1.0.dylib`**. Never inject the restore library alongside it.
4. Open Maps, select a language, and acknowledge the message. Opening the picker alone does not change the language.
5. **Swipe Maps away in the app switcher, then reopen it.** Going to the Home Screen is not enough. Existing screens are not translated live.

The checkmark represents the saved preference, not the currently rendered language. Reopen the picker with the two-finger hold; reinjection is unnecessary. Gesture interaction with Maps and accessibility features still needs device testing.

## Restore and remove

Removing the dylib alone does not undo the language preference.

- Follow System: choose the option, fully close Maps, and reopen it.
- Original setting: choose Restore Original, fully close Maps, eject the main library, and reopen Maps.
- If the picker is unavailable: eject the main library, inject only `MapsLingoRestore-0.1.0.dylib`, launch Maps for a few seconds, then close it, eject Restore, and reopen.

Restoration does not clear Maps data. It preserves a different language value set later outside the plug-in. The first-run marker remains in Maps' preferences, so reinstalling may require the gesture rather than showing the picker automatically.

## Limitations and troubleshooting

Map labels, POIs, and navigation voice may follow separate language rules. This project changes only the app's language preference, not server behavior or system daemons.

Prefer Main Executable is a preference, not a guarantee. Check TrollFools' `Best matched Mach-O is .../Maps.app/Maps` log entry. A platform/non-platform signature mismatch is a loader problem; eject all injections and verify the original app rather than deleting Apple frameworks or stacking libraries.

Strings are created at runtime to avoid the previous arm64e static-CFString authentication failure. PAC and signature checks are not disabled.

If no picker appears, try the gesture and check the injection log. A weak dependency can let Maps launch even when the plug-in is absent. For crashes, attach the new `Maps-….ips` report after removing device identifiers and personal information; retain the exception, backtrace, architecture, and dylib UUID.

## Build

macOS requires full Xcode with an iPhoneOS SDK. Verification and packaging require Node.js 22+. No SDK or toolchain is redistributed.

```bash
bash build.sh
node scripts/verify.mjs
node scripts/package.mjs
```

For Linux/WSL, set `TOOLCHAIN_BIN` and `SDKROOT` to an existing iOS cross-toolchain and SDK. Windows users can compile in WSL and run the Node commands from Windows in the project directory.

The build produces arm64 + modern arm64e dylibs. Verification checks architecture, minimum OS, dependencies, static-CFString/class-registration regressions, and every ad-hoc code-signature page. It does not establish device stability.

Outputs in `dist/` include the main/restore dylibs, build information, verification JSON, SHA-256 checksums, a release ZIP, and a source-only ZIP that excludes SDKs, toolchains, legacy files, and crash reports.

See [publishing](PUBLISHING.md) and [changes](CHANGELOG.md). The GitHub workflow builds artifacts but does not create a public release. A license has not been chosen; add an appropriate `LICENSE` before publishing as open source. This project is not affiliated with Apple or TrollFools.
