"""Evidence of effective direct supervision, never a model-quality admission.

Counts describe successful train optimizer steps, including repeated sampling.
Missing legacy evidence is unknown; an aggregate head flag is not evidence for
its individual components. Ranking does not establish absolute good-frame labels.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence
import copy
import hashlib
import json

import torch

from .losses import DIRECT_LOSS_HEADS, merge_intent_supervision_mask

SCHEMA_ID = "camera-component-supervision-v1"
CHECKPOINT_VERSION = "camera_training_checkpoint.v2"
LEGACY_CHECKPOINT_VERSION = "camera_training_checkpoint.v1"
COUNT_FIELDS = ("observations", "targets_equal_one", "targets_equal_zero", "other_targets", "optimizer_steps")


class SupervisionError(ValueError):
    pass


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
        ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def component_names(contract):
    return {head: list(contract.output_head_specs[head].get("ordered_names", [head]))
            for head in DIRECT_LOSS_HEADS}


def _valid_hash(value):
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _count(value, label):
    if type(value) is not int or value < 0:
        raise SupervisionError(f"{label} must be a non-negative integer")
    return value


def records_fingerprint(records):
    """Bind the actual supplied targets/masks, separately from the declared file."""
    return canonical_hash([dict(record_id=r.record_id, split=r.split,
        source_family_id=r.source_family_id,
        targets={k:v.detach().cpu().tolist() for k,v in r.targets.items()},
        masks={k:v.detach().cpu().tolist() for k,v in r.masks.items()},
        intent_known=r.intent_known, intent_styles=r.intent_styles, roi=r.roi,
        pixels_sha256=hashlib.sha256(r.pixels.detach().cpu().contiguous().numpy().tobytes()).hexdigest(),
        ranking=list(r.ranking))
        for r in sorted(records, key=lambda r:r.record_id)])


def new_supervision(contract, source, *, legacy_unknown=False):
    names = component_names(contract)
    result = dict(schema_id=SCHEMA_ID, source=dict(source), legacy_prefix_unknown=legacy_unknown,
        successful_optimizer_steps=0, processed_train_observations=0, ranking_pairs=0,
        processed_batches_sha256=canonical_hash(dict(schema_id=SCHEMA_ID, source=dict(source))),
        heads={head:dict(ordered_names=ordered, **{key:[0]*len(ordered) for key in COUNT_FIELDS})
               for head,ordered in names.items()})
    return validate_supervision(result, contract)


def validate_supervision(value, contract, *, source=None):
    required = {"schema_id", "source", "legacy_prefix_unknown", "successful_optimizer_steps",
        "processed_train_observations", "ranking_pairs", "processed_batches_sha256", "heads"}
    if not isinstance(value, Mapping) or set(value) != required or value.get("schema_id") != SCHEMA_ID:
        raise SupervisionError("component supervision schema/keys mismatch")
    if type(value["legacy_prefix_unknown"]) is not bool or not isinstance(value["source"], Mapping):
        raise SupervisionError("invalid component supervision source/legacy flag")
    if not value["source"] or any(not _valid_hash(v) for v in value["source"].values()):
        raise SupervisionError("component supervision source must contain hash identities")
    if source is not None and dict(value["source"]) != dict(source):
        raise SupervisionError("component supervision source does not match this run")
    if not _valid_hash(value["processed_batches_sha256"]):
        raise SupervisionError("invalid processed-batch digest")
    steps = _count(value["successful_optimizer_steps"], "successful optimizer steps")
    observations = _count(value["processed_train_observations"], "processed train observations")
    ranking = _count(value["ranking_pairs"], "ranking pairs")
    if (steps == 0) != (observations == 0) or (ranking and not steps):
        raise SupervisionError("optimizer steps and processed observations disagree")
    names = component_names(contract)
    if not isinstance(value["heads"], Mapping) or set(value["heads"]) != set(names):
        raise SupervisionError("component supervision head catalog mismatch")
    for head, ordered in names.items():
        entry = value["heads"][head]
        if not isinstance(entry, Mapping) or set(entry) != {"ordered_names", *COUNT_FIELDS} or entry["ordered_names"] != ordered:
            raise SupervisionError(f"{head}: component order/keys mismatch")
        for key in COUNT_FIELDS:
            if not isinstance(entry[key], list) or len(entry[key]) != len(ordered):
                raise SupervisionError(f"{head}.{key}: component width mismatch")
            for count in entry[key]:
                _count(count, f"{head}.{key}")
        for index in range(len(ordered)):
            n = entry["observations"][index]
            k = entry["optimizer_steps"][index]
            if (n > observations or k > steps or k > n or (n == 0) != (k == 0)
                    or n != sum(entry[key][index] for key in ("targets_equal_one", "targets_equal_zero", "other_targets"))):
                raise SupervisionError(f"{head}.{ordered[index]}: inconsistent component counts")
    return copy.deepcopy(dict(value))


def batch_supervision(outputs, targets, masks, intent_mask, loss_config, record_ids, *, ranking_pairs=0):
    """Read the same prepared tensors/masks as the loss; commit only after step()."""
    batch_size = len(record_ids)
    active = merge_intent_supervision_mask(outputs, masks, intent_mask, batch_size=batch_size)
    heads = {}
    digest_rows = {}
    for head in DIRECT_LOSS_HEADS:
        prediction, target = outputs[head], targets[head]
        mask = active.get(head)
        if mask is None:
            raise SupervisionError(f"{head}: explicit supervision mask required")
        if not torch.isfinite(mask).all() or torch.any((mask != 0) & (mask != 1)):
            raise SupervisionError(f"{head}: invalid effective mask")
        mask = mask.detach().to(device="cpu", dtype=torch.bool)
        target = target.detach().cpu()
        if head == "scene_class_logits":
            # A categorical target supervises every softmax logit, while counts
            # preserve which classes actually appeared as positive targets.
            target = torch.nn.functional.one_hot(target.reshape(-1).long(), prediction.shape[1]).float()
            mask = mask.reshape(batch_size, 1).expand_as(target)
        else:
            if mask.ndim == 1:
                mask = mask.reshape(batch_size, 1)
            mask = mask.expand_as(target)
        if getattr(loss_config.weights, head) <= 0:
            mask = torch.zeros_like(mask)
        if head in ("issue_logits", "action_utility_logits"):
            balancing = loss_config.focal_alpha*target + (1-loss_config.focal_alpha)*(1-target)
            mask = mask & (balancing > 0)
        positive = mask & (target == 1)
        negative = mask & (target == 0)
        other = mask & ~positive & ~negative
        heads[head] = dict(observations=mask.sum(0).tolist(), targets_equal_one=positive.sum(0).tolist(),
            targets_equal_zero=negative.sum(0).tolist(), other_targets=other.sum(0).tolist(),
            optimizer_steps=mask.any(0).long().tolist())
        digest_rows[head] = dict(targets=target.tolist(), effective_masks=mask.long().tolist())
    has_supervision = any(any(v["observations"]) for v in heads.values()) or ranking_pairs > 0
    return dict(heads=heads, records=batch_size, ranking_pairs=ranking_pairs, has_supervision=has_supervision,
        digest=canonical_hash(dict(record_ids=list(record_ids), heads=digest_rows, ranking_pairs=ranking_pairs)))


def record_successful_step(state, delta):
    if not delta["has_supervision"]:
        raise SupervisionError("a fully masked batch cannot count as a supervised optimizer step")
    state["successful_optimizer_steps"] += 1
    state["processed_train_observations"] += delta["records"]
    state["ranking_pairs"] += delta["ranking_pairs"]
    state["processed_batches_sha256"] = canonical_hash([state["processed_batches_sha256"], delta["digest"]])
    for head, fields in delta["heads"].items():
        for field in COUNT_FIELDS:
            state["heads"][head][field] = [a+b for a,b in zip(state["heads"][head][field], fields[field])]


def trained_head_mask(state):
    """Deprecated aggregate means any observed component, never the whole head."""
    return {head:any(entry["observations"]) for head,entry in state["heads"].items()}


def checkpoint_supervision(payload, contract, *, source=None, selected_best=False):
    node = payload.get("best") if selected_best and isinstance(payload.get("best"), Mapping) else payload
    value = node.get("component_supervision")
    if value is not None:
        return validate_supervision(value, contract, source=source)
    if payload.get("checkpoint_version") == CHECKPOINT_VERSION:
        raise SupervisionError("v2 checkpoint is missing required component supervision")
    unknown_source = source or {"legacy_metadata_sha256":canonical_hash({
        "checkpoint_version":payload.get("checkpoint_version"),
        "config_sha256":payload.get("config_sha256"), "epoch":node.get("epoch"),
        "aggregate_flags_ignored":payload.get("trained_head_mask", payload.get("trainable_heads"))})}
    return new_supervision(contract, unknown_source, legacy_unknown=True)


def export_metadata(state, contract, *, required_components=None):
    state = validate_supervision(state, contract)
    statuses = {head:["observed_direct_supervision" if n else
        ("unknown" if state["legacy_prefix_unknown"] else "no_observed_direct_supervision")
        for n in entry["observations"]] for head,entry in state["heads"].items()}
    missing = []
    for head, requested in (required_components or {}).items():
        names = component_names(contract).get(head)
        if names is None or not isinstance(requested, Sequence) or isinstance(requested, str) or not requested:
            raise SupervisionError("required components must name nonempty canonical component lists")
        for name in requested:
            if name not in names:
                raise SupervisionError(f"unknown required component {head}.{name}")
            if statuses[head][names.index(name)] != "observed_direct_supervision":
                missing.append(f"{head}.{name}")
    if missing:
        raise SupervisionError("required components have unknown/missing supervision: " + ", ".join(missing))
    return dict(schema_id="camera-component-export-evidence-v1", component_supervision=state,
        component_status=statuses, aggregate_trained_head_mask=trained_head_mask(state),
        required_components=dict(required_components or {}), release_admissible=False,
        scope="Direct supervision evidence only; no quality, rights, calibration or runtime admission")
