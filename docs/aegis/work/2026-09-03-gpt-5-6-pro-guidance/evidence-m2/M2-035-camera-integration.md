# M2-035 — Camera integration tests

Status: **verified on the current store; no production change required**.

Representative cases execute through production owners (manager →
scheduler → pipeline → subject/episode/verifier), not mocks of the final
planner/verifier: subject selection through stabilized episodes, scene
identity under noise/motion/cut, corrective + abstention capture paths,
automatic verification of corrective episodes, scene-cut sample fencing.
Protected cases assert fail-closed owner decisions and production-owned
neural/movement/verification seams.

Verification: `CameraCoachClosedLoopTests` 8/8 on permitted iPhone 17e
(`/private/tmp/m2-035-tests.xcresult`).
