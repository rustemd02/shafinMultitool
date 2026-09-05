# M5-017 — Generator clarification flow

## Scope and contract

The Generator now has one request-owned clarification projection layered on
the accepted M5-014 state machine and M5-016 object-binding snapshot. A
clarification payload is immutable after publication and carries the active
request UUID, epoch, stable payload ID, prompt, target reference, bounded
observed candidate options, observed diagnostics, and an attempt number.
Options are derived only from the parser trace's submitted observations or
from the unresolved binding resolution's candidate IDs. A missing candidate
set fails closed to the existing parse failure copy; no positional first-match
or placeholder object is introduced. Free text is length-bounded and must
normalize to exactly one candidate alias/name/type from the same submitted
binding snapshot.

The real no-override `generateScene()` path reaches clarification for the
existing same-type marker ambiguity and opens the existing `SceneInputSheet`
through the ViewModel-owned `showInputSheet` projection. The sheet reuses the
existing SET OS surface tokens and exposes stable prompt, option, text-entry,
submit, feedback, and cancel accessibility identifiers. It does not add a
second modal or state owner.

Answers are accepted only while the exact state UUID/epoch and payload ID are
current. A valid answer amends the existing binding snapshot, re-enters
validation, and reparses through the same generation owner without creating a
new UUID or owner/job. The selected marked candidate is the only marked parser
evidence passed on continuation; detection-only candidates retain the original
parser evidence and receive an explicit binding alias. A successful continuation
clears the clarification projection only after the existing model/AR commit
and success edge. A stale, wrong-request, wrong-epoch, missing, repeated, or
invalid answer is rejected. Invalid/unresolving answers consume at most three
clarification attempts; no parser or scene commit occurs after the cap.

Cancel retires the epoch before joining any owner task, returns an active
clarification to typed `.input`, and preserves the editable draft. Editing the
draft clears the old clarification and returns to input; the next submit gets a
new request identity. Teardown clears the payload/context, fences late work,
and retires the state to `.idle` through the existing teardown owner.

## Changed files

- `shafinMultitool/SceneGeneratorModule/Services/SceneParseCoordinator.swift`
  — bounded answer/payload value types and observed-candidate construction.
- `shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift`
  — thin parser diagnostics facade for immutable payload construction.
- `shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift`
  — request context, reachable clarification publication, answer validation,
  same-request continuation, cancel, teardown, and clearing rules.
- `shafinMultitool/SceneGeneratorModule/Views/SceneInputSheet.swift`
  — clarification presentation in the existing input sheet.
- `shafinMultitoolTests/SceneBundlePipelineTests.swift`
  — narrow real-path, continuation, cancellation/teardown, stale/repeated,
  and bounded-invalid-answer coverage.

No localization catalog, route, persistence schema, backend, camera, AR,
recording, project file, or shared state module was changed.

## Verification

All verification used the permitted ordinary iPhone Air simulator
(`A6E7238C-B4C6-4988-B399-8E127CA8683B`, iOS 26.5). No physical device and no
iPhone 17 Pro were used.

- `git diff --check` — passed.
- Final focused matrix, result bundle
  `/private/tmp/m5-017-final-focused-v3.xcresult` — passed 12/12, failed 0,
  skipped 0. It covered the existing M5-014 state/identity/input/success/
  clarification/teardown checks, the M5-016 unresolved-binding gates, the
  no-override same-name marker ambiguity path, and the four new clarification
  tests:
  `testClarificationAnswerResumesSameRequestOnceAndCommits`,
  `testClarificationCancelReturnsDraftAndClearsRequest`, and
  `testClarificationRejectsStaleRepeatedAndBoundedInvalidAnswers` (plus the
  real no-override ambiguity test).
- Release exposure: `xcodebuild -showBuildSettings` resolved
  `CONFIGURATION=Release` with no DEBUG compilation condition; the incremental
  workspace Release build for the same Air destination exited 0 and produced
  `/private/tmp/m5-017-release.5jQ6f3/DerivedData/Build/Products/Release-iphonesimulator/shafinMultitool.app`.
  Existing storyboard/deprecation/asset warnings remain outside this slice.

## Judgment calls and boundaries

The clarification surface deliberately uses canonical-ID suffixes in option
labels so repeated names are distinguishable without claiming a left/right or
array-position meaning. Free text is accepted only as an exact normalized
observed alias, not as an unconstrained new parser prompt. Parser clarification
causes without an answerable submitted candidate set fail closed rather than
showing a question that cannot safely resolve identity. The three-attempt cap
is local to the active clarification request and resets on cancel, success, or
a new edited request. Existing test-only state seams retain a typed empty
payload for state-machine compatibility; that branch is DEBUG-only and is not
reachable from production.

M5-018+ remain outside this slice: accepted/leader motion/event ledgers,
backend/local progress, transport and full cancellation breadth, background
recovery, durable error taxonomy, and general retry/idempotency policy. No
Generator or App Store readiness claim is made.
