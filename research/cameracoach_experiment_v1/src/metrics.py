"""Explicit diagnostic metrics. No risk certificates from reused development data."""
from __future__ import annotations
import math
from typing import Sequence
import numpy as np
from scipy.stats import beta


def expected_calibration_error(confidence: Sequence[float], correct: Sequence[int], bins: int = 10) -> dict:
    c = np.asarray(confidence, dtype=float)
    y = np.asarray(correct, dtype=float)
    if c.ndim != 1 or y.shape != c.shape or not len(c):
        raise ValueError('Expected nonempty equal-length one-dimensional arrays')
    if isinstance(bins,bool) or not isinstance(bins,int) or bins < 1 or not np.all(np.isfinite(c)) or not np.all((c >= 0) & (c <= 1)):
        raise ValueError('Confidence must be finite in [0,1], bins >= 1')
    if not np.all((y == 0) | (y == 1)):
        raise ValueError('correct must be binary')
    ids = np.minimum((c * bins).astype(int), bins - 1)
    details = []
    ece = 0.0
    for b in range(bins):
        keep = ids == b
        if not keep.any():
            continue
        n = int(keep.sum())
        acc, mean_conf = float(y[keep].mean()), float(c[keep].mean())
        ece += n / len(c) * abs(acc - mean_conf)
        details.append({'bin': b, 'count': n, 'accuracy': acc, 'mean_confidence': mean_conf})
    return {'ece': ece, 'n': len(c), 'bins': details}


def binomial_upper(errors: int, total: int, alpha: float = 0.05) -> float | None:
    """One-sided Clopper-Pearson upper endpoint, requiring IID Bernoulli trials.

    A numerical endpoint is not a certificate for correlated/selected observations.
    No issued decisions => undefined conditional risk, not zero.
    """
    if isinstance(total,bool) or isinstance(errors,bool) or not isinstance(total,int) or not isinstance(errors,int) or total < 0 or errors < 0 or errors > total or not 0 < alpha < 1:
        raise ValueError('Invalid count or alpha')
    if total == 0:
        return None
    if errors == total:
        return 1.0
    return float(beta.ppf(1 - alpha, errors + 1, total - errors))


def classification_metrics(y_true: Sequence, y_pred: Sequence, classes: Sequence) -> dict:
    y, p = np.asarray(y_true), np.asarray(y_pred)
    if not len(y) or y.shape != p.shape or y.ndim != 1:
        raise ValueError('Expected equal nonempty label vectors')
    if any(v not in classes for v in y) or any(v not in classes for v in p):
        raise ValueError('Unknown label')
    conf = [[int(((y == a) & (p == b)).sum()) for b in classes] for a in classes]
    per = {}
    for i, c in enumerate(classes):
        tp = conf[i][i]
        support = sum(conf[i]); issued = sum(r[i] for r in conf)
        precision = tp / issued if issued else 0.0
        recall = tp / support if support else None
        f1 = 2 * tp / (support + issued) if support + issued else 0.0
        per[str(c)] = {'support': support, 'precision': precision, 'recall': recall, 'f1': f1}
    valid = [v for v in per.values() if v['support']]
    return {'n': len(y), 'accuracy': float((y == p).mean()),
            'balanced_accuracy': float(np.mean([v['recall'] for v in valid])),
            'macro_f1': float(np.mean([v['f1'] for v in per.values()])),
            'macro_f1_class_policy': 'fixed_label_set_zero_division_0',
            'classes': list(classes), 'confusion': conf, 'per_class': per}


def action_metrics(expected: Sequence[set[str]], forbidden: Sequence[set[str]], predicted: Sequence[set[str]],
                   observed: Sequence[bool] | None = None, keep: str = 'keep_current_setup') -> dict:
    if not expected or len(expected) != len(forbidden) or len(expected) != len(predicted):
        raise ValueError('Unequal or empty collections')
    n = len(expected)
    valid = [True] * n if observed is None else list(observed)
    if len(valid) != n:
        raise ValueError('Invalid observation mask')
    hit, violate, issued, exact, precisions = [], [], [], [], []
    for e, f, p, ok in zip(expected, forbidden, predicted, valid):
        hit.append(bool(ok and (bool(e & p) if e else not p)))
        violate.append(bool(ok and f & p))
        issued.append(bool(ok and p - {keep}))
        exact.append(bool(ok and p == e))
        if ok and p:
            precisions.append(len(e & p) / len(p))
    denom = sum(issued)
    labeled = [bool(e) for e in expected]
    n_labeled = sum(labeled)
    return {'n': n, 'response_coverage': sum(valid)/n, 'semantic_labeled_n': n_labeled,
            'expected_action_recall_among_labeled': sum(h and l for h,l in zip(hit,labeled))/n_labeled if n_labeled else None,
            'exact_labeled_set_match': sum(e and l for e,l in zip(exact,labeled))/n_labeled if n_labeled else None, 'forbidden_any_rate': sum(violate)/n,
            'correction_coverage': denom/n,
            'forbidden_among_corrections': sum(v and i for v,i in zip(violate,issued))/denom if denom else None,
            'mean_label_set_precision_when_nonempty': float(np.mean(precisions)) if precisions else None}


def empirical_risk_coverage(confidence: Sequence[float], correct: Sequence[int]) -> list[dict]:
    c, y = np.asarray(confidence, float), np.asarray(correct, float)
    expected_calibration_error(c, y)  # validate inputs
    out = []
    for threshold in sorted(set([0.0, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 1.0])):
        chosen = c >= threshold
        k = int(chosen.sum()); err = int((1-y[chosen]).sum())
        out.append({'threshold': threshold, 'issued': k, 'coverage': k/len(c),
                    'empirical_error': err/k if k else None,
                    'binomial_upper_iid_reference_only': binomial_upper(err,k)})
    return out
