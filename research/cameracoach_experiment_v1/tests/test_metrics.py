import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import numpy as np
import pytest
from sklearn.metrics import f1_score
from metrics import expected_calibration_error as ece, binomial_upper, classification_metrics, action_metrics, empirical_risk_coverage

@pytest.mark.parametrize('c,y', [([1,1],[1,1]),([0,0],[0,0]),([.9,.8],[1,0]),([.15,.16],[0,1])])
def test_ece_uses_mean_not_midpoint(c,y):
    bins=1
    assert ece(c,y,bins)['ece']==pytest.approx(abs(np.mean(c)-np.mean(y)))

@pytest.mark.parametrize('c,y,bins', [([],[],10),([float('nan')],[1],10),([1.1],[1],10),([-.1],[0],10),([.5],[.5],10),([.5],[1],0),([.5],[1],2.5),([.5],[1],True),([.5,.6],[1],10)])
def test_ece_rejects_invalid(c,y,bins):
    with pytest.raises(ValueError):ece(c,y,bins)

def test_confidence_one_not_lost():
    assert ece([0,.5,1],[0,1,1])['n']==3
    assert sum(b['count'] for b in ece([0,.5,1],[0,1,1])['bins'])==3

@pytest.mark.parametrize('y', [[.5],[float('nan')],[2]])
def test_risk_curve_no_silent_int_truncation(y):
    with pytest.raises(ValueError):empirical_risk_coverage([.8],y)

def test_no_trials_not_zero_risk():
    assert binomial_upper(0,0) is None

def test_zero_errors_known_endpoint():
    assert binomial_upper(0,59)==pytest.approx(1-.05**(1/59))
    assert binomial_upper(59,59)==1

@pytest.mark.parametrize('e,n', [(-1,2),(3,2),(0,-1),(1.5,3),(True,2),(0,2.5)])
def test_invalid_counts(e,n):
    with pytest.raises(ValueError):binomial_upper(e,n)

def test_macro_fixed_labels_matches_sklearn():
    y=['bad','bad','good'];p=['bad','mixed','good'];classes=['good','mixed','bad']
    m=classification_metrics(y,p,classes)
    assert m['macro_f1']==pytest.approx(f1_score(y,p,labels=classes,average='macro',zero_division=0))
    assert m['balanced_accuracy']==pytest.approx(.75)

def test_unknown_class():
    with pytest.raises(ValueError):classification_metrics(['x'],['x'],['a'])

def test_empty_expected_excluded_not_free_hit():
    m=action_metrics([set(),{'a'}],[set(),set()],[set(),set()])
    assert m['semantic_labeled_n']==1 and m['expected_action_recall_among_labeled']==0
    assert m['forbidden_among_corrections'] is None

def test_shotgun_cannot_hide_forbidden():
    m=action_metrics([{'a'}],[{'b'}],[{'a','b','c'}])
    assert m['expected_action_recall_among_labeled']==1
    assert m['forbidden_among_corrections']==1
    assert m['mean_label_set_precision_when_nonempty']==pytest.approx(1/3)

def test_missing_response_counts_coverage():
    m=action_metrics([{'a'}],[set()],[{'a'}],[False])
    assert m['response_coverage']==0 and m['correction_coverage']==0

def test_visible_projection_does_not_include_hidden_other_mode():
    from run_experiment import visible_action_sets
    rows=[{'record_id':'x','shown':False,'semantic_actions':['bad']},
          {'record_id':'x','shown':True,'semantic_actions':['keep_current_setup']}]
    assert visible_action_sets(['x'],rows)==[{'keep_current_setup'}]
