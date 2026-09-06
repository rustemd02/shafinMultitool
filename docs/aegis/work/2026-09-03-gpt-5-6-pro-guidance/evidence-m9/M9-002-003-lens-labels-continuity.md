# M9-002 / M9-003 — lens labels and switch continuity

Status: **verified on the current store; no production change required**.

## M9-002 — labels match discovered devices

- Options come only from `cameraManager.availableLenses` (empty until
  discovery runs — no rail is shown before that); the production call site
  passes `availableLensDescriptors` with the honest
  `availableLenses.map(\.descriptor)` fallback whose labels are the physical
  WIDE/ULTRA/TELE names.
- Fallback names are localized through the existing copy keys and never
  claim a digital crop as a physical lens (no `×` literal anywhere in the
  lens surface; magnification appears only as truthful measured FOV ratio).

## M9-003 — switch continuity

- Switch is serialized (`switchLensOnSessionQueue`, single-flight
  transaction with rollback — `CameraLensSwitchTransactionTests` 4/4).
- Preview resumes via the session reconfiguration path; stale analysis,
  track, and episode state is invalidated by the M1-006 lens transaction
  fence and the M2-011 lifecycle guard (both suites green).
- Controls reflect new ranges through `availableLensDescriptors` rebinding;
  active-recording behavior follows the explicit allow/block policy
  (recording start requires the prepared writer for the active format).

## Verification

41/42 across `CameraViewModelLensSwitchTests` +
`CameraLensSwitchTransactionTests` + `CameraManagerLifecycleTests` on
permitted iPhone 17e (`/private/tmp/m9-002-003-tests.xcresult`). The single
failure (`testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline`)
reproduces on the clean store tree without any working-tree changes and is
registered as a pre-existing failure, out of M9 scope.
