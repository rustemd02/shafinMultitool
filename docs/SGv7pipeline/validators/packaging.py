from __future__ import annotations

from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from copy import deepcopy
from typing import Iterable

from cir_contract.contracts import structural_hash
from source_generation.prompt_builder import extract_required_surface_anchors

from .anchor_checks import validate_anchor_checks
from .config import ValidationDecision, ValidationRequest, ValidationRunResult
from .contracts import (
    ALLOWED_GENERATION_PASSES,
    canonical_graph_id,
    clone_record,
    has_required_envelope_fields,
    has_required_graph_constraints,
)
from .graph_checks import validate_graph_consistency
from .provenance import evaluate_provenance, train_eligibility_for
from .recoverability import compute_recoverability_score, deterministic_beat_collapse, recoverability_overcompressed
from .schema_checks import validate_schema_and_runtime_projection
from .semantic_critic import SemanticCriticError, run_semantic_critic
from .writer import read_jsonl, write_json, write_jsonl

_SAFE_SOFT_FAIL_CODES = {
    "semantic_marked_object_lost",
    "semantic_ordinal_anchor_lost",
    "semantic_beat_collapse",
}


def _cir_index(path: ValidationRequest) -> tuple[dict[str, dict[str, object]], set[str]]:
    if path.cir_jsonl is None:
        return {}, set()
    rows = read_jsonl(path.cir_jsonl)
    index: dict[str, dict[str, object]] = {}
    duplicates: set[str] = set()
    for row in rows:
        sample_id = str(row.get("sample_id", ""))
        if not sample_id:
            continue
        if sample_id in index:
            duplicates.add(sample_id)
            continue
        index[sample_id] = row
    return index, duplicates


def _resolve_cir_record(
    sample: dict[str, object],
    *,
    cir_index: dict[str, dict[str, object]],
    duplicate_sample_ids: set[str],
    request: ValidationRequest,
) -> tuple[dict[str, object] | None, list[str]]:
    sample_id = str(sample.get("sample_id", ""))
    embedded = sample.get("cir_record")
    if isinstance(embedded, dict):
        if embedded.get("sample_id") != sample_id:
            return None, ["contract_sample_id_mismatch"]
        return embedded, []
    if request.cir_jsonl is None:
        return None, ["contract_missing_cir_join_source"]
    if sample_id in duplicate_sample_ids:
        return None, ["contract_cir_join_non_unique"]
    cir_record = cir_index.get(sample_id)
    if cir_record is None:
        return None, ["contract_cir_join_not_found"]
    if cir_record.get("sample_id") != sample_id:
        return None, ["contract_sample_id_mismatch"]
    return cir_record, []


def _bucket_metrics(sample: dict[str, object], cir_record: dict[str, object]) -> dict[str, int]:
    anchors = extract_required_surface_anchors(cir_record)
    return {
        "marked_object_recall_expected": 1 if anchors["required_aliases"] else 0,
        "ordinal_binding_expected": len(anchors["required_ordinal_tokens"]),
        "must_keep_lemma_expected": len(sample.get("graph_constraints", {}).get("must_keep_lemmas", [])),
    }


def _apply_critic_payload(report: dict[str, object], critic_result: object) -> None:
    report["critic_verdict"] = critic_result.verdict
    report["critic_model"] = critic_result.execution.get("model", report.get("critic_model"))
    report["critic_artifact_id"] = critic_result.artifact_id
    report["critic_execution"] = critic_result.execution
    report["critic_confidence"] = critic_result.confidence
    report["critic_detected_failures"] = list(critic_result.detected_failures)
    report["critic_chronology_preserved"] = critic_result.chronology_preserved
    report["critic_object_grounding_preserved"] = critic_result.object_grounding_preserved
    report["critic_ordinal_binding_preserved"] = critic_result.ordinal_binding_preserved
    report["critic_unsupported_action_preserved"] = critic_result.unsupported_action_preserved
    report["critic_invented_content_present"] = critic_result.invented_content_present
    report["critic_summary"] = critic_result.summary
    report["semantic_findings"] = list(critic_result.findings)


def _soft_fail_can_be_auto_accepted(
    *,
    record: dict[str, object],
    cir_record: dict[str, object],
    critic_result: object | None,
    recoverability_band: str,
) -> bool:
    if critic_result is None or critic_result.verdict != "soft_fail":
        return False
    if recoverability_band != "high":
        return False
    if bool(getattr(critic_result, "invented_content_present", False)):
        return False

    detected_failures = {str(item) for item in critic_result.detected_failures}
    if not detected_failures or not detected_failures <= _SAFE_SOFT_FAIL_CODES:
        return False
    if "semantic_beat_collapse" in detected_failures and deterministic_beat_collapse(cir_record, record):
        return False
    return True


def validate_sample(
    sample: dict[str, object],
    request: ValidationRequest,
    *,
    cir_index: dict[str, dict[str, object]],
    duplicate_sample_ids: set[str],
) -> ValidationDecision:
    record = clone_record(sample)
    reject_reasons: list[str] = []
    review_reasons: list[str] = []

    if not has_required_envelope_fields(record):
        reject_reasons.append("contract_missing_required_field")
    if not has_required_graph_constraints(record):
        reject_reasons.append("contract_missing_graph_constraints")
    generation_pass = record.get("generation_pass")
    if generation_pass not in ALLOWED_GENERATION_PASSES:
        reject_reasons.append("contract_unknown_generation_pass")

    cir_record = None
    cir_reasons: list[str] = []
    if not reject_reasons:
        cir_record, cir_reasons = _resolve_cir_record(
            record,
            cir_index=cir_index,
            duplicate_sample_ids=duplicate_sample_ids,
            request=request,
        )
        reject_reasons.extend(cir_reasons)

    correction_tier, provenance_rejects, provenance_reviews = evaluate_provenance(record)
    reject_reasons.extend(provenance_rejects)
    review_reasons.extend(provenance_reviews)

    schema_passed = False
    graph_passed = False
    anchor_passed = False
    critic_result = None
    critic_error: str | None = None
    recoverability_score = 0
    recoverability_band = "low"
    soft_fail_auto_accepted = False

    if cir_record is not None and not reject_reasons:
        schema_reasons = validate_schema_and_runtime_projection(cir_record, source_text=str(record["source_text"]))
        if schema_reasons:
            reject_reasons.extend(schema_reasons)
        else:
            schema_passed = True

    graph_reasons: list[str] = []
    if cir_record is not None and schema_passed:
        graph_reasons = validate_graph_consistency(cir_record)
        if graph_reasons:
            reject_reasons.extend(graph_reasons)
        else:
            graph_passed = True

    anchor_reasons: list[str] = []
    if cir_record is not None and graph_passed:
        anchor_reasons = validate_anchor_checks(record, cir_record)
        if anchor_reasons:
            reject_reasons.extend(anchor_reasons)
        else:
            anchor_passed = True

    if cir_record is not None and anchor_passed:
        try:
            critic_result = run_semantic_critic(record, request, cir_record=cir_record)
        except SemanticCriticError as exc:
            critic_error = str(exc)
            reject_reasons.append("contract_invalid_critic_payload")
        else:
            if critic_result.verdict == "hard_fail":
                reject_reasons.extend(critic_result.detected_failures)

            recoverability_score, recoverability_band = compute_recoverability_score(
                record,
                cir_record,
                critic_result={
                    "chronology_preserved": critic_result.chronology_preserved,
                    "unsupported_action_preserved": critic_result.unsupported_action_preserved,
                    "object_grounding_preserved": critic_result.object_grounding_preserved,
                    "ordinal_binding_preserved": critic_result.ordinal_binding_preserved,
                },
                graph_reasons=graph_reasons + anchor_reasons + list(critic_result.detected_failures),
            )
            if recoverability_overcompressed(record, cir_record):
                reject_reasons.append("recoverability_overcompressed")
            if recoverability_band == "low":
                reject_reasons.append("recoverability_too_low")
            elif recoverability_band == "borderline":
                review_reasons.append("review_recoverability_borderline")

            soft_fail_auto_accepted = _soft_fail_can_be_auto_accepted(
                record=record,
                cir_record=cir_record,
                critic_result=critic_result,
                recoverability_band=recoverability_band,
            )
            if critic_result.verdict == "soft_fail" and not soft_fail_auto_accepted:
                review_reasons.append("review_critic_soft_fail")

    if record.get("graph_constraints", {}).get("same_type_marker_conflict"):
        same_type_failures = set(anchor_reasons)
        if critic_result is not None:
            same_type_failures.update(str(item) for item in critic_result.detected_failures)
        if not reject_reasons and (
            {"semantic_same_type_disambiguation_lost", "semantic_exact_marker_id_conflict"} & same_type_failures
            or recoverability_band == "borderline"
            or (
                critic_result is not None
                and critic_result.verdict == "soft_fail"
                and not soft_fail_auto_accepted
            )
        ):
            review_reasons.append("review_same_type_marker_conflict")
    if record.get("generation_pass") == "augmentation" and record.get("risk_flags"):
        if any(flag == "risky_transform_requested" for flag in record.get("risk_flags", [])):
            review_reasons.append("review_risky_augmentation_candidate")

    reject_reasons = sorted(set(reject_reasons))
    review_reasons = sorted(set(review_reasons))

    if reject_reasons:
        status = "rejected"
    elif review_reasons:
        status = "manual_review"
    else:
        status = "accepted"

    train_eligibility = train_eligibility_for(status, correction_tier)
    validation_report: dict[str, object] = {
        "validator_stack_version": request.validator_stack_version,
        "schema_checks_passed": schema_passed,
        "graph_checks_passed": graph_passed,
        "anchor_checks_passed": anchor_passed,
        "critic_verdict": critic_result.verdict if critic_result is not None else "hard_fail" if reject_reasons else "pass",
        "critic_model": request.critic_model,
        "recoverability_score": recoverability_score,
        "recoverability_band": recoverability_band,
        "review_required": status == "manual_review",
        "reject_reasons": reject_reasons,
        "review_reasons": review_reasons,
        "semantic_findings": list(critic_result.findings) if critic_result is not None else [],
        "bucket_metrics": _bucket_metrics(record, cir_record) if cir_record is not None else {
            "marked_object_recall_expected": 0,
            "ordinal_binding_expected": 0,
            "must_keep_lemma_expected": 0,
        },
    }
    if critic_result is not None:
        validation_report["critic_model"] = request.critic_model
        _apply_critic_payload(validation_report, critic_result)
    if critic_error is not None:
        validation_report["critic_error"] = critic_error

    output_record = deepcopy(record)
    output_record["graph_id"] = canonical_graph_id(output_record)
    output_record["correction_tier"] = correction_tier
    output_record["validation_status"] = status
    output_record["train_eligibility"] = train_eligibility
    output_record["validation_report"] = validation_report
    if cir_record is not None:
        output_record["graph_hash"] = structural_hash(cir_record)
    return ValidationDecision(status=status, train_eligibility=train_eligibility, record=output_record)


def _manifest(
    request: ValidationRequest,
    decisions: Iterable[ValidationDecision],
) -> dict[str, object]:
    decisions = list(decisions)
    status_counts = Counter(item.status for item in decisions)
    tier_counts = Counter(str(item.record.get("correction_tier")) for item in decisions)
    bucket_counts = Counter(str(item.record.get("difficulty_bucket")) for item in decisions)
    reject_counts = Counter(
        reason
        for item in decisions
        for reason in item.record.get("validation_report", {}).get("reject_reasons", [])
    )
    critic_verdicts = Counter(
        str(item.record.get("validation_report", {}).get("critic_verdict", ""))
        for item in decisions
    )
    score_histogram = Counter(
        int(item.record.get("validation_report", {}).get("recoverability_score", 0)) // 10 * 10
        for item in decisions
    )
    return {
        "validator_stack_version": request.validator_stack_version,
        "total_input_count": len(decisions),
        "accepted_count": status_counts["accepted"],
        "manual_review_count": status_counts["manual_review"],
        "rejected_count": status_counts["rejected"],
        "counts_by_correction_tier": dict(sorted(tier_counts.items())),
        "counts_by_difficulty_bucket": dict(sorted(bucket_counts.items())),
        "reject_counts_by_taxonomy_code": dict(sorted(reject_counts.items())),
        "critic_verdict_distribution": dict(sorted(critic_verdicts.items())),
        "recoverability_score_histogram": {str(key): value for key, value in sorted(score_histogram.items())},
    }


def validate_and_pack(request: ValidationRequest) -> ValidationRunResult:
    input_records = read_jsonl(request.input_jsonl)
    cir_index, duplicate_sample_ids = _cir_index(request)

    filtered_records = [
        sample
        for sample in input_records
        if request.difficulty_bucket is None or sample.get("difficulty_bucket") == request.difficulty_bucket
    ]
    print(
        "[validator] start: "
        f"input={len(input_records)} filtered={len(filtered_records)} backend={request.critic_backend} "
        f"workers={request.critic_workers} critic_enabled={request.enable_critic}",
        flush=True,
    )

    should_parallelize = request.enable_critic and request.critic_backend == "openai" and request.critic_workers > 1
    worker_count = max(1, min(request.critic_workers, len(filtered_records))) if should_parallelize else 1

    decisions: list[ValidationDecision]
    if worker_count == 1:
        decisions = []
        progress_stride = max(1, len(filtered_records) // 20) if filtered_records else 1
        for index, sample in enumerate(filtered_records, start=1):
            decisions.append(
                validate_sample(
                    sample,
                    request,
                    cir_index=cir_index,
                    duplicate_sample_ids=duplicate_sample_ids,
                )
            )
            if index == len(filtered_records) or index % progress_stride == 0:
                print(
                    f"[validator] progress: {index}/{len(filtered_records)} samples validated",
                    flush=True,
                )
    else:
        print(
            f"[validator] parallel semantic critic enabled: workers={worker_count}, samples={len(filtered_records)}",
            flush=True,
        )
        progress_stride = max(1, len(filtered_records) // 20)
        decision_slots: list[ValidationDecision | None] = [None] * len(filtered_records)
        with ThreadPoolExecutor(max_workers=worker_count, thread_name_prefix="sgv7-critic") as executor:
            future_index = {
                executor.submit(
                    validate_sample,
                    sample,
                    request,
                    cir_index=cir_index,
                    duplicate_sample_ids=duplicate_sample_ids,
                ): index
                for index, sample in enumerate(filtered_records)
            }
            completed = 0
            for future in as_completed(future_index):
                index = future_index[future]
                decision_slots[index] = future.result()
                completed += 1
                if completed == len(filtered_records) or completed % progress_stride == 0:
                    print(
                        f"[validator] progress: {completed}/{len(filtered_records)} samples validated",
                        flush=True,
                    )
        decisions = [item for item in decision_slots if item is not None]
    print(
        f"[validator] done: accepted={sum(1 for item in decisions if item.status == 'accepted')} "
        f"review={sum(1 for item in decisions if item.status == 'manual_review')} "
        f"rejected={sum(1 for item in decisions if item.status == 'rejected')}",
        flush=True,
    )

    accepted_records = [item.record for item in decisions if item.status == "accepted"]
    review_records = [item.record for item in decisions if item.status == "manual_review"]
    rejected_records = [item.record for item in decisions if item.status == "rejected"]

    accepted_records.sort(key=lambda row: (row["difficulty_bucket"], row["sample_id"], row["train_eligibility"]))
    review_records.sort(key=lambda row: (row["difficulty_bucket"], row["sample_id"], row["train_eligibility"]))
    rejected_records.sort(key=lambda row: (row["sample_id"], row["validation_report"]["reject_reasons"]))

    manifest = _manifest(request, decisions)
    write_jsonl(accepted_records, request.accepted_jsonl)
    write_jsonl(review_records, request.review_jsonl)
    write_jsonl(rejected_records, request.rejected_jsonl)
    write_json(manifest, request.manifest_json)
    return ValidationRunResult(
        accepted_records=accepted_records,
        review_records=review_records,
        rejected_records=rejected_records,
        manifest=manifest,
    )
