# MapsLingo

[简体中文](README.zh.md)

A standalone language picker for Apple Maps on iOS 15+. Switch the Maps interface language freely, decoupled from the system-wide language setting.
💡 Compatibility: verified on a real device running iOS 15.4.1. If your setup runs into problems, see [3. Submitting Crash Logs](#crash-logs).

Implemented as a dylib injected through TrollFools. It replaces no Objective-C methods, sends no telemetry, makes no network requests, and never reads or records location, routes, or personal data.

<img width="300" alt="20260911-210409" src="https://github.com/user-attachments/assets/2e6a2b40-88b1-4bad-874f-d59bae68ac3e" />

---

## 🌟 Core Features

- **Standalone language switching**: dynamically reads the localizations bundled with Apple Maps and offers a native iOS language picker.
- **Handy gesture summon**: shown automatically on first launch; afterwards just **hold two fingers still anywhere in Maps for 1.2 seconds** to bring it back.
- **One-tap follow / restore**:
  - **Follow System**: removes the standalone language setting so Maps follows the iOS system language again.
  - **Restore Original**: one tap restores the state saved before the first change (safe backup kept under `MapsLingo.SafeBackup.v1`).
- **Clean and safe**: never touches system region, location, map provider, or navigation data, and relies on no external servers.

---

## 📦 Release Artifacts

| File | Type / purpose | Audience |
| :--- | :--- | :--- |
| **`MapsLingo-0.1.0.dylib`** | **Main plug-in library** | Regular users (normal use needs only this file injected) |
| **`MapsLingoRestore-0.1.0.dylib`** | **Emergency restore library** | Recovery tool for when the picker cannot be opened (must never be injected alongside the main library) |
| `MapsLingo-0.1.0-release.zip` | Complete release package | Binaries, documentation, build log, and verification report |
| `SHA256SUMS-0.1.0.txt` | Hash checksum file | Verify file integrity and authenticity |
| `VERIFICATION-0.1.0.json` / `BUILD-INFO-0.1.0.txt` | Build and signing reports | For advanced users and security audits |

---

## 🚀 Installation and Usage

### Step 1: Prepare and inject
1. Swipe the **Apple Maps** card away in the app switcher to quit Maps completely.
2. Open **TrollFools** and go to **Advanced Settings**:
   - Enable **Prefer Main Executable**.
   - Keep the other options at their defaults (`Lexicographic` on, `Compatibility Fallback` on, `Use Weak Reference` on).
3. Inject **`MapsLingo-0.1.0.dylib`**.

### Step 2: Pick a language and make it take effect
1. Open Apple Maps and wait for the language picker to appear automatically (if it does not, **hold two fingers still for 1.2 seconds** on the map).
2. Choose the language you want and tap **confirm**. The checkmark in the panel means "saved preference"; the currently open screen does not update immediately.
3. **Key step (making the setting take effect)**: open the app switcher, **swipe the Apple Maps card away to quit it completely, then reopen Maps**.
   > ⚠️ **Note**: merely returning to the Home Screen is not a full quit. The language preference only loads on the app's next cold start.

---

## 🔄 Restore and Uninstall

> ⚠️ **Important**: removing the dylib in TrollFools alone does **not** undo the saved language preference.

### Option A: return to the system language (recommended)
1. Hold two fingers to open the in-Maps panel, choose **Follow System**, and confirm.
2. Kill Maps from the app switcher and reopen it.
3. (Optional) remove `MapsLingo-0.1.0.dylib` in TrollFools.

### Option B: restore the original setting from before the first change
1. Open the in-Maps panel, choose **Restore Original**, and confirm.
2. Kill Maps completely.
3. Remove the main library in TrollFools, then reopen Maps.

### Option C: emergency restore (the picker cannot be opened)
1. In TrollFools, **remove the main library** `MapsLingo-0.1.0.dylib`.
2. Inject only the emergency restore library **`MapsLingoRestore-0.1.0.dylib`**.
3. Open Maps and wait 3–5 seconds.
4. Kill Maps from the app switcher, **remove the restore library** in TrollFools, and reopen Maps.

---

## ⚠️ Limitations and Troubleshooting

### 1. What the language setting affects
* **Interface vs. place names vs. voice**: the iOS app interface language, map POI place names, and Siri navigation voice run through separate data pipelines. This plug-in switches the App UI language only — it **cannot, and does not attempt to**, force the vector place names returned by Apple's map servers or the voice engine to change.

### 2. Injection failed / the picker does not appear
* **First-run notice**: after the first-launch notice is dismissed it does not repeat on every launch; summon the panel with the **two-finger 1.2-second hold**. Some accessibility features or gesture tweaks may conflict with the gesture.
* **Confirm the target process**: check the TrollFools injection log for `Best matched Mach-O is .../Maps.app/Maps` — only that line confirms the main executable was targeted.
* **Platform-binary error**: if the log shows `mapping process is a platform binary, but mapped file is not`, there is a loading or signing problem. Tap **Eject All** in TrollFools and verify the original Maps still launches. Never delete Apple system frameworks or blindly stack injections.

<a id="crash-logs"></a>

### 3. Submitting crash logs
If Maps crashes, the logs live under: `Settings` → `Privacy & Security` → `Analytics & Improvements` → `Analytics Data`. Look for files whose name starts with `Maps-` and ends with `.ips` (for example `Maps-202X-XX-XX.ips`).
> 💡 **Before posting feedback**: strip device identifiers and other sensitive personal information from the log. Keep the exception type, the call stack, the hardware architecture, and the plug-in UUID.

---

## 🛠️ Local Build

### Requirements
- **macOS**: a full Xcode install with the iPhoneOS SDK, plus Node.js 22+ (the SDK and build toolchain are **not** distributed with this repository).
- **Linux / WSL**: cross-compilation is supported.

### Build commands

#### macOS + Xcode:
```bash
bash build.sh
node scripts/verify.mjs
node scripts/package.mjs
```

#### Linux / WSL cross-compilation:
```bash
TOOLCHAIN_BIN=/path/to/iphone/bin \
SDKROOT=/path/to/iPhoneOS.sdk \
bash build.sh
node scripts/verify.mjs
node scripts/package.mjs
```
> **Tip**: if the environment variables are not set, the Linux build falls back to the local `.build-tools/toolchain-modern/linux/iphone/bin` and `.build-tools/sdk/iPhoneOS15.6.sdk`. Windows users can compile in WSL, then run the Node.js verification and packaging steps from Windows.

The default output is a universal dylib for arm64 + the modern arm64e ABI (strings are created at runtime and comply with PAC pointer authentication). All artifacts are written to `dist/`.

---

## 📄 Declaration and License

- This project is open source under the **MIT license**.
- It is an independent open-source plug-in with no affiliation to Apple Inc. or the TrollFools development team.
