import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import pytest
from uncertainty import paired_cluster_difference as difference


def rows(v):return [{'case_id':str(i),'family_id':str(i//2),'benefit':float(x)} for i,x in enumerate(v)]

def test_zero_difference():
    a=rows([1,0,1,0]);r=difference(a,a)
    assert r['estimate']==0 and r['interval95']==[0,0] and r['families']==2

def test_paired_order_and_seed():
    a=rows([1,0,0,1,0,0]);b=rows([0,0,0,0,0,0]);r=difference(a,b)
    assert r==difference(a,list(reversed(b)))
    assert r['estimate']==pytest.approx(1/3)

def test_one_cluster_not_usable():
    assert difference(rows([1,1]),rows([0,0]))['interval95'] is None

@pytest.mark.parametrize('issue',['missing','duplicate','nan','family'])
def test_bad_pairs(issue):
    a=rows([1,1,0,0]);b=rows([0,0,0,0])
    if issue=='missing':b.pop()
    elif issue=='duplicate':b.append(b[0])
    elif issue=='nan':b[0]['benefit']=float('nan')
    else:b[0]['family_id']='unrelated'
    with pytest.raises(ValueError):difference(a,b)
