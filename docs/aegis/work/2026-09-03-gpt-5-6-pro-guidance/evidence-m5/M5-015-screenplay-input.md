# M5-015 — Screenplay input

## Scope

`SceneGeneratorViewModel.sceneDescription` remains the only screenplay draft
owner. Its existing metadata autosave and `persistWorkspaceState()` snapshot
path retain edits across sheet dismissal, re-presentation, recomposition, and
project reload. Submission still enters the existing M5-014
`SceneGenerationRequestState`; no second generation flag or draft object was
added.

The trust boundary rejects empty/whitespace-only input, input over 5,000
user-perceived `Character`s, disallowed control/NUL scalars (LF/CR remain
valid screenplay newlines), and Unicode noncharacters. The raw `String` is not
normalized or truncated, and Swift does not expose unpaired UTF-16 surrogates
as valid scalar input, so no impossible coverage claim is made. New RU/EN
catalog copy identifies oversized and invalid-text corrections.

The sheet keeps its header/cancel command outside the scrolling body, places
the generate command with native `.safeAreaInset`, and lets SwiftUI manage
keyboard avoidance without a keyboard-height constant. Existing input,
cancel, editor, validation, paste, and generate accessibility identifiers are
unchanged.

## Verification

Simulator-only verification used ordinary iPhone 17e
(`1F680A42-CEB3-43E8-9CED-52F874962A62`); no physical device or iPhone 17 Pro
was used.

- Four targeted `SceneBundlePipelineTests` passed: whitespace/empty behavior;
  sheet cancel plus owner-side persistence and project reload; Character max
  and max+1 with control/noncharacter rejection and RU/EN/emoji/newline
  acceptance; rapid double submit with one request owner.
- `SETGeneratorProductionUITests/testScreenplayDraftSurvivesCancelReopenAndKeyboardRecomposition`
  passed. It edits in landscape with the keyboard focused, proves Generate and
  Cancel remain reachable, cancels/reopens with the draft intact, rotates, and
  checks the draft remains visible.
- `git diff --check` and `python3 -m json.tool
  shafinMultitool/Resources/Localizable.xcstrings` passed.
- Stable unit result bundle: `/private/tmp/setos-m5-015-final-unit.xcresult`;
  `xcrun xcresulttool get test-results summary` reports 4 passed, 0 failed,
  and 0 skipped on the listed simulator. The earlier UI result bundle was
  transient DerivedData output and is not retained here.

Residual risk: simulator UI coverage cannot establish physical keyboard,
camera, or AR behavior; background persistence is proven through the existing
owner-side snapshot/reload seam rather than an OS background event.
