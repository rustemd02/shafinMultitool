# M9-004 — lens UI

Status: **verified on the current store; no production change required**.

## Verified surface (`ZoomControlView` + `SETCameraLensStatus`)

- **Only available options visible.** The expanded menu iterates exactly
  `availableLenses` (empty → rail hidden, expand collapses on empty);
  no focal-length rail is ever invented.
- **Selected state clear.** Current lens renders semibold + primary with
  the `setOrange` underline marker and exposes VoiceOver `isSelected` +
  selected value; others render regular + secondary.
- **Switching/failure states clear.** `SETCameraLensStatus` shows a
  localized switching-to/failed message naming the requested and current
  lenses, placed by the subject-safe solver; interaction locks during the
  switch (`isInteractionLocked` disables option buttons).
- **Hit targets + VoiceOver.** Every option meets the 44pt minimum with a
  rectangular content shape; the control exposes identifier
  `camera_coach_zoom_control`, label, per-option labels/values, and the
  expand hint — all through production copy keys.

## Verification

`testLensControlStartsCollapsedAndExpandsFromRealFixtureLenses` passed on
permitted iPhone 17e (`/private/tmp/m9-004-tests.xcresult`): collapsed
shows WIDE, expand reveals ULTRA + TELE from real fixture lenses.
