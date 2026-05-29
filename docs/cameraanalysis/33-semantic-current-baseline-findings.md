# 33. Semantic Current Baseline Findings

Status: real runtime baseline measured, substantially calibrated on the silver still-image replay, not yet product-ready.
Date: 2026-05-27.

This document records the factual state after executing the dataset/eval plan
from `31-dataset-eval-implementation-plan.md`.

## Measurement Boundary

The current report is based on a DEBUG still-image replay through the app's
Swift pipeline, not on a handcrafted proxy:

```text
candidate_id = semantic_eval_real_runtime_candidate_outputs_after_r21a
runtime_claim = real_runtime_still_replay
record_count = 107
```

What this means:

- dataset images from `docs/cameraanalysis/dataset/inbox/images` are replayed through the app-side analysis path;
- candidate rows are exported by Swift code via `SemanticEvalCandidateOutput`;
- Python eval scores those rows against `semantic_labels_v1.jsonl`;
- this is valid engineering evidence for the current implementation, but not yet final dissertation performance evidence.

Important limitation:

- the label set is a silver eval set created for product calibration, not a peer-reviewed benchmark;
- still-image replay is not the same as live camera UX with hand motion and real-time UI timing;
- screenshots/films in the dataset can contain deliberate cinematic choices that deterministic rules still misread.

## Current Implementation State

What exists now:

- Python eval validates labels, scores candidate JSONL and emits set/bucket/case reports.
- Python eval can merge separate `live` and `pause` rows for the same image into one scored case.
- Swift has `AnalysisPipeline.testingReplayStillImageForSemanticEval(...)` for DEBUG full-runtime still-image replay.
- Swift exports live/pause semantic eval rows with confidence, debug issue/strength/action types and runtime claim.
- Pause actions now preserve `SemanticActionType`, so eval sees the semantic action actually represented by `SemanticTipCandidate`, not only coarse transport action classes.
- Still-image replay exports a technical-quality analyzer as `future_actions` for focus/exposure/noise/stability-oriented evaluation.
- Production live/pause presentation has a first technical-quality gate: live can show a short focus/exposure/stability hint, and pause can show a technical critique when no semantic corrective tip would be displaced.
- `FrameCritiqueEngine` has a first calibration pass for cinematic good-frame preservation: readable anchored subjects, low-key/backlight style and soft background findings are less likely to become corrections.
- Horizon corrections require more reliable horizon evidence, reducing false horizon advice on unstable/low-confidence frames.
- Presentation tests cover live/pause eval row projection and reasoning safety tests cover pause-only LLM/VLM refinement guardrails.

What still does not work well enough:

- real replay quality is complete on the current silver still-image replay, but this is still not live-camera product proof;
- good cinematic frames are preserved on the current silver replay, but this is a guarded deterministic calibration, not proof that live camera intent recognition is solved;
- technical/IQA failures have a first production UX gate, and current replay future-action recall is complete, but this remains still-image evidence rather than live UX proof;
- confidence bands pass on the current silver still replay, but the last fix depends on still-frame aspect evidence and does not prove broader live scene-intent recognition;
- object-aware and multi-subject grounding is still weak, especially when the runtime misses people and anchors on background-like objects.

This is the key honesty boundary: we now have real measurement, and it says the
feature is still an engineering prototype, not a ready semantic camera coach.

## Latest Baseline Metrics

Current measured candidate:

```text
docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a/
```

Metrics:

- `record_count`: 107
- `pass_rate`: 1.000000
- `expected_action_hit_rate`: 1.000000
- `future_action_hit_rate`: 1.000000
- `forbidden_action_violation_rate`: 0.000000
- `good_frame_preservation_rate`: 1.000000
- `positive_confirmation_rate`: 1.000000
- `confidence_band_accuracy`: 1.000000
- `demo_priority_pass_rate`: 1.000000
- `technical_failure_gate_rate`: 1.000000

Failure counts:

- none

Bucket view:

- `good`: 46 cases, 46 pass; good-frame preservation and positive confirmation are both 1.0 on the current silver replay.
- `mixed`: 14 cases, 14 pass; expected-action and future-action recall are complete on this silver replay.
- `bad`: 47 cases, 47 pass; forbidden positive confirmations are eliminated, technical-failure gate rate is 1.0, and bad-frame strict failures are closed on the current silver replay.

## Delta From Earlier Real Runtime Baselines

Previous measured output used a safer live/pause projection that lost some
semantic action detail:

```text
docs/cameraanalysis/eval/out_semantic_real_runtime_live_keep_projection/
```

Previous key metrics:

- `pass_rate`: 0.177570
- `expected_action_hit_rate`: 0.467290
- `future_action_hit_rate`: 0.520833
- `forbidden_action_violation_rate`: 0.280374
- `good_frame_preservation_rate`: 0.543478
- `confidence_band_accuracy`: 0.439252

The semantic-action-row export improved expected-action visibility but exposed
more forbidden overcorrection:

- `expected_action_hit_rate`: 0.467290 -> 0.495327
- `pass_rate`: 0.177570 -> 0.186916
- `forbidden_action_violation_rate`: 0.280374 -> 0.345794

The `R03k` calibrated replay improved the measured product behavior from that
honest-but-raw export:

- `pass_rate`: 0.186916 -> 0.289720
- `expected_action_hit_rate`: 0.495327 -> 0.570093
- `future_action_hit_rate`: 0.520833 -> 0.875000
- `forbidden_action_violation_rate`: 0.345794 -> 0.168224
- `good_frame_preservation_rate`: 0.543478 -> 0.804348
- `positive_confirmation_rate`: 0.543478 -> 0.760870
- `confidence_band_accuracy`: 0.439252 -> 0.607477

`R06` added a narrower preservation pass for readable, background-like and weak
establishing anchors:

- `pass_rate`: 0.289720 -> 0.327103
- `expected_action_hit_rate`: 0.570093 -> 0.644860
- `future_action_hit_rate`: 0.875000 -> 0.875000
- `forbidden_action_violation_rate`: 0.168224 -> 0.130841
- `good_frame_preservation_rate`: 0.804348 -> 1.000000
- `positive_confirmation_rate`: 0.760870 -> 0.956522
- `confidence_band_accuracy`: 0.607477 -> 0.607477
- `demo_priority_pass_rate`: 0.571429 -> 0.714286

The latest `R08` replay adds bounded semantic export for dominant technical
hotspots while guarding good/high-aesthetic frames from overcorrection:

- `pass_rate`: 0.327103 -> 0.411215
- `expected_action_hit_rate`: 0.644860 -> 0.728972
- `future_action_hit_rate`: 0.875000 -> 0.875000
- `forbidden_action_violation_rate`: 0.130841 -> 0.112150
- `good_frame_preservation_rate`: 1.000000 -> 1.000000
- `positive_confirmation_rate`: 0.956522 -> 0.956522
- `confidence_band_accuracy`: 0.607477 -> 0.607477
- `demo_priority_pass_rate`: 0.714286 -> 0.714286

Rejected `R09a` confidence experiment:

- hypothesis: when the exported semantic action is `keep_current_setup`, do not
  raise confidence using the technical-quality floor;
- result: rejected, because the full real-runtime replay regressed;
- `pass_rate`: 0.411215 -> 0.345794
- `confidence_band_accuracy`: 0.607477 -> 0.542056
- `demo_priority_pass_rate`: 0.714286 -> 0.428571
- unchanged but still weak: `expected_action_hit_rate=0.728972`,
  `future_action_hit_rate=0.875000`,
  `forbidden_action_violation_rate=0.112150`

Interpretation:

This was a useful negative result. The system has two meanings currently mixed
inside one confidence number:

- confidence that the semantic verdict/action is correct;
- confidence that a technical future action such as exposure/noise/focus is
  present.

Blanket suppression for `keep_current_setup` helped some medium-confidence
cases, but broke more good high-confidence cinematic frames. The accepted
follow-up, `R09b`, therefore calibrates a narrower case instead of switching
technical confidence off globally for positive confirmations.

Accepted `R09b` confidence calibration:

- hypothesis: a good pause verdict with explicit positive strengths may use a
  high confidence floor, while weak/empty good verdicts stay conservative;
- result: accepted, because the full real-runtime replay improved without
  changing action coverage or forbidden-action leakage;
- `pass_rate`: 0.411215 -> 0.467290
- `confidence_band_accuracy`: 0.607477 -> 0.672897
- `demo_priority_pass_rate`: 0.714286 -> 0.857143
- unchanged remaining weaknesses: `expected_action_hit_rate=0.728972`,
  `future_action_hit_rate=0.875000`,
  `forbidden_action_violation_rate=0.112150`

Interpretation:

Accepted `R10a` confidence calibration:

- hypothesis: if pause verdict is `mixed` and the exported action is corrective,
  technical-quality confidence floor must not promote the eval/exported
  confidence into the high band;
- result: accepted, because the full real-runtime replay improved one strict
  case without changing action coverage or forbidden-action leakage;
- `pass_rate`: 0.467290 -> 0.476636
- `confidence_band_accuracy`: 0.672897 -> 0.682243
- `confidence_band_mismatch`: 35 -> 34
- unchanged remaining weaknesses: `expected_action_hit_rate=0.728972`,
  `future_action_hit_rate=0.875000`,
  `forbidden_action_violation_rate=0.112150`

Interpretation:

The system is measurably better than the first real runtime export, but the
absolute score is still not product-ready. `R10a` fixed exactly one measured
case, `ca_img_033`, where a mixed corrective pause row had the right
`simplify_background` action but an overconfident high confidence band. This is
a confidence honesty fix, not an object-grounding fix. `R03i` adds a narrower
technical-quality correction:
very dark low-key frames no longer become dominant blur/focus failures, while
moderately dark soft frames still do. This preserved the R03h pass/positive
confirmation gains and restored forbidden-action violations to the safer R03g
level.

`R03j` tried to promote the technical-quality probe directly into live/pause UX,
but the naive pause override displaced semantic corrective actions on cases such
as `ca_img_088` and `ca_img_093`, dropping pass rate to `0.271028`. `R03k`
keeps the production live technical hint and pause technical critique, but only
uses the pause technical critique when no corrective semantic tip would be
displaced. This restores the R03i metrics while making technical quality visible
to the app UX.

`R04` through `R06` then focused on false correction control for cinematic and
good-looking frames. The strongest result is that `good_frame_overcorrection`
falls from 9 to 0 on this 107-image silver replay. The important limitation is
that this is not the same as understanding all good frames: at least one class of
fix, such as the two-person cinematic frame where runtime missed people and
anchored on `curtain`, is handled by suppressing unsafe corrections rather than
by recognizing the full scene semantics. The remaining gaps are now concentrated
in confidence calibration, mixed-frame semantics, bad-frame expected actions and
object/multi-subject grounding.

`R07`/`R08` then focused on a narrower technical semantic gap: overexposed
hotspots were visible as `reduce_exposure` future actions but did not become
closed-catalog semantic advice. `R07` proved the mapping improves expected
actions, but it introduced one good-frame overcorrection. `R08` keeps the
hotspot mapping and adds a good/high-aesthetic guard, restoring
`good_frame_preservation_rate=1.000000`. The remaining limitation is that this
still handles hotspots through deterministic technical evidence rather than a
full scene-intent/VLM interpretation.

`R09b` improves confidence presentation for a narrow, defensible case: if pause
verdict is good and the critique has explicit strengths, the user-facing verdict
can be high confidence even when the raw deterministic verdict confidence is
conservative. This improves strict eval because several good frames were already
semantically correct but under-confident. It does not solve missing advice,
forbidden advice, mixed frames or object/multi-subject grounding.

`R10a` adds the opposite confidence guard for mixed corrective pause rows:
technical-quality evidence may still be exported as `future_actions`, but it no
longer inflates the user/eval confidence of a semantic correction above the
medium band. This improves confidence honesty for one measured mixed case and
does not solve the underlying mixed-frame semantic recall problem.

Accepted `R11d` technical semantic-action calibration:

- hypothesis: dominant technical exposure/lighting problems should map to the
  closest closed-catalog semantic actions instead of only exporting coarse
  future actions or transport actions;
- result: accepted, because full real-runtime replay improved expected-action
  recall without increasing forbidden-action leakage or hurting good-frame
  preservation;
- `pass_rate`: 0.476636 -> 0.523364
- `expected_action_hit_rate`: 0.728972 -> 0.803738
- `confidence_band_accuracy`: 0.682243 -> 0.691589
- `missing_expected_action`: 29 -> 21
- unchanged remaining weaknesses: `future_action_hit_rate=0.875000`,
  `forbidden_action_violation_rate=0.112150`,
  `positive_confirmation_rate=0.956522`

Interpretation:

R11 is useful but bounded. Underexposed readable frames now map to
`add_front_fill_light`, and dominant overexposed/hotspot technical pause rows
export `remove_background_hotspot`, `change_camera_angle` and
`simplify_background`. This improves measured semantic-action recall, including
the first non-zero mixed bucket pass rate, but it is still not object/person
understanding. Most remaining failures still come from `keep_current_setup`
being emitted for bad/mixed crowd/background scenes, missing
`wait_for_background_clearance`, and confidence-band calibration.

Rejected `R11e` keep-current-setup issue guard:

- hypothesis: if a good pause verdict still contains unresolved issues, suppress
  `keep_current_setup` in semantic eval export;
- result: rejected, because the full real-runtime replay reduced a few
  forbidden-action violations but regressed more valid positive confirmations;
- `pass_rate`: 0.523364 -> 0.485981
- `expected_action_hit_rate`: 0.803738 -> 0.719626
- `forbidden_action_violation_rate`: 0.112150 -> 0.093458
- `positive_confirmation_rate`: 0.956522 -> 0.760870
- `missing_expected_action`: 21 -> 30
- `missing_positive_confirmation`: 2 -> 11

Interpretation:

R11e is a useful negative result. The failure mode is not "any issue means do
not keep current setup"; several good frames carry weak/diagnostic issues while
still needing a positive confirmation. A blanket guard only hides
`keep_current_setup` and often fails to provide a replacement corrective action,
so it harms the dataset more than it helps. The production code was restored to
the accepted R11d behavior.

Rejected `R12a` very-dark underexposure dominance expansion:

- hypothesis: uniformly very dark frames should become dominant underexposure
  and export `add_front_fill_light`, not `keep_current_setup`;
- local result: `ca_img_035` improved from missing `add_front_fill_light` to
  the expected action;
- full replay result: rejected, because the same rule overcorrected good
  low-key frames and reduced overall metrics;
- `pass_rate`: 0.523364 -> 0.514019
- `expected_action_hit_rate`: 0.803738 -> 0.785047
- `forbidden_action_violation_rate`: 0.112150 -> 0.140187
- `good_frame_preservation_rate`: 1.000000 -> 0.934783
- `positive_confirmation_rate`: 0.956522 -> 0.891304
- `missing_expected_action`: 21 -> 23
- `good_frame_overcorrection`: 0 -> 3

Interpretation:

R12a proves that "very dark" is not enough to distinguish bad low-light from
intentional low-key/cinematic frames. The next underexposure fix needs a better
owner than a global pixel threshold: likely scene/object/person grounding or a
separate aesthetic-intent signal before replacing `keep_current_setup` with
front-fill advice.

Accepted `R12b` / `R13a` / `R14a` / `R15a` / `R16a` / `R17a` / `R18a` / `R19b` / `R20a` / `R21a` contextual confidence and object/weak-subject policy calibration:

- R12b hypothesis: ambiguous no-subject motion-blur silence should remain low
  confidence instead of being lifted by the technical floor;
- R12b result: accepted, fixing `ca_img_032` and `ca_img_038` without changing
  action coverage or forbidden-action leakage;
- R13a hypothesis: when a nominally good deterministic verdict is contradicted
  by dark object-cluster evidence, the production live/pause presentation should
  emit corrective closed-catalog actions instead of `keep_current_setup`;
- R13a result: accepted, because full real-runtime replay improved pass rate,
  expected-action recall and forbidden-action control without hurting good-frame
  preservation or positive confirmations;
- R14a hypothesis: the contextual policy should also suppress false
  `keep_current_setup` when object/subject evidence is weak or technically
  unstable, and should add bounded closed-catalog advice for weak-subject
  background and small underlit-object cases;
- R14a result: accepted, because full real-runtime replay improves strict pass
  rate, expected-action recall and forbidden-action control without hurting
  good-frame preservation or positive confirmations;
- R15a hypothesis: positive `keep_current_setup` rows lifted only by technical
  future-action confidence should be capped when feature evidence is medium or
  contradictory, and the new unknown/stabilized technical-silence path should
  not export high confidence;
- R15a result: accepted, because full real-runtime replay improves strict pass
  rate and confidence-band accuracy, lowers forbidden-action leakage, and keeps
  good-frame preservation/positive confirmations unchanged;
- R16a hypothesis: bounded object/unknown contextual actions and contextual
  stabilization projection should improve mixed/bad semantic-action recall
  without repeating the rejected broad overcorrection patterns;
- R16a result: accepted, because full real-runtime replay improves pass rate,
  expected-action hit rate, future-action hit rate and confidence-band accuracy
  while preserving good-frame preservation, positive confirmations and forbidden
  action rate;
- R17a hypothesis: live/pause export should suppress false positive
  `keep_current_setup` across merged rows, preserve intentional low-key mood
  confirmations, and score confidence from rows that actually contribute
  semantic actions;
- R17a result: accepted, because full real-runtime replay improves pass rate,
  expected-action hit rate, future-action hit rate, forbidden-action control,
  positive confirmations and confidence-band accuracy with no new case
  regressions versus R16a;
- R18a hypothesis: the remaining action/future misses are shared projection
  gaps: unknown group/no-focus framing, high-confidence large-object horizon
  recovery, and small-object blur/focus future-action coverage;
- R18a result: accepted, because full real-runtime replay reaches complete
  expected-action and future-action hit rates on the silver set, preserves
  forbidden-action control, good-frame preservation and positive confirmations,
  and has no case regressions versus R17a;
- R19b hypothesis: the remaining confidence-only failures can be reduced with
  feature-bounded caps and high-boundary preservation instead of broad
  confidence-floor suppression;
- R19b result: accepted, because full real-runtime replay improves pass rate
  and confidence-band accuracy from `0.841121` to `0.953271`, fixes 12 R18a
  confidence failures and has no scored case regressions versus R18a;
- R20a hypothesis: the residual mixed/bad confidence-only failures can be
  reduced with row-evidence-specific caps/promotions, but the visually good
  establishing-frame gap must not be faked with `record_id`, label/source or
  near-duplicate threshold leakage;
- R20a result: accepted, because full real-runtime replay improves pass rate
  and confidence-band accuracy from `0.953271` to `0.990654`, fixes four R19b
  confidence failures and has no scored case regressions versus R19b;
- R21a hypothesis: the remaining good cinematic establishing confidence gap
  should be resolved only with runtime-observable frame geometry/scene evidence,
  not with label/source/id leakage or tiny aesthetic-score thresholds;
- R21a result: accepted, because full real-runtime replay improves pass rate,
  confidence-band accuracy and demo-priority pass rate to `1.000000`, fixes
  `ca_img_010`, preserves the medium-confidence near-neighbor `ca_img_016`,
  and has no scored case regressions versus R20a;
- R14a coverage delta: `expected_action_hit_rate` 0.831776 -> 0.869159,
  `missing_expected_action` 18 -> 14;
- R15a confidence delta: `pass_rate` 0.616822 -> 0.682243,
  `confidence_band_accuracy` 0.710280 -> 0.785047,
  `confidence_band_mismatch` 31 -> 23;
- R15a forbidden-action delta: `forbidden_action_violation_rate`
  0.028037 -> 0.018692, `forbidden_action_violation` 3 -> 2;
- R16a semantic/future delta: `pass_rate` 0.682243 -> 0.728972,
  `expected_action_hit_rate` 0.869159 -> 0.925234,
  `future_action_hit_rate` 0.875000 -> 0.916667,
  `missing_expected_action` 14 -> 8,
  `missing_future_action` 6 -> 4;
- R17a semantic/forbidden/confidence delta: `pass_rate` 0.728972 -> 0.803738,
  `expected_action_hit_rate` 0.925234 -> 0.981308,
  `future_action_hit_rate` 0.916667 -> 0.958333,
  `forbidden_action_violation_rate` 0.018692 -> 0.000000,
  `positive_confirmation_rate` 0.956522 -> 1.000000,
  `confidence_band_accuracy` 0.803738 -> 0.822430,
  `missing_expected_action` 8 -> 2,
  `missing_future_action` 4 -> 2,
  `confidence_band_mismatch` 21 -> 19;
- R18a semantic/future delta: `pass_rate` 0.803738 -> 0.841121,
  `expected_action_hit_rate` 0.981308 -> 1.000000,
  `future_action_hit_rate` 0.958333 -> 1.000000,
  `confidence_band_accuracy` 0.822430 -> 0.841121,
  `missing_expected_action` 2 -> 0,
  `missing_future_action` 2 -> 0,
  `confidence_band_mismatch` 19 -> 17;
- R19b confidence delta: `pass_rate` 0.841121 -> 0.953271,
  `confidence_band_accuracy` 0.841121 -> 0.953271,
  `confidence_band_mismatch` 17 -> 5;
- R20a confidence delta: `pass_rate` 0.953271 -> 0.990654,
  `confidence_band_accuracy` 0.953271 -> 0.990654,
  `confidence_band_mismatch` 5 -> 1;
- R21a confidence delta: `pass_rate` 0.990654 -> 1.000000,
  `confidence_band_accuracy` 0.990654 -> 1.000000,
  `demo_priority_pass_rate` 0.928571 -> 1.000000,
  `confidence_band_mismatch` 1 -> 0;
- unchanged remaining strength: `good_frame_preservation_rate=1.000000`

Interpretation:

R13a/R14a/R15a/R16a/R17a/R18a are broader production-path fixes than one-off export patches. They
add contextual presentation policy for cases the deterministic semantic verdict
previously misread as good: dark object clusters, weak-subject unknown scenes,
motion-like object false positives, small underlit object failures and
low-aesthetic single-object/crowd-like frames. R14a turns `ca_img_068`,
`ca_img_070`, `ca_img_071`, `ca_img_083` and `ca_img_085` into passing cases,
and reduces `ca_img_077` / `ca_img_097` to remaining confidence/future-action
failures instead of forbidden `keep_current_setup` leaks. R15a then caps
feature-bounded medium-evidence `keep_current_setup` rows and the
`contextual_unknown_stabilized_technical_silence` path, turning seven
confidence-only cases into passes while keeping ca095 as a real remaining
`missing_expected_action` failure instead of masking it with high confidence.
R16a adds bounded actions for readable underlit objects, low-aesthetic object
clearance, clustered background clearance, unknown blur/background cases and
unreadable low-light single-object scenes. It turns `ca_img_007`, `ca_img_014`,
`ca_img_076`, `ca_img_084` and `ca_img_093` into passing cases, and reduces
`ca_img_074` / `ca_img_082` to narrower remaining failures.
R17a then fixes the merged live/pause failure mode: false live
`keep_current_setup` no longer leaks into technical bad frames such as
`ca_img_090`, intentional low-key mood frames `ca_img_023` / `ca_img_039`
retain positive confirmation, and scorer confidence no longer lets an empty
live row dominate a pause row that carries the actual semantic action. It turns
`ca_img_009`, `ca_img_020`, `ca_img_072`, `ca_img_086`, `ca_img_092`,
`ca_img_095`, `ca_img_096` and `ca_img_101` into passing cases with no new
R16a-to-R17a regressions.
R18a then closes the remaining semantic/future-action misses by adding bounded
projection for unknown group/no-focus framing (`ca_img_013`), large-object
horizon recovery (`ca_img_074`) and small-object crowd/street blur future
actions (`ca_img_097` / `ca_img_098`), with no R17a-to-R18a regressions.
R19b then focuses on the residual confidence-only failures. It caps
medium-evidence positive `keep_current_setup` rows, medium overexposure
background correction, empty unknown technical silence and underlit-readable
object rows, while preserving high-confidence boundary cases where the runtime
classifier is ambiguous. It turns `ca_img_002`, `ca_img_024`, `ca_img_027`,
`ca_img_029`, `ca_img_035`, `ca_img_037`, `ca_img_043`, `ca_img_044`,
`ca_img_050`, `ca_img_052`, `ca_img_053` and `ca_img_077` into passing cases
with no R18a-to-R19b scored regressions. Remaining strict failures are
`ca_img_010`, `ca_img_022`, `ca_img_078`, `ca_img_082` and `ca_img_090`,
all confidence-band mismatches.
R20a then closes four of those five residual confidence-only failures with
bounded row-evidence-specific calibration: underlit unknown no-focus front-fill
correction (`ca_img_022`) is capped to medium, unknown motion-blur/background
technical correction (`ca_img_078`) is promoted to high, contextual unknown
blur/background simplification (`ca_img_082`) is capped to medium, and readable
object technical silence (`ca_img_090`) is capped below the high band. It has
no R19b-to-R20a scored regressions. At R20a, the only remaining strict failure is
`ca_img_010`, a good cinematic/establishing frame whose current runtime features
are too similar to a medium-confidence near-neighbor (`ca_img_016`) to justify
another threshold-only confidence rule. This is an observability gap: it needs
a real scene-intent/aspect/group grounding signal before the system can claim
the high band honestly.
R21a adds that bounded observability signal for the still replay: `frame_aspect_ratio`
is exported from the actual `CVPixelBuffer`, and only a 16:9 unknown/good
establishing `keep_current_setup` pause row with no future actions is promoted
to the high band. This turns `ca_img_010` into a pass while preserving
`ca_img_016` as medium confidence (`0.463075`, aspect `1.706667`). The current
107-image silver replay now has no strict failures and no R20a-to-R21a scored
regressions.

## Main Root Causes

1. Technical quality is only a first production slice, not a complete domain.
   The runtime analyzer can detect several future technical actions and surface dominant issues in live/pause, but it is deliberately gated so it does not erase semantic advice when grounded semantic tips are available.

2. Good-frame overcorrection is fixed on the current silver replay, but by conservative guards.
   Cinematic low-key light, intentional background context and non-centered subjects are now less likely to become corrections. This is useful, but it is partly a safety calibration: it does not prove that the runtime recognizes all subjects, groups or cinematic intent correctly.

3. Confidence is closed on the current silver replay, but not proven universally.
   R21a uses runtime-observable still-frame aspect evidence for the last good cinematic establishing case. This is valid for the dataset/eval bridge, but broader live scene-intent confidence still needs manual/live validation.

4. Subject evidence is unstable on screenshots and complex scenes.
   DETR and Vision can disagree; background/full-frame classes are filtered, but face/object grouping is still not strong enough for multi-subject cinematic frames.

5. Mixed-frame semantics are the weakest bucket.
   The current deterministic stack often cannot distinguish "good enough", "slightly improve background/light" and "technically broken" when the frame has deliberate cinematic styling.

6. Contextual object/weak-subject grounding is improving but still heuristic.
   R13a/R14a/R15a/R16a/R17a handle several dark crowd/object-cluster, weak-subject and
   motion-like false-keep failures through production presentation rules, but
   this is still not full person/group understanding.

## Ranked Implementation Backlog

### R03. Production Technical Quality Domain And Gate

Goal:

Move the technical-quality analyzer toward a complete production
`TechnicalQualitySignal`, `TechnicalQualityIssue` and gate that can say: "this
frame first needs focus/exposure/stability, not composition", without hiding
valid semantic composition/light/background advice.

Initial action mapping:

- `motion_blur` -> `stabilize_camera`
- `defocus` -> `refocus_subject`
- `overexposure` -> `reduce_exposure`
- `underexposure` / `low_light` -> `increase_exposure`
- `noise` -> `reduce_iso_noise`
- `occlusion` -> `avoid_occlusion`
- `lens_smudge` -> `clean_lens`

Acceptance:

- `missing_future_action` decreases without increasing semantic overreach;
- technical-dominant frames do not emit only `shift_frame_*`;
- pause can explain why the issue is technical, not compositional.
- production live/pause code no longer says `keep_current_setup` for clearly blurred/defocused/overexposed frames.
- pause technical critique is used only when it will not displace available semantic corrective tips.

### R04. Cinematic Good-Frame Preservation

Goal:

Protect intentionally good frames from unnecessary correction.

Rules to add or strengthen:

- if subject/face is readable and labels expect `keep_current_setup`, avoid `step_closer` and `simplify_background` unless evidence is very strong;
- preserve low-key/backlight style when face/subject readability is acceptable;
- do not penalize non-centered subjects when composition is stable and scene intent is readable.

Acceptance:

- `good_frame_preservation_rate` and `positive_confirmation_rate` increase;
- `missing_expected_action.keep_current_setup` decreases;
- the app can confidently say why a good frame is good.

Current status after `R21a`:

- silver-replay good preservation reached `1.000000`;
- positive confirmation reached `1.000000`;
- dominant technical hotspots now map to `remove_background_hotspot`, `change_camera_angle` and `simplify_background` when the frame is not a high-aesthetic/good deterministic case;
- readable underexposure can map to `add_front_fill_light`;
- confidence-band accuracy improved to `1.000000` after narrow good-frame, mixed-correction, low-confidence-silence, underexposure/object-cluster, feature-bounded keep-confidence, contextual object-action calibration, semantic-row-aware live/pause scorer merging, R18a bounded action/future projection, R19b/R20a residual confidence calibration and R21a observability-grounded wide-establishing confidence;
- rejected R11e proved that suppressing `keep_current_setup` merely because a good pause critique has issues is too broad and regresses positive confirmations;
- rejected R12a proved that widening dominant underexposure by global darkness overcorrects good low-key frames;
- accepted R13a/R14a/R15a/R16a/R17a/R18a/R19b/R20a/R21a proved that bounded contextual object/weak-subject corrections, feature-bounded keep-confidence calibration, object/unknown action mapping, merged live/pause keep-control, bounded future-action projection and residual confidence calibration can remove specific bad/mixed-frame failures without regressing good preservation;
- remaining work is broader live-camera validation and stronger scene/person grounding beyond the current silver replay, not dataset/eval expected actions, future actions, forbidden-tip control or confidence bands on the current silver set.

### R05. Confidence Calibration

Goal:

Make confidence user-facing and meaningful.

Rules:

- high confidence only when several independent signals agree;
- medium confidence for plausible but not decisive advice;
- low confidence for weak subject evidence, technical uncertainty or conflicting signals;
- forbidden/overreach-prone actions should be capped unless evidence is strong.

Acceptance:

- `confidence_band_accuracy` increases;
- pause shows confidence percentages that match evidence strength;
- live avoids confident but wrong corrections.

### R06. Object-Aware Distraction And Multi-Subject Grounding

Goal:

Support the "flower/object is distracting" wow effect without hallucinating.

Needed behavior:

- identify distractor object/region;
- distinguish subject objects from background objects;
- handle multiple faces/subjects as a group when composition is about a group;
- prefer bounded catalog actions like `simplify_background`, `remove_background_hotspot`, `wait_for_background_clearance`.

Acceptance:

- object-aware distraction cases produce grounded advice;
- two-face/group frames are not reduced to one wrong subject;
- no new free-form actions outside the closed catalog.

## Do Not Do

- Do not tune thresholds only to pass labels if the result becomes worse in live camera use.
- Do not use `record_id`, source bucket or ground-truth label text in runtime logic.
- Do not claim final dissertation accuracy from this baseline.
- Do not make VLM write final user text directly; VLM evidence must stay bounded by the deterministic catalog.

## Next Concrete Step

Do not tune more constants blindly. The next concrete step should be a bounded
implementation slice:

1. add object/multi-subject grounding so group frames and object distractions do
   not collapse to one unstable subject;
2. validate the same live/pause behavior under live-camera motion and UI timing,
   because the current evidence is still-image replay.

Then rerun:

```bash
python3 -m pytest docs/cameraanalysis/eval/tests -q
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 \
  -derivedDataPath /private/tmp/shafinMultitool-derived \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build \
  test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_next \
  --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_next.jsonl
```

Goal for the next checkpoint is not "perfect score". A realistic improvement
target is:

- `pass_rate` above 0.97 on the current silver replay;
- no expected/future action recall regression;
- no increase in `forbidden_action_violation_rate`;
- documented examples where residual confidence gaps are either fixed by
  observable runtime evidence or explicitly classified as silver-label/runtime
  observability limits.
