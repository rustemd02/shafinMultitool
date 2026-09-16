#!/usr/bin/env python3
"""M01 tests: typed records, masked losses, direction-preserving flip, resume.

Run from the repository root::

    python3 -m pytest ml/camera_coach/tests/ -q
"""

from __future__ import annotations

from dataclasses import replace
import json
from pathlib import Path
import sys
import tempfile

import pytest
import torch

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.data.training_records import (  # noqa: E402
    FamilyBalancedSampler,
    TrainingRecordError,
    apply_horizontal_flip,
    eligible_ranking_pairs,
    intent_head_mask,
    load_records,
    parse_record,
)
from ml.camera_coach.losses import LossConfig, compute_multitask_loss  # noqa: E402
from ml.camera_coach.models.set_composition_net_v2 import (  # noqa: E402
    INTENT_CONDITIONED_HEAD_ORDER,
    SETCompositionNetV2CandidateB,
    SETCompositionNetV2Manifest,
)
from ml.camera_coach.trainer_records import (  # noqa: E402
    RecordsTrainingConfig,
    train_one_seed,
)

CONFIG_PATH = REPO_ROOT / "ml" / "camera_coach" / "configs" / "production_records_smoke.json"
RECORDS_PATH = REPO_ROOT / "ml" / "camera_coach" / "configs" / "production_records_smoke.jsonl"
LOSS_PATH = REPO_ROOT / "ml" / "camera_coach" / "configs" / "loss_weights.json"

torch.set_num_threads(1)
CONTRACT = SETCompositionNetV2Manifest.load()


def _base_record(**overrides) -> dict:
    record = {
        "schema_id": "camera-training-record-v2",
        "schema_version": "v2.0.0",
        "record_id": "cam-test-0001",
        "split": "train",
        "source_family_id": "shoot-test",
        "matrix_class": "single_person",
        "capture_intent": {"styles": ["natural"], "known": True},
        "roi_normalized_xywh": [0.2, 0.2, 0.4, 0.4],
        "pixels": {
            "width": 4,
            "height": 4,
            "values": [((x * 17 + y * 29 + c * 53) % 256) for y in range(4) for x in range(4) for c in range(3)],
        },
        "scalar_features": None,
        "missing_feature_mask": None,
        "targets": {
            "scene_class": "single_character_medium",
            "subjectness": {"subjectness": 1, "roi_agreement": 1, "ambiguity": 0},
            "issues": {"reviewed": True, "present": ["horizon_distracts"]},
            "utility": {"reviewed": True, "acceptable": ["shift_frame_left"], "forbidden": ["step_closer"]},
            "good_frame": 1,
            "abstention": 0,
            "risk": 0,
            "target_deltas": {
                "delta_x": 0.3,
                "delta_y": None,
                "scale_delta": None,
                "light_delta": None,
                "horizon_delta": None,
            },
        },
        "ranking": [],
    }
    record.update(overrides)
    return record


def _valid_record(**overrides):
    return parse_record(_base_record(**overrides), CONTRACT)


def test_absent_delta_is_masked_not_zero_target() -> None:
    record = _valid_record()
    delta_mask = record.masks["continuous_target_deltas"]
    assert delta_mask.tolist() == [1.0, 0.0, 0.0, 0.0, 0.0]
    assert record.targets["continuous_target_deltas"][1].item() == 0.0
    assert delta_mask[1].item() == 0.0


def test_unreviewed_issues_are_unknown_not_negative() -> None:
    record = _valid_record(
        targets={**_base_record()["targets"], "issues": {"reviewed": False, "present": []}}
    )
    assert record.masks["issue_logits"].tolist() == [0.0] * 8
    assert record.targets["issue_logits"].sum().item() == 0.0


def test_forbidden_action_has_its_own_meaning() -> None:
    record = _valid_record()
    utility_names = list(CONTRACT.output_head_specs["action_utility_logits"]["ordered_names"])
    values = record.targets["action_utility_logits"]
    mask = record.masks["action_utility_logits"]
    forbidden = utility_names.index("step_closer")
    acceptable = utility_names.index("shift_frame_left")
    untouched = utility_names.index("keep_current_setup")
    assert (values[forbidden].item(), mask[forbidden].item()) == (0.0, 1.0)
    assert (values[acceptable].item(), mask[acceptable].item()) == (1.0, 1.0)
    # An approved action that was neither accepted nor forbidden is unknown.
    assert mask[untouched].item() == 0.0


def test_intent_conditioned_label_without_intent_fails_closed() -> None:
    with pytest.raises(TrainingRecordError, match="not admissible"):
        _valid_record(capture_intent={"styles": [], "known": False})


def test_intent_conditioned_label_without_roi_fails_closed() -> None:
    with pytest.raises(TrainingRecordError, match="not admissible"):
        _valid_record(roi_normalized_xywh=None)


def test_unknown_intent_gets_zero_intent_mask() -> None:
    record = _valid_record(
        capture_intent={"styles": [], "known": False},
        targets={
            **_base_record()["targets"],
            "utility": {"reviewed": False, "acceptable": [], "forbidden": []},
            "good_frame": None,
            "risk": None,
            "target_deltas": {name: None for name in ("delta_x", "delta_y", "scale_delta", "light_delta", "horizon_delta")},
        },
    )
    assert intent_head_mask([record], CONTRACT).tolist() == [[0.0, 0.0, 0.0, 0.0]]


def test_overlapping_accepted_and_forbidden_fails_closed() -> None:
    targets = {
        **_base_record()["targets"],
        "utility": {"reviewed": True, "acceptable": ["step_closer"], "forbidden": ["step_closer"]},
    }
    with pytest.raises(TrainingRecordError, match="both acceptable and forbidden"):
        _valid_record(targets=targets)


def test_unreviewed_catalog_with_labels_fails_closed() -> None:
    targets = {
        **_base_record()["targets"],
        "issues": {"reviewed": False, "present": ["horizon_distracts"]},
    }
    with pytest.raises(TrainingRecordError, match="unlabeled issues must stay unknown"):
        _valid_record(targets=targets)
    targets = {
        **_base_record()["targets"],
        "utility": {"reviewed": False, "acceptable": ["step_closer"], "forbidden": []},
    }
    with pytest.raises(TrainingRecordError, match="unreviewed catalog must stay unknown"):
        _valid_record(targets=targets)


def test_delta_out_of_range_fails_closed() -> None:
    targets = {
        **_base_record()["targets"],
        "target_deltas": {
            "delta_x": 1.5,
            "delta_y": None,
            "scale_delta": None,
            "light_delta": None,
            "horizon_delta": None,
        },
    }
    with pytest.raises(TrainingRecordError, match=r"within \[-1, 1\]"):
        _valid_record(targets=targets)


def test_horizontal_flip_remaps_directions_and_roi() -> None:
    record = _valid_record()
    flipped = apply_horizontal_flip(record, CONTRACT)
    utility_names = list(CONTRACT.output_head_specs["action_utility_logits"]["ordered_names"])
    left = utility_names.index("shift_frame_left")
    right = utility_names.index("shift_frame_right")
    assert record.targets["action_utility_logits"][left].item() == 1.0
    assert flipped.targets["action_utility_logits"][right].item() == 1.0
    assert flipped.targets["action_utility_logits"][left].item() == 0.0
    assert flipped.masks["action_utility_logits"][right].item() == 1.0
    # delta_x is lateral and flips sign.
    assert flipped.targets["continuous_target_deltas"][0].item() == pytest.approx(-0.3)
    # ROI mirrors and the flip is an involution.
    assert flipped.roi == pytest.approx((1.0 - 0.2 - 0.4, 0.2, 0.4, 0.4))
    assert apply_horizontal_flip(flipped, CONTRACT).roi == pytest.approx(record.roi)
    assert torch.equal(apply_horizontal_flip(flipped, CONTRACT).pixels, record.pixels)


def test_masked_targets_contribute_no_loss_or_gradient() -> None:
    batch = 2
    outputs = {
        "scene_class_logits": torch.zeros(batch, 8, requires_grad=True),
        "subjectness_roi_agreement_logits": torch.zeros(batch, 3, requires_grad=True),
        "issue_logits": torch.zeros(batch, 8, requires_grad=True),
        "action_utility_logits": torch.zeros(batch, 26, requires_grad=True),
        "good_frame_probability": torch.full((batch, 1), 0.5, requires_grad=True),
        "abstention_probability": torch.full((batch, 1), 0.5, requires_grad=True),
        "risk_probability": torch.full((batch, 1), 0.5, requires_grad=True),
        "continuous_target_deltas": torch.zeros(batch, 5, requires_grad=True),
        "embedding": torch.zeros(batch, 128, requires_grad=True),
    }
    targets = {
        "scene_class_logits": torch.tensor([1, 1]),
        "subjectness_roi_agreement_logits": torch.tensor([[1.0, 1.0, 0.0], [1.0, 1.0, 0.0]]),
        "issue_logits": torch.zeros(batch, 8),
        "action_utility_logits": torch.zeros(batch, 26),
        "good_frame_probability": torch.ones(batch, 1),
        "abstention_probability": torch.zeros(batch, 1),
        "risk_probability": torch.zeros(batch, 1),
        "continuous_target_deltas": torch.full((batch, 5), 0.25),
    }
    masks = {name: torch.ones_like(value) for name, value in targets.items() if name != "scene_class_logits"}
    masks["scene_class_logits"] = torch.ones(batch, 1)
    # All delta labels are masked out.
    masks["continuous_target_deltas"] = torch.zeros(batch, 5)
    config = LossConfig.from_file(LOSS_PATH)

    result_a = compute_multitask_loss(outputs, targets, masks=masks, config=config)
    targets_changed = {**targets, "continuous_target_deltas": torch.full((batch, 5), -0.9)}
    result_b = compute_multitask_loss(outputs, targets_changed, masks=masks, config=config)
    assert result_a.per_head["continuous_target_deltas"].item() == 0.0
    assert torch.allclose(result_a.total, result_b.total)
    result_a.total.backward()
    assert outputs["continuous_target_deltas"].grad is not None
    assert torch.count_nonzero(outputs["continuous_target_deltas"].grad).item() == 0
    # A zero intent mask silences every intent-conditioned head.
    intent_mask = torch.zeros(batch, len(INTENT_CONDITIONED_HEAD_ORDER))
    all_on = {name: torch.ones_like(value) for name, value in targets.items()}
    all_on["scene_class_logits"] = torch.ones(batch, 1)
    silent = compute_multitask_loss(outputs, targets, masks=all_on, intent_mask=intent_mask, config=config)
    for head in INTENT_CONDITIONED_HEAD_ORDER:
        assert silent.per_head[head].item() == 0.0, head


def test_family_sampler_state_restores_stream() -> None:
    records = load_records(RECORDS_PATH)
    train = [record for record in records if record.split == "train"]
    first = FamilyBalancedSampler(train, seed=7)
    first.epoch_indices()
    state = first.state_dict()
    second_indices = first.epoch_indices()
    resumed = FamilyBalancedSampler(train, seed=999)
    resumed.load_state_dict(state)
    assert resumed.epoch_indices() == second_indices


def test_eligible_ranking_pairs_skip_inadmissible() -> None:
    records = load_records(RECORDS_PATH)
    pairs = eligible_ranking_pairs(records)
    assert (0, 1, 1) in pairs and (1, 0, 0) in pairs
    by_index = {record.record_id: index for index, record in enumerate(records)}
    # The t08 -> t03 entry points at an inadmissible record and must be dropped.
    assert by_index["cam-smoke-t08"] not in {pair[0] for pair in pairs}


def test_effective_supervision_retains_admissible_ranking_only_rows() -> None:
    from ml.camera_coach.trainer_records import _supervised_records

    targets = {"scene_class": None, "subjectness": {"subjectness": None, "roi_agreement": None, "ambiguity": None},
        "issues": {"reviewed": False, "present": []}, "utility": {"reviewed": False, "acceptable": [], "forbidden": []},
        "good_frame": None, "abstention": None, "risk": None,
        "target_deltas": {name: None for name in ("delta_x", "delta_y", "scale_delta", "light_delta", "horizon_delta")}}
    left = _valid_record(record_id="ranking-left", targets=targets,
                         ranking=[{"other_record_id": "ranking-right", "preference": 1}])
    right = _valid_record(record_id="ranking-right", targets=targets)
    trained = {"good_frame_probability": True}
    assert _supervised_records([left, right], trained) == []
    assert [record.record_id for record in _supervised_records([left, right], trained, ranking_enabled=True)] == [
        "ranking-left", "ranking-right"]


def _tiny_config() -> RecordsTrainingConfig:
    config = RecordsTrainingConfig.from_file(CONFIG_PATH)
    training = replace(config.training, epochs=2, batch_size=4, early_stop_patience=2, class_weight_max=5.0)
    return replace(config, seeds=(7,), training=training)


def _train(config, run_dir, *, resume_from=None, interrupt_after_epoch=None):
    records = load_records(RECORDS_PATH, config.dataset.sha256)
    return train_one_seed(
        config,
        seed=7,
        run_dir=run_dir,
        contract=CONTRACT,
        loss_config=LossConfig.from_file(LOSS_PATH),
        records=records,
        resume_from=resume_from,
        interrupt_after_epoch=interrupt_after_epoch,
    )


def test_checkpoint_resume_matches_continuous_run() -> None:
    config = _tiny_config()
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        continuous_dir = root / "continuous"
        interrupted_dir = root / "interrupted"
        resumed_dir = root / "resumed"
        for path in (continuous_dir, interrupted_dir, resumed_dir):
            path.mkdir()

        continuous = _train(config, continuous_dir)
        _train(config, interrupted_dir, interrupt_after_epoch=1)
        resumed = _train(config, resumed_dir, resume_from=interrupted_dir / "checkpoint.pt")

        assert len(continuous["history"]) == 2 and len(resumed["history"]) == 2
        assert continuous["component_supervision"] == resumed["component_supervision"]
        assert continuous["final_component_supervision"] == resumed["final_component_supervision"]
        assert resumed["final_component_supervision"]["successful_optimizer_steps"] == sum(
            row["optimizer_steps"] for row in resumed["history"])
        for epoch in (1, 2):
            assert resumed["history"][epoch - 1]["train_loss"] == pytest.approx(
                continuous["history"][epoch - 1]["train_loss"], rel=0, abs=1e-9
            )
            assert resumed["history"][epoch - 1]["validation_loss"] == pytest.approx(
                continuous["history"][epoch - 1]["validation_loss"], rel=0, abs=1e-9
            )
        continuous_best = torch.load(continuous_dir / "best.pt", map_location="cpu", weights_only=False)
        resumed_best = torch.load(resumed_dir / "best.pt", map_location="cpu", weights_only=False)
        assert continuous_best["epoch"] == resumed_best["epoch"]
        for name, value in continuous_best["model_state"].items():
            assert torch.allclose(value, resumed_best["model_state"][name], atol=1e-7), name


def test_train_step_changes_trained_parameters_and_masks_untrained_head() -> None:
    config = _tiny_config()
    masked_config = replace(
        config,
        training=replace(
            config.training,
            trained_heads=tuple(
                name for name in config.training.trained_heads if name != "continuous_target_deltas"
            ),
        ),
    )
    torch.manual_seed(7)
    initial = SETCompositionNetV2CandidateB(CONTRACT).state_dict()
    with tempfile.TemporaryDirectory() as temporary:
        run_dir = Path(temporary) / "run"
        run_dir.mkdir()
        result = _train(masked_config, run_dir)
        assert result["trained_head_mask"]["continuous_target_deltas"] is False
        assert any(name.startswith("heads.continuous_target_deltas") for name in initial)
        selected = torch.load(run_dir / "best.pt", map_location="cpu", weights_only=False)["model_state"]
        changed = [
            name for name, value in initial.items()
            if name.startswith("heads.") and not name.startswith("heads.continuous_target_deltas")
            and not torch.allclose(value, selected[name])
        ]
        assert changed, "trained head parameters did not move"
        for name, value in initial.items():
            if name.startswith("heads.continuous_target_deltas"):
                assert torch.allclose(value, selected[name]), f"masked head moved: {name}"


def test_declared_admission_requires_rights_manifest() -> None:
    raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    raw["dataset"]["admission"] = "declared_admitted"
    raw["dataset"]["rights_manifest_sha256"] = None
    with pytest.raises(Exception):
        RecordsTrainingConfig.from_mapping(raw)


# --- M01 review fixes: D1 horizon mirror, D2 multi-seed resume, D4 missing mask ---


def _scalar_vector(**values: float) -> list[float]:
    names = list(CONTRACT.raw["inputs"]["scalar_features"]["ordered_names"])
    vector = [0.0] * len(names)
    for name, value in values.items():
        vector[names.index(name)] = value
    return vector


def _delta_vector(**values: float) -> dict:
    axes = list(CONTRACT.output_head_specs["continuous_target_deltas"]["ordered_names"])
    return {axis: values.get(axis) for axis in axes}


def test_horizontal_flip_negates_horizon_delta_and_angle() -> None:
    """D1: a mirror reverses scene roll, so a signed horizon must change sign."""

    record = _valid_record(
        targets={
            **_base_record()["targets"],
            "target_deltas": _delta_vector(delta_x=0.3, horizon_delta=0.4),
        },
        scalar_features=_scalar_vector(horizon_angle=0.25, saliency_left_right_balance=0.5),
    )
    flipped = apply_horizontal_flip(record, CONTRACT)
    delta_names = list(CONTRACT.output_head_specs["continuous_target_deltas"]["ordered_names"])
    horizon = delta_names.index("horizon_delta")
    assert flipped.targets["continuous_target_deltas"][horizon].item() == pytest.approx(-0.4)
    assert flipped.masks["continuous_target_deltas"][horizon].item() == 1.0
    scalar_names = list(CONTRACT.raw["inputs"]["scalar_features"]["ordered_names"])
    assert flipped.scalar_features[scalar_names.index("horizon_angle")].item() == pytest.approx(-0.25)
    assert flipped.scalar_features[scalar_names.index("saliency_left_right_balance")].item() == pytest.approx(-0.5)
    # The flip stays an involution for the signed axes.
    restored = apply_horizontal_flip(flipped, CONTRACT)
    assert restored.targets["continuous_target_deltas"][horizon].item() == pytest.approx(0.4)
    assert restored.scalar_features[scalar_names.index("horizon_angle")].item() == pytest.approx(0.25)


def test_horizontal_flip_does_not_revive_missing_scalars() -> None:
    """D4: features flagged missing keep their fill value and mask under the flip."""

    names = list(CONTRACT.raw["inputs"]["scalar_features"]["ordered_names"])
    missing = [0] * len(names)
    for name in ("subject_bbox_x", "mirroring_flag", "horizon_angle"):
        missing[names.index(name)] = 1
    record = _valid_record(scalar_features=_scalar_vector(), missing_feature_mask=missing)
    flipped = apply_horizontal_flip(record, CONTRACT)
    for name in ("subject_bbox_x", "mirroring_flag", "horizon_angle"):
        value = flipped.scalar_features[names.index(name)].item()
        assert value == 0.0, f"missing scalar {name} was revived to {value}"
    assert torch.equal(flipped.missing_feature_mask, record.missing_feature_mask)


def test_horizontal_flip_swaps_present_partners_only() -> None:
    """D4: a swap must not move a present value into a missing slot."""

    names = list(CONTRACT.raw["inputs"]["scalar_features"]["ordered_names"])
    missing = [0] * len(names)
    missing[names.index("subject_edge_pressure_right")] = 1
    record = _valid_record(
        scalar_features=_scalar_vector(subject_edge_pressure_left=0.6),
        missing_feature_mask=missing,
    )
    flipped = apply_horizontal_flip(record, CONTRACT)
    assert flipped.scalar_features[names.index("subject_edge_pressure_left")].item() == pytest.approx(0.6)
    assert flipped.scalar_features[names.index("subject_edge_pressure_right")].item() == 0.0
    assert torch.equal(flipped.missing_feature_mask, record.missing_feature_mask)


def test_multi_seed_resume_from_is_rejected() -> None:
    """D2: resume_from with more than one seed must fail closed, not become a no-op."""

    raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    raw["seeds"] = [11, 22]
    raw["resume_from"] = "/tmp/does-not-matter.pt"
    with pytest.raises(Exception, match="exactly one seed"):
        RecordsTrainingConfig.from_mapping(raw)


def test_multi_seed_resume_from_fails_closed_through_run_entrypoint(tmp_path) -> None:
    """D2: the run entry point itself refuses a silently ignored resume."""

    from ml.camera_coach.trainer_records import run_records_training

    config = RecordsTrainingConfig.from_file(CONFIG_PATH)
    config = replace(config, seeds=(11, 22), resume_from="/tmp/does-not-matter.pt")
    with pytest.raises(Exception, match="exactly one seed"):
        run_records_training(config, config_path=CONFIG_PATH, run_dir=tmp_path / "run")


def test_resume_semantics_ignore_orchestration_only_fields() -> None:
    """D5: resume compatibility must not depend on output_root or resume_from."""

    from ml.camera_coach.trainer_records import resume_semantic_sha256

    config = RecordsTrainingConfig.from_file(CONFIG_PATH)
    assert resume_semantic_sha256(config) == resume_semantic_sha256(
        replace(config, output_root="/somewhere/else")
    )
    assert resume_semantic_sha256(config) == resume_semantic_sha256(
        replace(config, resume_from="/tmp/checkpoint.pt")
    )
    assert resume_semantic_sha256(config) != resume_semantic_sha256(replace(config, device="cuda"))


def test_colab_installed_runtime_profile_is_explicit() -> None:
    """D3: the declared Colab profile parses; it may not smuggle a wheel lock."""

    raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    raw["runtime_profile"] = "colab_installed_runtime"
    raw["lock_sha256"] = None
    raw["device"] = "cuda"
    config = RecordsTrainingConfig.from_mapping(raw)
    assert config.runtime_profile == "colab_installed_runtime"
    assert config.device == "cuda" and config.lock_sha256 is None
    with pytest.raises(Exception, match="lock_sha256 must be null"):
        RecordsTrainingConfig.from_mapping({**raw, "lock_sha256": "0" * 64})
    with pytest.raises(Exception, match="pinned_local"):
        RecordsTrainingConfig.from_mapping(
            {**json.loads(CONFIG_PATH.read_text(encoding="utf-8")), "device": "cuda"}
        )
    with pytest.raises(Exception, match="runtime_profile"):
        RecordsTrainingConfig.from_mapping({**raw, "runtime_profile": "colab_anything_goes"})


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
