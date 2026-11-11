"""Exploratory paired cluster-bootstrap intervals. Not rare-risk certification."""
from __future__ import annotations
from collections import defaultdict
import numpy as np


def paired_cluster_difference(rows_a, rows_b, field='benefit', repeats=2000, seed=20261111):
    """Difference A-B of case-weighted means; resample whole source families.

    Inputs: one {case_id, family_id, <field>: finite float} row per case and method.
    At least two observed families are needed. Shared sites beyond family_id may
    require a higher cluster level. Percentile intervals are approximate.
    """
    if isinstance(repeats,bool) or not isinstance(repeats,int) or repeats<100:
        raise ValueError('At least 100 bootstrap repeats required')
    a={r['case_id']:r for r in rows_a};b={r['case_id']:r for r in rows_b}
    if not a or len(a)!=len(rows_a) or len(b)!=len(rows_b) or set(a)!=set(b):
        raise ValueError('Cases must be nonempty, unique and exactly paired')
    groups=defaultdict(list)
    for key in sorted(a):
        if a[key]['family_id']!=b[key]['family_id']:raise ValueError('Family mismatch')
        x,y=a[key][field],b[key][field]
        if isinstance(x,bool) or isinstance(y,bool) or not isinstance(x,(int,float)) or not isinstance(y,(int,float)) or not np.isfinite([x,y]).all():
            raise ValueError('Scores must be finite numeric observations, not missing outcomes')
        groups[a[key]['family_id']].append(x-y)
    values=[np.array(groups[g],float) for g in sorted(groups)];estimate=float(np.concatenate(values).mean())
    if len(values)<2:
        return {'estimate':estimate,'interval95':None,'families':len(values),'status':'insufficient_clusters'}
    sizes=np.array([len(v) for v in values]);sums=np.array([v.sum() for v in values]);rng=np.random.default_rng(seed)
    sample=rng.integers(0,len(values),size=(repeats,len(values)))
    differences=sums[sample].sum(axis=1)/sizes[sample].sum(axis=1)
    return {'estimate':estimate,'interval95':np.quantile(differences,[.025,.975]).tolist(),'families':len(values),
            'cases':len(a),'repeats':repeats,'seed':seed,'status':'descriptive_percentile_cluster_bootstrap',
            'warning':'Not a risk certificate; validity requires appropriate independent sampling units.'}
