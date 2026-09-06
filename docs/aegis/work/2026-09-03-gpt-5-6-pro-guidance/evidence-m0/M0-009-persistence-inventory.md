# M0-009 — persistence inventory

Status: **verified on the current store; no production change required**.

| Record | Schema/version | Owner | Location | Backup | Migration | Deletion path |
|---|---|---|---|---|---|---|
| UnifiedSceneProject | v1 envelope (`UnifiedSceneProjectFile`) | DBService (serial queue) | UnifiedSceneProjects/ | included (user data) | v0 raw preserved until legitimate save; future rejected | lease-guarded staged delete |
| ARWorldMap (archived) | NSKeyedArchiver, secure coding | DBService | alongside project | included | legacy sidecar removed on save | with project |
| Recording artifact (project) | SceneRecordingReference (relative path) | RecordingArtifactStore | Recordings/Projects/<uuid>/ | included (user media) | n/a (content-addressed by recording ID) | staged project delete |
| Recording artifact (pending) | PendingRecordingJournalEntry | RecordingArtifactStore | Recordings/Pending + Journal | **excluded** (transient) | n/a | retention/orphan sweeps |
| SceneData legacy | legacy map/data files | DBService | Scenes/ | included | read-compat preserved | legacy deleteMap |
| Settings/preferences | UserDefaults keys | CameraScreenInteractor | app defaults | system-managed | zero→default fallback | n/a (no deletion) |

Verified by DBServiceConcurrencyTests, SceneSaveLoadTests,
RecordingRecoveryAndRetentionTests, and the M5-014/M7-019…021 suites.
