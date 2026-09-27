#!/usr/bin/env python3
"""Fail-closed Colab preflight for the ML-004 camera-coach training bundle.

Run this from the extracted bundle root before any training cell:

    python3 check_environment.py --mode dry_run            # no human gold needed
    python3 check_environment.py --mode smoke              # mini-batch masked-loss smoke
    python3 check_environment.py --mode final_fit          # REQUIRES human-gold labels

Checks: interpreter/torch versions, bundle code hashes against
``bundle-receipt.json``, the pinned ML-002 production-heads contract, data
files at their Drive paths from ``data_manifest.jsonl`` (hash-verified; sample
by default, ``--full`` for every file), and the human-gold gate. Without
``human_gold=true`` labels the bundle permits ``dry_run``/``smoke`` only —
``final_fit`` refuses (exit 3). Silver is never gold.

Exit codes: 0 pass · 2 environment/data failure · 3 human-gold gate refusal.
Stdlib plus ``torch`` (preinstalled on Colab); ``jsonschema`` is needed only
when human labels are validated and is reported as a fixable gap if absent.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
import sys
import time
from pathlib import Path

MODES = ("dry_run", "smoke", "final_fit")
EXIT_OK, EXIT_ENV_FAIL, EXIT_HUMAN_GOLD = 0, 2, 3
HUMAN_GOLD_PERMITTED_MODES = ("dry_run", "smoke")
FULL_SAMPLE_CAP = 500


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _fail(message: str, code: int = EXIT_ENV_FAIL) -> int:
    print(f"PREFLIGHT FAIL: {message}")
    return code


def _deterministic_sample(rows: list[dict], sample: int) -> list[dict]:
    if sample <= 0 or len(rows) <= sample:
        return list(rows)
    ordered = sorted(rows, key=lambda row: (row.get("content_sha256") or "", row.get("record_id") or ""))
    step = len(rows) / float(sample)
    return [ordered[min(len(ordered) - 1, int(i * step))] for i in range(sample)]


def human_gold_of(row: dict) -> dict | None:
    """Adjudicated human-gold payload of one labels row, or None (fail-closed).

    Exported rows are envelopes (``release_label`` beside the raw opinion); gold
    lives in ``release_label.provenance``. A row counts as gold only when it says
    ``human_gold=true`` AND was adjudicated with an adjudicator id (DATA-011) —
    raw review is never gold, and an unknown row shape is not silently trusted.
    """
    if not isinstance(row, dict):
        return None
    payload = row.get("release_label", row)
    if not isinstance(payload, dict):
        return None
    provenance = payload.get("provenance")
    if not isinstance(provenance, dict):
        return None
    if (provenance.get("human_gold") is True
            and provenance.get("review_status") == "adjudicated"
            and provenance.get("adjudicator_id")):
        return payload
    return None


def contract_invalid_indexes(gold_payloads: list[dict], contracts_dir: Path,
                             time_budget_s: float | None = 120.0) -> list[int]:
    """Индексы payload'ов, не проходящих контракт camera-release-label-v1.

    Использует реальный API валидатора (``validate_record(validator, record)``),
    тот же, что и release_label_adapter: имён ``validate_release_label`` в модуле
    нет, и старый вызов падал бы AttributeError в момент появления первых меток.
    """
    import sys as _sys
    import time as _time

    _sys.path.insert(0, str(contracts_dir))
    import validate_camera_release_label as validator_module  # noqa: PLC0415
    from jsonschema import Draft202012Validator  # noqa: PLC0415

    schema = json.loads((contracts_dir / "camera_release_label_v1.schema.json")
                        .read_text(encoding="utf-8"))
    contract_validator = Draft202012Validator(schema)
    started = _time.time()
    invalid: list[int] = []
    for index, payload in enumerate(gold_payloads):
        if validator_module.validate_record(contract_validator, payload):
            invalid.append(index)
        if time_budget_s is not None and _time.time() - started > time_budget_s:
            raise TimeoutError(f"human label validation exceeded {time_budget_s}s at row {index}")
    return invalid


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=MODES, default="dry_run")
    parser.add_argument("--bundle-root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--drive-root", type=Path, default=None, help="override the Drive root prefix")
    parser.add_argument("--sample", type=int, default=200, help="hash-sample size for data files")
    parser.add_argument("--full", action="store_true", help="verify every data file hash (slow)")
    parser.add_argument(
        "--human-labels", type=Path, default=None,
        help="override the human-gold labels path (default: slot row from data_manifest.jsonl)",
    )
    args = parser.parse_args()

    root: Path = args.bundle_root
    receipt_path = root / "bundle-receipt.json"
    manifest_path = root / "data_manifest.jsonl"
    config_path = root / "config.json"
    for required in (receipt_path, manifest_path, config_path):
        if not required.is_file():
            return _fail(f"bundle file missing: {required.name} (run from the extracted bundle root)")

    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    config = json.loads(config_path.read_text(encoding="utf-8"))
    print(f"bundle: {receipt.get('schema_id')} v{receipt.get('schema_version')} built {receipt.get('built_utc')}")

    # --- 1. interpreter / torch / accelerator --------------------------------
    print(f"python: {platform.python_version()} at {sys.executable}")
    min_python = tuple(int(part) for part in str(config["environment"]["python_min"]).split("."))
    if sys.version_info[:2] < min_python:
        return _fail(f"python {platform.python_version()} < required {config['environment']['python_min']}")
    try:
        import torch
    except ImportError:
        return _fail("torch is not importable in this runtime")
    print(f"torch: {torch.__version__} cuda_available={torch.cuda.is_available()}")
    min_torch = tuple(int(part) for part in str(config["environment"]["torch_min"]).split("."))
    torch_version = tuple(int(part) for part in torch.__version__.split("+")[0].split(".")[:2])
    if torch_version < min_torch:
        return _fail(f"torch {torch.__version__} < required {config['environment']['torch_min']}")
    if torch.cuda.is_available():
        print(f"gpu: {torch.cuda.get_device_name(0)} (driver report via nvidia-smi skipped; Colab-managed)")
    else:
        print("gpu: none — CPU runtime is acceptable for dry_run/smoke, not for final_fit")

    # --- 2. bundle code hashes -----------------------------------------------
    drifted = [
        rel
        for rel, expected in sorted(receipt["code_hashes_sha256"].items())
        if not (root / "bundle" / rel).is_file() or _sha256_file(root / "bundle" / rel) != expected
    ]
    if drifted:
        return _fail(f"bundle code hash drift: {drifted[:3]}")
    print(f"code hashes: {len(receipt['code_hashes_sha256'])} files verified against bundle-receipt.json")

    # --- 3. pinned production-heads contract ---------------------------------
    check = subprocess.run(
        [sys.executable, str(root / "bundle" / "ml/camera_coach/contracts/check_production_heads_v1.py")],
        capture_output=True, text=True,
    )
    if check.returncode != 0:
        print(check.stdout[-800:])
        print(check.stderr[-800:])
        return _fail("pinned production-heads contract check failed inside the bundle")
    print("production heads contract: PASS (7/7 entries, 15 issues, 26 mapped actions)")

    # --- 4. data files at Drive paths ----------------------------------------
    rows = [json.loads(line) for line in manifest_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    file_rows = [row for row in rows if row.get("source_kind") != "human_labels_dir"]
    drive_root: Path = args.drive_root or Path("/content/drive/MyDrive")
    if args.drive_root is None and not drive_root.is_dir():
        return _fail(f"Drive root not mounted: {drive_root} (mount Drive or pass --drive-root)")
    checked = missing = mismatched = 0
    for row in ([*file_rows] if args.full else _deterministic_sample(file_rows, min(args.sample, FULL_SAMPLE_CAP))):
        local = drive_root / str(row["drive_path"]).removeprefix("/content/drive/MyDrive/")
        if not local.is_file():
            missing += 1
            if missing <= 3:
                print(f"  missing: {row['drive_path']}")
            continue
        if _sha256_file(local) != row["content_sha256"]:
            mismatched += 1
            if mismatched <= 3:
                print(f"  hash mismatch: {row['drive_path']}")
            continue
        checked += 1
    if missing or mismatched:
        return _fail(f"data verification failed: {missing} missing, {mismatched} hash mismatched")
    mode_label = "full" if args.full else f"sample({min(args.sample, FULL_SAMPLE_CAP)})"
    print(f"data files: {checked} verified ({mode_label} of {len(file_rows)} pinned rows)")

    # --- 5. human-gold gate (fail-closed) ------------------------------------
    slot = next((row for row in rows if row.get("source_kind") == "human_labels_dir"), None)
    labels_path = args.human_labels or (drive_root / str(slot["drive_path"]).removeprefix("/content/drive/MyDrive/") if slot else None)
    label_rows: list[dict] = []
    if labels_path is not None and Path(labels_path).is_file():
        try:
            for line in Path(labels_path).read_text(encoding="utf-8").splitlines():
                if line.strip():
                    label_rows.append(json.loads(line))
        except json.JSONDecodeError as exc:
            return _fail(f"human labels file is not valid JSONL: {exc}")
    gold_payloads = [payload for payload in (human_gold_of(row) for row in label_rows)
                     if payload is not None]
    gate = {
        "labels_file": str(labels_path) if labels_path else None,
        "rows": len(label_rows),
        "human_gold_rows": len(gold_payloads),
        "mode": args.mode,
    }
    if args.mode in HUMAN_GOLD_PERMITTED_MODES:
        print(f"human-gold gate: mode={args.mode} — human labels not required ({len(label_rows)} rows present)")
    else:
        if not label_rows:
            print(
                "human-gold gate: REFUSED — no human labels exist yet. The bundle permits "
                "dry_run/smoke only. Fill the human_labels_dir slot (pilot-100 then DATA-013) "
                "and adjudicate (DATA-010/011) before final_fit. Silver data is never gold."
            )
            gate["decision"] = "refused_no_human_labels"
            print(json.dumps(gate, indent=2))
            return EXIT_HUMAN_GOLD
        if len(gold_payloads) != len(label_rows) or not gold_payloads:
            return _fail(
                f"human-gold gate: {len(label_rows) - len(gold_payloads)} of {len(label_rows)} "
                "rows are not adjudicated human_gold=true (envelope: release_label.provenance); "
                "silver or unadjudicated labels cannot back final_fit",
                EXIT_HUMAN_GOLD,
            )
        try:
            invalid = contract_invalid_indexes(gold_payloads,
                                               root / "bundle" / "ml" / "camera_coach" / "contracts")
        except ImportError as exc:
            return _fail(f"validating human labels needs jsonschema: pip install jsonschema ({exc})")
        except TimeoutError as exc:
            return _fail(str(exc))
        except (OSError, json.JSONDecodeError) as exc:
            return _fail(f"bundled release-label contract is unreadable: {exc}")
        if invalid:
            return _fail(f"human-gold gate: {len(invalid)} contract-invalid label rows (first: {invalid[:3]})")
        gate["decision"] = "admitted"
        gate["contract_validated_rows"] = len(gold_payloads)
        print(f"human-gold gate: ADMITTED — {len(gold_payloads)} contract-valid "
              "adjudicated human_gold=true rows")

    print("PREFLIGHT PASS")
    print(json.dumps({"mode": args.mode, "human_gold_gate": gate}, indent=2))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
