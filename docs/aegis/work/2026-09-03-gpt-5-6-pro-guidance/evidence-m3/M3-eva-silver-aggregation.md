# M3 EVA silver aggregation evidence

## Status

Implemented in the current working tree. The pinned EVA source adapter has
finished extraction and the real silver run succeeded. This slice is a
metadata projection only. It does not create Camera Coach action labels,
human gold, a release split, or a rights grant.

## Contract

`tools/dataset/build_eva_silver.py` reads an already acquired external EVA
root and fails closed unless the root contains:

- the P1 `inventory.jsonl`, with every referenced image still present,
  regular, in-root, and byte/hash identical to its inventory row;
- the P2 `receipts/eva-source-receipt.json` attesting the pinned official EVA
  repository and commit `fb40a9f1abe4be96b69229aaac3d0838a2e1d31c`;
- `data/votes_filtered.csv` with its exact `=`-delimited upstream header;
- UTF-8-BOM-compatible `data/image_content_category.csv` with its exact CSV
  header.

The output is external-root-only:

- `silver-manifest.jsonl` — one deterministic, image-level record per image
  with a category, vote/unique-voter counts, mean/median/population standard
  deviation/MAD for `score`, `difficulty`, `visual`, `composition`, `quality`,
  and `semantic`, plus normalized uncertainty and conflict dimensions;
- `receipts/eva-silver-receipt.json` — input/output hashes, coverage,
  fail-closed unknown-row policy, aggregation thresholds, upstream scale
  semantics, pinned metadata SHA-1s, and a Colab JSONL join contract.

Before parsing, the tool verifies both EVA metadata files against the
committed-style `datasets/camera-coach/v1/sources/eva-fb40a9f1.json` path,
exact byte size, and Git blob SHA-1. It captures the source manifest, source
receipt, inventory, votes, and category hashes at admission and re-hashes all
five inputs immediately before output. A changed input aborts the write.

Rows are sorted by `image_id`, use only data-root-relative paths, preserve the
source commit, and are permanently stamped `research_only`,
`human_gold=false`, and `release_admissible=false`. The category file can
contain images without filtered votes; those rows are excluded from training
metadata and counted as `category_only_excluded` in the receipt. A vote or
category row that names an image outside the P1 inventory is an error rather
than a silently accounted-for label.

## Verification

Commands run from the repository root:

```text
$ python3 -m py_compile tools/dataset/build_eva_silver.py
PASS

$ python3 tools/dataset/build_eva_silver.py --self-test
PASS build_eva_silver self-test deterministic_sort robust_stats uncertainty_conflict category_join unknown_reference_fail_closed symlink_guard receipts_symlink_guard atomic_outputs research_only_boundary

$ git diff --check -- tools/dataset/build_eva_silver.py docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m3/M3-eva-silver-aggregation.md
PASS (no output)
```

The self-test creates only a task-owned temporary synthetic root and covers
deterministic reruns, robust statistics, uncertainty/conflict output, BOM
category parsing, category-only exclusion, unknown vote rejection without
replacing an existing manifest, same-schema metadata substitution rejected by
the pinned Git blob, admission hash-change detection, media symlink rejection,
both output-target guards (including an outside sentinel behind a symlinked
receipts directory), atomic output cleanup, and the immutable research-only
boundary. It performs no download.

The real run was:

```text
python3 tools/dataset/build_eva_silver.py \
  --data-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/eva/fb40a9f1"
```

Result:

```text
PASS build-eva-silver source_id=eva_official records=4070 manifest_sha256=8351cdfc3ca43095c109a95c6e317693f4d5479f6f8387d4f2f272cff0947a8c receipt_sha256=381937c0dba8478640860b255b25ca10cffba7e3034a71092b6831ab2245443f
```

The receipt records 5,101 verified inventory/category images, 136,943
filtered vote rows over 4,070 image IDs, and 1,031 category-only exclusions.
No unknown vote or category rows were admitted. The external root contains no
`.part` or temporary output files after the run; raw media and generated
manifests remain outside Git.

## Boundaries and next step

EVA is AVA-derived and its repository CC0 declaration does not settle the
underlying image rights. This manifest therefore remains research-only and is
not a release asset. It assigns no Camera Coach action labels and no train,
calibration, or holdout split; later Colab work must perform family-aware
splitting and keep silver/reference data separate from human-gold evaluation.
The next package can consume this export for an auxiliary aesthetic-quality
baseline or teacher bootstrap, then produce a conflict queue for human review.
