import XCTest
@testable import shafinMultitool

final class CameraCoachDraftV3ProposalIngressTests: XCTestCase {
    func testAcceptsTwoLocallyGroundedObjectsAndProjectsBoundedEvidence() throws {
        let response = makeResponse()
        let context = makeContext()

        let result = CameraCoachDraftV3ProposalIngress.validate(response, against: context)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.entityProposals.count, 2)
        guard case let .converted(observations, relations) = result.existingEvidence else {
            return XCTFail("Expected projection into existing VLM evidence shapes")
        }
        XCTAssertEqual(observations.first?.primaryEntityRef, "object-a")
        XCTAssertEqual(observations.first?.secondaryEntityRef, "object-b")
        XCTAssertEqual(observations.first?.visualProblemType, .objectConflictsWithSubject)
        XCTAssertEqual(relations.first?.sourceEntityRef, "object-a")
        XCTAssertEqual(relations.first?.targetEntityRef, "object-b")
        XCTAssertEqual(relations.first?.relationType, .competesWith)
    }

    func testRejectsOutOfBoundsProviderRegionWithoutClamping() {
        var response = makeResponse()
        response = CameraCoachDraftV3ProposalResponse(
            schemaVersion: response.schemaVersion,
            profile: response.profile,
            correlation: response.correlation,
            status: response.status,
            refusalReason: response.refusalReason,
            entityProposals: [
                CameraCoachDraftV3ObjectProposal(
                    proposalID: "proposal-a",
                    labelCandidate: "лампа",
                    region: CameraCoachDraftV3Region(
                        frameRef: "frame-1",
                        space: .orientedFrame,
                        transformRef: "transform-1",
                        rect: CameraCoachDraftV3RawRect(x: -0.1, y: 0.1, width: 0.2, height: 0.2)
                    ),
                    confidence: 0.9
                ),
                response.entityProposals[1]
            ],
            evidenceProposals: response.evidenceProposals,
            relationProposals: response.relationProposals
        )

        let result = CameraCoachDraftV3ProposalIngress.validate(response, against: makeContext())

        XCTAssertFalse(result.accepted)
        XCTAssertTrue(result.violations.contains(.invalidRegion))
    }

    func testRejectsAliasCollapseBetweenTwoObjectProposals() {
        let response = makeResponse()
        let context = CameraCoachDraftV3IngressContext(
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            isCurrentRequest: true,
            isCancelled: false,
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            groundedEntities: [object("object-a", label: "лампа"), object("object-b", label: "ваза")],
            proposalGroundings: [
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-a", groundedEntity: object("object-a", label: "лампа")
                ),
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-b", groundedEntity: object("object-a", label: "лампа")
                )
            ]
        )

        let result = CameraCoachDraftV3ProposalIngress.validate(response, against: context)

        XCTAssertFalse(result.accepted)
        XCTAssertTrue(result.violations.contains(.groundingAlias))
    }

    func testRejectsGroundingPayloadThatDiffersFromLocalOwner() {
        let context = CameraCoachDraftV3IngressContext(
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            isCurrentRequest: true,
            isCancelled: false,
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            groundedEntities: [object("object-a", label: "лампа"), object("object-b", label: "ваза")],
            proposalGroundings: [
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-a", groundedEntity: object("object-a", label: "ваза")
                ),
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-b", groundedEntity: object("object-b", label: "ваза")
                )
            ]
        )

        let result = CameraCoachDraftV3ProposalIngress.validate(makeResponse(), against: context)

        XCTAssertFalse(result.accepted)
        XCTAssertTrue(result.violations.contains(.groundingMismatch))
    }

    func testRejectsStructuredOnlyAndExpiredRequest() {
        let context = CameraCoachDraftV3IngressContext(
            correlation: makeCorrelation(),
            privacyMode: .structuredOnly,
            isCurrentRequest: true,
            isCancelled: false,
            expiresAt: Date(timeIntervalSince1970: 10),
            groundedEntities: [object("object-a", label: "лампа"), object("object-b", label: "ваза")],
            proposalGroundings: [
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-a", groundedEntity: object("object-a", label: "лампа")
                ),
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-b", groundedEntity: object("object-b", label: "ваза")
                )
            ]
        )

        let result = CameraCoachDraftV3ProposalIngress.validate(
            makeResponse(), against: context, now: Date(timeIntervalSince1970: 11)
        )

        XCTAssertFalse(result.accepted)
        XCTAssertTrue(result.violations.contains(.privacyPolicyBlocked))
        XCTAssertTrue(result.violations.contains(.staleRequest))
    }

    func testStrictDecoderRejectsProviderTrackIDAndUnsupportedActionArray() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(makeResponse())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entities = try XCTUnwrap(object["entityProposals"] as? [[String: Any]])
        entities[0]["trackID"] = "provider-track-must-not-cross-boundary"
        object["entityProposals"] = entities

        let withTrackID = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try CameraCoachDraftV3ProposalResponse.decodeStrict(withTrackID))

        entities[0].removeValue(forKey: "trackID")
        object["entityProposals"] = entities
        object["actionProposals"] = []
        let withUnsupportedArray = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try CameraCoachDraftV3ProposalResponse.decodeStrict(withUnsupportedArray))
    }

    // MARK: - C09: correlation tuple / limits / refusal / dependent removal

    func testStaleCorrelationTupleIsRejectedAndPreservesLocalEvidence() {
        let stale = correlation(analysisID: "analysis-1", generation: 1, intentRevision: 2)
        let response = makeResponse(correlation: stale)
        let current: CameraCoachDraftV3ExistingEvidenceProjection = .converted(observations: [], relations: [])

        let admission = CameraCoachDraftV3ProposalIngress.admit(
            response, against: makeContext(), replacing: current
        )

        XCTAssertFalse(admission.result.accepted)
        XCTAssertTrue(admission.result.violations.contains(.staleRequest))
        XCTAssertTrue(admission.result.entityProposals.isEmpty)
        XCTAssertEqual(admission.localEvidence, current)
    }

    func testForeignCorrelationTupleIsRejectedAndPreservesLocalEvidence() {
        let foreign = correlation(analysisID: "analysis-other", generation: 7, intentRevision: 1)
        let response = makeResponse(correlation: foreign)
        let current: CameraCoachDraftV3ExistingEvidenceProjection = .notFound

        let admission = CameraCoachDraftV3ProposalIngress.admit(
            response, against: makeContext(), replacing: current
        )

        XCTAssertFalse(admission.result.accepted)
        XCTAssertTrue(admission.result.violations.contains(.correlationMismatch))
        XCTAssertTrue(admission.result.violations.contains(.staleRequest))
        XCTAssertEqual(admission.localEvidence, current)
    }

    func testRequestWithoutLimitsIsNotSent() {
        let withoutLimits = CameraCoachDraftV3ProposalRequest(
            schemaVersion: .s2Draft1,
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            limits: nil,
            attachments: [],
            isExplicitUserRequest: true,
            consentGranted: true
        )
        XCTAssertEqual(
            CameraCoachDraftV3ProposalIngress.validateForSend(withoutLimits),
            .notSent(violations: [.missingLimits])
        )

        let zeroDeadline = CameraCoachDraftV3ProposalRequest(
            schemaVersion: .s2Draft1,
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            limits: limits(deadlineSeconds: 0),
            attachments: [],
            isExplicitUserRequest: true,
            consentGranted: true
        )
        XCTAssertEqual(
            CameraCoachDraftV3ProposalIngress.validateForSend(zeroDeadline),
            .notSent(violations: [.missingLimits])
        )
    }

    func testMultiFrameRequestIsNotSent() {
        let request = CameraCoachDraftV3ProposalRequest(
            schemaVersion: .s2Draft1,
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            limits: limits(maxFrames: 4),
            attachments: [],
            isExplicitUserRequest: true,
            consentGranted: true
        )
        XCTAssertEqual(
            CameraCoachDraftV3ProposalIngress.validateForSend(request),
            .notSent(violations: [.limitsExceeded])
        )
    }

    func testRemoteCapableRequestRequiresExplicitUserRequest() {
        let request = CameraCoachDraftV3ProposalRequest(
            schemaVersion: .s2Draft1,
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            limits: limits(),
            attachments: [],
            isExplicitUserRequest: false,
            consentGranted: true
        )
        let disposition = CameraCoachDraftV3ProposalIngress.validateForSend(request, remoteCapable: true)
        XCTAssertEqual(disposition, .notSent(violations: [.explicitRequestRequired]))
    }

    func testRefusedResponseIsEmptyWithReasonAndPreservesLocalEvidence() {
        let current: CameraCoachDraftV3ExistingEvidenceProjection = .converted(observations: [], relations: [])
        let response = makeResponse(status: .refused, refusalReason: "provider_policy_refusal")

        let admission = CameraCoachDraftV3ProposalIngress.admit(
            response, against: makeContext(), replacing: current
        )

        XCTAssertFalse(admission.result.accepted)
        XCTAssertEqual(admission.result.resolution, .refused(reason: "provider_policy_refusal"))
        XCTAssertTrue(admission.result.entityProposals.isEmpty)
        XCTAssertTrue(admission.result.evidenceProposals.isEmpty)
        XCTAssertTrue(admission.result.relationProposals.isEmpty)
        XCTAssertEqual(admission.localEvidence, current)
    }

    func testRefusedResponseWithProposalsIsRejected() {
        let base = makeResponse()
        let response = CameraCoachDraftV3ProposalResponse(
            schemaVersion: base.schemaVersion,
            profile: base.profile,
            correlation: base.correlation,
            status: .refused,
            refusalReason: "provider_policy_refusal",
            entityProposals: base.entityProposals,
            evidenceProposals: base.evidenceProposals,
            relationProposals: base.relationProposals
        )

        let result = CameraCoachDraftV3ProposalIngress.validate(response, against: makeContext())

        XCTAssertFalse(result.accepted)
        XCTAssertTrue(result.violations.contains(.invalidStatus))
        XCTAssertTrue(result.evidenceProposals.isEmpty)
    }

    func testUnacceptedEndpointRemovesDependentProposals() {
        let context = CameraCoachDraftV3IngressContext(
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            isCurrentRequest: true,
            isCancelled: false,
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            groundedEntities: [object("object-a", label: "лампа"), object("object-b", label: "ваза")],
            proposalGroundings: [
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-a", groundedEntity: object("object-a", label: "лампа")
                ),
                // Local owner labelled object-b as "ваза"; provider grounding disagrees.
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-b", groundedEntity: object("object-b", label: "лампа")
                )
            ]
        )

        let result = CameraCoachDraftV3ProposalIngress.validate(makeDependentResponse(), against: context)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.entityProposals.map(\.proposalID), ["proposal-a"])
        XCTAssertEqual(result.evidenceProposals.map(\.proposalID), ["evidence-a"])
        XCTAssertEqual(result.relationProposals.map(\.proposalID), ["relation-a"])
        XCTAssertTrue(result.violations.contains(.dependentProposalRemoved))
        XCTAssertTrue(result.violations.contains(.groundingMismatch))
        XCTAssertFalse(result.entityProposals.contains { $0.proposalID == "proposal-b" })
    }

    func testExceedingLimitsIsTypedRefusalNotTruncation() {
        var context = makeContext()
        context = CameraCoachDraftV3IngressContext(
            correlation: context.correlation,
            privacyMode: context.privacyMode,
            isCurrentRequest: context.isCurrentRequest,
            isCancelled: context.isCancelled,
            expiresAt: context.expiresAt,
            groundedEntities: context.groundedEntities,
            proposalGroundings: context.proposalGroundings,
            limits: limits(maxObservations: 1, maxRelations: 1)
        )
        let response = makeResponse(
            evidenceProposals: [
                evidence("evidence-1", primary: .entityProposal("proposal-a"), secondary: .entityProposal("proposal-b")),
                evidence("evidence-2", primary: .entityProposal("proposal-a"), secondary: .entityProposal("proposal-b"))
            ]
        )

        let result = CameraCoachDraftV3ProposalIngress.validate(response, against: context)

        XCTAssertFalse(result.accepted)
        XCTAssertTrue(result.violations.contains(.limitsExceeded))
        XCTAssertTrue(result.evidenceProposals.isEmpty, "limits must refuse, not truncate")
    }

    func testProviderOwnedDecisionFieldsAreRejected() throws {
        for field in ["finalDecision", "activeAction", "trackID", "qualificationRef", "verificationOutcome"] {
            let data = try makeEntityStrictJSON(extraField: field, value: "provider-owned")
            XCTAssertThrowsError(try CameraCoachDraftV3ProposalResponse.decodeStrict(data)) { error in
                XCTAssertEqual(
                    error as? CameraCoachDraftV3IngressDecodeError,
                    .forbiddenProviderField(field)
                )
            }
        }
    }

    func testUnsupportedProviderFieldIsTyped() throws {
        let data = try makeEntityStrictJSON(extraField: "providerScratch", value: "x")
        XCTAssertThrowsError(try CameraCoachDraftV3ProposalResponse.decodeStrict(data)) { error in
            XCTAssertEqual(error as? CameraCoachDraftV3IngressDecodeError, .unsupportedField("providerScratch"))
        }
    }

    func testSafeAttachmentSendabilityRejectsURLAndUnboundedRedaction() {
        let valid = attachment()
        let validRequest = CameraCoachDraftV3ProposalRequest(
            schemaVersion: .s2Draft1,
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            limits: limits(),
            attachments: [valid],
            isExplicitUserRequest: true,
            consentGranted: true
        )
        XCTAssertEqual(CameraCoachDraftV3ProposalIngress.validateForSend(validRequest), .sendable)
        XCTAssertEqual(
            CameraCoachDraftV3ProposalIngress.validateForSend(validRequest, remoteCapable: true),
            .sendable
        )

        let urlRequest = CameraCoachDraftV3ProposalRequest(
            schemaVersion: .s2Draft1,
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            limits: limits(),
            attachments: [attachment(opaqueRef: "https://model-issued.example/frame.jpg")],
            isExplicitUserRequest: true,
            consentGranted: true
        )
        XCTAssertEqual(
            CameraCoachDraftV3ProposalIngress.validateForSend(urlRequest),
            .notSent(violations: [.attachmentURLNotAllowed])
        )

        let unboundedRequest = CameraCoachDraftV3ProposalRequest(
            schemaVersion: .s2Draft1,
            correlation: makeCorrelation(),
            privacyMode: .redactedVisual,
            limits: limits(),
            attachments: [attachment(visibleRegion: nil)],
            isExplicitUserRequest: true,
            consentGranted: true
        )
        XCTAssertEqual(
            CameraCoachDraftV3ProposalIngress.validateForSend(unboundedRequest),
            .notSent(violations: [.unsafeAttachment])
        )

        let revoked = CameraCoachDraftV3ProposalRequest(
            schemaVersion: .s2Draft1,
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            limits: limits(),
            attachments: [],
            isExplicitUserRequest: true,
            consentGranted: false
        )
        XCTAssertEqual(
            CameraCoachDraftV3ProposalIngress.validateForSend(revoked),
            .notSent(violations: [.consentRevoked])
        )
    }

    func testRedactedAttachmentBoundsRegionClaims() {
        let context = CameraCoachDraftV3IngressContext(
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            isCurrentRequest: true,
            isCancelled: false,
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            groundedEntities: [object("object-a", label: "лампа"), object("object-b", label: "ваза")],
            proposalGroundings: [
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-a", groundedEntity: object("object-a", label: "лампа")
                ),
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-b", groundedEntity: object("object-b", label: "ваза")
                )
            ],
            attachments: [
                attachment(visibleRegion: CameraCoachDraftV3RawRect(x: 0, y: 0, width: 0.45, height: 0.45))
            ]
        )

        let result = CameraCoachDraftV3ProposalIngress.validate(makeDependentResponse(), against: context)

        XCTAssertTrue(result.violations.contains(.redactedRegionClaim))
        XCTAssertFalse(result.entityProposals.contains { $0.proposalID == "proposal-b" })
        XCTAssertTrue(result.entityProposals.contains { $0.proposalID == "proposal-a" })
    }

    // MARK: - Helpers

    private func correlation(analysisID: String, generation: UInt64, intentRevision: UInt64) -> CameraCoachDraftV3Correlation {
        CameraCoachDraftV3Correlation(
            requestID: "request-1",
            analysisID: analysisID,
            sessionID: "session-1",
            generation: generation,
            sceneID: "scene-1",
            intentRevision: intentRevision,
            anchorFrameRef: "frame-1",
            anchorTransformRef: "transform-1",
            catalogVersion: "catalog-1",
            policyVersion: "policy-1",
            coverage: .singleFrame
        )
    }

    private func limits(deadlineSeconds: Int = 20,
                        maxFrames: Int = 1,
                        maxObservations: Int = 8,
                        maxRelations: Int = 6) -> CameraCoachDraftV3ProposalLimits {
        CameraCoachDraftV3ProposalLimits(
            deadlineSeconds: deadlineSeconds,
            maxInputBytes: 256 * 1024,
            maxAttachmentBytes: 512 * 1024,
            maxAttachmentLongEdgePx: 1024,
            maxFrames: maxFrames,
            maxEntities: 2,
            maxObservations: maxObservations,
            maxRelations: maxRelations,
            maxOutputTokens: 1024
        )
    }

    private func attachment(opaqueRef: String = "opaque-frame-1-v1",
                            visibleRegion: CameraCoachDraftV3RawRect? = CameraCoachDraftV3RawRect(x: 0, y: 0, width: 1, height: 1)) -> CameraCoachDraftV3SafeAttachment {
        CameraCoachDraftV3SafeAttachment(
            frameRef: "frame-1",
            transformRef: "transform-1",
            coverage: .singleFrame,
            sourceKind: .locallyProcessedVersion,
            opaqueRef: opaqueRef,
            longEdgePx: 768,
            byteCount: 40_000,
            exifStripped: true,
            redactionApplied: true,
            visibleRegion: visibleRegion
        )
    }

    private func evidence(_ id: String,
                          primary: CameraCoachDraftV3Reference,
                          secondary: CameraCoachDraftV3Reference) -> CameraCoachDraftV3EvidenceProposal {
        CameraCoachDraftV3EvidenceProposal(
            proposalID: id,
            frameRef: "frame-1",
            dimension: .clutter,
            primaryRef: primary,
            secondaryRef: secondary,
            score: 0.80,
            confidence: 0.86,
            problem: .objectConflictsWithSubject
        )
    }

    private func makeEntityStrictJSON(extraField: String, value: String) throws -> Data {
        let data = try JSONEncoder().encode(makeResponse())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entities = try XCTUnwrap(object["entityProposals"] as? [[String: Any]])
        entities[0][extraField] = value
        object["entityProposals"] = entities
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func makeCorrelation() -> CameraCoachDraftV3Correlation {
        CameraCoachDraftV3Correlation(
            requestID: "request-1",
            analysisID: "analysis-1",
            sessionID: "session-1",
            generation: 1,
            sceneID: "scene-1",
            intentRevision: 1,
            anchorFrameRef: "frame-1",
            anchorTransformRef: "transform-1",
            catalogVersion: "catalog-1",
            policyVersion: "policy-1",
            coverage: .singleFrame
        )
    }

    private func makeContext() -> CameraCoachDraftV3IngressContext {
        CameraCoachDraftV3IngressContext(
            correlation: makeCorrelation(),
            privacyMode: .localAuthorizedStill,
            isCurrentRequest: true,
            isCancelled: false,
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            groundedEntities: [object("object-a", label: "лампа"), object("object-b", label: "ваза")],
            proposalGroundings: [
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-a", groundedEntity: object("object-a", label: "лампа")
                ),
                CameraCoachDraftV3LocalProposalGrounding(
                    proposalID: "proposal-b", groundedEntity: object("object-b", label: "ваза")
                )
            ]
        )
    }

    private func makeResponse(correlation: CameraCoachDraftV3Correlation? = nil,
                              status: CameraCoachDraftV3ResponseStatus = .completed,
                              refusalReason: String? = nil,
                              evidenceProposals: [CameraCoachDraftV3EvidenceProposal]? = nil) -> CameraCoachDraftV3ProposalResponse {
        let regionA = CameraCoachDraftV3Region(
            frameRef: "frame-1",
            space: .orientedFrame,
            transformRef: "transform-1",
            rect: CameraCoachDraftV3RawRect(x: 0.10, y: 0.20, width: 0.20, height: 0.25)
        )
        let regionB = CameraCoachDraftV3Region(
            frameRef: "frame-1",
            space: .orientedFrame,
            transformRef: "transform-1",
            rect: CameraCoachDraftV3RawRect(x: 0.50, y: 0.20, width: 0.20, height: 0.25)
        )
        let isEmpty = status == .refused || status == .unavailable
        return CameraCoachDraftV3ProposalResponse(
            schemaVersion: .s2Draft1,
            profile: .twoObjectLocalGroundedObservation,
            correlation: correlation ?? makeCorrelation(),
            status: status,
            refusalReason: refusalReason,
            entityProposals: isEmpty ? [] : [
                CameraCoachDraftV3ObjectProposal(
                    proposalID: "proposal-a", labelCandidate: "лампа", region: regionA, confidence: 0.90
                ),
                CameraCoachDraftV3ObjectProposal(
                    proposalID: "proposal-b", labelCandidate: "ваза", region: regionB, confidence: 0.88
                )
            ],
            evidenceProposals: isEmpty ? [] : (evidenceProposals ?? [
                evidence("evidence-1", primary: .entityProposal("proposal-a"), secondary: .entityProposal("proposal-b"))
            ]),
            relationProposals: isEmpty ? [] : [
                CameraCoachDraftV3RelationProposal(
                    proposalID: "relation-1",
                    frameRef: "frame-1",
                    relationType: .competesForAttention,
                    sourceRef: .entityProposal("proposal-a"),
                    targetRef: .entityProposal("proposal-b"),
                    dimension: .clutter,
                    score: 0.78,
                    confidence: 0.84,
                    supportedEvidenceProposalIDs: ["evidence-1"]
                )
            ]
        )
    }

    /// Response where `proposal-b` is the endpoint under test: evidence/relation
    /// that depend on it must be removed, `evidence-a`/`relation-a` stay valid
    /// through the independent local entity `object-b`.
    private func makeDependentResponse() -> CameraCoachDraftV3ProposalResponse {
        let regionA = CameraCoachDraftV3Region(
            frameRef: "frame-1",
            space: .orientedFrame,
            transformRef: "transform-1",
            rect: CameraCoachDraftV3RawRect(x: 0.10, y: 0.20, width: 0.20, height: 0.25)
        )
        let regionB = CameraCoachDraftV3Region(
            frameRef: "frame-1",
            space: .orientedFrame,
            transformRef: "transform-1",
            rect: CameraCoachDraftV3RawRect(x: 0.50, y: 0.20, width: 0.20, height: 0.25)
        )
        let evidenceA = CameraCoachDraftV3EvidenceProposal(
            proposalID: "evidence-a",
            frameRef: "frame-1",
            dimension: .clutter,
            primaryRef: .entityProposal("proposal-a"),
            secondaryRef: .localEntity("object-b"),
            score: 0.80,
            confidence: 0.86,
            problem: .objectConflictsWithSubject
        )
        let evidenceB = CameraCoachDraftV3EvidenceProposal(
            proposalID: "evidence-b",
            frameRef: "frame-1",
            dimension: .clutter,
            primaryRef: .entityProposal("proposal-b"),
            secondaryRef: .localEntity("object-a"),
            score: 0.70,
            confidence: 0.80,
            problem: .objectConflictsWithSubject
        )
        return CameraCoachDraftV3ProposalResponse(
            schemaVersion: .s2Draft1,
            profile: .twoObjectLocalGroundedObservation,
            correlation: makeCorrelation(),
            status: .completed,
            refusalReason: nil,
            entityProposals: [
                CameraCoachDraftV3ObjectProposal(
                    proposalID: "proposal-a", labelCandidate: "лампа", region: regionA, confidence: 0.90
                ),
                CameraCoachDraftV3ObjectProposal(
                    proposalID: "proposal-b", labelCandidate: "ваза", region: regionB, confidence: 0.88
                )
            ],
            evidenceProposals: [evidenceA, evidenceB],
            relationProposals: [
                CameraCoachDraftV3RelationProposal(
                    proposalID: "relation-a",
                    frameRef: "frame-1",
                    relationType: .competesForAttention,
                    sourceRef: .entityProposal("proposal-a"),
                    targetRef: .localEntity("object-b"),
                    dimension: .clutter,
                    score: 0.78,
                    confidence: 0.84,
                    supportedEvidenceProposalIDs: ["evidence-a"]
                ),
                CameraCoachDraftV3RelationProposal(
                    proposalID: "relation-b",
                    frameRef: "frame-1",
                    relationType: .competesForAttention,
                    sourceRef: .entityProposal("proposal-b"),
                    targetRef: .localEntity("object-a"),
                    dimension: .clutter,
                    score: 0.77,
                    confidence: 0.83,
                    supportedEvidenceProposalIDs: ["evidence-b"]
                )
            ]
        )
    }

    private func object(_ id: String, label: String) -> VLMGroundedEntity {
        VLMGroundedEntity(
            entityRef: id,
            kind: .object,
            role: .foregroundObject,
            region: NormalizedRect(x: 0.1, y: 0.2, width: 0.2, height: 0.25),
            detectorLabel: label,
            detectorConfidence: 0.9,
            displayLabelCandidate: label,
            displayLabelConfidence: 0.9
        )
    }
}
