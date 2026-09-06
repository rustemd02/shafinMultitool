# M0-006 — build settings matrix (app/unit/UI × Debug/Release)

Generated 2026-09-06 from live `xcodebuild -showBuildSettings`.

| Setting | app Debug | app Release | unit Debug | unit Release | UI Debug | UI Release | Verdict |
|---|---|---|---|---|---|---|---|
| PRODUCT_NAME | shafinMultitool | shafinMultitool | shafinMultitoolTests | shafinMultitoolTests | shafinMultitoolUITests | shafinMultitoolUITests | OK (per-target names) |
| WRAPPER_EXTENSION | app | app | xctest | xctest | xctest | xctest | OK |
| MACH_O_TYPE | mh_execute | mh_execute | mh_bundle | mh_bundle | mh_bundle | mh_bundle | OK |
| SWIFT_VERSION | 5.0 | 5.0 | 5.0 | 5.0 | 5.0 | 5.0 | OK |
| IPHONEOS_DEPLOYMENT_TARGET | 17.0 | 17.0 | **17.2→17.0** | **17.2→17.0** | 17.0 | 17.0 | **FIXED this task** |
| TARGETED_DEVICE_FAMILY | 1,2 | 1,2 | 1,2 | 1,2 | 1,2 | 1,2 | OK |
| CODE_SIGN_STYLE | Automatic | Automatic | Automatic | Automatic | Automatic | Automatic | OK |
| BUNDLE_ID | …shafinMultitool | …shafinMultitool | …shafinMultitoolTests | …shafinMultitoolTests | …shafinMultitoolUITests | …shafinMultitoolUITests | OK |
| Optimization | -Onone | -O wholemodule | -Onone | -O wholemodule | -Onone | -O wholemodule | OK (expected Debug/Release split) |
| TEST_HOST/BUNDLE_LOADER | n/a | n/a | app binary | app binary | n/a (UI) | n/a (UI) | OK |

## Mismatches found and disposition

1. **Unit-test target was 17.2 while app + UI tests were 17.0** — fixed in
   `project.pbxproj` (test Debug+Release → 17.0). A higher test-only floor
   would silently exclude the app's own minimum-OS surface from coverage.
2. **Project-level default 16.2** — superseded by every target's explicit
   17.0; recorded as dead default, not a mismatch (no target inherits it).
