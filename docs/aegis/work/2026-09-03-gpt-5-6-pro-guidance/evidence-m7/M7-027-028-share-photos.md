# M7-027 / M7-028 — share and Photos export

Status: **implemented and verified on the current store**.

## M7-027 — share gate

`recordingShareButtonPressed` now shares only resolved, still-existing media:
a stale URL (project deleted after the artifact was cached) or a missing file
surfaces the localized recorder error band instead of a share sheet over
nothing. Cancellation remains a native no-op (the sheet dismisses itself);
route teardown releases the shell surface as before.

## M7-028 — transactional Photos export owner

`ScenePhotosExportService` (actor) + `PhotosLibraryExporting` seam +
`PHPhotosExportAdapter` production adapter:

- Authorization is contextual — `requestAuthorization(for: .addOnly)` is
  requested inside the explicit export action, never at launch (the M2-004
  permission-matrix principle, now on the export path).
- Typed outcomes: `exported` (only after the Photos change commits),
  `denied`, `restricted`, `alreadyInFlight`, `failed`. An unresolved
  `notDetermined` after the request maps fail-closed to `failed`.
- The actor's in-flight guard makes concurrent exports report
  `alreadyInFlight` without creating duplicate assets; the source file stays
  project-owned (the service never deletes or moves media).
- `NSPhotoLibraryAddUsageDescription` ships via the project's
  INFOPLIST_KEY (verified present in the pbxproj and InfoPlist.xcstrings).

## Verification

`ScenePhotosExportServiceTests` 5/5 on permitted iPhone 17e
(`/private/tmp/m7-028-tests-r5.xcresult`): authorized export emits success
only after the change; denied/restricted never touch the library; Photos
failures map to `failed`; a gated concurrent export reports
`alreadyInFlight` with exactly one perform. The share gate is covered by the
M7-026 probe matrix for the corrupt/missing legs and by the existence gate
here.

## Honest boundary

Physical Photos library behavior (permissions against a real account,
duplicate assets in the real library) remains M13 device qualification.
