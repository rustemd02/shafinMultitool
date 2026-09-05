# M7-030 — recording diagnostics

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

New `Services/Recording/RecordingDiagnostics.swift` — a bounded, versioned,
redacted diagnostics owner for the recording engine:

- **Schema**: `RecordingDiagnosticsEvent` (schema version 1, timestamp,
  recording identity UUID, typed `Kind`). Kinds cover lifecycle state
  changes (canonical M1-010 state names), terminal stop outcomes, admission
  counters (accepted/rejected by reason), backpressure drops, the
  drop-policy firing, storage pressure, disk-budget verdicts (byte
  magnitudes only), A/V sync criterion results, and recovery
  classifications.
- **Redaction**: only typed enumerations, counters, durations, and UUIDs are
  representable. There is no field that could carry frame pixels, audio
  samples, screenplay text, or file paths — a JSON export of a full event
  set contains no `/` characters (path-shaped strings are structurally
  impossible).
- **Bounded**: fixed-size ring (default 200 events, oldest evicted first).
  Emission is a locked O(1) append called from the recorder queue — it never
  blocks the recording critical path.
- **Export**: explicit `exportedEvents()` returns the typed events for the
  test harness / user-triggered export; `Codable` round-trip is proven.
- **Integration**: `SerializedMediaRecorder` accepts an optional
  `RecordingDiagnosticsEmitting` sink (production binds
  `RecordingDiagnosticsLog.shared` at the controller factory; nil = silent)
  and emits lifecycle, terminal, storage-pressure, and drop-policy events.

## Acceptance criteria evidence

| Criterion | Evidence (RecordingDiagnosticsTests) |
|---|---|
| Versioned + schema | `testRingBufferIsBoundedAndOrdered` asserts schema version on every event; `testEventsCarryOnlyTypedFieldsAndNeverPayloads` proves the Codable round-trip. |
| Redaction | Same test asserts the JSON export contains no `/` and no container-extension strings. |
| Size cap | `testRingBufferIsBoundedAndOrdered` (40 emissions → 16 retained, ordered). |
| No media content | Structural: the typed schema has no content-carrying field (asserted by the redaction scan). |
| Production-owner emission | `testSerializedRecorderEmitsLifecycleAndTerminalDiagnostics` (canonical state sequence + exactly one terminal event with the recording identity), `testStoragePressureAndDropPolicyAreEmitted`. |

## Narrow verification

Package D focused run: **16/16 PASS** (xcresult
`/private/tmp/m7-pkgD-tests-r3.xcresult`). `git diff --check` clean.
