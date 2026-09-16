//
//  SETCompositionNetScorer.swift
//  shafinMultitool
//
//  M4 camera-coach research candidate loader. Loads the locally trained
//  Stage-2 silver candidate (SETCompositionNet-Stage2-Local) and exposes its
//  raw multi-task tensors under the frozen IO contract.
//
//  Fail-closed: a missing or unreadable package yields a nil model and every
//  call returns nil — no fabricated scores. This type is deliberately NOT
//  wired into any coaching path: the artifact is research-only
//  (human_gold=false, release_admissible=false), so consuming its heads in
//  production requires the human-gold corpus and a physical-device evaluation
//  first (see ml/camera_coach/INTEGRATION.md).
//

import CoreML
import Foundation

/// Named inputs of the frozen SETCompositionNet v1 contract.
enum SETCompositionNetInputName: String, CaseIterable {
    case fullFrameRGB = "full_frame_rgb"
    case subjectCropRGB = "subject_crop_rgb"
    case roiMask = "roi_mask"
    case roiNormalizedXYWH = "roi_normalized_xywh"
    case scalarFeatures = "scalar_features"
    case missingFeatureMask = "missing_feature_mask"
}

/// Named heads of the frozen SETCompositionNet v1 contract.
enum SETCompositionNetOutputName: String, CaseIterable {
    case sceneClassLogits = "scene_class_logits"
    case subjectnessROIAgreementLogits = "subjectness_roi_agreement_logits"
    case issueLogits = "issue_logits"
    case actionUtilityLogits = "action_utility_logits"
    case goodFrameProbability = "good_frame_probability"
    case abstentionProbability = "abstention_probability"
    case riskProbability = "risk_probability"
    case continuousTargetDeltas = "continuous_target_deltas"
    case embedding = "embedding"
}

/// One loaded candidate. `nil` `model` means the artifact is unavailable.
final class SETCompositionNetScorer {

    /// Resource name of the packaged candidate (compiled to `.mlmodelc` at
    /// build time, with the `.mlpackage` fallback used by the other wrappers).
    static let resourceName = "SETCompositionNet-Stage2-Local"

    private let model: MLModel?

    init() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        if let url = Bundle.main.url(forResource: Self.resourceName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: Self.resourceName, withExtension: "mlpackage"),
           let loaded = try? MLModel(contentsOf: url, configuration: configuration) {
            self.model = loaded
        } else {
            self.model = nil
        }
    }

    /// True only when the artifact loaded; callers must not treat a `false`
    /// value as a zero-score result.
    var isAvailable: Bool { model != nil }

    /// The IO names actually declared by the loaded model, for contract
    /// verification. Empty when the model is unavailable.
    func declaredIO() -> (inputs: Set<String>, outputs: Set<String>)? {
        guard let model else { return nil }
        let description = model.modelDescription
        return (
            inputs: Set(description.inputDescriptionsByName.keys),
            outputs: Set(description.outputDescriptionsByName.keys)
        )
    }

    /// Runs one forward pass. Every supplied feature must already be
    /// preprocessed by the caller (`MetalPreprocessor` owns the tensor layout);
    /// this method performs no coercion and returns `nil` on any failure.
    func predict(features: [SETCompositionNetInputName: MLFeatureValue]) -> [SETCompositionNetOutputName: MLMultiArray]? {
        var provider: [String: MLFeatureValue] = [:]
        for (name, value) in features {
            provider[name.rawValue] = value
        }
        return predictRaw(provider)
    }

    /// String-keyed forward pass. This is the seam v2 uses to add its separate
    /// `intent_features` input without widening the frozen v1 six-input enum.
    /// Fails closed: `nil` when the model is unavailable or prediction fails.
    func predictRaw(_ provider: [String: MLFeatureValue]) -> [SETCompositionNetOutputName: MLMultiArray]? {
        guard let model else { return nil }
        guard let input = try? MLDictionaryFeatureProvider(dictionary: provider),
              let output = try? model.prediction(from: input) else {
            return nil
        }
        var result: [SETCompositionNetOutputName: MLMultiArray] = [:]
        for name in SETCompositionNetOutputName.allCases {
            if let value = output.featureValue(for: name.rawValue)?.multiArrayValue {
                result[name] = value
            }
        }
        return result
    }

    /// True only when a loaded artifact declares the v2 `intent_features`
    /// input. The bundled research candidate is v1 and does not, so this stays
    /// false until a v2 Core ML model is exported (M05/M06). A false value is
    /// not a score and must never be treated as one.
    var declaresV2IntentInput: Bool {
        guard let io = declaredIO() else { return false }
        return io.inputs.contains(SETCompositionNetV2Contract.intentFeatureName)
    }

    /// v2 forward seam: unchanged v1 tensors plus the separate validated
    /// `intent_features` vector. Fail-closed by construction — returns `nil`
    /// when the intent is invalid, no model is loaded, or the loaded model does
    /// not declare `intent_features`. No v2 artifact exists yet, so with the
    /// v1 research candidate this always returns `nil` rather than fabricating
    /// an intent-conditioned score.
    func predictV2(baseFeatures: [SETCompositionNetInputName: MLFeatureValue],
                   intentFeatures: [Double]) -> [SETCompositionNetOutputName: MLMultiArray]? {
        guard declaresV2IntentInput else { return nil }
        guard CaptureIntentFeatureContract.validate(intentFeatures).isEmpty,
              intentFeatures.count == SETCompositionNetV2Contract.intentFeatureCount,
              let array = try? MLMultiArray(
                shape: [NSNumber(value: SETCompositionNetV2Contract.intentFeatureCount)],
                dataType: .float32
              ) else {
            return nil
        }
        for (index, value) in intentFeatures.enumerated() {
            array[index] = NSNumber(value: value)
        }
        var provider: [String: MLFeatureValue] = [:]
        for (name, value) in baseFeatures {
            provider[name.rawValue] = value
        }
        provider[SETCompositionNetV2Contract.intentFeatureName] = MLFeatureValue(multiArray: array)
        return predictRaw(provider)
    }
}
