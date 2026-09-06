#!/usr/bin/env python3
"""M3-026: scene annotation tooling (candidate assist, not a labeler).

Reads a scene annotation input record (candidates + acceptable variants in
the M3-023 vocabulary), verifies every candidate alternative is intact, and
writes a schema-valid gold scaffold that a human annotator reviews: the
primary candidate plus the full preserved variant list, empty votes, and an
empty review history awaiting the M3-005 pilot.

Hard guarantees:
- every candidate and every acceptable variant from the input is preserved
  verbatim in the output (dropping or editing one is a typed failure);
- the output validates against scene-annotation-v1.schema.json (Draft
  2020-12, mandatory);
- no model identity is exposed: the tool records only its own tool id and
  schema version, never a model name, checkpoint, or score.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any

TOOL_ID = "scene-annotation-assist-v1"

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SCHEMA = (
    REPO_ROOT
    / "datasets"
    / "scene-generator"
    / "v1"
    / "schema"
    / "scene-annotation-v1.schema.json"
)


class AnnotationError(Exception):
    """One deterministic tooling failure with a stable message."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AnnotationError(f"cannot read JSON at {path}: {error}") from error


SHARED_SCHEMA = (
    REPO_ROOT
    / "datasets"
    / "scene-generator"
    / "v1"
    / "schema"
    / "scene-contract-v1.schema.json"
)
CANONICAL_SHARED_URI = "https://set-os.local/schemas/scene-contract-v1.schema.json"


def validate_against_schema(record: dict[str, Any]) -> None:
    try:
        from jsonschema import Draft202012Validator, FormatChecker
    except ImportError as error:
        raise AnnotationError(
            "jsonschema (Draft 2020-12) is required; the tool fails closed without it"
        ) from error
    schema = load_json(SCHEMA)
    shared = load_json(SHARED_SCHEMA)
    try:
        from referencing import Registry, Resource
    except ImportError:
        from jsonschema import RefResolver

        resolver = RefResolver(
            base_uri=SCHEMA.as_uri(),
            referrer=schema,
            store={SHARED_SCHEMA.as_uri(): shared, CANONICAL_SHARED_URI: shared},
        )
        validator = Draft202012Validator(schema, resolver=resolver, format_checker=FormatChecker())
    else:
        registry = Registry().with_resource(CANONICAL_SHARED_URI, Resource.from_contents(shared))
        validator = Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(record), key=lambda e: list(e.path))
    if errors:
        location = "/".join(str(part) for part in errors[0].path) or "<root>"
        raise AnnotationError(
            f"gold candidate fails schema at '{location}': {errors[0].message}"
        )


def scaffold_gold(scene_input: dict[str, Any]) -> dict[str, Any]:
    """Build a draft gold annotation from a scene annotation input record.

    Candidates and acceptable variants are deep-copied verbatim. The gold
    points at the first candidate as the primary and lists every acceptable
    variant id; votes and review history start empty for the human pilot.
    The tool never invents entities, actions, variants, or resolutions.
    """
    candidates = scene_input.get("candidates")
    if not candidates:
        raise AnnotationError("scene input has no candidates to preserve")
    variants = scene_input.get("acceptable_variants", [])

    gold_record = copy.deepcopy(scene_input)
    gold_record["gold"] = {
        "primary_candidate_id": candidates[0]["candidate_id"],
        "acceptable_variant_ids": [v["variant_id"] for v in variants],
    }
    gold_record["votes"] = []
    gold_record["review_history"] = []
    return gold_record


def check_alternatives_preserved(scene_input: dict[str, Any], gold: dict[str, Any]) -> None:
    for key in ("candidates", "acceptable_variants"):
        wanted = scene_input.get(key, [])
        kept = gold.get(key, [])
        if kept != wanted:
            raise AnnotationError(
                f"{key} changed: input has {len(wanted)}, gold has {len(kept)}"
            )
    wanted_ids = [c["candidate_id"] for c in scene_input.get("candidates", [])]
    if gold.get("gold", {}).get("primary_candidate_id") not in wanted_ids:
        raise AnnotationError("gold primary points outside the preserved candidates")
    wanted_variants = {v["variant_id"] for v in scene_input.get("acceptable_variants", [])}
    for variant_id in gold.get("gold", {}).get("acceptable_variant_ids", []):
        if variant_id not in wanted_variants:
            raise AnnotationError(f"gold references undeclared variant {variant_id!r}")


def check_no_model_identity(gold: dict[str, Any]) -> None:
    # Model-kind candidates may exist as reviewable alternatives, but gold
    # must never SELECT one as primary: the primary is always human (or
    # deterministic) work. Name/token scans catch smuggled identities.
    primary = gold.get("gold", {}).get("primary_candidate_id")
    primaries = [c for c in gold.get("candidates", []) if c.get("candidate_id") == primary]
    if primaries and primaries[0].get("kind") not in ("human", "deterministic"):
        raise AnnotationError(
            f"gold primary {primary!r} exposes model identity "
            f"(kind {primaries[0].get('kind')!r})"
        )
    blob = json.dumps(gold, ensure_ascii=False).lower()
    for token in ("gpt", "claude", "llama", "checkpoint", "ckpt", "weights"):
        if token in blob:
            raise AnnotationError(f"gold candidate exposes model identity token {token!r}")


def annotate_file(input_path: Path, output_path: Path) -> dict[str, Any]:
    scene_input = load_json(input_path)
    gold = scaffold_gold(scene_input)
    check_alternatives_preserved(scene_input, gold)
    check_no_model_identity(gold)
    validate_against_schema(gold)
    output_path.write_text(json.dumps(gold, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return gold


def self_test() -> int:
    fixtures = Path(__file__).resolve().parent / "fixtures"
    gold = annotate_file(
        fixtures / "positive-annotation-input.json",
        fixtures / ".self-test-gold.json",
    )
    assert gold["votes"] == [] and gold["review_history"] == []
    assert gold["gold"]["primary_candidate_id"] == "candidate_human"
    (fixtures / ".self-test-gold.json").unlink(missing_ok=True)

    negatives = sorted((fixtures / "negative").glob("*.driver.json"))
    if len(negatives) < 3:
        raise AnnotationError(f"expected at least 3 negative fixtures, found {len(negatives)}")
    checked = 0
    for path in negatives:
        payload = load_json(path)
        input_name = payload["input"]
        input_path = (fixtures / "negative" / input_name) if (fixtures / "negative" / input_name).exists() else (fixtures / input_name)
        negative_record = load_json(input_path)
        try:
            if "gold" in payload:
                # Check-level fixture: the checks run against a supplied
                # (mutated or smuggled) gold candidate. Model-identity runs
                # first so a smuggled primary is reported as identity
                # exposure, not as a preservation diff.
                mutated = load_json(fixtures / "negative" / payload["gold"])
                negative_record = load_json(input_path)
                check_no_model_identity(mutated)
                check_alternatives_preserved(negative_record, mutated)
                validate_against_schema(mutated)
            else:
                gold = scaffold_gold(negative_record)
                check_alternatives_preserved(negative_record, gold)
                check_no_model_identity(gold)
                validate_against_schema(gold)
        except AnnotationError as error:
            expected = payload["expected_error_contains"]
            if expected not in str(error):
                raise AnnotationError(
                    f"{path.name}: {str(error)!r} does not mention {expected!r}"
                ) from error
            checked += 1
        else:
            raise AnnotationError(f"{path.name}: negative fixture unexpectedly passed")
    print(f"scene annotation v1: scaffold OK, {checked} negative fixtures rejected")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        if args.self_test:
            return self_test()
        if not args.input or not args.output:
            parser.error("--input and --output are required without --self-test")
        gold = annotate_file(args.input, args.output)
        print(f"scene annotation v1: gold scaffold for {gold.get('annotation_id')} written")
        return 0
    except AnnotationError as error:
        print(f"scene annotation v1: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
