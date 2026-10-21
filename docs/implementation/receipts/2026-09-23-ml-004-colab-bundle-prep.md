# ML-004 — reproducible Colab bundle prep (bounded, not trained)

Date: 2026-09-23 · Task: tracker §11 **ML-004** (preparatory slice) · Status row before: `TODO`
Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`)
Depends on: ML-002 (heads contract), ML-003 (masked-heads trainer). DATA-016 stays the blocker for the real fit.

## Scope of this slice

Bounded prep only: **nothing was trained, downloaded, or uploaded**. The goal is that when
human-gold markup exists (pilot-100 in `local-data/SETOS/annotation/pilot-20260923-strata-v1/`,
full corpus = DATA-016), build → upload → Colab preflight are single commands.

New directory `ml/camera_coach/colab_bundle/` (Own per ML-004); **no existing
`ml/camera_coach/**` file was modified**. `local-data` was read-only. Test bundle built into
`/tmp` only and deleted after verification. No git commit/push; other working-tree changes
untouched.

## What was created

| File | Role |
|---|---|
| `ml/camera_coach/colab_bundle/build_bundle.py` | stdlib builder → deterministic `tar.gz` (sorted members, mtime 0) under a caller-chosen output dir (tests used `/tmp`). Copies a hashed code closure (18 files: `production_heads.py`, `losses.py`, `train_silver_actions.py`, `evaluate_silver_pairs.py`, `data/preprocessing.py`, `models/`, contracts + validators + fixtures, `generate_camera_corruptions.py`), generates `config.json` (pinned head widths 1/15/26/5/1/1, masked-loss types, seed 20260923 + 2 variance seeds, resume every 200 steps to Drive, keep_last_k 3), emits `data_manifest.jsonl` and `bundle-receipt.json` (per-file SHA-256, git HEAD, verification result). |
| `ml/camera_coach/colab_bundle/check_environment.py` | Colab preflight, fail-closed. Verifies python/torch minimums, all 18 bundle code hashes vs `bundle-receipt.json`, runs the pinned ML-002 contract check inside the bundle, hash-verifies data at Drive paths (sample default 200 / `--full`), and enforces the human-gold gate: modes `dry_run`/`smoke` run without labels; `final_fit` exits 3 unless every label row is `human_gold=true` and contract-valid. Exit codes: 0 pass / 2 env-data fail / 3 human-gold refusal. |
| `ml/camera_coach/colab_bundle/colab_training_template.ipynb` | 11 cells: preflight → mount Drive → full hash verify → human-gold slot (TODO stub with the exact admission steps) → smoke (synthetic mini-batch, masked losses, backward, runnable today) → full train (TODO skeleton with resume-from-Drive) → per-head eval (validation only, locked test forbidden until ML-008) → FP16 Core ML export sketch (ML-012 prep) → `receipts.jsonl` on Drive. |
| `ml/camera_coach/colab_bundle/README.md` | Owner workflow: build command, Drive layout, rclone copy+check upload practice, Colab Pro notes (A100/T4, no macOS requirements.lock in Colab), and the rules (locked test, silver ≠ gold, resumability). |

`data_manifest.jsonl` (12 449 rows; **no media copied**): 11 810 `package_frame` rows from
`colab_package_v2_20260914/manifest.jsonl` (package-relative relpath + Drive placeholder +
`content_sha256`; aggregate manifest SHA-256 re-verified against `package-receipt.json` at
build), 636 `silver_derivative_image` rows + 2 `silver_pairs` manifest/receipt rows from
`silver-fit-20260918/pairs/` (`pairs.jsonl` SHA re-verified against `receipt.output_manifest`),
and one explicit `human_labels_dir` slot: `status=awaiting_owner`, expected = pilot-100
`labels.jsonl` (queue pin `cbb55e63…`, 100 items) + future DATA-013 episodes. Historical old
absolute paths from the v2 manifest are not propagated.

Upload/verify practices reference the archived `colab_package/README.md` inside
`local-data/SETOS/verification/attempts-metadata-20260923.tar.gz` (rclone `copy --immutable` +
`check --one-way`, no sync/delete/overwrite; Drive mount + hash checks in Colab). The archived
metadata was read-only; no new duplicate data packages were created.

## How it was tested (all in /tmp, all removed afterwards)

```text
build:  python3 ml/camera_coach/colab_bundle/build_bundle.py --output-dir /tmp/setos-colab-bundle
        → BUNDLE …20260923T150839+0000.tar.gz
          SHA256 8caa5b14b1e209f273b454c63d59e66fa14fc28e16cab4fa68e87df17a879145
          ROWS 12449 CODE_FILES 18 HUMAN_GOLD awaiting_owner
```

- tar listing: 23 members, expected layout (`bundle/…`, `config.json`, `data_manifest.jsonl`,
  `check_environment.py`, notebook, `bundle-receipt.json`, `README_BUNDLE.md`).
- Preflight against a `/tmp` Drive mirror (symlinks to local-data, read-only):
  `--mode dry_run --sample 40` → code hashes 18/18, contract PASS (7/7 heads, 15 issues,
  26 mapped actions), data 40/40 verified, **PREFLIGHT PASS, exit 0**.
- Fail-closed gate: `--mode final_fit` with no labels → **exit 3** (`refused_no_human_labels`);
  with a labels file whose row is `human_gold=false` → **exit 3** ("silver or unadjudicated
  labels cannot back final_fit").
- Notebook smoke cell executed verbatim from the extracted bundle: head widths
  {1, 15, 26, 5, 1, 1}, total loss finite, unadjudicated row mask = 0, all head gradients
  finite, **exit 0, warning-clean** (torch 2.10 CPU locally).
- Manifest spot-checks: one frame row and one silver-derivative row re-hashed from source →
  both `hash match: True`.
- Environment: macOS arm64, python 3.11.9, torch 2.10.0 (CPU), builder/preflight stdlib+torch
  only (`jsonschema` needed on Colab only when human labels are validated; reported as a
  fixable gap if missing).
- Cleanup: `/tmp/setos-colab-bundle`, `/tmp/mydrive` mirror and scratch script removed;
  no built bundle remains on disk.

Two real defects were caught by this local test run and fixed before finalizing: the code
closure was missing `contracts/set_composition_net_v1.json` (import-time dependency of
`losses.py`), and the smoke cell initially sent a partial issues list, which
`supervision_from_release_label` correctly rejects (all 15 heads must be covered) — the
notebook now builds a full 15-head list.

## SHA-256 (created files)

```text
b4f9a487896a641b453fea381bcc6968c4c57d276a03710897e6f285d06615a7  ml/camera_coach/colab_bundle/build_bundle.py
0623688ad22df2c4c764d85564c8283b5817111da2b108060e56628ae38ad268  ml/camera_coach/colab_bundle/check_environment.py
8dc1010217c2cd4759db04277e884b55d38f3347b8cfb7c1a3902b9e75570554  ml/camera_coach/colab_bundle/colab_training_template.ipynb
c213c5c340f0b689a128583850abf0610bbe5654862ee758d3533a7827612f25  ml/camera_coach/colab_bundle/README.md
```

## What remains (expected — data not final by design)

1. Owner annotates pilot-100 (`annotate_gui.py`, per pilot README) → adjudication (DATA-010/011)
   → fill the `human_labels_dir` slot on Drive.
2. Owner runs `build_bundle.py --full-verify` (full re-hash before upload) and uploads
   per README (rclone copy + check).
3. First real Colab run: preflight `--full` on an actual Drive mount (only sampled/partially
   verified locally), then smoke → ML-005 training entrypoint (backbone selection is ML-005's).
4. Per-head eval, calibration (ML-007), locked test (ML-008), export (ML-012) — separate rows.
5. Tracker row ML-004 status update is the orchestrator's; this receipt is the evidence.
