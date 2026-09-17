# Release localization source-to-bundle integrity

Verified 2026-09-16. This is a localization integrity check, not an approval of
component rights, translation quality, privacy policy, UI layout or release
readiness. The ten existing component-disposition blockers remain unchanged.

## Problem and implementation

The previous bundle gate required four localization files to exist. An older
archive could satisfy that condition while omitting newer recording, consent
and privacy strings. The preserved archive below contains 526 Localizable
keys per language, while the current source contains 615.

`scripts/validate_release_localizations.py` is now called by stage 5 of
`scripts/validate_release_bundle.sh`. It owns the two application string tables:

- `shafinMultitool/Resources/InfoPlist.xcstrings`
- `shafinMultitool/Resources/Localizable.xcstrings`

The helper reads exact source snapshots and records their SHA-256 values, then
compiles the snapshots with the installed Xcode `xcstringstool`, retaining its
default `stringsAndStringsdict` product format. Binary serialization is used
for expected products. All declared languages are compiled; unexpected source
locales are rejected rather than hidden by a compiler language filter.

The required product scope is EN/RU with source language EN. Both catalogs must
be nonempty, and each must produce nonempty dictionaries for both languages.
Compiler exit zero with zero products is a failure. Unsupported compiler
products, duplicate JSON keys, compiler failures and unavailable tools fail the
check.

Expected and actual `.strings` and `.stringsdict` files are compared as typed,
recursive property-list dictionaries, including every plural rule and format
substitution. Foundation `plutil` parses a temporary copy when an actual file
uses a text/OpenStep serialization that `plistlib` cannot decode directly. No
conversion is performed on the supplied app. Missing and extra products,
locales, keys or changed values fail. Stray tables at app root or nested inside
an application locale also fail. Other tables and resources inside nested
frameworks/bundles remain with their existing owners. Base storyboard resources
are allowed; these two tables in Base are unexpected products.

Both original source bytes and the app table inventory/bytes are read again at
the end. A concurrent change fails validation. The compiler path/hash and source
hashes are printed in the validation log. Semantic equality does not assert
that an entire archive was built from current source bytes: archive build
identity, full source fingerprints and rights admission remain separate gates.

## Xcode semantics retained

The real compiler probe and regression fixture establish that:

- A source-English value without Russian localization is omitted from the
  Russian compiled table; the helper does not add an English fallback entry.
- Implicit entries and untranslated entries without localized values can be
  omitted entirely. A catalog containing only these can compile successfully
  without producing any files, which this gate rejects for required coverage.
- Explicit empty values and non-final translation states can still compile.
  Correspondence with compiler output does not approve the quality of such text.
- Plural and named-substitution entries can live only in `.stringsdict`.
  Xcode can normalize substitution format syntax, for example from
  `%#@count@` to `%1$#@count@`; the compiled representation is compared in full.
- Text and binary serialization can differ in bytes while carrying identical
  dictionaries. File hashes identify the artifacts; typed dictionary equality
  is the semantic acceptance criterion.

## Verification and evidence

Authoritative local evidence directory:

`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/localization-gate-implementation-20260916-ftox104k/`

`final-receipt.json` SHA-256:
`01e58a3e0289b0503732e81596eec460bab620cce9e50776c975dbc21ca0f6a5`.

The receipt binds implementation hashes, commands, return codes, logs, current
catalog hashes and the before/after archive inventory.

| Check | Result | Evidence |
|---|---|---|
| Real-Xcode helper suite | 33 tests, 0 failures, 0 skipped, 1.588 seconds; exit 0 | `unit-tests-final.log` |
| Shell syntax | Both changed shell scripts parse; exit 0 | `shell-syntax.log` |
| Preserved archive, helper | Expected rejection: 89 missing EN keys and 89 missing RU keys; exit 1 | `old-archive-helper.log` |
| Preserved archive, enclosing bundle validator | Same localization mismatch propagated at stage 5; exit 1 | `old-archive-wrapper.log` |
| Current catalog products | Localization-only fixture passes; exit 0, not a built-app claim | `current-localization-fixture.log` |
| Archive preservation | All 41 file hashes, sizes and modification timestamps unchanged | `final-receipt.json` |

The helper tests cover missing, extra and renamed locales; missing/extra/changed
keys and types; empty and malformed source/product data; stale and misplaced
tables; changed plural rules and substitution formats; compiler rejection;
fallback omission; text/binary semantic parity; symlinks; source/app mutation;
and CLI failure propagation, including malformed XML without an uncaught
traceback. The suite needs macOS/Xcode; skipped tests on another platform are
not evidence of executed compiler checks.

Preserved archive:

`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-execution-20260916/20260916T152044616359Z-release-archive/SETOS.xcarchive`

Catalog identities used by this verification:

| Source | SHA-256 |
|---|---|
| InfoPlist.xcstrings | `988ebbc39b369d497a7f89ae4da7704ef4ffedb2f4020569bb8bec01585ebb5b` |
| Localizable.xcstrings | `5bb70a08ac013ed759cf6a6a31a4e3aeba7e3a3ef4e1d5170fefd4ab14f69511` |

Run the focused suite from the repository:

```sh
python3 -B -m unittest discover -s scripts/tests -p test_validate_release_localizations.py -v
```

Run the helper against an actual app using explicit absolute paths:

```sh
python3 -B scripts/validate_release_localizations.py \
  --repo-root /Users/unterlantas/Documents/XCode/shafinMultitool \
  --app /absolute/path/to/shafinMultitool.app
```

After a fresh archive is built from current tested source, run the existing
`scripts/tests/test_release_bundle_gate.sh --release-app /absolute/path/to/shafinMultitool.app`.
It now requires localization equality before accepting the known-blocked clean
fixture and adds a changed-Russian-display-name rejection, for twelve negative
fixtures total. That full fresh-archive fixture run was not performed in this
localization packet; the older archive intentionally fails its clean baseline.
