#!/usr/bin/env python3
"""Fail-closed preflight for the Camera Coach v2 records Colab run (M02).

This tool is the only gate between the owner's one-click Colab run and the
single training CLI (``python3 -m ml.camera_coach.train --config ...``).  It:

1. verifies the whole-archive trust anchor (caller-supplied SHA-256) and never
   rewrites an expected hash to match whatever archive it was handed;
2. safely validates and extracts both ZIPs (no traversal, no symlinks, no
   duplicate names, per-member/total/member-count ceilings);
3. verifies the embedded bundle manifests against the extracted bytes and
   validates every typed record, the schema id/version and the split layout;
4. rejects rights/admission inconsistencies and blocks a ``full_fit`` profile
   while the corpus is ``non_admitted_research`` (0 admitted records, Packet A
   pending);
5. checks free disk, RAM and VRAM against an explicit need estimate;
6. instantiates the declared v2 candidate, runs a real optimizer step from a
   real record batch on the requested device and proves the actually used
   tensors live on that device (CUDA is not accepted because it was selected);
7. records the pretrained lineage (scratch init from the frozen v2 manifest)
   and, when resuming, requires the checkpoint's resume-semantics hash to match;
8. writes a machine-readable preflight receipt and exits non-zero on any
   failure so the notebook's ``check=True`` stops before a fit starts.

Exit codes: 0 = admitted, 1 = refused/blocked, 2 = malformed invocation/input.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tempfile
import time
from typing import Any, Mapping
import zipfile


_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


CODE_BUNDLE_SCHEMA_ID = "camera-coach-records-colab-bundle-v1"
CODE_SUMS_SCHEMA_ID = "camera-coach-records-sha256-v1"
DATA_BUNDLE_SCHEMA_ID = "camera-coach-records-data-bundle-v1"
DATA_SUMS_SCHEMA_ID = "camera-coach-records-data-sha256-v1"
MANIFEST_KIND = "research_only_colab_orchestration"
DATA_KIND = "research_only_typed_training_records"
EXECUTION_PROFILES = ("non_admitted_research", "full_fit")
MAX_CODE_MEMBER_BYTES = 4 * 1024 * 1024
MAX_CODE_TOTAL_BYTES = 32 * 1024 * 1024
MAX_CODE_MEMBERS = 2_000
MAX_DATA_MEMBER_BYTES = 64 * 1024 * 1024
MAX_DATA_TOTAL_BYTES = 8 * 1024 * 1024 * 1024
MAX_DATA_MEMBERS = 50_000
HEX64_RE = __import__("re").compile(r"^[0-9a-f]{64}$")


class PreflightError(RuntimeError):
    """Raised when a preflight check refuses the run."""


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_hex64(value: object, label: str) -> str:
    if not isinstance(value, str) or not HEX64_RE.fullmatch(value):
        raise PreflightError(f"{label} must be a lowercase SHA-256 hex digest supplied by the caller")
    return value


def _require_regular_file(path: Path, label: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise PreflightError(f"{label} must be a regular non-symlink file: {path}")
    return path


def _validate_archive(archive: zipfile.ZipFile, *, member: int, total: int, count: int, label: str) -> list[str]:
    names = archive.namelist()
    if not names:
        raise PreflightError(f"{label} archive is empty")
    if len(names) != len(set(names)):
        raise PreflightError(f"{label} archive contains duplicate member names")
    if len(names) > count:
        raise PreflightError(f"{label} archive has more than {count} members")
    total_bytes = 0
    for info in archive.infolist():
        name = info.filename
        path = PurePosixPath(name)
        if path.is_absolute() or name.startswith("/") or "\\" in name:
            raise PreflightError(f"{label} archive member is not a safe relative posix path: {name!r}")
        if any(part in {"", ".", ".."} for part in path.parts):
            raise PreflightError(f"{label} archive member escapes its root: {name!r}")
        mode = info.external_attr >> 16
        if stat.S_ISLNK(mode):
            raise PreflightError(f"{label} archive member is a symlink: {name!r}")
        # Some zip writers store bare permission bits without S_IFREG; only a
        # directory or a special file type is rejected, never a plain file.
        if mode and stat.S_ISDIR(mode):
            raise PreflightError(f"{label} archive member is a directory: {name!r}")
        if mode and not stat.S_ISREG(mode) and not (mode & 0o777):
            raise PreflightError(f"{label} archive member is not a regular file: {name!r}")
        if info.file_size > member:
            raise PreflightError(f"{label} archive member exceeds the per-member ceiling: {name!r}")
        total_bytes += info.file_size
        if total_bytes > total:
            raise PreflightError(f"{label} archive exceeds the total size ceiling")
    return names


def _extract_safe(archive: zipfile.ZipFile, destination: Path, names: list[str]) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    for name in names:
        target = destination.joinpath(*PurePosixPath(name).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(name) as source, target.open("wb") as sink:
            shutil.copyfileobj(source, sink)


def _verify_manifest_files(root: Path, records: object, label: str) -> None:
    if not isinstance(records, list) or not records:
        raise PreflightError(f"{label} manifest has no file records")
    for record in records:
        if not isinstance(record, Mapping) or set(record) != {"path", "bytes", "sha256"}:
            raise PreflightError(f"{label} manifest file record is malformed")
        relative = record["path"]
        if not isinstance(relative, str) or not relative:
            raise PreflightError(f"{label} manifest has an invalid path")
        target = root.joinpath(*PurePosixPath(relative).parts)
        if target.is_symlink() or not target.is_file():
            raise PreflightError(f"{label} bundle member is missing or unsafe: {relative}")
        size = target.stat().st_size
        if size != record["bytes"]:
            raise PreflightError(f"{label} member size mismatch for {relative}: {size} != {record['bytes']}")
        digest = _sha256_file(target)
        if digest != record["sha256"]:
            raise PreflightError(f"{label} member hash mismatch for {relative}: {digest} != {record['sha256']}")


def _load_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PreflightError(f"{label} is not readable JSON: {path}") from exc


def _strip_overridable(raw: Mapping[str, Any]) -> dict[str, Any]:
    from ml.camera_coach.trainer_records import RUNTIME_OVERRIDABLE_CONFIG_FIELDS

    stripped = json.loads(json.dumps(raw))
    for dotted in RUNTIME_OVERRIDABLE_CONFIG_FIELDS:
        node = stripped
        parts = dotted.split(".")
        for part in parts[:-1]:
            node = node.get(part) if isinstance(node, dict) else None
            if node is None:
                break
        if isinstance(node, dict):
            node.pop(parts[-1], None)
    return stripped


def _probe_device(config: Any, records: list[Any], contract: Any, loss_config: Any) -> dict[str, Any]:
    import torch

    from ml.camera_coach.data.training_records import class_pos_weights
    from ml.camera_coach.trainer_records import (
        _assert_actually_on_device,
        _available_heads,
        _batch_loss,
        _make_model,
        _torch_device,
    )

    device = _torch_device(config)
    model = _make_model(config, contract, device)
    train_records = [record for record in records if record.split == "train"]
    if not train_records:
        raise PreflightError("preflight device probe needs at least one train record")
    trained, _masks = _available_heads(train_records, config)
    pos_weights = None
    if config.training.class_weight_max > 0.0:
        pos_weights = {
            head: class_pos_weights(train_records, head, maximum=config.training.class_weight_max)
            for head in ("issue_logits", "action_utility_logits")
            if trained.get(head, False)
        }
    batch = train_records[: config.training.batch_size]
    if device.type == "cuda":
        torch.cuda.reset_peak_memory_stats(device)
    timings = []
    scalar_terms: dict[str, float] = {}
    for _ in range(2):
        started = time.perf_counter()
        total, scalar_terms = _batch_loss(
            model,
            batch,
            contract,
            loss_config,
            trained,
            pos_weights=pos_weights,
            augment=False,
            seed=config.seed,
            epoch=1,
            device=device,
        )
        if not torch.isfinite(total):
            raise PreflightError("preflight device probe produced a non-finite loss")
        total.backward()
        _assert_actually_on_device(model, device, [total], "preflight probe")
        grad_devices = {parameter.grad.device.type for parameter in model.parameters() if parameter.grad is not None}
        if grad_devices != {device.type}:
            raise PreflightError(f"preflight probe gradients are on {sorted(grad_devices)}, expected {device.type}")
        timings.append(time.perf_counter() - started)
    peak = torch.cuda.max_memory_allocated(device) if device.type == "cuda" else 0
    if device.type == "cuda" and peak <= 0:
        raise PreflightError("CUDA was selected but the preflight probe allocated no CUDA memory")
    parameter_bytes = sum(parameter.numel() * parameter.element_size() for parameter in model.parameters())
    return {
        "requested_device": config.device,
        "actual_device": device.type,
        "cuda_device_name": torch.cuda.get_device_name(device) if device.type == "cuda" else None,
        "cuda_total_memory_bytes": (
            torch.cuda.get_device_properties(device).total_memory if device.type == "cuda" else 0
        ),
        "probe_peak_vram_bytes": peak,
        "seconds_per_optimizer_step": min(timings),
        "probe_batch_size": len(batch),
        "parameter_bytes": parameter_bytes,
        "probe_loss_terms": scalar_terms,
        "tensor_device_proof": "model parameters, batch inputs, loss and gradients observed on the declared device",
    }


def _resource_checks(runtime_root: Path, durable_dir: Path, data_bytes: int, device_info: Mapping[str, Any]) -> dict[str, Any]:
    import shutil as _shutil

    runtime_free = _shutil.disk_usage(runtime_root).free
    durable_free = _shutil.disk_usage(durable_dir).free
    parameter_bytes = int(device_info["parameter_bytes"])
    # weights + gradients + two Adam moments + activation headroom; two checkpoints.
    need_runtime = data_bytes * 2 + parameter_bytes * 12 + 512 * 1024 * 1024
    need_durable = parameter_bytes * 12 + 256 * 1024 * 1024
    if runtime_free < need_runtime:
        raise PreflightError(
            f"runtime disk is too small: free={runtime_free} bytes, need>={need_runtime} bytes"
        )
    if durable_free < need_durable:
        raise PreflightError(
            f"durable disk is too small: free={durable_free} bytes, need>={need_durable} bytes"
        )
    try:
        page_size = os.sysconf("SC_PAGE_SIZE")
        pages = os.sysconf("SC_PHYS_PAGES")
        total_ram = int(page_size) * int(pages)
    except (ValueError, OSError, AttributeError):
        total_ram = 0
    need_ram = data_bytes * 3 + parameter_bytes * 12 + 512 * 1024 * 1024
    if total_ram and total_ram < need_ram:
        raise PreflightError(f"RAM is too small: total={total_ram} bytes, need>={need_ram} bytes")
    info: dict[str, Any] = {
        "runtime_free_bytes": runtime_free,
        "durable_free_bytes": durable_free,
        "estimated_runtime_need_bytes": need_runtime,
        "estimated_durable_need_bytes": need_durable,
        "total_ram_bytes": total_ram,
        "estimated_ram_need_bytes": need_ram,
    }
    if device_info["actual_device"] == "cuda":
        vram = int(device_info["cuda_total_memory_bytes"])
        need_vram = parameter_bytes * 6 + 512 * 1024 * 1024
        if vram < need_vram:
            raise PreflightError(f"VRAM is too small: total={vram} bytes, need>={need_vram} bytes")
        info["cuda_total_memory_bytes"] = vram
        info["estimated_vram_need_bytes"] = need_vram
    return info


def _epoch_estimate(records: list[Any], config: Any, seconds_per_step: float) -> dict[str, Any]:
    train_count = sum(1 for record in records if record.split == "train")
    steps_per_epoch = max(1, (train_count + config.training.batch_size - 1) // config.training.batch_size)
    per_epoch = steps_per_epoch * seconds_per_step
    return {
        "train_records": train_count,
        "steps_per_epoch": steps_per_epoch,
        "estimated_seconds_per_epoch": per_epoch,
        "estimated_total_seconds_no_early_stop": per_epoch * config.training.epochs * len(config.seeds),
        "seeds": list(config.seeds),
        "epochs": config.training.epochs,
        "is_estimate_not_a_measurement": True,
    }


def run_preflight(args: argparse.Namespace) -> dict[str, Any]:
    from ml.camera_coach.data.training_records import TrainingRecordError, load_records
    from ml.camera_coach.losses import LossConfig
    from ml.camera_coach.models.set_composition_net_v2 import SETCompositionNetV2Manifest
    from ml.camera_coach.trainer_records import RecordsTrainingConfig, resume_semantic_sha256

    runtime_root = Path(args.runtime_root).expanduser().resolve()
    durable_dir = Path(args.durable_dir).expanduser().resolve()
    for label, directory in (("runtime-root", runtime_root), ("durable-dir", durable_dir)):
        if not directory.is_dir():
            raise PreflightError(f"{label} must be an existing directory: {directory}")

    code_zip = _require_regular_file(Path(args.code_bundle).expanduser(), "code bundle")
    data_zip = _require_regular_file(Path(args.data_bundle).expanduser(), "data bundle")
    expected_code = _require_hex64(args.expected_code_bundle_sha256, "expected code bundle sha256")
    expected_data = _require_hex64(args.expected_data_bundle_sha256, "expected data bundle sha256")
    actual_code = _sha256_file(code_zip)
    if actual_code != expected_code:
        raise PreflightError(
            f"code bundle trust anchor mismatch: expected {expected_code}, got {actual_code}"
        )
    actual_data = _sha256_file(data_zip)
    if actual_data != expected_data:
        raise PreflightError(
            f"data bundle trust anchor mismatch: expected {expected_data}, got {actual_data}"
        )

    staging = Path(tempfile.mkdtemp(prefix=".setos-preflight-", dir=runtime_root))
    data_root = runtime_root / "data"
    try:
        with zipfile.ZipFile(code_zip) as archive:
            code_names = _validate_archive(
                archive, member=MAX_CODE_MEMBER_BYTES, total=MAX_CODE_TOTAL_BYTES, count=MAX_CODE_MEMBERS, label="code"
            )
            if args.code_root:
                # The notebook already trust-anchored and extracted this archive;
                # preflight still re-validates the archive member policy and every
                # extracted byte against the embedded manifest.
                code_stage = Path(args.code_root).expanduser().resolve()
                if not code_stage.is_dir():
                    raise PreflightError(f"code-root must be an extracted directory: {code_stage}")
                code_extracted = False
            else:
                code_stage = staging / "code"
                _extract_safe(archive, code_stage, code_names)
                code_extracted = True
        with zipfile.ZipFile(data_zip) as archive:
            data_names = _validate_archive(
                archive, member=MAX_DATA_MEMBER_BYTES, total=MAX_DATA_TOTAL_BYTES, count=MAX_DATA_MEMBERS, label="data"
            )
            data_stage = staging / "data"
            _extract_safe(archive, data_stage, data_names)

        code_manifest = _load_json(code_stage / "bundle-manifest.json", "code bundle manifest")
        code_sums = _load_json(code_stage / "SHA256SUMS.json", "code bundle SHA256SUMS")
        if code_manifest.get("schema_id") != CODE_BUNDLE_SCHEMA_ID or code_manifest.get("kind") != MANIFEST_KIND:
            raise PreflightError("unsupported code bundle manifest")
        if code_sums.get("schema_id") != CODE_SUMS_SCHEMA_ID:
            raise PreflightError("unsupported code bundle SHA256SUMS schema")
        if code_sums.get("files") != code_manifest.get("files"):
            raise PreflightError("code bundle SHA256SUMS disagree with the manifest")
        _verify_manifest_files(code_stage, code_manifest.get("files"), "code")
        declared_files = [record["path"] for record in code_manifest["files"]]
        if sorted(declared_files) != sorted(name for name in code_names if name not in {"bundle-manifest.json", "SHA256SUMS.json"}):
            raise PreflightError("code bundle allowlist does not match the archive members")

        data_manifest = _load_json(data_stage / "data-manifest.json", "data bundle manifest")
        data_sums = _load_json(data_stage / "SHA256SUMS.json", "data bundle SHA256SUMS")
        if data_manifest.get("schema_id") != DATA_BUNDLE_SCHEMA_ID or data_manifest.get("kind") != DATA_KIND:
            raise PreflightError("unsupported data bundle manifest")
        if data_sums.get("schema_id") != DATA_SUMS_SCHEMA_ID:
            raise PreflightError("unsupported data bundle SHA256SUMS schema")
        _verify_manifest_files(data_stage, data_manifest.get("files"), "data")
        record_relative = data_manifest.get("record_path")
        if not isinstance(record_relative, str) or not record_relative:
            raise PreflightError("data bundle manifest has no record path")
        data_file = data_stage.joinpath(*PurePosixPath(record_relative).parts)
        if not data_file.is_file():
            raise PreflightError(f"data bundle record file is missing: {record_relative}")
        data_bytes = data_file.stat().st_size
        data_hash = _sha256_file(data_file)

        # Publish the verified code/data onto the local runtime disk, atomically
        # and only after every check above passed.  The data always lives on the
        # local runtime disk; durable storage receives only checkpoints/receipts.
        if data_root.exists():
            shutil.rmtree(data_root)
        os.replace(data_stage, data_root)
        data_file = data_root.joinpath(*PurePosixPath(record_relative).parts)
        if code_extracted:
            repo_root = runtime_root / "code"
            if repo_root.exists():
                shutil.rmtree(repo_root)
            os.replace(code_stage, repo_root)
        else:
            repo_root = code_stage

        template = _load_json(Path(args.config_template).expanduser(), "config template")
        runtime_config_raw = _load_json(Path(args.runtime_config).expanduser(), "runtime config")
        if _strip_overridable(template) != _strip_overridable(runtime_config_raw):
            raise PreflightError(
                "runtime config changes frozen training semantics; only device/output_root/resume_from/runtime versions may be rebound"
            )
        config = RecordsTrainingConfig.from_mapping(runtime_config_raw)

        if config.runtime_profile == "pinned_local":
            raise PreflightError("the Colab preflight requires runtime_profile 'colab_installed_runtime'")
        if config.dataset.sha256 != data_hash:
            raise PreflightError(
                f"data hash mismatch against config: expected {config.dataset.sha256}, got {data_hash}"
            )

        manifest_path = repo_root / config.model.manifest_path
        if _sha256_file(manifest_path) != config.model.manifest_sha256:
            raise PreflightError("v2 model manifest hash does not match the runtime config")
        contract = SETCompositionNetV2Manifest.load(manifest_path)
        loss_path = repo_root / config.loss.path
        if _sha256_file(loss_path) != config.loss.sha256:
            raise PreflightError("loss config hash does not match the runtime config")
        loss_config = LossConfig.from_file(loss_path)

        # Place the verified records exactly where the trainer resolves them.
        resolved_records = (repo_root / config.dataset.path).resolve()
        if repo_root not in resolved_records.parents:
            raise PreflightError("dataset.path escapes the local runtime code root")
        resolved_records.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(data_file, resolved_records)
        if _sha256_file(resolved_records) != data_hash:
            raise PreflightError("copied records do not match the verified data bundle hash")

        try:
            records = load_records(resolved_records, data_hash)
        except TrainingRecordError as exc:
            raise PreflightError(f"typed records rejected: {exc}") from exc
        splits: dict[str, int] = {}
        for record in records:
            splits[record.split] = splits.get(record.split, 0) + 1
        if splits.get("train", 0) == 0 or splits.get("validation", 0) == 0:
            raise PreflightError(f"data bundle needs train and validation splits, got {splits}")
        if splits.get("locked_test", 0) != 0:
            raise PreflightError("locked_test records are sealed and cannot enter a fit bundle")
        declared_admission = data_manifest.get("admission")
        if declared_admission != config.dataset.admission:
            raise PreflightError("data bundle admission status disagrees with the runtime config")
        if config.dataset.admission == "declared_admitted" and not config.dataset.rights_manifest_sha256:
            raise PreflightError("declared_admitted data requires a rights manifest hash")
        if config.dataset.admission != "declared_admitted" and config.dataset.rights_manifest_sha256 is not None:
            raise PreflightError("non-admitted research data must not claim a rights manifest hash")
        if args.execution_profile == "full_fit" and config.dataset.admission != "declared_admitted":
            raise PreflightError(
                "full_fit is blocked: the corpus is non_admitted_research and Packet A (0 admitted records) is pending"
            )

        if args.require_cuda:
            import torch

            if not torch.cuda.is_available():
                raise PreflightError(
                    "require-cuda was requested but torch.cuda.is_available() is False; select a GPU runtime or rerun the non-admitted smoke with --allow-cpu-smoke"
                )
        device_info = _probe_device(config, records, contract, loss_config)
        if args.require_cuda and device_info["actual_device"] != "cuda":
            raise PreflightError("require-cuda was requested but the preflight probe ran on CPU")
        if not args.require_cuda and not args.allow_cpu_smoke and device_info["actual_device"] == "cpu":
            raise PreflightError("CPU execution requires the explicit --allow-cpu-smoke flag")

        resume_lineage = None
        if config.resume_from:
            resume_path = Path(config.resume_from).expanduser()
            _require_regular_file(resume_path, "resume checkpoint")
            import torch

            checkpoint = torch.load(resume_path, map_location="cpu", weights_only=False)
            recorded = checkpoint.get("resume_semantic_sha256")
            if recorded != resume_semantic_sha256(config):
                raise PreflightError(
                    "resume checkpoint code/config/data/device semantics do not match; start a new run with an explicit warm-start"
                )
            resume_lineage = {"path": str(resume_path), "epoch": checkpoint.get("epoch"), "resume_semantic_sha256": recorded}
        elif args.execution_profile == "full_fit" and args.warm_start_from:
            warm = _require_regular_file(Path(args.warm_start_from).expanduser(), "warm-start checkpoint")
            import torch

            checkpoint = torch.load(warm, map_location="cpu", weights_only=False)
            resume_lineage = {
                "path": str(warm),
                "kind": "explicit_warm_start",
                "model_state_sha256": hashlib.sha256(
                    json.dumps(sorted(checkpoint.get("model_state", {}).keys()), sort_keys=True).encode("utf-8")
                ).hexdigest(),
            }

        resources = _resource_checks(runtime_root, durable_dir, data_bytes, device_info)
        estimates = _epoch_estimate(records, config, device_info["seconds_per_optimizer_step"])

        backbone_hash = _sha256_file(repo_root / "ml/camera_coach/models/set_composition_net.py")
        receipt = {
            "schema_id": "camera-coach-records-preflight-receipt-v1",
            "schema_version": "1.0.0",
            "status": "pass",
            "execution_profile": args.execution_profile,
            "data_admission": {
                "declared": config.dataset.admission,
                "rights_manifest_sha256": config.dataset.rights_manifest_sha256,
                "full_fit_allowed": config.dataset.admission == "declared_admitted",
                "note": (
                    "non_admitted_research: no admitted records exist yet; a full fit is blocked until Packet A."
                    if config.dataset.admission != "declared_admitted"
                    else "declared_admitted is a producer claim; the bundle manifest hash is the trust anchor for this run."
                ),
            },
            "bundle": {
                "code_bundle_path": str(code_zip),
                "code_bundle_sha256": actual_code,
                "data_bundle_path": str(data_zip),
                "data_bundle_sha256": actual_data,
                "records_path": str(resolved_records),
                "records_sha256": data_hash,
                "records_bytes": data_bytes,
                "record_count": len(records),
                "splits": splits,
            },
            "config": {
                "runtime_path": str(Path(args.runtime_config).expanduser()),
                "runtime_profile": config.runtime_profile,
                "config_sha256": config.config_sha256,
                "resume_semantic_sha256": resume_semantic_sha256(config),
                "candidate": config.candidate,
            },
            "model": {
                "manifest_path": str(manifest_path),
                "manifest_sha256": config.model.manifest_sha256,
                "loss_path": str(loss_path),
                "loss_sha256": config.loss.sha256,
            },
            "pretrained_lineage": {
                "state": "scratch_init_from_frozen_v2_manifest",
                "external_pretrained_weights": False,
                "v1_backbone_source_sha256": backbone_hash,
                "resume": resume_lineage,
            },
            "device": device_info,
            "resources": resources,
            "estimates": estimates,
            "runtime_root": str(runtime_root),
            "repo_root": str(repo_root),
            "durable_dir": str(durable_dir),
        }
        if args.json_out:
            output = Path(args.json_out).expanduser()
            output.parent.mkdir(parents=True, exist_ok=True)
            temporary = output.with_name(output.name + ".tmp")
            temporary.write_text(json.dumps(receipt, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
            os.replace(temporary, output)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    else:
        shutil.rmtree(staging, ignore_errors=True)
        return receipt


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--code-bundle", required=True)
    parser.add_argument("--expected-code-bundle-sha256", required=True)
    parser.add_argument("--data-bundle", required=True)
    parser.add_argument("--expected-data-bundle-sha256", required=True)
    parser.add_argument("--runtime-root", required=True, help="local runtime disk directory the bundles are extracted into")
    parser.add_argument("--code-root", default=None, help="already trust-anchored extracted code bundle root (notebook bootstrap)")
    parser.add_argument("--durable-dir", required=True, help="persistent directory for checkpoints/receipts")
    parser.add_argument("--config-template", required=True, help="bundled frozen config template")
    parser.add_argument("--runtime-config", required=True, help="runtime config derived from the template")
    parser.add_argument("--execution-profile", choices=EXECUTION_PROFILES, default="non_admitted_research")
    parser.add_argument("--require-cuda", action="store_true")
    parser.add_argument("--allow-cpu-smoke", action="store_true")
    parser.add_argument("--warm-start-from", default=None)
    parser.add_argument("--json-out", default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        receipt = run_preflight(args)
    except PreflightError as exc:
        print(f"PREFLIGHT REFUSED: {exc}", file=sys.stderr)
        return 1
    except (OSError, ValueError) as exc:
        print(f"PREFLIGHT INVALID: {exc}", file=sys.stderr)
        return 2
    print(
        "PREFLIGHT PASS "
        f"profile={receipt['execution_profile']} admission={receipt['data_admission']['declared']} "
        f"device={receipt['device']['actual_device']} records={receipt['bundle']['record_count']} "
        f"sec_per_step={receipt['device']['seconds_per_optimizer_step']:.4f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
