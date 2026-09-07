# M12-024 — runtime egress audit evidence

Status: CLOSED on the current store.

## Verdict

No production runtime egress exists in the 1.0 binary. The M5-025
`SceneGenerationClient` is implemented and tested but NOT constructed
anywhere in production (zero call sites outside its own file); the
offload seam stays off (`SceneParserService.configureRemoteOffload`
has zero callers; `remoteOffloadEnabled` defaults false); the only
other network use (Remote VLM provider) is `#if DEBUG`-gated and
unreachable in Release (M12-002); no iCloud/CloudKit APIs or
entitlements exist (M12-023).

## Audit (this session)

- `SceneGenerationClient(` — zero production construction sites.
- `configureRemoteOffload` — zero callers outside the parser service
  definition; no production path enables remote offload.
- Entitlements: no `.entitlements` file exists in the repo — no push
  notification, associated domain, or network-extension entitlement
  that could add an egress route.
- The client's default configuration points at the M12-003
  placeholder host; even a hypothetical mis-wire cannot reach a real
  backend until deployment config supplies one.

## Boundary

Runtime network-proxy verification on device remains M13; the
deployed-service egress posture is M12-019/020 (external until the
service exists).
