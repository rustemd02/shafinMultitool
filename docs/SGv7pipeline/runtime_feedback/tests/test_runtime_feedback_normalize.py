from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from runtime_feedback import NormalizeRuntimeFeedbackRequest, normalize_runtime_feedback


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


class TestRuntimeFeedbackNormalize(unittest.TestCase):
    def test_normalize_captures_reject_and_low_quality_accept(self) -> None:
        reject_event = {
            "event_id": "rtp_1",
            "timestamp": "2026-04-14T10:00:00Z",
            "source": "2 актёра идут навстречу друг другу, останавливаются у компа",
            "marked_objects": [{"name_normalized": "компа", "mentioned_in_source": True}],
            "rule_based_result": {
                "script_json": {"actors": [{"id": "actor_1"}], "objects": [{"id": "object_marked_ab12"}], "beats": []},
                "diagnostics": {"confidence": 0.7, "matchedMarkedObjectsCount": 1},
            },
            "final_result": {
                "script_json": {"actors": [{"id": "actor_1"}], "objects": [], "beats": []},
                "diagnostics": {"confidence": 0.4, "matchedMarkedObjectsCount": 0, "unresolvedMarkedObjects": True},
            },
            "selection": {"decision": "reject", "reason": "потеряны размеченные объекты", "final_script_source": "rule_based"},
            "privacy": {"status": "clear"},
        }
        accept_low_quality = {
            "event_id": "rtp_2",
            "timestamp": "2026-04-14T10:01:00Z",
            "source": "2 актера идут и затем останавливаются у стола",
            "marked_objects": [{"name_normalized": "стола", "mentioned_in_source": True}],
            "rule_based_result": {
                "script_json": {
                    "actors": [{"id": "actor_1"}, {"id": "actor_2"}],
                    "objects": [{"id": "object_marked_cd34"}],
                    "beats": [{"id": "beat_1", "actions": [{"type": "approach", "target": "actor_2"}]}],
                },
                "diagnostics": {"confidence": 0.8, "matchedMarkedObjectsCount": 1},
            },
            "final_result": {
                "script_json": {
                    "actors": [{"id": "actor_1"}, {"id": "actor_2"}],
                    "objects": [{"id": "object_marked_cd34"}],
                    "beats": [{"id": "beat_1", "actions": [{"type": "approach", "target": "actor_2"}]}],
                },
                "diagnostics": {"confidence": 0.7, "matchedMarkedObjectsCount": 1, "unresolvedMarkedObjects": False},
            },
            "selection": {"decision": "accept", "reason": "", "final_script_source": "llm"},
            "privacy": {"status": "clear"},
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            events_jsonl = tmp / "runtime_events.jsonl"
            _write_jsonl(events_jsonl, [reject_event, accept_low_quality])

            request = NormalizeRuntimeFeedbackRequest(
                runtime_events_jsonl=events_jsonl,
                runtime_failures_jsonl=tmp / "runtime_failures.jsonl",
                review_queue_jsonl=tmp / "review_queue.jsonl",
                cluster_manifest_json=tmp / "clusters.json",
                manifest_json=tmp / "manifest.json",
                seed=20260414,
            )
            result = normalize_runtime_feedback(request)

            self.assertEqual(result.manifest["runtime_failure_count"], 2)
            accept_rows = [row for row in result.runtime_failures if row["final_decision"] == "accept"]
            self.assertEqual(len(accept_rows), 1)
            self.assertEqual(accept_rows[0]["low_quality_accept_reason"], "lqa_rule_1")
            self.assertEqual(accept_rows[0]["low_quality_accept_policy_version"], "low_quality_accept_v1")
            self.assertTrue(result.cluster_manifest["cluster_count"] >= 1)

    def test_normalize_supports_zero_failure_output(self) -> None:
        accept_good = {
            "event_id": "rtp_ok",
            "timestamp": "2026-04-14T10:10:00Z",
            "source": "2 актера идут рядом",
            "marked_objects": [],
            "rule_based_result": {
                "script_json": {"actors": [{"id": "actor_1"}, {"id": "actor_2"}], "objects": [], "beats": []},
                "diagnostics": {"confidence": 0.8, "matchedMarkedObjectsCount": 0},
            },
            "final_result": {
                "script_json": {
                    "actors": [{"id": "actor_1"}, {"id": "actor_2"}],
                    "objects": [],
                    "beats": [{"id": "beat_1", "actions": [{"type": "walk"}]}],
                },
                "diagnostics": {"confidence": 0.9, "matchedMarkedObjectsCount": 0, "unresolvedMarkedObjects": False},
            },
            "selection": {"decision": "accept", "reason": "", "final_script_source": "llm"},
            "privacy": {"status": "clear"},
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            events_jsonl = tmp / "runtime_events.jsonl"
            _write_jsonl(events_jsonl, [accept_good])

            request = NormalizeRuntimeFeedbackRequest(
                runtime_events_jsonl=events_jsonl,
                runtime_failures_jsonl=tmp / "runtime_failures.jsonl",
                review_queue_jsonl=tmp / "review_queue.jsonl",
                cluster_manifest_json=tmp / "clusters.json",
                manifest_json=tmp / "manifest.json",
                seed=20260414,
            )
            result = normalize_runtime_feedback(request)
            self.assertEqual(result.manifest["runtime_failure_count"], 0)
            self.assertEqual(result.review_queue, [])

    def test_rule6_checks_final_graph_described_action(self) -> None:
        event = {
            "event_id": "rtp_da",
            "timestamp": "2026-04-14T10:20:00Z",
            "source": "первый начинает курить",
            "marked_objects": [],
            "rule_based_result": {
                "script_json": {"actors": [{"id": "actor_1"}], "objects": [], "beats": []},
                "diagnostics": {"confidence": 0.8, "matchedMarkedObjectsCount": 0},
            },
            "final_result": {
                "script_json": {
                    "actors": [{"id": "actor_1"}],
                    "objects": [],
                    "beats": [
                        {
                            "id": "beat_1",
                            "actions": [{"type": "described_action", "actorId": "actor_1", "fallbackText": "курить"}],
                        }
                    ],
                },
                "diagnostics": {"confidence": 0.9, "matchedMarkedObjectsCount": 0, "unresolvedMarkedObjects": False},
            },
            "selection": {"decision": "accept", "reason": "", "final_script_source": "llm"},
            "privacy": {"status": "clear"},
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            events_jsonl = tmp / "runtime_events.jsonl"
            _write_jsonl(events_jsonl, [event])
            result = normalize_runtime_feedback(
                NormalizeRuntimeFeedbackRequest(
                    runtime_events_jsonl=events_jsonl,
                    runtime_failures_jsonl=tmp / "runtime_failures.jsonl",
                    review_queue_jsonl=tmp / "review_queue.jsonl",
                    cluster_manifest_json=tmp / "clusters.json",
                    manifest_json=tmp / "manifest.json",
                    seed=20260414,
                )
            )
            self.assertEqual(result.manifest["runtime_failure_count"], 0)
