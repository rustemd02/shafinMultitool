# Third-party notices and credits (draft)

Status: **draft for release review, not a substitute for legal clearance.**
This file is the human-readable acknowledgement set derived from
`docs/implementation/provenance/s07-component-inventory.json` and
`docs/implementation/provenance/release-component-status.json` on 2026-09-13.

Credits in this project mean **attribution of authorship and provenance only**.
They are not a virtual currency, not an in-app reward, and not a monetization
surface. No paid feature or StoreKit product is attached to this file.

An acknowledgement here does **not** clear redistribution rights. Components whose
rights decision is `owner_required` are listed with that status, not as approved.

## Bundled components requiring a notice

### llama.cpp / llama.xcframework — MIT

- Upstream: https://github.com/ggerganov/llama.cpp, commit `8f974d2392da4e6fa422a67050e90f1471d72966`.
- Vendored binary: `Frameworks/llama.xcframework` (MIT).
- Copyright (c) 2023-2024 The ggml authors / Georgi Gerganov and contributors.
- Full MIT text is preserved verbatim at
  `docs/implementation/third-party-notices/llama-cpp/LICENSE`
  (sha256 `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d`).
- Redistribution decision: **owner_approval_pending** (see the inventory record).

### SnapKit 5.7.1 — MIT

- Upstream: https://github.com/SnapKit/SnapKit at commit
  `2842e6e84e82eb9a8dac0100ca90d9444b0307f4` (tag/pod 5.7.1, spec checksum
  `d612e99e678a2d3b95bf60b0705ed0a35c03484a`). All 40 installed source files
  match that official commit; both installed lock files match the verified spec.
- Copyright (c) 2011-Present SnapKit Team - https://github.com/SnapKit.
- Complete unmodified notice: `third-party-notices/SnapKit-LICENSE.txt`, SHA256
  `7c0d21cf5314759fd35a22e42a52099d9cad2570db55a78e4eda26c82493b96b`.
  MIT permits app distribution with the notice preserved. The exact built app
  must contain these same bytes as `SnapKit-LICENSE.txt`; source-only notices
  cannot pass the release acknowledgement gate. See
  `docs/implementation/provenance/snapkit-admission.md` for proof and verification.
- MIT text (verbatim from `Pods/SnapKit/LICENSE`):

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### Fonts — SIL Open Font License 1.1

All five bundled fonts carry an OFL 1.1 license string and copyright in their
own `name` table (verified by parsing name IDs 0/13/14). OFL requires the
copyright notice and the license text to ship with the font.

| Font file | Copyright (from font) | License |
|---|---|---|
| `BebasNeue-Regular.ttf` (v2.000, sha256 `08e46238…c73`) | Copyright 2019 The Bebas Neue Project Authors (https://github.com/dharmatype/Bebas-Neue) | OFL-1.1 |
| `Caveat-Variable.ttf` (v2.000, sha256 `0bdb6b66…988`) | Copyright 2014 The Caveat Project Authors (https://github.com/googlefonts/caveat) | OFL-1.1 |
| `JetBrainsMono-Variable.ttf` (v2.211, sha256 `48715a42…eda`) | Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono) | OFL-1.1 |
| `Oswald-Variable.ttf` (v4.103, sha256 `5b38c246…817`) | Copyright 2016 The Oswald Project Authors (https://github.com/googlefonts/OswaldFont) | OFL-1.1 |
| `PTM55FT.ttf` / PT Mono (v1.001W, sha256 `cbe732b3…804`) | Copyright © 2010 ParaType Inc., ParaType Ltd.; Reserved Font Names "PT Sans", "PT Serif", "PT Mono", "ParaType" | OFL-1.1 |

The complete applicable OFL texts are already preserved beside the fonts in
`shafinMultitool/Resources/Fonts/`: `OFL-BebasNeue.txt`, `OFL-Caveat.txt`,
`OFL-JetBrainsMono.txt`, `OFL-Oswald.txt`, and `OFL-PTMono.txt`.
On 2026-09-16 every font and notice was downloaded from the immutable
`google/fonts@e1118da94a8cb00cf6d06cdac9ef13eb1e5c6ab7` distribution and matched
the existing repository bytes exactly. The unmodified fonts are admitted for
app bundling under OFL-1.1 with these preserved notices; the release validator
also checks the exact font and notice bytes in the supplied built app.

The Bebas Neue notice retains the upstream 2010 Dharma Type statement alongside
the font's 2019 project authorship. The PT Mono notice retains upstream 2011
ParaType copyright alongside the font's 2010 metadata. Both pairs occur in the
same pinned upstream distribution; neither was rewritten to make the years agree.
See `docs/implementation/provenance/font-admission.md` and the hash-bound
`font-provenance.json` in that folder. The [official OFL text](https://openfontlicense.org/open-font-license-official-text/)
and [SIL's mobile-app guidance, FAQ 1.20](https://openfontlicense.org/ofl-faq/)
describe the applicable conditions.

## Bundled components with an UNKNOWN or owner-required rights decision

These are recorded honestly and are **not** covered by the acknowledgements above:

- `DETRResnet50SemanticSegmentationF16P8.mlpackage` — embedded string says Apache-2.0 and names
  `facebook/detr-resnet-50-panoptic`, but product/redistribution approval is `owner_required`.
- `aesthetic_nima_mobilenet_fp16.mlpackage` — no author, license, checkpoint or source;
  `owner_required`, must not be declared provenance-cleared.
- `Circle.usdz`, `Person.usdz` — creator/redistribution evidence missing.
- `Resources/Assets.xcassets`, `Multitool2Module/Assets.xcassets` — branding/AppIcon authorship not recorded.
- `SETCompositionNet-Stage2-Local.mlpackage` — research-only artifact, currently unregistered and
  release-blocking until it is excluded or formally registered.

## Not bundled (excluded from the app target)

`Resources/Models/*.gguf`, `Resources/Textures/SETGrain.png`,
`Resources/Circle.rcproject`, `Resources/DeviceBenchmark`, `Resources/Fixtures`.
No notice is required while they remain excluded, but their rights records are still
unresolved in the inventory.
