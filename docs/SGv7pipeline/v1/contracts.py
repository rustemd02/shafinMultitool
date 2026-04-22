from __future__ import annotations

from typing import Any, NotRequired, TypedDict


class ScriptOffsetRangeRecord(TypedDict):
    start: int
    end: int


class NormalizedScriptUnitRecord(TypedDict):
    id: str
    kind: str
    text: str
    lineIndex: int
    charRange: ScriptOffsetRangeRecord


class SceneTopLevelMetadataRecord(TypedDict):
    sceneHeading: NotRequired[str | None]
    locationName: NotRequired[str | None]
    interiorExterior: NotRequired[str | None]
    timeOfDay: NotRequired[str | None]


class ScriptSceneCandidateRecord(TypedDict):
    id: str
    sceneIndex: int
    heading: NotRequired[str | None]
    sourceText: str
    metadata: SceneTopLevelMetadataRecord
    isImplicit: bool


class SourceAnchorBundleRecord(TypedDict):
    actor_count_hint: int
    ordinal_mentions: list[str]
    mentioned_marked_objects: list[str]
    object_surface_mentions: list[str]
    phase_cues: list[str]
    unsupported_action_flags: list[str]
    same_type_marker_conflict: bool
    low_confidence_flags: list[str]


class SceneChunkAnchorRecord(TypedDict):
    sourceBundle: SourceAnchorBundleRecord
    speakerCues: list[str]
    actorMentions: list[str]
    objectMentions: list[str]
    markedObjectMentions: list[str]
    pronounMentions: list[str]
    chronologyCues: list[str]
    locationCues: list[str]
    timeCues: list[str]
    uncertaintyFlags: list[str]


class ScenePlanIRRecord(TypedDict):
    actors: list[dict[str, Any]]
    objects: list[dict[str, Any]]
    beats: list[dict[str, Any]]
    spatialRelations: list[dict[str, Any]]
    referenceBindings: dict[str, Any]


class SceneEntityRegistrySnapshotRecord(TypedDict):
    actors: list[dict[str, Any]]
    objects: list[dict[str, Any]]
    actorAliasMap: dict[str, str]
    objectAliasMap: dict[str, str]
    speakerAliasMap: dict[str, str]
    unresolvedMentions: list[str]
    lastResolvedSpeaker: NotRequired[str | None]
    locationName: NotRequired[str | None]
    actorPoses: dict[str, str]
    heldObjects: dict[str, str]


class SceneDeferredRefRecord(TypedDict):
    id: str
    localRef: str
    kind: str
    alias: NotRequired[str | None]
    sourceText: NotRequired[str | None]


class SceneChunkDraftRecord(TypedDict):
    sceneID: str
    chunkID: str
    chunkIndex: int
    sourceText: str
    sourceRange: ScriptOffsetRangeRecord
    anchors: SceneChunkAnchorRecord
    registrySnapshot: SceneEntityRegistrySnapshotRecord
    plan: ScenePlanIRRecord
    usedFallbackPlanner: bool
    usedLegacyPlanBridge: bool
    confidence: float
    unresolvedMentions: list[str]
    reasonCodes: list[str]


class SceneChunkRecord(TypedDict):
    sceneID: str
    chunkID: str
    chunkIndex: int
    sourceText: str
    sourceRange: ScriptOffsetRangeRecord
    anchors: SceneChunkAnchorRecord
    registryPatch: dict[str, Any]
    beatPatch: list[dict[str, Any]]
    spatialRelationPatch: list[dict[str, Any]]
    stateDelta: dict[str, Any]
    deferredRefs: list[SceneDeferredRefRecord]
    reasonCodes: list[str]
    usedFallbackPlanner: bool
    usedLegacyPlanBridge: bool


class SceneStitchStateRecord(TypedDict):
    sceneID: str
    sceneIndex: int
    sourceText: str
    metadata: SceneTopLevelMetadataRecord
    registry: SceneEntityRegistrySnapshotRecord
    actors: list[dict[str, Any]]
    objects: list[dict[str, Any]]
    beats: list[dict[str, Any]]
    spatialRelations: list[dict[str, Any]]
    chunkLedger: list[str]
    deferredRefs: list[SceneDeferredRefRecord]
    continuityDiagnostics: list[str]


class SceneBundlePlanSceneEntryRecord(TypedDict):
    sceneID: str
    sceneIndex: int
    sourceText: str
    metadata: SceneTopLevelMetadataRecord
    chunks: list[SceneChunkRecord]
    diagnostics: list[str]
    plan: ScenePlanIRRecord


class SceneBundlePlanRecord(TypedDict):
    bundleID: str
    scenes: list[SceneBundlePlanSceneEntryRecord]
    activeSceneIndex: int
    diagnostics: list[str]


class SceneBundleScriptRecord(TypedDict):
    bundleID: str
    scenes: list[dict[str, Any]]
    activeSceneIndex: int
    diagnostics: list[str]


class ScriptDocumentStateRecord(TypedDict):
    documentID: str
    mode: str
    sourceText: str
    normalizedUnits: list[NormalizedScriptUnitRecord]
    sceneCandidates: list[ScriptSceneCandidateRecord]
    stitchStates: list[SceneStitchStateRecord]
    bundlePlan: SceneBundlePlanRecord
    bundleScript: SceneBundleScriptRecord
    activeSceneIndex: int

