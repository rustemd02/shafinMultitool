"""M0-011 fixture check: positive and negative manifests against release-evidence-schema."""
import json, sys
schema = json.load(open('docs/implementation/release-evidence-schema.json'))
def check(m, label):
    errs = [k for k in schema['required'] if k not in m]
    print(('PASS ' if not errs else 'FAIL ') + label + ('' if not errs else ' missing=%s' % errs))
    return not errs
ok = True
ok &= check({'schema_version':'release-evidence-v1','task_id':'M0-001','milestone_gate':'M0-GATE','utc':'2026-09-03T00:00:00Z','source_state':{'branch':'store','head':'c61e988','porcelain_v2_sha256':'x','dirty_receipt_sha256':'y'},'toolchain':{'xcode':'26.6','sdk':'iPhoneOS26.5','sim_runtime':'iOS 26.5'},'command':{'argv':'git status','exit_code':0,'log_sha256':'z'},'artifacts':[],'claim_scope':'source'}, 'positive-fixture')
ok &= (not check({'task_id':'M0-001'}, 'negative-fixture-must-fail'))
sys.exit(0 if ok else 1)
