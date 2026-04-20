from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def test_run_eval_generates_required_artifacts(tmp_path: Path) -> None:
    eval_dir = Path(__file__).resolve().parents[1]
    script = eval_dir / "run_eval.py"

    cmd = [
        sys.executable,
        str(script),
        "--bundle",
        str(eval_dir),
        "--candidate",
        "camera_analysis_v1_core",
        "--baseline",
        "legacy_suggestion_engine",
        "--output",
        str(tmp_path),
    ]
    subprocess.run(cmd, check=True)

    for name in (
        "case_results.jsonl",
        "set_metrics.json",
        "bucket_metrics.json",
        "compare_report.json",
        "eval_summary.md",
    ):
        assert (tmp_path / name).exists(), f"missing {name}"

    compare_report = json.loads((tmp_path / "compare_report.json").read_text(encoding="utf-8"))
    assert compare_report["baseline_id"] == "legacy_suggestion_engine"
    assert compare_report["candidate_id"] == "camera_analysis_v1_core"
