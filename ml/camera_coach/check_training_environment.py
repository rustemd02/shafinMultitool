"""Bounded, offline acceptance check for the M4-006 training environment."""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile

import torch

# Keep the bounded check runnable by path as well as by module.
if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from ml.camera_coach.train import (
    LOSS_CONFIG_PATH,
    LOSS_CONFIG_RELATIVE_PATH,
    LOSS_DEFINITION,
    REPO_ROOT,
    ConfigError,
    TrainingConfig,
    TrainingError,
    _file_hash,
    _tensor_hash,
    run_training,
)


CONFIG_PATH = REPO_ROOT / "ml/camera_coach/configs/synthetic_dry_run.json"
SCHEMA_PATH = REPO_ROOT / "ml/camera_coach/configs/training_config.schema.json"
EXPECTED_FIRST_STEP_LOSS = 5.071068286895752
OBSOLETE_LOSS_DEFINITION = "mean_mse_over_manifest_heads_before_one_sgd_step"


def _must_reject(factory, label: str) -> None:
    try:
        factory()
    except (ConfigError, TrainingError):
        return
    raise AssertionError(f"negative check was accepted: {label}")


def _without_run_instance(receipt: dict[str, object]) -> dict[str, object]:
    value = deepcopy(receipt)
    value.pop("run_instance", None)
    hashes = value.get("hashes")
    if isinstance(hashes, dict):
        hashes.pop("receipt_sha256", None)
    return value


def main() -> int:
    config = TrainingConfig.from_file(CONFIG_PATH)
    with SCHEMA_PATH.open(encoding="utf-8") as stream:
        schema = json.load(stream)
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {
        "config_version",
        "seed",
        "deterministic",
        "device",
        "candidate",
        "dataset",
        "model",
        "runtime",
        "loss",
        "lock_sha256",
        "output_root",
        "dry_run",
    }
    assert schema["properties"]["dataset"]["additionalProperties"] is False
    assert schema["properties"]["model"]["additionalProperties"] is False
    assert schema["properties"]["runtime"]["additionalProperties"] is False
    assert schema["properties"]["loss"]["additionalProperties"] is False
    assert schema["properties"]["dry_run"]["additionalProperties"] is False
    assert schema["properties"]["dry_run"]["properties"]["sample_count"]["maximum"] == 4
    assert config.dry_run.sample_count == 4

    unknown = config.to_mapping()
    unknown["unexpected"] = True
    _must_reject(lambda: TrainingConfig.from_mapping(unknown), "unknown top-level key")
    wrong_type = config.to_mapping()
    wrong_type["seed"] = "20260905"
    _must_reject(lambda: TrainingConfig.from_mapping(wrong_type), "seed type")
    wrong_range = config.to_mapping()
    wrong_range["dry_run"]["batch_size"] = 0
    _must_reject(lambda: TrainingConfig.from_mapping(wrong_range), "batch-size range")
    alternate_source = config.to_mapping()
    alternate_source["model"]["source_path"] = "ml/camera_coach/models/set_composition_net.py"
    _must_reject(lambda: TrainingConfig.from_mapping(alternate_source), "alternate model source path")
    bad_contract_pin = config.to_mapping()
    bad_contract_pin["model"]["manifest_sha256"] = "0" * 64
    bad_contract = TrainingConfig.from_mapping(bad_contract_pin)
    bad_dataset_pin = config.to_mapping()
    bad_dataset_pin["dataset"]["sha256"] = "0" * 64
    bad_dataset = TrainingConfig.from_mapping(bad_dataset_pin)
    bad_lock_pin = config.to_mapping()
    bad_lock_pin["lock_sha256"] = "0" * 64
    bad_lock = TrainingConfig.from_mapping(bad_lock_pin)
    bad_runtime_pin = config.to_mapping()
    bad_runtime_pin["runtime"]["torch_version"] = "0.0.0"
    bad_runtime = TrainingConfig.from_mapping(bad_runtime_pin)
    bad_loss_pin = config.to_mapping()
    bad_loss_pin["loss"]["sha256"] = "0" * 64
    bad_loss = TrainingConfig.from_mapping(bad_loss_pin)

    backing = torch.arange(8, dtype=torch.float32)
    logical_slice = backing[2:6]
    before_slice_hash = _tensor_hash(logical_slice)
    backing[0] = -123.0
    assert _tensor_hash(logical_slice) == before_slice_hash
    backing[2] = -456.0
    assert _tensor_hash(logical_slice) != before_slice_hash

    with tempfile.TemporaryDirectory(prefix="m4-006-", dir="/private/tmp") as temporary:
        root = Path(temporary)
        receipt_a = run_training(
            config,
            config_path=CONFIG_PATH,
            run_dir=root / "same-seed-a",
            argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "same-seed-a")),
        )
        receipt_b = run_training(
            config,
            config_path=CONFIG_PATH,
            run_dir=root / "same-seed-b",
            argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "same-seed-b")),
        )
        assert _without_run_instance(receipt_a) == _without_run_instance(receipt_b)
        projection_a = receipt_a["content_stable_projection"]
        projection_b = receipt_b["content_stable_projection"]
        assert projection_a == projection_b
        assert isinstance(projection_a, dict)
        reproducibility = projection_a["reproducibility"]
        assert isinstance(reproducibility, dict)
        assert reproducibility["sample_order_sha256"]
        assert reproducibility["model_initialization_sha256"]
        assert abs(
            float(reproducibility["first_step_loss"])
            - float(projection_b["reproducibility"]["first_step_loss"])
        ) <= 1e-7
        assert abs(float(reproducibility["first_step_loss"]) - EXPECTED_FIRST_STEP_LOSS) <= 1e-7
        loss_info = projection_a["loss"]
        assert isinstance(loss_info, dict)
        assert loss_info["definition"] == LOSS_DEFINITION
        assert loss_info["definition"] != OBSOLETE_LOSS_DEFINITION
        assert loss_info["config"] == LOSS_CONFIG_RELATIVE_PATH
        assert loss_info["config_sha256"] == _file_hash(LOSS_CONFIG_PATH)
        assert projection_a["loss"]["config_sha256"] == receipt_a["hashes"]["loss_config_sha256"]
        assert isinstance(loss_info["weights"], dict)
        assert set(loss_info["weights"]) == {
            "scene_class_logits",
            "subjectness_roi_agreement_logits",
            "issue_logits",
            "action_utility_logits",
            "good_frame_probability",
            "abstention_probability",
            "risk_probability",
            "continuous_target_deltas",
            "ranking",
            "contrastive",
        }
        _must_reject(
            lambda: run_training(
                config,
                config_path=CONFIG_PATH,
                run_dir=root / "same-seed-a",
                argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "same-seed-a")),
            ),
            "existing output target",
        )

        changed_seed_mapping = config.to_mapping()
        changed_seed_mapping["seed"] += 1
        changed_seed = TrainingConfig.from_mapping(changed_seed_mapping)
        changed_seed_receipt = run_training(
            changed_seed,
            config_path=CONFIG_PATH,
            run_dir=root / "changed-seed",
            argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "changed-seed")),
        )
        assert changed_seed.config_sha256 != config.config_sha256
        assert changed_seed_receipt["hashes"]["dataset_sha256"] != receipt_a["hashes"]["dataset_sha256"]
        assert (
            changed_seed_receipt["hashes"]["model_initialization_sha256"]
            != receipt_a["hashes"]["model_initialization_sha256"]
        )

        changed_config_mapping = config.to_mapping()
        changed_config_mapping["dry_run"]["batch_size"] = 1
        changed_config = TrainingConfig.from_mapping(changed_config_mapping)
        changed_config_receipt = run_training(
            changed_config,
            config_path=CONFIG_PATH,
            run_dir=root / "changed-config",
            argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "changed-config")),
        )
        assert changed_config.config_sha256 != config.config_sha256
        assert changed_config_receipt["hashes"]["config_sha256"] != receipt_a["hashes"]["config_sha256"]

        _must_reject(
            lambda: run_training(
                bad_contract,
                config_path=CONFIG_PATH,
                run_dir=root / "bad-contract",
                argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "bad-contract")),
            ),
            "changed contract hash",
        )
        _must_reject(
            lambda: run_training(
                bad_dataset,
                config_path=CONFIG_PATH,
                run_dir=root / "bad-dataset",
                argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "bad-dataset")),
            ),
            "changed dataset hash",
        )
        _must_reject(
            lambda: run_training(
                bad_lock,
                config_path=CONFIG_PATH,
                run_dir=root / "bad-lock",
                argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "bad-lock")),
            ),
            "changed runtime lock hash",
        )
        _must_reject(
            lambda: run_training(
                bad_runtime,
                config_path=CONFIG_PATH,
                run_dir=root / "bad-runtime",
                argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "bad-runtime")),
            ),
            "runtime version drift",
        )
        _must_reject(
            lambda: run_training(
                bad_loss,
                config_path=CONFIG_PATH,
                run_dir=root / "bad-loss",
                argv=("--config", str(CONFIG_PATH), "--run-dir", str(root / "bad-loss")),
            ),
            "changed loss config hash",
        )

        summary = {
            "status": "pass",
            "same_seed_projection_equal": True,
            "sample_order_sha256": reproducibility["sample_order_sha256"],
            "model_initialization_sha256": reproducibility["model_initialization_sha256"],
            "first_step_loss": reproducibility["first_step_loss"],
            "first_step_loss_tolerance": reproducibility["first_step_loss_tolerance"],
            "expected_first_step_loss": EXPECTED_FIRST_STEP_LOSS,
            "loss_definition": loss_info["definition"],
            "loss_config": loss_info["config"],
            "loss_config_sha256": loss_info["config_sha256"],
            "weighted_loss_receipt_validated": True,
            "obsolete_mse_definition_rejected": True,
            "changed_seed_drift_detected": True,
            "changed_config_drift_detected": True,
            "unknown_key_rejected": True,
            "schema_closed": True,
            "existing_target_rejected": True,
            "contract_hash_pin_rejected": True,
            "dataset_hash_pin_rejected": True,
            "runtime_lock_hash_pin_rejected": True,
            "runtime_version_drift_rejected": True,
            "loss_config_hash_pin_rejected": True,
            "alternate_model_source_path_rejected": True,
            "logical_tensor_slice_hash_isolated": True,
            "maximum_sample_count_exercised": True,
            "temporary_receipts_cleaned": True,
        }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
