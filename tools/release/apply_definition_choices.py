#!/usr/bin/env python3
"""Apply the owner's definition choices to the frozen evaluation policy.

Ten rows of the §5.1 table have a threshold and no definition; the candidate
readings are laid out in `evidence-release/definition-packet-5-1.json`, and the
decision belongs to the owner. This tool reduces that decision to one small file:

    {"direction_horizon_precision": "A", "light_exposure_precision": "B", ...}

and does the careful part mechanically — setting `definition_status` and
`definition_source` from the chosen option, bumping `schema_version`, and writing
the chosen options into `revision_history` as the impact list the freeze step
requires. It refuses while any row is unchoiced, so a half-filled file cannot leave
the policy half-edited, and it refuses to apply twice.

The tool does not mark the packet as decided: the packet stays the record of the
finding, and an `applied` record inside the policy says which choices were used.

Exit codes
    0  every row was defined and the policy was rewritten
    1  the choices are syntactically fine but incomplete (a row is missing)
    2  the packet or policy is missing/unreadable, or a choice names no option

Usage
    python3 tools/release/apply_definition_choices.py --choices choices.json [--out receipt.json]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PACKET = (REPO_ROOT / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release"
                  / "definition-packet-5-1.json")
DEFAULT_POLICY = REPO_ROOT / "datasets/camera-coach/v1/evaluation-policy-v1.json"


class InputError(Exception):
    pass


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _patch_version(version: str) -> str:
    """A definition change is substantive: bump the minor, keep the patch at zero."""
    parts = version.split(".")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise InputError(f"policy schema_version {version!r} is not major.minor.patch")
    major, minor, _ = (int(part) for part in parts)
    return f"{major}.{minor + 1}.0"


def load_packet(path: Path) -> dict:
    try:
        packet = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InputError(f"definition packet is unreadable: {error}") from error
    if not isinstance(packet, dict) or not isinstance(packet.get("rows"), dict):
        raise InputError("definition packet carries no rows")
    return packet


def load_choices(path: Path) -> dict[str, str]:
    try:
        choices = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InputError(f"choices file is unreadable: {error}") from error
    if not isinstance(choices, dict) or not choices:
        raise InputError("choices must be a non-empty object mapping row -> option id")
    for row, option in choices.items():
        if not isinstance(option, str) or not option.strip():
            raise InputError(f"choice for {row!r} must be a non-empty option id")
    return {row: option.strip() for row, option in choices.items()}


def resolve(packet: dict, choices: dict[str, str]) -> dict[str, dict]:
    """Validate the choices against the packet and return {row: option}."""
    rows = packet["rows"]
    unknown = sorted(row for row in choices if row not in rows)
    if unknown:
        raise InputError(f"choices name rows that are not in the packet: {unknown}")
    resolved = {}
    for row, option_id in choices.items():
        options = {option["id"]: option for option in rows[row]["options"]}
        if option_id not in options:
            raise InputError(f"{row}: option {option_id!r} does not exist "
                             f"(available: {sorted(options)})")
        resolved[row] = options[option_id]
    return resolved


def apply(policy: dict, resolved: dict[str, dict], choices_sha256: str, applied_at: str) -> dict:
    rows = policy["runbook_5_1_rows"]["rows"]
    missing = sorted(row for row in resolved if row not in rows)
    if missing:
        raise InputError(f"the policy has no such rows: {missing}")
    for row, option in resolved.items():
        entry = rows[row]
        if entry["definition_status"] != "pending_definition":
            raise InputError(f"{row} is already defined (status={entry['definition_status']!r}); "
                             "refusing to overwrite a recorded definition")
        entry["definition_status"] = "defined_by_owner_choice"
        entry["definition_source"] = (f"owner chose option {option['id']} in "
                                      f"evidence-release/definition-packet-5-1.json: "
                                      f"{option['reading']} Formula: {option['formula']}")
        entry["definition_option"] = option["id"]
        entry["definition_evidence"] = option["evidence"]

    old_version = policy["schema_version"]
    policy["schema_version"] = _patch_version(old_version)
    history = policy.setdefault("revision_history", [])
    history.append({
        "from": old_version,
        "to": policy["schema_version"],
        "change": f"definitions chosen for {len(resolved)} §5.1 row(s)",
        "impact": "; ".join(f"{row}: option {option['id']}" for row, option in sorted(resolved.items())),
        "reason": "a threshold without a numerator and denominator cannot be measured; the owner "
                  "chose a reading for each pending row",
    })
    policy["runbook_5_1_rows"]["decision_packet_applied"] = {
        "applied_at": applied_at,
        "choices_sha256": choices_sha256,
        "rows": sorted(resolved),
    }
    return policy


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--choices", type=Path, required=True)
    parser.add_argument("--packet", type=Path, default=DEFAULT_PACKET)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument("--applied-at", default=None, help="stamp to record (default: from the choices file)")
    parser.add_argument("--out", type=Path, help="write a receipt of what was applied")
    args = parser.parse_args(argv)

    if not args.packet.is_file():
        print(f"FAIL CLOSED: definition packet not found: {args.packet}", file=sys.stderr)
        return 2
    if not args.policy.is_file():
        print(f"FAIL CLOSED: policy not found: {args.policy}", file=sys.stderr)
        return 2

    try:
        packet = load_packet(args.packet)
        choices = load_choices(args.choices)
        policy = json.loads(args.policy.read_text(encoding="utf-8"))

        already = (policy.get("runbook_5_1_rows") or {}).get("decision_packet_applied")
        if already:
            print(f"FAIL CLOSED: the choices were already applied on {already.get('applied_at')} "
                  f"(choices sha256 {already.get('choices_sha256')}); restore the policy or record a "
                  "new decision deliberately", file=sys.stderr)
            return 2

        pending = sorted(row for row, entry in policy["runbook_5_1_rows"]["rows"].items()
                         if entry["definition_status"] == "pending_definition")
        if sorted(choices) != pending:
            missing = sorted(set(pending) - set(choices))
            extra = sorted(set(choices) - set(pending))
            print(f"FAIL: the choices must cover every pending row "
                  f"(missing: {missing}; not pending: {extra})", file=sys.stderr)
            return 1

        resolved = resolve(packet, choices)
        stamp = args.applied_at or "recorded-by-the-caller"
        updated = apply(policy, resolved, _sha256(args.choices), stamp)
    except (InputError, OSError, json.JSONDecodeError, KeyError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    args.policy.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"APPLIED {len(resolved)} definition(s); policy {updated['schema_version']}")
    for row, option in sorted(resolved.items()):
        print(f"  {row}: option {option['id']}")

    if args.out is not None:
        receipt = {
            "schema_id": "camera-definition-choices-receipt",
            "schema_version": "1.0.0",
            "applied_at": updated["runbook_5_1_rows"]["decision_packet_applied"]["applied_at"],
            "choices_sha256": updated["runbook_5_1_rows"]["decision_packet_applied"]["choices_sha256"],
            "packet": {"path": str(args.packet), "sha256": _sha256(args.packet)},
            "policy_before": {"path": str(args.policy)},
            "policy_version_after": updated["schema_version"],
            "rows": {row: {"option": option["id"], "formula": option["formula"],
                           "evidence": option["evidence"]}
                     for row, option in sorted(resolved.items())},
            "next_step": ("python3 tools/release/freeze_receipt.py --check (expect exit 2: requires "
                          "impact list), then --write and --check again"),
        }
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"WROTE {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
