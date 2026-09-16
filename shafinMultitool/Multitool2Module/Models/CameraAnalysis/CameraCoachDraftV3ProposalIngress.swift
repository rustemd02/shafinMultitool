#if DEBUG

import Foundation

// Research/debug-only. This is not a v3 runtime decoder and is not wired to
// the production provider, pipeline, or planner. It admits only a single-frame
// two-object visual subset whose output remains an unadmitted projection.
//
// C09 ingress side: request sendability (mandatory limits, safe attachments,
// explicit-request/consent gates), correlation-tuple admission, bounded
// proposal validation with dependent removal, and strict rejection of any
// provider field that claims a decision the local owner holds.

enum CameraCoachDraftV3SchemaVersion: String, Codable, Sendable {
    case s2Draft1 = "camera-coach.vlm-evidence.s2-draft.1"
}

enum CameraCoachDraftV3ResponseStatus: String, Codable, Sendable {
    case completed
    case refused
    case unavailable
}

enum CameraCoachDraftV3Coverage: String, Codable, Sendable {
    case singleFrame = "single_frame"
}

enum CameraCoachDraftV3IngressProfile: String, Codable, Sendable {
    case twoObjectLocalGroundedObservation = "two_object_local_grounded_observation"
}

enum CameraCoachDraftV3LocalInputMode: String, Codable, Sendable {
    case structuredOnly = "structured_only"
    case redactedVisual = "redacted_visual"
    case localAuthorizedStill = "local_authorized_still"
}

enum CameraCoachDraftV3RegionSpace: String, Codable, Sendable {
    case orientedFrame = "oriented_frame"
}

enum CameraCoachDraftV3ReferenceSpace: String, Codable, Sendable {
    case localEntity = "local_entity"
    case entityProposal = "entity_proposal"
}

enum CameraCoachDraftV3ObjectDimension: String, Codable, Sendable {
    case clutter
    case backgroundSeparation = "background_separation"

    var existingDimension: VLMVisualEvidenceDimension {
        switch self {
        case .clutter: return .clutter
        case .backgroundSeparation: return .backgroundSeparation
        }
    }
}

enum CameraCoachDraftV3ObjectProblem: String, Codable, Sendable {
    case objectConflictsWithSubject = "object_conflicts_with_subject"

    var existingProblem: VisualProblemType {
        switch self {
        case .objectConflictsWithSubject: return .objectConflictsWithSubject
        }
    }
}

enum CameraCoachDraftV3RelationType: String, Codable, Sendable {
    case competesForAttention = "competes_for_attention"

    var existingRelation: VLMEntityRelationType {
        switch self {
        case .competesForAttention: return .competesWith
        }
    }
}

/// Attachments are processed local versions handed to transport, never a URL
/// produced by the model. `opaqueRef` is issued by the transport boundary.
enum CameraCoachDraftV3AttachmentSource: String, Codable, Sendable {
    case locallyProcessedVersion = "locally_processed_version"
}

enum CameraCoachDraftV3IngressViolation: String, Codable, Sendable, Hashable {
    // Correlation / staleness
    case correlationMismatch = "correlation_mismatch"
    case requestMismatch = "request_mismatch"
    case schemaVersionMismatch = "schema_version_mismatch"
    case staleFrame = "stale_frame"
    case staleRequest = "stale_request"
    case invalidIdentifier = "invalid_identifier"
    // Bounds and limits
    case missingLimits = "missing_limits"
    case limitsExceeded = "limits_exceeded"
    case outputTokensExceeded = "output_tokens_exceeded"
    case invalidOutputBytes = "invalid_output_bytes"
    // Privacy / attachments / egress
    case privacyPolicyBlocked = "privacy_policy_blocked"
    case consentRevoked = "consent_revoked"
    case explicitRequestRequired = "explicit_request_required"
    case unsafeAttachment = "unsafe_attachment"
    case attachmentURLNotAllowed = "attachment_url_not_allowed"
    case redactedRegionClaim = "redacted_region_claim"
    // Proposals
    case invalidRegion = "invalid_region"
    case invalidConfidence = "invalid_confidence"
    case invalidStatus = "invalid_status"
    case unsupportedCoverage = "unsupported_coverage"
    case unsupportedProfile = "unsupported_profile"
    case proposalLimitExceeded = "proposal_limit_exceeded"
    case duplicateProposalID = "duplicate_proposal_id"
    case unknownEntityReference = "unknown_entity_reference"
    case groundingMissing = "grounding_missing"
    case groundingKindMismatch = "grounding_kind_mismatch"
    case groundingMismatch = "grounding_mismatch"
    case groundingAlias = "grounding_alias"
    case invalidRelationEndpoint = "invalid_relation_endpoint"
    case invalidEvidence = "invalid_evidence"
    case dependentProposalRemoved = "dependent_proposal_removed"
    case unsupportedConversion = "unsupported_conversion"
    // Provider ownership
    case providerOwnedField = "provider_owned_field"
}

struct CameraCoachDraftV3Correlation: Codable, Equatable, Sendable {
    let requestID: String
    let analysisID: String
    let sessionID: String
    let generation: UInt64
    let sceneID: String
    let intentRevision: UInt64
    let anchorFrameRef: String
    let anchorTransformRef: String
    let catalogVersion: String
    let policyVersion: String
    let coverage: CameraCoachDraftV3Coverage
}

struct CameraCoachDraftV3Reference: Codable, Equatable, Sendable {
    let space: CameraCoachDraftV3ReferenceSpace
    let value: String

    static func localEntity(_ value: String) -> Self {
        Self(space: .localEntity, value: value)
    }

    static func entityProposal(_ value: String) -> Self {
        Self(space: .entityProposal, value: value)
    }
}

/// Unlike `NormalizedRect`, this type never clamps untrusted coordinates.
struct CameraCoachDraftV3RawRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var isValidNormalizedRect: Bool {
        [x, y, width, height].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1 && y + height <= 1
    }

    func contains(_ other: CameraCoachDraftV3RawRect) -> Bool {
        isValidNormalizedRect && other.isValidNormalizedRect
            && other.x >= x && other.y >= y
            && other.x + other.width <= x + width
            && other.y + other.height <= y + height
    }
}

struct CameraCoachDraftV3Region: Codable, Equatable, Sendable {
    let frameRef: String
    let space: CameraCoachDraftV3RegionSpace
    let transformRef: String
    let rect: CameraCoachDraftV3RawRect
}

/// Declared by the local transport adapter, never by the model.
struct CameraCoachDraftV3SafeAttachment: Codable, Equatable, Sendable {
    let frameRef: String
    let transformRef: String
    let coverage: CameraCoachDraftV3Coverage
    let sourceKind: CameraCoachDraftV3AttachmentSource
    let opaqueRef: String
    let longEdgePx: Int
    let byteCount: Int
    let exifStripped: Bool
    let redactionApplied: Bool
    /// Region that remains visible after redaction. Required for redacted input
    /// so that no conclusion about a hidden area can be justified.
    let visibleRegion: CameraCoachDraftV3RawRect?

    var looksLikeURL: Bool {
        let lowered = opaqueRef.lowercased()
        return lowered.contains("://")
            || lowered.hasPrefix("http:")
            || lowered.hasPrefix("https:")
            || lowered.hasPrefix("file:")
            || lowered.hasPrefix("data:")
    }
}

/// Bounds the transport may use for a single s2 request. A request without a
/// complete limit set is never sent; exceeding a limit is a typed refusal, not
/// silent truncation that would drop references.
struct CameraCoachDraftV3ProposalLimits: Codable, Equatable, Sendable {
    let deadlineSeconds: Int
    let maxInputBytes: Int
    let maxAttachmentBytes: Int
    let maxAttachmentLongEdgePx: Int
    let maxFrames: Int
    let maxEntities: Int
    let maxObservations: Int
    let maxRelations: Int
    let maxOutputTokens: Int

    static let s2Initial = CameraCoachDraftV3ProposalLimits(
        deadlineSeconds: 20,
        maxInputBytes: 256 * 1024,
        maxAttachmentBytes: 512 * 1024,
        maxAttachmentLongEdgePx: 1024,
        maxFrames: 1,
        maxEntities: 2,
        maxObservations: 8,
        maxRelations: 6,
        maxOutputTokens: 1024
    )

    var isComplete: Bool {
        deadlineSeconds > 0 && maxInputBytes > 0 && maxAttachmentBytes > 0
            && maxAttachmentLongEdgePx > 0 && maxFrames > 0 && maxEntities > 0
            && maxObservations > 0 && maxRelations > 0 && maxOutputTokens > 0
    }

    var boundsSingleAnchorFrame: Bool { maxFrames == 1 }
}

struct CameraCoachDraftV3ProposalRequest: Codable, Equatable, Sendable {
    let schemaVersion: CameraCoachDraftV3SchemaVersion
    let correlation: CameraCoachDraftV3Correlation
    let privacyMode: CameraCoachDraftV3LocalInputMode
    let limits: CameraCoachDraftV3ProposalLimits?
    let attachments: [CameraCoachDraftV3SafeAttachment]
    let isExplicitUserRequest: Bool
    let consentGranted: Bool
}

enum CameraCoachDraftV3RequestDisposition: Equatable, Sendable {
    case sendable
    case notSent(violations: [CameraCoachDraftV3IngressViolation])
}

enum CameraCoachDraftV3IngressResolution: Equatable, Sendable {
    case admitted
    case notFound
    case refused(reason: String)
    case unavailable(reason: String)
    case rejected
}

struct CameraCoachDraftV3ObjectProposal: Codable, Equatable, Sendable {
    let proposalID: String
    let labelCandidate: String?
    let region: CameraCoachDraftV3Region
    let confidence: Double
}

struct CameraCoachDraftV3EvidenceProposal: Codable, Equatable, Sendable {
    let proposalID: String
    let frameRef: String
    let dimension: CameraCoachDraftV3ObjectDimension
    let primaryRef: CameraCoachDraftV3Reference
    let secondaryRef: CameraCoachDraftV3Reference
    let score: Double
    let confidence: Double
    let problem: CameraCoachDraftV3ObjectProblem
}

struct CameraCoachDraftV3RelationProposal: Codable, Equatable, Sendable {
    let proposalID: String
    let frameRef: String
    let relationType: CameraCoachDraftV3RelationType
    let sourceRef: CameraCoachDraftV3Reference
    let targetRef: CameraCoachDraftV3Reference
    let dimension: CameraCoachDraftV3ObjectDimension
    let score: Double
    let confidence: Double
    let supportedEvidenceProposalIDs: [String]
}

struct CameraCoachDraftV3ProposalResponse: Codable, Equatable, Sendable {
    let schemaVersion: CameraCoachDraftV3SchemaVersion
    let profile: CameraCoachDraftV3IngressProfile
    let correlation: CameraCoachDraftV3Correlation
    let status: CameraCoachDraftV3ResponseStatus
    let refusalReason: String?
    let entityProposals: [CameraCoachDraftV3ObjectProposal]
    let evidenceProposals: [CameraCoachDraftV3EvidenceProposal]
    let relationProposals: [CameraCoachDraftV3RelationProposal]

    /// Required for untrusted JSON. Synthesized decoding alone would silently
    /// ignore unsupported fields such as provider-supplied `trackID`.
    static func decodeStrict(_ data: Data,
                             using decoder: JSONDecoder = JSONDecoder()) throws -> Self {
        let canonical = try CameraCoachDraftV3StrictJSON.canonicalData(data)
        do {
            return try decoder.decode(Self.self, from: canonical)
        } catch {
            throw CameraCoachDraftV3IngressDecodeError.invalidStructure
        }
    }
}

enum CameraCoachDraftV3IngressDecodeError: Error, Equatable, Sendable {
    case inputTooLarge
    case malformedJSON
    case invalidStructure
    case unsupportedField(String)
    case forbiddenProviderField(String)
}

/// Created by the local grounding owner; never decoded from provider JSON.
struct CameraCoachDraftV3LocalProposalGrounding: Equatable, Sendable {
    let proposalID: String
    let groundedEntity: VLMGroundedEntity
}

struct CameraCoachDraftV3IngressContext: Equatable, Sendable {
    let correlation: CameraCoachDraftV3Correlation
    let privacyMode: CameraCoachDraftV3LocalInputMode
    let isCurrentRequest: Bool
    let isCancelled: Bool
    let expiresAt: Date
    let groundedEntities: [VLMGroundedEntity]
    let proposalGroundings: [CameraCoachDraftV3LocalProposalGrounding]
    let expectedSchemaVersion: CameraCoachDraftV3SchemaVersion
    let limits: CameraCoachDraftV3ProposalLimits
    let consentGranted: Bool
    let attachments: [CameraCoachDraftV3SafeAttachment]

    init(correlation: CameraCoachDraftV3Correlation,
         privacyMode: CameraCoachDraftV3LocalInputMode,
         isCurrentRequest: Bool,
         isCancelled: Bool,
         expiresAt: Date,
         groundedEntities: [VLMGroundedEntity],
         proposalGroundings: [CameraCoachDraftV3LocalProposalGrounding],
         expectedSchemaVersion: CameraCoachDraftV3SchemaVersion = .s2Draft1,
         limits: CameraCoachDraftV3ProposalLimits = .s2Initial,
         consentGranted: Bool = true,
         attachments: [CameraCoachDraftV3SafeAttachment] = []) {
        self.correlation = correlation
        self.privacyMode = privacyMode
        self.isCurrentRequest = isCurrentRequest
        self.isCancelled = isCancelled
        self.expiresAt = expiresAt
        self.groundedEntities = groundedEntities
        self.proposalGroundings = proposalGroundings
        self.expectedSchemaVersion = expectedSchemaVersion
        self.limits = limits
        self.consentGranted = consentGranted
        self.attachments = attachments
    }
}

enum CameraCoachDraftV3ExistingEvidenceProjection: Equatable, Sendable {
    case converted(observations: [VLMVisualEvidenceObservation], relations: [VLMEntityRelation])
    case notFound
    case unadmitted(reason: CameraCoachDraftV3IngressViolation)
}

struct CameraCoachDraftV3IngressResult: Equatable, Sendable {
    let accepted: Bool
    let resolution: CameraCoachDraftV3IngressResolution
    let entityProposals: [CameraCoachDraftV3ObjectProposal]
    let evidenceProposals: [CameraCoachDraftV3EvidenceProposal]
    let relationProposals: [CameraCoachDraftV3RelationProposal]
    let existingEvidence: CameraCoachDraftV3ExistingEvidenceProjection?
    let violations: [CameraCoachDraftV3IngressViolation]
}

/// Local admission gate. Provider output may only replace existing local
/// evidence when it is admitted; a stale/foreign/refused payload preserves the
/// current local projection unchanged.
struct CameraCoachDraftV3IngressAdmission: Equatable, Sendable {
    let result: CameraCoachDraftV3IngressResult
    let localEvidence: CameraCoachDraftV3ExistingEvidenceProjection?
}

enum CameraCoachDraftV3ProposalIngress {
    // MARK: - Request sendability

    /// A request without mandatory limits is never sent. Remote-capable
    /// transports additionally require an explicit user request, so detailed
    /// cloud analysis cannot be triggered silently for a quality gate.
    static func validateForSend(_ request: CameraCoachDraftV3ProposalRequest,
                                remoteCapable: Bool = false) -> CameraCoachDraftV3RequestDisposition {
        var violations: [CameraCoachDraftV3IngressViolation] = []

        if request.schemaVersion != .s2Draft1 { violations.append(.schemaVersionMismatch) }
        if !validCorrelationTuple(request.correlation) { violations.append(.invalidIdentifier) }

        guard let limits = request.limits, limits.isComplete else {
            return .notSent(violations: unique([.missingLimits] + violations))
        }
        if !limits.boundsSingleAnchorFrame { violations.append(.limitsExceeded) }
        if request.attachments.count > limits.maxFrames { violations.append(.limitsExceeded) }
        if !request.consentGranted { violations.append(.consentRevoked) }
        if remoteCapable && !request.isExplicitUserRequest { violations.append(.explicitRequestRequired) }

        switch request.privacyMode {
        case .structuredOnly:
            if !request.attachments.isEmpty { violations.append(.privacyPolicyBlocked) }
        case .redactedVisual, .localAuthorizedStill:
            for attachment in request.attachments {
                if attachment.looksLikeURL { violations.append(.attachmentURLNotAllowed) }
                if attachment.sourceKind != .locallyProcessedVersion { violations.append(.unsafeAttachment) }
                if attachment.frameRef != request.correlation.anchorFrameRef { violations.append(.staleFrame) }
                if attachment.transformRef != request.correlation.anchorTransformRef { violations.append(.invalidRegion) }
                if attachment.coverage != request.correlation.coverage { violations.append(.unsupportedCoverage) }
                if attachment.byteCount <= 0 || attachment.byteCount > limits.maxAttachmentBytes
                    || attachment.longEdgePx <= 0 || attachment.longEdgePx > limits.maxAttachmentLongEdgePx {
                    violations.append(.limitsExceeded)
                }
                if !attachment.exifStripped || !attachment.redactionApplied {
                    violations.append(.unsafeAttachment)
                }
                if attachment.visibleRegion?.isValidNormalizedRect != true {
                    violations.append(.unsafeAttachment)
                }
            }
        }

        let found = unique(violations)
        return found.isEmpty ? .sendable : .notSent(violations: found)
    }

    // MARK: - Response admission

    static func validate(_ response: CameraCoachDraftV3ProposalResponse,
                         against context: CameraCoachDraftV3IngressContext,
                         now: Date = Date()) -> CameraCoachDraftV3IngressResult {
        let expected = context.correlation
        var hard: [CameraCoachDraftV3IngressViolation] = []
        var soft: [CameraCoachDraftV3IngressViolation] = []

        let allIDs = response.entityProposals.map(\.proposalID)
            + response.evidenceProposals.map(\.proposalID)
            + response.relationProposals.map(\.proposalID)

        // Correlation tuple: schemaVersion, requestID, analysisID, sessionID,
        // generation, sceneID, intentRevision, anchorFrameRef, catalogVersion,
        // policyVersion, coverage.
        if response.schemaVersion != context.expectedSchemaVersion { hard.append(.schemaVersionMismatch) }
        if response.correlation != expected { hard.append(.correlationMismatch) }
        if response.correlation.requestID != expected.requestID { hard.append(.requestMismatch) }
        if response.correlation.analysisID != expected.analysisID
            || response.correlation.sessionID != expected.sessionID
            || response.correlation.sceneID != expected.sceneID
            || response.correlation.generation != expected.generation
            || response.correlation.intentRevision != expected.intentRevision {
            hard.append(.staleRequest)
        }
        if response.correlation.anchorFrameRef != expected.anchorFrameRef { hard.append(.staleFrame) }
        if response.correlation.catalogVersion != expected.catalogVersion
            || response.correlation.policyVersion != expected.policyVersion {
            hard.append(.correlationMismatch)
        }

        if response.profile != .twoObjectLocalGroundedObservation { hard.append(.unsupportedProfile) }
        if context.privacyMode != .localAuthorizedStill { hard.append(.privacyPolicyBlocked) }
        if !context.consentGranted { hard.append(.consentRevoked) }
        if !context.isCurrentRequest || context.isCancelled || now >= context.expiresAt {
            hard.append(.staleRequest)
        }
        if response.correlation.coverage != .singleFrame { hard.append(.unsupportedCoverage) }
        if !validCorrelationTuple(expected) { hard.append(.invalidIdentifier) }
        if !context.limits.isComplete { hard.append(.missingLimits) }

        // Bounds: exceeding a limit is a typed refusal, never truncation.
        if !context.limits.boundsSingleAnchorFrame { hard.append(.limitsExceeded) }
        if response.entityProposals.count > context.limits.maxEntities
            || response.evidenceProposals.count > context.limits.maxObservations
            || response.relationProposals.count > context.limits.maxRelations {
            hard.append(.limitsExceeded)
        }
        let hasAnyProposal = !response.entityProposals.isEmpty
            || !response.evidenceProposals.isEmpty
            || !response.relationProposals.isEmpty
        if response.status == .completed, hasAnyProposal, response.entityProposals.count != 2 {
            hard.append(.proposalLimitExceeded)
        }
        if approxOutputTokens(of: response) > context.limits.maxOutputTokens {
            hard.append(.outputTokensExceeded)
        }
        if allIDs.contains(where: { !validIdentifier($0) }) { hard.append(.invalidIdentifier) }
        if Set(allIDs).count != allIDs.count { hard.append(.duplicateProposalID) }

        var local: [String: VLMGroundedEntity] = [:]
        context.groundedEntities.forEach { local[$0.entityRef] = $0 }
        var mappings: [String: CameraCoachDraftV3LocalProposalGrounding] = [:]
        context.proposalGroundings.forEach { mappings[$0.proposalID] = $0 }
        if context.groundedEntities.count != local.count { hard.append(.duplicateProposalID) }
        if context.proposalGroundings.count != mappings.count { hard.append(.duplicateProposalID) }
        if Set(mappings.values.map(\.groundedEntity.entityRef)).count
            != mappings.values.map(\.groundedEntity.entityRef).count {
            hard.append(.groundingAlias)
        }

        var statusResolution: CameraCoachDraftV3IngressResolution?
        switch response.status {
        case .completed where response.refusalReason != nil:
            hard.append(.invalidStatus)
        case .refused, .unavailable:
            let reason = response.refusalReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasProposals = !response.entityProposals.isEmpty
                || !response.evidenceProposals.isEmpty
                || !response.relationProposals.isEmpty
            if hasProposals || reason?.isEmpty != false {
                hard.append(.invalidStatus)
            } else if response.status == .refused {
                statusResolution = .refused(reason: reason ?? "")
            } else {
                statusResolution = .unavailable(reason: reason ?? "")
            }
        default:
            break
        }

        if !hard.isEmpty {
            return rejected(unique(hard + soft))
        }

        if let statusResolution {
            return CameraCoachDraftV3IngressResult(
                accepted: false,
                resolution: statusResolution,
                entityProposals: [],
                evidenceProposals: [],
                relationProposals: [],
                existingEvidence: nil,
                violations: unique(soft)
            )
        }

        // Entity proposals: reject an endpoint, then remove everything that
        // depends on it.
        var acceptedEntities: [CameraCoachDraftV3ObjectProposal] = []
        var acceptedEntityIDs: Set<String> = []
        for proposal in response.entityProposals {
            var rejection: CameraCoachDraftV3IngressViolation?
            if proposal.region.frameRef != expected.anchorFrameRef {
                rejection = .staleFrame
            } else if proposal.region.space != .orientedFrame
                || proposal.region.transformRef != expected.anchorTransformRef
                || !proposal.region.rect.isValidNormalizedRect {
                rejection = .invalidRegion
            } else if !validUnitRange(proposal.confidence) {
                rejection = .invalidConfidence
            } else if let label = proposal.labelCandidate,
                      !SemanticDisplayLabelPolicy.isAllowedDisplayLabel(label.lowercased()) {
                rejection = .invalidEvidence
            } else if !regionIsVisible(proposal.region.rect, frameRef: proposal.region.frameRef,
                                       attachments: context.attachments) {
                rejection = .redactedRegionClaim
            } else if let grounding = mappings[proposal.proposalID] {
                if grounding.groundedEntity.kind != .object && grounding.groundedEntity.kind != .prop {
                    rejection = .groundingKindMismatch
                } else if let locallyGrounded = local[grounding.groundedEntity.entityRef] {
                    if locallyGrounded != grounding.groundedEntity {
                        rejection = .groundingMismatch
                    } else if grounding.groundedEntity.region?.isDegenerate != false {
                        rejection = .unknownEntityReference
                    }
                } else {
                    rejection = .unknownEntityReference
                }
            } else {
                rejection = .groundingMissing
            }

            if let rejection {
                soft.append(rejection)
            } else {
                acceptedEntities.append(proposal)
                acceptedEntityIDs.insert(proposal.proposalID)
            }
        }

        let mappedObjects = acceptedEntities.compactMap { mappings[$0.proposalID]?.groundedEntity.entityRef }
        if mappedObjects.count != Set(mappedObjects).count { soft.append(.groundingAlias) }

        let responseProposalIDs = Set(response.entityProposals.map(\.proposalID))

        // Evidence proposals: unresolved or dependent-on-rejected-entity
        // proposals are dropped together with their relations.
        var acceptedEvidence: [CameraCoachDraftV3EvidenceProposal] = []
        var acceptedEvidenceIDs: Set<String> = []
        for proposal in response.evidenceProposals {
            if proposal.frameRef != expected.anchorFrameRef {
                soft.append(.staleFrame)
                continue
            }
            if !validUnitRange(proposal.score) || !validUnitRange(proposal.confidence) {
                soft.append(.invalidConfidence)
                continue
            }
            let primary = resolveReference(proposal.primaryRef, local: local, responseProposalIDs: responseProposalIDs,
                                           acceptedEntityIDs: acceptedEntityIDs, mappings: mappings)
            let secondary = resolveReference(proposal.secondaryRef, local: local, responseProposalIDs: responseProposalIDs,
                                             acceptedEntityIDs: acceptedEntityIDs, mappings: mappings)
            if case .invalid(.dependentProposalRemoved) = primary { soft.append(.dependentProposalRemoved); continue }
            if case .invalid(.dependentProposalRemoved) = secondary { soft.append(.dependentProposalRemoved); continue }
            if case .invalid(let violation) = primary { soft.append(violation); continue }
            if case .invalid(let violation) = secondary { soft.append(violation); continue }
            if case .resolved(let primaryID) = primary, case .resolved(let secondaryID) = secondary,
               primaryID == secondaryID {
                soft.append(.invalidRelationEndpoint)
                continue
            }
            acceptedEvidence.append(proposal)
            acceptedEvidenceIDs.insert(proposal.proposalID)
        }

        var acceptedRelations: [CameraCoachDraftV3RelationProposal] = []
        for proposal in response.relationProposals {
            if proposal.frameRef != expected.anchorFrameRef {
                soft.append(.staleFrame)
                continue
            }
            if !validUnitRange(proposal.score) || !validUnitRange(proposal.confidence)
                || proposal.supportedEvidenceProposalIDs.isEmpty
                || Set(proposal.supportedEvidenceProposalIDs).count != proposal.supportedEvidenceProposalIDs.count {
                soft.append(.invalidEvidence)
                continue
            }
            if proposal.supportedEvidenceProposalIDs.contains(where: { !acceptedEvidenceIDs.contains($0) }) {
                let referencedRemoved = proposal.supportedEvidenceProposalIDs
                    .contains(where: { responseProposalIDs.contains($0) })
                soft.append(referencedRemoved ? .dependentProposalRemoved : .invalidEvidence)
                continue
            }
            let source = resolveReference(proposal.sourceRef, local: local, responseProposalIDs: responseProposalIDs,
                                          acceptedEntityIDs: acceptedEntityIDs, mappings: mappings)
            let target = resolveReference(proposal.targetRef, local: local, responseProposalIDs: responseProposalIDs,
                                          acceptedEntityIDs: acceptedEntityIDs, mappings: mappings)
            if case .invalid(.dependentProposalRemoved) = source { soft.append(.dependentProposalRemoved); continue }
            if case .invalid(.dependentProposalRemoved) = target { soft.append(.dependentProposalRemoved); continue }
            if case .invalid(let violation) = source { soft.append(violation); continue }
            if case .invalid(let violation) = target { soft.append(violation); continue }
            guard case .resolved(let sourceID) = source, case .resolved(let targetID) = target else {
                soft.append(.unknownEntityReference)
                continue
            }
            if proposal.sourceRef == proposal.targetRef || sourceID == targetID {
                soft.append(.invalidRelationEndpoint)
                continue
            }
            let supportedEvidence = acceptedEvidence.filter {
                proposal.supportedEvidenceProposalIDs.contains($0.proposalID)
            }
            if supportedEvidence.contains(where: {
                $0.dimension != proposal.dimension
                    || resolvedID($0.primaryRef, local: local, acceptedEntityIDs: acceptedEntityIDs, mappings: mappings) != sourceID
                    || resolvedID($0.secondaryRef, local: local, acceptedEntityIDs: acceptedEntityIDs, mappings: mappings) != targetID
            }) {
                soft.append(.invalidEvidence)
                continue
            }
            acceptedRelations.append(proposal)
        }

        let violations = unique(soft)
        let hasUsableOutput = !acceptedEvidence.isEmpty || !acceptedRelations.isEmpty
        let isEmptyCompleted = response.entityProposals.isEmpty
            && response.evidenceProposals.isEmpty
            && response.relationProposals.isEmpty

        if hasUsableOutput {
            return CameraCoachDraftV3IngressResult(
                accepted: true,
                resolution: .admitted,
                entityProposals: acceptedEntities,
                evidenceProposals: acceptedEvidence,
                relationProposals: acceptedRelations,
                existingEvidence: projection(evidence: acceptedEvidence, relations: acceptedRelations,
                                             mappings: mappings, local: local),
                violations: violations
            )
        }
        if isEmptyCompleted {
            // Completed with nothing usable is "not found", never KEEP.
            return CameraCoachDraftV3IngressResult(
                accepted: false,
                resolution: .notFound,
                entityProposals: [],
                evidenceProposals: [],
                relationProposals: [],
                existingEvidence: .notFound,
                violations: violations
            )
        }
        return rejected(violations)
    }

    /// Provider output can only replace local evidence when admitted.
    static func admit(_ response: CameraCoachDraftV3ProposalResponse,
                      against context: CameraCoachDraftV3IngressContext,
                      replacing currentEvidence: CameraCoachDraftV3ExistingEvidenceProjection?,
                      now: Date = Date()) -> CameraCoachDraftV3IngressAdmission {
        let result = validate(response, against: context, now: now)
        let local = (result.accepted && result.resolution == .admitted) ? result.existingEvidence : currentEvidence
        return CameraCoachDraftV3IngressAdmission(result: result, localEvidence: local)
    }

    // MARK: - Helpers

    private static func rejected(_ violations: [CameraCoachDraftV3IngressViolation]) -> CameraCoachDraftV3IngressResult {
        CameraCoachDraftV3IngressResult(
            accepted: false,
            resolution: .rejected,
            entityProposals: [],
            evidenceProposals: [],
            relationProposals: [],
            existingEvidence: nil,
            violations: unique(violations)
        )
    }

    private enum ReferenceResolution: Equatable {
        case resolved(String)
        case invalid(CameraCoachDraftV3IngressViolation)
    }

    private static func resolveReference(_ ref: CameraCoachDraftV3Reference,
                                         local: [String: VLMGroundedEntity],
                                         responseProposalIDs: Set<String>,
                                         acceptedEntityIDs: Set<String>,
                                         mappings: [String: CameraCoachDraftV3LocalProposalGrounding]) -> ReferenceResolution {
        guard validIdentifier(ref.value) else { return .invalid(.invalidIdentifier) }
        switch ref.space {
        case .localEntity:
            guard let entity = local[ref.value],
                  entity.kind == .object || entity.kind == .prop,
                  entity.region?.isDegenerate == false else {
                return .invalid(.unknownEntityReference)
            }
            return .resolved(entity.entityRef)
        case .entityProposal:
            guard responseProposalIDs.contains(ref.value) else { return .invalid(.unknownEntityReference) }
            guard let acceptable = acceptableProposalReference(ref.value, mappings: mappings,
                                                               acceptedEntityIDs: acceptedEntityIDs) else {
                return .invalid(.groundingMissing)
            }
            guard acceptable else { return .invalid(.dependentProposalRemoved) }
            return .resolved(mappings[ref.value]?.groundedEntity.entityRef ?? ref.value)
        }
    }

    private static func resolvedID(_ ref: CameraCoachDraftV3Reference,
                                   local: [String: VLMGroundedEntity],
                                   acceptedEntityIDs: Set<String>,
                                   mappings: [String: CameraCoachDraftV3LocalProposalGrounding]) -> String? {
        switch ref.space {
        case .localEntity: return local[ref.value]?.entityRef
        case .entityProposal:
            guard acceptedEntityIDs.contains(ref.value) else { return nil }
            return mappings[ref.value]?.groundedEntity.entityRef
        }
    }

    private static func acceptableProposalReference(_ proposalID: String,
                                                    mappings: [String: CameraCoachDraftV3LocalProposalGrounding],
                                                    acceptedEntityIDs: Set<String>) -> Bool? {
        guard let mapping = mappings[proposalID] else { return nil }
        return mapping.groundedEntity.entityRef.isEmpty ? false : acceptedEntityIDs.contains(proposalID)
    }

    private static func regionIsVisible(_ rect: CameraCoachDraftV3RawRect,
                                        frameRef: String,
                                        attachments: [CameraCoachDraftV3SafeAttachment]) -> Bool {
        let relevant = attachments.filter { $0.frameRef == frameRef }
        guard !relevant.isEmpty else { return true }
        return relevant.contains { attachment in
            guard let visible = attachment.visibleRegion else { return false }
            return visible.contains(rect)
        }
    }

    private static func projection(evidence: [CameraCoachDraftV3EvidenceProposal],
                                   relations: [CameraCoachDraftV3RelationProposal],
                                   mappings: [String: CameraCoachDraftV3LocalProposalGrounding],
                                   local: [String: VLMGroundedEntity]) -> CameraCoachDraftV3ExistingEvidenceProjection {
        let acceptedEntityIDs = Set(mappings.keys)
        let observations = evidence.compactMap { proposal -> VLMVisualEvidenceObservation? in
            guard let primary = resolvedID(proposal.primaryRef, local: local,
                                           acceptedEntityIDs: acceptedEntityIDs, mappings: mappings),
                  let secondary = resolvedID(proposal.secondaryRef, local: local,
                                             acceptedEntityIDs: acceptedEntityIDs, mappings: mappings) else {
                return nil
            }
            return VLMVisualEvidenceObservation(
                observationId: "v3-\(proposal.proposalID)", dimension: proposal.dimension.existingDimension,
                polarity: .supportsProblem, score: proposal.score, confidence: proposal.confidence,
                uncertaintyReasons: [], primaryEntityRef: primary,
                secondaryEntityRef: secondary,
                visualProblemType: proposal.problem.existingProblem, visualStrengthType: nil,
                supportedIssueIds: [], supportedStrengthIds: [], suggestedActionIds: [], evidenceNote: nil
            )
        }
        let projectedRelations = relations.compactMap { proposal -> VLMEntityRelation? in
            guard let source = resolvedID(proposal.sourceRef, local: local,
                                          acceptedEntityIDs: acceptedEntityIDs, mappings: mappings),
                  let target = resolvedID(proposal.targetRef, local: local,
                                          acceptedEntityIDs: acceptedEntityIDs, mappings: mappings) else {
                return nil
            }
            return VLMEntityRelation(
                relationId: "v3-\(proposal.proposalID)",
                sourceEntityRef: source,
                targetEntityRef: target,
                relationType: proposal.relationType.existingRelation, dimension: proposal.dimension.existingDimension,
                score: proposal.score, confidence: proposal.confidence, uncertaintyReasons: [],
                supportedObservationIds: proposal.supportedEvidenceProposalIDs.map { "v3-\($0)" }
            )
        }
        guard observations.count == evidence.count, projectedRelations.count == relations.count else {
            return .unadmitted(reason: .unsupportedConversion)
        }
        return .converted(observations: observations, relations: projectedRelations)
    }

    private static func validCorrelationTuple(_ tuple: CameraCoachDraftV3Correlation) -> Bool {
        validIdentifiers([tuple.requestID, tuple.analysisID, tuple.sessionID, tuple.sceneID,
                          tuple.anchorFrameRef, tuple.anchorTransformRef,
                          tuple.catalogVersion, tuple.policyVersion])
    }

    private static func validIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122)
                || $0 == 46 || $0 == 95 || $0 == 45
        }
    }

    private static func validIdentifiers(_ values: [String]) -> Bool { values.allSatisfy(validIdentifier) }
    private static func validUnitRange(_ value: Double) -> Bool { value.isFinite && (0...1).contains(value) }

    private static func approxOutputTokens(of response: CameraCoachDraftV3ProposalResponse) -> Int {
        var characters = response.refusalReason?.count ?? 0
        characters += response.evidenceProposals.count * 32
        characters += response.relationProposals.count * 16
        characters += response.entityProposals.count * 16
        return (characters + 3) / 4
    }

    private static func unique(_ violations: [CameraCoachDraftV3IngressViolation]) -> [CameraCoachDraftV3IngressViolation] {
        Array(Set(violations)).sorted { $0.rawValue < $1.rawValue }
    }
}

private enum CameraCoachDraftV3StrictJSON {
    private static let maxInputBytes = 256 * 1024

    /// Fields a provider must never return. They stay unsupported for the
    /// decoder and are reported distinctly so the refusal is typed.
    private static let forbiddenProviderFields: Set<String> = [
        "finalDecision", "final_decision", "activeDecision", "activeAction", "active_action",
        "trackID", "trackId", "track_id", "qualificationRef", "qualification_ref",
        "verificationOutcome", "verification_outcome", "verificationResult", "verification_result",
        "entityID", "entityId", "entity_id", "userSelection", "user_selection",
        "subjectSelection", "subject_selection", "physicalRoute", "physical_route",
        "operation", "newOperation", "threshold", "predicate"
    ]

    private static let allowed: [String: Set<String>] = [
        "response": ["schemaVersion", "profile", "correlation", "status", "refusalReason", "entityProposals", "evidenceProposals", "relationProposals"],
        "correlation": ["requestID", "analysisID", "sessionID", "generation", "sceneID", "intentRevision", "anchorFrameRef", "anchorTransformRef", "catalogVersion", "policyVersion", "coverage"],
        "reference": ["space", "value"], "rect": ["x", "y", "width", "height"],
        "region": ["frameRef", "space", "transformRef", "rect"],
        "entity": ["proposalID", "labelCandidate", "region", "confidence"],
        "evidence": ["proposalID", "frameRef", "dimension", "primaryRef", "secondaryRef", "score", "confidence", "problem"],
        "relation": ["proposalID", "frameRef", "relationType", "sourceRef", "targetRef", "dimension", "score", "confidence", "supportedEvidenceProposalIDs"]
    ]

    static func canonicalData(_ data: Data) throws -> Data {
        guard data.count <= maxInputBytes else {
            throw CameraCoachDraftV3IngressDecodeError.inputTooLarge
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CameraCoachDraftV3IngressDecodeError.malformedJSON
        }
        try validate(object, schema: "response")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func validate(_ object: Any, schema: String) throws {
        guard let dict = object as? [String: Any], let keys = allowed[schema] else {
            throw CameraCoachDraftV3IngressDecodeError.invalidStructure
        }
        let extra = Set(dict.keys).subtracting(keys)
        if !extra.isEmpty {
            if let forbidden = extra.sorted().first(where: { forbiddenProviderFields.contains($0) }) {
                throw CameraCoachDraftV3IngressDecodeError.forbiddenProviderField(forbidden)
            }
            throw CameraCoachDraftV3IngressDecodeError.unsupportedField(extra.sorted().first ?? "unknown")
        }
        switch schema {
        case "response":
            try validate(dict["correlation"] as Any, schema: "correlation")
            try validateArray(dict["entityProposals"], schema: "entity")
            try validateArray(dict["evidenceProposals"], schema: "evidence")
            try validateArray(dict["relationProposals"], schema: "relation")
        case "entity": try validate(dict["region"] as Any, schema: "region")
        case "region": try validate(dict["rect"] as Any, schema: "rect")
        case "evidence":
            try validate(dict["primaryRef"] as Any, schema: "reference")
            try validate(dict["secondaryRef"] as Any, schema: "reference")
        case "relation":
            try validate(dict["sourceRef"] as Any, schema: "reference")
            try validate(dict["targetRef"] as Any, schema: "reference")
        default: break
        }
    }

    private static func validateArray(_ object: Any?, schema: String) throws {
        guard let array = object as? [Any] else { throw CameraCoachDraftV3IngressDecodeError.invalidStructure }
        for item in array { try validate(item, schema: schema) }
    }
}

#endif
