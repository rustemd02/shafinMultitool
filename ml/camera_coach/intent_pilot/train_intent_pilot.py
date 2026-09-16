#!/usr/bin/env python3
"""Train the pilot intent model (variant A feasibility, R15 groundwork).

Deterministic softmax regression on the pilot intent dataset (numpy only).
Reports holdout accuracy/per-class metrics and saves the model + metrics.

Research_only pilot: the result quantifies feature separability for the
intent-source decision; it is NOT a production intent model and must not be
bundled or promoted.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

SEED = 20260912


def load_split(path: Path) -> tuple[np.ndarray, np.ndarray, list[str], list[dict]]:
    features: list[list[float]] = []
    labels: list[int] = []
    rows: list[dict] = []
    class_index = {"good": 0, "mixed": 1, "bad": 2}
    feature_names: list[str] | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        names = sorted(row["provenance"]["feature_names"])
        if feature_names is None:
            feature_names = names
        features.append([float(row["features"].get(name, 0.0)) for name in names])
        labels.append(class_index[row["label"]])
        rows.append(row)
    return np.array(features, dtype=float), np.array(labels), feature_names or [], rows


def softmax(z: np.ndarray) -> np.ndarray:
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


def fit(X: np.ndarray, y: np.ndarray, lam: float, iters: int, lr: float) -> tuple[np.ndarray, np.ndarray]:
    n, d = X.shape
    k = 3
    W = np.zeros((d, k))
    b = np.zeros(k)
    Y = np.zeros((n, k))
    for c in range(k):
        Y[y == c, c] = 1.0
    for _ in range(iters):
        P = softmax(X @ W + b)
        G = (P - Y) / n
        W -= lr * (X.T @ G + lam * W)
        b -= lr * G.sum(axis=0)
    return W, b


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--lam", type=float, default=1.0)
    parser.add_argument("--iters", type=int, default=800)
    parser.add_argument("--lr", type=float, default=0.5)
    parser.add_argument("--repeats", type=int, default=5, help="extra stratified re-splits for variance")
    parser.add_argument("--seed", type=int, default=SEED)
    args = parser.parse_args()

    train_path = args.dataset_dir / "intent-dataset-train.jsonl"
    test_path = args.dataset_dir / "intent-dataset-test.jsonl"
    X_train, y_train, feature_names, _ = load_split(train_path)
    X_test, y_test, _, _ = load_split(test_path)
    mu, sd = X_train.mean(axis=0), X_train.std(axis=0) + 1e-9
    Xtr = (X_train - mu) / sd
    Xte = (X_test - mu) / sd

    W, b = fit(Xtr, y_train, args.lam, args.iters, args.lr)
    prob = softmax(Xte @ W + b)
    pred = prob.argmax(axis=1)
    accuracy = float((pred == y_test).mean())
    per_class = {}
    for c, name in ((0, "good"), (1, "mixed"), (2, "bad")):
        mask = y_test == c
        predicted = pred == c
        tp = int((mask & predicted).sum())
        precision = tp / int(predicted.sum()) if predicted.sum() else 0.0
        recall = tp / int(mask.sum()) if mask.sum() else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        per_class[name] = {"support": int(mask.sum()), "precision": round(precision, 3),
                           "recall": round(recall, 3), "f1": round(f1, 3)}
    confusion = {"true_pred": {f"{t}->{p}": int(((y_test == t) & (pred == p)).sum())
                               for t in range(3) for p in range(3)}}

    variance_runs = []
    rng = np.random.default_rng(args.seed)
    all_idx = np.arange(len(X_train) + len(X_test))
    y_all = np.concatenate([y_train, y_test])
    X_all = np.concatenate([X_train, X_test])
    for repeat in range(args.repeats):
        shuffle = rng.permutation(len(y_all))
        cut = int(len(y_all) * 0.7)
        tr = shuffle[:cut]
        te = shuffle[cut:]
        mu_r = X_all[tr].mean(axis=0)
        sd_r = X_all[tr].std(axis=0) + 1e-9
        Wr, br = fit((X_all[tr] - mu_r) / sd_r, y_all[tr], args.lam, args.iters, args.lr)
        P = softmax((X_all[te] - mu_r) / sd_r @ Wr + br)
        variance_runs.append(float(((P.argmax(axis=1)) == y_all[te]).mean()))

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    metrics = {
        "model_id": "camera-intent-pilot-v1",
        "research_only": True,
        "human_gold": False,
        "note": "feature-separability pilot; not a production intent model; must not be bundled",
        "trained_at": now,
        "seed": args.seed,
        "hyperparameters": {"lam": args.lam, "iters": args.iters, "lr": args.lr},
        "train_count": int(len(y_train)),
        "test_count": int(len(y_test)),
        "test_accuracy": round(accuracy, 4),
        "per_class": per_class,
        "confusion": confusion,
        "resplit_variance": {"runs": args.repeats, "accuracies": [round(a, 4) for a in variance_runs],
                             "mean": round(float(np.mean(variance_runs)), 4)},
        "feature_names": feature_names,
    }
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "intent-pilot-metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    np.savez(
        args.out_dir / "intent-pilot-model.npz",
        W=W, b=b, mu=mu, sd=sd,
        feature_names=np.array(feature_names),
    )
    print(f"test_accuracy={accuracy:.4f} per_class={per_class}")
    print(f"resplit variance mean over {args.repeats} runs: {np.mean(variance_runs):.4f}")
    print(f"WROTE {args.out_dir / 'intent-pilot-metrics.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
