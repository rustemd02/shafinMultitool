from __future__ import annotations

import unittest

from docs.SGv7pipeline.v1.datasets import (
    chunk_anchor_builder,
    chunk_patch_builder,
    entity_registry_builder,
    macro_scene_builder,
)
from docs.SGv7pipeline.v1.eval_artifacts import stitch_eval_artifacts_builder


def _document_state() -> dict:
    return {
        "document_state": {
            "documentID": "doc-1",
            "mode": "full",
            "sourceText": "INT. OFFICE - NIGHT\nЕгор подходит к столу.",
            "normalizedUnits": [],
            "sceneCandidates": [
                {
                    "id": "scene_1",
                    "sceneIndex": 0,
                    "heading": "INT. OFFICE - NIGHT",
                    "sourceText": "INT. OFFICE - NIGHT\nЕгор подходит к столу.",
                    "metadata": {
                        "sceneHeading": "INT. OFFICE - NIGHT",
                        "locationName": "OFFICE",
                        "interiorExterior": "interior",
                        "timeOfDay": "night",
                    },
                    "isImplicit": False,
                }
            ],
            "stitchStates": [
                {
                    "sceneID": "scene_1",
                    "sceneIndex": 0,
                    "sourceText": "INT. OFFICE - NIGHT\nЕгор подходит к столу.",
                    "metadata": {
                        "sceneHeading": "INT. OFFICE - NIGHT",
                        "locationName": "OFFICE",
                        "interiorExterior": "interior",
                        "timeOfDay": "night",
                    },
                    "registry": {
                        "actors": [{"ref": "actor_scene1_egor_1", "type": "human", "name": "егор"}],
                        "objects": [{"ref": "object_scene1_table_1", "type": "table", "relativePosition": "center", "name": "стол"}],
                        "actorAliasMap": {"егор": "actor_scene1_egor_1"},
                        "objectAliasMap": {"стол": "object_scene1_table_1"},
                        "speakerAliasMap": {},
                        "unresolvedMentions": [],
                        "actorPoses": {"actor_scene1_egor_1": "walking"},
                        "heldObjects": {},
                    },
                    "actors": [{"ref": "actor_scene1_egor_1", "type": "human", "name": "егор"}],
                    "objects": [{"ref": "object_scene1_table_1", "type": "table", "relativePosition": "center", "name": "стол"}],
                    "beats": [
                        {
                            "ref": "scene_1_chunk_1_beat_1",
                            "phase": "approach",
                            "actions": [{"actorRef": "actor_scene1_egor_1", "type": "approach", "targetRef": "object_scene1_table_1"}],
                        }
                    ],
                    "spatialRelations": [],
                    "chunkLedger": ["scene_1_chunk_1"],
                    "deferredRefs": [],
                    "continuityDiagnostics": [],
                }
            ],
            "bundlePlan": {
                "bundleID": "bundle-1",
                "activeSceneIndex": 0,
                "diagnostics": [],
                "scenes": [
                    {
                        "sceneID": "scene_1",
                        "sceneIndex": 0,
                        "sourceText": "INT. OFFICE - NIGHT\nЕгор подходит к столу.",
                        "metadata": {
                            "sceneHeading": "INT. OFFICE - NIGHT",
                            "locationName": "OFFICE",
                            "interiorExterior": "interior",
                            "timeOfDay": "night",
                        },
                        "diagnostics": [],
                        "plan": {
                            "actors": [{"ref": "actor_scene1_egor_1", "type": "human", "name": "егор"}],
                            "objects": [{"ref": "object_scene1_table_1", "type": "table", "relativePosition": "center", "name": "стол"}],
                            "beats": [
                                {
                                    "ref": "beat_1",
                                    "phase": "approach",
                                    "actions": [{"actorRef": "actor_scene1_egor_1", "type": "approach", "targetRef": "object_scene1_table_1"}],
                                }
                            ],
                            "spatialRelations": [],
                            "referenceBindings": {"actorBindings": {"actor_scene1_egor_1": "actor_scene1_egor_1"}, "markedObjectIDs": []},
                        },
                        "chunks": [
                            {
                                "chunkID": "scene_1_chunk_1",
                                "chunkIndex": 0,
                                "sceneID": "scene_1",
                                "sourceText": "Егор подходит к столу.",
                                "sourceRange": {"start": 0, "end": 22},
                                "anchors": {
                                    "sourceBundle": {
                                        "actor_count_hint": 1,
                                        "ordinal_mentions": [],
                                        "mentioned_marked_objects": [],
                                        "object_surface_mentions": ["стол"],
                                        "phase_cues": ["approach"],
                                        "unsupported_action_flags": [],
                                        "same_type_marker_conflict": False,
                                        "low_confidence_flags": [],
                                    },
                                    "speakerCues": [],
                                    "actorMentions": ["егор"],
                                    "objectMentions": ["стол"],
                                    "markedObjectMentions": [],
                                    "pronounMentions": [],
                                    "chronologyCues": [],
                                    "locationCues": ["office"],
                                    "timeCues": ["night"],
                                    "uncertaintyFlags": [],
                                },
                                "registryPatch": {},
                                "beatPatch": [
                                    {
                                        "ref": "scene_1_chunk_1_beat_1",
                                        "phase": "approach",
                                        "actions": [{"actorRef": "actor_scene1_egor_1", "type": "approach", "targetRef": "object_scene1_table_1"}],
                                    }
                                ],
                                "spatialRelationPatch": [],
                                "stateDelta": {},
                                "deferredRefs": [],
                                "reasonCodes": [],
                                "usedFallbackPlanner": True,
                                "usedLegacyPlanBridge": True,
                            }
                        ],
                    }
                ],
            },
            "bundleScript": {"bundleID": "bundle-1", "activeSceneIndex": 0, "diagnostics": [], "scenes": []},
            "activeSceneIndex": 0,
        }
    }


class V1PipelineTests(unittest.TestCase):
    def test_dataset_builders_extract_rows(self) -> None:
        rows = [_document_state()]
        self.assertEqual(len(macro_scene_builder(rows)), 1)
        self.assertEqual(len(chunk_anchor_builder(rows)), 1)
        self.assertEqual(len(entity_registry_builder(rows)), 1)
        chunk_patch_rows = chunk_patch_builder(rows)
        self.assertEqual(len(chunk_patch_rows), 1)
        self.assertEqual(chunk_patch_rows[0]["document_id"], "doc-1")

    def test_eval_artifacts_builder_compiles_active_scene(self) -> None:
        eval_cases = [{"eval_case_id": "doc-1"}]
        chunk_rows, scene_rows, bundle_rows, compiled_rows = stitch_eval_artifacts_builder(
            eval_case_rows=eval_cases,
            prediction_rows=[{"eval_case_id": "doc-1", **_document_state()}],
        )
        self.assertEqual(len(chunk_rows), 1)
        self.assertEqual(len(scene_rows), 1)
        self.assertEqual(len(bundle_rows), 1)
        self.assertEqual(len(compiled_rows), 1)
        self.assertIsInstance(compiled_rows[0]["predicted_script"], dict)


if __name__ == "__main__":
    unittest.main()
