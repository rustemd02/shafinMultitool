# M12-036 — exact font and OFL admission, 2026-09-16

The five existing font binaries and their five full OFL notices match the
immutable `google/fonts@e1118da94a8cb00cf6d06cdac9ef13eb1e5c6ab7` distribution
byte-for-byte. They are admitted for **unmodified font bundling within SET OS
under OFL-1.1 with preserved copyright and license information**. This resolves
their source/license provenance blocker without replacing fonts or requesting
an additional agreement from the owner.

The decision applies to these exact bytes and use. The [official OFL 1.1 text](https://openfontlicense.org/open-font-license-official-text/)
permits software bundling under its conditions. [SIL's FAQ](https://openfontlicense.org/ofl-faq/)
sections 1.3, 1.4 and 1.20 address proprietary software, commercial bundles and
mobile apps, including retention of applicable copyright and license material.
The fonts keep their own OFL license; authorship credit does not imply endorsement.
No font is sold independently or modified by this change.

## Exact source verification

The existing font pin was recovered from `docs/implementation/ux/set-os-visual-policy.md`
§4.1, then independently checked against actual upstream downloads and local
bytes. All ten requests returned HTTP 200 using ordinary TLS certificate
verification (`curl_ssl_verify_result=0`); all ten byte comparisons passed.
The raw URLs are `https://raw.githubusercontent.com/google/fonts/` followed by
the commit above and these paths (square brackets URL-encoded in requests):

| Bundle font | Version from binary | Upstream path | Bundled full notice |
|---|---|---|---|
| BebasNeue-Regular.ttf | 2.000 | ofl/bebasneue/BebasNeue-Regular.ttf | OFL-BebasNeue.txt |
| Caveat-Variable.ttf | 2.000 | ofl/caveat/Caveat[wght].ttf | OFL-Caveat.txt |
| JetBrainsMono-Variable.ttf | 2.211 | ofl/jetbrainsmono/JetBrainsMono[wght].ttf | OFL-JetBrainsMono.txt |
| Oswald-Variable.ttf | 4.103; gftools[0.9.33.dev8+g029e19f] | ofl/oswald/Oswald[wght].ttf | OFL-Oswald.txt |
| PTM55FT.ttf | 1.001W OFL | ofl/ptmono/PTM55FT.ttf | OFL-PTMono.txt |

Each matching upstream notice is the adjacent `OFL.txt`. Full binary and notice
SHA256 values, source/bundle paths and upstream paths are in `font-provenance.json`.
The complete acquisition receipt, public upstream files and embedded metadata
are retained outside Git:

`../setos-backend/local-data/SETOS/verification/font-upstream-20260916T130200Z-aeeeczkd/`

- `font-upstream-comparison.json`, SHA256
  `2e9642800cbddfa397d3c00627ce882168fcb57cba302a05e554f1b8c98b5238`.
- `font-upstream-verification-summary.json`, SHA256
  `eea6aa34cb59a770a49d74467d41e6b5b1bb7014253628efd5de76829c865663`.

## Correction of earlier evidence

The historical `evidence-m12/M12-036-font-provenance.json` claimed Caveat had no
embedded license. The same binary SHA contains Windows Unicode name IDs 0, 13
and 14 (platform 3, encoding 1, language 0x409, UTF-16BE), including its OFL 1.1
statement. Current parsing and exact upstream comparison supersede that claim;
the historical receipt is preserved. The former statement in the current
`third-party-notices/NOTICES.md` that full OFL texts were missing was also stale:
all five existing texts match their pinned upstream counterparts.

Bebas Neue's binary says 2019 project authors while its OFL file says 2010 Dharma
Type. PT Mono's binary and embedded license say 2010 while its OFL file says
2011 ParaType. Both differences occur in the pinned upstream release. All
statements, including PT Mono's reserved names, remain intact; their historical
cause is not inferred and no copyright text has been edited.

## Release enforcement and scope

The five font entries in `release-component-status.json` are `APPROVED` for the
use above. That state requires a matching entry in `font-provenance.json`.
`validate_release_component_status.py` checks exact font and full-notice SHA256,
all declared `UIAppFonts`, missing/symlinked files, and—when `--app` is provided—the
font and notice files in that exact built app. Missing notices or changed font
bytes fail even if filenames and the status flag remain unchanged. The existing
Release bundle gate already calls this component validator.

```bash
python3 -B scripts/validate_release_component_status.py --repo-root . --fonts-only
python3 -B scripts/validate_release_component_status.py --repo-root . --fonts-only --app /path/to/shafinMultitool.app
```

`--fonts-only` is a scoped check and never emits a zero count for unrelated
release blockers. Source verification does not prove notice packaging in a
future archive; each supplied Release app must pass its own check. Runtime
font loading, RU/EN glyph coverage, accessibility, typography and other assets
remain separate gates. This change does not alter app resources, Info.plist,
font binaries or notice bytes, and it does not declare the whole app releasable.
