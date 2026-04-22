from __future__ import annotations

from typing import NotRequired, TypedDict


class SourceAnchorBundleRecord(TypedDict):
    actor_count_hint: int
    ordinal_mentions: list[str]
    mentioned_marked_objects: list[str]
    object_surface_mentions: list[str]
    phase_cues: list[str]
    unsupported_action_flags: list[str]
    same_type_marker_conflict: bool
    low_confidence_flags: list[str]


class ScenePlanActorRecord(TypedDict):
    ref: str
    type: str
    name: NotRequired[str]


class ScenePlanObjectRecord(TypedDict):
    ref: str
    type: str
    relativePosition: str
    name: NotRequired[str]
    markedObjectID: NotRequired[str]


class ScenePlanActionRecord(TypedDict):
    actorRef: str
    type: str
    targetRef: NotRequired[str]
    direction: NotRequired[str]
    modifier: NotRequired[str]
    resultingPose: NotRequired[str]
    holdingObjectRef: NotRequired[str]
    dialogue: NotRequired[str]
    fallbackText: NotRequired[str]
    sourceText: NotRequired[str]


class ScenePlanBeatRecord(TypedDict):
    ref: str
    phase: NotRequired[str]
    actions: list[ScenePlanActionRecord]
    minDuration: NotRequired[float]


class ScenePlanSpatialRelationRecord(TypedDict):
    ref: str
    subjectRef: str
    relation: str
    objectRef: str


class ScenePlanReferenceBindingsRecord(TypedDict):
    actorBindings: dict[str, str]
    markedObjectIDs: list[str]
    aliasToObjectRef: NotRequired[dict[str, str]]


class ScenePlanIRRecord(TypedDict):
    actors: list[ScenePlanActorRecord]
    objects: list[ScenePlanObjectRecord]
    beats: list[ScenePlanBeatRecord]
    spatialRelations: list[ScenePlanSpatialRelationRecord]
    referenceBindings: ScenePlanReferenceBindingsRecord
