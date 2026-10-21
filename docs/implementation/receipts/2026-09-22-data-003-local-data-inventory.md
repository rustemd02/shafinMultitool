# DATA-003 — текущий relocated local-data inventory receipt

Date: 2026-09-22. Mode: **read-only**. No file under the canonical data tree or historical relocation receipt was deleted, moved, rewritten, normalized, or had its mtime touched by this inventory.

Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`).
Canonical root: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS`.
Historical relocation evidence: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/relocation-20260916.json` (SHA-256 `5720bff8b81ec7ecf2468dd8d57c4efe455130d6aeb93b68a852b3ab28f8371e`).

## Current totals

Current walk found **149,849 regular files**, **39,467,986,588 logical bytes**, and **76 symlinks**. Full SHA-256 was computed for **18 checkpoint/model binaries (220,722,688 bytes)**. The 46 rows below are meaningful dataset/model/checkpoint/manifest/evidence families; `<root-files>` is a reporting group for files directly under that parent and is not a created directory.

| top-level | families | regular files | logical bytes | symlinks |
|---|---:|---:|---:|---:|
| `Datasets` | 26 | 148,981 | 39,440,847,929 | 3 |
| `annotation` | 8 | 642 | 23,684,930 | 73 |
| `inventory` | 1 | 1 | 109,305 | 0 |
| `snapshots` | 10 | 188 | 3,137,695 | 0 |
| `verification` | 1 | 37 | 206,729 | 0 |

## Family inventory

Hash columns: `metadata_sha256` is a deterministic aggregate over sorted canonical relative path + logical size + per-file digest of sorted declared content hashes found in metadata + full SHA-256 of bounded checkpoint/model binaries. `M` is the number of manifest/receipt-like files whose own SHA-256 was recomputed (text metadata ≤256 MiB); `D` is the number of metadata files with one or more declared content hashes; `C` is the number of checkpoint/model binaries full-hashed; `L` is the symlink count. Raw media was not full-content hashed.

| canonical family path | kind | files | bytes | metadata_sha256 | M/D/C/L | rights/admission tier | label tier | provenance |
|---|---|---:|---:|---|---:|---|---|---|
| `Datasets/camera-coach/research/aadb` | raw dataset | 9438 | 140175342 | `239887e02b8bb1ce19b48d088c75f1aa60d003a16d4913ebd3fcb6b3d44a671d` | 4/2/0/0 | R1 · per-record; no family licence | silver/research · human_gold=false | AADB silver-manifest.jsonl |
| `Datasets/camera-coach/research/ava` | raw dataset | 16814 | 866739864 | `06db2f1276eed6873dd3e8b064ca7ac93ec0aeb5c9ec7a740e7156aec9a6d634` | 4/2/0/0 | R1 · AVA research/no redistribution | silver/research · human_gold=false | AVA legacy-silver inventory.jsonl |
| `Datasets/camera-coach/research/bundles` | derived bundle | 1 | 6148 | `1d78cb46f53d4b8b60ffb869b337e6bb32cd55691614636b9304ffb8fce20158` | 0/0/0/0 | R3 · inherited source rights | unlabeled derived evidence | research bundle receipt |
| `Datasets/camera-coach/research/cinematic` | raw/derived dataset | 7116 | 2553465503 | `23d9995d0aae842b129c6d35fa1c717841cfc2ca229166859950a1c5afc7e2da` | 12/11/0/0 | R2 · CC-BY Blender; attribution/no redistribution | silver/unlabeled · human_gold=false | Blender Open Movies receipts + manifest |
| `Datasets/camera-coach/research/commons` | raw dataset | 794 | 559253248 | `53b0cc5581c43ca13c39c9a17dc3327db7d37100978d3f5f1b558eb8f44244c0` | 8/8/0/0 | R2 · per-file Wikimedia rights | silver/unlabeled · human_gold=false | Wikimedia API candidates/accepted-rights receipts |
| `Datasets/camera-coach/research/edge-controls` | derived eval | 427 | 94866889 | `34a445002fde7e87d89ea2287bee815676b1f65311f2394649d94e37809f651b` | 7/4/0/0 | R3 · inherited research rights | unlabeled derived evidence | edge-control run receipts |
| `Datasets/camera-coach/research/eva` | raw dataset | 5113 | 776815865 | `df3181477cfdc9c119dc563cfcc6842913772e5eb4434d471b658705c76a0cfa` | 5/4/0/0 | R1 · per-record; no family licence | silver/research · human_gold=false | EVA silver-manifest.jsonl |
| `Datasets/camera-coach/research/geometry` | derived eval | 6 | 34363656 | `d4f1d88c5710891d66b5200e93558f3ad991c53976baeb53b20d3d8677e5931f` | 3/6/0/0 | R3 · inherited research rights | unlabeled derived evidence | camera geometry receipts |
| `Datasets/camera-coach/research/lighting` | raw dataset | 41 | 27683222 | `211282dac46c4a71f3b3c7c8718827b959412eac613d8419ca6ea5f18966ea0d` | 2/18/0/0 | R2 · Poly Haven CC0; API terms retained | silver/unlabeled · human_gold=false | Poly Haven assets/terms receipts |
| `Datasets/camera-coach/research/open-images-lamp-pilot-20260911.4PMfRR` | raw/derived pilot | 12 | 52448370 | `a3282330536e9e8710f77369387810e924c247249c6415e89d4049d4d16ecc1f` | 6/2/1/0 | R1 · per-record; admission not established | silver/unlabeled · human_gold=false | Open Images source/detr receipts |
| `Datasets/camera-coach/research/paired-corruptions` | derived dataset | 5603 | 1199368777 | `e9b8daee12c510078210e4a40bca6d9a0183e06ef083da1e699caffa30df4b81` | 3/6/0/0 | R3 · inherits AADB/EVA/Commons rights | silver derived · human_gold=false | camera-silver-action-pair receipts |
| `Datasets/camera-coach/research/photography` | raw dataset | 2119 | 4173398858 | `4f0c21720671b3619a513331bb9534df10d16908f4f8c98040505e10aee2c44c` | 8/8/0/0 | R2/R1 · mixed per-record; OpenImages intake blocked | silver/unlabeled · human_gold=false | Commons/OpenImages intake manifests |
| `Datasets/camera-coach/research/runs` | checkpoint/eval | 16 | 181669497 | `74dd6a4f3b15dd33ee835282bc6631e66ff9f7d1d70bbb7faa4e401db3a3aae0` | 2/2/12/0 | R3 · research-only run receipts | unlabeled model artifact · human_gold=false | stage1/stage2 checkpoint receipts |
| `Datasets/camera-coach/research/synthetic` | derived dataset | 2261 | 7069987760 | `1755c868a198d594f7301dc8f469e6655991adbaf777ae70a478ee6891a08b49` | 4/4/0/0 | R2 · SceneTrans CC-BY-4.0 note | silver derived · human_gold=false | SceneTrans pair receipts |
| `Datasets/camera-coach/research/temporal` | raw/derived temporal | 10000 | 2643802205 | `0addefdd5e6f774a62f1965f55edba7b3093a080b65aea7ceea35d4b2b13f12f` | 8/5/0/0 | R2/R1 · per-video rights policy | silver/unlabeled · human_gold=false | LaSiesta/TAP-Vid receipts |
| `Datasets/camera-coach/research/vlm-polza` | eval/proposal | 68 | 497681 | `1caccf4d98b524bbd4e6921ea2395e830eb3eb11ff7d6107c7d8f4927ebd3e6e` | 18/1/0/0 | R1 · research-only; rights not established | unlabeled proposal · human_gold=false | VLM strict manifest |
| `Datasets/camera-coach/research/webresearch-2026-09-14` | mixed package/eval | 13788 | 1685997317 | `8e94266a7a4771b1316459d169e1139cece00faad9937eb8079ae1dcff816e53` | 31/12/0/3 | R1/R2 · per-source receipts; no release admission | silver/unlabeled · human_gold=false | webresearch package receipts |
| `Datasets/camera-coach/research/<root-files>` | manifest/metadata | 1 | 6148 | `c4f468c1ded6234ef40a58ed0bdfbb2d32f51107c48148941efe4d0aab46d474` | 0/0/0/0 | R6 · metadata only | n/a | root .DS_Store (not a dataset) |
| `Datasets/camera-coach/colab_package` | package | 6327 | 779543639 | `d8486df9f75032d44005c8e11d3c869839ab4e82d24e0b81f850bb6c90e2f23d` | 20/19/0/0 | R4 · research_only; inherited source receipts | silver/unlabeled · human_gold=false | Colab/package receipt + source manifests |
| `Datasets/camera-coach/colab_package_v2_20260914` | package | 12259 | 3343445050 | `76af619b8c12582c09808d68c9892939dd2de2314752f8000663cc02ba950098` | 37/32/0/0 | R4 · research_only; inherited source receipts | silver/unlabeled · human_gold=false | Colab/package receipt + source manifests |
| `Datasets/camera-coach/colab_package_v2_20260914_attempt1_frame_name_collision_preserved` | package | 8311 | 1439858973 | `3fd30add98fa5d80c1b28410d57e596392e9f506b519b9b50d9ddf1da597ceb0` | 36/31/0/0 | R4 · research_only; inherited source receipts | silver/unlabeled · human_gold=false | Colab/package receipt + source manifests |
| `Datasets/camera-coach/colab_package_v2_20260914_attempt2_paired_dedup_preserved` | package | 11723 | 2699875549 | `97e00b0591f0fcc52ab3a0bebf9010ac8a49871020674bb3681bc569a5e848fd` | 36/32/0/0 | R4 · research_only; inherited source receipts | silver/unlabeled · human_gold=false | Colab/package receipt + source manifests |
| `Datasets/camera-coach/colab_package_v2_20260914_attempt3_sequence_qc_preserved` | package | 11803 | 2797448735 | `74991a5fee3fc5e7bbbd404d7c38226c69dbcf832bcea08a8cd3f17e6d6945db` | 36/32/0/0 | R4 · research_only; inherited source receipts | silver/unlabeled · human_gold=false | Colab/package receipt + source manifests |
| `Datasets/camera-coach/colab_package_v2_20260914_attempt4_temporal_dedup_preserved` | package | 11803 | 2797449058 | `730eb7b917cdab4da2fe2328c58793cf55848cfc1116901c65a21489ff11f000` | 36/32/0/0 | R4 · research_only; inherited source receipts | silver/unlabeled · human_gold=false | Colab/package receipt + source manifests |
| `Datasets/camera-coach/colab_package_v2_20260914_attempt5_scenetrans_id_collision_preserved` | package | 11805 | 2798063465 | `5858280ee118ae02f8e9c3868c17425c0be47f07f6c4f45275e1b94aec7a5f4d` | 36/32/0/0 | R4 · research_only; inherited source receipts | silver/unlabeled · human_gold=false | Colab/package receipt + source manifests |
| `Datasets/camera-coach/silver-fit-20260918` | checkpoint/eval/export | 1332 | 724617110 | `935518630dba14721d3fc9b83580e302d2e4bc510c2a4af8cd89e0a338202922` | 28/39/5/0 | R4 · explicit research_only/release_admissible=false | silver fit · human_gold=false | silver-fit run/conversion/parity receipts |
| `annotation/language-review-20260915` | annotation/review artifact | 6 | 1228741 | `232727866bbd46663660ee5e17d475835ac5c01040c686964edcede34b66edbd` | 2/2/0/0 | R5 · local research-only; no release admission | mixed proposal/human-confirmed · explicit human_gold=false | annotation receipts/journals/pytest evidence |
| `annotation/partial-intake-20260916-v1` | annotation/review artifact | 6 | 16569049 | `f1a878f30d88129d17936f473bc24509991733cca61864cb1124dddeb5fc2a9c` | 4/2/0/0 | R5 · local research-only; no release admission | mixed proposal/human-confirmed · explicit human_gold=false | annotation receipts/journals/pytest evidence |
| `annotation/partial-intake-checks-20260916-zqrxPK` | annotation/review artifact | 194 | 847651 | `c2b3148aa2ffe56f38fb43940b9397cf2b5aa0a02ec80d771835bbc7b1d2d2f6` | 77/92/0/24 | R5 · local research-only; no release admission | mixed proposal/human-confirmed · explicit human_gold=false | annotation receipts/journals/pytest evidence |
| `annotation/partial-intake-final-20260916-wIZyYx` | annotation/review artifact | 174 | 892239 | `902d0a3ca3ded374e3fa56cc14e484b73ee1c3c0611aaf2c71bbfc63e1d6e273` | 83/86/0/16 | R5 · local research-only; no release admission | mixed proposal/human-confirmed · explicit human_gold=false | annotation receipts/journals/pytest evidence |
| `annotation/partial-intake-guards-20260916-14Ynmj` | annotation/review artifact | 175 | 892760 | `580dbcf32f7cff98b57f16a7b0c344df3b465b4ab87ae2a9c1ff920b0dcd6ab5` | 83/86/0/16 | R5 · local research-only; no release admission | mixed proposal/human-confirmed · explicit human_gold=false | annotation receipts/journals/pytest evidence |
| `annotation/pilot-20260914-v4` | annotation/review artifact | 25 | 2695882 | `6962eb388a72c6d8d1ff310d6c8681f02f8fdf5dde37bdecd5f09479e53eb45d` | 6/7/0/0 | R5 · local research-only; no release admission | mixed proposal/human-confirmed · explicit human_gold=false | annotation receipts/journals/pytest evidence |
| `annotation/verification-20260916-Uaj87d` | annotation/review artifact | 59 | 46179 | `49d0c1b7b2a1615a0f213769559f59afdcb8529d648a335b5eef974971d765a6` | 2/12/0/17 | R5 · local research-only; no release admission | mixed proposal/human-confirmed · explicit human_gold=false | annotation receipts/journals/pytest evidence |
| `annotation/<root-files>` | manifest/queue metadata | 3 | 512429 | `f1dbeb2e96ae3fdf0860005353489ae6562c6697e6cc08e0b32437686c7f35c7` | 3/3/0/0 | R6 · metadata only | unknown | root queues; no admission evidence |
| `snapshots/20260916-backend-cancellation-repair` | snapshot/package evidence | 6 | 214946 | `a707acaf20fe7ae921b01ca4bb9b6640b9d4a09c02bfc0be1cec2d7556003a45` | 2/2/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/20260916-backend-cloud-auth` | snapshot/package evidence | 43 | 626167 | `8245ac555d103b8922770ea105f2f07781a0f805f1aba4a2a0d44c85f66f094b` | 6/3/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/20260916-backend-content-retention` | snapshot/package evidence | 6 | 200914 | `eefcd28b1b9cd77f472b509bdeb6ee1ea7b51662630f5673e0a4db3189ff09ea` | 2/2/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/20260916-backend-deployable-package` | snapshot/package evidence | 35 | 471617 | `2b591472167732cf82077ce95b7d613261ed27782a097497b8a299fe43cbf559` | 5/3/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/20260916-backend-host-package` | snapshot/package evidence | 67 | 809867 | `b10a15d27e90a84e36824c21f0e906b4b3b8fa0c36a382fb746404979c2edb1b` | 9/8/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/20260916-backend-installation-deletion` | snapshot/package evidence | 12 | 428292 | `4d5e350ff6140a9bc60121839977f2ffde4e53b9becf5ad122810e39bb1c4db9` | 4/4/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/20260916-backend-lifecycle-admission` | snapshot/package evidence | 4 | 31951 | `a6c070822f7392a4d35c046129c2ea8e74d8a295282e6dff8e2d98d6b9bf3362` | 2/0/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/app-attest-crypto-20260916` | snapshot/package evidence | 7 | 112506 | `7f017ccbfb5f24e64bc96f0e905a112e585c9ea8398b0b84cb0af6eb4d01c076` | 2/0/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/s02a-roundtrip-koj70wiq` | snapshot/package evidence | 3 | 45169 | `dc7c2f29ba3fa6cf7c76a37d6aa298128e9a555232b8418dc8ba602a188be4f4` | 0/0/0/0 | R5 · internal evidence; not dataset admission | n/a / unlabeled | backend/crypto snapshot receipt |
| `snapshots/<root-files>` | archive/manifest metadata | 5 | 196266 | `8a9b9458c48f407384fa73bd5750c11af5d6281fe61f8e8d59d21d3adaa2c94d` | 2/1/0/0 | R5 · internal evidence; not dataset admission | n/a | root snapshot archives/manifests |
| `verification/camera-runtime-owner-review-20260917-z0c1qz_i` | verification/evidence packet | 37 | 206729 | `66e21a8ba25cbb61afe747774da046b1c73261e4aafe3f9fa21c108f966926c0` | 8/6/0/0 | R5 · explicit research_only/release_admissible=false | unlabeled evidence · human_gold=false | runtime owner-review manifest/queue |
| `inventory` | inventory receipt | 1 | 109305 | `47a0d28a604990509e417bbdee1a4880e3532b93efad84b55de1449b882755af` | 1/1/0/0 | R6 · metadata only | unknown | historical 2026-09-20 machine inventory |

## Rights, label and admission interpretation

Codes used above: `R1` = source-specific research-only/per-record provenance (no family-level release licence established); `R2` = a documented upstream licence/terms note exists but attribution/redistribution constraints remain; `R3` = derived/internal artifact inheriting the source restrictions; `R4` = package/checkpoint receipt explicitly says `research_only=true`, `human_gold=false`, `release_admissible=false`; `R5` = internal verification/snapshot evidence, not a training or release dataset; `R6` = metadata only.

The metadata scan read **1,037,664,608 bytes** of bounded text metadata. It found 0 `human_gold:true`, 316,825 `human_gold:false`, 286,726 `research_only:true`, 0 `research_only:false`, 0 `release_admissible:true`, 316,826 `release_admissible:false`, 239,547 `label_status:"unlabeled"`, and 7 other label-status occurrences. These are field occurrences, not deduplicated label rows; files over the 64 MiB text-scan cap remain unknown. Therefore this receipt declares no current human-gold or release-admissible family. Annotation rows are conservatively `mixed ... human_gold=false` even where a human confirmed text/proposal; they are not DATA-010/011 gold.

License/provenance notes are taken from existing receipts/manifests only: AADB/EVA have no family-level licence note; AVA is research/no redistribution; cinematic records cite Blender CC-BY; synthetic cites SceneTrans CC-BY-4.0; Commons is per-file Wikimedia rights; lighting cites Poly Haven CC0/API terms; photography is mixed Commons/OpenImages with an intake-blocked subset; temporal is per-video rights-policy evidence; paired-corruptions and fit/checkpoint outputs inherit source restrictions. No name or size was treated as proof of rights or human-gold status.

## Full checkpoint/model hashes

Full SHA-256 was computed for bounded model/checkpoint binaries (18 files, 220,722,688 bytes); this does not include raw media or the old `.venv` interpreter link.
- `Datasets/camera-coach/research/open-images-lamp-pilot-20260911.4PMfRR/DETRResearchSignals.mlpackage/Data/com.apple.CoreML/model.mlmodel` — `4d0340a0d1784b6ca7b0db1e4939cab93afb6391d10ce33db3319900e5d2eaa3`
- `Datasets/camera-coach/research/runs/eva-stage1-local-20260913/checkpoints/epoch-0001.pt` — `61f02131684bb7354cf9ee77151d3ac99ae4f5f57f4e32436ecead5f4f99738d`
- `Datasets/camera-coach/research/runs/eva-stage1-local-20260913/checkpoints/epoch-0002.pt` — `49b6829b59935314eb2c43df968145e3d9a0ef12b2a1683c0990d34446cf4af9`
- `Datasets/camera-coach/research/runs/eva-stage1-local-20260913/checkpoints/epoch-0003.pt` — `ca3efa6f26627f7e0d195df334f507b0fd81cbde2ce1942f915f90df535123ff`
- `Datasets/camera-coach/research/runs/eva-stage1-local-20260913/checkpoints/epoch-0004.pt` — `aee276d9e3a685714fb61c60080ec2b545d384d9379bce3a4b28ea91a2a82daa`
- `Datasets/camera-coach/research/runs/eva-stage1-local-20260913/checkpoints/epoch-0005.pt` — `fb05067de473a1e880d00678de339855782e5a5abc9720ca64c7e41e4badcc6d`
- `Datasets/camera-coach/research/runs/eva-stage1-local-20260913/encoder-final.pt` — `4397b7613fd4e830e7628007bb920cf5f5d0c4419480d22603cf451d5025ab00`
- `Datasets/camera-coach/research/runs/stage2-local-20260913/candidate-final.pt` — `fe81f0a657ea35b91eead1ac2d475f1228696bb4d2390185c658b98e287bbfcb`
- `Datasets/camera-coach/research/runs/stage2-local-20260913/checkpoints/epoch-0001.pt` — `04b90ed7a3088fa4ed49a1dc426493e917d9f445f169ad3c343625f560324584`
- `Datasets/camera-coach/research/runs/stage2-local-20260913/checkpoints/epoch-0002.pt` — `85b568405d19e24ea7553af4b35786f0433493f0fc73be1e594765b2c435ad74`
- `Datasets/camera-coach/research/runs/stage2-local-20260913/checkpoints/epoch-0003.pt` — `5b8d2e09ccc16d3c61f538033836a8b05e8a898f2d2e39e21335be9bb27d8ff4`
- `Datasets/camera-coach/research/runs/stage2-local-20260913/checkpoints/epoch-0004.pt` — `14793629ff92ab530bc1c566407e330ac980849b5d1b80650ea551ee057d85c2`
- `Datasets/camera-coach/research/runs/stage2-local-20260913/checkpoints/epoch-0005.pt` — `92793b5109463ffb6031d40d4374b151112386f59cc549a88efed1a69620a03e`
- `Datasets/camera-coach/silver-fit-20260918/export/SETCompositionNet-silver-fit-20260918.mlpackage/Data/com.apple.CoreML/model.mlmodel` — `79b2e9326421f4e3b4c4012da21ec1befbd85dbc5b0c404412472a207272aaaf`
- `Datasets/camera-coach/silver-fit-20260918/run-complement/candidate-final.pt` — `23c31a9d313d9bdd82521b9b663ae091db50ed91ef8d083880fed3b284525324`
- `Datasets/camera-coach/silver-fit-20260918/run-complement/checkpoints/epoch-0012.pt` — `7723ee8f75335688d583bba46b36021e70e7cdff7a0a23b5c12f7817d9c170ca`
- `Datasets/camera-coach/silver-fit-20260918/run/candidate-final.pt` — `fd7329d2f854c95334e2b86dc066be8bec74f34c5442e8bc8063be3d7f76c380`
- `Datasets/camera-coach/silver-fit-20260918/run/checkpoints/epoch-0012.pt` — `094725556cfb7a14c2fe2977118d504637383c1cf8b0848b60fe3b2cf253b0e4`

## Aliases, stale references and duplicate limits

- `76` symlinks were observed: `73` are internal annotation pytest `*current` aliases, and `3` are the old webresearch virtualenv interpreter links (`python`, `python3`, and `/Library/Frameworks/Python.framework/.../python3.11`). None points to the historical `~/Library/Application Support/SETOS/` root. No symlink was deleted or dereferenced as a byte-equality claim.
- `/Users/unterlantas/Library/Application Support/SETOS` is absent. Historical manifests still contain that absolute prefix; readers must apply the documented in-memory prefix replacement from `../setos-backend/LOCAL_DATA.md`. No historical bytes were rewritten.
- The old 2026-09-20 machine receipt (`SETOS/inventory/2026-09-20-data-003-inventory.json`, SHA-256 `1fa36be3928e2b451e5c373e895473c110b2d51191753f4b091726f6a657ba26`) reported 225 families/253,490 files/52.3 GB, while this live tree contains 46 meaningful families/149,849 regular files/39,467,986,588 bytes. That historical difference is recorded as a stale-reference/state discrepancy, not attributed to deletion by this task and not used to declare content equality. The old receipt and its bytes were not changed.
- Named package attempts (`colab_package_v2_20260914*`) are retained as distinct historical families. No byte-level duplicate/reclaim claim was made: only metadata aggregates and existing declared hashes were used; a full raw-media content-dedup audit remains GOV-007/owner-decision scope.
- A representative verification queue still references `/Users/unterlantas/.../verification/legacy-reference-recovery-20260917-p8m2af3s/recovered/180.jpg`; the resolved current path is missing. This is recorded as a stale/missing reference, not repaired here.

## Representative declared-hash checks

1. `research/cinematic/manifest.jsonl` first `image_sha256` resolved through the relocation mapping to `frames/tears_of_steel/frame_0010_00.jpg`: declared and actual SHA-256 both `350e940975423666cfde64134934c2af31d1b5514d20772926ac5f751b18e029` (PASS).
2. `colab_package/manifest.jsonl` first `image_sha256` resolved to `frames/big_buck_bunny_research_20260914/frame_000011.jpg`: declared and actual SHA-256 both `72907ace6a2201796591913295779d6b2032ee02bfe0d58ffb4ed628b138bf7e` (PASS).
3. `verification/.../queue.jsonl` first `media_sha256` points to the missing recovered `180.jpg`: existence/hash check `MISSING` (explicit limitation).

## Before/after no-mutation evidence

Before and after metadata walks used the same candidate HEAD and the following exact baseline: `regular_files=149849`, `logical_bytes=39467986588`, `symlinks=76`, `metadata_aggregate_sha256=057f227364a5266192ea8282c40f6d1c1844b66f1333cbf296bf626193036d6e`, old Library alias `absent`. Representative sample files retained identical size, mtime_ns and SHA-256 across the re-run: cinematic manifest (`209069`, `1789297459347208240`, `5ea01c75ca75e1b7027796e7a348631e44f6fb931ae67e594d718a969f3350f4`), Colab manifest (`13199906`, `1789391225923666791`, `1c56dac0433754a47c3bc02584f1d7c6697e1c075b8fcb23130ffabc0681053f`), pilot receipt (`829`, `1789416885645199680`, `c74377f834db15cc9709c856c20317381ee16b2159ca6a24ca301e3a0a63d97e`), verification manifest (`550`, `1789610237666075804`, `19800d68881af1a1f79f9f43e687d9db634e854373135b6df697ff5f57d74d6f`), snapshot receipt (`9775`, `1789564975439694631`, `74522f28607b90e86483189f8648ff199cfe218da1c227f3b7e46a36b973d965`), and relocation receipt (`1819`, `1789559135289511215`, `5720bff8b81ec7ecf2468dd8d57c4efe455130d6aeb93b68a852b3ab28f8371e`). **Deleted: nothing.**

Exact bounded commands (run from the app repo; no raw copies):

```sh
python3 -B /private/tmp/setos-data003-ZFwP1N/inventory_current.py /private/tmp/setos-data003-ZFwP1N
python3 -B /private/tmp/setos-data003-ZFwP1N/evidence.py /private/tmp/setos-data003-ZFwP1N/evidence-before3.json
python3 -B /private/tmp/setos-data003-ZFwP1N/evidence.py /private/tmp/setos-data003-ZFwP1N/evidence-after3.json
find /Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS -type f -print0 | xargs -0 stat -f "%z" | awk ...
```

The inventory helpers were temporary and contained metadata only. Cleanup at finish: `rm -rf /private/tmp/setos-data003-ZFwP1N` (exact bounded path); no file under `local-data/SETOS`, `~/Library`, or `/Library` was targeted.

## Acceptance

`DATA-003 DONE`: current canonical families are inventoried with exact counts/bytes, deterministic aggregate identity, rights/admission and conservative label tiers, model/checkpoint/manifest families are visible, historical aliases and missing references are explicit, historical evidence remains untouched, and no deletion is claimed without before/after proof.
