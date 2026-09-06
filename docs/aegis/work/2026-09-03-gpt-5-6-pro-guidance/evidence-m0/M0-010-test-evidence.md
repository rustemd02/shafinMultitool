# M0-010 — test evidence

Status: **closed on the current store**.

`evidence-m0/test-topology-v2.json` tags all 125 suites (1474 tests):
unit/integration/UI by structural rule, plus simulator/device/
research-gated markers; device, release, and research lanes are explicit
with documented prerequisites (hardware, signed build, eval corpus).
Historical results are `available` where a durable xcresult exists in this
lane's receipts, `missing`/`partial`/`stale` otherwise per the per-task
evidence files — no result is inferred.
