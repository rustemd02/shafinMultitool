from __future__ import annotations

from typing import Literal, NotRequired, TypedDict


CIRVersion = Literal["sg_v7_cir_v1"]
DifficultyBucket = Literal["core", "hard"]
ComplexityClass = Literal["S", "M", "L"]
SourceVariantKey = Literal[
    "base",
    "ordinal_stress",
    "morphology_stress",
    "same_type_marker_stress",
    "dialogue_mix",
]

ActorType = Literal["human", "tiger", "lion", "dog", "cat", "bird", "generic"]
ObjectType = Literal[
    "table",
    "chair",
    "cabinet",
    "door",
    "couch",
    "bed",
    "window",
    "shelf",
    "tv",
    "generic",
]
RelativePosition = Literal["left", "right", "center", "background", "foreground", "unknown"]
ActorPose = Literal["standing", "sitting", "crouching", "lying", "walking", "running"]
ActionType = Literal[
    "walk",
    "run",
    "stop",
    "turn",
    "approach",
    "pass_by",
    "enter",
    "exit",
    "stand",
    "sit",
    "lie_down",
    "crouch",
    "look_at",
    "pick_up",
    "put_down",
    "open",
    "close",
    "give",
    "talk",
    "described_action",
]
Direction = Literal[
    "left",
    "right",
    "forward",
    "backward",
    "toward_each_other",
    "away_from_each_other",
    "to_target",
]
Modifier = Literal["slowly", "quickly", "carefully"]
RelationType = Literal[
    "near",
    "in_front_of",
    "behind",
    "left_of",
    "right_of",
    "between",
    "pass_by",
    "inside",
    "outside",
]
BeatPhase = Literal[
    "single_action",
    "dialogue_exchange",
    "toward_each_other",
    "approach_object",
    "stop_near_object",
    "pass_by_object",
    "turn_to_target",
    "pickup_object",
    "putdown_object",
    "open_object",
    "close_object",
    "give_object",
    "first_described_action",
    "second_described_action",
    "third_described_action",
    "small_followup_action",
]


class ActorLabels(TypedDict):
    ordinal: Literal["first", "second", "third"]
    surface_role: NotRequired[str | None]


class ActorNode(TypedDict):
    id: str
    type: ActorType
    labels: ActorLabels
    name: NotRequired[str | None]


class MarkerBinding(TypedDict):
    kind: Literal["marked", "unmarked"]
    marker_short_id: NotRequired[str]
    source_name: NotRequired[str]
    mentioned_aliases: NotRequired[list[str]]


class ObjectNode(TypedDict):
    id: str
    type: ObjectType
    relative_position: RelativePosition
    marker_binding: MarkerBinding
    name: NotRequired[str | None]


class DescribedActionPayload(TypedDict):
    canonical_text: str
    fallback_text: str
    source_lemma_hint: NotRequired[str]


class ActionSemantics(TypedDict):
    chronology_rank: int
    is_unsupported_runtime_action: NotRequired[bool]
    must_preserve_in_source: NotRequired[bool]


class ActionNode(TypedDict):
    id: str
    actor_id: str
    type: ActionType
    resulting_pose: ActorPose
    semantics: ActionSemantics
    target_id: NotRequired[str | None]
    direction: NotRequired[Direction | None]
    modifier: NotRequired[Modifier | None]
    holding_object: NotRequired[str | None]
    dialogue: NotRequired[str | None]
    described_action: NotRequired[DescribedActionPayload]


class CameraNode(TypedDict):
    shot_type: Literal["wide", "medium", "close_up", "extreme_close_up", "over_shoulder", "two_shot"]
    movement: NotRequired[
        Literal[
            "static",
            "pan_left",
            "pan_right",
            "tilt_up",
            "tilt_down",
            "dolly_in",
            "dolly_out",
            "tracking",
            "crane_up",
            "crane_down",
        ]
    ]
    target: NotRequired[str]


class BeatNode(TypedDict):
    id: str
    phase: BeatPhase
    actions: list[ActionNode]
    camera: NotRequired[CameraNode]
    min_duration: NotRequired[float]


class SpatialRelationNode(TypedDict):
    id: str
    subject: str
    relation: RelationType
    object: str


class ReferenceBindings(TypedDict):
    ordinal_map: dict[str, str]
    marked_object_ids: list[str]
    alias_to_object_id: dict[str, str]


class SceneGraph(TypedDict):
    actors: list[ActorNode]
    objects: list[ObjectNode]
    beats: list[BeatNode]
    spatial_relations: list[SpatialRelationNode]
    reference_bindings: ReferenceBindings
    must_preserve: list[str]


class DeterminismSpec(TypedDict):
    id_policy: Literal["canonical_v1"]
    ordering_policy: Literal["stable_v1"]
    serializer: Literal["deterministic_scene_script_v1"]
    phase_policy: Literal["phase_enum_v1"]
    described_action_policy: Literal["described_action_v1"]


class BudgetSpec(TypedDict):
    actor_count: int
    object_count: int
    beat_count: int
    action_count: int
    relation_count: int


class RuntimeProjectionSpec(TypedDict):
    target_schema: Literal["SceneScript"]
    field_casing: Literal["camelCase"]
    drop_internal_fields: Literal[True]
    fill_original_description_from_source_variant: Literal[True]
    described_action_source_text_policy: Literal["canonical_text_to_sourceText"]
    top_level_optional_policy: Literal["omit_all"]
    beat_optional_policy: Literal["preserve_if_present_else_omit"]


class CIRRecord(TypedDict):
    cir_version: CIRVersion
    contract_version: str
    sample_id: str
    source_variant_key: SourceVariantKey
    pattern_name: str
    difficulty_bucket: DifficultyBucket
    complexity_class: ComplexityClass
    graph_seed: int
    scene_graph: SceneGraph
    semantic_tags: list[str]
    determinism: DeterminismSpec
    budgets: BudgetSpec
    runtime_projection: RuntimeProjectionSpec
    internal_metadata: NotRequired[dict[str, object]]


class SceneScriptAction(TypedDict):
    id: str
    actorId: str
    type: ActionType
    resultingPose: ActorPose
    target: NotRequired[str]
    direction: NotRequired[Direction]
    modifier: NotRequired[Modifier]
    holdingObject: NotRequired[str]
    dialogue: NotRequired[str]
    fallbackText: NotRequired[str]
    sourceText: NotRequired[str]


class SceneScriptCamera(TypedDict):
    shotType: Literal["wide", "medium", "close_up", "extreme_close_up", "over_shoulder", "two_shot"]
    movement: NotRequired[
        Literal[
            "static",
            "pan_left",
            "pan_right",
            "tilt_up",
            "tilt_down",
            "dolly_in",
            "dolly_out",
            "tracking",
            "crane_up",
            "crane_down",
        ]
    ]
    target: NotRequired[str]


class SceneScriptBeat(TypedDict):
    id: str
    actions: list[SceneScriptAction]
    camera: NotRequired[SceneScriptCamera]
    minDuration: NotRequired[float]


class SceneScriptActor(TypedDict):
    id: str
    type: ActorType
    name: NotRequired[str]


class SceneScriptObject(TypedDict):
    id: str
    type: ObjectType
    relativePosition: RelativePosition
    name: NotRequired[str]


class SceneScriptSpatialRelation(TypedDict):
    id: str
    subject: str
    relation: RelationType
    object: str


class SceneScriptRecord(TypedDict):
    actors: list[SceneScriptActor]
    objects: list[SceneScriptObject]
    beats: list[SceneScriptBeat]
    spatialRelations: list[SceneScriptSpatialRelation]
    originalDescription: str
