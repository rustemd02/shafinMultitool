# Polza Camera Coach research probe — 2026-09-11

Status: first paid probe cycle complete; app slice verification tracked below. This is a bounded offline-photo VLM experiment, not production
Camera Coach, not s2 ingress conformance, and not a human-gold aesthetic benchmark.

## Scope and continuation

- Parent: [domain v3 design](../03-domain-contracts.md#camera-coach-domain-v3--проект-контракта-для-фото-и-видео), especially N8/N12; current App Store no-camera-egress boundary remains unchanged.
- Start HEAD: `0733df2cb83c8e3687c31251e11e5d0747052602`, `store`; pre-existing dirty ML/data/docs preserved. No commit/push/reset authorized.
- User authorized paid Polza experiments under the provider-configured key limit; balance preflight reported `available=600 RUB`. No credential is stored in files or command-line arguments. Interactive `getpass` passes authorization to curl via stdin. System curl verifies TLS; Python's default CA store failed certificate validation on this host, so it is not used for transport. TLS verification is never disabled.
- Parent owns Python probes/docs; explicitly requested Luna 5.6 max subagent owns an isolated debug-only Swift ingress slice. No direct connection from this probe's response format into Swift, no production cloud transport, no replacement of the existing planner or ML heads.
- Current tasks: baseline → stricter prompt/schema → new-image checks → inspect concrete errors/costs → review Swift change → record limits. Stop on provider/billing errors without automatic retries; never bypass a key limit.

## Reproduction

`run_polza_probe.py` reuses existing eval JSON I/O. The input manifest selects only
existing Commons files with accepted rights receipts and matching image SHA-256;
raw media stays outside Git. The request sends those selected images to Polza and
its downstream model provider, not personal photos. Sources and attribution are
saved with each run. A new output directory is mandatory; old results are not replaced.

```sh
python3 -B docs/cameraanalysis/eval/run_polza_probe.py --self-check
python3 -B docs/cameraanalysis/eval/run_polza_probe.py \
  --manifest docs/cameraanalysis/eval/polza_probe_cases.json \
  --commons-root '/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/commons/v1-scale-1000' \
  --out '/ABSOLUTE/NEW/OUTPUT/DIRECTORY'
```

The default is preflight only: it fetches the public model catalog, validates local
inputs, and sends no images. Paid mode additionally requires `--execute
--allow-public-image-egress --max-spend-rub 40`, then a hidden key prompt. `--strict`
adds explicit constraints and requests JSON Schema only when catalog capabilities
advertise structured output. All responses still undergo local validation; advertised
schema support is not trusted as enforcement. `--models` pins exact catalog IDs.

Each run writes input/source/catalog/config snapshots, per-request results with
latency and reported usage/cost, incremental summary, and start/end balance.
Timeout/error costs remain unknown; do not treat missing cost as zero. No automatic
retries or provider-limit changes. The local spend setting is a **soft stop between
requests**, with a 10 RUB reserve, not an exact per-request reservation; the provider's
key limit is the hard spending boundary. A run stops early when billing is unknown.

## Evaluation limits

Eight development cases use three inspected images. Five new-image cases use two
additional images; the archival interior comes from the same collection, so this is
not an independently sourced locked holdout. Prompts must not be tuned on those
new-image results and then advertised as held-out generalization.

Checks cover exact JSON/enum/reference/frame binding, coordinate bounds, explicit
no-move and observation-only constraints, absent-target abstention and byte-identical
before/after consistency. Localization anchors are provisional points chosen by the
agent, not human-gold boxes: inclusion of a point is weak evidence and does not measure
IoU or prove precise grounding. A very large box can pass point coverage. Constraint
pass rates do not measure advice usefulness; a model that always abstains may pass
many negatives. Single-frame `unchanged` is treated as an unsupported temporal claim.

The repeated-image comparison is only a negative temporal sanity check. A later
two-direction changed-pair probe uses one existing SHA-pinned `rotate_horizon`
derivative of the initial room, not a newly generated image. Original/derivative
order is explicit; lineage and both image hashes are checked. This tests recognition
of a synthetic rotation/crop, not real video motion, action completion or aesthetic
improvement. The later challenge adds two matching wall-light groups, two vases,
similar chairs and a reflection. Two identical **movable** lamps with a demonstrated
safe destination remain untested, as do physical feasibility, useful positive
actions, before/after human preference and iPhone UX.

## Provider references

- [Media inputs](https://polza.ai/docs/gaidy/media-input)
- [Model discovery](https://polza.ai/docs/gaidy/models)
- [Structured output](https://polza.ai/docs/gaidy/structured-output)
- [Usage/cost fields](https://polza.ai/docs/osobennosti/usage)
- [Available balance and key limits](https://polza.ai/docs/api-reference/other/balance)

## Evidence location

External root: `/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/vlm-polza/`.
Run directories are listed in the result table below; `20260911-preflight` is unpaid.
All evidence remains `research_only=true`, `human_gold=false`, `release_admissible=false`.
No M3/M4 release gate is closed by these probes.

## Measured first-cycle results

140 paid responses across six model IDs, seven original Commons images and one
existing synthetic derivative. Provider-reported total: **95.20637306 RUB**.
The key started with 600 RUB available; no key limit was raised. These are actual
response costs including reported cache/reasoning effects, not a catalog estimate.
Some batches overlapped in time; latency is observed end-to-end, not a controlled
device/network benchmark. Repeated responses may benefit from provider caching.

| External run directory | Calls | Reported RUB | Purpose / stop |
|---|---:|---:|---|
| `20260911-baseline` | 24 | 2.41402442 | 8 cases × 3 models; complete |
| `20260911-strict` | 32 | 4.49204683 | Same 8 cases × 4 models; stronger prompt/schema; complete |
| `20260911-new-images` | 30 | 4.47231830 | 5 new-image cases × 3 models × 2 repeats; complete |
| `20260911-two-objects` | 18 | 2.95846103 | 6 additional multi-object/reflection cases × 3 models; complete |
| `20260911-strong-challengers` | 11 | 70.50502699 | Same challenge with Sonnet 5/Astra; local 80 RUB batch reserve stop |
| `20260911-astra-reflection` | 1 | 6.76206216 | Remaining Astra case, explicit separate bounded batch; complete |
| `20260911-focused` | 18 | 2.60259397 | Same challenge with task-relevant two-object instruction; complete |
| `20260911-changed-pair` | 6 | 0.99983936 | One existing rotation/crop pair in both orders × 3 models; complete |

Scores below require valid structure **and** the case's explicit constraints / coarse
point checks. These are not percentages of useful coaching or calibrated accuracy.

| Model | Baseline | Strict development | New images (two repeats) | Multi-object challenge | Focused variant |
|---|---:|---:|---:|---:|---:|
| `google/gemini-2.5-flash-lite` | 2/8 | 6/8 | 9/10 | 4/6 | 3/6 |
| `openai/gpt-4.1-mini` | 3/8 | 6/8 | 8/10 | 5/6 | 3/6 |
| `qwen/qwen3-vl-235b-a22b-instruct` | 2/8 | 2/8 | not run | not run | not run |
| `google/gemini-3-flash-preview` | not run | 8/8 | 10/10 | 5/6 | 5/6 |
| `anthropic/claude-sonnet-5` | not run | not run | not run | 0/6 | not run |
| `openai/gpt-6-astra` | not run | not run | not run | 6/6 | not run |

Changed-pair checks: Flash Lite 1/2 (detected change but once gave an unsolicited
correction); GPT-4.1 mini 2/2; Gemini 3 Flash 2/2. This does not establish that their
description of every changed line is correct.

### Concrete findings and next decision

- Qwen emitted 0–1000 corner coordinates under the baseline and often normalized
  corners instead of width/height under strict instructions. No auto-rescaling,
  coordinate guessing or clipping was used to turn invalid payloads into passes.
- Flash Lite sometimes made a temporal `unchanged` claim from one image or used an
  unsupported action enum. Strict instructions improved structure, not all localization.
- GPT-4.1 mini and Flash Lite missed small vase/lamp point anchors despite plausible
  descriptions. Point coverage is too weak to establish precise boxes even when passed.
- Gemini 3 Flash's reflection response correctly abstained but emitted an unrelated
  chair box `[1,0.358,0.19,0.262]`; the whole response was rejected. Focused prompting
  fixed that case but introduced another invalid chair box: **no net challenge gain**.
- Sonnet 5's six responses under this particular prompt/profile failed bounds. This
  is not a universal claim about the model; an alternative coordinate contract was
  not tested. Astra passed six challenge cases, at roughly 6.76–13.52 RUB/request;
  Gemini 3 Flash's corresponding standard challenge cost roughly 0.19–0.27 RUB/request.
- Manual review still found ambiguity in otherwise valid advice: “lower the camera”
  can mean tilt or translation, and screen movement is not the same as physical
  camera movement. No response is approved for a live arrow or physical instruction.

Working shortlist: Gemini 3 Flash for further economical research, Astra as an
expensive comparison reference, **not an autonomous judge or human-gold labeler**.
The focused variant is not promoted. The remaining budget is not evidence of quality
and was not burned through identical repeats. The next useful step is a qualified
grounding/coordinate contract, source-diverse positive-action episodes and local
tracking/verifier evidence, rather than claiming an ideal model from these probes.

For a selected-case rerun use `--case-ids`; `--focused` is an experimental instruction,
not the default winner. The changed-pair manifest additionally requires `--pairs-root`
pointing to the existing Commons paired-corruption root. No source files are modified.

### Integrity readback

Fresh local recomputation matched every stored per-model summary to the raw rows,
counted 140 responses / 6 models / 7 originals, and reconciled exact decimal cost
`95.20637306` with final key availability `504.79362694 = 600 - cost`. All 140
responses had reported cost; no unknown-billing attempts were discarded.

| Run | SHA-256 of `results.jsonl` |
|---|---|
| baseline | `b9d9a885034eea3060b8b2fa848d68b1733ddc129f048f5d4520fa642357a581` |
| strict | `477fa59e7ef959e471537ad89bdb7c0ef27018a3dad28252a935a879747ec337` |
| new-images | `a05f550518de11ceb757857af0e8bc9ed5c0330cdbe0f1c274639981cc260193` |
| two-objects | `e1753644b3d53c9fc5188b659d501cc1107e8f1c945400068b48dd13b7adb313` |
| strong-challengers | `6e8ff24875259edc1147780a48f544a611502626d81b27ac7d31b901319afa6d` |
| astra-reflection | `3bdf6a0e5199bf5226ec57d2025e0846d3c8724011dff3c45fbc98a8163f05eb` |
| focused | `cb95f20eebf901b305a89d293785ddf25bd591543cf3517407e43cb5ed67e22b` |
| changed-pair | `243b825082ba64e81053c2c8841251b9d5f1038f967052009453877a1ed5ba0f` |

## App slice: verified DEBUG-only ingress

The requested Luna 5.6 max subagent implemented
`shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraCoachDraftV3ProposalIngress.swift`
and six focused tests in `shafinMultitoolTests/CameraCoachDraftV3ProposalIngressTests.swift`.
The explicit `two_object_local_grounded_observation` profile admits two object/prop
proposals, clutter/background-separation evidence, object conflict and
competes-for-attention relations only. It is not the full s2/v3 schema.

The boundary rejects unknown JSON keys (including provider track IDs/actions),
oversized input, invalid raw normalized rectangles without clamping, stale/cancelled
or mismatched requests, disallowed privacy modes, unresolved references and collapsed
or substituted local identities. Grounding is supplied by a local owner, never trusted
from provider JSON. Accepted observations project into existing evidence types;
scores are uncalibrated and do not qualify a user-facing action. Review removed
face-occlusion semantics because object-only endpoints cannot establish them.

There are **no production callers, cloud camera transport, UI changes or planner
integration**. Python probe responses use a different experimental schema and cannot
be passed directly to this decoder. The remaining implementation is real local
grounding, action admission and outcome verification, not merely wiring this parser
to a paid endpoint.

Focused verification after the final semantic trim:

```sh
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=523ED550-7B55-41C0-A2B1-44B12D1B97AF' \
  -derivedDataPath /tmp/shafin-camera-coach-v3-derived \
  -only-testing:shafinMultitoolTests/CameraCoachDraftV3ProposalIngressTests test
```

Result: **6 passed, 0 failed, 0 skipped**, iPhone 17 Pro simulator, iOS 26.5.
Parent independently read the result with `xcresulttool get test-results summary`:
`/tmp/shafin-camera-coach-v3-derived/Logs/Test/Test-shafinMultitool-2026.09.11_14-17-02-+0300.xcresult`.
This temporary evidence path is not durable; the command and summary are recorded
here. Tests cover acceptance/projection, invalid bounds, alias collapse, local-owner
substitution, privacy/expiry and forbidden provider keys. They do not establish full
contract conformance, actual object recognition, device performance or live UX.

The probe's `--self-check` and repository `git diff --check` also pass. Existing dirty
files were preserved; no commit/push, model-bundle admission or M3/M4 closure occurred.
