# M3 EVA source adapter evidence

## Scope

This slice adds a source-specific, pinned EVA acquisition adapter. It targets
the official `kang-gnak/eva-dataset` repository at commit
`fb40a9f1abe4be96b69229aaac3d0838a2e1d31c`. The repository manifest records
exactly seven `EVA_together.zip.001` through `.007` segments, five data CSVs,
`readme.md`, and `LICENSE`, with the declared byte sizes and Git blob SHA-1
values.

The adapter writes only to a caller-selected data root outside this repository.
It uses a Python outer retry loop (12 attempts) around `curl`, with fixed pinned
raw URLs, `--fail --location --proto =https --proto-redir =https`, and
`--continue-at -` against a `.part` file. Curl-internal retry flags are
intentionally absent so each new invocation recomputes its resume offset from
the current partial file. Completed files are accepted only after exact-size and
Git blob SHA-1 verification, then atomically renamed. Segments are concatenated
in Python, the merged archive is
CRC-checked and extracted through a staging directory with traversal, symlink,
member-count, and uncompressed-size guards, and images are promoted atomically
when the destination is new. A pre-existing merged ZIP is never trusted: it is
deleted and rebuilt from the verified pinned segments. Existing images are
reused without archives only when a receipt matches the pinned source and the
recorded raw-manifest and inventory SHA-256 values still match; that path reruns
the current image scan and `verify-local`. Fixed `archives`, `data`, `docs`,
`receipts`, `images`, and staging paths reject symlink parents and final
directories, and receipts use a random `mkstemp` followed by an atomic rename.
With `--keep-archives`, archive-free receipt reuse is disallowed unless every
pinned segment is present and revalidated; the receipt records whether the
verified segment set is actually retained.

The output `raw-manifest.jsonl` intentionally contains only `image_id` and
data-root-relative `path` in this implementation. The original `votes.csv` and
`votes_filtered.csv` files are retained as upstream metadata and are not
presented as Camera Coach action labels. `inventory.jsonl` is produced by the
existing `camera_source_intake.py verify-local` command. Every receipt and
output is stamped `research_only`, `human_gold=false`, and
`release_admissible=false`; the repository's CC0 declaration does not resolve
the underlying AVA image rights.

## Changed files

- `datasets/camera-coach/v1/sources/eva-fb40a9f1.json` — immutable EVA source
  pins, sizes, Git blob SHA-1s, rights boundary, and raw-manifest contract.
- `tools/dataset/fetch_eva.py` — fixed-asset resumable downloader, safe archive
  handling, deterministic image manifest, intake alignment, receipt, cleanup,
  and network-free self-test.

## Narrow verification

Commands run from the repository root:

```text
$ python3 -m json.tool datasets/camera-coach/v1/sources/eva-fb40a9f1.json >/dev/null
PASS eva manifest segments=7 metadata=5 rights_boundary=true

$ python3 -m py_compile tools/dataset/fetch_eva.py

$ python3 tools/dataset/fetch_eva.py --self-test
PASS verify-local source_id=eva_official records=2 output_sha256=4380a34419e6ba737ec039b369574a353851cbfc7f5df9c710f44bb70d59592d
PASS verify-local source_id=eva_official records=2 output_sha256=4380a34419e6ba737ec039b369574a353851cbfc7f5df9c710f44bb70d59592d
PASS verify-local source_id=eva_official records=2 output_sha256=4380a34419e6ba737ec039b369574a353851cbfc7f5df9c710f44bb70d59592d
PASS verify-local source_id=eva_official records=2 output_sha256=4380a34419e6ba737ec039b369574a353851cbfc7f5df9c710f44bb70d59592d
PASS verify-local source_id=eva_official records=2 output_sha256=4380a34419e6ba737ec039b369574a353851cbfc7f5df9c710f44bb70d59592d
PASS fetch-eva source_id=eva_official records=2 keep_archives=false
PASS verify-local source_id=eva_official records=2 output_sha256=4380a34419e6ba737ec039b369574a353851cbfc7f5df9c710f44bb70d59592d
PASS verify-local source_id=eva_official records=2 output_sha256=4380a34419e6ba737ec039b369574a353851cbfc7f5df9c710f44bb70d59592d
PASS fetch-eva source_id=eva_official records=2 keep_archives=true
PASS fetch_eva self-test fake_curl pinned_resume outer_retry_resume proto_redir_no_internal_retry git_blob_sha1 safe_concat rebuilt_merge zip_crc traversal symlink deterministic_manifest verify_local receipt_reuse retention_gate archives_retained_truth stale_attestation safe_receipt_temp archive_dir_guard receipts_dir_guard cleanup repo_boundary

$ git diff --check -- datasets/camera-coach/v1/sources/eva-fb40a9f1.json tools/dataset/fetch_eva.py
PASS (no output)
```

The self-test injects a fake curl runner and never contacts the network. It
exercises partial-download resume and idempotence, an exit-18 outer-retry
resume simulation that preserves the observed offset, Git blob verification,
in-process concatenation, rejection and rebuild of a same-size valid but wrong
merged ZIP, ZIP CRC validation, traversal and symlink rejection, deterministic
JSONL bytes, receipt-gated archive-free reuse, stale/forged attestation
rejection, the `--keep-archives` retention gate and truthful receipt flag,
receipt temporary-path symlink resistance, fixed archive/receipt directory
guards, the existing `verify-local` boundary, archive cleanup while retaining
images/manifests/receipts, and repository-boundary rejection. The requested
750 MB EVA fetch is covered separately by the successful external acquisition
recorded below; this self-test remains network-free.

## Successful external acquisition

The pinned EVA acquisition completed into the external root
`/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/eva/fb40a9f1`.
Command:

```text
python3 tools/dataset/fetch_eva.py fetch --data-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/eva/fb40a9f1"
```

Observed output:

```text
PASS fetch-eva source_id=eva_official records=5101 keep_archives=false
```

The adapter reported `source_id=eva_official`, `records=5101`, and
`keep_archives=false`. The resulting root footprint was `747M`; its
`archives/` directory is empty and the receipt records `archives_retained=false`.
The raw manifest SHA-256 is
`6bf7f359663ada637cec5392084aebc9ffd8d468e93be9b57d36cc337f0c5243`, and the
inventory SHA-256 is
`9e19d308adf74cee833988f9b898dac555fed926351d881b203751df53c3f571`.

An independent invocation of `camera_source_intake.py verify-local` regenerated
the inventory byte-identically with the same
`9e19d308adf74cee833988f9b898dac555fed926351d881b203751df53c3f571` digest.
Its result was:

```text
PASS verify-local source_id=eva_official records=5101 output_sha256=9e19d308adf74cee833988f9b898dac555fed926351d881b203751df53c3f571
```

The first real run stopped after TLS errors with a partial segment preserved;
the rerun resumed from that `.part` file and completed successfully.

## Runtime observation and rights boundary

During the initial parent-run fetch, curl returned exit 18 after receiving
approximately 43.8 MB of a 99 MB segment. The adapter failed closed and
correctly retained the `.part` resume artifact. A later attempt showed curl's
internal retries reused the invocation's original offset, discarding progress
from that attempt; the partial was retained at 68,664,302 bytes when the parent
stopped safely. The Python outer retry loop now recomputes the offset from the
current `.part`, enabling the successful resumed run above.

This acquisition remains `research_only`, `human_gold=false`, and
`release_admissible=false`; the repository's CC0 declaration does not resolve
the underlying AVA image rights.

## Deliberate boundary

Vote/category aggregation is intentionally deferred from this routine adapter
slice. Adding it later should remain an allowlisted silver/reference metadata
projection and must not turn EVA preference votes into Camera Coach action
labels or release-cleared records.
