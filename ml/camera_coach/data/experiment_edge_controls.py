"""Finite actual-record edge experiment using the existing v2 trainer/resume.

This compares a small research fit to exact ROI geometry and a train-majority
baseline. It does not calibrate confidence, export Core ML or admit runtime use.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import signal
import time

import torch

from .training_records import (GEOMETRIC_LABEL_SCHEMA_VERSION, load_records, stack_inputs,
    stack_masks, stack_targets, intent_head_mask, edge_measurement)
from ..models.set_composition_net_v2 import SETCompositionNetV2CandidateB, SETCompositionNetV2Manifest
from ..losses import LossConfig, compute_multitask_loss
from ..trainer_records import RecordsTrainingConfig, train_one_seed, _configure_records_runtime, _environment_receipt_v2

ROOT = Path(__file__).resolve().parents[3]
SEED = 20260916
FLAGS = dict(research_only=True, human_gold=False, release_admissible=False, training_ready=False)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    with Path(path).open("x") as stream:
        json.dump(value, stream, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")


def load_intake(intake):
    receipt = json.loads((intake/"receipt.json").read_text())
    if receipt["schema_id"] != "camera-edge-controls-v1" or any(receipt.get(k) is not v for k,v in FLAGS.items()):
        raise ValueError("Not the admitted research measurement intake")
    for name in ("records", "lineage", "split-assessment"):
        path = intake / (name + (".json" if name == "split-assessment" else ".jsonl"))
        if sha(path) != receipt[name.replace("-", "_") + "_sha256"]:
            raise ValueError("Intake evidence hash mismatch: " + name)
    records = load_records(intake/"records.jsonl", receipt["records_sha256"], admission="non_admitted_research")
    if len(records) != receipt["records"] or any(r.schema_version != GEOMETRIC_LABEL_SCHEMA_VERSION or r.split not in ("train","validation") for r in records):
        raise ValueError("Invalid/locked/empty experiment records")
    by_split = {split:[r for r in records if r.split == split] for split in ("train","validation")}
    if {r.source_family_id for r in by_split["train"]} & {r.source_family_id for r in by_split["validation"]}:
        raise ValueError("Source/derivative group leakage")
    for split, values in by_split.items():
        if {int(r.targets["issue_logits"][0]) for r in values} != {0,1}:
            raise ValueError("Both measured classes required in actual " + split)
        if any(int(r.masks["issue_logits"].sum()) != 1 or any(mask.any() for head,mask in r.masks.items() if head != "issue_logits") for r in values):
            raise ValueError("Unsupported labels reached an actual model mask")
    return receipt, records, by_split


def metrics(records, scores):
    if not records or len(records) != len(scores):
        raise ValueError("Empty or mismatched metric input")
    actual = [int(r.targets["issue_logits"][0]) for r in records]
    predicted = [int(score >= .5) for score in scores]
    count = Counter((a,p) for a,p in zip(actual,predicted))
    tn,fp,fn,tp = (count[(0,0)],count[(0,1)],count[(1,0)],count[(1,1)])
    if not (tn+fp) or not (tp+fn):
        raise ValueError("Undefined class metric")
    return dict(n=len(records), threshold=.5, confusion=dict(tn=tn,fp=fp,fn=fn,tp=tp),
        accuracy=(tp+tn)/len(records), balanced_accuracy=.5*(tp/(tp+fn)+tn/(tn+fp)),
        false_positive_on_geometric_noop=fp/(fp+tn), false_negative_on_edge=fn/(fn+tp),
        sigmoid_score_squared_error=sum((score-label)**2 for score,label in zip(scores,actual))/len(records))


def neural_scores(model, records, contract):
    model.eval()
    scores = []
    with torch.no_grad():
        for start in range(0,len(records),8):
            batch = records[start:start+8]
            inputs = stack_inputs(batch,contract)
            if not torch.allclose(inputs.roi_normalized_xywh,torch.tensor([r.roi for r in batch]),atol=1e-7,rtol=0):
                raise ValueError("Runtime preprocessing changed normalized ROI coordinates unexpectedly")
            if inputs.intent_features.any():
                raise ValueError("Runtime preprocessing fabricated known intent")
            # roi_mask is a spatial raster, not an availability bit. Validate
            # both its positive region and the zeros outside using pixel centers.
            mask_height, mask_width = inputs.roi_mask.shape[1:3]
            xs = (torch.arange(mask_width,dtype=torch.float32)+.5)/mask_width
            ys = (torch.arange(mask_height,dtype=torch.float32)+.5)/mask_height
            expected_masks = []
            for record in batch:
                x,y,width,height = record.roi
                expected_masks.append(((ys[:,None]>=y) & (ys[:,None]<y+height) &
                    (xs[None,:]>=x) & (xs[None,:]<x+width)).float())
            if not torch.equal(inputs.roi_mask[:,:,:,0],torch.stack(expected_masks)):
                raise ValueError("Runtime ROI mask differs from independent pixel-center rasterization")
            scores.extend(model(inputs)["issue_logits"][:,0].sigmoid().tolist())
    return scores


def preflight(intake, out):
    if out.exists():
        raise ValueError("Do not overwrite an experiment artifact")
    started = time.monotonic()
    receipt, records, splits = load_intake(intake)
    torch.set_num_threads(1)
    torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED)
    contract = SETCompositionNetV2Manifest.load()
    model = SETCompositionNetV2CandidateB(contract).cpu()
    baselines = {}
    train_counts = Counter(int(r.targets["issue_logits"][0]) for r in splits["train"])
    majority = int(train_counts[1] > train_counts[0])
    for split,values in splits.items():
        exact = [edge_measurement(r.roi) for r in values]
        if None in exact:
            raise ValueError("An uncertain margin was silently labeled")
        baselines[split] = dict(majority=metrics(values,[float(majority)]*len(values)),
            exact_roi_geometry=metrics(values,exact), random_candidate=metrics(values,neural_scores(model,values,contract)))
        if baselines[split]["exact_roi_geometry"]["accuracy"] != 1:
            raise ValueError("Producer label and exact geometry baseline disagree")
    pair = [next(r for r in splits["train"] if int(r.targets["issue_logits"][0])==label) for label in (0,1)]
    model.train()
    model.zero_grad(set_to_none=True)
    inputs = stack_inputs(pair,contract)
    outputs = model(inputs)
    masks = stack_masks(pair)
    for name in masks:
        outputs[name].retain_grad()
    loss = compute_multitask_loss(outputs,stack_targets(pair),masks=masks,intent_mask=intent_head_mask(pair,contract),
        config=LossConfig.from_file(ROOT/"ml/camera_coach/configs/loss_weights.json"))
    loss.total.backward()
    gradient_l1 = {}
    for name,mask in masks.items():
        gradient = outputs[name].grad
        if gradient is None or not torch.isfinite(gradient).all():
            raise ValueError("Missing/nonfinite output gradient: " + name)
        if mask.shape != gradient.shape:
            mask = mask.expand_as(gradient)
        if (gradient[mask==0] != 0).any():
            raise ValueError("Masked component received a gradient: " + name)
        gradient_l1[name] = float(gradient.abs().sum())
    if gradient_l1["issue_logits"] <= 0 or not torch.isfinite(loss.total) or any(v != 0 for k,v in gradient_l1.items() if k != "issue_logits"):
        raise ValueError("Actual edge-only backward did not reach the intended component")
    result = dict(schema_id="camera-edge-preflight-v1", status="pass", **FLAGS,
        intake_receipt_sha256=sha(intake/"receipt.json"), records_sha256=receipt["records_sha256"], seed=SEED,
        records=len(records), split_counts={k:len(v) for k,v in splits.items()},
        groups={k:len({r.source_family_id for r in v}) for k,v in splits.items()},
        coverage={k:dict(Counter(int(r.targets["issue_logits"][0]) for r in v)) for k,v in splits.items()},
        baselines=baselines, backward_record_ids=[r.record_id for r in pair],
        output_gradient_l1=gradient_l1, issue_component_gradient_l1=outputs["issue_logits"].grad.abs().sum(0).tolist(),
        optimizer_steps=0, masked_gradient_violations=0, preprocessing_roi_parity_records=len(records),
        all_intents_unknown=True, spatial_roi_raster_parity_records=len(records),
        preprocessing_contract_sha256=sha(ROOT/"ml/camera_coach/contracts/set_composition_net_v2.json"),
        resize_geometry="independent_scale_to_target", elapsed_seconds=time.monotonic()-started,
        scope="Actual pixels/typed masks/preprocessing and bounded backward. Conditional edge extremes only; no calibrated probability or runtime admission.")
    out.mkdir(parents=True,exist_ok=False)
    write(out/"receipt.json",result)
    return result


def _timeout(signum, frame):
    raise TimeoutError("Declared 300-second CPU fit budget reached; durable completed epochs retained")


def fit(intake,out,preflight_dir):
    if out.exists():
        raise ValueError("Do not overwrite an experiment run")
    receipt, records, splits = load_intake(intake)
    approved = json.loads((preflight_dir/"receipt.json").read_text())
    if approved.get("status") != "pass" or approved.get("records_sha256") != receipt["records_sha256"] or approved.get("intake_receipt_sha256") != sha(intake/"receipt.json"):
        raise ValueError("Matching actual-record preflight required before fit")
    config_raw = json.loads((ROOT/"ml/camera_coach/configs/production_records_smoke.json").read_text())
    config_raw.update(seed=SEED,seeds=[SEED],output_root=str(out),resume_from=None)
    config_raw["dataset"].update(path=str(intake/"records.jsonl"),sha256=receipt["records_sha256"],admission="non_admitted_research")
    config_raw["augmentation"]["horizontal_flip"] = False
    # Four full epochs keep the measured real-record preprocessing/forward cost
    # inside the declared five-minute CPU budget; this is not validation tuning.
    config_raw["training"].update(epochs=4,batch_size=8,early_stop_patience=4,trained_heads=["issue_logits"])
    config = RecordsTrainingConfig.from_mapping(config_raw)
    runtime = _configure_records_runtime(config)
    torch.set_num_threads(1)
    contract = SETCompositionNetV2Manifest.load()
    loss = LossConfig.from_file(ROOT/"ml/camera_coach/configs/loss_weights.json")
    out.mkdir(parents=True,exist_ok=False)
    write(out/"config.json",config.as_mapping())
    write(out/"environment.json",_environment_receipt_v2(config,runtime))
    phase1, resumed = out/"interrupted-after-epoch2",out/"resumed"
    phase1.mkdir();resumed.mkdir()
    started = time.monotonic()
    previous_handler = signal.signal(signal.SIGALRM,_timeout)
    signal.alarm(300)
    try:
        first = train_one_seed(config,seed=SEED,run_dir=phase1,contract=contract,loss_config=loss,
            records=records,interrupt_after_epoch=2,argv=["experiment_edge_controls","fit","interrupt_after_epoch=2"])
        write(phase1/"result.json",first)
        checkpoint = Path(first["checkpoint_path"])
        checkpoint_sha = sha(checkpoint)
        continued = train_one_seed(config,seed=SEED,run_dir=resumed,contract=contract,loss_config=loss,
            records=records,resume_from=checkpoint,argv=["experiment_edge_controls","fit","resume"])
        write(resumed/"result.json",continued)
        if continued["start_epoch"] != 3 or continued["history"][:2] != first["history"] or sha(checkpoint) != checkpoint_sha:
            raise ValueError("Real-data resume lost or changed completed epochs")
        state = torch.load(continued["checkpoint_path"],map_location="cpu",weights_only=False)
        model = SETCompositionNetV2CandidateB(contract).cpu()
        model.load_state_dict(state["best"]["state"])
        final_metrics = {split:metrics(values,neural_scores(model,values,contract)) for split,values in splits.items()}
        result = dict(schema_id="camera-edge-learning-experiment-v1",status="completed",**FLAGS,seed=SEED,
            dataset_receipt_sha256=sha(intake/"receipt.json"),records_sha256=receipt["records_sha256"],
            preflight_receipt_sha256=sha(preflight_dir/"receipt.json"),initialization="random; no historical research checkpoint loaded",
            active_component="issue_logits[subject_too_close_to_edge] only; seven other components and all other heads unsupported",
            finite_budget=dict(api_cost_usd=0,cpu_threads=1,time_limit_seconds=300,planned_epochs=4,mps_used=False),
            interrupted_after_epoch=2,resumed_start_epoch=continued["start_epoch"],completed_epochs=continued["final_epoch"],
            retained_initial_history=True,interrupt_checkpoint_sha256=checkpoint_sha,selected_epoch=continued["selected_epoch"],
            selected_validation_loss=continued["selected_validation_loss"],history=continued["history"],
            checkpoint_path=continued["checkpoint_path"],checkpoint_sha256=sha(continued["checkpoint_path"]),
            model_state_sha256=continued["model_state_sha256"],neural_metrics=final_metrics,baselines=approved["baselines"],
            elapsed_seconds=time.monotonic()-started,python=platform.python_version(),torch=torch.__version__,
            inference="Exact ROI geometry is already sufficient for this relation. This fit is learning/preprocessing/resume evidence and cannot justify replacing that baseline or enabling the candidate in production.",
            source_code_sha256={str(path.relative_to(ROOT)):sha(path) for path in (
                Path(__file__),ROOT/"ml/camera_coach/data/training_records.py",ROOT/"ml/camera_coach/trainer_records.py",
                ROOT/"ml/camera_coach/models/set_composition_net_v2.py",ROOT/"ml/camera_coach/losses.py")})
        write(out/"receipt.json",result)
        return result
    except BaseException as exc:
        write(out/"failure.json",dict(status="incomplete",error=type(exc).__name__,message=str(exc),elapsed_seconds=time.monotonic()-started,**FLAGS))
        raise
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM,previous_handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode",choices=("preflight","fit"))
    parser.add_argument("--intake",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--preflight",type=Path)
    args = parser.parse_args()
    if args.mode == "fit" and args.preflight is None:
        parser.error("fit requires --preflight")
    result = preflight(args.intake,args.out) if args.mode == "preflight" else fit(args.intake,args.out,args.preflight)
    print(json.dumps({k:result[k] for k in ("status","elapsed_seconds")},sort_keys=True))


if __name__ == "__main__":
    main()
