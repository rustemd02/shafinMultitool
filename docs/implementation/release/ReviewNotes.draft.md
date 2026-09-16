# Review notes (draft, not submitted)

Status, 2026-09-16: technical draft; not ready to paste into App Store Connect.
The final signed archive, configured service and physical acceptance are still
open. Nothing here has been submitted and no App Store Connect access was used.

## What the app does

Shafin Multitool is a camera coach. In Camera mode it analyses the live frame on
device and presents a coaching suggestion when the available evidence supports it.
The intended Scene flow turns a written description into a staged shot list that
the user can save and work with locally. Configured cloud Scene generation uses
the app's backend and provider; local fallback is a separate capability and does
not establish equivalent generation quality. There is no user-account sign-in;
backend access uses installation authentication through App Attest.

## What the reviewer needs

1. **Camera.** The camera is the core surface; the app asks for camera access on
   first use of Camera mode and explains why in the system prompt. Microphone,
   Speech and Photos (add-only) are requested only for their own features
   (recording with sound, spoken scene input, saving a finished video).
2. **No account.** Every feature is reachable without sign-in. Nothing needs to be
   purchased to reach the coaching surface.
3. **Processing and network use.** Camera frames are analysed locally through
   Vision, the bundled Core ML baselines and the existing planner. The current
   Release excludes the research Camera cloud-evidence path. Spoken scene input
   can use Apple's Speech service. Configured cloud Scene generation sends the
   scene request to the authenticated HTTPS backend; its actual provider and
   qualified retention policy must match the final privacy disclosures.
4. **Silence is a designed state.** When the engine is not confident it shows no
   advice instead of guessing. A missing suggestion is the intended behaviour on
   ambiguous frames, not a failure.

## Archive configuration that must be replaced before submission

The unsigned engineering archive produced at `20260916T152044616359Z` has an empty
`SETOSSceneBaseURL`; its remote Scene route is unavailable. It contains DETR and
NIMA baselines and excludes the research composition checkpoint and GGUF payloads.
This archive predates the full Camera recording/current-pixel tracking package.
It is useful build evidence, not the final working generation or distribution
artifact. Do not present an unavailable cloud route as a completed offline flow.

Evidence: `../setos-backend/local-data/SETOS/verification/release-execution-20260916/`
`20260916T152044616359Z-release-archive/` and the subsequent
`20260916T152455588085Z-archive-validator-repair/` receipt. The repaired bundle gate
reports ten unresolved component provenance rows; it does not approve distribution.

## Known limitation to verify before writing final notes

The simulator has no camera feed, so the full camera flow cannot be exercised
there. The owner still has to run the physical-device pass (first launch,
permission denial, offline, recording, thermal and background behaviour) before
any submission; gate 11 of the product plan is open and is not substituted by
simulator evidence.

## Open items before this draft can be submitted

- Support URL, marketing URL and the hosted privacy policy (gate 5).
- Screenshots for the required sizes, captured after the flows are final.
- Name, subtitle and price: owner decisions held until beta evidence, per the
  product plan.
- Legal review of the bundled models and assets (the NIMA provenance in the model
  spec is incomplete).
