#!/usr/bin/env python3
"""ML-003 synthetic mini-batch tests for the production-heads trainer extension.

Covers the ML-002 ``camera_production_heads_v1`` check/Done criteria:

* head shapes match the pinned contract (6 tensor heads; calibration is not one);
* the mask is label presence: a missing label is a zero mask and contributes
  neither loss nor gradient — it is never coerced into a zero target
  (``not_observed`` issues are masked, ``absent`` issues are explicit negatives);
* the synthetic mini-batch loss is finite, backward works, and gradients pass
  only through masked-in positions (backward-only-on-mask);
* the old focused silver checkpoint loads *only* through the explicit
  ``research_only=True`` research-baseline path, never as a production claim.

Run from the repository root::

    python3 -m pytest ml/camera_coach/tests/test_production_heads_trainer.py -q
"""

from __future__ import annotations

from pathlib import Path
import sys

import pytest
import torch

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.production_heads import (  # noqa: E402
    PRODUCTION_TENSOR_HEAD_ORDER,
    ProductionHeadsError,
    ProductionHeadsScorer,
    ProductionHeadsSpec,
    ResearchBaselineError,
    compute_production_heads_loss,
    load_research_baseline,
    supervision_from_release_label,
)

torch.set_num_threads(1)
SPEC = ProductionHeadsSpec.load()
RESEARCH_CHECKPOINT_SCHEMA_ID = "camera-silver-actions-stage2-checkpoint-v1"


def _full_issues(**status_by_id: str) -> list[dict[str, str]]:
    return [
        {"issue_id": issue_id, "status": status_by_id.get(issue_id, "not_observed")}
        for issue_id in SPEC.issue_ids
    ]


def _issue_entry(issue_id: str, status: str) -> list[dict[str, str]]:
    return [{"issue_id": entry["issue_id"], "status": (status if entry["issue_id"] == issue_id else "not_observed")}
            for entry in _full_issues()]


# --- spec ---------------------------------------------------------------------

def test_spec_matches_pinned_production_contracts() -> None:
    assert SPEC.contract_id == "camera-production-heads-v1"
    assert SPEC.issue_ids == tuple(
        ["subject_too_close_to_edge", "subject_not_prominent_enough", "background_competes_with_subject",
         "insufficient_look_space", "backlight_hides_subject", "scene_has_no_clear_focus",
         "frame_visually_overloaded", "horizon_distracts", "motion_blur", "defocus", "overexposure",
         "underexposure", "noise", "occlusion", "lens_smudge"]
    )
    assert len(SPEC.action_ids) == 26
    # The five mapped technical actions of DATA-002 must be present (GAP-3 fix).
    for technical in ("stabilize_camera", "refocus_subject", "reduce_exposure", "increase_exposure",
                      "avoid_occlusion"):
        assert technical in SPEC.action_ids
    # The four unsupported semantic actions and keep_current_setup must be excluded.
    for forbidden in ("rotate_subject_toward_light", "reposition_prop_for_balance",
                      "remove_background_hotspot", "simplify_background", "clean_lens",
                      "reduce_iso_noise", "keep_current_setup"):
        assert forbidden in SPEC.excluded_action_ids
        assert forbidden not in SPEC.action_ids
    assert SPEC.delta_axes == ("delta_x", "delta_y", "scale_delta", "light_delta", "horizon_delta")
    assert dict(SPEC.head_widths) == {
        "good_frame_probability": 1,
        "issue_logits": 15,
        "action_utility_logits": 26,
        "continuous_target_deltas": 5,
        "risk_probability": 1,
        "abstention_probability": 1,
    }


# --- shapes -------------------------------------------------------------------

def test_scorer_emits_exact_production_head_shapes() -> None:
    torch.manual_seed(3)
    model = ProductionHeadsScorer(SPEC, feature_dim=8, hidden_dim=16)
    outputs = model(torch.randn(3, 8))
    assert tuple(outputs.keys()) == PRODUCTION_TENSOR_HEAD_ORDER
    assert "calibration_artifact" not in outputs
    for head in PRODUCTION_TENSOR_HEAD_ORDER:
        assert outputs[head].shape == (3, SPEC.width(head))
        assert torch.isfinite(outputs[head]).all()


# --- mask semantics -----------------------------------------------------------

def test_absent_label_is_masked_and_not_a_zero_target() -> None:
    supervision = supervision_from_release_label(None, SPEC)
    for head in PRODUCTION_TENSOR_HEAD_ORDER:
        assert torch.all(supervision.masks[head] == 0.0), head
        assert torch.all(supervision.targets[head] == 0.0), head


def test_issue_status_semantics_present_absent_not_observed() -> None:
    issues = _full_issues()
    issues[SPEC.issue_ids.index("motion_blur")]["status"] = "present"
    issues[SPEC.issue_ids.index("noise")]["status"] = "absent"
    supervision = supervision_from_release_label({"issues": issues}, SPEC)
    targets = supervision.targets["issue_logits"][0]
    masks = supervision.masks["issue_logits"][0]
    present = SPEC.issue_ids.index("motion_blur")
    absent = SPEC.issue_ids.index("noise")
    not_observed = SPEC.issue_ids.index("defocus")
    assert (targets[present].item(), masks[present].item()) == (1.0, 1.0)
    assert (targets[absent].item(), masks[absent].item()) == (0.0, 1.0)  # explicit negative
    assert (targets[not_observed].item(), masks[not_observed].item()) == (0.0, 0.0)  # uncertainty
    assert masks.sum().item() == 2.0


def test_missing_label_and_explicit_zero_target_are_not_the_same_supervision() -> None:
    """A zero mask must behave differently from a zero target at mask 1."""

    def run_for(mask_value: float, target_value: float) -> tuple[float, float]:
        outputs = {
            head: torch.zeros(1, SPEC.width(head)) for head in PRODUCTION_TENSOR_HEAD_ORDER
        }
        logits = torch.full((1, 1), 0.75, requires_grad=True)
        outputs["good_frame_probability"] = logits
        result = compute_production_heads_loss(
            outputs,
            {head: torch.zeros(1, SPEC.width(head)) for head in PRODUCTION_TENSOR_HEAD_ORDER}
            | {"good_frame_probability": torch.tensor([[target_value]])},
            {head: torch.zeros(1, SPEC.width(head)) for head in PRODUCTION_TENSOR_HEAD_ORDER}
            | {"good_frame_probability": torch.tensor([[mask_value]])},
            SPEC,
        )
        result.total.backward()
        return float(result.total.detach()), float(logits.grad[0, 0])

    missing_loss, missing_grad = run_for(0.0, 0.0)
    negative_loss, negative_grad = run_for(1.0, 0.0)
    assert missing_loss == 0.0 and missing_grad == 0.0
    expected_negative_grad = float(torch.sigmoid(torch.tensor(0.75)))
    assert negative_loss > 0.0 and negative_grad == pytest.approx(expected_negative_grad, abs=1e-6)
    # Under a zero mask the target value is irrelevant: masking is not implemented
    # by substituting a zero target.
    zero_target_loss, zero_target_grad = run_for(0.0, 0.0)
    one_target_loss, one_target_grad = run_for(0.0, 1.0)
    assert zero_target_loss == one_target_loss and zero_target_grad == one_target_grad


def test_unsupported_and_app_only_actions_fail_closed() -> None:
    for action_id in ("rotate_subject_toward_light", "keep_current_setup", "clean_lens", "not_an_action"):
        with pytest.raises(ProductionHeadsError):
            supervision_from_release_label(
                {"action": {"action_id": action_id, "magnitude": {"status": "not_observed", "axis": None,
                                                                 "value": None, "unit": None}}},
                SPEC,
            )


def test_delta_absent_axis_is_masked_never_coerced_to_zero_target() -> None:
    label = {
        "action": {
            "action_id": "shift_frame_left",
            "magnitude": {"status": "observed", "axis": "delta_x", "value": -0.3, "unit": "normalized_delta"},
        }
    }
    supervision = supervision_from_release_label(label, SPEC)
    targets = supervision.targets["continuous_target_deltas"][0]
    masks = supervision.masks["continuous_target_deltas"][0]
    assert targets[0].item() == pytest.approx(-0.3, abs=1e-6) and masks[0].item() == 1.0
    for axis_index in range(1, 5):
        assert masks[axis_index].item() == 0.0  # absent axis masked...
        assert targets[axis_index].item() == 0.0  # ...and its placeholder is ignored, not a zero label.


# --- synthetic mini-batch: loss/backward --------------------------------------

def _mini_batch_supervisions() -> list:
    supervisions = []
    for index in range(4):
        issues = _full_issues()
        issues[SPEC.issue_ids.index("horizon_distracts")]["status"] = "present" if index % 2 == 0 else "absent"
        observed_magnitude = index == 1
        abstain = index == 3
        label = {
            "verdict": None if abstain else ("good" if index == 0 else "needs_fix"),
            "issues": issues,
            "action": None if abstain else {
                "action_id": SPEC.action_ids[index],
                "magnitude": {
                    "status": "observed" if observed_magnitude else "not_observed",
                    "axis": "delta_x" if observed_magnitude else None,
                    "value": 0.25 if observed_magnitude else None,
                    "unit": "normalized_delta" if observed_magnitude else None,
                },
            },
            "risk": {"status": "observed" if index == 2 else "not_observed",
                     "probability": 0.7 if index == 2 else None},
            "abstention": {"status": "abstain" if abstain else "none",
                           "reasons": ["ambiguous_subject"] if abstain else []},
        }
        supervisions.append(supervision_from_release_label(label, SPEC))
    return supervisions


def test_synthetic_minibatch_loss_is_finite_and_backward_reaches_only_masked_positions() -> None:
    supervisions = _mini_batch_supervisions()
    targets, masks = supervisions[0].collate(supervisions[1:])
    assert targets["issue_logits"].shape == (4, 15)
    assert masks["action_utility_logits"].shape == (4, 26)

    torch.manual_seed(11)
    model = ProductionHeadsScorer(SPEC, feature_dim=8, hidden_dim=16)
    features = torch.randn(4, 8)
    outputs = model(features)
    for head, tensor in outputs.items():
        tensor.retain_grad()
    result = compute_production_heads_loss(outputs, targets, masks, SPEC)
    assert torch.isfinite(result.total).all()
    for head in PRODUCTION_TENSOR_HEAD_ORDER:
        assert torch.isfinite(result.per_head[head]).all()
    result.total.backward()

    # The action head is supervised only where a corrective action was labelled
    # (rows 0-2); the abstaining row 3 and its never-labelled columns get no gradient.
    action_grad = outputs["action_utility_logits"].grad
    assert torch.count_nonzero(action_grad[3]) == 0
    assert torch.count_nonzero(action_grad[:3]) > 0
    # Rows 0-2 each label the corrective action SPEC.action_ids[row]; the
    # abstaining row 3 and every never-labelled column get no gradient.
    labelled_columns = [0, 1, 2]
    for row in range(3):
        for column in range(26):
            if column not in labelled_columns:
                assert action_grad[row, column].item() == 0.0
    # The good-frame head is masked exactly on the abstaining row.
    good_grad = outputs["good_frame_probability"].grad
    assert good_grad[3, 0].item() == 0.0
    assert good_grad[:3, 0].abs().sum().item() > 0.0
    # Risk was adjudicated only on row 2.
    risk_grad = outputs["risk_probability"].grad
    assert risk_grad[2, 0].item() != 0.0
    assert risk_grad[0, 0].item() == 0.0 and risk_grad[1, 0].item() == 0.0 and risk_grad[3, 0].item() == 0.0


def test_synthetic_minibatch_train_step_reduces_masked_loss() -> None:
    supervisions = _mini_batch_supervisions()
    targets, masks = supervisions[0].collate(supervisions[1:])
    torch.manual_seed(7)
    model = ProductionHeadsScorer(SPEC, feature_dim=8, hidden_dim=16)
    features = torch.randn(4, 8)
    optimizer = torch.optim.SGD(model.parameters(), lr=0.05)
    first_loss = None
    last_loss = None
    for _ in range(40):
        optimizer.zero_grad(set_to_none=True)
        outputs = model(features)
        result = compute_production_heads_loss(outputs, targets, masks, SPEC)
        assert torch.isfinite(result.total).all()
        result.total.backward()
        optimizer.step()
        first_loss = float(result.total.detach()) if first_loss is None else first_loss
        last_loss = float(result.total.detach())
    assert first_loss > 0.0 and last_loss > 0.0
    assert last_loss < first_loss
    # delta_y is never labelled in the batch: its dedicated head row must have
    # received exactly zero gradient (masking, not zero-target substitution).
    delta_grad = model.heads["continuous_target_deltas"].weight.grad
    assert torch.count_nonzero(delta_grad[1]) == 0
    assert torch.count_nonzero(delta_grad[0]) > 0  # delta_x was supervised once.


def test_fully_masked_head_keeps_total_differentiable() -> None:
    outputs = {head: torch.zeros(2, SPEC.width(head), requires_grad=True) for head in PRODUCTION_TENSOR_HEAD_ORDER}
    targets = {head: torch.zeros(2, SPEC.width(head)) for head in PRODUCTION_TENSOR_HEAD_ORDER}
    masks = {head: torch.zeros(2, SPEC.width(head)) for head in PRODUCTION_TENSOR_HEAD_ORDER}
    result = compute_production_heads_loss(outputs, targets, masks, SPEC)
    assert float(result.total.detach()) == 0.0
    result.total.backward()
    for head in PRODUCTION_TENSOR_HEAD_ORDER:
        assert outputs[head].grad is not None
        assert torch.count_nonzero(outputs[head].grad) == 0


# --- research baseline compatibility -----------------------------------------

def _write_research_checkpoint(
    tmp_path: Path,
    *,
    issue_width: int = 8,
    action_width: int = 26,
    flags: dict | None = None,
) -> Path:
    torch.manual_seed(0)
    state: dict[str, torch.Tensor] = {}
    widths = {
        "scene_class_logits": 8,
        "subjectness_roi_agreement_logits": 3,
        "issue_logits": issue_width,
        "action_utility_logits": action_width,
        "good_frame_probability": 1,
        "abstention_probability": 1,
        "risk_probability": 1,
        "continuous_target_deltas": 5,
    }
    for name, width in widths.items():
        state[f"heads.{name}.weight"] = torch.randn(width, 16)
        state[f"heads.{name}.bias"] = torch.zeros(width)
    payload = {
        "schema_id": RESEARCH_CHECKPOINT_SCHEMA_ID,
        "schema_version": "1.0.0",
        "epoch": 12,
        "context": {"note": "synthetic stand-in with the exact old payload shape"},
        "history": [],
        "model_state": state,
        "optimizer_state": {},
        "python_random_state": None,
        "torch_rng_state": None,
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
    }
    if flags:
        payload.update(flags)
    path = tmp_path / "epoch-0012.pt"
    torch.save(payload, path)
    return path


def test_research_baseline_requires_explicit_research_only_flag(tmp_path: Path) -> None:
    path = _write_research_checkpoint(tmp_path)
    with pytest.raises(ResearchBaselineError, match="research_only=True"):
        load_research_baseline(path)
    with pytest.raises(ResearchBaselineError, match="research_only=True"):
        load_research_baseline(path, research_only=False)
    baseline = load_research_baseline(path, research_only=True)
    assert baseline.research_only is True
    assert baseline.human_gold is False
    assert baseline.release_admissible is False
    assert baseline.production_admitted is False
    assert baseline.epoch == 12
    assert baseline.schema_id == RESEARCH_CHECKPOINT_SCHEMA_ID
    assert len(baseline.checkpoint_sha256) == 64
    assert baseline.trained_heads == ("issue_logits", "action_utility_logits", "continuous_target_deltas")
    # GAP-1: the production probability heads were never trained in the baseline.
    assert baseline.untrained_production_heads == ("good_frame_probability", "risk_probability",
                                                   "abstention_probability")
    # GAP-2/GAP-3: the baseline names the OLD head layout, not the production one.
    assert baseline.head_widths["issue_logits"] == 8
    assert baseline.head_widths["action_utility_logits"] == 26
    assert baseline.head_widths["continuous_target_deltas"] == 5


def test_research_baseline_rejects_payload_with_production_claim(tmp_path: Path) -> None:
    for flags in (
        {"research_only": False},
        {"human_gold": True},
        {"release_admissible": True},
    ):
        path = _write_research_checkpoint(tmp_path, flags=flags)
        with pytest.raises(ResearchBaselineError, match="research-only boundary"):
            load_research_baseline(path, research_only=True)


def test_research_baseline_rejects_non_focused_layout(tmp_path: Path) -> None:
    path = _write_research_checkpoint(tmp_path, issue_width=15)
    with pytest.raises(ResearchBaselineError, match="focused research layout"):
        load_research_baseline(path, research_only=True)


def test_baseline_state_cannot_load_into_the_production_head_layout(tmp_path: Path) -> None:
    """The compatibility boundary: old state does not silently fit production heads."""

    path = _write_research_checkpoint(tmp_path)
    baseline = load_research_baseline(path, research_only=True)
    model = ProductionHeadsScorer(SPEC, feature_dim=8, hidden_dim=16)
    with pytest.raises(RuntimeError):
        model.load_state_dict(dict(baseline.state_dict), strict=True)
