"""Component provenance uses effective losses and completed steps, not head flags."""
import copy
from dataclasses import replace
import json

import pytest
import torch

from ml.camera_coach.component_supervision import (
    CHECKPOINT_VERSION, LEGACY_CHECKPOINT_VERSION, SupervisionError, batch_supervision,
    checkpoint_supervision, component_names, export_metadata, new_supervision,
    record_successful_step, validate_supervision,
)
from ml.camera_coach import trainer_records as trainer, export_v2
from ml.camera_coach.data.training_records import load_records
from ml.camera_coach.losses import DIRECT_LOSS_HEADS, LossConfig
from ml.camera_coach.tests.test_train_records_v2 import CONTRACT, LOSS_PATH, RECORDS_PATH, _tiny_config

SOURCE = {"observed_records_sha256":"a"*64}
LOSS = LossConfig.from_file(LOSS_PATH)


@pytest.fixture(autouse=True)
def one_cpu_thread():
    before = torch.get_num_threads()
    torch.set_num_threads(1)
    yield
    torch.set_num_threads(before)


def tensors():
    outputs = {head:torch.zeros(2, CONTRACT.output_head_shapes[head]) for head in DIRECT_LOSS_HEADS}
    targets = {head:torch.zeros_like(value) for head,value in outputs.items()}
    targets["scene_class_logits"] = torch.zeros(2, dtype=torch.long)
    masks = {head:torch.zeros_like(value) for head,value in targets.items()}
    return outputs, targets, masks, torch.zeros(2, 4)


def collect(values, loss=LOSS, **kwargs):
    return batch_supervision(*values, loss, ["a", "b"], **kwargs)


def test_partial_issue_counts_require_successful_step_and_keep_seven_unknown_targets():
    values = tensors()
    values[2]["issue_logits"][:,0] = 1
    values[1]["issue_logits"][0,0] = 1
    state = new_supervision(CONTRACT, SOURCE)
    delta = collect(values)
    assert state["successful_optimizer_steps"] == 0
    record_successful_step(state, delta)
    state = validate_supervision(state, CONTRACT)
    issue = state["heads"]["issue_logits"]
    assert issue["observations"] == [2]+[0]*7
    assert issue["targets_equal_one"] == [1]+[0]*7
    assert issue["targets_equal_zero"] == [1]+[0]*7
    assert issue["optimizer_steps"] == [1]+[0]*7
    evidence = export_metadata(state, CONTRACT, required_components={"issue_logits":[component_names(CONTRACT)["issue_logits"][0]]})
    assert evidence["aggregate_trained_head_mask"]["issue_logits"] is True
    assert evidence["release_admissible"] is False
    with pytest.raises(SupervisionError, match="subject_not_prominent"):
        export_metadata(state, CONTRACT, required_components={"issue_logits":[component_names(CONTRACT)["issue_logits"][1]]})


def test_intent_head_and_zero_loss_masks_cannot_create_component_evidence():
    values = tensors()
    values[2]["action_utility_logits"][:] = 1
    values[2]["issue_logits"][:] = 1
    loss = replace(LOSS, weights=replace(LOSS.weights, issue_logits=0))
    delta = collect(values, loss)
    assert not delta["has_supervision"]
    with pytest.raises(SupervisionError, match="fully masked"):
        record_successful_step(new_supervision(CONTRACT, SOURCE), delta)


def test_known_zero_delta_is_counted_while_missing_deltas_are_not():
    values = tensors()
    values[3][:] = 1
    values[2]["continuous_target_deltas"][:,0] = 1
    delta = collect(values)
    assert delta["heads"]["continuous_target_deltas"]["observations"] == [2,0,0,0,0]
    assert delta["heads"]["continuous_target_deltas"]["targets_equal_zero"] == [2,0,0,0,0]


def test_ranking_does_not_claim_absolute_good_frame_supervision():
    state = new_supervision(CONTRACT, SOURCE)
    record_successful_step(state, collect(tensors(), ranking_pairs=1))
    assert state["ranking_pairs"] == 1
    assert state["heads"]["good_frame_probability"]["observations"] == [0]
    with pytest.raises(SupervisionError, match="good_frame"):
        export_metadata(state, CONTRACT, required_components={"good_frame_probability":["good_frame_probability"]})


def test_zero_focal_alpha_does_not_count_positive_labels():
    values = tensors()
    values[2]["issue_logits"][:,0] = 1
    values[1]["issue_logits"][0,0] = 1
    delta = collect(values, replace(LOSS, focal_alpha=0))
    assert delta["heads"]["issue_logits"]["observations"][0] == 1


def test_legacy_aggregate_flag_is_unknown_and_cannot_meet_required_components():
    state = checkpoint_supervision({"checkpoint_version":LEGACY_CHECKPOINT_VERSION,
        "trained_head_mask":{"issue_logits":True}}, CONTRACT)
    assert state["legacy_prefix_unknown"]
    assert export_metadata(state, CONTRACT)["component_status"]["issue_logits"] == ["unknown"]*8
    with pytest.raises(SupervisionError, match="unknown/missing"):
        export_metadata(state, CONTRACT, required_components={"issue_logits":[component_names(CONTRACT)["issue_logits"][0]]})
    with pytest.raises(SupervisionError, match="missing required"):
        checkpoint_supervision({"checkpoint_version":CHECKPOINT_VERSION}, CONTRACT)


@pytest.mark.parametrize("kind", ["order", "false_count", "bad_mask", "source"])
def test_component_evidence_rejects_inconsistency(kind):
    state = new_supervision(CONTRACT, SOURCE)
    if kind == "bad_mask":
        values = tensors(); values[2]["issue_logits"][0,0] = float("nan")
        with pytest.raises(SupervisionError): collect(values)
        return
    if kind == "order": state["heads"]["issue_logits"]["ordered_names"].reverse()
    if kind == "false_count": state["heads"]["issue_logits"]["observations"][0] = 4
    with pytest.raises(SupervisionError):
        validate_supervision(state, CONTRACT, source={"observed_records_sha256":"b"*64} if kind == "source" else None)


def partial_records():
    records = load_records(RECORDS_PATH)
    result = []
    for record in records:
        masks = {name:torch.zeros_like(value) for name,value in record.masks.items()}
        masks["issue_logits"][0] = 1
        result.append(replace(record, masks=masks, ranking=()))
    return result


def run_fixture(path, *, resume=None, interrupt=None, config=None):
    config = config or replace(_tiny_config(), training=replace(_tiny_config().training,
        trained_heads=("issue_logits",), batch_size=32))
    path.mkdir()
    return config, trainer.train_one_seed(config, seed=7, run_dir=path, contract=CONTRACT,
        loss_config=LOSS, records=partial_records(), resume_from=resume, interrupt_after_epoch=interrupt)


def test_real_trainer_partial_head_selected_snapshot_and_legacy_resume(tmp_path, monkeypatch):
    # Constant validation selects the first state. Later observations may not be
    # attributed to that earlier state, including after resuming a legacy file.
    monkeypatch.setattr(trainer, "_validate", lambda *a,**kw:(0.1, {h:0. for h in DIRECT_LOSS_HEADS}))
    config, first = run_fixture(tmp_path/"first", interrupt=1)
    original = tmp_path/"first/checkpoint.pt"
    original_bytes = original.read_bytes()
    payload = torch.load(original, weights_only=True)
    assert payload["checkpoint_version"] == CHECKPOINT_VERSION
    assert payload["component_supervision"]["heads"]["issue_logits"]["observations"][1:] == [0]*7
    _, resumed = run_fixture(tmp_path/"resumed", resume=original, config=config)
    assert resumed["component_supervision"] == first["component_supervision"]
    assert resumed["final_component_supervision"]["successful_optimizer_steps"] == 2
    assert original.read_bytes() == original_bytes
    legacy = copy.deepcopy(payload)
    legacy["checkpoint_version"] = LEGACY_CHECKPOINT_VERSION
    legacy.pop("component_supervision")
    legacy["best"].pop("component_supervision")
    legacy_path = tmp_path/"legacy.pt"; torch.save(legacy, legacy_path)
    _, continued = run_fixture(tmp_path/"legacy-resumed", resume=legacy_path, config=config)
    assert continued["component_supervision"]["legacy_prefix_unknown"]
    assert continued["component_supervision"]["successful_optimizer_steps"] == 0
    assert continued["final_component_supervision"]["legacy_prefix_unknown"]
    assert continued["final_component_supervision"]["successful_optimizer_steps"] == 1
    config_file = tmp_path/"config.json"; config_file.write_text(json.dumps(config.as_mapping()))
    _, _, _, origin = export_v2.load_checkpoint_model(original, config_file, CONTRACT,
        required_components={"issue_logits":[component_names(CONTRACT)["issue_logits"][0]]})
    assert origin["selected_epoch"] == 1 and not origin["release_admissible"]
    with pytest.raises(SupervisionError, match="unknown/missing"):
        export_v2.load_checkpoint_model(legacy_path, config_file, CONTRACT,
            required_components={"issue_logits":[component_names(CONTRACT)["issue_logits"][0]]})
    for mutation in ("state", "semantics", "missing"):
        broken = copy.deepcopy(payload)
        if mutation == "state": broken["best"]["state"].pop(next(iter(broken["best"]["state"])))
        if mutation == "semantics": broken["resume_semantic_sha256"] = "0"*64
        if mutation == "missing": broken["best"].pop("component_supervision")
        changed = tmp_path/f"{mutation}.pt"; torch.save(broken, changed)
        with pytest.raises((ValueError, RuntimeError)):
            export_v2.load_checkpoint_model(changed, config_file, CONTRACT)


def test_failed_optimizer_cannot_commit_supervision(tmp_path, monkeypatch):
    commits = []
    monkeypatch.setattr(trainer, "record_successful_step", lambda *args:commits.append(args))
    def fail_step(*args, **kwargs): raise RuntimeError("controlled optimizer failure")
    monkeypatch.setattr(torch.optim.AdamW, "step", fail_step)
    with pytest.raises(RuntimeError, match="controlled optimizer failure"):
        run_fixture(tmp_path/"failed")
    assert commits == [] and not (tmp_path/"failed/checkpoint.pt").exists()


def test_validation_only_component_never_receives_training_counts(tmp_path):
    config = replace(_tiny_config(), training=replace(_tiny_config().training,
        trained_heads=("issue_logits",), batch_size=32, epochs=1))
    records = partial_records()
    for record in records:
        if record.split == "validation":
            record.masks["issue_logits"][0] = 0
            record.masks["issue_logits"][1] = 1
    run = tmp_path/"validation-only"; run.mkdir()
    result = trainer.train_one_seed(config, seed=7, run_dir=run, contract=CONTRACT,
        loss_config=LOSS, records=records)
    counts = result["final_component_supervision"]["heads"]["issue_logits"]["observations"]
    assert counts[0] > 0 and counts[1:] == [0]*7


def test_export_required_component_guard_is_connected_before_conversion(tmp_path):
    path = tmp_path/"not-created.mlpackage"
    with pytest.raises(SupervisionError, match="unknown/missing"):
        export_v2.export(path, required_components={"issue_logits":[component_names(CONTRACT)["issue_logits"][0]]})
    assert not path.exists() and not export_v2.receipt_path(path).exists()


@pytest.mark.parametrize("offset", [0.02, float("nan")])
def test_parity_rejects_numeric_errors_and_nonfinite_values(offset):
    class Constant(torch.nn.Module):
        def forward(self, *args):
            return tuple(torch.zeros(1, CONTRACT.output_head_shapes[h]) for h in CONTRACT.output_head_names)
    class CoreML:
        def predict(self, provider):
            return {h:torch.full((1, CONTRACT.output_head_shapes[h]), offset).numpy()
                    for h in CONTRACT.output_head_names}
    result = export_v2.parity_report(Constant(), CoreML(), CONTRACT, export_v2.parity_cases(CONTRACT, 2))
    assert result["passed"] is False
    with pytest.raises(ValueError, match="nonempty"):
        export_v2.parity_report(Constant(), CoreML(), CONTRACT, [])


def test_early_stop_keeps_the_latest_completed_checkpoint(tmp_path, monkeypatch):
    monkeypatch.setattr(trainer, "_validate", lambda *a,**kw:(0.1, {h:0. for h in DIRECT_LOSS_HEADS}))
    config = replace(_tiny_config(), training=replace(_tiny_config().training,
        trained_heads=("issue_logits",), batch_size=32, early_stop_patience=1))
    _, result = run_fixture(tmp_path/"stopped", config=config)
    saved = torch.load(tmp_path/"stopped/checkpoint.pt", weights_only=True)
    assert result["stopped_early"] and saved["epoch"] == result["final_epoch"] == 2
    assert saved["component_supervision"] == result["final_component_supervision"]
