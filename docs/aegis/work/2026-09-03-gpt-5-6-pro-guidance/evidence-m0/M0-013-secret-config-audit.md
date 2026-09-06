# M0-013 — secret/config audit

Status: **closed on the current store**.

## Classification (every secret/config input)

| Input | Class | Evidence |
|---|---|---|
| `CAMERA_VLM_VISUAL_EVIDENCE_ENDPOINT` / `CAMERA_VLM_VISUAL_EVIDENCE_API_KEY` (env) | runtime secret (DEBUG evaluation only) | never in repo; remote branch `#if DEBUG`-gated (M12-002); absent in Release |
| `CAMERA_VLM_VISUAL_EVIDENCE_PROVIDER`, `CAMERA_REASONING_PROVIDER` (env selectors) | local-development config | plain strings, no credential value |
| `UserDefaults` keys (resolutionWidth, framerate, whiteBalance, iso, …) | public local config | device settings, no secrecy |
| `DEVICE_BENCHMARK_CONFIG_BASE64` (env) | local-development config | test-harness input, never a credential |
| App bundle ID, team references, Info.plist keys | public | shipped metadata |

## Forbidden-in-client

No API key, token, password, or private-key value exists in the app
target, tests excluded (grep-verified: only `llama_token`/tokenizer
vocabulary and request UUIDs match `token`, all non-credential). No
credential value is copied into this evidence.
