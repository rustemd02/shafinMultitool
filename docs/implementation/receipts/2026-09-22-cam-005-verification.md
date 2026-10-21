# CAM-005 — target-scoped action verification receipt

Date: 2026-09-22. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`). The initial working tree was already dirty with user-owned documentation/source changes and untracked paths; those changes were preserved. This slice changed only the CAM-005 tracker row and this receipt; no staging, commit, branch, reset, clean, stash, or worktree operation was performed.

## Evidence

- **Exact command:**
  `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -derivedDataPath /private/tmp/setos-cam001/dd -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/ActionVerifierTests/testCommandedTargetScopeRejectsAnotherEntityMovement -only-testing:shafinMultitoolTests/ActionVerifierTests/testN7OrderMakesScopeAndIdentityViolationsIncomparableDespiteScalarGrowth -only-testing:shafinMultitoolTests/ActionVerifierTests/testScopedObjectAreaCannotUseUnrelatedPrimarySubjectScalar -only-testing:shafinMultitoolTests/UserMovementObserverTests/testTargetScopedTrackerIgnoresAnotherObjectMovement test`
- **Result:** exit `0`; `** TEST SUCCEEDED **`.
- **Per-test result:** `ActionVerifierTests.testCommandedTargetScopeRejectsAnotherEntityMovement` passed; `ActionVerifierTests.testN7OrderMakesScopeAndIdentityViolationsIncomparableDespiteScalarGrowth` passed; `ActionVerifierTests.testScopedObjectAreaCannotUseUnrelatedPrimarySubjectScalar` passed; `UserMovementObserverTests.testTargetScopedTrackerIgnoresAnotherObjectMovement` passed. Total: 4 executed / 0 failures / 0 skipped.
- **Owner inspected:** `ActionVerifier.swift:354–358, 505–587` (`evaluateEntityScope` runs before effect classification; missing target and swapped track are incomparable); `UserMovementObserver.swift:727–777, 1091–1169` (`targetRefs` reaches `evaluate`, only one target displacement reads target geometry, and target-scoped scalar metrics fail closed).
- **Tests inspected:** `ActionVerifierTests.swift:1037–1119`, `:1181–1194`, `:1380–1464`; `UserMovementObserverTests.swift:1406–1445`.
- **Contract result:** a commanded object is the measured entity; unrelated subject/object movement cannot produce `improved`; a commanded target that is lost or changes track identity is incomparable; target-scoped object area cannot borrow the primary-subject area scalar.
- **Fail-closed boundary:** only single-target displacement currently has qualified entity geometry. Partial/lost/ambiguous target evidence and unsupported target scalar metrics remain incomparable; no unsupported action is promoted to success.
- **Temporary behavior:** reused existing `/private/tmp/setos-cam001/dd`; no new DerivedData directory or separately requested `.xcresult` bundle was created, and no historical temp/evidence was deleted.
- **Direct checks:** `git diff --check -- docs/implementation/APP_STORE_RELEASE_TRACKER.md docs/implementation/receipts/2026-09-22-cam-005-verification.md` exited `0`. Direct scans found no trailing whitespace on the changed CAM-005 row or in this receipt; pre-existing Markdown hard-break spaces on tracker header lines 3–7 were left untouched. Direct inspection confirmed only the CAM-005 row changed in the tracker and this receipt was added in this slice.

## Scope and residual risk

This is a focused serial simulator verification of the four CAM-005 owner tests. It does not qualify target-scoped area/depth/light/focus metrics or multi-target displacement; those remain unsupported/incomparable until an honest entity metric and identity contract exist.
