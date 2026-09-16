from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
BASELINE_DIR = Path(__file__).resolve().parents[1] / "camera-baseline-v0"
CONFIG_PATHS = sorted(BASELINE_DIR.glob("replay-config-*.json"))


def test_committed_replay_configs_declare_the_runtime_contract() -> None:
    assert CONFIG_PATHS, "expected at least one committed replay config"
    for config_path in CONFIG_PATHS:
        config = json.loads(config_path.read_text(encoding="utf-8"))
        assert config["runtime"] == "real_runtime_still_replay", config_path
        assert config["output_path"] == "<EXTERNAL_OUTPUT_PATH>", config_path
        assert isinstance(config["config_id"], str) and config["config_id"], config_path
        assert config["limit"] == config["expected_records"], config_path
        assert config["expected_rows"] == config["expected_records"] * 2, config_path


def test_committed_replay_config_paths_resolve_and_match_declared_records() -> None:
    for config_path in CONFIG_PATHS:
        config = json.loads(config_path.read_text(encoding="utf-8"))
        labels_path = REPO_ROOT / config["labels_path"]
        images_root = REPO_ROOT / config["images_root_path"]
        assert not Path(config["labels_path"]).is_absolute(), config_path
        assert not Path(config["images_root_path"]).is_absolute(), config_path
        assert labels_path.is_file(), config_path
        assert images_root.is_dir(), config_path
        records = [
            line
            for line in labels_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        assert len(records) == config["expected_records"], config_path


def test_label_drift_lane_targets_the_bundled_174_record_pack() -> None:
    config_path = BASELINE_DIR / "replay-config-174-drift.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    assert config["config_id"] == "m4-001-fullruntime-174-drift-r1"
    assert config["expected_records"] == 174
    assert config["labels_path"].endswith("camera_device_benchmark_pack_v1/camera_full_labels.jsonl")
    assert config["images_root_path"].endswith("camera_device_benchmark_pack_v1/images")
