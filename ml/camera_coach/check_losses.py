"""Focused synthetic acceptance check for the M4-009 loss contract."""

from __future__ import annotations

import json
import math
from pathlib import Path
import sys

import torch

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from ml.camera_coach.losses import (
    DIRECT_LOSS_HEADS,
    LOSS_TERM_NAMES,
    LossConfig,
    LossError,
    LossWeights,
    compute_multitask_loss,
    focal_binary_cross_entropy,
)


ROOT = Path(__file__).resolve().parent
LOSS_CONFIG_PATH = ROOT / "configs" / "loss_weights.json"
LOSS_SCHEMA_PATH = ROOT / "configs" / "loss_weights.schema.json"


def _outputs(*, requires_grad: bool = True) -> dict[str, torch.Tensor]:
    def tensor(values: list[list[float]], width: int | None = None) -> torch.Tensor:
        value = torch.tensor(values, dtype=torch.float32)
        if width is not None:
            assert value.shape == (3, width)
        return value.requires_grad_(requires_grad)

    return {
        "scene_class_logits": tensor([[10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0], [-10.0, 10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0], [-10.0, -10.0, 10.0, -10.0, -10.0, -10.0, -10.0, -10.0]], 8),
        "subjectness_roi_agreement_logits": tensor([[10.0, -10.0, 10.0], [10.0, 10.0, -10.0], [-10.0, 10.0, 10.0]], 3),
        "issue_logits": tensor([[10.0, -10.0, 10.0, -10.0, 10.0, -10.0, 10.0, -10.0]] * 3, 8),
        "action_utility_logits": tensor([[10.0, -10.0] * 13] * 3, 26),
        "good_frame_probability": tensor([[0.9], [0.1], [0.8]], 1),
        "abstention_probability": tensor([[0.1], [0.2], [0.1]], 1),
        "risk_probability": tensor([[0.1], [0.2], [0.1]], 1),
        "continuous_target_deltas": tensor([[0.0] * 5] * 3, 5),
        "embedding": tensor([[0.0] * 128, [3.0] * 128, [3.0] * 128], 128),
    }


def _targets() -> dict[str, torch.Tensor]:
    return {
        "scene_class_logits": torch.tensor([0, 1, 2], dtype=torch.long),
        "subjectness_roi_agreement_logits": torch.tensor([[1.0, 0.0, 1.0], [1.0, 1.0, 0.0], [0.0, 1.0, 1.0]]),
        "issue_logits": torch.tensor([[1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0]] * 3),
        "action_utility_logits": torch.tensor([[1.0, 0.0] * 13] * 3),
        "good_frame_probability": torch.tensor([[1.0], [0.0], [1.0]]),
        "abstention_probability": torch.tensor([[0.0], [0.0], [0.0]]),
        "risk_probability": torch.tensor([[0.0], [0.0], [0.0]]),
        "continuous_target_deltas": torch.zeros(3, 5),
    }


def _pairs() -> dict[str, dict[str, torch.Tensor]]:
    return {
        "good_vs_harmful": {
            "indices": torch.tensor([[0, 1]]),
            "labels": torch.tensor([1.0]),
            "mask": torch.tensor([1.0]),
            "contrastive_labels": torch.tensor([0.0]),
        },
        "before_after": {
            "indices": torch.tensor([[1, 2]]),
            "labels": torch.tensor([0.0]),
            "mask": torch.tensor([1.0]),
            "contrastive_labels": torch.tensor([1.0]),
        },
    }


def _reject(operation, label: str) -> None:
    try:
        operation()
    except (LossError, ValueError, RuntimeError):
        return
    raise AssertionError(f"malformed loss input accepted: {label}")


def main() -> int:
    config = LossConfig.from_file(LOSS_CONFIG_PATH)
    schema = json.loads(LOSS_SCHEMA_PATH.read_text(encoding="utf-8"))
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {
        "config_version", "weights", "focal_gamma", "focal_alpha", "ranking_margin", "contrastive_margin"
    }
    assert set(config.weights.as_mapping()) == set(LOSS_TERM_NAMES)

    perfect_outputs = _outputs()
    perfect = compute_multitask_loss(
        perfect_outputs,
        _targets(),
        pair_labels=_pairs(),
        config=config,
    )
    assert torch.isfinite(perfect.total)
    assert perfect.ranking.item() == 0.0
    assert perfect.contrastive.item() == 0.0
    perfect.total.backward()
    assert all(
        parameter.grad is None or torch.isfinite(parameter.grad).all()
        for parameter in perfect_outputs.values()
    )

    wrong_outputs = _outputs()
    wrong_outputs["good_frame_probability"].data.copy_(torch.tensor([[0.1], [0.9], [0.2]]))
    wrong_outputs["embedding"].data.copy_(torch.zeros(3, 128))
    wrong = compute_multitask_loss(wrong_outputs, _targets(), pair_labels=_pairs(), config=config)
    assert wrong.total.item() > perfect.total.item()
    assert wrong.ranking.item() > perfect.ranking.item()
    assert wrong.contrastive.item() > perfect.contrastive.item()
    ranking_only_pairs = {
        name: {key: value for key, value in spec.items() if key != "contrastive_labels"}
        for name, spec in _pairs().items()
    }
    ranking_only = compute_multitask_loss(
        _outputs(), _targets(), pair_labels=ranking_only_pairs, config=config
    )
    assert ranking_only.contrastive.item() == 0.0

    # Sample-level masks must expand across every element before reduction:
    # all ones is identical to no mask, and a partial mask is the selected
    # sample mean rather than a value scaled by the head width.
    batch_mask_outputs = _outputs()
    issue_targets = {"issue_logits": _targets()["issue_logits"]}
    no_mask = compute_multitask_loss(
        batch_mask_outputs, issue_targets, config=config
    )
    all_ones_batch_mask = compute_multitask_loss(
        batch_mask_outputs,
        issue_targets,
        masks={"issue_logits": torch.ones(3)},
        config=config,
    )
    assert torch.allclose(no_mask.total, all_ones_batch_mask.total)
    partial_batch_mask = compute_multitask_loss(
        batch_mask_outputs,
        issue_targets,
        masks={"issue_logits": torch.tensor([1.0, 0.0, 1.0])},
        config=config,
    )
    expected_selected_issue = focal_binary_cross_entropy(
        batch_mask_outputs["issue_logits"][[0, 2]],
        issue_targets["issue_logits"][[0, 2]],
        gamma=config.focal_gamma,
        alpha=config.focal_alpha,
    )
    assert torch.allclose(partial_batch_mask.per_head["issue_logits"], expected_selected_issue)

    all_missing = {name: torch.zeros_like(value) for name, value in perfect_outputs.items()}
    for name, value in all_missing.items():
        value.requires_grad_(True)
    all_missing_masks = {
        name: torch.zeros_like(target, dtype=torch.float32)
        for name, target in _targets().items()
    }
    all_missing_masks["scene_class_logits"] = torch.zeros(3)
    empty_pairs = {
        name: {**spec, "mask": torch.zeros_like(spec["mask"])}
        for name, spec in _pairs().items()
    }
    missing = compute_multitask_loss(
        all_missing,
        _targets(),
        masks=all_missing_masks,
        pair_labels=empty_pairs,
        config=config,
    )
    assert missing.total.item() == 0.0
    missing.total.backward()
    assert all(
        parameter.grad is not None and torch.count_nonzero(parameter.grad) == 0
        for parameter in all_missing.values()
    )

    partial_outputs = _outputs()
    partial_mask = {"issue_logits": torch.ones(3, 8)}
    partial_mask["issue_logits"][1, 3] = 0.0
    partial = compute_multitask_loss(
        partial_outputs,
        {"issue_logits": _targets()["issue_logits"]},
        masks=partial_mask,
        config=config,
    )
    partial.total.backward()
    assert partial_outputs["issue_logits"].grad is not None
    assert partial_outputs["issue_logits"].grad[1, 3].item() == 0.0
    assert torch.count_nonzero(partial_outputs["issue_logits"].grad).item() > 0

    bad_weights = config.weights.as_mapping()
    bad_weights["ranking"] = float("nan")
    _reject(lambda: LossWeights.from_mapping(bad_weights), "non-finite weight")
    bad_weights = config.weights.as_mapping()
    bad_weights["unexpected"] = 1.0
    _reject(lambda: LossWeights.from_mapping(bad_weights), "unknown weight")
    bad_config = config.as_mapping()
    bad_config["focal_gamma"] = "not-a-number"
    _reject(lambda: LossConfig.from_mapping(bad_config), "malformed focal gamma")
    _reject(
        lambda: compute_multitask_loss(
            _outputs(requires_grad=False),
            {"issue_logits": torch.zeros(1, 7)},
            config=config,
        ),
        "wrong target shape",
    )
    _reject(
        lambda: compute_multitask_loss(
            {**_outputs(requires_grad=False), "issue_logits": torch.full((3, 8), float("nan"))},
            {"issue_logits": torch.zeros(1, 8)},
            config=config,
        ),
        "non-finite prediction",
    )
    _reject(
        lambda: compute_multitask_loss(
            _outputs(requires_grad=False),
            {"issue_logits": torch.zeros(3, 8)},
            masks={"issue_logits": torch.full((3, 8), 0.5)},
            config=config,
        ),
        "non-binary mask",
    )
    _reject(
        lambda: compute_multitask_loss(
            _outputs(requires_grad=False),
            {},
            contrastive_pairs={"before_after": {"indices": [[0, 0]]}},
            config=config,
        ),
        "missing contrastive labels",
    )
    _reject(
        lambda: compute_multitask_loss(
            _outputs(requires_grad=False),
            {},
            contrastive_pairs={"unapproved": {"indices": [[0, 0]], "contrastive_labels": [1.0]}},
            config=config,
        ),
        "unknown pair set",
    )
    _reject(
        lambda: compute_multitask_loss(
            {"issue_logits": torch.zeros(1, 8)},
            {"issue_logits": torch.zeros(1, 8)},
            config=config,
        ),
        "missing output head",
    )

    print(json.dumps({
        "status": "pass",
        "direct_loss_heads": list(DIRECT_LOSS_HEADS),
        "loss_terms": list(LOSS_TERM_NAMES),
        "perfect_total": perfect.total.item(),
        "wrong_total": wrong.total.item(),
        "perfect_ranking": perfect.ranking.item(),
        "wrong_ranking": wrong.ranking.item(),
        "perfect_contrastive": perfect.contrastive.item(),
        "wrong_contrastive": wrong.contrastive.item(),
        "missing_total": missing.total.item(),
        "missing_gradients_zero": True,
        "missing_label_gradient_zero": True,
        "malformed_inputs_rejected": True,
    }, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
