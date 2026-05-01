from __future__ import annotations

from typing import Any, NotRequired, TypedDict


class ActorSlotRecord(TypedDict):
    slotId: str
    ref: str
    type: str
    name: NotRequired[str]


class ObjectSlotRecord(TypedDict):
    slotId: str
    ref: str
    type: str
    relativePosition: str
    markedObjectID: NotRequired[str]
    name: NotRequired[str]


class BeatSlotRecord(TypedDict):
    slotId: str
    beatRef: str
    phaseHint: NotRequired[str]
    order: int
    minDuration: NotRequired[float]


class RelationHintRecord(TypedDict):
    subjectSlot: str
    relation: str
    objectSlot: str


class SlotCatalogRecord(TypedDict):
    contractVersion: str
    actorSlots: list[ActorSlotRecord]
    objectSlots: list[ObjectSlotRecord]
    markedObjectSlots: list[str]
    beatSlots: list[BeatSlotRecord]
    actionTypes: list[str]
    relationHints: list[RelationHintRecord]


class EventRowRecord(TypedDict):
    rowId: str
    beatSlot: str
    actorSlot: str
    actionType: str
    targetSlot: NotRequired[str]
    holdingObjectSlot: NotRequired[str]
    dialogueText: NotRequired[str]
    describedActionText: NotRequired[str]
    sourceSpan: NotRequired[str]
    confidence: NotRequired[float]


class EventTableRecord(TypedDict):
    contractVersion: str
    rows: list[EventRowRecord]


class PatchOpRecord(TypedDict):
    op: str
    rowId: str
    field: NotRequired[str]
    value: NotRequired[Any]


class PatchOpsRecord(TypedDict):
    contractVersion: str
    ops: list[PatchOpRecord]


class VerifierIssueRecord(TypedDict):
    code: str
    rowId: str
    details: str
    fixable: bool
