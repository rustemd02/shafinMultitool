"""Research partial intake regressions. All journals/media are generated fixtures."""
from __future__ import annotations

from copy import deepcopy
from dataclasses import replace
import json
from pathlib import Path
import random
import sys

import pytest
from PIL import Image
import torch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(REPO / "tools/camera_annotation"))

from annotation_labels import ISSUES, sha256_file
from language_labels import FLAGS, projection
from language_intake import export_language_review, select_confirmations
from ml.camera_coach.data.training_records import (TrainingRecordError, load_records, parse_record,
    stack_masks, stack_targets, validate_record_admission)
from ml.camera_coach.losses import compute_multitask_loss
from ml.camera_coach.models.set_composition_net_v2 import SETCompositionNetV2Manifest
from ml.camera_coach.trainer_records import RecordsTrainingConfig, TrainingError, train_one_seed
from ml.camera_coach.losses import LossConfig

CONTRACT = SETCompositionNetV2Manifest.load()
torch.set_num_threads(1)


def interpretation():
    return dict(verdict=dict(value="good", evidence="Frame is good"),
        issues=[dict(code=ISSUES[0], polarity="present", evidence="Edge is crowded"),
                dict(code=ISSUES[1], polarity="absent", evidence="Subject is clear")],
        actions=[dict(code="move_object_left", polarity="acceptable", evidence="Move object left")],
        intent=dict(value="natural", evidence="Natural framing"),
        subject=dict(description="table", evidence="table"), temporal=dict(value="not_stated", evidence=""),
        spatial_requests=[dict(entity="table", goal="center", evidence="Center the table")], unmapped=[], question=None)


def add_fixture(folder, rid="fixture-1", split="train", seed=1, visual=True):
    generator = random.Random(seed)
    path = folder / (rid + ".png")
    image = Image.frombytes("RGB", (24, 18), generator.randbytes(24 * 18 * 3)); image.save(path)
    digest = sha256_file(path)
    source = dict(record_id=rid, image_path=str(path), image_sha256=digest, source_group="fixture-group-" + str(seed),
                  split=split, matrix_class="object_or_food", matrix_class_basis="fixture stratum only", **FLAGS)
    item = dict(record_id=rid, kind="photo", media_path=str(path), media_sha256=digest, source=source, **FLAGS)
    value = interpretation()
    base = dict(schema_id="camera-human-visual-review-v2", record_id=rid, annotator_id="test-fixture-only",
                media_kind="photo", media_sha256=digest, **FLAGS)
    if visual:
        base.update(job_id=rid + "-job", cache_key="fixture-cache")
        events = [dict(base, state="visual_dispatch", model="offline-fixture"),
            dict(base, state="visual_proposal", interpretation=value, model="offline-fixture"),
            dict(base, state="visual_confirmed", interpretation=value, human_confirmed_assessment=True,
                 contract_projection=projection(value, "photo"))]
    else:
        text = ". ".join(["Frame is good", "Edge is crowded", "Subject is clear", "Move object left",
                           "Natural framing", "table", "Center the table"])
        base.update(review_id=rid + "-review", raw_text=text)
        events = [dict(base, state="draft"), dict(base, state="proposal", interpretation=value, model="offline-fixture"),
            dict(base, state="confirmed", interpretation=value, human_confirmed_translation=True,
                 contract_projection=projection(value, "photo"))]
    return item, events


def write_source(folder, fixtures):
    items = [item for item, _ in fixtures]
    events = [event for _, rows in fixtures for event in rows]
    for name, rows in (("queue.jsonl", items), ("opinions.jsonl", events)):
        (folder / name).write_text("".join(json.dumps(row) + "\n" for row in rows))
    return items, events


@pytest.fixture
def intake(tmp_path):
    folder = tmp_path / "source"; folder.mkdir()
    fixtures = [add_fixture(folder), add_fixture(folder, "fixture-2", "validation", 2, visual=False)]
    write_source(folder, fixtures)
    before = {name: (folder / name).read_bytes() for name in ("queue.jsonl", "opinions.jsonl")}
    out = tmp_path / "intake"
    receipt = export_language_review(folder, out)
    assert all((folder / name).read_bytes() == data for name, data in before.items())
    raw = [json.loads(line) for line in (out / "records.jsonl").read_text().splitlines()]
    return folder, out, receipt, raw


def test_partial_projection_preserves_masks_and_origin_without_fabricated_heads(intake):
    _, out, receipt, raw = intake
    records = load_records(out / "records.jsonl", receipt["records_sha256"])
    assert receipt["records"] == 2 and receipt["active_targets"]["issue_logits"] == 4
    assert receipt["label_origins"] == {"model_visual_human_confirmed": 1, "human_text_model_translation_confirmed": 1}
    for node, record in zip(raw, records):
        assert record.masks["issue_logits"].tolist() == [1, 1, 0, 0, 0, 0, 0, 0]
        assert record.targets["issue_logits"].tolist() == [1, 0, 0, 0, 0, 0, 0, 0]
        assert all(not mask.any() for head, mask in record.masks.items() if head != "issue_logits")
        assert record.roi is None and not record.intent_known
        assert node["annotation_provenance"]["projection"]["spatial_requests"] == interpretation()["spatial_requests"]
        assert node["annotation_provenance"]["projection"]["good_frame_probability"] == 1
        assert node["targets"]["good_frame"] is None
        assert node["annotation_provenance"]["training_ready"] is False
        assert node["annotation_provenance"]["human_gold"] is False


def test_partial_unknowns_have_zero_gradient_and_explicit_negative_has_gradient(intake):
    records = [parse_record(row) for row in intake[3]]
    outputs = {head: torch.full((2, width), .5 if "probability" in head else 0., requires_grad=True)
               for head, width in CONTRACT.output_head_shapes.items()}
    masks = stack_masks(records)
    result = compute_multitask_loss(outputs, stack_targets(records), masks=masks)
    result.total.backward()
    issue_grad = outputs["issue_logits"].grad
    assert (issue_grad[:, 0] < 0).all() and (issue_grad[:, 1] > 0).all()
    assert torch.count_nonzero(issue_grad[:, 2:]) == 0
    assert all(torch.count_nonzero(outputs[head].grad) == 0 for head in masks if head != "issue_logits")


def test_versioned_issue_formats_cannot_be_silently_mixed(intake):
    raw = deepcopy(intake[3][0]); raw["schema_version"] = "v2.0.0"
    with pytest.raises(TrainingRecordError, match="keys drifted"):
        parse_record(raw)
    raw.pop("annotation_provenance")
    with pytest.raises(TrainingRecordError, match="keys drifted"):
        parse_record(raw)
    raw["targets"]["issues"] = dict(reviewed=True, present=[ISSUES[0]])
    assert parse_record(raw).masks["issue_logits"].tolist() == [1] * 8
    raw["schema_version"] = "v2.1.0"
    with pytest.raises(TrainingRecordError, match="keys drifted"):
        parse_record(raw)


@pytest.mark.parametrize("value", [False, True, -1, 2, .5, "0"])
def test_partial_issue_type_is_closed(intake, value):
    raw = deepcopy(intake[3][0]); raw["targets"]["issues"][ISSUES[2]] = value
    with pytest.raises(TrainingRecordError):
        parse_record(raw)


@pytest.mark.parametrize("flag", ["research_only", "human_gold", "release_admissible", "training_ready"])
def test_admission_flags_cannot_be_promoted(intake, flag):
    raw = deepcopy(intake[3][0]); raw["annotation_provenance"][flag] = not raw["annotation_provenance"][flag]
    with pytest.raises(TrainingRecordError, match="research flags"):
        parse_record(raw)


def test_projection_and_new_head_invention_fail_closed(intake):
    raw = deepcopy(intake[3][0]); raw["targets"]["issues"][ISSUES[0]] = 0
    with pytest.raises(TrainingRecordError, match="disagree"):
        parse_record(raw)
    raw = deepcopy(intake[3][0]); raw["targets"]["abstention"] = 0
    with pytest.raises(TrainingRecordError, match="issue supervision only"):
        parse_record(raw)


def test_trainer_config_cannot_promote_partial_research(intake):
    records = [parse_record(row) for row in intake[3]]
    validate_record_admission(records, "non_admitted_research")
    with pytest.raises(TrainingRecordError, match="non_admitted_research"):
        validate_record_admission(records, "declared_admitted")
    with pytest.raises(TrainingRecordError, match="non_admitted_research"):
        load_records(intake[1] / "records.jsonl", admission="declared_admitted")


@pytest.mark.parametrize("split", ["train", "validation"])
def test_empty_effective_training_or_validation_is_rejected(intake, tmp_path, split):
    raw = deepcopy(intake[3])
    for node in raw:
        if node["split"] == split:
            node["targets"]["issues"] = {name: None for name in ISSUES}
            node["annotation_provenance"]["projection"]["issue_logits"] = [None] * 8
    records = [parse_record(node) for node in raw]
    config = RecordsTrainingConfig.from_file(REPO / "ml/camera_coach/configs/production_records_smoke.json")
    config = replace(config, training=replace(config.training, trained_heads=("issue_logits",)))
    with pytest.raises(TrainingError, match="no supervised targets"):
        train_one_seed(config, seed=1, run_dir=tmp_path / "never-created", contract=CONTRACT,
                       loss_config=LossConfig.from_file(REPO / "ml/camera_coach/configs/loss_weights.json"), records=records)
    assert not (tmp_path / "never-created").exists()


@pytest.mark.parametrize("state", ["draft", "raw", "proposal"])
def test_new_manual_revision_withdraws_previous_visual_label(tmp_path, state):
    _, events = add_fixture(tmp_path)
    events.append(dict(events[0], state=state, review_id="new-human-revision"))
    selected, held = select_confirmations(list(enumerate(events, 1)))
    assert selected == [] and held[0]["reason"] == "newer_unconfirmed_manual_revision"


def test_slow_visual_confirmation_cannot_override_revision_after_dispatch(tmp_path):
    _, events = add_fixture(tmp_path)
    events.insert(1, dict(events[0], state="draft", review_id="new-human-revision"))
    selected, held = select_confirmations(list(enumerate(events, 1)))
    assert not selected and held[0]["reason"] == "visual_superseded_by_manual_revision"


def test_unconfirmed_model_proposal_is_not_exported(tmp_path):
    item, events = add_fixture(tmp_path)
    write_source(tmp_path, [(item, events[:-1])])
    with pytest.raises(ValueError, match="No current confirmed"):
        export_language_review(tmp_path, tmp_path / "out")
    assert not (tmp_path / "out").exists()


def test_locked_test_refused_before_pixel_read(tmp_path, monkeypatch):
    write_source(tmp_path, [add_fixture(tmp_path, split="locked_test")])
    monkeypatch.setattr("language_intake.image_pixels", lambda item: pytest.fail("locked pixels read"))
    with pytest.raises(ValueError, match="Locked test"):
        export_language_review(tmp_path, tmp_path / "out")


def test_source_hash_tampering_is_not_exported(tmp_path):
    item, events = add_fixture(tmp_path)
    write_source(tmp_path, [(item, events)])
    Path(item["media_path"]).write_bytes(b"changed pixels")
    with pytest.raises(ValueError, match="SHA changed"):
        export_language_review(tmp_path, tmp_path / "out")
    assert not (tmp_path / "out").exists()


def test_cross_split_family_conflict_blocks_intake(tmp_path):
    left = add_fixture(tmp_path)
    right = add_fixture(tmp_path, "fixture-2", "validation", 2)
    right[0]["source"]["source_group"] = left[0]["source"]["source_group"]
    write_source(tmp_path, [left, right])
    with pytest.raises(ValueError, match="split conflict"):
        export_language_review(tmp_path, tmp_path / "out")


def test_existing_output_is_never_overwritten(intake):
    folder, out, _, _ = intake
    receipt = (out / "receipt.json").read_bytes()
    with pytest.raises(ValueError, match="overwrite"):
        export_language_review(folder, out)
    assert (out / "receipt.json").read_bytes() == receipt


def test_export_language_cli_dispatches_versioned_adapter(intake, tmp_path, monkeypatch, capsys):
    import review_pipeline
    out = tmp_path / "cli-intake"
    monkeypatch.setattr(sys, "argv", ["review_pipeline.py", "export-language", "--folder", str(intake[0]), "--out", str(out)])
    review_pipeline.main()
    assert json.loads(capsys.readouterr().out)["records"] == 2
    assert json.loads((out / "receipt.json").read_text())["record_schema_version"] == "v2.1.0"
