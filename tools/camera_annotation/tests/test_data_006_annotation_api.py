#!/usr/bin/env python3
"""DATA-006 focused tests: annotation API pre-write gates (Command Code + teacher).

Covers the tracker Done-when for the local call side only (no network, no
commandcode/ directory):

* invalid or partial model JSON is never persisted as a proposal/gold
  (typed error instead, journal keeps only the error event);
* retries exist solely as bounded backoff on free idempotent endpoints
  (catalog/balance); a paid chat/completions request is never auto-retried;
* credential material is redacted from persisted/echoed error paths;
* the teacher proposal gate validates the raw payload against the exact wire
  schema (proposal_schema) before acceptance.

Run from the repository root::

    python3 -m pytest tools/camera_annotation/tests/test_data_006_annotation_api.py -q
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from PIL import Image  # noqa: E402

import language_review  # noqa: E402
import review_pipeline  # noqa: E402
from annotation_labels import sha256_file  # noqa: E402
from language_labels import FLAGS  # noqa: E402

VALID_KEY = "abcd1234efgh"


def make_review(folder, record_ids=("photo-1",)):
    items = []
    for rid in record_ids:
        image_path = folder / f"{rid}.png"
        Image.new("RGB", (160, 90), (80, 120, 160)).save(image_path)
        items.append(dict(record_id=rid, kind="photo", media_path=str(image_path),
            media_sha256=sha256_file(image_path), title="Фото", source={}, **FLAGS))
    return language_review.Review(folder, items, "data-006", max_requests=5)


@pytest.fixture
def review(tmp_path):
    state = make_review(tmp_path)
    yield state
    state.close()


def journal_states(state):
    return [event["state"] for event in language_review.rows(state.journal)]


def single_visual_error(state, rid):
    events = language_review.rows(state.journal)
    assert "visual_proposal" not in [event["state"] for event in events]
    errors = [event for event in events if event["state"] == "visual_error" and event.get("record_id") == rid]
    assert len(errors) == 1
    assert "interpretation" not in errors[0]
    return errors[0]


# --- (a) invalid / partial model JSON must not be persisted -----------------

def test_invalid_json_not_persisted_as_proposal(review, monkeypatch):
    review.key = VALID_KEY
    calls = []

    def fake_api(path, key="", payload=None):
        calls.append(path)
        return dict(id="resp-1", choices=[dict(message=dict(content="{not json"))])

    monkeypatch.setattr(language_review, "command_api", fake_api)
    review.analyze_visual("photo-1")
    error = single_visual_error(review, "photo-1")
    assert calls == ["chat/completions"]  # exactly one paid attempt, no auto-retry
    assert error["error"] == "JSONDecodeError"
    assert error["billing_unknown"] is False  # provider answered; request count already reserved


def test_partial_schema_invalid_json_not_persisted(tmp_path, monkeypatch):
    state = make_review(tmp_path, ("photo-1", "photo-2"))
    state.key = VALID_KEY
    try:
        partial = dict(verdict=dict(value="good", evidence="ровно"))  # missing 8 required keys

        def partial_api(path, key="", payload=None):
            return dict(id="resp-2", choices=[dict(message=dict(content=json.dumps(partial)))])

        monkeypatch.setattr(language_review, "command_api", partial_api)
        state.analyze_visual("photo-1")
        error = single_visual_error(state, "photo-1")
        assert error["error"] == "ValueError"

        drifted = dict(verdict=dict(value="excellent", evidence="идеально"), issues=[],
            actions=[], intent=dict(value="unknown", evidence=""), subject=dict(description="", evidence=""),
            temporal=dict(value="not_stated", evidence=""), spatial_requests=[], unmapped=[], question=None)

        def enum_api(path, key="", payload=None):
            return dict(id="resp-3", choices=[dict(message=dict(content=json.dumps(drifted)))])

        monkeypatch.setattr(language_review, "command_api", enum_api)
        state.analyze_visual("photo-2")
        error = single_visual_error(state, "photo-2")
        assert error["error"] == "ValueError"
    finally:
        state.close()


def test_valid_visual_proposal_still_persisted(review, monkeypatch):
    review.key = VALID_KEY
    value = dict(verdict=dict(value="good", evidence="кадр ровный"), issues=[],
        actions=[dict(code="keep_current_setup", polarity="acceptable", evidence="всё на месте")],
        intent=dict(value="unknown", evidence=""), subject=dict(description="", evidence=""),
        temporal=dict(value="not_stated", evidence=""), spatial_requests=[], unmapped=[], question=None)

    def good_api(path, key="", payload=None):
        assert path == "chat/completions"
        return dict(id="resp-4", choices=[dict(message=dict(content=json.dumps(value)))])

    monkeypatch.setattr(language_review, "command_api", good_api)
    monkeypatch.setattr(language_review, "summary", lambda value, visual=False: "stub")
    review.analyze_visual("photo-1")
    events = language_review.rows(review.journal)
    assert [event["state"] for event in events].count("visual_proposal") == 1
    proposal = next(event for event in events if event["state"] == "visual_proposal")
    assert proposal["interpretation"]["summary"] == "stub"


# --- (b) retries: bounded backoff on free endpoints, never on paid calls ----

def test_catalog_retry_is_bounded(tmp_path, monkeypatch):
    state = make_review(tmp_path)
    sleeps, attempts = [], []
    monkeypatch.setattr(language_review, "time", SimpleNamespace(sleep=sleeps.append))

    def flaky(path, key="", payload=None):
        attempts.append(path)
        if len(attempts) < 3:
            raise RuntimeError("command_transport_exit_7; billing_unknown")
        return dict(data=[dict(id=language_review.MODEL)])

    monkeypatch.setattr(language_review, "command_api", flaky)
    state.connect(VALID_KEY)
    assert attempts == ["models"] * 3 and sleeps == [1.0, 2.0]
    assert state.key == VALID_KEY and state.model == language_review.MODEL
    connection = next(event for event in language_review.rows(state.journal) if event["state"] == "connection")
    assert connection["key_persisted"] is False and connection["zdr_enforced"] is False
    state.close()


def test_catalog_retry_gives_up_after_three_attempts(tmp_path, monkeypatch):
    state = make_review(tmp_path)
    sleeps, attempts = [], []
    monkeypatch.setattr(language_review, "time", SimpleNamespace(sleep=sleeps.append))

    def always_down(path, key="", payload=None):
        attempts.append(path)
        raise RuntimeError("command_http_503_provider_error; billing_unknown")

    monkeypatch.setattr(language_review, "command_api", always_down)
    with pytest.raises(RuntimeError):
        state.connect(VALID_KEY)
    assert len(attempts) == 3 and sleeps == [1.0, 2.0]
    assert state.key == ""  # connect failed; key never stored
    state.close()


def test_paid_request_is_never_retried(review, monkeypatch):
    review.key = VALID_KEY
    sleeps, attempts = [], []
    monkeypatch.setattr(language_review, "time", SimpleNamespace(sleep=sleeps.append))

    def flaky_paid(path, key="", payload=None):
        attempts.append(path)
        raise RuntimeError("command_transport_exit_7; billing_unknown")

    monkeypatch.setattr(language_review, "command_api", flaky_paid)
    review.analyze_visual("photo-1")
    assert attempts == ["chat/completions"] and sleeps == []
    error = single_visual_error(review, "photo-1")
    assert error["billing_unknown"] is True and review.billing_unknown is True


def test_paid_endpoint_rejected_by_free_retry_allowlist():
    with pytest.raises(ValueError):
        language_review.command_api_free("chat/completions", VALID_KEY)


def test_command_timeout_is_typed_and_content_free(monkeypatch):
    def slow_run(*args, **kwargs):
        raise subprocess.TimeoutExpired(cmd="curl --silent …", timeout=80)

    monkeypatch.setattr(language_review.subprocess, "run", slow_run)
    with pytest.raises(RuntimeError, match="command_transport_timeout"):
        language_review.command_api("models", VALID_KEY)


# --- (d) secret handling: the key never reaches journal or echoed text ------

def test_key_redacted_from_journal_error_paths(review, monkeypatch):
    review.key = VALID_KEY

    def leaky_transport(path, key="", payload=None):
        raise RuntimeError(f"curl exited 7 while sending key {key}")

    monkeypatch.setattr(language_review, "command_api", leaky_transport)
    review.analyze_visual("photo-1")
    journal_text = review.journal.read_text(encoding="utf-8")
    assert VALID_KEY not in journal_text
    error = single_visual_error(review, "photo-1")
    assert VALID_KEY not in error["public_error"] and "[redacted]" in error["public_error"]


def test_redact_helper():
    assert language_review.redact(f"Bearer {VALID_KEY} {VALID_KEY}", VALID_KEY) == "Bearer [redacted] [redacted]"
    assert language_review.redact("no secret", "") == "no secret"


def test_handler_error_echo_is_redacted(tmp_path, monkeypatch):
    state = make_review(tmp_path)

    def leaky_catalog(path, key="", payload=None):
        raise ValueError(f"catalog rejected key {key}")

    monkeypatch.setattr(language_review, "command_api", leaky_catalog)
    with pytest.raises(ValueError) as excinfo:
        state.connect(VALID_KEY)
    # do_POST echoes errors only after redact(); the raw message may carry the key.
    echoed = language_review.redact(str(excinfo.value), VALID_KEY)
    assert VALID_KEY not in echoed
    assert state.key == ""
    state.close()


# --- teacher path (Polza): strict wire-schema gate before write -------------

def teacher_row():
    return dict(record_id="r1", image_sha256="0" * 64)


def valid_proposal():
    return dict(record_id="r1", beauty="beautiful", improvement_needed=False, issues=[],
        actions=["keep_current_setup"], regions=[], notes="Кадр читается", unsure=False)


def test_valid_teacher_proposal_still_accepted():
    review_pipeline.validate_proposal(valid_proposal(), teacher_row())


def test_teacher_schema_gate_rejects_drift_hand_checks_miss():
    # Three distinct corrective actions satisfy every hand check once a subject
    # ROI grounds them, but the wire schema caps actions at 2.
    drifted = dict(valid_proposal(), improvement_needed=True, issues=["horizon_distracts"],
        actions=["shift_frame_left", "shift_frame_right", "step_back"],
        regions=[dict(role="subject", rect=[.1, .1, .5, .5], label="лампа")])
    with pytest.raises(ValueError, match="strict local schema"):
        review_pipeline.validate_proposal(drifted, teacher_row())


def test_teacher_schema_gate_rejects_partial_payload():
    partial = valid_proposal()
    del partial["notes"]
    with pytest.raises(ValueError, match="strict local schema"):
        review_pipeline.validate_proposal(partial, teacher_row())
    assert review_pipeline.schema_violation(dict(valid_proposal(), notes=None), review_pipeline.proposal_schema())
    assert review_pipeline.schema_violation(dict(valid_proposal(), beauty="masterpiece"),
                                           review_pipeline.proposal_schema())


def test_teacher_schema_gate_rejects_nonfinite_rect():
    # json.loads admits NaN/Infinity by default; the gate must not.
    nan_rect = dict(valid_proposal(), regions=[dict(role="subject", rect=[0.1, float("nan"), 0.2, 0.2], label="л")])
    with pytest.raises(ValueError):
        review_pipeline.validate_proposal(nan_rect, teacher_row())


def test_assemble_rejects_schema_invalid_accepted_row(tmp_path):
    row = dict(record_id="r1", review_mode="assisted", image_sha256="0" * 64,
               capture_intent="natural", split="train", review_mode_basis="test")
    accepted = dict(record_id="r1", image_sha256="0" * 64, capture_intent="natural", accepted=True,
        proposal=dict(valid_proposal(), improvement_needed=True, issues=["horizon_distracts"],
            actions=["shift_frame_left", "shift_frame_right", "step_back"],
            regions=[dict(role="subject", rect=[.1, .1, .5, .5], label="лампа")]))
    pilot = tmp_path / "pilot.jsonl"
    results = tmp_path / "results.jsonl"
    review_pipeline.write_rows(pilot, [row])
    review_pipeline.write_rows(results, [accepted])
    with pytest.raises(ValueError, match="strict local schema"):
        review_pipeline.assemble(argparse_namespace(pilot=pilot, results=[results], out=tmp_path / "q.jsonl"))
    assert not (tmp_path / "q.jsonl").exists()


def argparse_namespace(**kwargs):
    import argparse
    return argparse.Namespace(**kwargs)


def test_teacher_transport_redaction_and_bounded_free_retry(monkeypatch):
    key = "polza-secret-key"
    assert review_pipeline.redact(f"Bearer {key} failed", key) == "Bearer [redacted] failed"
    sleeps, calls = [], []

    def flaky(path, key="", payload=None):
        calls.append(path)
        if len(calls) < 3:
            raise RuntimeError("transport_exit_7; billing_unknown")
        return dict(available=100)

    monkeypatch.setattr(review_pipeline, "_polza_api", lambda: flaky)
    monkeypatch.setattr(review_pipeline.time, "sleep", sleeps.append)
    balance = review_pipeline.api_free("balance", key)
    assert balance == dict(available=100)
    assert calls == ["balance"] * 3 and sleeps == [1.0, 2.0]
    with pytest.raises(ValueError):
        review_pipeline.api_free("chat/completions", key)  # paid call is not allowlisted


def test_teacher_timeout_is_not_retried(monkeypatch):
    calls = []

    def slow(path, key="", payload=None):
        calls.append(path)
        raise subprocess.TimeoutExpired(cmd="curl", timeout=80)

    monkeypatch.setattr(review_pipeline, "_polza_api", lambda: slow)
    with pytest.raises(subprocess.TimeoutExpired):
        review_pipeline.api_free("models?type=chat", "k")
    assert calls == ["models?type=chat"]


def test_teacher_wire_schema_covers_output_contract():
    # The gate and the request must speak about the same schema object.
    schema = review_pipeline.proposal_schema()
    assert schema["properties"]["actions"]["maxItems"] == 2
    assert schema["properties"]["regions"]["maxItems"] == 8
    assert not review_pipeline.schema_violation(valid_proposal(), schema)
