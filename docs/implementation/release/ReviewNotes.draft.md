# Review notes (draft, not submitted)

Status: draft for the owner to edit and paste into App Store Connect. Nothing here
has been submitted, and no App Store Connect access was used.

## What the app does

Shafin Multitool is a camera coach. In Camera mode it analyses the live frame on
device and shows at most one actionable suggestion ("what is hurting this frame,
and what to do about it"). In Scene mode it turns a written scene description into
a staged shot list and keeps the material locally. There is no account and no login.
The app has no server dependency for camera or scene processing, except that spoken
scene input uses Apple's Speech service, which may process the microphone audio on
Apple's servers; nothing is sent to a developer-operated server in this
configuration.

## What the reviewer needs

1. **Camera.** The camera is the core surface; the app asks for camera access on
   first use of Camera mode and explains why in the system prompt. Microphone,
   Speech and Photos (add-only) are requested only for their own features
   (recording with sound, spoken scene input, saving a finished video).
2. **No account.** Every feature is reachable without sign-in. Nothing needs to be
   purchased to reach the coaching surface.
3. **On-device processing.** Frames are analysed locally (Apple Vision, bundled
   Core ML models, a deterministic critique engine). Spoken scene input is the one
   exception: it is processed by Apple's Speech service, which may receive the audio
   on Apple's servers (the app's own Speech usage string says so). The remote Scene
   provider is fail-closed off in this build: without an explicitly configured HTTPS
   endpoint and App Attest, the app makes no request to it, and the remote
   visual-evidence provider cannot be constructed in a Release build at all.
4. **Silence is a designed state.** When the engine is not confident it shows no
   advice instead of guessing. A missing suggestion is the intended behaviour on
   ambiguous frames, not a failure.

## Known limitation to declare honestly

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
