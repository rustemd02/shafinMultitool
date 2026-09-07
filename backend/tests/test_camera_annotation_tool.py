from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "annotate_camera", REPO_ROOT / "tools/camera_annotation/annotate_camera.py"
)
assert SPEC and SPEC.loader
TOOL = importlib.util.module_from_spec(SPEC)
sys.modules["annotate_camera"] = TOOL
SPEC.loader.exec_module(TOOL)


class CameraAnnotationToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="m3-006-camera-annotation-")
        self.store = Path(self.temp.name) / "votes.jsonl"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_round_trip_vote_and_export(self):
        vote = TOOL.build_vote(
            record_id="rec_1",
            annotator_id="ann_a",
            verdict="good",
            subject_state="selected",
            selected_subject_id="person_primary",
            region_ids=["region_1"],
        )
        TOOL.append_record(self.store, vote)
        bundle = TOOL.export_bundle(self.store)
        self.assertEqual(bundle["vote_count"], 1)
        exported = bundle["records"][0]
        self.assertEqual(exported["record_id"], "rec_1")
        self.assertEqual(exported["verdict"], "good")
        self.assertNotIn("model", exported)

    def test_candidate_identity_hidden_qc_rejected(self):
        # Field-name leak gate: any candidate/model key anywhere in the
        # tree is rejected.
        with self.assertRaises(TOOL.AdmissionError):
            TOOL.check_no_candidate_leak({"votes": [{"candidate_id": "x"}]})
        with self.assertRaises(TOOL.AdmissionError):
            TOOL.check_no_candidate_leak({"meta": {"model_version": "m"}})
        # Annotator prose in notes is free text, not a leak.
        TOOL.check_no_candidate_leak({"notes": "annotator mentioned the model words"})
        # And a poisoned store line is rejected on load.
        self.store.write_text(json.dumps({
            "record_type": "vote", "record_id": "x", "annotator_id": "a",
            "verdict": "good", "subject_state": "none",
            "selected_subject_id": None, "region_ids": [],
            "notes": "", "created_at": "t", "tool_id": TOOL.TOOL_ID,
            "store_version": 1, "candidate_score": 0.9,
        }) + "\n", encoding="utf-8")
        with self.assertRaises(TOOL.AdmissionError):
            TOOL.load_store(self.store)

    def test_concurrent_annotator_ids_all_persist(self):
        barrier = threading.Barrier(8)
        errors: list[Exception] = []

        def worker(index: int) -> None:
            try:
                barrier.wait()
                vote = TOOL.build_vote(
                    record_id=f"rec_{index}",
                    annotator_id=f"ann_{index}",
                    verdict="abstain",
                    subject_state="abstain",
                    selected_subject_id=None,
                    region_ids=[],
                    notes="concurrent probe",
                )
                TOOL.append_record(self.store, vote)
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(errors, [])
        self.assertEqual(TOOL.export_bundle(self.store)["vote_count"], 8)

    def test_adjudication_appends_without_overwriting_votes(self):
        vote_a = TOOL.build_vote("rec_1", "ann_a", "good", "selected", "s1", [])
        vote_b = TOOL.build_vote("rec_1", "ann_b", "bad", "ambiguous", None, [])
        TOOL.append_record(self.store, vote_a)
        TOOL.append_record(self.store, vote_b)
        adj = TOOL.build_adjudication(
            record_id="rec_1",
            adjudicator_id="adj_1",
            outcome="override",
            referenced_vote_ids=["rec_1:ann_a", "rec_1:ann_b"],
            resolved_subject_id="s2",
            notes="second annotator missed the second person",
        )
        TOOL.append_record(self.store, adj)
        bundle = TOOL.export_bundle(self.store)
        self.assertEqual(bundle["vote_count"], 2)
        self.assertEqual(bundle["adjudication_count"], 1)
        # Original votes are byte-identical after adjudication.
        self.assertEqual(bundle["records"][0]["verdict"], "good")
        self.assertEqual(bundle["records"][1]["verdict"], "bad")

    def test_adjudication_requires_references_and_notes(self):
        with self.assertRaises(TOOL.AdmissionError):
            TOOL.build_adjudication("rec_1", "adj_1", "uphold", [], None, "n")
        with self.assertRaises(TOOL.AdmissionError):
            TOOL.build_adjudication("rec_1", "adj_1", "uphold", ["v1"], None, "")

    def test_subject_state_discipline(self):
        with self.assertRaises(TOOL.AdmissionError):
            TOOL.build_vote("r", "a", "good", "ambiguous", "s1", [])


if __name__ == "__main__":
    unittest.main()
