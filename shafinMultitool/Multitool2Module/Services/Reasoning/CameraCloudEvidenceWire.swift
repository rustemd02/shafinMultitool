import Foundation

/// Camera v1 sends descriptive evidence only. S1 remains the local admission contract.
/// The service cannot assign local actions, verdicts, labels, tracks or completion state.
enum CameraCloudEvidenceWire {
    static let version = "camera_evidence_v1"
    static let maximumRequestBytes = 768 * 1_024
    static let maximumResponseBytes = 128 * 1_024

    struct Timestamp: Codable, Equatable, Sendable {
        let value: Int64
        let timescale: Int32
        let flags: UInt32
        let epoch: Int64
    }

    struct Correlation: Codable, Equatable, Sendable {
        let frame_id: String
        let snapshot_id: String
        let capture_session_id: String
        let capture_generation: UInt64
        let frame_pts: Timestamp
        let scene_epoch: Int
        let intent_revision: UInt64
    }

    struct Consent: Encodable, Sendable {
        let mode = "authorized_selected_still"
        let nonce: String
        let policy_fingerprint: String
    }

    struct Media: Encodable, Sendable {
        let mime_type = "image/jpeg"
        let encoding = "base64"
        let data: String
        let sha256: String
        let width: Int
        let height: Int
        let metadata_stripped = true
        let redaction = "none"
        let coordinate_space = "normalized_top_left"
    }

    struct Entity: Encodable, Sendable {
        let entity_ref: String
        let kind: VLMEntityKind
        let region: NormalizedRect?
        let detector_label: String?
        /// Detector support, when available. This is not a calibrated probability.
        let confidence: Double?

        enum CodingKeys: String, CodingKey {
            case entity_ref, kind, region, detector_label, confidence
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(entity_ref, forKey: .entity_ref)
            try values.encode(kind, forKey: .kind)
            try values.encode(region, forKey: .region)
            try values.encode(detector_label, forKey: .detector_label)
            try values.encode(confidence, forKey: .confidence)
        }
    }

    struct LocalContext: Encodable, Sendable {
        let known_entities: [Entity]
        let issue_ids: [String]
        let strength_ids: [String]
        let allowed_dimensions: [VLMVisualEvidenceDimension]
        let allowed_problem_types: [VisualProblemType]
        let allowed_strength_types: [VisualStrengthType]
        let allowed_relation_types: [VLMEntityRelationType]
        /// Actual CameraIntentClarificationPolicy values; omitted answers are unknown.
        let intent_answers: [String: Bool]
    }

    struct Request: Encodable, Sendable {
        let schema_version = CameraCloudEvidenceWire.version
        let request_id: String
        let locale: String
        let correlation: Correlation
        let consent: Consent
        let media: Media
        let local_context: LocalContext

        func encoded() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(self)
        }
    }

    struct Observation: Decodable, Sendable {
        let observation_id: String
        let dimension: VLMVisualEvidenceDimension
        let polarity: VLMEvidencePolarity
        let score: Double
        let confidence: Double
        let uncertainty_reasons: [VLMUncertaintyReason]
        /// Ordered primary, secondary references, each belonging to this request.
        let entity_refs: [String]
        let visual_problem_type: VisualProblemType?
        let visual_strength_type: VisualStrengthType?
        let supporting_issue_ids: [String]
        let supporting_strength_ids: [String]
        let rationale: String
    }

    struct Relation: Decodable, Sendable {
        let relation_id: String
        let relation_type: VLMEntityRelationType
        let source_entity_ref: String
        let target_entity_ref: String
        let dimension: VLMVisualEvidenceDimension
        let score: Double
        let confidence: Double
        let uncertainty_reasons: [VLMUncertaintyReason]
        let supported_observation_ids: [String]
        let rationale: String
    }

    struct Evidence: Decodable, Sendable {
        let observations: [Observation]
        let relations: [Relation]
        let abstained: Bool
        let abstention_reason: String?
    }

    struct Response: Decodable, Sendable {
        let schema_version: String
        let request_id: String
        let request_sha256: String
        let correlation: Correlation
        let media_sha256: String
        let policy_fingerprint: String
        let evidence: Evidence
    }

    static func decode(_ data: Data, request: Request, bodyHash: String) throws -> Response {
        guard !data.isEmpty, data.count <= maximumResponseBytes else {
            throw CameraCloudClientError.invalidResponse
        }
        do {
            // Codable ignores unknown keys. Check each wire object before typed decoding,
            // including nullable fields: an omitted field is not an explicit unknown value.
            let root = try object(JSONSerialization.jsonObject(with: data), keys: [
                "schema_version", "request_id", "request_sha256", "correlation",
                "media_sha256", "policy_fingerprint", "evidence"
            ])
            let correlation = try object(root["correlation"], keys: [
                "frame_id", "snapshot_id", "capture_session_id", "capture_generation",
                "frame_pts", "scene_epoch", "intent_revision"
            ])
            _ = try object(correlation["frame_pts"], keys: ["value", "timescale", "flags", "epoch"])
            let evidence = try object(root["evidence"], keys: [
                "observations", "relations", "abstained", "abstention_reason"
            ])
            guard let observations = evidence["observations"] as? [Any], observations.count <= 8,
                  let relations = evidence["relations"] as? [Any], relations.count <= 6 else {
                throw CameraCloudClientError.invalidResponse
            }
            for observation in observations {
                _ = try object(observation, keys: [
                    "observation_id", "dimension", "polarity", "score", "confidence",
                    "uncertainty_reasons", "entity_refs", "visual_problem_type",
                    "visual_strength_type", "supporting_issue_ids", "supporting_strength_ids", "rationale"
                ])
            }
            for relation in relations {
                _ = try object(relation, keys: [
                    "relation_id", "relation_type", "source_entity_ref", "target_entity_ref",
                    "dimension", "score", "confidence", "uncertainty_reasons",
                    "supported_observation_ids", "rationale"
                ])
            }
            // Decode the same checked object. Separate parsers must not select
            // different values from repeated keys in the original byte stream.
            let checkedData = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            let response = try JSONDecoder().decode(Response.self, from: checkedData)
            try validate(response, request: request, bodyHash: bodyHash)
            return response
        } catch {
            throw CameraCloudClientError.invalidResponse
        }
    }

    private static func validate(_ response: Response, request: Request, bodyHash: String) throws {
        guard response.schema_version == version,
              response.request_id == request.request_id,
              response.request_sha256 == bodyHash,
              response.correlation == request.correlation,
              response.media_sha256 == request.media.sha256,
              response.policy_fingerprint == request.consent.policy_fingerprint else {
            throw CameraCloudClientError.invalidResponse
        }
        let evidence = response.evidence
        guard evidence.observations.count <= 8, evidence.relations.count <= 6 else {
            throw CameraCloudClientError.invalidResponse
        }
        if evidence.abstained {
            guard evidence.observations.isEmpty, evidence.relations.isEmpty,
                  let reason = evidence.abstention_reason, boundedText(reason, maximum: 500) else {
                throw CameraCloudClientError.invalidResponse
            }
        } else if evidence.abstention_reason != nil {
            throw CameraCloudClientError.invalidResponse
        }

        let local = request.local_context
        let entities = Set(local.known_entities.map(\.entity_ref))
        let issues = Set(local.issue_ids)
        let strengths = Set(local.strength_ids)
        var observationIDs: Set<String> = []
        for value in evidence.observations {
            guard validID(value.observation_id), observationIDs.insert(value.observation_id).inserted,
                  local.allowed_dimensions.contains(value.dimension),
                  unit(value.score), unit(value.confidence),
                  unique(value.uncertainty_reasons.map(\.rawValue), maximum: VLMUncertaintyReason.allCases.count),
                  value.confidence >= 0.45 || !value.uncertainty_reasons.isEmpty,
                  unique(value.entity_refs, maximum: 2), Set(value.entity_refs).isSubset(of: entities),
                  unique(value.supporting_issue_ids, maximum: 64),
                  Set(value.supporting_issue_ids).isSubset(of: issues),
                  unique(value.supporting_strength_ids, maximum: 64),
                  Set(value.supporting_strength_ids).isSubset(of: strengths),
                  boundedText(value.rationale, maximum: 500),
                  value.visual_problem_type.map(local.allowed_problem_types.contains) ?? true,
                  value.visual_strength_type.map(local.allowed_strength_types.contains) ?? true else {
                throw CameraCloudClientError.invalidResponse
            }
            switch value.polarity {
            case .supportsProblem:
                guard value.visual_problem_type != nil, value.visual_strength_type == nil,
                      value.supporting_strength_ids.isEmpty else { throw CameraCloudClientError.invalidResponse }
            case .supportsStrength:
                guard value.visual_strength_type != nil, value.visual_problem_type == nil,
                      value.supporting_issue_ids.isEmpty else { throw CameraCloudClientError.invalidResponse }
            case .neutralContext:
                guard value.visual_problem_type == nil, value.visual_strength_type == nil,
                      value.supporting_issue_ids.isEmpty, value.supporting_strength_ids.isEmpty else {
                    throw CameraCloudClientError.invalidResponse
                }
            }
        }
        var relationIDs: Set<String> = []
        for value in evidence.relations {
            guard validID(value.relation_id), relationIDs.insert(value.relation_id).inserted,
                  local.allowed_relation_types.contains(value.relation_type),
                  local.allowed_dimensions.contains(value.dimension),
                  entities.contains(value.source_entity_ref), entities.contains(value.target_entity_ref),
                  value.source_entity_ref != value.target_entity_ref,
                  unit(value.score), unit(value.confidence),
                  unique(value.uncertainty_reasons.map(\.rawValue), maximum: VLMUncertaintyReason.allCases.count),
                  value.confidence >= 0.45 || !value.uncertainty_reasons.isEmpty,
                  !value.supported_observation_ids.isEmpty,
                  unique(value.supported_observation_ids, maximum: 8),
                  Set(value.supported_observation_ids).isSubset(of: observationIDs),
                  boundedText(value.rationale, maximum: 500) else {
                throw CameraCloudClientError.invalidResponse
            }
        }
    }

    static func adapt(_ response: Response, request: VLMVisualEvidenceRequest,
                      policy: CameraCloudTransferPolicy, latencyMs: Int) -> VLMVisualEvidenceResponse {
        // Request-local labels are reused. The provider never supplies labels or kinds
        // capable of creating a new local target; ambiguous overall identity stays absent.
        let primaryRefs = Set(response.evidence.observations.compactMap { $0.entity_refs.first })
        let primaryRef = primaryRefs.count == 1 ? primaryRefs.first : nil
        let primary = request.localContext.groundedEntities.first { $0.entityRef == primaryRef }
        let secondaryRefs = Set(response.evidence.observations.compactMap {
            $0.entity_refs.count == 2 ? $0.entity_refs[1] : nil
        })
        let secondaryRef = secondaryRefs.count == 1 ? secondaryRefs.first : nil
        let secondary = request.localContext.groundedEntities.first { $0.entityRef == secondaryRef }
        return VLMVisualEvidenceResponse(
            schemaVersion: .s1, requestId: request.requestId, frameId: request.frameId,
            mode: .pause, providerId: policy.providerName,
            status: response.evidence.abstained ? .refused : .completed,
            primaryEntityRef: primary?.entityRef, primaryEntityKind: primary?.kind ?? .frame,
            primaryEntityDisplayLabelCandidate: primary?.displayLabelCandidate ?? "кадр",
            primaryEntityLabelConfidence: primary?.displayLabelConfidence ?? 0,
            secondaryEntityRef: secondary?.entityRef, secondaryEntityKind: secondary?.kind,
            secondaryEntityDisplayLabelCandidate: secondary?.displayLabelCandidate,
            secondaryEntityLabelConfidence: secondary?.displayLabelConfidence,
            observations: response.evidence.observations.map {
                VLMVisualEvidenceObservation(
                    observationId: $0.observation_id, dimension: $0.dimension, polarity: $0.polarity,
                    score: $0.score, confidence: $0.confidence, uncertaintyReasons: $0.uncertainty_reasons,
                    primaryEntityRef: $0.entity_refs.first,
                    secondaryEntityRef: $0.entity_refs.count == 2 ? $0.entity_refs[1] : nil,
                    visualProblemType: $0.visual_problem_type, visualStrengthType: $0.visual_strength_type,
                    supportedIssueIds: $0.supporting_issue_ids, supportedStrengthIds: $0.supporting_strength_ids,
                    suggestedActionIds: [], evidenceNote: $0.rationale
                )
            },
            relations: response.evidence.relations.map {
                VLMEntityRelation(
                    relationId: $0.relation_id, sourceEntityRef: $0.source_entity_ref,
                    targetEntityRef: $0.target_entity_ref, relationType: $0.relation_type,
                    dimension: $0.dimension, score: $0.score, confidence: $0.confidence,
                    uncertaintyReasons: $0.uncertainty_reasons, supportedObservationIds: $0.supported_observation_ids
                )
            },
            suggestedActionIds: [], explanation: nil,
            // This means the v1 structural boundary passed, not that the advice is true.
            safety: VLMEvidenceSafetyReport(passed: true, violations: []),
            diagnostics: VLMEvidenceDiagnostics(
                latencyMs: latencyMs, providerModelFamily: policy.providerName,
                providerModelVersion: policy.providerVersion, promptVersion: version,
                privacyTier: .authorizedSelectedStill, fallbackReason: response.evidence.abstention_reason
            )
        )
    }

    static func validID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        func alphaNumeric(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        guard !bytes.isEmpty, bytes.count <= 128, alphaNumeric(bytes[0]) else { return false }
        return bytes.allSatisfy { alphaNumeric($0) || [58, 46, 95, 45].contains($0) }
    }

    static func validDetectorLabel(_ value: String) -> Bool { boundedText(value, maximum: 128) }
    static func unit(_ value: Double) -> Bool { value.isFinite && value >= 0 && value <= 1 }

    static func unique(_ values: [String], maximum: Int) -> Bool {
        values.count <= maximum && Set(values).count == values.count && values.allSatisfy(validID)
    }

    private static func boundedText(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any], Set(object.keys) == keys else {
            throw CameraCloudClientError.invalidResponse
        }
        return object
    }
}
