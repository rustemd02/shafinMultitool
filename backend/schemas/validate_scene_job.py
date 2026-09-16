#!/usr/bin/env python3
"""Validate the versioned SET OS Scene Generation job envelope (M12-003).

Mirrors the conventions of datasets/scene-generator/v1/schema/
validate_scene_schema.py: Draft 2020-12 validation is mandatory, plus
stdlib semantic checks JSON Schema cannot express (request/epoch binding
between the envelope and an embedded clarification payload, terminal
branch exclusivity already enforced by schema allOf, size bounds).

Positive fixtures: job-valid-{pending,running,complete,
awaiting-clarification,failed,cancelled}.json
Negative fixtures: job-invalid-*.json (each must FAIL validation).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures"
JOB_SCHEMA = ROOT / "scene-job-v1.schema.json"
CONTRACT_SCHEMA = Path(__file__).resolve().parent.parent.parent / (
    "datasets/scene-generator/v1/schema/scene-contract-v1.schema.json"
)
MAX_BYTES = 256 * 1024

REQUEST_ID = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)
HASH = re.compile(r"^[0-9a-f]{64}$")


def load_json(path: Path) -> object:
    raw = path.read_bytes()
    if len(raw) > MAX_BYTES:
        raise ValueError(f"{path.name}: exceeds {MAX_BYTES} bytes")
    return json.loads(raw.decode("utf-8"))


def semantic_check(doc: dict) -> list[str]:
    errors: list[str] = []
    req = doc.get("request_id")
    if not isinstance(req, str) or not REQUEST_ID.match(req):
        errors.append("request_id must be UUID")
    h = doc.get("request_hash")
    if not isinstance(h, str) or not HASH.match(h):
        errors.append("request_hash must be lowercase hex sha256")
    for key in ("model_version", "prompt_version", "provider_name", "provider_version"):
        v = doc.get(key)
        if not isinstance(v, str) or not v or len(v) > 128:
            errors.append(f"{key} must be non-empty text ≤128")
    clar = doc.get("clarification")
    if isinstance(clar, dict):
        if clar.get("requestID") != req:
            errors.append("clarification.requestID must equal envelope request_id")
        ep = clar.get("epoch")
        if not isinstance(ep, int) or ep < 0:
            errors.append("clarification.epoch must be non-negative")
        opts = clar.get("options")
        if not isinstance(opts, list):
            errors.append("clarification.options must be a list")
        else:
            seen = set()
            for o in opts:
                oid = o.get("id") if isinstance(o, dict) else None
                if not isinstance(oid, str) or not oid:
                    errors.append("clarification option id must be non-empty")
                elif oid in seen:
                    errors.append(f"duplicate clarification option id {oid}")
                else:
                    seen.add(oid)
    res = doc.get("result")
    if isinstance(res, dict):
        for key in ("model_version", "prompt_version"):
            if res.get(key) != doc.get(key):
                errors.append(f"result.{key} must equal envelope {key}")
        if res.get("schema_version") != "scene-script-v1":
            errors.append("result.schema_version must be scene-script-v1")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixtures", type=Path, default=FIXTURES)
    args = ap.parse_args()
    try:
        import jsonschema
        from referencing import Registry, Resource
    except ImportError:
        print("FAIL: jsonschema (with referencing) is required; refusing to pass without Draft 2020-12 validation")
        return 1
    schema = load_json(JOB_SCHEMA)
    contract = json.loads(CONTRACT_SCHEMA.read_bytes().decode("utf-8"))
    canonical = "https://set-os.local/schemas/scene-contract-v1.schema.json"
    registry = Registry().with_resources([
        ("scene-contract-v1.schema.json", Resource.from_contents(contract)),
        (canonical, Resource.from_contents(contract)),
    ])
    validator = jsonschema.Draft202012Validator(schema, registry=registry)
    positives = sorted(args.fixtures.glob("job-valid-*.json"))
    negatives = sorted(args.fixtures.glob("job-invalid-*.json"))
    # A fixtures directory that holds neither kind validates nothing while printing
    # the same PASS as a full run, so the counts are a precondition, not a summary.
    if not positives or not negatives:
        print("FAIL: fixtures are missing")
        print(f"  {args.fixtures}: {len(positives)} positive, {len(negatives)} negative")
        print("  a run needs at least one of each: positives prove the schema accepts a "
              "well-formed envelope, negatives prove it rejects a malformed one")
        return 1
    failures: list[str] = []
    for path in positives:
        doc = load_json(path)
        schema_errors = list(validator.iter_errors(doc))
        sem_errors = semantic_check(doc) if isinstance(doc, dict) else ["not an object"]
        if schema_errors or sem_errors:
            failures.append(f"{path.name}: UNEXPECTED FAIL")
            for e in schema_errors[:4]:
                failures.append(f"  schema: {e.message[:160]}")
            for e in sem_errors[:4]:
                failures.append(f"  semantic: {e}")
    for path in negatives:
        doc = load_json(path)
        schema_errors = list(validator.iter_errors(doc))
        sem_errors = semantic_check(doc) if isinstance(doc, dict) else ["not an object"]
        if not schema_errors and not sem_errors:
            failures.append(f"{path.name}: UNEXPECTED PASS (negative must fail)")
    if failures:
        print("FAIL")
        for f in failures:
            print(f)
        return 1
    print(f"PASS: {len(positives)} positive + {len(negatives)} negative job fixtures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
