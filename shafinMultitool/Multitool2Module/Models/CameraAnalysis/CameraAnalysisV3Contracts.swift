//
//  CameraAnalysisV3Contracts.swift
//  shafinMultitool
//
//  Runbook package C01.a: executable v3 schema/types and fail-closed validation
//  for the CameraAnalysis draft contract.
//
//  Authority chain
//  ---------------
//  * docs/cameraanalysis/operations-registry.v3-draft.json is the machine-readable
//    P01 projection of docs/cameraanalysis/03-domain-contracts.md N6.1. It is not a
//    stable contract; stable v3 is declared only after this C01 conformance passes.
//  * Frozen axes SemanticActionType (26) and TechnicalQualityActionType (7) live in
//    CameraAnalysisDomainContracts.swift and are NOT edited or redeclared here.
//  * This file intentionally defines its own Region type instead of reusing
//    NormalizedRect: NormalizedRect silently clamps non-finite/out-of-range input to
//    zero, which would turn "unknown" into a plausible value. The v3 contract is
//    fail-closed and rejects such payloads with a specific reason.
//  * The Python mirror is tools/tests/test_camera_analysis_v3_parity.py; both
//    languages consume the same fixtures, see tools/tests/fixtures/
//    camera_analysis_v3_cases.json (bundled copy for this test target at
//    shafinMultitoolTests/Fixtures/camera_analysis_v3_cases.json).
//
//  Validation order is deterministic and mirrored in Python; the first fault wins.
//

import Foundation
import CoreFoundation

// MARK: - Canonical constants

enum CameraAnalysisV3Contract {
    static let schemaID = "camera-operations-registry-v3-draft"
    static let schemaVersion = "3.0.0-draft.1"

    /// Frozen operation catalog (registry `operations`, 20 entries, unique ids).
    /// Operations whose id equals a TechnicalQualityActionType id reference the
    /// existing technical action and never re-declare it.
    static let operations: [String] = [
        "reframe_subject",
        "change_subject_scale",
        "level_frame",
        "reposition_entity",
        "rotate_entity",
        "exclude_entity",
        "reposition_camera",
        "adjust_light",
        "adjust_exposure",
        "refocus_subject",
        "hold_steady",
        "set_capture_parameter",
        "change_lens",
        "reserve_output_region",
        "wait_for_clearance",
        "select_capture_moment",
        "maintain_subject_zone",
        "smooth_camera_motion",
        "plan_motion_endpoints",
        "clear_lens_obstruction",
    ]

    static let reasonCodes: [String] = [
        "ready",
        "correction_available",
        "ambiguous_subject",
        "no_subject",
        "acquiring",
        "unstable",
        "stale",
        "identity_lost",
        "unsupported_case",
        "unqualified",
        "missing_evidence",
        "conflicting_evidence",
        "protected_intent",
        "infeasible",
        "network_unavailable",
        "quota_exhausted",
        "invalid_payload",
        "scope_changed",
    ]

    static let states: Set<String> = ["CORRECT", "SELECT_SUBJECT", "KEEP", "WAIT", "ABSTAIN"]
    static let phases: Set<String> = ["live", "review"]
    static let orientations: Set<String> = ["portrait", "landscape"]
    static let entityKinds: Set<String> = ["person", "object", "group", "light"]
    static let entityRoles: Set<String> = ["target", "protected", "context"]
    static let evidenceQualifications: Set<String> = ["qualified", "unknown"]
    static let qualificationStatuses: Set<String> = ["qualified", "unknown"]
    static let artifactKinds: Set<String> = ["production", "research"]
    static let desiredValues: Set<String> = ["inside_region", "increase", "decrease", "preserve"]
    static let verificationOutcomes: Set<String> = ["improved", "unchanged", "worse", "incomparable"]
    static let coverageKinds: Set<String> = ["single_frame", "sampled_frames", "continuous_interval"]
    static let temporalCoverageKinds: Set<String> = ["sampled_frames", "continuous_interval"]
    static let lockParameters: Set<String> = ["exposure_lock", "focus_lock", "white_balance_lock"]
    static let numericParameters: Set<String> = ["white_balance_kelvin", "shutter_seconds"]
    static let captureParameters: Set<String> = lockParameters.union(numericParameters)
}

// MARK: - Rejection reasons (canonical, shared with the Python validator)

enum CameraAnalysisV3ValidationReason: String, Error, Equatable {
    case invalidJSON = "invalid_json"
    case schemaVersionMismatch = "schema_version_mismatch"
    case missingRequiredField = "missing_required_field"
    case unknownEnumValue = "unknown_enum_value"
    case unknownReasonCode = "unknown_reason_code"
    case unknownOperation = "unknown_operation"
    case invalidActionPayload = "invalid_action_payload"
    case nonFiniteNumber = "non_finite_number"
    case regionNotNumeric = "region_not_numeric"
    case regionNonFinite = "region_non_finite"
    case regionOutOfRange = "region_out_of_range"
    case regionDegenerate = "region_degenerate"
    case entityReferenceMissing = "entity_reference_missing"
    case relationEndpointMissing = "relation_endpoint_missing"
    case duplicateEntityID = "duplicate_entity_id"
    case duplicateRelationID = "duplicate_relation_id"
    case entityGraphCycle = "entity_graph_cycle"
    case labelNotIdentity = "label_not_identity"
    case frameReferenceMissing = "frame_reference_missing"
    case transformReferenceMissing = "transform_reference_missing"
    case outputCropMismatch = "output_crop_mismatch"
    case orientationMismatch = "orientation_mismatch"
    case mirroringMismatch = "mirroring_mismatch"
    case staleIntentRevision = "stale_intent_revision"
    case stateActionConflict = "state_action_conflict"
    case reviewStateWithAction = "review_state_with_action"
    case selectionCandidatesConflict = "selection_candidates_conflict"
    case missingQualification = "missing_qualification"
    case unqualifiedEvidence = "unqualified_evidence"
    case researchNotAdmitted = "research_not_admitted"
    case missingTemporalEvidence = "missing_temporal_evidence"
    case claimedImprovementWithoutDelta = "claimed_improvement_without_delta"
    case protectedRegression = "protected_regression"
    case frozenRecordMutation = "frozen_record_mutation"
    case identityLost = "identity_lost"
}

struct CameraAnalysisV3ValidationFailure: Error, Equatable {
    let reason: CameraAnalysisV3ValidationReason
    let path: String
    let detail: String

    init(_ reason: CameraAnalysisV3ValidationReason, _ path: String, _ detail: String = "") {
        self.reason = reason
        self.path = path
        self.detail = detail
    }
}

// MARK: - Executable types

enum CameraAnalysisV3Phase: String, Equatable, Sendable {
    case live
    case review
}

enum CameraAnalysisV3State: String, Equatable, Sendable {
    case correct = "CORRECT"
    case selectSubject = "SELECT_SUBJECT"
    case keep = "KEEP"
    case wait = "WAIT"
    case abstain = "ABSTAIN"
}

enum CameraAnalysisV3ReasonCode: String, Equatable, Sendable {
    case ready
    case correctionAvailable = "correction_available"
    case ambiguousSubject = "ambiguous_subject"
    case noSubject = "no_subject"
    case acquiring
    case unstable
    case stale
    case identityLost = "identity_lost"
    case unsupportedCase = "unsupported_case"
    case unqualified
    case missingEvidence = "missing_evidence"
    case conflictingEvidence = "conflicting_evidence"
    case protectedIntent = "protected_intent"
    case infeasible
    case networkUnavailable = "network_unavailable"
    case quotaExhausted = "quota_exhausted"
    case invalidPayload = "invalid_payload"
    case scopeChanged = "scope_changed"
}

/// Disposition vocabulary projected from case-coverage.v3-draft.json.
enum CameraAnalysisV3Disposition: String, Equatable, Sendable {
    case qualified
    case conditionalReview = "conditional_review"
    case unsupportedWithReason = "unsupported_with_reason"
    case outOfReleaseScope = "out_of_release_scope_by_owner"
}

enum CameraAnalysisV3Orientation: String, Equatable, Sendable {
    case portrait
    case landscape
}

enum CameraAnalysisV3EntityKind: String, Equatable, Sendable {
    case person, object, group, light
}

enum CameraAnalysisV3EntityRole: String, Equatable, Sendable {
    case target, protected, context
}

enum CameraAnalysisV3EvidenceQualification: String, Equatable, Sendable {
    case qualified
    case unknown
}

enum CameraAnalysisV3ArtifactKind: String, Equatable, Sendable {
    case production
    case research
}

enum CameraAnalysisV3Desired: String, Equatable, Sendable {
    case insideRegion = "inside_region"
    case increase
    case decrease
    case preserve
}

enum CameraAnalysisV3VerificationOutcome: String, Equatable, Sendable {
    case improved, unchanged, worse, incomparable
}

enum CameraAnalysisV3CoverageKind: String, Equatable, Sendable {
    case singleFrame = "single_frame"
    case sampledFrames = "sampled_frames"
    case continuousInterval = "continuous_interval"
}

/// Validated normalized region. Raw values are stored exactly as supplied; the
/// only way to obtain one is through validation, which rejects non-finite and
/// out-of-range values instead of clamping them.
struct CameraAnalysisV3Region: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var isDegenerate: Bool { width <= 0 || height <= 0 }

    func contains(_ inner: CameraAnalysisV3Region, epsilon: Double = 1e-9) -> Bool {
        inner.x >= x - epsilon
            && inner.y >= y - epsilon
            && inner.x + inner.width <= x + width + epsilon
            && inner.y + inner.height <= y + height + epsilon
    }
}

struct CameraAnalysisV3FrameReference: Equatable, Sendable {
    let frameID: String
    let orientation: CameraAnalysisV3Orientation
    let mirrored: Bool
    let outputCrop: CameraAnalysisV3Region
    let transformRef: String
}

struct CameraAnalysisV3Entity: Equatable, Sendable {
    let entityID: String
    let kind: CameraAnalysisV3EntityKind
    let displayLabel: String
    let trackID: String
    let role: CameraAnalysisV3EntityRole
}

struct CameraAnalysisV3Relation: Equatable, Sendable {
    let relationID: String
    let kind: String
    let endpoints: [String]
}

struct CameraAnalysisV3Evidence: Equatable, Sendable {
    let evidenceID: String
    let qualificationStatus: CameraAnalysisV3EvidenceQualification
    let relationRef: String?
}

struct CameraAnalysisV3Qualification: Equatable, Sendable {
    let ref: String
    let status: String
    let artifactKind: CameraAnalysisV3ArtifactKind
    let releaseAdmissionRef: String?
}

struct CameraAnalysisV3EffectGoal: Equatable, Sendable {
    let metricID: String
    let targetEntityRefs: [String]
    let relationRef: String?
    let desired: CameraAnalysisV3Desired
    let targetRegion: CameraAnalysisV3Region?
    let policyRef: String
}

struct CameraAnalysisV3ProtectedDelta: Equatable, Sendable {
    let entityRef: String
    let delta: Double
}

struct CameraAnalysisV3Verification: Equatable, Sendable {
    let outcome: CameraAnalysisV3VerificationOutcome
    let effectDelta: Double
    let deadband: Double
    let goalSatisfied: Bool?
    let protectedDeltas: [CameraAnalysisV3ProtectedDelta]
}

struct CameraAnalysisV3Coverage: Equatable, Sendable {
    let kind: CameraAnalysisV3CoverageKind
    /// MediaTime values. Decoded from Int, Int64-as-string or number; the
    /// string form is accepted so Swift/Python serialization parity is visible.
    let pts: [Int64]
    let contentRevision: Int
}

struct CameraAnalysisV3RecordBaseline: Equatable, Sendable {
    let actionID: String
    let targetRefs: [String]
    let protectedRefs: [String]
}

struct CameraAnalysisV3Record: Equatable, Sendable {
    let recordID: String
    let revision: Int
    let frozen: Bool
    let baseline: CameraAnalysisV3RecordBaseline?
}

/// Operation-typed action payload. Only the fields required by the selected
/// operation are populated; validation enforces the enum/payload combination.
struct CameraAnalysisV3ActionPayload: Equatable, Sendable {
    var targetRegion: CameraAnalysisV3Region?
    var destination: String?
    var fixedCamera: Bool?
    var method: String?
    var desired: String?
    var targetAreaRatio: Double?
    var rotation: String?
    var targetHorizonDegrees: Double?
    var relationRef: String?
    var referencePoint: String?
    var towardEntityRef: String?
    var revealRegion: CameraAnalysisV3Region?
    var turn: String?
    var angleDegrees: Double?
    var change: String?
    var goalRegion: CameraAnalysisV3Region?
    var step: String?
    var lateralDirection: String?
    var receiverEntityRef: String?
    var sourceEntityRef: String?
    var parameter: String?
    var booleanValue: Bool?
    var numberValue: Double?
    var suggestedEV: Double?
    var focusRegion: CameraAnalysisV3Region?
    var windowPolicyRef: String?
    var deviceLensID: String?
    var blockerRefs: [String]
    var fromRegion: CameraAnalysisV3Region?
    var obstructionRegion: CameraAnalysisV3Region?
    var startFrameRef: String?
    var endFrameRef: String?
    var holdPolicyRef: String?
    var region: CameraAnalysisV3Region?
}

struct CameraAnalysisV3ActionBaseline: Equatable, Sendable {
    let actionID: String
    let targetRefs: [String]
    let protectedRefs: [String]
    let intentRevision: Int
    let trackBindings: [String: String]
}

struct CameraAnalysisV3Action: Equatable, Sendable {
    let actionID: String
    let operation: String
    let intentRevision: Int
    let frameRef: String
    let targetRefs: [String]
    let protectedRefs: [String]
    let qualificationRef: String
    let verifierRef: String
    let payload: CameraAnalysisV3ActionPayload
    let effectGoal: CameraAnalysisV3EffectGoal
    let baseline: CameraAnalysisV3ActionBaseline
    let frameOrientation: CameraAnalysisV3Orientation?
    let mirrored: Bool?
}

/// Fully validated v3 envelope. Instances only exist after validation, so a
/// consumer can rely on cross-field invariants (exactly one activeAction in
/// CORRECT, review carries none, refs resolve, record immutability, ...).
struct CameraAnalysisV3Envelope: Equatable, Sendable {
    let schemaVersion: String
    let analysisID: String
    let sessionID: String
    let generation: Int
    let intentRevision: Int
    let phase: CameraAnalysisV3Phase
    let state: CameraAnalysisV3State
    let reasonCode: CameraAnalysisV3ReasonCode
    let frameReference: CameraAnalysisV3FrameReference
    let transformRefs: [String]
    let entities: [CameraAnalysisV3Entity]
    let relations: [CameraAnalysisV3Relation]
    let evidence: [CameraAnalysisV3Evidence]
    let qualification: CameraAnalysisV3Qualification?
    let activeAction: CameraAnalysisV3Action?
    let selectionCandidates: [String]
    let verification: CameraAnalysisV3Verification?
    let coverage: CameraAnalysisV3Coverage?
    let record: CameraAnalysisV3Record?
}

// MARK: - Entry point

extension CameraAnalysisV3Contract {
    /// Strict, fail-closed decode: parse, validate, then build executable types.
    static func decode(_ data: Data) throws -> CameraAnalysisV3Envelope {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw CameraAnalysisV3ValidationFailure(.invalidJSON, "$", "JSON is not parseable")
        }
        try CameraAnalysisV3ContractValidator.validate(jsonObject: raw)
        return try CameraAnalysisV3ContractBuilder.build(raw)
    }

    static func decode(_ data: Data, expectingSchemaVersion version: String) throws -> CameraAnalysisV3Envelope {
        guard version == schemaVersion else {
            throw CameraAnalysisV3ValidationFailure(.schemaVersionMismatch, "$.schemaVersion")
        }
        return try decode(data)
    }
}

// MARK: - Validator

enum CameraAnalysisV3ContractValidator {

    private struct Context {
        let entityIDs: Set<String>
        let labels: Set<String>
        let relationIDs: Set<String>
        let trackBindings: [String: String]
        let frameIDs: Set<String>
        let outputCrop: CameraAnalysisV3Region
        let regionByPath: [String: CameraAnalysisV3Region]
        let phase: String
    }

    static func validate(data: Data) throws {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw CameraAnalysisV3ValidationFailure(.invalidJSON, "$", "JSON is not parseable")
        }
        try validate(jsonObject: raw)
    }

    static func validate(jsonObject raw: Any) throws {
        let body = try object(raw, "$")

        guard let version = body["schemaVersion"] as? String else {
            throw CameraAnalysisV3ValidationFailure(.schemaVersionMismatch, "$.schemaVersion")
        }
        guard version == CameraAnalysisV3Contract.schemaVersion else {
            throw CameraAnalysisV3ValidationFailure(.schemaVersionMismatch, "$.schemaVersion")
        }
        _ = try requiredString(body, "analysisID", "$")
        _ = try requiredString(body, "sessionID", "$")
        _ = try requiredInt(body, "generation", "$")
        let intentRevision = try requiredInt(body, "intentRevision", "$")
        let phase = try requiredEnum(body, "phase", "$", CameraAnalysisV3Contract.phases)
        let state = try requiredEnum(body, "state", "$", CameraAnalysisV3Contract.states)
        let reasonCode = try requiredString(body, "reasonCode", "$")
        guard CameraAnalysisV3Contract.reasonCodes.contains(reasonCode) else {
            throw CameraAnalysisV3ValidationFailure(.unknownReasonCode, "$.reasonCode")
        }

        let activeAction = body["activeAction"]
        if state == "CORRECT" {
            if phase != "live" {
                throw CameraAnalysisV3ValidationFailure(.reviewStateWithAction, "$.phase")
            }
            guard activeAction is [String: Any] else {
                throw CameraAnalysisV3ValidationFailure(.stateActionConflict, "$.activeAction")
            }
        } else if activeAction != nil {
            throw CameraAnalysisV3ValidationFailure(.stateActionConflict, "$.activeAction")
        }

        let candidates = body["selectionCandidates"] ?? []
        guard let candidateList = candidates as? [Any] else {
            throw CameraAnalysisV3ValidationFailure(.selectionCandidatesConflict, "$.selectionCandidates")
        }
        if state == "SELECT_SUBJECT" {
            if candidateList.isEmpty {
                throw CameraAnalysisV3ValidationFailure(.selectionCandidatesConflict, "$.selectionCandidates")
            }
        } else if !candidateList.isEmpty {
            throw CameraAnalysisV3ValidationFailure(.selectionCandidatesConflict, "$.selectionCandidates")
        }

        // Frame / transform references.
        let frame = try object(try required(body, "frameReference", "$"), "$.frameReference")
        let frameID = try requiredString(frame, "frameID", "$.frameReference")
        let orientation = try requiredEnum(frame, "orientation", "$.frameReference", CameraAnalysisV3Contract.orientations)
        let mirrored = try requiredBool(frame, "mirrored", "$.frameReference")
        let outputCrop = try validateRegion(try required(frame, "outputCrop", "$.frameReference"), "$.frameReference.outputCrop")
        let transformRef = try requiredString(frame, "transformRef", "$.frameReference")
        guard let transforms = body["transformRefs"] as? [Any], !transforms.isEmpty else {
            throw CameraAnalysisV3ValidationFailure(.transformReferenceMissing, "$.transformRefs")
        }
        let transformList = transforms.compactMap { $0 as? String }
        guard transformList.contains(transformRef) else {
            throw CameraAnalysisV3ValidationFailure(.transformReferenceMissing, "$.frameReference.transformRef")
        }
        var frameIDs: Set<String> = [frameID]
        if let extras = body["additionalFrameIds"] as? [Any] {
            for extra in extras {
                if let value = extra as? String, !value.isEmpty { frameIDs.insert(value) }
            }
        }

        // Entity graph.
        guard let entityList = body["entities"] as? [Any], !entityList.isEmpty else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "$.entities")
        }
        var entityIDs = Set<String>()
        var labels = Set<String>()
        var trackBindings: [String: String] = [:]
        for (index, element) in entityList.enumerated() {
            let path = "$.entities[\(index)]"
            let entity = try object(element, path)
            let entityID = try requiredString(entity, "entityID", path)
            guard entityIDs.insert(entityID).inserted else {
                throw CameraAnalysisV3ValidationFailure(.duplicateEntityID, path)
            }
            labels.insert(try requiredString(entity, "displayLabel", path))
            _ = try requiredEnum(entity, "kind", path, CameraAnalysisV3Contract.entityKinds)
            _ = try requiredEnum(entity, "role", path, CameraAnalysisV3Contract.entityRoles)
            trackBindings[entityID] = try requiredString(entity, "trackID", path)
        }

        var relationIDs = Set<String>()
        var edges: [String: Set<String>] = [:]
        if let relationList = body["relations"] as? [Any] {
            for (index, element) in relationList.enumerated() {
                let path = "$.relations[\(index)]"
                let relation = try object(element, path)
                let relationID = try requiredString(relation, "relationID", path)
                guard relationIDs.insert(relationID).inserted else {
                    throw CameraAnalysisV3ValidationFailure(.duplicateRelationID, path)
                }
                guard let endpoints = relation["endpoints"] as? [Any], !endpoints.isEmpty else {
                    throw CameraAnalysisV3ValidationFailure(.relationEndpointMissing, path)
                }
                var endpointStrings: [String] = []
                for endpoint in endpoints {
                    guard let name = endpoint as? String, entityIDs.contains(name) else {
                        throw CameraAnalysisV3ValidationFailure(.relationEndpointMissing, path)
                    }
                    endpointStrings.append(name)
                }
                if endpointStrings.count >= 2 {
                    var outgoing = edges[endpointStrings[0]] ?? []
                    for tail in endpointStrings.dropFirst() { outgoing.insert(tail) }
                    edges[endpointStrings[0]] = outgoing
                }
            }
        } else if body["relations"] != nil {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "$.relations")
        }
        try detectCycle(edges, "$.relations")

        // Evidence.
        if let evidenceList = body["evidence"] as? [Any] {
            for (index, element) in evidenceList.enumerated() {
                let path = "$.evidence[\(index)]"
                let item = try object(element, path)
                _ = try requiredString(item, "evidenceID", path)
                _ = try requiredEnum(item, "qualificationStatus", path, CameraAnalysisV3Contract.evidenceQualifications)
                if let relationRef = item["relationRef"] as? String, !relationIDs.contains(relationRef) {
                    throw CameraAnalysisV3ValidationFailure(.entityReferenceMissing, "\(path).relationRef")
                }
                if let entityRef = item["entityRef"], !(entityRef is NSNull) {
                    _ = try resolveEntity(entityRef, entityIDs: entityIDs, labels: labels, path: "\(path).entityRef")
                }
                if let revision = item["intentRevision"] as? Int, revision != intentRevision {
                    throw CameraAnalysisV3ValidationFailure(.staleIntentRevision, "\(path).intentRevision")
                }
            }
        } else if body["evidence"] != nil {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "$.evidence")
        }

        // Qualification / release admission.
        var qualificationRef: String?
        let qualification = body["qualification"]
        if state == "CORRECT" {
            guard let qualificationObject = qualification as? [String: Any] else {
                throw CameraAnalysisV3ValidationFailure(.missingQualification, "$.qualification")
            }
            qualificationRef = try requiredString(qualificationObject, "ref", "$.qualification")
            let status = try requiredEnum(qualificationObject, "status", "$.qualification", CameraAnalysisV3Contract.qualificationStatuses)
            guard status == "qualified" else {
                throw CameraAnalysisV3ValidationFailure(.unqualifiedEvidence, "$.qualification.status")
            }
            let artifactKind = try requiredEnum(qualificationObject, "artifactKind", "$.qualification", CameraAnalysisV3Contract.artifactKinds)
            if artifactKind == "research" {
                let admission = qualificationObject["releaseAdmissionRef"] as? String
                guard admission?.isEmpty == false else {
                    throw CameraAnalysisV3ValidationFailure(.researchNotAdmitted, "$.qualification.releaseAdmissionRef")
                }
            }
        } else if let qualificationObject = qualification as? [String: Any] {
            if qualificationObject["artifactKind"] != nil {
                _ = try requiredEnum(qualificationObject, "artifactKind", "$.qualification", CameraAnalysisV3Contract.artifactKinds)
            }
            if qualificationObject["status"] != nil {
                _ = try requiredEnum(qualificationObject, "status", "$.qualification", CameraAnalysisV3Contract.qualificationStatuses)
            }
        }

        // Active action.
        if let action = activeAction as? [String: Any] {
            try validateAction(action, qualificationRef: qualificationRef, intentRevision: intentRevision,
                               entityIDs: entityIDs, labels: labels, relationIDs: relationIDs,
                               trackBindings: trackBindings, frameIDs: frameIDs, outputCrop: outputCrop,
                               phase: phase, frameOrientation: orientation, frameMirrored: mirrored)
        }

        // Verification.
        if let verification = body["verification"] {
            try validateVerification(verification, entityIDs: entityIDs, labels: labels)
        }

        // Coverage / temporality.
        if let coverage = body["coverage"] {
            try validateCoverage(coverage)
        }

        // Record immutability.
        if let record = body["record"] {
            try validateRecord(record, action: activeAction as? [String: Any])
        }
    }

    // MARK: Action validation

    private static func validateAction(_ action: [String: Any], qualificationRef: String?,
                                       intentRevision: Int, entityIDs: Set<String>, labels: Set<String>,
                                       relationIDs: Set<String>, trackBindings: [String: String],
                                       frameIDs: Set<String>, outputCrop: CameraAnalysisV3Region, phase: String,
                                       frameOrientation: String, frameMirrored: Bool) throws {
        let path = "activeAction"
        let operation = try requiredString(action, "operation", path)
        guard CameraAnalysisV3Contract.operations.contains(operation) else {
            throw CameraAnalysisV3ValidationFailure(.unknownOperation, "\(path).operation")
        }
        _ = try requiredString(action, "actionID", path)
        _ = try requiredString(action, "frameRef", path)
        _ = try requiredString(action, "qualificationRef", path)
        _ = try requiredString(action, "verifierRef", path)
        _ = try requiredInt(action, "intentRevision", path)
        guard let targets = action["targetRefs"] as? [Any], !targets.isEmpty else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "\(path).targetRefs")
        }
        guard let protected = action["protectedRefs"] as? [Any] else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "\(path).protectedRefs")
        }
        for (index, ref) in targets.enumerated() {
            _ = try resolveEntity(ref, entityIDs: entityIDs, labels: labels, path: "\(path).targetRefs[\(index)]")
        }
        for (index, ref) in protected.enumerated() {
            _ = try resolveEntity(ref, entityIDs: entityIDs, labels: labels, path: "\(path).protectedRefs[\(index)]")
        }
        let actionFrameRef = try requiredString(action, "frameRef", path)
        guard frameIDs.contains(actionFrameRef) else {
            throw CameraAnalysisV3ValidationFailure(.frameReferenceMissing, "\(path).frameRef")
        }

        let payload = try object(try required(action, "payload", path), "\(path).payload")
        try validatePayload(operation, payload: payload, phase: phase,
                            entityIDs: entityIDs, labels: labels, relationIDs: relationIDs,
                            frameIDs: frameIDs, outputCrop: outputCrop)

        let effectGoal = try object(try required(action, "effectGoal", path), "\(path).effectGoal")
        try validateEffectGoal(effectGoal, entityIDs: entityIDs, labels: labels,
                               relationIDs: relationIDs, outputCrop: outputCrop)

        if let orientationValue = action["frameOrientation"], !(orientationValue is NSNull) {
            let value = try requiredEnum(action, "frameOrientation", path, CameraAnalysisV3Contract.orientations)
            if value != frameOrientation {
                throw CameraAnalysisV3ValidationFailure(.orientationMismatch, "\(path).frameOrientation")
            }
        }
        if let mirroredValue = action["mirrored"], !(mirroredValue is NSNull) {
            guard isJSONBool(mirroredValue) else {
                throw CameraAnalysisV3ValidationFailure(.mirroringMismatch, "\(path).mirrored")
            }
            let value = try requiredBool(action, "mirrored", path)
            if value != frameMirrored {
                throw CameraAnalysisV3ValidationFailure(.mirroringMismatch, "\(path).mirrored")
            }
        }

        let actionRevision = try requiredInt(action, "intentRevision", path)
        guard actionRevision == intentRevision else {
            throw CameraAnalysisV3ValidationFailure(.staleIntentRevision, "\(path).intentRevision")
        }

        let baseline = try object(try required(action, "baseline", path), "\(path).baseline")
        _ = try requiredString(baseline, "actionID", "\(path).baseline")
        if let baselineRevision = baseline["intentRevision"] as? Int {
            guard baselineRevision == intentRevision else {
                throw CameraAnalysisV3ValidationFailure(.staleIntentRevision, "\(path).baseline.intentRevision")
            }
        } else {
            throw CameraAnalysisV3ValidationFailure(.staleIntentRevision, "\(path).baseline.intentRevision")
        }
        if let bindings = baseline["trackBindings"] as? [String: Any] {
            for (entityID, trackID) in bindings {
                if trackBindings[entityID] != (trackID as? String) {
                    throw CameraAnalysisV3ValidationFailure(.identityLost, "\(path).baseline.trackBindings.\(entityID)")
                }
            }
        }

        if let qualificationRef, (action["qualificationRef"] as? String) != qualificationRef {
            throw CameraAnalysisV3ValidationFailure(.unqualifiedEvidence, "\(path).qualificationRef")
        }
    }

    // MARK: Payload validation

    private static func validatePayload(_ operation: String, payload: [String: Any], phase: String,
                                        entityIDs: Set<String>, labels: Set<String>, relationIDs: Set<String>,
                                        frameIDs: Set<String>, outputCrop: CameraAnalysisV3Region) throws {
        do {
            try validatePayloadInner(operation, payload: payload, phase: phase, entityIDs: entityIDs,
                                     labels: labels, relationIDs: relationIDs, frameIDs: frameIDs,
                                     outputCrop: outputCrop)
        } catch let failure as CameraAnalysisV3ValidationFailure where failure.reason == .missingRequiredField {
            throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, failure.path, failure.detail)
        }
    }

    private static func validatePayloadInner(_ operation: String, payload: [String: Any], phase: String,
                                             entityIDs: Set<String>, labels: Set<String>, relationIDs: Set<String>,
                                             frameIDs: Set<String>, outputCrop: CameraAnalysisV3Region) throws {
        let path = "activeAction.payload"

        func enumValue(_ key: String, _ allowed: Set<String>) throws -> String {
            try requiredEnum(payload, key, path, allowed)
        }
        func entityRef(_ key: String, required: Bool = true) throws -> String? {
            guard let raw = payload[key], !(raw is NSNull) else {
                if required { throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).\(key)") }
                return nil
            }
            return try resolveEntity(raw, entityIDs: entityIDs, labels: labels, path: "\(path).\(key)")
        }

        switch operation {
        case "reframe_subject":
            let region = try validateRegion(try required(payload, "targetRegion", path), "\(path).targetRegion")
            guard outputCrop.contains(region) else {
                throw CameraAnalysisV3ValidationFailure(.outputCropMismatch, path)
            }

        case "change_subject_scale":
            _ = try enumValue("method", ["camera_distance", "zoom"])
            _ = try enumValue("desired", ["larger", "smaller"])
            let ratio = try finiteNumber(try required(payload, "targetAreaRatio", path), "\(path).targetAreaRatio")
            guard ratio > 0.0 && ratio <= 1.0 else {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).targetAreaRatio")
            }

        case "level_frame":
            _ = try enumValue("rotation", ["clockwise", "counterclockwise"])
            _ = try finiteNumber(try required(payload, "targetHorizonDegrees", path), "\(path).targetHorizonDegrees")

        case "reposition_entity":
            let destination = try enumValue("destination", ["screen_goal", "relative_depth"])
            if destination == "screen_goal" {
                let region = try validateRegion(try required(payload, "targetRegion", path), "\(path).targetRegion")
                guard outputCrop.contains(region) else {
                    throw CameraAnalysisV3ValidationFailure(.outputCropMismatch, path)
                }
                guard let fixedCamera = payload["fixedCamera"],
                      isJSONBool(fixedCamera), (fixedCamera as? Bool) == true else {
                    throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).fixedCamera")
                }
            } else {
                _ = try requiredString(payload, "relationRef", path)
                _ = try requiredString(payload, "referencePoint", path)
            }

        case "rotate_entity":
            let hasToward = payload["towardEntityRef"] != nil && !(payload["towardEntityRef"] is NSNull)
            let hasReveal = payload["revealRegion"] != nil && !(payload["revealRegion"] is NSNull)
            guard hasToward != hasReveal else {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).toward/reveal")
            }
            if hasToward {
                _ = try entityRef("towardEntityRef")
            } else {
                _ = try validateRegion(payload["revealRegion"], "\(path).revealRegion")
            }
            let turn = try enumValue("turn", ["small_probe", "measured"])
            let hasAngle = payload["angleDegrees"] != nil && !(payload["angleDegrees"] is NSNull)
            if turn == "measured" {
                guard hasAngle else {
                    throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).angleDegrees")
                }
                _ = try finiteNumber(payload["angleDegrees"] as Any, "\(path).angleDegrees")
            } else if hasAngle {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).angleDegrees")
            }

        case "exclude_entity":
            _ = try validateRegion(try required(payload, "fromRegion", path), "\(path).fromRegion")

        case "reposition_camera":
            let change = try enumValue("change", ["raise", "lower", "lateral_probe"])
            _ = try validateRegion(try required(payload, "goalRegion", path), "\(path).goalRegion")
            guard (payload["step"] as? String) == "small_probe" else {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).step")
            }
            if change == "lateral_probe" {
                _ = try enumValue("lateralDirection", ["left", "right"])
            } else if payload["lateralDirection"] != nil && !(payload["lateralDirection"] is NSNull) {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).lateralDirection")
            }

        case "adjust_light":
            let change = try enumValue("change", ["dim", "brighten", "switch_off", "add_fill", "add_background"])
            _ = try entityRef("receiverEntityRef")
            if ["dim", "brighten", "switch_off"].contains(change) {
                _ = try entityRef("sourceEntityRef")
            }

        case "adjust_exposure":
            _ = try enumValue("change", ["increase", "decrease"])
            guard (payload["parameter"] as? String) == "exposure_bias" else {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).parameter")
            }
            if let ev = payload["suggestedEV"], !(ev is NSNull) {
                _ = try finiteNumber(ev, "\(path).suggestedEV")
            }

        case "refocus_subject":
            _ = try validateRegion(try required(payload, "focusRegion", path), "\(path).focusRegion")

        case "hold_steady":
            _ = try requiredString(payload, "windowPolicyRef", path)

        case "set_capture_parameter":
            let parameter = try enumValue("parameter", CameraAnalysisV3Contract.captureParameters)
            guard let rawValue = payload["value"], !(rawValue is NSNull) else {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).value")
            }
            if CameraAnalysisV3Contract.lockParameters.contains(parameter) {
                guard isJSONBool(rawValue), (rawValue as? Bool) != nil else {
                    throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).value")
                }
            } else {
                guard !isJSONBool(rawValue) else {
                    throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).value")
                }
                let numeric = try finiteNumber(rawValue, "\(path).value")
                guard numeric > 0.0 else {
                    throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).value")
                }
            }

        case "change_lens":
            _ = try requiredString(payload, "deviceLensID", path)

        case "reserve_output_region":
            let region = try validateRegion(try required(payload, "region", path), "\(path).region")
            guard outputCrop.contains(region) else {
                throw CameraAnalysisV3ValidationFailure(.outputCropMismatch, path)
            }

        case "wait_for_clearance":
            _ = try validateRegion(try required(payload, "region", path), "\(path).region")
            guard let blockers = payload["blockerRefs"] as? [Any], !blockers.isEmpty else {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).blockerRefs")
            }
            for (index, ref) in blockers.enumerated() {
                _ = try resolveEntity(ref, entityIDs: entityIDs, labels: labels, path: "\(path).blockerRefs[\(index)]")
            }
            _ = try requiredString(payload, "windowPolicyRef", path)

        case "select_capture_moment":
            let frameRef = try requiredString(payload, "frameRef", path)
            guard frameIDs.contains(frameRef) else {
                throw CameraAnalysisV3ValidationFailure(.frameReferenceMissing, "\(path).frameRef")
            }
            guard phase == "review" else {
                throw CameraAnalysisV3ValidationFailure(.invalidActionPayload, "\(path).frameRef")
            }

        case "maintain_subject_zone":
            _ = try validateRegion(try required(payload, "region", path), "\(path).region")
            _ = try requiredString(payload, "windowPolicyRef", path)

        case "smooth_camera_motion":
            _ = try requiredString(payload, "windowPolicyRef", path)

        case "plan_motion_endpoints":
            for key in ["startFrameRef", "endFrameRef"] {
                let frameRef = try requiredString(payload, key, path)
                guard frameIDs.contains(frameRef) else {
                    throw CameraAnalysisV3ValidationFailure(.frameReferenceMissing, "\(path).\(key)")
                }
            }
            _ = try requiredString(payload, "holdPolicyRef", path)

        case "clear_lens_obstruction":
            _ = try validateRegion(try required(payload, "obstructionRegion", path), "\(path).obstructionRegion")

        default:
            throw CameraAnalysisV3ValidationFailure(.unknownOperation, path)
        }
    }

    // MARK: Effect goal / verification / coverage / record

    private static func validateEffectGoal(_ goal: [String: Any], entityIDs: Set<String>, labels: Set<String>,
                                           relationIDs: Set<String>, outputCrop: CameraAnalysisV3Region) throws {
        let path = "activeAction.effectGoal"
        _ = try requiredString(goal, "metricID", path)
        guard let refs = goal["targetEntityRefs"] as? [Any], !refs.isEmpty else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "\(path).targetEntityRefs")
        }
        for (index, ref) in refs.enumerated() {
            _ = try resolveEntity(ref, entityIDs: entityIDs, labels: labels, path: "\(path).targetEntityRefs[\(index)]")
        }
        _ = try requiredEnum(goal, "desired", path, CameraAnalysisV3Contract.desiredValues)
        _ = try requiredString(goal, "policyRef", path)
        if let relationRef = goal["relationRef"] as? String, !relationIDs.contains(relationRef) {
            throw CameraAnalysisV3ValidationFailure(.entityReferenceMissing, "\(path).relationRef")
        }
        if let region = goal["targetRegion"], !(region is NSNull) {
            let validated = try validateRegion(region, "\(path).targetRegion")
            guard outputCrop.contains(validated) else {
                throw CameraAnalysisV3ValidationFailure(.outputCropMismatch, path)
            }
        }
    }

    private static func validateVerification(_ value: Any, entityIDs: Set<String>, labels: Set<String>) throws {
        let path = "$.verification"
        let verification = try object(value, path)
        let outcome = try requiredEnum(verification, "outcome", path, CameraAnalysisV3Contract.verificationOutcomes)
        let effectDelta = try finiteNumber(try required(verification, "effectDelta", path), "\(path).effectDelta")
        let deadband = try finiteNumber(try required(verification, "deadband", path), "\(path).deadband")
        guard deadband >= 0.0 else {
            throw CameraAnalysisV3ValidationFailure(.nonFiniteNumber, "\(path).deadband")
        }
        if let goalSatisfied = verification["goalSatisfied"], !(goalSatisfied is NSNull) {
            _ = try requiredBool(verification, "goalSatisfied", path)
        }
        if outcome == "improved" {
            guard effectDelta > deadband else {
                throw CameraAnalysisV3ValidationFailure(.claimedImprovementWithoutDelta, "\(path).effectDelta")
            }
            if let deltas = verification["protectedDeltas"] as? [Any] {
                for (index, element) in deltas.enumerated() {
                    let deltaPath = "\(path).protectedDeltas[\(index)]"
                    let delta = try object(element, deltaPath)
                    _ = try resolveEntity(try required(delta, "entityRef", deltaPath),
                                          entityIDs: entityIDs, labels: labels, path: "\(deltaPath).entityRef")
                    let amount = try finiteNumber(try required(delta, "delta", deltaPath), "\(deltaPath).delta")
                    guard amount <= 0.0 else {
                        throw CameraAnalysisV3ValidationFailure(.protectedRegression, "\(deltaPath).delta")
                    }
                }
            } else if verification["protectedDeltas"] != nil && !(verification["protectedDeltas"] is NSNull) {
                throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "\(path).protectedDeltas")
            }
        }
    }

    private static func validateCoverage(_ value: Any) throws {
        let path = "$.coverage"
        let coverage = try object(value, path)
        let kind = try requiredEnum(coverage, "kind", path, CameraAnalysisV3Contract.coverageKinds)
        _ = try requiredInt(coverage, "contentRevision", path)
        guard CameraAnalysisV3Contract.temporalCoverageKinds.contains(kind) else { return }
        guard let pts = coverage["pts"] as? [Any], !pts.isEmpty else {
            throw CameraAnalysisV3ValidationFailure(.missingTemporalEvidence, "\(path).pts")
        }
        for (index, value) in pts.enumerated() {
            let valuePath = "\(path).pts[\(index)]"
            if isJSONBool(value) {
                throw CameraAnalysisV3ValidationFailure(.nonFiniteNumber, valuePath)
            }
            if value is Int { continue }
            if let text = value as? String, Int(text) != nil { continue }
            throw CameraAnalysisV3ValidationFailure(.nonFiniteNumber, valuePath)
        }
    }

    private static func validateRecord(_ value: Any, action: [String: Any]?) throws {
        let path = "$.record"
        let record = try object(value, path)
        _ = try requiredString(record, "recordID", path)
        _ = try requiredInt(record, "revision", path)
        let frozen = try requiredBool(record, "frozen", path)
        guard frozen else { return }
        guard let action = action else {
            throw CameraAnalysisV3ValidationFailure(.frozenRecordMutation, path)
        }
        guard let baseline = record["baseline"] as? [String: Any] else {
            throw CameraAnalysisV3ValidationFailure(.frozenRecordMutation, "\(path).baseline")
        }
        guard (baseline["actionID"] as? String) == (action["actionID"] as? String) else {
            throw CameraAnalysisV3ValidationFailure(.frozenRecordMutation, "\(path).baseline.actionID")
        }
        guard stringArraysEqual(baseline["targetRefs"], action["targetRefs"]) else {
            throw CameraAnalysisV3ValidationFailure(.frozenRecordMutation, "\(path).baseline.targetRefs")
        }
        guard stringArraysEqual(baseline["protectedRefs"], action["protectedRefs"]) else {
            throw CameraAnalysisV3ValidationFailure(.frozenRecordMutation, "\(path).baseline.protectedRefs")
        }
    }

    // MARK: Region / primitives

    @discardableResult
    static func validateRegion(_ value: Any?, _ path: String) throws -> CameraAnalysisV3Region {
        let region = try object(value, path)
        var coords: [String: Double] = [:]
        for key in ["x", "y", "width", "height"] {
            guard let raw = region[key], !(raw is NSNull) else {
                throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "\(path).\(key)")
            }
            let (number, reason) = coerceDouble(raw)
            if let reason {
                throw CameraAnalysisV3ValidationFailure(reason, "\(path).\(key)")
            }
            guard let number, number.isFinite else {
                throw CameraAnalysisV3ValidationFailure(.regionNonFinite, "\(path).\(key)")
            }
            coords[key] = number
        }
        for (key, number) in coords where number < 0.0 || number > 1.0 {
            throw CameraAnalysisV3ValidationFailure(.regionOutOfRange, "\(path).\(key)")
        }
        guard let x = coords["x"], let y = coords["y"], let width = coords["width"], let height = coords["height"] else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, path)
        }
        guard width > 0.0, height > 0.0 else {
            throw CameraAnalysisV3ValidationFailure(.regionDegenerate, path)
        }
        let epsilon = 1e-9
        guard x + width <= 1.0 + epsilon, y + height <= 1.0 + epsilon else {
            throw CameraAnalysisV3ValidationFailure(.regionOutOfRange, path)
        }
        return CameraAnalysisV3Region(x: x, y: y, width: width, height: height)
    }

    private static func resolveEntity(_ value: Any, entityIDs: Set<String>, labels: Set<String>, path: String) throws -> String {
        guard let ref = value as? String, !ref.isEmpty else {
            throw CameraAnalysisV3ValidationFailure(.entityReferenceMissing, path)
        }
        if entityIDs.contains(ref) { return ref }
        if labels.contains(ref) {
            throw CameraAnalysisV3ValidationFailure(.labelNotIdentity, path)
        }
        throw CameraAnalysisV3ValidationFailure(.entityReferenceMissing, path)
    }

    private static func coerceDouble(_ value: Any) -> (Double?, CameraAnalysisV3ValidationReason?) {
        if isJSONBool(value) { return (nil, .regionNotNumeric) }
        if let number = value as? NSNumber { return (number.doubleValue, nil) }
        if let text = value as? String {
            if let number = Double(text) { return (number, nil) }
            return (nil, .regionNotNumeric)
        }
        return (nil, .regionNotNumeric)
    }

    private static func finiteNumber(_ value: Any, _ path: String) throws -> Double {
        if isJSONBool(value) {
            throw CameraAnalysisV3ValidationFailure(.nonFiniteNumber, path)
        }
        let number: Double?
        if let raw = value as? NSNumber {
            number = raw.doubleValue
        } else if let text = value as? String {
            number = Double(text)
        } else {
            number = nil
        }
        guard let number, number.isFinite else {
            throw CameraAnalysisV3ValidationFailure(.nonFiniteNumber, path)
        }
        return number
    }

    // MARK: Access helpers

    private static func object(_ value: Any?, _ path: String) throws -> [String: Any] {
        guard let value, let object = value as? [String: Any] else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, path)
        }
        return object
    }

    private static func required(_ object: [String: Any], _ key: String, _ path: String) throws -> Any {
        guard let value = object[key], !(value is NSNull) else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "\(path).\(key)")
        }
        return value
    }

    private static func requiredString(_ object: [String: Any], _ key: String, _ path: String) throws -> String {
        let value = try required(object, key, path)
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "\(path).\(key)")
        }
        return text
    }

    private static func requiredInt(_ object: [String: Any], _ key: String, _ path: String) throws -> Int {
        let value = try required(object, key, path)
        guard !isJSONBool(value), let number = value as? Int else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "\(path).\(key)")
        }
        return number
    }

    private static func requiredBool(_ object: [String: Any], _ key: String, _ path: String) throws -> Bool {
        let value = try required(object, key, path)
        guard isJSONBool(value), let bool = value as? Bool else {
            throw CameraAnalysisV3ValidationFailure(.unknownEnumValue, "\(path).\(key)")
        }
        return bool
    }

    private static func requiredEnum(_ object: [String: Any], _ key: String, _ path: String, _ allowed: Set<String>) throws -> String {
        let value = try required(object, key, path)
        guard let text = value as? String, allowed.contains(text) else {
            throw CameraAnalysisV3ValidationFailure(.unknownEnumValue, "\(path).\(key)")
        }
        return text
    }

    private static func isJSONBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func stringArraysEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        let left = (lhs as? [Any])?.compactMap { $0 as? String }
        let right = (rhs as? [Any])?.compactMap { $0 as? String }
        return left == right
    }

    private static func detectCycle(_ edges: [String: Set<String>], _ path: String) throws {
        // 0 = white, 1 = gray, 2 = black
        var colors: [String: Int] = [:]

        func visit(_ node: String) throws {
            colors[node] = 1
            for neighbor in edges[node] ?? [] {
                switch colors[neighbor] ?? 0 {
                case 1:
                    throw CameraAnalysisV3ValidationFailure(.entityGraphCycle, path)
                case 0:
                    try visit(neighbor)
                default:
                    break
                }
            }
            colors[node] = 2
        }

        for node in edges.keys where (colors[node] ?? 0) == 0 {
            try visit(node)
        }
    }
}

// MARK: - Builder: validated JSON -> executable types

enum CameraAnalysisV3ContractBuilder {

    static func build(_ raw: Any) throws -> CameraAnalysisV3Envelope {
        guard let body = raw as? [String: Any] else {
            throw CameraAnalysisV3ValidationFailure(.invalidJSON, "$")
        }
        func string(_ key: String) throws -> String {
            guard let value = body[key] as? String else {
                throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "$.\(key)")
            }
            return value
        }
        func int(_ key: String) throws -> Int {
            guard let value = body[key] as? Int else {
                throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "$.\(key)")
            }
            return value
        }
        let frame = body["frameReference"] as? [String: Any] ?? [:]
        let frameReference = CameraAnalysisV3FrameReference(
            frameID: try stringValue(frame["frameID"]),
            orientation: CameraAnalysisV3Orientation(rawValue: frame["orientation"] as? String ?? "") ?? .portrait,
            mirrored: frame["mirrored"] as? Bool ?? false,
            outputCrop: try regionValue(frame["outputCrop"]),
            transformRef: try stringValue(frame["transformRef"])
        )
        let entities = try (body["entities"] as? [Any] ?? []).map { element -> CameraAnalysisV3Entity in
            let entity = element as? [String: Any] ?? [:]
            return CameraAnalysisV3Entity(
                entityID: try stringValue(entity["entityID"]),
                kind: CameraAnalysisV3EntityKind(rawValue: entity["kind"] as? String ?? "") ?? .object,
                displayLabel: try stringValue(entity["displayLabel"]),
                trackID: try stringValue(entity["trackID"]),
                role: CameraAnalysisV3EntityRole(rawValue: entity["role"] as? String ?? "") ?? .context
            )
        }
        let relations = try (body["relations"] as? [Any] ?? []).map { element -> CameraAnalysisV3Relation in
            let relation = element as? [String: Any] ?? [:]
            return CameraAnalysisV3Relation(
                relationID: try stringValue(relation["relationID"]),
                kind: relation["kind"] as? String ?? "",
                endpoints: (relation["endpoints"] as? [Any] ?? []).compactMap { $0 as? String }
            )
        }
        let evidence = try (body["evidence"] as? [Any] ?? []).map { element -> CameraAnalysisV3Evidence in
            let item = element as? [String: Any] ?? [:]
            return CameraAnalysisV3Evidence(
                evidenceID: try stringValue(item["evidenceID"]),
                qualificationStatus: CameraAnalysisV3EvidenceQualification(rawValue: item["qualificationStatus"] as? String ?? "") ?? .unknown,
                relationRef: item["relationRef"] as? String
            )
        }
        var qualification: CameraAnalysisV3Qualification?
        if let item = body["qualification"] as? [String: Any], let ref = item["ref"] as? String {
            qualification = CameraAnalysisV3Qualification(
                ref: ref,
                status: item["status"] as? String ?? "",
                artifactKind: CameraAnalysisV3ArtifactKind(rawValue: item["artifactKind"] as? String ?? "") ?? .production,
                releaseAdmissionRef: item["releaseAdmissionRef"] as? String
            )
        }
        var activeAction: CameraAnalysisV3Action?
        if let action = body["activeAction"] as? [String: Any] {
            activeAction = try buildAction(action)
        }
        var verification: CameraAnalysisV3Verification?
        if let item = body["verification"] as? [String: Any] {
            verification = CameraAnalysisV3Verification(
                outcome: CameraAnalysisV3VerificationOutcome(rawValue: item["outcome"] as? String ?? "") ?? .unchanged,
                effectDelta: asNumber(item["effectDelta"]) ?? 0,
                deadband: asNumber(item["deadband"]) ?? 0,
                goalSatisfied: item["goalSatisfied"] as? Bool,
                protectedDeltas: (item["protectedDeltas"] as? [Any] ?? []).compactMap { element in
                    guard let delta = element as? [String: Any], let ref = delta["entityRef"] as? String else { return nil }
                    return CameraAnalysisV3ProtectedDelta(entityRef: ref, delta: asNumber(delta["delta"]) ?? 0)
                }
            )
        }
        var coverage: CameraAnalysisV3Coverage?
        if let item = body["coverage"] as? [String: Any] {
            coverage = CameraAnalysisV3Coverage(
                kind: CameraAnalysisV3CoverageKind(rawValue: item["kind"] as? String ?? "") ?? .singleFrame,
                pts: (item["pts"] as? [Any] ?? []).compactMap { mediaTime($0) },
                contentRevision: item["contentRevision"] as? Int ?? 0
            )
        }
        var record: CameraAnalysisV3Record?
        if let item = body["record"] as? [String: Any] {
            var baseline: CameraAnalysisV3RecordBaseline?
            if let raw = item["baseline"] as? [String: Any] {
                baseline = CameraAnalysisV3RecordBaseline(
                    actionID: raw["actionID"] as? String ?? "",
                    targetRefs: (raw["targetRefs"] as? [Any] ?? []).compactMap { $0 as? String },
                    protectedRefs: (raw["protectedRefs"] as? [Any] ?? []).compactMap { $0 as? String }
                )
            }
            record = CameraAnalysisV3Record(
                recordID: item["recordID"] as? String ?? "",
                revision: item["revision"] as? Int ?? 0,
                frozen: item["frozen"] as? Bool ?? false,
                baseline: baseline
            )
        }
        return CameraAnalysisV3Envelope(
            schemaVersion: try string("schemaVersion"),
            analysisID: try string("analysisID"),
            sessionID: try string("sessionID"),
            generation: try int("generation"),
            intentRevision: try int("intentRevision"),
            phase: CameraAnalysisV3Phase(rawValue: body["phase"] as? String ?? "") ?? .live,
            state: CameraAnalysisV3State(rawValue: body["state"] as? String ?? "") ?? .abstain,
            reasonCode: CameraAnalysisV3ReasonCode(rawValue: body["reasonCode"] as? String ?? "") ?? .ready,
            frameReference: frameReference,
            transformRefs: (body["transformRefs"] as? [Any] ?? []).compactMap { $0 as? String },
            entities: entities,
            relations: relations,
            evidence: evidence,
            qualification: qualification,
            activeAction: activeAction,
            selectionCandidates: (body["selectionCandidates"] as? [Any] ?? []).compactMap { $0 as? String },
            verification: verification,
            coverage: coverage,
            record: record
        )
    }

    private static func buildAction(_ action: [String: Any]) throws -> CameraAnalysisV3Action {
        let payload = action["payload"] as? [String: Any] ?? [:]
        let goal = action["effectGoal"] as? [String: Any] ?? [:]
        let baseline = action["baseline"] as? [String: Any] ?? [:]
        var trackBindings: [String: String] = [:]
        if let bindings = baseline["trackBindings"] as? [String: Any] {
            for (key, value) in bindings {
                if let text = value as? String { trackBindings[key] = text }
            }
        }
        var booleanValue: Bool?
        var numberValue: Double?
        if let value = payload["value"], !(value is NSNull) {
            if isBool(value) { booleanValue = value as? Bool } else { numberValue = asNumber(value) }
        }
        let parsedPayload = CameraAnalysisV3ActionPayload(
            targetRegion: try optionalRegion(payload["targetRegion"]),
            destination: payload["destination"] as? String,
            fixedCamera: payload["fixedCamera"] as? Bool,
            method: payload["method"] as? String,
            desired: payload["desired"] as? String,
            targetAreaRatio: asNumber(payload["targetAreaRatio"]),
            rotation: payload["rotation"] as? String,
            targetHorizonDegrees: asNumber(payload["targetHorizonDegrees"]),
            relationRef: payload["relationRef"] as? String,
            referencePoint: payload["referencePoint"] as? String,
            towardEntityRef: payload["towardEntityRef"] as? String,
            revealRegion: try optionalRegion(payload["revealRegion"]),
            turn: payload["turn"] as? String,
            angleDegrees: asNumber(payload["angleDegrees"]),
            change: payload["change"] as? String,
            goalRegion: try optionalRegion(payload["goalRegion"]),
            step: payload["step"] as? String,
            lateralDirection: payload["lateralDirection"] as? String,
            receiverEntityRef: payload["receiverEntityRef"] as? String,
            sourceEntityRef: payload["sourceEntityRef"] as? String,
            parameter: payload["parameter"] as? String,
            booleanValue: booleanValue,
            numberValue: numberValue,
            suggestedEV: asNumber(payload["suggestedEV"]),
            focusRegion: try optionalRegion(payload["focusRegion"]),
            windowPolicyRef: payload["windowPolicyRef"] as? String,
            deviceLensID: payload["deviceLensID"] as? String,
            blockerRefs: (payload["blockerRefs"] as? [Any] ?? []).compactMap { $0 as? String },
            fromRegion: try optionalRegion(payload["fromRegion"]),
            obstructionRegion: try optionalRegion(payload["obstructionRegion"]),
            startFrameRef: payload["startFrameRef"] as? String,
            endFrameRef: payload["endFrameRef"] as? String,
            holdPolicyRef: payload["holdPolicyRef"] as? String,
            region: try optionalRegion(payload["region"])
        )
        let effectGoal = CameraAnalysisV3EffectGoal(
            metricID: goal["metricID"] as? String ?? "",
            targetEntityRefs: (goal["targetEntityRefs"] as? [Any] ?? []).compactMap { $0 as? String },
            relationRef: goal["relationRef"] as? String,
            desired: CameraAnalysisV3Desired(rawValue: goal["desired"] as? String ?? "") ?? .preserve,
            targetRegion: try optionalRegion(goal["targetRegion"]),
            policyRef: goal["policyRef"] as? String ?? ""
        )
        let parsedBaseline = CameraAnalysisV3ActionBaseline(
            actionID: baseline["actionID"] as? String ?? "",
            targetRefs: (baseline["targetRefs"] as? [Any] ?? []).compactMap { $0 as? String },
            protectedRefs: (baseline["protectedRefs"] as? [Any] ?? []).compactMap { $0 as? String },
            intentRevision: baseline["intentRevision"] as? Int ?? 0,
            trackBindings: trackBindings
        )
        return CameraAnalysisV3Action(
            actionID: action["actionID"] as? String ?? "",
            operation: action["operation"] as? String ?? "",
            intentRevision: action["intentRevision"] as? Int ?? 0,
            frameRef: action["frameRef"] as? String ?? "",
            targetRefs: (action["targetRefs"] as? [Any] ?? []).compactMap { $0 as? String },
            protectedRefs: (action["protectedRefs"] as? [Any] ?? []).compactMap { $0 as? String },
            qualificationRef: action["qualificationRef"] as? String ?? "",
            verifierRef: action["verifierRef"] as? String ?? "",
            payload: parsedPayload,
            effectGoal: effectGoal,
            baseline: parsedBaseline,
            frameOrientation: (action["frameOrientation"] as? String).flatMap(CameraAnalysisV3Orientation.init(rawValue:)),
            mirrored: action["mirrored"] as? Bool
        )
    }

    private static func optionalRegion(_ value: Any?) throws -> CameraAnalysisV3Region? {
        guard let value, !(value is NSNull) else { return nil }
        return try CameraAnalysisV3ContractValidator.validateRegion(value, "region")
    }

    private static func regionValue(_ value: Any?) throws -> CameraAnalysisV3Region {
        try CameraAnalysisV3ContractValidator.validateRegion(value, "region")
    }

    private static func stringValue(_ value: Any?) throws -> String {
        guard let text = value as? String else {
            throw CameraAnalysisV3ValidationFailure(.missingRequiredField, "value")
        }
        return text
    }

    private static func asNumber(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func mediaTime(_ value: Any) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) }
        return nil
    }

    private static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
