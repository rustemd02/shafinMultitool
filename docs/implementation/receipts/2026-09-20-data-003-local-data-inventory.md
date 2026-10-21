# DATA-003 — Relocated local-data inventory receipt

Date: 2026-09-20. Mode: **read-only** — nothing in the data tree was modified, moved or deleted; historical manifests keep original bytes and old absolute `~/Library/Application Support/SETOS/...` paths (AGENTS.md / `../setos-backend/LOCAL_DATA.md` rule preserved).

- Machine receipt: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/inventory/2026-09-20-data-003-inventory.json`
- Machine receipt SHA-256: `1fa36be3928e2b451e5c373e895473c110b2d51191753f4b091726f6a657ba26`
- Method: recursive metadata walk (file counts + byte totals per family); SHA-256 recomputed only for small root-level manifest/receipt files; rights parsed from existing receipts without rewriting them. Media bytes were NOT re-hashed (52 GB; per-record `image_sha256` remains in the original manifests).

## Totals

- 225 families, 253 490 files, 52.3 GB under `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/`.

## Key families (tier, size, rights)

| Family | Tier | Files | Bytes | Rights evidence |
|---|---|---:|---:|---|
| `research/ava` (human-rated-20k) | silver/research | 16 814 | 0.87 GB | "AVA research dataset; research/demo use only, no redistribution" |
| `research/aadb`, `research/eva` (+warp256/fb40a9f1 manifests) | silver/research | 14 551 | 0.92 GB | raw/silver manifests with per-record sha256; no blanket license note → per-record provenance required |
| `research/cinematic` | silver/research | 7 116 | 2.55 GB | CC-BY Blender open movies; attribution required, no redistribution |
| `research/synthetic` (SceneTrans pairs) | silver/research | 2 261 | 7.07 GB | SceneTrans README front-matter: `license: cc-by-4.0` |
| `research/temporal` (3 candidate sets) | silver/research | 10 000 | 2.64 GB | per-video MediaWiki imageinfo rights policy receipt |
| `research/commons` (v1-pilot-20-r3) | silver/research | 794 | 0.56 GB | per-file accepted-rights receipts (Wikimedia, e.g. CC BY 4.0) |
| `research/photography` | silver/research | 2 119 | 4.17 GB | commons_quality_diverse manifest: CC BY-SA 4.0; openimages intake has `intake-blocked.json` |
| `research/paired-corruptions` | silver/research | 5 603 | 1.20 GB | derived from aadb/eva/commons roots via generator receipts |
| `research/lighting` (Poly Haven) | silver/research | 41 | 0.03 GB | API terms stored; assets CC0 |
| `research/webresearch-2026-09-14` | silver/research | 13 791 | 1.69 GB | package receipts + verification manifests present |
| `research/edge-controls`, `geometry`, `runs`, `vlm-polza`, `bundles` | silver/research receipts | 466 | 0.22 GB | run receipts with tool/input hashes |
| `colab_package` + 5 v2 attempts (20260914) | silver/research packages | 62 231 | 15.6 GB | package receipts, CC attribution notes |
| `silver-fit-20260918` | silver/research fit artifacts | 1 332 | 0.72 GB | config/logs/pairs/holdout for the ML-001 baseline |
| `annotation/*` (pilot-20260914-v4, intake/checks/guards/final 20260916, language-review, verification) | human-annotation | 624 | 0.03 GB | pilot receipt + teacher batches; CC BY-SA 3.0 source note on pilot |
| `verification/*` (63 packages) | evidence-receipts | 20 000+ | 12 GB | bound test/verification artifacts incl. camera-binding, DETR tracking, consent UI |
| `snapshots/*` (10 packages) | evidence-receipts | ~ | 3.4 MB | backend repair/deploy snapshots |
| `inventory/` (this receipt's machine JSON) | evidence-receipt | 1 | — | created 2026-09-20 by this task |

## Facts that matter downstream

1. **Silver receipts carry explicit admission flags**: `research_only: true`, `release_admissible: false`, `human_gold: false` (e.g. `research/runs/stage2-local-20260913/receipt.json`, `camera-silver-action-pair-receipt-v1`). This mechanically supports the tracker rule "не выдавать silver за human gold".
2. **Old absolute paths** are embedded in historical manifests (Library root). Per AGENTS.md they are NOT rewritten; consumers must apply the `LOCAL_DATA.md` relocation mapping.
3. **Rights gaps to carry into DATA-004/015**: `aadb`, `eva` raw/silver manifests have no family-level license note (per-record provenance needed before any release use); `research/photography` contains an `intake-blocked.json` subpackage; `paired-corruptions` has no direct manifest at family root (derivation receipts live in `runs/`).
4. **Nothing deleted, nothing rewritten** — the duplicate path aliases (old Library root vs `local-data/SETOS/`) remain side by side in the historical bytes.
