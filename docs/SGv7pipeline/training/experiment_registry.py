from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
from typing import Any

from .io import read_json, write_json


class ExperimentRegistryError(ValueError):
    """Raised when reproducible experiment notes cannot be materialized."""


@dataclass(frozen=True)
class ExperimentRegistryRequest:
    experiment_id: str
    phase: str
    config_path: Path
    output_dir: Path
    input_artifacts: list[Path]
    notes: str | None = None


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return digest


def register_experiment(request: ExperimentRegistryRequest) -> dict[str, Any]:
    experiment_id = request.experiment_id.strip()
    if not experiment_id:
        raise ExperimentRegistryError("experiment_id must be non-empty")
    if not request.config_path.exists():
        raise ExperimentRegistryError(f"config_path does not exist: {request.config_path}")

    artifacts: list[dict[str, Any]] = []
    for path in request.input_artifacts:
        if not path.exists():
            raise ExperimentRegistryError(f"input artifact does not exist: {path}")
        item: dict[str, Any] = {
            "path": str(path),
            "sha256": _file_sha256(path),
        }
        if path.suffix.lower() == ".json":
            try:
                item["json_keys"] = sorted(read_json(path).keys())
            except Exception:
                item["json_keys"] = []
        artifacts.append(item)

    payload = {
        "experiment_id": experiment_id,
        "phase": request.phase,
        "config_path": str(request.config_path),
        "config_sha256": _file_sha256(request.config_path),
        "input_artifacts": artifacts,
        "notes": request.notes or "",
    }
    out = request.output_dir / experiment_id / "experiment_note.json"
    write_json(payload, out)
    return payload

