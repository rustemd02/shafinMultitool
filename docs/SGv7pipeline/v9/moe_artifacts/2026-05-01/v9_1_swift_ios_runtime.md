# V9.1 Swift/iOS Runtime

## proposal
- Keep screen text overlay lightweight and UI-only; do not add a new `SceneAction.ActionType`.
- Reuse existing caption/timeline scheduling; add separate top overlay channel to avoid mixing dialogue/action captions.
- Keep static JSON grammar; enforce slot ids through verifier and patch retry.

## risks
- Running multiple llama contexts remains expensive; V9.1 should not add more contexts.
- Simulator test runner may hang independently of compilation; use `build-for-testing` as compile evidence when needed.

## required_tests
- Build-for-testing through `.xcworkspace` to include Pods.
- UI state reset clears dialogue/action/screen text captions.

## open_conflicts
- Full device latency needs live AR profiling; not covered by this patch.

## approval
PASS for mobile feasibility with deferred live latency profiling.
