# SG v7 CIR Contract Artifacts

This directory contains executable artifacts for `sg_v7_cir_v1`.

## Files

- `cir_schema_v1.json`: machine-readable JSON Schema for CIR records.
- `cir_types.py`: Python `TypedDict` contract for CIR records.
- `cir_validator.py`: schema + invariant validator.
- `cir_serializer.py`: deterministic `CIR -> SceneScript` projection.
- `examples/*.json`: canonical valid records.

## Validation Commands

Validate bundled examples:

```bash
python3 docs/SGv7pipeline/cir_contract/scripts/validate_cir_contract.py
```

Validate specific files:

```bash
python3 docs/SGv7pipeline/cir_contract/scripts/validate_cir_contract.py path/to/file.json
```

Run tests:

```bash
python3 -m unittest discover -s docs/SGv7pipeline/cir_contract/tests
```

Project a CIR file to canonical runtime `SceneScript` JSON:

```bash
python3 generate_dataset_v7.py --cir docs/SGv7pipeline/cir_contract/contracts/examples/ex1_stop_near_marked_then_first_described.json --original-description "Два актёра подходят к ноутбуку, затем первый закуривает."
```
