from __future__ import annotations

from collections import Counter, defaultdict
import hashlib
import re
from typing import Any

from .expectations import normalize_source_text


_WS_RE = re.compile(r"\s+", flags=re.UNICODE)


def _bucket_marked_objects(value: int) -> str:
    if value <= 0:
        return "0"
    if value == 1:
        return "1"
    return "2p"


def _bucket_beats(value: int) -> str:
    if value <= 0:
        return "0"
    if value == 1:
        return "1"
    if value == 2:
        return "2"
    return "3p"


def _bucket_actors(value: int) -> str:
    if value <= 0:
        return "0"
    if value == 1:
        return "1"
    if value == 2:
        return "2"
    return "3p"


def normalize_source_template(source: str, marked_objects: list[dict[str, Any]]) -> str:
    value = normalize_source_text(source)
    for marker in marked_objects:
        name = str(marker.get("name_normalized") or marker.get("name") or "").strip().lower()
        if not name:
            continue
        value = value.replace(name, "<marked_object>")
    for ordinal in ("первый", "второй", "третий"):
        value = value.replace(ordinal, "<ordinal_ref>")
    value = re.sub(r"\b\d+\b", "<actor_count>", value)
    return _WS_RE.sub(" ", value).strip()


def build_failure_signature(record: dict[str, Any]) -> str:
    failure_taxonomy = record.get("failure_taxonomy", {})
    dominant = str(failure_taxonomy.get("dominant", "policy_acceptability_drift"))
    final_decision = str(record.get("final_decision", ""))
    expectations = record.get("source_expectations", {})
    expected_marked = int(expectations.get("expected_marked_object_mentions", 0))
    unsupported_action_present = bool(expectations.get("unsupported_action_present", False))
    normalized_source = str(expectations.get("normalized_source", ""))

    ordinal_flag = int(any(token in normalized_source for token in ("перв", "втор", "трет")))
    same_type_flag = int(bool(record.get("same_type_marker_flag", False)))
    described_action_flag = int(unsupported_action_present)

    final_script = {}
    final_result = record.get("final_result")
    if isinstance(final_result, dict):
        script = final_result.get("script_json")
        if isinstance(script, dict):
            final_script = script
    beat_count = len(final_script.get("beats", [])) if isinstance(final_script.get("beats"), list) else 0
    actor_count = len(final_script.get("actors", [])) if isinstance(final_script.get("actors"), list) else 0

    privacy_status = str(record.get("privacy_status", "clear"))
    return (
        f"ffs_v1:{dominant}|{final_decision}|mo{_bucket_marked_objects(expected_marked)}|"
        f"stm{same_type_flag}|ord{ordinal_flag}|da{described_action_flag}|"
        f"beat{_bucket_beats(beat_count)}|act{_bucket_actors(actor_count)}|p{privacy_status}"
    )


def build_cluster_id(*, failure_signature: str, normalized_source_template: str) -> str:
    payload = (failure_signature + "|" + normalized_source_template).encode("utf-8")
    return "rfc_" + hashlib.sha256(payload).hexdigest()[:8]


def build_cluster_manifest(failures: list[dict[str, Any]]) -> dict[str, Any]:
    by_cluster: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in failures:
        cluster = row.get("cluster")
        if not isinstance(cluster, dict):
            continue
        cluster_id = str(cluster.get("cluster_id", "")).strip()
        if not cluster_id:
            continue
        by_cluster[cluster_id].append(row)

    clusters: list[dict[str, Any]] = []
    for cluster_id, rows in sorted(by_cluster.items()):
        labels = Counter(str(row.get("failure_taxonomy", {}).get("dominant", "")) for row in rows)
        tiers = Counter(str(row.get("correction_tier", "")) for row in rows)
        statuses = Counter(str(row.get("review_status", "")) for row in rows)
        first_seen = min(str(row.get("timestamp", "")) for row in rows)
        last_seen = max(str(row.get("timestamp", "")) for row in rows)
        clusters.append(
            {
                "cluster_id": cluster_id,
                "failure_signature": str(rows[0].get("cluster", {}).get("failure_signature", "")),
                "dominant_label": labels.most_common(1)[0][0] if labels else "",
                "case_count": len(rows),
                "first_seen_at": first_seen,
                "last_seen_at": last_seen,
                "example_failure_ids": [str(row.get("failure_id", "")) for row in rows[:5]],
                "review_queue_size": statuses.get("pending", 0),
                "promotion_counts_by_tier": dict(sorted(tiers.items())),
            }
        )

    top_three = sorted(clusters, key=lambda item: (-int(item["case_count"]), str(item["cluster_id"])))[:3]
    return {
        "cluster_version": "runtime_cluster_v1",
        "cluster_count": len(clusters),
        "clusters": clusters,
        "top_three_cluster_ids": [str(item["cluster_id"]) for item in top_three],
    }

