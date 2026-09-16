#!/usr/bin/env python3
"""Fail-closed importer for SET OS physical device-run reports (Q03/Q04).

This tool takes the JSON manifest an operator fills in after running the locked
device protocols (``docs/implementation/device-tests/recording-v1.md`` and
``ar-workspace-v1.md`` — see the appended v3 case checks) and decides whether the
report may be imported into the evidence chain.

It is deliberately *not* a gate evaluator: it never marks a hardware gate
``pass``. It only proves three things:

1. the report is structurally complete (no missing build/device/OS/source/check
   fields);
2. the run really happened on the pinned build, device and OS, from the pinned
   source state, with every artifact carrying a real timestamp inside the run
   window;
3. each check carries evidence whose *kind* can support the claim. A screenshot
   or a screen recording is never accepted as thermal or audio-sync evidence;
   those require a device-origin benchmark/diagnostics JSON with measured
   samples, verified by content signature, not by a self-declared role string.

The importer defaults to REJECT. A report is accepted only when the caller
supplies the full expectation tuple. Missing expectations, an unknown check id
(which would let the operator silently downgrade a requirement), a tampered
artifact hash, or a file that does not match its claimed role all produce a
non-zero exit and no accepted output.

Usage
    python3 tools/device/import_device_report.py --report run.json \
        --expectations expectations.json [--out accepted.json]

    python3 tools/device/import_device_report.py --template   # print a skeleton

Exit codes
    0  report accepted (only with complete expectations and verified artifacts)
    1  report rejected, with one reason per line
    2  usage error (missing/unreadable input)
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "setos-device-run-report-v1"

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
CHECK_ID = re.compile(r"^[a-z][a-z0-9]*(?:[._][a-z0-9]+)*$")
CASE_ID = re.compile(r"^CC-[A-Z]\d{2}$")

STATUS_VOCABULARY = {
    "executed_pass",
    "executed_fail",
    "not_supported",
    "blocked_source",
    "blocked_external",
    "not_executed",
}

# Status values that assert something actually ran. Every one of these needs at
# least one artifact; the non-executed states need a written reason instead.
EXECUTED_STATUSES = {"executed_pass", "executed_fail"}
NON_EXECUTED_STATUSES = {"not_supported", "blocked_source", "blocked_external", "not_executed"}

_REQUIRED_TOP = (
    "schema_version",
    "run_id",
    "operator",
    "created_utc",
    "build",
    "device",
    "source_state",
    "run_window",
    "checks",
)
_REQUIRED_BUILD = ("build_id", "configuration", "bundle_id", "version", "build_number", "app_sha256")
_REQUIRED_DEVICE = ("kind", "model_identifier", "marketing_name", "os_version", "os_build")
_REQUIRED_SOURCE = ("branch", "head", "porcelain_v2_sha256", "dirty_receipt_sha256", "captured_utc")
_REQUIRED_WINDOW = ("started_utc", "finished_utc")
_REQUIRED_CHECK = ("check_id", "category", "case_ids", "status", "evidence")
_REQUIRED_EVIDENCE = ("path", "sha256", "role", "origin", "captured_utc")

# ---------------------------------------------------------------------------
# Pinned check registry.
#
# The category of a check is fixed here, not in the report: an operator cannot
# relabel a thermal soak as a functional check to escape the metadata
# requirement. An unknown check id is rejected outright so a new check cannot be
# introduced with weaker evidence rules.
# ---------------------------------------------------------------------------

_FUNCTIONAL_CHECKS = (
    "rec.mic_permission",
    "rec.start_stop",
    "rec.orientation",
    "rec.lens_change",
    "rec.audio_interruption",
    "rec.background",
    "rec.low_disk",
    "rec.os_kill",
    "rec.playback",
    "rec.photos_export",
    "rec.share",
    "rec.deletion",
    "ar.entry_readiness",
    "ar.surface_search",
    "ar.placement_determinism",
    "ar.marking_lifecycle",
    "ar.tracking_limitations",
    "ar.interruption",
    "ar.background",
    "ar.world_map_restore",
    "ar.hint_pause",
    "ar.recording_integrity",
    "ar.teardown_convergence",
    "v3.two_object_target",
    "v3.protected_ref_intent",
    "v3.glare_review",
    "v3.video_temporal_coverage",
    "v3.output_crop",
    "v3.track_swap_incomparable",
    "v3.technical_action_verify",
    "v3.lens_switch_fence",
)
_THERMAL_CHECKS = ("rec.soak", "hw.thermal_soak")
_AUDIO_SYNC_CHECKS = ("rec.av_sync",)
_PERF_CHECKS = ("rec.drops_backpressure", "hw.perf_budgets")
_IPAD_CHECKS = ("ar.ipad_window_modes", "hw.ipad_layout")
_ACCESSIBILITY_CHECKS = ("hw.voiceover", "hw.dynamic_type_ru_en")

CATEGORY_BY_CHECK: dict[str, str] = {}
for _check in _FUNCTIONAL_CHECKS:
    CATEGORY_BY_CHECK[_check] = "functional"
for _check in _THERMAL_CHECKS:
    CATEGORY_BY_CHECK[_check] = "thermal"
for _check in _AUDIO_SYNC_CHECKS:
    CATEGORY_BY_CHECK[_check] = "audio_sync"
for _check in _PERF_CHECKS:
    CATEGORY_BY_CHECK[_check] = "perf"
for _check in _IPAD_CHECKS:
    CATEGORY_BY_CHECK[_check] = "ipad_layout"
for _check in _ACCESSIBILITY_CHECKS:
    CATEGORY_BY_CHECK[_check] = "accessibility"

# Content signatures: a role is only believable if the bytes match the medium.
JSON_ROLES = {
    "benchmark_summary",
    "audio_sync_report",
    "thermal_report",
    "diagnostics_export",
    "metadata_dump",
    "accessibility_audit",
    "photos_export_receipt",
    "consent_receipt",
}
JSONL_ROLES = {"perf_samples"}
ZIP_ROLES = {"device_container_archive", "sysdiagnose"}
IMAGE_ROLES = {"screenshot"}
VIDEO_ROLES = {"screen_recording"}
ALL_ROLES = JSON_ROLES | JSONL_ROLES | ZIP_ROLES | IMAGE_ROLES | VIDEO_ROLES

# A category fixes which media can support it, and what measurement the artifact
# must carry. ``forbidden_roles`` is what makes "screenshot is not proof" real:
# even if the bytes are mislabelled, the signature check below catches it.
CATEGORY_RULES: dict[str, dict[str, Any]] = {
    "functional": {
        "allowed_roles": {
            "screen_recording",
            "screenshot",
            "metadata_dump",
            "xcresult",
            "device_container_archive",
        }
        | JSON_ROLES,
        "forbidden_roles": set(),
        "measured_keys": (),
    },
    "ipad_layout": {
        "allowed_roles": {"screen_recording", "screenshot", "metadata_dump", "device_container_archive"},
        "forbidden_roles": set(),
        "measured_keys": (),
    },
    "accessibility": {
        "allowed_roles": {"screen_recording", "screenshot", "accessibility_audit", "device_container_archive"},
        "forbidden_roles": set(),
        "measured_keys": (),
    },
    "thermal": {
        "allowed_roles": {
            "benchmark_summary",
            "perf_samples",
            "thermal_report",
            "diagnostics_export",
            "sysdiagnose",
            "device_container_archive",
        },
        "forbidden_roles": {"screenshot", "screen_recording"},
        "measured_keys": ("thermal_sample_count", "thermal_states_seen"),
    },
    "audio_sync": {
        "allowed_roles": {
            "audio_sync_report",
            "benchmark_summary",
            "diagnostics_export",
            "device_container_archive",
        },
        "forbidden_roles": {"screenshot", "screen_recording"},
        "measured_keys": ("sync_error_start_ms", "sync_error_end_ms"),
    },
    "perf": {
        "allowed_roles": {
            "benchmark_summary",
            "perf_samples",
            "diagnostics_export",
            "device_container_archive",
        },
        "forbidden_roles": {"screenshot", "screen_recording"},
        "measured_keys": (
            "vision_p95_ms",
            "composition_p95_ms",
            "planner_p95_ms",
            "analysis_sample_p95_ms",
            "camera_rss_p95_mb",
        ),
    },
}

# xcresult is accepted structurally but is not a first-class physical artifact;
# it must still be signed/hashed, so the role is kept explicit rather than
# merged into a generic bucket.
CONTENT_ROLES = ALL_ROLES | {"xcresult"}


@dataclasses.dataclass(frozen=True)
class Expectations:
    """The pinned candidate tuple the run must match exactly."""

    build_id: str
    build_sha256: str
    configuration: str
    device_model_identifier: str
    os_version: str
    source_head: str
    source_porcelain_v2_sha256: str
    source_dirty_receipt_sha256: str

    @staticmethod
    def from_mapping(mapping: dict[str, Any]) -> "Expectations":
        field_names = {field.name for field in dataclasses.fields(Expectations)}
        missing = [name for name in field_names if not mapping.get(name)]
        if missing:
            raise ValueError("expectations missing: " + ", ".join(sorted(missing)))
        return Expectations(**{name: str(mapping[name]) for name in field_names})


@dataclasses.dataclass
class ImportResult:
    ok: bool
    errors: list[str]
    normalized: dict[str, Any] | None = None

    def render(self) -> str:
        if self.ok:
            return "ACCEPTED: device run report matches the pinned build/device/OS/source tuple."
        lines = ["REJECTED: device run report failed closed:"]
        lines.extend(f"  - {error}" for error in self.errors)
        return "\n".join(lines)


def _is_nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _parse_utc(value: Any) -> datetime | None:
    if not _is_nonempty_string(value):
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _content_kind(path: Path) -> str:
    """Classify the actual bytes: json, jsonl, zip, png, jpeg, video or other."""
    head = path.read_bytes()[:16]
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if head.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if len(head) >= 12 and head[4:8] == b"ftyp":
        return "video"
    if head.startswith(b"PK\x03\x04") or head.startswith(b"PK\x05\x06"):
        return "zip"
    if head.lstrip()[:1] in {b"{", b"["}:
        return "json"
    return "text"


def _role_accepts(role: str, kind: str) -> bool:
    if role in IMAGE_ROLES:
        return kind in {"png", "jpeg"}
    if role in VIDEO_ROLES:
        return kind in {"video", "png"}
    if role in ZIP_ROLES:
        return kind == "zip"
    if role in JSON_ROLES:
        return kind == "json"
    if role == "perf_samples":
        return kind in {"json", "jsonl", "text"}
    if role == "xcresult":
        return kind in {"zip", "json", "text"}
    return False


def _validate_role_content(role: str, path: Path, errors: list[str], where: str) -> None:
    kind = _content_kind(path)
    if not _role_accepts(role, kind):
        errors.append(
            f"{where}: role '{role}' cannot be backed by {kind} content; "
            "a screenshot/screen recording is not thermal, perf or audio-sync evidence"
            if role in JSON_ROLES | JSONL_ROLES | ZIP_ROLES
            else f"{where}: role '{role}' does not match {kind} content"
        )
        return
    if role in JSON_ROLES:
        try:
            json.loads(path.read_text(encoding="utf-8", errors="strict"))
        except (ValueError, UnicodeDecodeError) as error:
            errors.append(f"{where}: role '{role}' expected valid JSON: {error}")
    elif role == "perf_samples":
        for line_number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if not line.strip():
                continue
            try:
                json.loads(line)
            except ValueError as error:
                errors.append(f"{where}: perf_samples line {line_number} is not JSON: {error}")


def _validate_evidence(
    item: Any,
    category: str,
    report_root: Path,
    run_start: datetime,
    run_finish: datetime,
    clock_skew: timedelta,
    errors: list[str],
    where: str,
) -> dict[str, Any] | None:
    if not isinstance(item, dict):
        errors.append(f"{where}: evidence entry is not an object")
        return None
    missing = [key for key in _REQUIRED_EVIDENCE if key not in item]
    if missing:
        errors.append(f"{where}: evidence missing required fields: {', '.join(missing)}")
        return None

    role = item["role"]
    origin = item["origin"]
    if role not in CONTENT_ROLES:
        errors.append(f"{where}: unknown evidence role '{role}'")
        return None
    if origin not in {"device", "host", "external"}:
        errors.append(f"{where}: unknown evidence origin '{origin}'")
        return None

    captured = _parse_utc(item["captured_utc"])
    if captured is None:
        errors.append(f"{where}: evidence captured_utc is missing or not an ISO-8601 UTC timestamp")
    else:
        low, high = run_start - clock_skew, run_finish + clock_skew
        if not (low <= captured <= high):
            errors.append(
                f"{where}: evidence captured_utc {item['captured_utc']} is outside the run window "
                f"[{run_start.isoformat()}, {run_finish.isoformat()}] (clock skew {int(clock_skew.total_seconds())}s)"
            )

    declared_sha = item["sha256"]
    if not (isinstance(declared_sha, str) and HEX64.match(declared_sha)):
        errors.append(f"{where}: evidence sha256 is not a 64-char lowercase hex digest")
    else:
        resolved = (report_root / item["path"]).resolve()
        try:
            resolved.relative_to(report_root.resolve())
        except ValueError:
            errors.append(f"{where}: evidence path escapes the report root: {item['path']}")
            resolved = None  # type: ignore[assignment]
        if resolved is not None:
            if not resolved.is_file():
                errors.append(f"{where}: evidence file not found: {item['path']}")
            else:
                actual = _sha256(resolved)
                if actual != declared_sha:
                    errors.append(
                        f"{where}: evidence sha256 mismatch for {item['path']} "
                        f"(declared {declared_sha[:12]}…, actual {actual[:12]}…)"
                    )
                else:
                    _validate_role_content(role, resolved, errors, where)

    measured = item.get("measured")
    if measured is not None and not isinstance(measured, dict):
        errors.append(f"{where}: evidence measured field must be an object")
        measured = None

    rules = CATEGORY_RULES[category]
    if role in rules["forbidden_roles"]:
        errors.append(
            f"{where}: category '{category}' forbids role '{role}'; "
            "thermal/audio/perf claims need a measured device export, not a screenshot"
        )
    elif role not in rules["allowed_roles"]:
        errors.append(f"{where}: role '{role}' is not allowed for category '{category}'")

    return {
        "path": item["path"],
        "role": role,
        "origin": origin,
        "captured_utc": item["captured_utc"],
        "sha256": declared_sha,
        "source_timestamp": item.get("source_timestamp"),
        "measured": measured,
    }


def validate_report(
    report: Any,
    expectations: Expectations,
    *,
    report_root: Path | None = None,
    clock_skew_seconds: int = 120,
) -> ImportResult:
    """Validate a device-run report. Pure except for reading the referenced artifacts."""
    errors: list[str] = []
    if not isinstance(report, dict):
        return ImportResult(False, ["report is not a JSON object"])

    for key in _REQUIRED_TOP:
        if key not in report or report[key] in (None, "", [], {}):
            errors.append(f"missing required top-level field: {key}")
    if errors:
        return ImportResult(False, errors)

    if report["schema_version"] != SCHEMA_VERSION:
        return ImportResult(
            False,
            [f"schema_version must be '{SCHEMA_VERSION}', got {report['schema_version']!r}"],
        )

    root = (report_root or Path.cwd()).resolve()
    skew = timedelta(seconds=clock_skew_seconds)

    # --- build -------------------------------------------------------------
    build = report.get("build")
    if not isinstance(build, dict):
        return ImportResult(False, ["build must be an object"])
    for key in _REQUIRED_BUILD:
        if not _is_nonempty_string(build.get(key)):
            errors.append(f"build missing or empty field: {key}")
    if _is_nonempty_string(build.get("build_id")) and build["build_id"] != expectations.build_id:
        errors.append(f"wrong build: report build_id {build['build_id']!r} != pinned {expectations.build_id!r}")
    if _is_nonempty_string(build.get("app_sha256")) and build["app_sha256"] != expectations.build_sha256:
        errors.append(
            f"wrong build artifact: app_sha256 {str(build.get('app_sha256'))[:12]}… != pinned {expectations.build_sha256[:12]}…"
        )
    if _is_nonempty_string(build.get("configuration")) and build["configuration"] != expectations.configuration:
        errors.append(
            f"wrong build configuration: {build['configuration']!r} != pinned {expectations.configuration!r}"
        )
    if _is_nonempty_string(build.get("bundle_id")) and build["bundle_id"] != "com.vigvamcev-media.shafinMultitool":
        errors.append(f"unexpected bundle_id: {build['bundle_id']!r}")

    # --- device ------------------------------------------------------------
    device = report.get("device")
    if not isinstance(device, dict):
        return ImportResult(False, ["device must be an object"])
    for key in _REQUIRED_DEVICE:
        if not _is_nonempty_string(device.get(key)):
            errors.append(f"device missing or empty field: {key}")
    if device.get("kind") != "device":
        errors.append(
            f"device.kind must be 'device' (simulator evidence is not admissible here), got {device.get('kind')!r}"
        )
    if _is_nonempty_string(device.get("model_identifier")) and device["model_identifier"] != expectations.device_model_identifier:
        errors.append(
            f"wrong device: {device['model_identifier']!r} != pinned {expectations.device_model_identifier!r}"
        )
    if _is_nonempty_string(device.get("os_version")) and device["os_version"] != expectations.os_version:
        errors.append(f"wrong OS: {device['os_version']!r} != pinned {expectations.os_version!r}")

    # --- source state ------------------------------------------------------
    source = report.get("source_state")
    if not isinstance(source, dict):
        return ImportResult(False, ["source_state must be an object"])
    for key in _REQUIRED_SOURCE:
        if not _is_nonempty_string(source.get(key)):
            errors.append(f"source_state missing or empty field: {key}")
    if _is_nonempty_string(source.get("head")) and source["head"] != expectations.source_head:
        errors.append(f"wrong source: head {source['head']!r} != pinned {expectations.source_head!r}")
    if _is_nonempty_string(source.get("porcelain_v2_sha256")) and source["porcelain_v2_sha256"] != expectations.source_porcelain_v2_sha256:
        errors.append("wrong source: porcelain_v2_sha256 does not match the pinned dirty tree")
    if _is_nonempty_string(source.get("dirty_receipt_sha256")) and source["dirty_receipt_sha256"] != expectations.source_dirty_receipt_sha256:
        errors.append("wrong source: dirty_receipt_sha256 does not match the pinned dirty tree")
    source_captured = _parse_utc(source.get("captured_utc"))
    if source.get("captured_utc") and source_captured is None:
        errors.append("source_state.captured_utc is not an ISO-8601 UTC timestamp")

    # --- run window --------------------------------------------------------
    window = report.get("run_window")
    if not isinstance(window, dict):
        return ImportResult(False, ["run_window must be an object"])
    for key in _REQUIRED_WINDOW:
        if not _is_nonempty_string(window.get(key)):
            errors.append(f"run_window missing or empty field: {key}")
    run_start = _parse_utc(window.get("started_utc"))
    run_finish = _parse_utc(window.get("finished_utc"))
    if run_start is None:
        errors.append("run_window.started_utc is not an ISO-8601 UTC timestamp")
    if run_finish is None:
        errors.append("run_window.finished_utc is not an ISO-8601 UTC timestamp")
    if run_start is not None and run_finish is not None:
        if run_finish < run_start:
            errors.append("run_window.finished_utc is before started_utc")
        if source_captured is not None and source_captured > run_finish + skew:
            errors.append("source_state.captured_utc is after the run finished; source state is not contemporaneous")

    if run_start is None or run_finish is None:
        return ImportResult(False, errors or ["run window is not parseable"])

    # --- checks ------------------------------------------------------------
    checks = report.get("checks")
    if not isinstance(checks, list) or not checks:
        errors.append("checks must be a non-empty list")
        return ImportResult(False, errors)

    normalized_checks: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, check in enumerate(checks):
        where = f"check[{index}]"
        if not isinstance(check, dict):
            errors.append(f"{where}: not an object")
            continue
        missing = [key for key in _REQUIRED_CHECK if key not in check]
        if missing:
            errors.append(f"{where}: missing fields: {', '.join(missing)}")
            continue
        check_id = check["check_id"]
        where = f"check '{check_id}'"
        if not (isinstance(check_id, str) and CHECK_ID.match(check_id)):
            errors.append(f"{where}: invalid check_id")
            continue
        if check_id in seen:
            errors.append(f"{where}: duplicate check_id")
            continue
        seen.add(check_id)
        if check_id not in CATEGORY_BY_CHECK:
            errors.append(
                f"{where}: unknown check_id; adding checks with unpinned evidence rules is refused"
            )
            continue
        pinned_category = CATEGORY_BY_CHECK[check_id]
        if check.get("category") != pinned_category:
            errors.append(
                f"{where}: category {check.get('category')!r} != pinned {pinned_category!r}; "
                "checks may not be relabelled to weaker rules"
            )
        status = check.get("status")
        if status not in STATUS_VOCABULARY:
            errors.append(f"{where}: unknown status {status!r}")
        case_ids = check.get("case_ids")
        if not isinstance(case_ids, list) or not case_ids:
            errors.append(f"{where}: case_ids must be a non-empty list")
        else:
            for case_id in case_ids:
                if not (isinstance(case_id, str) and CASE_ID.match(case_id)):
                    errors.append(f"{where}: invalid case id {case_id!r}")

        evidence = check.get("evidence")
        if not isinstance(evidence, list):
            errors.append(f"{where}: evidence must be a list")
            evidence = []
        if status in EXECUTED_STATUSES and not evidence:
            errors.append(f"{where}: status {status} requires at least one evidence artifact")
        if status in NON_EXECUTED_STATUSES and not _is_nonempty_string(check.get("reason")):
            errors.append(f"{where}: status {status} requires a written 'reason'")

        normalized_evidence = []
        for evidence_index, item in enumerate(evidence):
            normalized = _validate_evidence(
                item,
                pinned_category,
                root,
                run_start,
                run_finish,
                skew,
                errors,
                f"{where} evidence[{evidence_index}]",
            )
            if normalized is not None:
                normalized_evidence.append(normalized)

        rules = CATEGORY_RULES[pinned_category]
        if status in EXECUTED_STATUSES and rules["measured_keys"] and normalized_evidence:
            merged: dict[str, Any] = {}
            for item in normalized_evidence:
                if isinstance(item.get("measured"), dict):
                    merged.update(item["measured"])
            for key in rules["measured_keys"]:
                if key not in merged:
                    errors.append(
                        f"{where}: category '{pinned_category}' requires measured field '{key}' "
                        "in a device-origin export"
                    )
            device_or_native = any(item["origin"] == "device" for item in normalized_evidence)
            if not device_or_native:
                errors.append(f"{where}: category '{pinned_category}' requires at least one device-origin artifact")

        normalized_checks.append(
            {
                "check_id": check_id,
                "category": pinned_category,
                "case_ids": case_ids,
                "status": status,
                "reason": check.get("reason"),
                "evidence": normalized_evidence,
            }
        )

    if errors:
        return ImportResult(False, errors)

    normalized = {
        "import_verdict": "accepted",
        "schema_version": SCHEMA_VERSION,
        "run_id": report["run_id"],
        "build": {
            "build_id": build["build_id"],
            "configuration": build["configuration"],
            "bundle_id": build["bundle_id"],
            "version": build["version"],
            "build_number": build["build_number"],
            "app_sha256": build["app_sha256"],
        },
        "device": {
            "kind": device["kind"],
            "model_identifier": device["model_identifier"],
            "marketing_name": device["marketing_name"],
            "os_version": device["os_version"],
            "os_build": device["os_build"],
            "udid": device.get("udid"),
        },
        "source_state": dict(source),
        "run_window": dict(window),
        "checks": normalized_checks,
        "import_note": (
            "The importer verified structure, the pinned tuple and artifact content. "
            "It does not grade any hardware gate; accepting a report is not a PASS."
        ),
    }
    return ImportResult(True, [], normalized)


def _template(expectations: Expectations | None) -> dict[str, Any]:
    exp = expectations
    return {
        "schema_version": SCHEMA_VERSION,
        "run_id": "<operator-set run id, e.g. q04-2026-10-01-iphone13pro>",
        "operator": "<name>",
        "created_utc": "<ISO-8601 UTC>",
        "build": {
            "build_id": exp.build_id if exp else "<pinned build id from Q01>",
            "configuration": exp.configuration if exp else "Debug",
            "bundle_id": "com.vigvamcev-media.shafinMultitool",
            "version": "1.0",
            "build_number": "<CFBundleVersion>",
            "app_sha256": exp.build_sha256 if exp else "<sha256 of the exact installed .app bundle>",
        },
        "device": {
            "kind": "device",
            "model_identifier": exp.device_model_identifier if exp else "iPhone14,2",
            "marketing_name": "iPhone 13 Pro",
            "os_version": exp.os_version if exp else "<iOS version>",
            "os_build": "<iOS build>",
            "udid": "<UDID>",
        },
        "source_state": {
            "branch": "store",
            "head": exp.source_head if exp else "<40-hex>",
            "porcelain_v2_sha256": exp.source_porcelain_v2_sha256 if exp else "<64-hex>",
            "dirty_receipt_sha256": exp.source_dirty_receipt_sha256 if exp else "<64-hex>",
            "captured_utc": "<ISO-8601 UTC>",
        },
        "run_window": {"started_utc": "<ISO-8601 UTC>", "finished_utc": "<ISO-8601 UTC>"},
        "checks": [
            {
                "check_id": "rec.mic_permission",
                "category": "functional",
                "case_ids": ["CC-R02"],
                "status": "not_executed",
                "reason": "<fill in; never pre-mark a hardware gate pass>",
                "evidence": [],
            },
            {
                "check_id": "rec.soak",
                "category": "thermal",
                "case_ids": ["CC-R04"],
                "status": "not_executed",
                "reason": "<a screenshot is not thermal evidence; attach the benchmark diagnostics export>",
                "evidence": [],
            },
        ],
    }


def _load_json(path: Path, parser: argparse.ArgumentParser) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        parser.error(f"file not found: {path}")
    except json.JSONDecodeError as error:
        parser.error(f"{path} is not valid JSON: {error}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fail-closed importer for SET OS device-run reports.")
    parser.add_argument("--report", type=Path, help="device-run report JSON")
    parser.add_argument("--expectations", type=Path, help="pinned candidate expectations JSON")
    parser.add_argument("--report-root", type=Path, help="root the evidence paths are relative to (default: report's directory)")
    parser.add_argument("--out", type=Path, help="write the accepted normalized report here (on success only)")
    parser.add_argument("--clock-skew-seconds", type=int, default=120, help="tolerance for device clock skew (default 120)")
    parser.add_argument("--template", action="store_true", help="print a report skeleton and exit")
    args = parser.parse_args(argv)

    expectations: Expectations | None = None
    if args.expectations is not None:
        raw = _load_json(args.expectations, parser)
        if not isinstance(raw, dict):
            parser.error("expectations file must contain a JSON object")
        try:
            expectations = Expectations.from_mapping(raw)
        except ValueError as error:
            print(f"FAIL CLOSED: {error}")
            return 1

    if args.template:
        print(json.dumps(_template(expectations), ensure_ascii=False, indent=2))
        return 0

    if args.report is None:
        parser.error("--report is required (or use --template)")
    if expectations is None:
        print("FAIL CLOSED: --expectations is required; without the pinned tuple no exact-match claim is possible.")
        return 1

    raw_report = _load_json(args.report, parser)
    root = args.report_root if args.report_root is not None else args.report.resolve().parent
    result = validate_report(
        raw_report,
        expectations,
        report_root=root,
        clock_skew_seconds=args.clock_skew_seconds,
    )
    print(result.render())
    if not result.ok:
        return 1
    if args.out is not None and result.normalized is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result.normalized, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"WROTE {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
