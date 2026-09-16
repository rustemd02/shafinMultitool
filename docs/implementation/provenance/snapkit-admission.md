# SnapKit 5.7.1 source admission and shipped notice

Verified 2026-09-16. Owner: M12-039. This record supersedes only the SnapKit
source-provenance uncertainty in the historical 2026-09-13 S07 inventory.
That inventory remains an unchanged snapshot of its original inspection.

The installed SnapKit source is admitted under the upstream MIT license with
the complete copyright and permission notice preserved. The app distribution
condition is enforced separately against each supplied built app. A source-only
PASS cannot establish that the release artifact contains the notice.

## Source evidence

- `Podfile.lock` and `Pods/Manifest.lock` are byte-identical, 281 bytes, SHA256
  `6f57b660a78eecb4eeada8b5a259322ed3f1cc95812ecbdb7c8ea6c9851104f1`.
- Version and upstream tag: **5.7.1**. The official tag resolved to
  `2842e6e84e82eb9a8dac0100ca90d9444b0307f4`.
- The fetched [CocoaPods spec](https://raw.githubusercontent.com/CocoaPods/Specs/master/Specs/1/f/6/SnapKit/5.7.1/SnapKit.podspec.json)
  has raw SHA1 `d612e99e678a2d3b95bf60b0705ed0a35c03484a`, exactly matching
  the locked spec checksum. It declares `https://github.com/SnapKit/SnapKit.git`,
  tag `5.7.1`, MIT, `Sources/*.swift`, and the privacy resource bundle.
- All **40 installed files**—37 Swift sources, privacy manifest, README and
  LICENSE—match the corresponding Git blob identifiers in the
  [official immutable commit tree](https://api.github.com/repos/SnapKit/SnapKit/git/trees/2842e6e84e82eb9a8dac0100ca90d9444b0307f4?recursive=1).
  The independent SHA256 tree aggregate is
  `c2a33a0c5b5c9de280f15ff41ef4b7516afa8bf1cafe0536c3de1fdf5354a294`.
  Its exact construction is recorded in `snapkit-provenance.json`.
- The [complete upstream LICENSE](https://raw.githubusercontent.com/SnapKit/SnapKit/2842e6e84e82eb9a8dac0100ca90d9444b0307f4/LICENSE)
  is 1,093 bytes, SHA256
  `7c0d21cf5314759fd35a22e42a52099d9cad2570db55a78e4eda26c82493b96b`.
  `Pods/SnapKit/LICENSE` and the tracked
  `third-party-notices/SnapKit-LICENSE.txt` preserve these exact bytes.

Public metadata/spec/license downloads used normal TLS verification. The raw
verification receipt is outside Git at
`../setos-backend/local-data/SETOS/verification/snapkit-upstream-20260916T132021Z-2vk5jxu6/snapkit-upstream-inventory.json`,
SHA256 `d555b450e86340f30cc7fbfe19e2af23b8594846c62c324149b18835b99e7e50`.
It retains the installed per-file hashes, Git blob comparison and fetch details.
The summary beside it is `snapkit-provenance-summary.json`, SHA256
`7fbf8ca15b3ce148bac73e4cdd347566e861b9147d7c4f036489c420179ca0fb`.

There is no local SnapKit Git checkout metadata or podspec. The lockfiles pin
version/tag and spec checksum; they do not pin a source commit. The offline gate
therefore rehashes the entire small installed source tree. A same-version source
replacement, an extra file, a symlink or a moved upstream tag cannot pass by name.
An intentional dependency update requires a fresh provenance record.

## Notice packaging correction

The CocoaPods app-target acknowledgement plist contains exactly one SnapKit
entry. Its `FooterText`, after plist decoding and UTF-8 encoding, equals the
complete upstream license bytes without normalization. The Markdown also
contains that exact notice. The validator checks both conditions.

The prior release script merely searched the app for a Settings bundle or
Acknowledgements plist and printed a source-proof fallback when neither existed.
It still passed. The generated CocoaPods files were only project references,
not copied app resources, so that result did not prove distribution compliance.

The gate now requires **`SnapKit-LICENSE.txt` at the built app root**, with exact
upstream bytes. Missing, truncated or symlinked notices fail. A CocoaPods name or
an unrelated Settings bundle cannot substitute. The resource is intended at
`shafinMultitool/Resources/Legal/SnapKit-LICENSE.txt`; the synchronized app group
copies the text file to the root. Actual bundle placement must be checked on the
new Release build; no source-config inference closes that check.

At this package's initial verification the app source was frozen for the root
build checkpoint. The resource addition was prepared as an external
`snapkit-app-notice.patch`, alongside the checks receipt, for application after
that freeze. After the root released the freeze, the resource was added on
2026-09-16 at 13:34 UTC and its 1,093 bytes matched both verified license copies.
`snapkit-admission-checks-20260916-7j0vfae4/notice-source-integration.json` records
that source integration. The actual built-app check remains separate and open.

## Reproduction and limits

```sh
python3 -B scripts/validate_release_component_status.py --repo-root . --snapkit-only
python3 -B scripts/validate_release_component_status.py --repo-root . --snapkit-only --app /absolute/path/shafinMultitool.app
python3 -B -m pytest -q scripts/tests/test_validate_release_component_status.py -p no:cacheprovider
```

The scoped command reports source or bundle explicitly and never emits the
whole-release zero-blocker metric. `validate_release_bundle.sh` invokes the
bundle form and fails before a missing notice can be reported as a PASS. Full
component status also verifies this proof for the approved SnapKit component.

This approval covers the exact SnapKit source and MIT notice. It does not prove
which source produced an arbitrary Mach-O binary, a successful app build, a
physical-device result, or admission of any other component. Release build and
source-snapshot receipts, framework/privacy checks and remaining material
provenance gates retain their own criteria.
