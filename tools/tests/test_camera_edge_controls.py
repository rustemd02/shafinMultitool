from __future__ import annotations

import copy
import hashlib
import unittest

from PIL import Image
import torch

from tools.dataset import build_camera_edge_controls as builder
from tools.dataset import generate_camera_corruptions as geometry
from ml.camera_coach.data.training_records import (
    TrainingRecordError, edge_measurement, parse_record, validate_record_admission,
    stack_inputs, stack_masks, stack_targets, intent_head_mask,
)
from ml.camera_coach.models.set_composition_net_v2 import SETCompositionNetV2CandidateB, SETCompositionNetV2Manifest
from ml.camera_coach.losses import LossConfig, compute_multitask_loss
from ml.camera_coach.data.experiment_edge_controls import metrics, neural_scores


class CameraEdgeControlsTests(unittest.TestCase):
    def setUp(self):
        self.contract = SETCompositionNetV2Manifest.load()
        self.image = Image.frombytes("RGB", (24, 16), bytes((i*17) % 256 for i in range(24*16*3)))
        self.roi = (0.3, 0.3, 0.2, 0.2)
        self.source = dict(id="commons-unit", rights={"license_kind": "public-domain", "artist_text": "fixture author"},
            geometry={"geometry_authority": "silver_apple_vision", "selection_status": "selected",
                "coordinate_space": {"id": "vision_oriented_normalized"},
                "selected_subject": {"x": 0.3, "y": 0.5, "width": 0.2, "height": 0.2, "confidence": 0.95, "kind": "person"},
                "source": {"source_record_id": "commons-unit", "sha256": "1"*64},
                "research_only": True, "human_gold": False, "release_admissible": False})

    def record(self, recipe="source_noop"):
        window = dict(builder.windows(self.roi))[recipe]
        return builder.make_record(self.source, recipe, window, self.image,
            geometry._crop_roi(self.roi, window), "group-unit", "train",
            {"geometry": "2"*64, "rights": "3"*64}, self.contract)

    def test_pressure_extremes_do_not_label_uncertain_interval(self):
        self.assertEqual(edge_measurement((.02,.3,.2,.2)), 1)
        self.assertEqual(edge_measurement((.1,.3,.2,.2)), 0)
        self.assertIsNone(edge_measurement((.06,.3,.2,.2)))

    def test_all_edge_directions_and_nontrivial_noop_have_exact_labels(self):
        recipes = dict(builder.windows(self.roi))
        self.assertEqual(set(recipes), {"source_noop", "clear_crop", "edge_left", "edge_right", "edge_top", "edge_bottom"})
        for recipe in recipes:
            parsed = parse_record(self.record(recipe))
            self.assertEqual(parsed.targets["issue_logits"][0].item(), int(recipe.startswith("edge_")))
            self.assertEqual(parsed.masks["issue_logits"].sum().item(), 1)
            self.assertFalse(parsed.intent_known)
            self.assertTrue(all(not mask.any() for head,mask in parsed.masks.items() if head != "issue_logits"))

    def test_changed_bbox_breaks_source_target_binding(self):
        raw = self.record()
        raw["roi_normalized_xywh"][0] += .01
        with self.assertRaisesRegex(TrainingRecordError, "analytic crop"):
            parse_record(raw)

    def test_unobserved_issue_cannot_become_negative(self):
        raw = self.record()
        raw["targets"]["issues"]["backlight_hides_subject"] = 0
        with self.assertRaisesRegex(TrainingRecordError, "other issue labels"):
            parse_record(raw)

    def test_geometric_noop_is_not_good_frame_or_action_label(self):
        for field in ("good_frame", "risk", "abstention"):
            raw = self.record()
            raw["targets"][field] = 1
            with self.assertRaises(TrainingRecordError):
                parse_record(raw)

    def test_source_and_derivative_hash_mutation_fail(self):
        raw = self.record()
        raw["pixels"]["values"][0] ^= 1
        with self.assertRaisesRegex(TrainingRecordError, "pixel SHA"):
            parse_record(raw)
        raw = self.record()
        raw["annotation_provenance"]["geometry"]["selected_subject"]["x"] += .1
        with self.assertRaisesRegex(TrainingRecordError, "geometry SHA"):
            parse_record(raw)

    def test_flags_and_config_cannot_promote_measurements(self):
        for key,value in (("human_gold",True),("release_admissible",True),("research_only",False),("training_ready",True)):
            raw = self.record()
            raw["annotation_provenance"][key] = value
            with self.assertRaisesRegex(TrainingRecordError, "non-admitted research"):
                parse_record(raw)
        with self.assertRaisesRegex(TrainingRecordError, "non_admitted_research"):
            validate_record_admission([parse_record(self.record())], "declared_admitted")

    def test_incompatible_versions_reject_geometric_provenance(self):
        for version in ("v2.0.0", "v2.1.0"):
            raw = self.record()
            raw["schema_version"] = version
            with self.assertRaises(TrainingRecordError):
                parse_record(raw)

    def test_author_and_near_duplicate_families_cannot_cross_split(self):
        sources = [dict(id="a",author="Author",pixel_sha256="a",dhash=0),
                   dict(id="b",author="author",pixel_sha256="b",dhash=(1<<64)-1),
                   dict(id="c",author="Other",pixel_sha256="c",dhash=1),
                   dict(id="d",author="Separate",pixel_sha256="d",dhash=int("55"*8,16))]
        assignments, links = builder.grouped_sources(sources, 20260916)
        self.assertEqual(assignments["a"],assignments["b"])
        self.assertEqual(assignments["a"],assignments["c"])
        self.assertNotEqual(assignments["a"][0],assignments["d"][0])
        self.assertEqual(assignments,builder.grouped_sources(list(reversed(sources)),20260916)[0])
        self.assertTrue(links)

    def test_real_model_receives_only_edge_component_gradient(self):
        torch.set_num_threads(1)
        torch.manual_seed(20260916)
        records = [parse_record(self.record(recipe)) for recipe in ("source_noop","edge_right")]
        model = SETCompositionNetV2CandidateB(self.contract)
        outputs = model(stack_inputs(records,self.contract))
        for output in outputs.values():
            output.retain_grad()
        result = compute_multitask_loss(outputs,stack_targets(records),masks=stack_masks(records),
            intent_mask=intent_head_mask(records,self.contract),config=LossConfig.from_file(builder.ROOT/"ml/camera_coach/configs/loss_weights.json"))
        result.total.backward()
        self.assertTrue(torch.isfinite(result.total))
        self.assertTrue((outputs["issue_logits"].grad[:,0] != 0).all())
        self.assertTrue((outputs["issue_logits"].grad[:,1:] == 0).all())
        for head,mask in stack_masks(records).items():
            if head != "issue_logits":
                self.assertTrue((outputs[head].grad == 0).all())

    def test_preflight_validates_spatial_mask_without_requiring_full_frame_roi(self):
        torch.set_num_threads(1)
        records = [parse_record(self.record(recipe)) for recipe in ("source_noop","edge_left")]
        inputs = stack_inputs(records,self.contract)
        self.assertFalse(inputs.roi_mask.all())
        self.assertTrue(inputs.roi_mask.any())
        model = SETCompositionNetV2CandidateB(self.contract)
        self.assertEqual(len(neural_scores(model,records,self.contract)),2)

    def test_metric_rejects_empty_or_single_class_instead_of_passing(self):
        clear = parse_record(self.record())
        edge = parse_record(self.record("edge_right"))
        for records,scores in (([],[]),([clear],[0.0]),([clear,edge],[0.0])):
            with self.assertRaises(ValueError):
                metrics(records,scores)
        self.assertEqual(metrics([clear,edge],[0.0,1.0])["balanced_accuracy"],1.0)
        self.assertEqual(metrics([clear,edge],[1.0,1.0])["false_positive_on_geometric_noop"],1.0)


if __name__ == "__main__":
    unittest.main()
