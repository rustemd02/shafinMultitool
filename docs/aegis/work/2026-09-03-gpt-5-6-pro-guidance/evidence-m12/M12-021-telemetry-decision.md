# M12-021 — Camera telemetry decision

Status: **closed on the current store**.

## Decision (locked)

- No camera frame, crop, face box, audio sample, or derived visual
  embedding leaves the device. The only network-capable code on the Camera
  path is the DEBUG-gated remote VLM seam (M12-002); Release cannot
  construct it.
- Local diagnostics are bounded and redacted: `Telemetry` writes to local
  `OSLog` + in-memory `@Published` metrics only (no URLSession, no upload
  task — grep-verified); recording diagnostics are the versioned 200-event
  redacted ring with explicit user export (M7-030).
- Any future upload is POST_1_0: it requires the deployed backend service
  (M12-002 boundary), approved policy, and explicit user consent — none of
  which exist in this build.
