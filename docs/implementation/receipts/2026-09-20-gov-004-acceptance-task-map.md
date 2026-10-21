# GOV-004 — Acceptance A–L → tracker task map

Date: 2026-09-20. Source contract: `docs/implementation/PRODUCTION_ACCEPTANCE.md` (unchanged). Target: `docs/implementation/APP_STORE_RELEASE_TRACKER.md` task IDs.

Rule: every gate below has task owners; every P0 tracker task serves at least one gate. Only additions that were genuinely missing were made — none required; the tracker already covers A–L except the explicit deferrals noted for Gates I/J.

| Gate | Scope | Owning tracker tasks |
|---|---|---|
| A — product/scope integrity | Coach default route; free local loop; Scene secondary; saved scenes; traceability | BASE-001, GOV-002 (Scene stays, held), CAM-012, CAM-013, UI-001, UI-003, UI-011, DEV-010, REL-011 final audit |
| B — functional end-to-end | permissions, live coach loop, pause/resume, rotation, lifecycle, recording, offline/timeout/quota, Scene create/reopen | UI-006, DEV-002, DEV-003, UI-004, DEV-004, UI-009, DEV-005, DEV-008, DEV-009, BE-012, UI-010, DEV-006, UI-011, CAM-022 |
| C1 — dataset structure | regression/locked_holdout/live_device layers, coverage, leakage | DATA-001…DATA-016 (key: DATA-003 inventory, DATA-004 coverage matrix, DATA-012/014 frozen splits, DATA-016 package) |
| C2 — still-image full-runtime gates | locked holdout thresholds (pass ≥0.90, forbidden ≤0.02, good-frame ≥0.95…) | ML-006, ML-007, ML-008, ML-009, ML-010, ML-018; runtime behavior CAM-007…CAM-012 |
| C3 — live sequence gates | first advice p50≤3s/p95≤8s, single action, verified completion | DEV-003, DEV-005, ML-016, ML-011, CAM-021, CAM-022 |
| D — Scene generator quality | parser artifact provenance, fresh benchmark thresholds, 30 locked prompts | BE-006, BE-007, BE-011, BE-013, DEV-006, DATA-016 (training package where applicable) |
| E — UI/UX and accessibility | states, no dead ends, orientation, VoiceOver/Dynamic Type, golden screenshots, beta 85% loop completion | UI-001…UI-014, BETA-003/BETA-006 |
| F — reliability/performance/device | device matrix, soaks, memory/thermal, crash-free ≥0.995 | DEV-001, DEV-005, DEV-012, ML-016, ML-017, BE-014, BETA-003 |
| G — tests/reproducibility | focused + full suites, release gates from clean HEAD, real UI target, archive+validate | CAM-001, CAM-022, REL-001, REL-002, REL-003, REL-005, REL-006, UI-test target work under REL-001/REL-003 |
| H — privacy/security/provenance/legal | all shipped artifacts verified/replaced/excluded; privacy answers; negative security tests | SEC-001…SEC-012, SEC-006 (4 PENDING), SEC-007, BE-004, BE-008, BE-009, BE-010, ML-014, ML-015, REL-006, DEV-001 (signing), BASE-004 |
| I — Deep Review economics | out of 1.0 scope | POST-001 `DEFERRED` (BASE-014/metadata record exclusion). Gate N/A for 1.0 unless owner re-scopes; would require new P0 tasks |
| J — monetization | out of 1.0 scope; delayed monetization must be an explicit recorded decision | POST-003 `DEFERRED`; explicit delayed-monetization acceptance recorded in BETA-007 release decision + REL-008 metadata consistency |
| K — external beta | 15–20 users, ≥200 sessions, ≥85% loop completion, no open P0/P1 | BETA-001…BETA-008 (BETA-002 owner-blocked) |
| L — submission readiness | clean archive+validate, metadata, privacy, review notes, final review | REL-004…REL-013, SEC-005, REL-008, REL-009, REL-010, UI-013, UI-014 |

## Coverage verdict

- No acceptance gate lacks a task owner.
- No P0 tracker task exists outside gates A–L.
- Gates I/J are scope-deferred (BASE-014, POST-001/003); both require explicit owner-recorded decisions at BETA-007 before submission (already enforced by BETA-007 + REL-008 checks).
- Physical/legal/commercial dependencies remain inside the owner-blocked tasks listed in tracker §19.
