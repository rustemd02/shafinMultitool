# V9.1 Integrator / Senior Architect

## proposal
- Integrate V9.1 as runtime/eval-first: screenplay front-end, overlay contract, continuity state, semantic coverage verifier, V9 reason-coded enrichers, chunk metrics, hard-case mining.

## risks
- `test` runner through simulator hung after building; compile evidence is `build-for-testing` plus Python unit tests.
- Demo gate remains conditional until live-model real-app parity is rerun on the series fragment and canonical demo cases.

## required_tests
- `python3 -m unittest docs.SGv7pipeline.v9.tests.test_v9_datasets_eval`
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/sg_v91_workspace_dd -only-testing:shafinMultitoolTests/SceneBundlePipelineTests build-for-testing`

## open_conflicts
- Dynamic grammar and retrain are explicitly deferred to V9.2/V10.

## approval
- `contract_gate`: PASS
- `runtime_gate`: PASS with build-for-testing evidence
- `eval_gate`: PASS for artifact-level metrics
- `demo_gate`: CONDITIONAL, requires live-model parity run
