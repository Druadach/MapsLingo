# Changelog

## 0.1.0 — Prerelease

- Initial release of MapsLingo: a native in-Maps language picker for Apple Maps on iOS 15+, injected as a single dylib with TrollFools. No separate settings app, Substrate, or ElleKit.
- The picker uses stock UIKit controllers and a callback class registered through the Objective-C runtime on the main queue. No launch-time static Objective-C class, category, or protocol metadata; no method replacement; PAC and signature checks stay enabled.
- Languages are read from Maps' bundled localizations, with native names, English names, and language codes. Includes first-run presentation, a two-finger 1.2-second hold to reopen, Follow System, and Restore Original.
- The language backup is stored under `MapsLingo.SafeBackup.v1` in Maps' own preference domain, with pending/applied state so an interrupted save can be recognized.
- Verification rejects static CFString and static class-registration metadata regressions and checks every ad-hoc signature page. On-device validation beyond one iOS 15.4.1 success report is pending; treat this build as a prerelease.
