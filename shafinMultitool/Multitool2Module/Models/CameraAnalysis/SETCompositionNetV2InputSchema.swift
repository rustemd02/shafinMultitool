//
//  SETCompositionNetV2InputSchema.swift
//  shafinMultitool
//
//  M00b input-side seam for SETCompositionNet-v2. It pairs the unchanged v1
//  six-tensor payload with the separate 9-component `intent_features` input.
//
//  The v1 six-input research contract is untouched: `SETCompositionNetContract`
//  and `SETCompositionNetInputTensors` are neither renamed, resized nor reused.
//  In particular the 40 scalar slots never carry intent
//  (`not_encoded_in_scalar_features` in the v2 manifest).
//
//  Honesty boundary: no exported Core ML v2 model exists yet (M05/M06), so this
//  type is an assembly/validation boundary only. `SETCompositionNetScorer`
//  fails closed when asked to run it.
//

import Foundation

/// Metadata for the separate v2 intent input. Version strings come from
/// `ml/camera_coach/contracts/set_composition_net_v2.json`.
enum SETCompositionNetV2Contract {
    static let inputContractVersion = "setcompositionnet.input.v2"
    static let preprocessingVersion = "setcompositionnet.preprocessing.v2"
    static let featureVersion = "setcompositionnet.features.v2"
    static let intentFeatureName = CaptureIntentFeatureContract.intentFeatureName
    static let intentFeatureCount = CaptureIntentFeatureContract.featureCount
}

/// Assembly boundary payload for one v2 record: the v1 tensors plus a validated
/// `intent_features` vector. The v1 payload keeps its own validation.
struct SETCompositionNetV2InputTensors: Equatable, Sendable {
    let base: SETCompositionNetInputTensors
    let intentFeatures: [Double]

    init(base: SETCompositionNetInputTensors, intentFeatures: [Double]) {
        self.base = base
        self.intentFeatures = intentFeatures
    }

    /// Build from an explicit `CaptureIntent`. Empty styles remain the unknown
    /// encoding; they are never replaced with `natural`.
    init(base: SETCompositionNetInputTensors, intent: CaptureIntent) throws {
        self.init(base: base, intentFeatures: try intent.intentFeatures())
    }

    /// The 40 scalar slots of the base payload stay exactly as supplied. This
    /// property exists to make that isolation explicit at call sites.
    var scalarFeatures: [Double] { base.scalarFeatures }

    func validate() -> [String] {
        var errors = base.validate()
        errors.append(contentsOf: CaptureIntentFeatureContract.validate(intentFeatures).map {
            "compositionNetV2.\($0)"
        })
        return errors
    }
}
