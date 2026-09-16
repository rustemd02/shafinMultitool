# M3 — Wikimedia Commons rights-first adapter

## Scope and boundary

This slice adds a fixed-category Wikimedia Commons adapter for Camera Coach.
It is an acquisition boundary only: it does not create human gold, action
labels, personality/likeness consent, or release clearance. Raw media and all
generated receipts stay below a caller-selected external data root.

The tracked spec uses only direct namespace-6 file members, no search, and no
category recursion. Quotas are deterministic largest-remainder allocations:

| bucket | fixed category | target |
| --- | --- | ---: |
| people | `Category:Portraits` | 25% |
| landscape | `Category:Landscape photography` | 20% |
| architecture_streets | `Category:Architecture` | 20% |
| interiors | `Category:Interiors` | 15% |
| objects_details | `Category:Quality images of objects` | 15% |
| historical_cinematic | `Category:Black and white photographs` | 5% |

Before member discovery, the adapter queries `prop=categoryinfo` and records
the current direct-file capacity. A non-zero target shortfall is durable as
`status=PARTIAL` and returns exit code 2; it is never printed as `PASS` or
filled from another bucket.

## Rights and media handling

The spec's `accepted_tuples` is checked against the adapter's frozen policy
owner. Classification accepts only the exact trimmed, case-sensitive
machine/license tokens and normalized URLs below:

* `cc0` + `CC0 1.0` +
  `https://creativecommons.org/publicdomain/zero/1.0`, with no attribution or
  restrictions;
* `cc-by-4.0` + `CC BY 4.0` +
  `https://creativecommons.org/licenses/by/4.0`,
  `AttributionRequired=true`, and non-empty plain-text `Artist`;
* `pd` + `Public domain` + `Copyrighted=false` +
  `AttributionRequired=false` + empty `Restrictions`.

CC BY-SA, GFDL, old, multiple, unknown, malformed, and missing tuples are
quarantined. Raw extmetadata, including HTML `Artist` and `Credit`, is
preserved; plain-text forms are derived separately. Every API response used
for category capacity, member discovery, or imageinfo is represented by a
canonical SHA-256 in the durable receipt; row-level response hashes are also
preserved.

Thumbnails request width 1600, with no height cap. The tracked pixel ceiling
is 16,000,000 and is checked from image headers before Pillow loads pixels.
Downloaded dimensions must equal API `thumbwidth`/`thumbheight`, and decoded
MIME must equal canonical `thumbmime` (Commons responses that omit `thumbmime`
use the response's allowlisted bitmap MIME as that canonical thumbnail MIME).
One Commons API edge case is explicit: when the validated thumbnail URL has
`utm_content=thumbnail_unscaled` and exactly the same media path as the
original URL, the expected byte dimensions are the original API `width`/
`height`; this expectation and its source are persisted in both candidate and
rights-receipt rows and checked again by `verify-local`. A second explicit
Commons CDN edge case is a final path segment matching `/<N>px-<filename>`:
the expected byte width is the positive bucket `N`, and the expected height is
the original `width`/`height` aspect-ratio projection with a one-pixel integer
rounding tolerance. Bucket, display, source, and tolerance fields are
persisted and re-derived during verification; arbitrary dimensions are not
accepted. JPEG, PNG, and WebP only; byte ceiling is 8,000,000. Downloads use safe
relative paths, stale `.part` cleanup, bounded retry, a 206 `Content-Range`
start check, local SHA-256, duplicate rejection, and atomic promotion. API
and media requests are HTTPS-only, host allowlisted, redirect-rejecting,
rate-limited to about one request per second, and carry a descriptive
User-Agent/contact with `maxlag=5`. Top-level MediaWiki `maxlag` errors retry
within the same bounded retry budget.

For download mode, ordered rights-valid candidates beyond each quota remain
available for same-category media backfill. Receipt category records include
`attempted`, `rejected`, and `backfilled`; `backfilled` counts only successful
candidate indexes at or beyond the original target window. Metadata-only mode
selects only the first target candidates. Reuse requires an existing receipt with the same
spec, limit, and mode plus matching candidate/quarantine hashes/counts and
persisted discovery-response hashes. A completed run root rejects mode,
spec, or limit changes; local hash reuse is additionally bound to the
candidate thumbnail URL/API response/metadata hash.

`raw-manifest.jsonl` contains only `image_id` and safe relative `path`, so it
is consumable by the existing `camera_source_intake.py` verifier. Rights
provenance remains in `accepted-rights-receipt.jsonl`. Every accepted row is
`research_only=true`, `human_gold=false`, and `release_admissible=false`;
public-domain rows are only `clearance_candidate=true`, and verification
requires the top-level flag to equal recomputed rights classification.
JSONL records are delimited only by literal LF, matching the atomic writer;
the reader preserves Unicode separators inside JSON strings, accepts only a
terminal CR as explicit CRLF compatibility, and rejects other raw CR bytes.

## Changed files

* `tools/dataset/fetch_commons.py`
* `datasets/camera-coach/v1/sources/wikimedia-commons-v1.json`
* `datasets/camera-coach/v1/research-source-catalog.json` (Commons ingest,
  verify, and status fields only)

## Verification evidence

Commands run from the repository root:

```text
python3 -m py_compile tools/dataset/fetch_commons.py
python3 tools/dataset/fetch_commons.py --self-test
python3 -m json.tool datasets/camera-coach/v1/sources/wikimedia-commons-v1.json >/dev/null
python3 -m json.tool datasets/camera-coach/v1/research-source-catalog.json >/dev/null
git diff --check
```

Compile, JSON parsing, and diff checks passed. The network-free self-test
passed:

```text
PASS fetch_commons self-test accepted_cc0 accepted_cc_by accepted_pd reject_sa_unknown_missing unsafe_host redirect malformed_api retry_429 maxlag resume stale_part bad_content_range hash_mismatch duplicate oversized non_image symlink unscaled_dimensions bucket_dimensions unicode_jsonl deterministic e2e_receipt_verify
```

The self-test calls `_fetch` and `_verify_local` with a fake API/media opener,
invokes the existing intake verifier, produces a durable partial receipt, and
asserts actual duplicate-content rejection. It includes the exact
success/fail/success/success, target-three backfill sequence (one backfilled
success). It also exercises strict rights,
redirect/host rejection, malformed API data, HTTP 429 and top-level maxlag
retry, interrupted resume, stale partial cleanup, invalid `Content-Range`,
range end/total/length validation, hash mismatch, oversized/non-image media,
symlink guards, deterministic outputs, and exact receipt/output linkage.
`verify-local` checks the persisted inventory hash/count against the receipt
before running a read-only intake recomputation into a temporary output; the
canonical inventory file is unchanged.

The strict TDD regression fixtures were first added and run RED: the
`thumbnail_unscaled` fixture failed with exit 1 and
`KeyError: 'expected_download_width'`; the subsequent CDN-bucket fixture
failed with exit 1 because its expected dimensions were still the display
`1600x2843`. The adapter fixes were then added and run GREEN with the
self-test result shown above. The scale-parser fixture then failed RED with
`FAIL JSONL line 1 is malformed` (exit 1) for a record containing literal
U+2028/U+2029/NEL; the literal-LF reader fix made the same self-test GREEN.

Fresh live metadata-only probe (20 requested records):

```text
python3 tools/dataset/fetch_commons.py fetch \
  --spec datasets/camera-coach/v1/sources/wikimedia-commons-v1.json \
  --data-root /private/tmp/commons-meta20-fix.fPGEKT \
  --limit 20 --metadata-only
python3 tools/dataset/fetch_commons.py verify-local \
  --spec datasets/camera-coach/v1/sources/wikimedia-commons-v1.json \
  --data-root /private/tmp/commons-meta20-fix.fPGEKT
```

Observed statuses were `fetch exit=2` and `verify-local exit=2`, both explicit
`PARTIAL`:

```text
PARTIAL fetch-commons source_id=wikimedia_commons_api candidates=21 accepted_rights=15 downloaded=0 quarantined=145 metadata_only=true
PARTIAL verify-local source_id=wikimedia_commons_api records=0 output_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

The categoryinfo direct-file capacities observed in that run were:

| bucket | direct files | target | accepted | shortfall |
| --- | ---: | ---: | ---: | ---: |
| people | 14,042 | 5 | 5 | 0 |
| landscape | 918 | 4 | 3 | 1 |
| architecture_streets | 1,777 | 4 | 4 | 0 |
| interiors | 1,189 | 3 | 1 | 2 |
| objects_details | 4,036 | 3 | 1 | 2 |
| historical_cinematic | 29,816 | 1 | 1 | 0 |

The direct category capacities themselves are ample for this pilot; the
shortfall is rights/metadata supply in the bounded deterministic candidate
window. No substitution was performed. Receipt counts were:

```text
{"accepted_rights": 15, "attempted": 15, "backfilled": 0, "candidates": 21, "downloaded": 0, "quarantined": 145, "rejected": 0}
```

Output SHA-256 values and record counts:

```text
candidates.jsonl                         21  98b7e781b26a4532dffbf4acbf34aa91e1537ecccdaaf7a308e6c3aa425d4633
accepted-rights-receipt.jsonl            15  73358da92b6a2d3262fc841762f6d9b73e4fd3d227d7e89ac1a0a292cb90371e
quarantined.jsonl                       145  50d67c6abc28b8c7c80f5ad62f505b4fcfd2b488165f0c394c27afec01c97d8c
raw-manifest.jsonl                        0  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
inventory.jsonl                           0  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
receipts/commons-source-receipt.json      1  bd7d33301d32431b5cd74fdc57a3c2a21de3cfe52dca8b08fd67150d769131e3
```

The prior durable `v1-pilot-20` root is retained as diagnostic evidence and
must not be rerun. It recorded 21 media width mismatches and zero downloads;
pageid `175916788` was the reproduced case (`1400x875` bytes versus API
`thumbwidth=1600`, `thumbheight=1000`) with a `thumbnail_unscaled` URL.

After the RED/GREEN repair, the real download pilot used a fresh root because
the prior diagnostic root was not rerun:

```text
python3 tools/dataset/fetch_commons.py fetch \
  --spec datasets/camera-coach/v1/sources/wikimedia-commons-v1.json \
  --data-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/commons/v1-pilot-20-r2" \
  --limit 20
python3 tools/dataset/fetch_commons.py verify-local \
  --spec datasets/camera-coach/v1/sources/wikimedia-commons-v1.json \
  --data-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/commons/v1-pilot-20-r2"
```

The adapter fetch receipt recorded `PARTIAL`, `exit_code=2`, and:

```text
PARTIAL fetch-commons source_id=wikimedia_commons_api candidates=21 accepted_rights=8 downloaded=8 quarantined=152 metadata_only=false
PARTIAL verify-local source_id=wikimedia_commons_api records=8 output_sha256=fd95a1494f34d01aaae9d4fbd45c6292b49890cd36a88fdf7465e1c0a21be151
```

The verify command returned exit 2, as required for the recorded category
shortfalls. Current direct-file capacities in this repaired pilot receipt
remain people 14,042, landscape 918, architecture 1,777, interiors 1,189,
objects/details 4,036, and historical/cinematic 29,816. Accepted/downloaded
counts by bucket were people 5, landscape 1, architecture/streets 1,
interiors 1, objects/details 0, historical/cinematic 0; no substitution was
performed. The repaired page `175916788` row records
`expected_download_dimensions_source=original_unscaled`, expected `1400x875`,
and local `1400x875`.

Pilot receipt output SHA-256 values and record counts:

```text
candidates.jsonl                         21  1ebd680fb1a722fe443abb858e4b293dc707fdb118072c836d9bef07c5be8066
accepted-rights-receipt.jsonl             8  4ee206d482a310a4e75954e6a2749dd019ecbf61b86340d03c282e08650331b0
quarantined.jsonl                       152  1af88f6014b65d5ed5287c23ebf69afbc9e78ab08c49df6a9fa57e94078ebd67
raw-manifest.jsonl                        8  b8e9c01140432514566e3566eb80b27cef0d7512da857e6347c1c62796277ce4
inventory.jsonl                           8  fd95a1494f34d01aaae9d4fbd45c6292b49890cd36a88fdf7465e1c0a21be151
receipts/commons-source-receipt.json      1  aabf793c352e6a4f197b16db28f73276b8b3d818a02d073c2a7718c64366d67c
```

The pilot receipt totals were `candidates=21`, `accepted_rights=8`,
`downloaded=8`, `quarantined=152`, `attempted=15`, `rejected=7`, and
`backfilled=0`. The eight image bytes remain only under the external pilot
root; none are in Git.

The repaired r2 root was not rerun or mutated. A second live download pilot
used a new root for the responsive CDN-bucket fix:

```text
python3 tools/dataset/fetch_commons.py fetch \
  --spec datasets/camera-coach/v1/sources/wikimedia-commons-v1.json \
  --data-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/commons/v1-pilot-20-r3" \
  --limit 20
python3 tools/dataset/fetch_commons.py verify-local \
  --spec datasets/camera-coach/v1/sources/wikimedia-commons-v1.json \
  --data-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/commons/v1-pilot-20-r3"
```

The r3 adapter receipt recorded `PARTIAL`, `exit_code=2`, and 15 successful
downloads from 15 rights-valid attempts; the only shortfalls were bounded
category supply/rights candidates, not media dimension failures:

```text
PARTIAL fetch-commons source_id=wikimedia_commons_api candidates=21 accepted_rights=15 downloaded=15 quarantined=145 metadata_only=false
PARTIAL verify-local source_id=wikimedia_commons_api records=15 output_sha256=d1031df11d876693e43144f360cb670fe927ed6c22e1ff2d45b9939b842734e5
```

The r3 verify command returned exit 2 because landscape, interiors, and
objects/details remained short of their fixed targets. Current direct-file
capacities were people 14,042, landscape 918, architecture 1,777, interiors
1,189, objects/details 4,036, and historical/cinematic 29,816. Accepted counts
were people 5, landscape 3, architecture/streets 4, interiors 1,
objects/details 1, and historical/cinematic 1. The reproduced page
`190457903` records `expected_download_dimensions_source=thumbnail_bucket`,
bucket/display `1920x3412` / `1600x2843`, and local `1920x3412`; page
`175916788` continues to record the prior `original_unscaled` expectation.

R3 pilot receipt output SHA-256 values and record counts:

```text
candidates.jsonl                         21  05e8afa0118a1663d23ab4f1ce6ea3655692c90430532affc0c00bb808e535c5
accepted-rights-receipt.jsonl            15  78e73f4c41e7f7ed84ec423c5750a6f89725bfe23580dd14cc8ec9a888ff61c8
quarantined.jsonl                       145  1abdf8d1325c12f417be2fd3c557547e63c7be51fcd25d9268ceba4b6f9a918b
raw-manifest.jsonl                       15  9c49c119f3af962977ee988e384f47b944075ecd05aef0a596e129b41abac5fa
inventory.jsonl                          15  d1031df11d876693e43144f360cb670fe927ed6c22e1ff2d45b9939b842734e5
receipts/commons-source-receipt.json      1  3527534d8cad893b1673f9dd6e96a695a58d0315c184ce1db6a5ad982795c942
```

The r3 receipt totals were `candidates=21`, `accepted_rights=15`,
`downloaded=15`, `quarantined=145`, `attempted=15`, `rejected=0`, and
`backfilled=0`. Eight accepted rows used the explicit unscaled-original
expectation and seven used the explicit CDN-bucket expectation. All 15 image
bytes remain only in the external r3 root; none are in Git.

The first bounded scale run was already durable at the external root below;
it was not fetched or rewritten during this fix. Before the parser repair,
`verify-local` stopped at JSONL line 4836 even though that quarantined record
was valid JSON. The cause was `str.splitlines()` treating U+2028/U+2029/NEL
inside Commons HTML metadata strings as record delimiters. After the literal
LF parser repair, read-only verification covered all 767 downloaded records:

```text
python3 tools/dataset/fetch_commons.py verify-local \
  --spec datasets/camera-coach/v1/sources/wikimedia-commons-v1.json \
  --data-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/commons/v1-scale-1000"
```

Observed result was `verify-local exit=2`, an explicit category-supply
`PARTIAL` rather than a parser failure:

```text
PARTIAL verify-local source_id=wikimedia_commons_api records=767 output_sha256=4d200d26e3720cb3f44665469902befb35c32771a3641514f439f946f4045c0f
```

The scale receipt records `candidates=1199`, `accepted_rights=767`,
`downloaded=767`, `quarantined=6540`, `attempted=774`, `rejected=7`, and
`backfilled=7`, with `status=PARTIAL` and `exit_code=2`. Current direct-file
capacities and accepted counts were people 14,042/250, landscape 918/82,
architecture 1,777/200, interiors 1,189/144, objects/details 4,037/41, and
historical/cinematic 29,816/50. Fixed-category shortfalls remain explicit;
no category substitution was made.

Scale-root output SHA-256 values and record counts:

```text
candidates.jsonl                       1199  53ac0fa183f805d79af36b362b5114bd5b370b70e2e08e00aad1dda55dde8880
accepted-rights-receipt.jsonl           767  fcdb4f62d12737bf1182ea979534f83abdf006cf4ec4aa7c1431d789d4965a19
quarantined.jsonl                      6540  ccebda889f1be942f335c5ac8ad735aa3eeebfd896cdbd21c40e54b5707364e5
raw-manifest.jsonl                      767  414002e13b3347566f81964f796465ca10d787115abd8dd944e81ca7741c8b0d
inventory.jsonl                         767  4d200d26e3720cb3f44665469902befb35c32771a3641514f439f946f4045c0f
receipts/commons-source-receipt.json      1  9f0f1c6d72a2294a4b27c11b5a589f29903e1b2f3d1a35e5921e73598fc5ce33
```

All 767 image bytes remain outside Git under the durable scale root; the
adapter still makes no human-gold, personality-release, or release-clearance
claim.

## Honest limitations

This package proves deterministic, rights-first acquisition and provenance
bookkeeping only. It does not prove human gold, Camera Coach action labels,
subject/scene semantics, person consent, personality/likeness release, or
redistribution clearance. A future 1,000–3,000 scale-up must rerun against
current Commons responses, preserve receipts outside Git, audit shortfalls and
duplicate families, and obtain legal/personality review before release use.
