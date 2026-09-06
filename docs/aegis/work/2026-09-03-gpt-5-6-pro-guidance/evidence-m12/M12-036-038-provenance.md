# M12-036 / M12-037 / M12-038 — bundled asset provenance

Status: **closed on the current store**.

## M12-036 — fonts

`M12-036-font-provenance.json`: 5 bundled fonts with path/sha256/bytes,
family, in-file license basis, consumer (typography role), and decision.
Bebas Neue, JetBrains Mono, Oswald carry in-file OFL/copyright records;
PT Mono carries the full in-file SIL OFL text. Caveat carries no in-file
license record — its decision is `keep-with-source-verification-required`,
i.e. the upstream OFL family claim must be verified from source before
release; no license is invented here. All five are declared in
`UIAppFonts` and consumed by `SETTypography` roles; no unapproved font
required replacement, so no visual-authority drift exists.

## M12-037 — AppIcon/branding

`M12-037-brand-provenance.json`: AppIcon contents (both asset catalogs) and
the menu logo with hashes, marked in-house product-owner authorship,
decision `keep`. No public-name conflict check is applicable (no new public
name ships in this slice); owner approval is the product owner by
construction.

## M12-038 — USDZ/media

`M12-038-media-provenance.json`: `Person.usdz`, `Circle.usdz`, and the
`Circle.rcproject` bundle have no production Swift consumer
(grep-verified) — decision `exclude-from-release-bundle`; design textures
(`SETGrain`, `SETCameraFrame`) are consumed by the overlay/design system —
decision `keep`. No fixture/unknown asset is required for AR behavior, so
exclusion preserves required behavior by construction.
