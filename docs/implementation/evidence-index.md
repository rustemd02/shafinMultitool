# Evidence index (GOV-005)

Compact index of current receipts and evidence for the App Store 1.0 push. This file indexes; it does not duplicate content. Owned by `APP_STORE_RELEASE_TRACKER.md` GOV-005. Historical material is listed separately and is not fresh evidence.

## Current (fresh, 2026-09-20+)

| Area | Evidence | Candidate context |
|---|---|---|
| Inventory/scope baseline | `receipts/2026-09-20-gov-001-fresh-inventory.md` | HEAD `f8b6afd`, branch `store` |
| Acceptance→task map | `receipts/2026-09-20-gov-004-acceptance-task-map.md` | Gates A–L mapped; I/J explicitly deferred |
| Owner decisions | tracker §8 GOV-002 (Scene stays, held), GOV-003 (iPhone+iPad), dated 2026-09-20 | HEAD `f8b6afd` |
| Storage audit (GOV-007) | `receipts/2026-09-22-gov-007-storage-audit.md` | SHA-256: 95 206 files / 21.09 GB; 13.197 GB verified reclaim (attempts+v1); план — §19 п.8; ничего не удалено |
| Data contracts & coverage | `receipts/2026-09-22-data-001-release-label-contract.md`, `…-data-002-release-capability-mapping.md`, `…-data-003-local-data-inventory.md`; `docs/implementation/data-coverage-matrix-v1.md` | release-label v1 closed; 68/68 mapping; 46 families / 39.47 GB; human-gold = 0 везде |
| Annotation tool → release contract | `receipts/2026-09-22-data-005-annotation-release-label.md`, `…-data-005-gui-elicitation.md`, `…-data-006-annotation-api-audit.md`, `…-data-007-import-identity.md` | round-trip contract-valid; GUI-элиcitации; wire-schema gate; identity 900/450 preserved |
| Production model contract | `ml/camera_coach/contracts/camera_production_heads_v1.md` + `check_production_heads_v1.py` (PASS); `receipts/2026-09-22-ml-002-…`, `…-ml-003-…` | 7 heads; action drift серебряного checkpoint записан; masked losses, 74 tests |
| Calibration artifact | `receipts/2026-09-22-cam-003-calibration-contract.md` | fail-closed loading, 20/0; артефакт не существует/admitted |
| UI states & slices | `docs/implementation/ui-states-matrix-v1.md`; `receipts/2026-09-22-ui-001/002/006/007/008/009/011-…` | 91 state; tokens 35/35; Dynamic Type 77/0; a11y 62/0; iPad landscape реальной геометрией; Library 28/0 |
| Tests & required check | `docs/implementation/test-command-matrix-v1.md`; `receipts/2026-09-22-rel-001-…`, `…-rel-003-…`; `scripts/required_check.sh` | M0–M7 blocking/diagnostic/device-gated; сквозной прогон 2026-09-22: PASSED (133/0 + contracts + privacy) |
| Environment fact | Xcode 27.0 (27A266a) / SDK 27.0 — workspace lane падает до компиляции (Pods pins); обход задокументирован | Указано в `receipts/2026-09-22-cam-003-…`; базовый CAM-001/009 baseline на новом тулчейне не перепроверялся |

## Standing evidence referenced by tracker baseline (BASE-001…015)

- `docs/implementation/audits/` — release-bundle, privacy-permissions, dependency-provenance, test-topology, camera-session, coaching-loop event, runtime-entry audits.
- `docs/implementation/release/` — AppStoreSubmissionGates.json, metadata/privacy/review drafts, ExportOptions, ReproducibleBuild.
- `docs/implementation/provenance/` — component provenance/admission JSON+MD (incl. release-component-status.json with 4 PENDING rows).
- `docs/implementation/PRODUCTION_ACCEPTANCE.md` — unchanged acceptance contract (gates A–L).
- `ml/camera_coach/INTEGRATION.md` and hash-bound receipts under `../setos-backend/local-data/SETOS/` — Stage 1/2 research artifacts and Core ML parity.
- `../setos-backend/README.md`, `OPERATIONS.md`, `deployment/`, `LOCAL_DATA.md` — backend package and local data mapping.

## Historical (not current evidence)

- Deleted-in-worktree aegis plans/handovers (see GOV-001 receipt) — recoverable via `git show HEAD:<path>`.
- `docs/implementation/STATUS.md`, `docs/implementation/BACKLOG.md` — superseded historical snapshots (deleted in worktree; recoverable from history).
- `docs/thesis/**`, `diploma.md` — thesis evidence, not release evidence.

Update rule: append a row under "Current" when a new receipt is accepted; move a row to "Historical" when a newer receipt supersedes it.
