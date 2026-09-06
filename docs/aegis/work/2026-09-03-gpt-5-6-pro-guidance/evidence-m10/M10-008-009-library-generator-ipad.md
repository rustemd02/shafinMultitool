# M10-008 / M10-009 — Library and Generator iPad

Status: **closed on the current store**.

## M10-008 — Library iPad

`SETLibrarySceneList` reads `horizontalSizeClass`: regular width renders a
two-column contact sheet (row-major order, same row identities/actions);
compact degrades intentionally to the single column. Actions and reading
order are unchanged in both. Library model regression 19/19.

## M10-009 — Generator iPad

`SceneInputSheet` reads `horizontalSizeClass`: regular width shows the
editor plus an independent context column (marked/detected objects);
compact keeps the portrait stack. Draft, clarification, and focus state
are shared owners, so resize preserves state by construction. The primary
generate action stays in the editor column's keyboard-aware safe-area
inset in both layouts; software/external keyboards cannot cover it.

## Verification

Input-sheet UI lane 3/3 on permitted iPhone 17e
(`/private/tmp/m10-008-009-tests.xcresult`): route reaches workspace+sheet,
whitespace validation, draft survives cancel/reopen/keyboard
recomposition. iPad hardware rendering remains M13.
