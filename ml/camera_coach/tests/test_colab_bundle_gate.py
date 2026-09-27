#!/usr/bin/env python3
"""Human-gold gate колаб-бандла (ML-004): envelope-aware и только adjudicated gold.

Регрессия, которую закрывает набор: gate считал ``row["human_gold"]`` на верхнем
уровне строки, а экспорт аннотаций кладёт gold в ``release_label.provenance`` —
даже корректные adjudicated-конверты были бы навсегда отвергнуты. Считаются
только строки с ``human_gold=true`` + ``review_status=adjudicated`` +
``adjudicator_id`` (DATA-011): raw review никогда не gold.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

CAMERA_COACH = Path(__file__).resolve().parents[1]
BUNDLE = CAMERA_COACH / "colab_bundle"
FIXTURES = CAMERA_COACH / "contracts" / "fixtures"

spec = importlib.util.spec_from_file_location("colab_check_environment", BUNDLE / "check_environment.py")
check_environment = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = check_environment
spec.loader.exec_module(check_environment)

VALID_LABEL = json.loads((FIXTURES / "camera_release_label_v1.valid.json").read_text(encoding="utf-8"))


def envelope_of(label: dict) -> dict:
    return {"envelope_schema_id": "camera-release-label-enveloped-v1",
            "envelope_version": 1, "release_label": label, "raw_opinion": {"text": "тест"}}


def with_provenance(**overrides) -> dict:
    label = json.loads(json.dumps(VALID_LABEL))
    label["provenance"].update(overrides)
    return label


def test_adjudicated_gold_envelope_is_counted():
    assert check_environment.human_gold_of(envelope_of(VALID_LABEL)) == VALID_LABEL


def test_plain_release_label_row_is_counted():
    assert check_environment.human_gold_of(VALID_LABEL) == VALID_LABEL


def test_raw_review_gold_is_never_counted():
    raw = with_provenance(human_gold=True, review_status="reviewed", adjudicator_id=None)
    assert check_environment.human_gold_of(envelope_of(raw)) is None


def test_gold_without_adjudicator_is_refused():
    missing = with_provenance(human_gold=True, review_status="adjudicated", adjudicator_id=None)
    assert check_environment.human_gold_of(envelope_of(missing)) is None


def test_unadjudicated_or_unknown_shapes_are_refused():
    assert check_environment.human_gold_of({}) is None
    assert check_environment.human_gold_of({"release_label": {}}) is None
    assert check_environment.human_gold_of({"release_label": {"provenance": "нет"}}) is None
    assert check_environment.human_gold_of({"human_gold": True}) is None  # legacy-верхний уровень не обманывает


def test_contract_validation_calls_the_real_validator_api():
    """Регрессия: гейт звал несуществующий validate_release_label → AttributeError."""
    contracts = CAMERA_COACH / "contracts"
    assert check_environment.contract_invalid_indexes([VALID_LABEL], contracts,
                                                      time_budget_s=None) == []
    broken = with_provenance()
    broken["verdict"] = {"not": "a valid verdict"}
    assert check_environment.contract_invalid_indexes([VALID_LABEL, broken], contracts,
                                                      time_budget_s=None) == [1]
