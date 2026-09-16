//
//  CaptureIntent.swift
//  shafinMultitool
//
//  Realizes the N3 domain-contract `CaptureIntent` and the frozen
//  SETCompositionNet-v2 `intent_features` encoding (M00b).
//
//  Two vocabularies exist and must not be conflated:
//
//  * `CaptureStyle` — the eight manifest styles that a user may explicitly
//    select: natural, silhouette, low_key, symmetry, negative_space,
//    dutch_angle, intentional_motion_blur, handheld.  Order IS the frozen
//    manifest order and is load-bearing for the 9-component vector.
//  * `CameraStyleCue` — the six detector cues already used by
//    CameraIntentClarificationPolicy.  It is a different set: it has `tilt`
//    (not `dutch_angle`), `motionBlur` (not `intentional_motion_blur`) and it
//    has neither `natural` nor `handheld`.  The cue enum is NOT renamed; the
//    mapping is explicit and documented below.
//
//  Honesty boundary: this file models the *input side* of the v2 contract.
//  No exported Core ML v2 model exists (M05/M06), and the research v1
//  candidate is not relabelled as v2.  Nothing here runs a network.
//

import Foundation

// MARK: - CaptureIntent vocabulary

/// N3 `CaptureIntent.selection`.
enum CaptureIntentSelection: String, CaseIterable, Codable, Sendable {
    case unknown
    case automatic
    case user
    case group
}

/// The eight explicitly selectable styles, in the frozen manifest order of
/// `set_composition_net_v2.json` `inputs.intent_features.ordered_names[0...7]`.
/// `CaseIterable` order equals declaration order, so `allCases` is the
/// canonical encoding order; `CaptureIntentFeatureContract` re-asserts it.
enum CaptureStyle: String, CaseIterable, Codable, Sendable {
    case natural
    case silhouette
    case lowKey = "low_key"
    case symmetry
    case negativeSpace = "negative_space"
    case dutchAngle = "dutch_angle"
    case intentionalMotionBlur = "intentional_motion_blur"
    case handheld
}

/// N3 `UserConstraint.kind`.
enum CaptureIntentConstraintKind: String, CaseIterable, Codable, Sendable {
    case doNotMove = "do_not_move"
    case doNotRemove = "do_not_remove"
    case preserveLight = "preserve_light"
    case preserveRegion = "preserve_region"
    case unavailableResource = "unavailable_resource"
}

/// Named resources admissible for `unavailable_resource`.
enum CaptureIntentResource: String, CaseIterable, Codable, Sendable {
    case additionalLight = "additional_light"
    case tripod
    case reflector
}

/// N3 `UserConstraint`: exactly the target required by `kind` is present and
/// the other two are absent. A VLM can never create or remove one.
struct CaptureIntentUserConstraint: Equatable, Codable, Sendable {
    let kind: CaptureIntentConstraintKind
    let entityRef: String?
    let region: NormalizedRect?
    let resourceID: CaptureIntentResource?

    init(kind: CaptureIntentConstraintKind,
         entityRef: String? = nil,
         region: NormalizedRect? = nil,
         resourceID: CaptureIntentResource? = nil) {
        self.kind = kind
        self.entityRef = entityRef
        self.region = region
        self.resourceID = resourceID
    }

    func validate() -> [String] {
        var errors: [String] = []
        let presentTargets = [entityRef != nil, region != nil, resourceID != nil].filter { $0 }.count
        if presentTargets != 1 {
            errors.append("captureIntent.constraint \(kind.rawValue) must carry exactly one target")
            return errors
        }
        switch kind {
        case .doNotMove, .doNotRemove:
            if entityRef == nil { errors.append("captureIntent.constraint \(kind.rawValue) requires entityRef") }
        case .preserveLight, .preserveRegion:
            if region == nil { errors.append("captureIntent.constraint \(kind.rawValue) requires region") }
        case .unavailableResource:
            if resourceID == nil { errors.append("captureIntent.constraint unavailable_resource requires resourceID") }
        }
        return errors
    }
}

/// N3 `OutputIntent`.
struct CaptureIntentOutput: Equatable, Codable, Sendable {
    let aspectRatio: Double
    let crop: NormalizedRect
    let reservedRegions: [NormalizedRect]

    init(aspectRatio: Double, crop: NormalizedRect, reservedRegions: [NormalizedRect] = []) {
        self.aspectRatio = aspectRatio
        self.crop = crop
        self.reservedRegions = reservedRegions
    }

    func validate() -> [String] {
        var errors: [String] = []
        if !aspectRatio.isFinite || aspectRatio <= 0 {
            errors.append("captureIntent.output.aspectRatio must be finite and positive")
        }
        if crop.isDegenerate {
            errors.append("captureIntent.output.crop must not be degenerate")
        }
        if reservedRegions.contains(where: { $0.isDegenerate }) {
            errors.append("captureIntent.output.reservedRegions must not be degenerate")
        }
        return errors
    }
}

/// N3 `CaptureIntent`: the user's explicit intent for one analysis generation.
///
/// An empty `styles` array means the intent is UNKNOWN.  It is never silently
/// promoted to `natural`.  Multiple explicitly selected styles are preserved
/// together.  Any change of selection, styles, constraints or output must bump
/// `intentRevision`; the `with*` helpers enforce that.
struct CaptureIntent: Equatable, Sendable {
    let selection: CaptureIntentSelection
    let subjectRefs: [String]
    let styles: [CaptureStyle]
    let constraints: [CaptureIntentUserConstraint]
    let output: CaptureIntentOutput?
    let intentRevision: UInt64

    init(selection: CaptureIntentSelection,
         subjectRefs: [String] = [],
         styles: [CaptureStyle] = [],
         constraints: [CaptureIntentUserConstraint] = [],
         output: CaptureIntentOutput? = nil,
         intentRevision: UInt64 = 0) {
        self.selection = selection
        self.subjectRefs = subjectRefs
        self.styles = styles
        self.constraints = constraints
        self.output = output
        self.intentRevision = intentRevision
    }

    /// Unknown intent: no explicit style, no subject, no claims.
    static func unknown(intentRevision: UInt64 = 0) -> CaptureIntent {
        CaptureIntent(selection: .unknown, intentRevision: intentRevision)
    }

    var hasExplicitStyles: Bool { !styles.isEmpty }

    func validate() -> [String] {
        var errors: [String] = []
        if selection == .unknown {
            if !subjectRefs.isEmpty {
                errors.append("captureIntent.selection unknown forbids subjectRefs")
            }
        }
        if selection == .group, subjectRefs.count < 2 {
            errors.append("captureIntent.selection group requires at least two subjectRefs")
        }
        if Set(subjectRefs).count != subjectRefs.count {
            errors.append("captureIntent.subjectRefs must be unique")
        }
        if subjectRefs.contains(where: { $0.isEmpty }) {
            errors.append("captureIntent.subjectRefs must be non-empty opaque ids")
        }
        if Set(styles).count != styles.count {
            errors.append("captureIntent.styles must be unique")
        }
        for constraint in constraints {
            errors.append(contentsOf: constraint.validate())
        }
        if let output {
            errors.append(contentsOf: output.validate())
        }
        return errors
    }

    /// The frozen 9-component `intent_features` vector for this intent.
    /// Empty styles encode the unknown state (all zeros), never `natural`.
    func intentFeatures() throws -> [Double] {
        try CaptureIntentFeatureContract.encode(styles: styles)
    }

    // MARK: - Revision-preserving mutations

    private func revised(selection: CaptureIntentSelection? = nil,
                         styles: [CaptureStyle]? = nil,
                         constraints: [CaptureIntentUserConstraint]? = nil,
                         output: CaptureIntentOutput?? = nil,
                         subjectRefs: [String]? = nil) -> CaptureIntent {
        let next = CaptureIntent(
            selection: selection ?? self.selection,
            subjectRefs: subjectRefs ?? self.subjectRefs,
            styles: styles ?? self.styles,
            constraints: constraints ?? self.constraints,
            output: output ?? self.output,
            intentRevision: intentRevision
        )
        guard next != self else { return self }
        return CaptureIntent(
            selection: next.selection,
            subjectRefs: next.subjectRefs,
            styles: next.styles,
            constraints: next.constraints,
            output: next.output,
            intentRevision: intentRevision &+ 1
        )
    }

    func selecting(_ selection: CaptureIntentSelection) -> CaptureIntent {
        revised(selection: selection)
    }

    func withStyles(_ styles: [CaptureStyle]) -> CaptureIntent {
        revised(styles: styles)
    }

    func withConstraints(_ constraints: [CaptureIntentUserConstraint]) -> CaptureIntent {
        revised(constraints: constraints)
    }

    func withOutput(_ output: CaptureIntentOutput?) -> CaptureIntent {
        revised(output: .some(output))
    }

    func withSubjectRefs(_ subjectRefs: [String]) -> CaptureIntent {
        revised(subjectRefs: subjectRefs)
    }
}

// MARK: - CameraStyleCue <-> CaptureStyle mapping

extension CameraStyleCue {

    /// Documented mapping of a detector cue onto the manifest style vocabulary.
    /// `isExactSemanticMatch == false` means the visible look can equally be a
    /// technical defect; such a cue is only a *candidate* and requires explicit
    /// user confirmation before it may become an explicit `CaptureStyle`.
    struct CaptureStyleMapping: Equatable, Sendable {
        let style: CaptureStyle
        let isExactSemanticMatch: Bool
        let rationale: String
    }

    var captureStyleMapping: CaptureStyleMapping {
        switch self {
        case .lowKey:
            return .init(
                style: .lowKey,
                isExactSemanticMatch: true,
                rationale: "deliberate low-key exposure"
            )
        case .silhouette:
            return .init(
                style: .silhouette,
                isExactSemanticMatch: true,
                rationale: "deliberate silhouette against a bright background"
            )
        case .symmetry:
            return .init(
                style: .symmetry,
                isExactSemanticMatch: true,
                rationale: "deliberate symmetrical composition"
            )
        case .negativeSpace:
            return .init(
                style: .negativeSpace,
                isExactSemanticMatch: true,
                rationale: "deliberate negative space"
            )
        case .tilt:
            return .init(
                style: .dutchAngle,
                isExactSemanticMatch: false,
                rationale: "a tilted horizon may be an accidental level error; dutch_angle is an intentional roll"
            )
        case .motionBlur:
            return .init(
                style: .intentionalMotionBlur,
                isExactSemanticMatch: false,
                rationale: "blur may be a defect; intentional_motion_blur is an explicit creative choice"
            )
        }
    }

    /// The mapped manifest style. All six existing cues have one candidate.
    var captureStyle: CaptureStyle { captureStyleMapping.style }
}

extension CaptureStyle {

    /// The cue that may *suggest* this style, or `nil` when the style lies
    /// outside the cue-detectable set. `natural` and `handheld` are
    /// explicit-only: no cue may infer them, and they are never defaults.
    var detectedCueCandidate: CameraStyleCue? {
        switch self {
        case .lowKey: return .lowKey
        case .silhouette: return .silhouette
        case .symmetry: return .symmetry
        case .negativeSpace: return .negativeSpace
        case .dutchAngle: return .tilt
        case .intentionalMotionBlur: return .motionBlur
        case .natural, .handheld: return nil
        }
    }
}

// MARK: - Frozen intent_features encoding

enum CaptureIntentFeatureEncodingError: Error, Equatable {
    case duplicateStyle(String)
    case unknownStyle(String)
    case emptyExplicitSelection
}

/// Machine-readable SETCompositionNet-v2 intent input contract. Order, dtype
/// and unknown/known semantics are copied from
/// `ml/camera_coach/contracts/set_composition_net_v2.json`
/// (`inputs.intent_features` + `preprocessing.intent_encoding`). The parity
/// fixture is `set_composition_net_v2_intent_parity.json`.
enum CaptureIntentFeatureContract {
    static let inputContractVersion = "setcompositionnet.input.v2"
    static let recipeVersion = "explicit_style_flags.v2"
    static let intentFeatureName = "intent_features"
    static let featureCount = 9
    static let dtype = "float32"

    /// Manifest `ordered_names` exactly.
    static let orderedNames = [
        "natural", "silhouette", "low_key", "symmetry",
        "negative_space", "dutch_angle", "intentional_motion_blur",
        "handheld", "known"
    ]
    static let styleFlagNames = Array(orderedNames.dropLast())
    static let knownFlagName = "known"
    static let knownFlagIndex = 8

    /// Encode explicit style names. An empty list is the unknown state and is
    /// encoded as known=0 with all eight flags 0. A bare string is not a list.
    static func encode(styleNames: [String]) throws -> [Double] {
        if Set(styleNames).count != styleNames.count {
            let duplicate = styleNames.first { name in
                styleNames.filter { $0 == name }.count > 1
            } ?? ""
            throw CaptureIntentFeatureEncodingError.duplicateStyle(duplicate)
        }
        let knownNames = Set(styleFlagNames)
        if let unknown = styleNames.first(where: { !knownNames.contains($0) }) {
            throw CaptureIntentFeatureEncodingError.unknownStyle(unknown)
        }
        var vector = Array(repeating: 0.0, count: featureCount)
        for name in styleNames {
            if let index = orderedNames.firstIndex(of: name) {
                vector[index] = 1.0
            }
        }
        vector[knownFlagIndex] = styleNames.isEmpty ? 0.0 : 1.0
        return vector
    }

    /// Encode explicit styles. Empty styles encode the unknown state.
    static func encode(styles: [CaptureStyle]) throws -> [Double] {
        try encode(styleNames: styles.map(\.rawValue))
    }

    /// Encode a selection asserted to be explicit. An empty selection is
    /// rejected: known=1 requires at least one explicit style.
    static func encodeExplicit(styleNames: [String]) throws -> [Double] {
        guard !styleNames.isEmpty else {
            throw CaptureIntentFeatureEncodingError.emptyExplicitSelection
        }
        return try encode(styleNames: styleNames)
    }

    /// Validate the frozen unknown/explicit semantics. Returns [] when valid,
    /// otherwise one message per violation. Mirrors the Python
    /// `validate_intent_features` rules exactly.
    static func validate(_ vector: [Double]) -> [String] {
        var errors: [String] = []
        guard vector.count == featureCount else {
            errors.append("intent_features must contain \(featureCount) values")
            return errors
        }
        if vector.contains(where: { !$0.isFinite }) {
            errors.append("intent_features must contain only finite values")
            return errors
        }
        if vector.contains(where: { $0 != 0.0 && $0 != 1.0 }) {
            errors.append("intent_features values must be exactly 0 or 1")
        }
        let styleSum = vector[0..<knownFlagIndex].reduce(0.0, +)
        let known = vector[knownFlagIndex]
        if known == 0.0 && styleSum > 0.0 {
            errors.append(
                "unknown intent must encode known=0 with all eight style flags 0; "
                    + "an absent intent must not be filled with a style such as natural"
            )
        }
        if known == 1.0 && styleSum == 0.0 {
            errors.append("known=1 requires at least one explicit style flag")
        }
        return errors
    }

    /// Frozen v2 supervision mask for the four intent-conditioned heads.
    /// Ones only when intent is explicitly known and a ROI is present.
    static func supervisionMask(intentFeatures: [Double], roiPresent: Bool) -> [Double] {
        let admissible = roiPresent
            && intentFeatures.count == featureCount
            && intentFeatures[knownFlagIndex] == 1.0
        return Array(repeating: admissible ? 1.0 : 0.0, count: 4)
    }

    /// The style flags present in a validated vector, in manifest order.
    static func selectedStyleNames(in vector: [Double]) -> [String] {
        guard vector.count == featureCount else { return [] }
        return (0..<knownFlagIndex).compactMap { index in
            vector[index] == 1.0 ? orderedNames[index] : nil
        }
    }
}
