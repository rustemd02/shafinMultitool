# M1-019 — Route/modal ownership audit

Task: Audit presented sheets/controllers so shell route transitions block or await only when the
active modal owns unsaved or hardware state.
Owner boundary: `NavigationOwner` (runtime-ownership-map.md row 12).
Stop gate honored: no CommercialShell route semantics or accessibility IDs changed. No production
code change required.

## Mechanism (pre-existing, tested)

`CommercialSceneLibraryRoute.hasPresentedControllerInRoute` (= nav controller's
presentedViewController, or any stacked controller presenting) gates both
`deactivateAndWait()` and `handleDidEnterBackground()` → `.blocked` before any workspace teardown.
Verified by SceneWorkspaceTeardownTests.testPresentedSceneModalBlocksWithoutStartingWorkspaceTeardown
(M1-009 evidence, 16/16 PASS).

## Modal inventory (scenes route — the only presenting route)

| Modal | Presented by | Unsaved/hardware state | Ownership during transition |
|---|---|---|---|
| SceneInputSheet (`.sheet showInputSheet`, SceneGeneratorView:83) | workspace root | draft text → VM `sceneDescription` | route blocked while presented; draft persisted by workspace teardown snapshot |
| Marker name input (`.sheet showMarkerNameInput`, :86) | workspace root | pending marker label | route blocked; AR session stays workspace-owned |
| Storyboard beat editor (`.sheet activeStoryboardEditDraft`, LegacyShell:1213) | legacy shell | unsaved beat draft (`activeStoryboardEditDraft`) | route blocked; draft dropped/cancelled only by explicit user action or playScene |
| Decision trace (`.sheet decisionTrace`, :1223) | legacy shell | none (diagnostic) | route blocked while presented |
| Recording review player (`present(playerViewController)`, :1048) | legacy shell | playback hardware (M1-017 PlaybackOwner) | route blocked; player released on disappear/dismiss/deinit |
| Share sheet (`present(activityViewController)`, :1063) | legacy shell | none (transient) | route blocked while presented |
| Alerts (`present(alert)`, :910) | legacy shell | none | route blocked while presented |

## Camera route

No modal presentations exist on `CommercialCameraCoachRoute` (entry flow is inline, not modal;
grep over CameraCoachEntryView/ContentView: no present/sheet). Its `deactivateAndWait` awaits the
camera `stopAndWait()` regardless of any system permission dialog, and the permission state
machine re-checks on foreground (M1-004 adapter).

## Conclusion

Every presented controller in the shell lives inside the scenes workspace and is covered by the
explicit `.blocked` gate; unsaved drafts are VM-owned and persisted by teardown; the only hardware
presenting modal (review player) is released by the M1-017 playback owner. Route transitions
cannot strand hardware or unsaved state behind a dismissed modal. Acceptance satisfied; no
additional production change.
