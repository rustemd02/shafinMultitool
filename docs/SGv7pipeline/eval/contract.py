from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

from .bundle import EvalBundle
from .io import read_json


class ContractDriftError(ValueError):
    """Raised when eval run violates frozen runtime/train contract snapshots."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_contract(bundle: EvalBundle) -> dict[str, Any]:
    snapshot_hashes: dict[str, str] = {}
    snapshot_meta: dict[str, dict[str, Any]] = {}
    for name, path in sorted(bundle.snapshot_paths.items()):
        snapshot_hashes[name] = _sha256(path)
        payload = read_json(path)
        snapshot_meta[name] = payload

    expected_hashes = bundle.manifest.get("expected_snapshot_hashes", {})
    if expected_hashes and not isinstance(expected_hashes, dict):
        raise ContractDriftError("manifest.expected_snapshot_hashes must be an object when provided")

    mismatches: list[str] = []
    if isinstance(expected_hashes, dict):
        for name, expected_hash in sorted(expected_hashes.items()):
            actual = snapshot_hashes.get(str(name))
            if actual is None:
                mismatches.append(f"missing_snapshot:{name}")
                continue
            if str(expected_hash) != actual:
                mismatches.append(f"hash_mismatch:{name}")
    if mismatches:
        raise ContractDriftError("contract drift detected: " + ", ".join(mismatches))

    return {
        "contract_version": str(bundle.manifest.get("contract_version", "")),
        "snapshot_hashes": snapshot_hashes,
        "snapshot_meta": snapshot_meta,
    }
