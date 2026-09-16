# M3 AADB source adapter evidence

## Scope and authority

This slice adds a fail-closed, resumable adapter for the official AADB
repository `aimerykong/deepImageAestheticsAnalysis` at commit
`a962a1d8c313cdbec97e51381187ffbaac469b28`.  The tracked source specification
records the official Google Drive IDs for the original-size train archive,
the original-size new-test archive, and `imgListFiles_label.zip`, plus the
official `AADBinfo.mat`, `AADBstatistics.m`, and `README.md` objects.

The observed original-size response lengths are retained as untrusted
bootstrap hints (2,190,275,815 train bytes and 221,891,666 test bytes).  They
are not archive pins.  Their SHA-256 values, and the label archive size/hash,
remain `null` until a full official response is streamed by the one-time
bootstrap command.  `--fetch` refuses to start while any of those exact pins
is absent from `aadb-v1.json`.  The smaller official warp-256 reference is
recorded separately with its verified 138,076,608-byte SHA-256 pin
`a31adc66fd47396cabcb581e66fa3e72b38814d6957b22bc3e2edab9e77126d2`; it is
not mixed into the original-size train/test projection.  Its pinned central
directory contains 9,958 images: 9,458 names link to the exact train/test
lists in `AADBinfo.mat`, while 500 legacy extras are counted and excluded.
Linked records are content-deduplicated before the common intake using the
source-file SHA-256; the deterministic winner order is train before test,
then source ID, source record ID, and source image name.  A cross-split
duplicate is excluded from the later split rather than leaking the same
content into both splits.  The admitted count is
`9458 - actual duplicate-linked exclusions`, so it may be less than 9,458 on
the real corpus.

## Adapter behavior

`tools/dataset/fetch_aadb.py` writes only to an external caller-selected root:

```text
images/train/        original-size train media
images/test/         original-size new-test media
labels/              selected upstream regression files
metadata/            AADBinfo.mat, AADBstatistics.m, README.md
raw-manifest.jsonl   only image_id and data-root-relative path
inventory.jsonl      existing camera_source_intake verify-local output
silver-manifest.jsonl  overall score + 11 auxiliary attributes
receipts/aadb-source-receipt.json
```

The bounded `--compact --fetch` mode reuses that pinned warp-256 ZIP (or
downloads it if no path is supplied), downloads and verifies the pinned
`AADBinfo.mat`, extracts only the linked images, and emits
`receipts/aadb-compact-receipt.json`.  Compact silver rows preserve
`overall_score` only; the 11 auxiliary attributes are deliberately absent
until the separately pinned `imgListFiles_label.zip` is acquired.  The compact
receipt records `archive_images=9958`, `matched_images=9458`,
`excluded_legacy_extras=500`, and the actual `admitted_images` plus a complete
`duplicate_linked_exclusions` list (SHA, loser/winner source IDs and names,
original overall scores, split, and cross-split flag).  The 500 unmatched
legacy extras and linked duplicate exclusions remain separate receipt
categories; group count and loser/excess count are both attested for the real
corpus.  Compact verification requires exact warp-256 basenames (the real
reference has no normalized-name changes) and binds each winner name to the
fresh inventory relative path.

The downloader uses fixed HTTPS hosts/URLs, curl range continuation against
`.part` files, exact size/SHA-256 checks, effective-host checks, and HTML/
Google-interstitial rejection. ZIP/TAR inspection rejects traversal,
absolute/drive paths, symlinks, duplicate members, unsupported members, CRC
errors, and excessive member/aggregate sizes. Extraction is deterministic and
promoted only on equal-content conflict checks. Archive staging is removed
only after media verification, label linkage, silver projection, and receipt
creation have succeeded; interrupted partials remain resumable. Signature
probes use bounded stream reads (512 bytes for HTML detection and 8 bytes for
archive/MAT signatures), so a multi-gigabyte archive is never loaded into RAM
for a type check. Compact linked-image deduplication happens before the
unchanged `camera_source_intake.py`; the shared intake's duplicate-content
guard is not weakened. A supplied compact archive is resolved and rejected if it is
inside the managed output root before that root is created or changed.

The selected label files are `imgListTrainRegression_<Attribute>.txt` and
`imgListTestNewRegression_<Attribute>.txt` for the documented 11 attributes.
Legacy test and validation files are deliberately ignored. Filename linkage
must be exact after the documented test score-prefix normalization; unknown
or missing references fail closed. Trailing source fields are preserved under
`original_rater_or_uncertainty_fields` when present.

Every silver row and receipt carries:

```text
research_only=true
human_gold=false
release_admissible=false
model_redistribution_cleared=false
label_boundary=auxiliary_aesthetic_attributes_only
```

No AADB value is mapped to an issue, action, KEEP, good-frame, risk,
abstention, locked holdout, Camera Coach human gold, or release evidence.

## Commands and bounded verification

Bootstrap (parent-run only after rights/access review; it may download the
large archives, but does not extract or admit them):

```text
python3 tools/dataset/fetch_aadb.py \
  --output-root <external-aadb-root> \
  --bootstrap-pins <external-proposed-pin.json>
```

After a human reviews and copies every exact proposed size/hash into the
tracked source spec:

```text
python3 tools/dataset/fetch_aadb.py --output-root <external-aadb-root> --fetch
python3 tools/dataset/fetch_aadb.py --output-root <external-aadb-root> --verify-local
```

For a bounded run using the already downloaded official reference archive:

```text
python3 tools/dataset/fetch_aadb.py \
  --output-root <external-aadb-compact-root> \
  --compact --fetch \
  --warp256-archive <external-datasetImages_warp256.zip>
python3 tools/dataset/fetch_aadb.py \
  --output-root <external-aadb-compact-root> \
  --compact --verify-local
```

The adapter self-test is network-free and uses tiny local fixtures.  It
covers resume offsets, exact-hash failure, HTML rejection, archive traversal,
annotation projection/linkage, compact overall-score-only projection with an
explicit legacy-extra exclusion and a linked train/test byte duplicate,
pre-intake content deduplication with no duplicate SHA in inventory, bounded
signature reads, managed-output-root archive rejection, a `.part.headers`
symlink rejection, prefixed winner/loser-name tampering rejection,
tampered deduplication-receipt rejection, and byte-preserving read-only
verification.  When the supplied official files are
present, it additionally parses the pinned compressed/cell/UTF-8 MAT v5 file
and hashes/inspects the supplied warp-256 ZIP central directory without
extracting it.  No multi-GB archive was downloaded or extracted in this
implementation turn.

## Verification evidence

Commands run from the repository root:

```text
$ python3 -m py_compile tools/dataset/fetch_aadb.py
PASS

$ python3 tools/dataset/fetch_aadb.py --self-test
PASS fetch-aadb source_id=aadb_official records=2 archives_retained=false
PASS verify-local-aadb source_id=aadb_official records=2 read_only=true
PASS fetch_aadb self-test resume hash archive_traversal annotation_projection compact_mode content_dedupe read_only_verify bounded_signature_reads managed_archive_guard header_symlink_guard official_mat_smoke=false warp256_reference_smoke=true

$ python3 -m json.tool datasets/camera-coach/v1/sources/aadb-v1.json >/dev/null
PASS

$ python3 -m json.tool datasets/camera-coach/v1/research-source-catalog.json >/dev/null
PASS

$ git diff --check
PASS (no tracked-file whitespace errors)
```

The self-test creates and removes its temporary root.  No raw media or label
archive is added to Git.  The external bootstrap root and any proposed pin
receipt remain outside repository ownership.

## Published compact research corpus

The audited compact adapter was run against the pinned warp-256 archive and
then rechecked with `--compact --verify-local`. The durable external root is
`~/Library/Application Support/SETOS/Datasets/camera-coach/research/aadb/warp256-v1`.

- archive images: `9,958`;
- MAT-linked train/test images: `9,458` (`8,458` train + `1,000` test);
- admitted unique images and overall-score rows: `9,433`;
- linked duplicate losers excluded before intake: `25`;
- unmatched legacy extras excluded: `500`;
- missing linked images: `0`.

The inventory SHA-256 is
`a3c32369dbb337396058e21e82300670b558eb069fba6e2d4b656d35cb24b8f7`,
the overall-score silver manifest SHA-256 is
`8c69aae0fdf171cec66633fbce604bffb2a394db8fdcbe62f32f058eb0c33f12`,
and the compact receipt SHA-256 is
`c7d3cf89325371af5f1ca1b9bbf32802fde0ef1cae81eca01d73f0864e5d7b4d`.
The 138 MB bootstrap ZIP was removed only after read-only verification; its
exact size and SHA remain bound in the receipt. Final fresh Sol verdict:
`SHIP`.

## Unresolved facts and review boundary

The old Google Drive label endpoint returned a sign-in/interstitial HTML
payload to unauthenticated probes, so no label archive hash is asserted here.
The full original-size archive hashes also require a parent-run bootstrap;
the observed content lengths alone are not trusted.  Repository metadata and
source-code hashes are pinned, but repository provenance is not a grant of
underlying image or derived-model redistribution rights. This package and
compact run are audited research inputs, not a shipping or release claim. The
full original-size and 11-attribute archives remain intentionally unpinned and
unused.
