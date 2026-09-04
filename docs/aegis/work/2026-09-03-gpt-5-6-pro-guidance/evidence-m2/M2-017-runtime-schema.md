# M2-017 — SETCompositionNet runtime schema (typed neural boundary)

Task: Define the typed input/output boundary for the mandatory production neural Camera
component.
Owner boundary: `CameraNeuralRuntimeOwner`. Implementation: NEW
SETCompositionNetRuntimeSchema.swift — SETCompositionNetInput / SETCompositionNetOutput /
Status (available/unavailable/failed(NeuralEvidenceProviderError)), constructors from
NeuralEvidenceProviderRequest+Descriptor+Output, fail-closed validation.

## Contract coverage (acceptance checklist)

| Required element | Where |
|---|---|
| model/version/preprocessing | Input mirrors NeuralEvidenceProviderDescriptor (modelFamily, modelVersion, preprocessingVersion, bundleVersion) |
| subject ROI provenance | Input.subjectROI + roiStrategy; Output echoes actual ROI; validation rejects subjectCropOnly/subject-region requests without ROI provenance and mismatched actual strategies |
| issue/action logits | Output.issueActionLogits keyed by EvidenceHeadId (all 8 required incl. shot_type_confidence delivered via its own field) |
| risk/abstention | Output.riskScore / abstentionScore, range-validated [0,1] |
| good-frame score | Output.goodFrameScore, range-validated |
| continuous targets | Output.continuousTargets keyed by SupportingSignalTag (21) |
| explicit unavailable/failure | Status .unavailable / .failed(reason); no scores carried; validation clean (honest states, not errors) |

## Fail-closed validation (rejects)

NaN/non-finite in any logit/target/affinity/summary score; missing required heads; wrong
frameId (provider-claimed id vs request); wrong pipeline generation; ROI strategy mismatch /
missing ROI provenance; risk/abstention/goodFrame out of [0,1].

## Tests (SETCompositionNetRuntimeSchemaTests 11/11 PASS; xcresult /private/tmp/shafin-m2-017.xcresult)

Clean boundary validates; NaN in heads/targets rejected; out-of-range risk/abstention/goodFrame
rejected; missing head rejected; wrong frameId rejected; wrong generation rejected; mismatched
ROI strategy rejected; missing subject ROI provenance rejected; unavailable/failed states carry
no scores and validate clean.

Attempts: 1) ImageIO import + let-status construction; 2) memberwise init for invalid-value
injection (let properties); 3) enum case-name fixes (subjectCropOnly/coremlLocal/onDevice);
4) helper ignoring injected output — fixed; 5) REAL constructor gap found by tests: the
.available echo dropped the shot_type_confidence head — fixed.
