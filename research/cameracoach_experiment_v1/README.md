# CameraCoach Experiment v1 — 2026-11-11

Research-only diagnostics, not a new VLM, iPhone or human study. No production code changed. No trained CameraCoach weights. No claim of scientific novelty.

## Observed results in the ChatGPT Linux run

174 original tracked images decoded; 139 existing label hashes match and 35 missing hashes measured separately. 1,089 snapshot/supplement files hash-verified. No exact image duplicates; known source families still cross the old train/test boundary.

On the historical 122/52 quality-classification split: majority 24/52; coarse source origin only 42/52; source sampling stratum only 48/52; aesthetic_score-only logistic 40/52; 27-feature logistic 33/52; exact legacy softmax 35/52 at lr=.05 and 39/52 at default lr=.5. These predict good/mixed/bad, NOT intent or action utility. Source-stratum names partly encode the selection policy; their score is a confounding control, not a deployable competitor or evidence that the app uses source metadata.

264 method/protocol combinations were computed: 8 fixed split, 6 methods x 20 seeds x 2 split schemes, 4 methods x 4 held-out origins. Reused splits are not independent experimental samples. Seven direct parent/derivative edges cross the old split; conservative title grouping gives nine overlapping known families. Grouping does not explain all performance: 27-feature mean accuracy was 64.06% stratified and 63.80% grouped. Unknown shoot-level dependence may remain.

Four sets of saved recommendation outputs were rescored exactly. The historic 90.8046% expected-action hit was reproduced, but this is NOT a fresh runtime result. The all-actions negative control gets 100% hit and 100% forbidden-action rate; combined pass correctly stays zero. An empty explicit response gets 100% good-frame preservation but zero overall pass. Missing/duplicate/unknown-action responses are rejected. `strict_visible` projects shown rows before unioning modes; empty expected-label cases do not give free recall.

Current confidence thresholds are not established action-utility probabilities. At threshold zero, 18/174 records fail historical semantic criteria excluding the confidence band; at .8, 6/43 fail. No threshold or rare-risk certificate is selected from these exposed data.

Local validation: 70 new tests + 109 old evaluator tests + 45 CC21 fixture tests pass; Chromium UI smoke passed separately on manufactured solid-color images. Main 18 output files reproduced byte-for-byte. No independent subagents ran: the local tunnel was unavailable. No VLM APIs or real raters were used. Historical 4,889-row proof reports were inspected, but their encrypted payload was not restored or newly evaluated.

## Code and reproducibility

`src/run_experiment.py` trains small diagnostic linear classifiers on saved features and rescores saved outputs. `src/additional_checks.py` verifies media and runs source-held-out stress tests. `src/metrics.py` implements explicit metric denominators. `src/pilot.py` exports before-only requests, builds blinded A/B review HTML and aggregates REAL supplied ratings. `src/uncertainty.py` implements descriptive paired family bootstrap, not rare-risk certification.

Use immutable inputs in a directory containing `store/` at 93f5daa3c91d791c5a5230f6731a359d74dd2946 and `data/` at ce9344d83e81d0950af1935fcf305eab5cb61306. Do not replace them with moving branch heads. The included GitHub workflow checks out these exact refs and saves numerical results/logs as an artifact.

```sh
python -m pip install -r research/cameracoach_experiment_v1/requirements.txt
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 python research/cameracoach_experiment_v1/src/run_experiment.py --snapshot /path/to/inputs --out /path/to/results
OPENBLAS_NUM_THREADS=1 python research/cameracoach_experiment_v1/src/additional_checks.py --snapshot /path/to/inputs --out /path/to/results
python -m pytest research/cameracoach_experiment_v1/tests -q
```

## Real pilot boundaries

First collect repeatable development scenes with an explicitly frozen brief and two physically executed camera translations. Candidate catalog: camera_left, camera_right, keep, abstain. Keep/goal_satisfied differs from keep/no_feasible_improvement and abstain/insufficient_evidence. Input packets whitelist before-image, brief, constraints and available actions; future images and ratings stay separate. This is a data-format separation, NOT an OS sandbox: an external model adapter must run in an isolated environment without verifier files.

Use `pilot.py --help` for requests, review, aggregate and evaluate commands. Three independently participating human raters should compare each action result against the initial frame relative to the brief. A/B order is randomized; model identity and advice text are absent. Votes remain individually retained. Insufficient votes, protocol deviations and lack of majority become unknown, NOT safe. The software validates declarations but cannot authenticate independence or competence of raters. No provider-specific VLM adapter is bundled or claimed tested.

40 development families are a feasibility study, not a powered superiority test. Two briefs per family do not double independent N. Compare a proposed method with strong VLM+brief+catalog+abstention and standard decision/geometric methods at equal information/budget. Do not justify novelty solely by adding intent or a confidence threshold.
