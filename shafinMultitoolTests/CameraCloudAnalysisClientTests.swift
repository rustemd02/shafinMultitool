import CoreMedia
import Foundation
import XCTest
@testable import shafinMultitool

/// Synthetic still + intercepted URLSession only. These tests do not enroll, upload,
/// contact a provider, or claim that descriptive cloud evidence is valid local advice.
final class CameraCloudAnalysisClientTests: XCTestCase {
    func testExactImageEdgeRemainsZeroAfterVisionCoordinateConversion() throws {
        let fixture = try fixture()
        defer { fixture.close() }
        let context = makeContext(primaryRegion: .init(x: 0.2, y: 0.8, width: 0.3, height: 0.2))
        let prepared = try fixture.client.prepare(still: makeStill(), context: context, locale: "en")
        let region = try XCTUnwrap(prepared.wireRequest.local_context.known_entities.first?.region)
        XCTAssertEqual(region.y, 0)
        XCTAssertTrue(CameraCloudEvidenceWire.unit(region.y))
        XCTAssertThrowsError(try fixture.client.prepare(
            still: makeStill(),
            context: makeContext(primaryRegion: .init(x: 0.2, y: 0.8, width: 0.3, height: 0.21)),
            locale: "en"
        ))
    }

    func testLowConfidenceRelationRequiresUncertaintyAndTextCannotBeBlank() throws {
        let request = wireRequest()
        let original = try responseObject(requestBody: request.encoded())
        let low = try changing(original, path: ["evidence", "relations", "0", "confidence"][...], value: 0.44)
        try assertRejected(low, request: request)
        let uncertain = try changing(low, path: ["evidence", "relations", "0", "uncertainty_reasons"][...],
                                     value: ["low_visual_confidence"])
        XCTAssertEqual(try decode(uncertain, request: request).evidence.relations.first?.confidence, 0.44)
        for path in [["evidence", "observations", "0", "rationale"],
                     ["evidence", "relations", "0", "rationale"]] {
            try assertRejected(changing(original, path: path[...], value: "   "), request: request)
        }
        let abstained = try changing(original, path: ["evidence"][...], value: [
            "observations": [], "relations": [], "abstained": true, "abstention_reason": "   "
        ] as [String: Any])
        try assertRejected(abstained, request: request)
    }

    func testEvidenceArraysRespectBoundsWithUniqueIdentifiers() throws {
        let request = wireRequest()
        let original = try responseObject(requestBody: request.encoded())
        let evidence = try XCTUnwrap(original["evidence"] as? [String: Any])
        let observation = try XCTUnwrap((evidence["observations"] as? [[String: Any]])?.first)
        let relation = try XCTUnwrap((evidence["relations"] as? [[String: Any]])?.first)
        let observations = (0..<9).map { index -> [String: Any] in
            var item = observation; item["observation_id"] = "observation-\(index)"; return item
        }
        let relations = (0..<7).map { index -> [String: Any] in
            var item = relation; item["relation_id"] = "relation-\(index)"; return item
        }
        try assertRejected(changing(original, path: ["evidence", "observations"][...],
                                    value: observations), request: request)
        try assertRejected(changing(original, path: ["evidence", "relations"][...],
                                    value: relations), request: request)
    }

    func testPrepareIsInertAndBindsExactStillContextNullsAndCoordinates() async throws {
        let fixture = try fixture()
        defer { fixture.close() }
        let still = makeStill()
        let context = makeContext()
        let prepared = try fixture.client.prepare(still: still, context: context, locale: "ru-RU")
        let body = try object(prepared.body)
        let media = try XCTUnwrap(body["media"] as? [String: Any])
        let correlation = try XCTUnwrap(body["correlation"] as? [String: Any])
        let pts = try XCTUnwrap(correlation["frame_pts"] as? [String: Any])
        let local = try XCTUnwrap(body["local_context"] as? [String: Any])
        let entities = try XCTUnwrap(local["known_entities"] as? [[String: Any]])
        let person = try XCTUnwrap(entities.first { $0["entity_ref"] as? String == "person-1" })
        let region = try XCTUnwrap(person["region"] as? [String: Any])
        let frame = try XCTUnwrap(entities.first { $0["entity_ref"] as? String == "frame-1" })
        XCTAssertEqual(body["locale"] as? String, "ru")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(media["data"] as? String)), still.jpegData)
        XCTAssertEqual(prepared.transfer.jpegData, still.jpegData)
        XCTAssertEqual(media["sha256"] as? String, still.sha256)
        XCTAssertEqual(media["width"] as? Int, 160)
        XCTAssertEqual(media["height"] as? Int, 96)
        XCTAssertEqual(media["metadata_stripped"] as? Bool, true)
        XCTAssertEqual(media["redaction"] as? String, "none")
        XCTAssertEqual(correlation["frame_id"] as? String, still.provenance.sourceFrameID)
        XCTAssertEqual(correlation["snapshot_id"] as? String, still.provenance.snapshotID)
        XCTAssertEqual(correlation["capture_session_id"] as? String, "capture-session:0")
        XCTAssertEqual(correlation["capture_generation"] as? Int, 7)
        XCTAssertEqual(correlation["scene_epoch"] as? Int, context.pauseRevision)
        XCTAssertEqual(correlation["intent_revision"] as? Int, Int(context.intentRevision))
        XCTAssertEqual(pts["value"] as? Int, 1_201)
        XCTAssertEqual(pts["timescale"] as? Int, 600)
        XCTAssertEqual(pts["flags"] as? Int, Int(CMTimeFlags.valid.rawValue))
        XCTAssertEqual(pts["epoch"] as? Int, 2)
        XCTAssertEqual(region["y"] as? Double ?? -1, 0.55, accuracy: 0.000_001)
        XCTAssertTrue(frame["region"] is NSNull)
        XCTAssertTrue(frame["detector_label"] is NSNull)
        XCTAssertTrue(frame["confidence"] is NSNull, "Unknown detector support must not become zero")
        XCTAssertEqual(local["intent_answers"] as? [String: Bool], ["silhouette": false])
        XCTAssertEqual(prepared.transfer.requestHash, CameraCloudTransferPolicy.sha256(prepared.body))
        XCTAssertEqual(prepared.visualRequest.privacyTier, .authorizedSelectedStill)
        XCTAssertEqual(prepared.visualRequest.trigger, .explicitUserRequest)
        XCTAssertTrue(prepared.visualRequest.validate().isEmpty)
        XCTAssertEqual(prepared.context, context)
        let calls = await fixture.tokens.counts()
        XCTAssertEqual(calls.current, 0)
        XCTAssertTrue(calls.rejected.isEmpty)
        XCTAssertTrue(fixture.journal.requests.isEmpty)
    }

    func testEachApprovalBindingAndForeignPolicyRejectBeforeTokenLookup() async throws {
        let fixture = try fixture()
        defer { fixture.close() }
        let prepared = try fixture.client.prepare(still: makeStill(), context: makeContext(), locale: "en")
        let approval = prepared.transfer.approval
        let wrong: [CameraCloudTransferApproval] = [
            .init(requestID: UUID(), requestHash: approval.requestHash, policyFingerprint: approval.policyFingerprint),
            .init(requestID: approval.requestID, requestHash: String(repeating: "0", count: 64), policyFingerprint: approval.policyFingerprint),
            .init(requestID: approval.requestID, requestHash: approval.requestHash, policyFingerprint: String(repeating: "0", count: 64))
        ]
        for value in wrong {
            await assertError(.approvalRequired) { try await fixture.client.analyze(prepared, approval: value) }
        }
        let other = CameraCloudAnalysisClient(policy: try policy(endpoint: fixture.endpoint, version: "changed"),
                                             session: fixture.session, tokenProvider: fixture.tokens)
        await assertError(.invalidRequest) { try await other.analyze(prepared, approval: approval) }
        let calls = await fixture.tokens.counts()
        XCTAssertEqual(calls.current, 0)
        XCTAssertTrue(calls.rejected.isEmpty)
        XCTAssertTrue(fixture.journal.requests.isEmpty)
    }

    func testPrepareRejectsWrongFrameSnapshotHashDimensionsAndTimestampWithoutAuthentication() async throws {
        let fixture = try fixture()
        defer { fixture.close() }
        let valid = makeStill()
        let changes: [(String, CameraCloudPreparedStill)] = [
            ("hash", makeStill(hash: String(repeating: "0", count: 64))),
            ("zero width", makeStill(width: 0)),
            ("oversized edge", makeStill(width: 1_025)),
            ("unknown frame", makeStill(frameID: "another-frame")),
            ("unknown snapshot", makeStill(snapshotID: "another-snapshot")),
            ("invalid timestamp", makeStill(timestampFlags: 0)),
            ("zero generation", makeStill(generation: 0)),
            ("empty body", makeStill(bytes: Data())),
            ("oversized body", makeStill(bytes: Data(repeating: 1, count: 512 * 1_024 + 1)))
        ]
        for (label, still) in changes {
            XCTAssertThrowsError(try fixture.client.prepare(still: still, context: makeContext(), locale: "en"), label) {
                XCTAssertEqual($0 as? CameraCloudClientError, .invalidRequest, label)
            }
        }
        let context = makeContext()
        let badIntent = CameraCloudPauseContext(snapshotID: context.snapshotID,
            pipelineGeneration: context.pipelineGeneration, pauseRevision: context.pauseRevision,
            intentRevision: context.intentRevision, intentAnswers: ["invented": true], localRequest: context.localRequest)
        XCTAssertThrowsError(try fixture.client.prepare(still: valid, context: badIntent, locale: "en"))
        let calls = await fixture.tokens.counts()
        XCTAssertEqual(calls.current, 0)
        XCTAssertTrue(fixture.journal.requests.isEmpty)
    }

    func testOne401RetryUsesDifferentTokenAndIdenticalApprovedBodyAndIdentity() async throws {
        let fixture = try fixture()
        defer { fixture.close() }
        let prepared = try fixture.client.prepare(still: makeStill(), context: makeContext(), locale: "en")
        let reply = try responseData(requestBody: prepared.body)
        fixture.journal.configure { request, index in
            guard request.method == "POST" else { return .complete(204, Data()) }
            return index == 0 ? .complete(401, Data()) : .complete(200, reply)
        }
        let result = try await fixture.client.analyze(prepared, approval: prepared.transfer.approval)
        let posts = fixture.journal.requests.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 2)
        XCTAssertEqual(posts.map(\.body), [prepared.body, prepared.body])
        XCTAssertEqual(posts.map(\.authorization), ["Bearer first-token", "Bearer replacement-token"])
        XCTAssertEqual(Set(posts.compactMap(\.idempotencyKey)), [prepared.transfer.requestID.uuidString.lowercased()])
        XCTAssertEqual(Set(posts.compactMap(\.bodyHash)), [prepared.transfer.requestHash])
        XCTAssertEqual(Set(posts.map(\.path)), ["/proxy/v1/camera/evidence"])
        XCTAssertFalse(fixture.journal.requests.contains { $0.method == "DELETE" })
        let calls = await fixture.tokens.counts()
        XCTAssertEqual(calls.current, 1)
        XCTAssertEqual(calls.rejected, ["first-token"])
        XCTAssertEqual(result.request, prepared.visualRequest)
        XCTAssertEqual(result.response.requestId, prepared.visualRequest.requestId)
        XCTAssertEqual(result.response.frameId, prepared.visualRequest.frameId)
        XCTAssertEqual(result.response.mode, .pause)
        XCTAssertEqual(result.response.status, .completed)
        XCTAssertEqual(result.response.primaryEntityDisplayLabelCandidate, "герой")
        XCTAssertTrue(result.response.suggestedActionIds.isEmpty)
        XCTAssertTrue(result.response.observations.allSatisfy { $0.suggestedActionIds.isEmpty })
        XCTAssertNil(result.response.explanation)
        XCTAssertEqual(result.response.diagnostics.privacyTier, .authorizedSelectedStill)
        XCTAssertEqual(prepared.context.localRequest.localContext.critique.verdict, .mixed)
    }

    func testRepeated401AndUnchangedReplacementNeverCreateThirdContentAttempt() async throws {
        for replacement in ["replacement-token", "first-token"] {
            let fixture = try fixture(replacement: replacement)
            defer { fixture.close() }
            let deleted = expectation(description: "cleanup \(replacement)")
            fixture.journal.configure { request, _ in
                if request.method == "DELETE" { deleted.fulfill(); return .complete(204, Data()) }
                return .complete(401, Data())
            }
            let prepared = try fixture.client.prepare(still: makeStill(), context: makeContext(), locale: "en")
            await assertError(.authentication) { try await fixture.client.analyze(prepared, approval: prepared.transfer.approval) }
            await fulfillment(of: [deleted], timeout: 2)
            let posts = fixture.journal.requests.filter { $0.method == "POST" }
            XCTAssertEqual(posts.count, replacement == "first-token" ? 1 : 2)
            let calls = await fixture.tokens.counts()
            XCTAssertEqual(calls.current, 1)
            XCTAssertEqual(calls.rejected, ["first-token"])
            XCTAssertEqual(fixture.journal.requests.filter { $0.method == "DELETE" }.count, 1)
        }
    }

    func testCancellationDuringUncancellableTokenWaitNeverSendsContentOrCleanup() async throws {
        let entered = expectation(description: "token provider entered")
        let returned = expectation(description: "late token provider returned")
        let fixture = try fixture(holdToken: true, entered: entered, returned: returned)
        defer { fixture.close() }
        let prepared = try fixture.client.prepare(still: makeStill(), context: makeContext(), locale: "en")
        let finished = expectation(description: "cancelled caller finished")
        let outcome = Outcome()
        let task = Task {
            do { _ = try await fixture.client.analyze(prepared, approval: prepared.transfer.approval); outcome.success() }
            catch { outcome.failure(error) }
            finished.fulfill()
        }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(outcome.error is CancellationError)
        XCTAssertTrue(fixture.journal.requests.isEmpty)
        await fixture.tokens.release()
        await fulfillment(of: [returned], timeout: 2)
        let calls = await fixture.tokens.counts()
        XCTAssertEqual(calls.current, 1)
        XCTAssertTrue(calls.rejected.isEmpty)
        XCTAssertTrue(fixture.journal.requests.isEmpty, "A late App Attest callback cannot own a POST or DELETE")
    }

    func testCancellationAfterPOSTUsesExistingTokenForExactlyOneDeleteAndStopsContentTask() async throws {
        let fixture = try fixture()
        defer { fixture.close() }
        let posted = expectation(description: "POST entered")
        let stopped = expectation(description: "POST stopped")
        let deleted = expectation(description: "DELETE entered")
        fixture.journal.configure(onStoppedPOST: { stopped.fulfill() }) { request, _ in
            if request.method == "POST" { posted.fulfill(); return .idle }
            deleted.fulfill()
            return .complete(204, Data())
        }
        let prepared = try fixture.client.prepare(still: makeStill(), context: makeContext(), locale: "en")
        let finished = expectation(description: "caller finished")
        let outcome = Outcome()
        let task = Task {
            do { _ = try await fixture.client.analyze(prepared, approval: prepared.transfer.approval); outcome.success() }
            catch { outcome.failure(error) }
            finished.fulfill()
        }
        await fulfillment(of: [posted], timeout: 2)
        task.cancel()
        await fulfillment(of: [finished, stopped, deleted], timeout: 3)
        XCTAssertTrue(outcome.error is CancellationError)
        let requests = fixture.journal.requests
        XCTAssertEqual(requests.filter { $0.method == "POST" }.count, 1)
        let deletes = requests.filter { $0.method == "DELETE" }
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(deletes.first?.authorization, "Bearer first-token")
        XCTAssertEqual(deletes.first?.path, "/proxy/v1/camera/evidence/" + prepared.transfer.requestID.uuidString.lowercased())
        XCTAssertEqual(deletes.first?.body, Data())
        let calls = await fixture.tokens.counts()
        XCTAssertEqual(calls.current, 1)
        XCTAssertTrue(calls.rejected.isEmpty)
    }

    func testPrecancelledAnalyzeNeverAcquiresTokenOrDispatchesRequest() async throws {
        let fixture = try fixture()
        defer { fixture.close() }
        let prepared = try fixture.client.prepare(still: makeStill(), context: makeContext(), locale: "en")
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await fixture.client.analyze(prepared, approval: prepared.transfer.approval); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        let calls = await fixture.tokens.counts()
        XCTAssertEqual(calls.current, 0)
        XCTAssertTrue(fixture.journal.requests.isEmpty)
    }

    func testResponseRejectsEveryRequestAndCaptureBindingMutation() throws {
        let request = wireRequest()
        let body = try request.encoded()
        let original = try responseObject(requestBody: body)
        let changes: [([String], Any)] = [
            (["schema_version"], "camera_evidence_v2"), (["request_id"], "other-request"),
            (["request_sha256"], String(repeating: "0", count: 64)),
            (["media_sha256"], String(repeating: "0", count: 64)),
            (["policy_fingerprint"], String(repeating: "0", count: 64)),
            (["correlation", "frame_id"], "other-frame"), (["correlation", "snapshot_id"], "other-snapshot"),
            (["correlation", "capture_session_id"], "capture-session:99"),
            (["correlation", "capture_generation"], 8), (["correlation", "scene_epoch"], 4),
            (["correlation", "intent_revision"], 6), (["correlation", "frame_pts", "value"], 1_202),
            (["correlation", "frame_pts", "timescale"], 601),
            (["correlation", "frame_pts", "flags"], 0), (["correlation", "frame_pts", "epoch"], 3)
        ]
        _ = try decode(original, request: request)
        for (path, value) in changes {
            try assertRejected(changing(original, path: path[...], value: value), request: request, label: path.joined(separator: "."))
        }
    }

    func testResponseRejectsUnknownFieldsActionsVerdictsAndProviderIdentityAtEveryObjectBoundary() throws {
        let request = wireRequest()
        let original = try responseObject(requestBody: request.encoded())
        let paths: [[String]] = [[], ["correlation"], ["correlation", "frame_pts"], ["evidence"],
                                ["evidence", "observations", "0"], ["evidence", "relations", "0"]]
        for path in paths {
            for key in ["unknown_field", "suggested_action_ids", "verdict", "target_track_id", "display_label"] {
                let changed = try changing(original, path: (path + [key])[...], value: "not-authoritative")
                try assertRejected(changed, request: request, label: (path + [key]).joined(separator: "."))
            }
        }
    }

    func testResponseRejectsUnknownReferencesDuplicatesAndPolarityMismatches() throws {
        let request = wireRequest()
        let original = try responseObject(requestBody: request.encoded())
        let observation = ["evidence", "observations", "0"]
        let relation = ["evidence", "relations", "0"]
        let changes: [([String], Any)] = [
            (observation + ["entity_refs"], ["invented-entity"]),
            (observation + ["entity_refs"], ["person-1", "person-1"]),
            (observation + ["supporting_issue_ids"], ["invented-issue"]),
            (observation + ["supporting_strength_ids"], ["invented-strength"]),
            (observation + ["visual_problem_type"], NSNull()),
            (observation + ["visual_strength_type"], "good_subject_isolation"),
            (observation + ["dimension"], "invented_dimension"),
            (observation + ["uncertainty_reasons"], ["invented_reason"]),
            (relation + ["source_entity_ref"], "invented-entity"),
            (relation + ["target_entity_ref"], "vase-1"),
            (relation + ["supported_observation_ids"], ["invented-observation"]),
            (relation + ["supported_observation_ids"], []),
            (relation + ["relation_type"], "invented_relation")
        ]
        for (path, value) in changes {
            try assertRejected(changing(original, path: path[...], value: value), request: request, label: path.joined(separator: "."))
        }
        let evidence = try XCTUnwrap(original["evidence"] as? [String: Any])
        let observations = try XCTUnwrap(evidence["observations"] as? [[String: Any]])
        let relations = try XCTUnwrap(evidence["relations"] as? [[String: Any]])
        try assertRejected(changing(original, path: ["evidence", "observations"][...], value: observations + observations), request: request)
        try assertRejected(changing(original, path: ["evidence", "relations"][...], value: relations + relations), request: request)
    }

    func testResponseKeepsExplicitNullUnknownAndRejectsMissingRequiredOrNonfiniteScores() throws {
        let request = wireRequest()
        let original = try responseObject(requestBody: request.encoded())
        let decoded = try decode(original, request: request)
        XCTAssertNil(decoded.evidence.abstention_reason)
        XCTAssertNil(decoded.evidence.observations.first?.visual_strength_type)
        for path in [["evidence", "abstention_reason"], ["evidence", "observations", "0", "visual_strength_type"],
                     ["evidence", "observations", "0", "confidence"]] {
            try assertRejected(changing(original, path: path[...], value: nil), request: request)
        }
        for field in ["score", "confidence"] {
            for value in [NSNull(), -0.01, 1.01, "NaN", "Infinity"] as [Any] {
                try assertRejected(changing(original, path: ["evidence", "observations", "0", field][...], value: value), request: request)
            }
        }
        let text = String(decoding: try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys]), as: UTF8.self)
        for literal in ["1e400", "NaN", "Infinity", "-Infinity"] {
            let invalid = text.replacingOccurrences(of: "\"score\":0.75", with: "\"score\":" + literal)
            XCTAssertNotEqual(invalid, text)
            XCTAssertThrowsError(try CameraCloudEvidenceWire.decode(Data(invalid.utf8), request: request,
                bodyHash: CameraCloudTransferPolicy.sha256(try request.encoded()))) {
                XCTAssertEqual($0 as? CameraCloudClientError, .invalidResponse)
            }
        }
        var zero = try changing(original, path: ["evidence", "observations", "0", "score"][...], value: 0)
        zero = try changing(zero, path: ["evidence", "observations", "0", "confidence"][...], value: 0)
        zero = try changing(zero, path: ["evidence", "observations", "0", "uncertainty_reasons"][...], value: ["low_visual_confidence"])
        let zeroResponse = try decode(zero, request: request)
        XCTAssertEqual(zeroResponse.evidence.observations.first?.score, 0)
        XCTAssertEqual(zeroResponse.evidence.observations.first?.confidence, 0)
    }

    func testAbstentionAdaptsToRefusalAndCannotCarryObservationsOrActions() throws {
        let request = wireRequest()
        let original = try responseObject(requestBody: request.encoded())
        let abstention: [String: Any] = ["observations": [], "relations": [], "abstained": true,
                                       "abstention_reason": "Not enough visual evidence"]
        let changed = try changing(original, path: ["evidence"][...], value: abstention)
        let response = try decode(changed, request: request)
        let adapted = CameraCloudEvidenceWire.adapt(response, request: makeContext().localRequest,
                                                   policy: try policy(endpoint: URL(string: "https://fixture.invalid/proxy/v1")!), latencyMs: 12)
        XCTAssertEqual(adapted.status, .refused)
        XCTAssertTrue(adapted.observations.isEmpty)
        XCTAssertTrue(adapted.relations.isEmpty)
        XCTAssertTrue(adapted.suggestedActionIds.isEmpty)
        XCTAssertNil(adapted.primaryEntityRef)
        XCTAssertEqual(adapted.primaryEntityLabelConfidence, 0)
        XCTAssertEqual(adapted.diagnostics.fallbackReason, "Not enough visual evidence")
        try assertRejected(changing(changed, path: ["evidence", "abstention_reason"][...], value: NSNull()), request: request)
        let originalEvidence = try XCTUnwrap(original["evidence"] as? [String: Any])
        try assertRejected(changing(changed, path: ["evidence", "observations"][...], value: originalEvidence["observations"]), request: request)
    }

    private func assertError(_ expected: CameraCloudClientError,
                             operation: () async throws -> CameraCloudAnalyzedEvidence,
                             file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? CameraCloudClientError, expected, file: file, line: line) }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func changing(_ source: Any, path: ArraySlice<String>, value: Any?) throws -> Any {
        guard let key = path.first else { return try XCTUnwrap(value) }
        let tail = path.dropFirst()
        if var object = source as? [String: Any] {
            if tail.isEmpty { object[key] = value }
            else { object[key] = try changing(XCTUnwrap(object[key]), path: tail, value: value) }
            return object
        }
        var array = try XCTUnwrap(source as? [Any])
        let index = try XCTUnwrap(Int(key))
        guard array.indices.contains(index) else { throw CameraCloudClientError.invalidRequest }
        array[index] = try changing(array[index], path: tail, value: value)
        return array
    }

    private func decode(_ response: Any, request: CameraCloudEvidenceWire.Request) throws -> CameraCloudEvidenceWire.Response {
        try CameraCloudEvidenceWire.decode(JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
            request: request, bodyHash: CameraCloudTransferPolicy.sha256(request.encoded()))
    }

    private func assertRejected(_ response: Any, request: CameraCloudEvidenceWire.Request, label: String = "",
                                file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try decode(response, request: request), label, file: file, line: line) {
            XCTAssertEqual($0 as? CameraCloudClientError, .invalidResponse, label, file: file, line: line)
        }
    }

    private func responseData(requestBody: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: responseObject(requestBody: requestBody), options: [.sortedKeys])
    }

    private func responseObject(requestBody: Data) throws -> [String: Any] {
        let request = try object(requestBody)
        let media = try XCTUnwrap(request["media"] as? [String: Any])
        let consent = try XCTUnwrap(request["consent"] as? [String: Any])
        return ["schema_version": CameraCloudEvidenceWire.version,
                "request_id": try XCTUnwrap(request["request_id"]),
                "request_sha256": CameraCloudTransferPolicy.sha256(requestBody),
                "correlation": try XCTUnwrap(request["correlation"]),
                "media_sha256": try XCTUnwrap(media["sha256"]),
                "policy_fingerprint": try XCTUnwrap(consent["policy_fingerprint"]),
                "evidence": ["abstained": false, "abstention_reason": NSNull(),
                    "observations": [["observation_id": "observation-1", "dimension": "face_visibility",
                        "polarity": "supports_problem", "score": 0.75, "confidence": 0.8,
                        "uncertainty_reasons": [], "entity_refs": ["person-1", "vase-1"],
                        "visual_problem_type": "face_contour_occlusion", "visual_strength_type": NSNull(),
                        "supporting_issue_ids": [], "supporting_strength_ids": [],
                        "rationale": "Synthetic foreground shape crosses the face."]],
                    "relations": [["relation_id": "relation-1", "relation_type": "blocks",
                        "source_entity_ref": "vase-1", "target_entity_ref": "person-1", "dimension": "face_visibility",
                        "score": 0.75, "confidence": 0.8, "uncertainty_reasons": [],
                        "supported_observation_ids": ["observation-1"], "rationale": "Synthetic occlusion relation."]]]]
    }

    private func wireRequest() -> CameraCloudEvidenceWire.Request {
        let still = makeStill()
        return .init(request_id: "wire-fixture-request", locale: "en",
            correlation: .init(frame_id: "frame-1", snapshot_id: "snapshot-1", capture_session_id: "capture-session:0",
                capture_generation: 7, frame_pts: .init(value: 1_201, timescale: 600, flags: CMTimeFlags.valid.rawValue, epoch: 2),
                scene_epoch: 3, intent_revision: 5),
            consent: .init(nonce: "fixture-nonce", policy_fingerprint: String(repeating: "a", count: 64)),
            media: .init(data: still.jpegData.base64EncodedString(), sha256: still.sha256, width: 160, height: 96),
            local_context: .init(known_entities: [
                .init(entity_ref: "person-1", kind: .person, region: .init(x: 0.2, y: 0.55, width: 0.3, height: 0.3), detector_label: "person", confidence: 0.9),
                .init(entity_ref: "vase-1", kind: .prop, region: .init(x: 0.3, y: 0.4, width: 0.1, height: 0.2), detector_label: "vase", confidence: 0.8)],
                issue_ids: [], strength_ids: [], allowed_dimensions: VLMVisualEvidenceDimension.allCases,
                allowed_problem_types: VisualProblemType.allCases, allowed_strength_types: VisualStrengthType.allCases,
                allowed_relation_types: VLMEntityRelationType.allCases, intent_answers: ["silhouette": false]))
    }

    private func makeContext(primaryRegion: NormalizedRect = .init(x: 0.2, y: 0.15, width: 0.3, height: 0.3)) -> CameraCloudPauseContext {
        let frameID = "frame-1"
        let semantics = SceneSemanticsReport(frameId: frameID, mode: .pause,
            sceneType: .singleCharacterMedium, sceneTypeConfidence: 0.8,
            primarySubject: .init(kind: .person, label: "person", confidence: 0.8),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.3, backgroundClutterScore: 0.3),
            readability: .init(subjectReadable: true, lookSpaceAdequate: nil, edgePressureScore: 0.2, separationScore: 0.7),
            ambiguities: [], assumptions: [])
        let critique = CritiqueReport(frameId: frameID, mode: .pause, verdict: .mixed, verdictConfidence: 0.7,
            strengths: [], issues: [], summary: .init(id: "summary-1", shortVerdict: "Synthetic review", whyProblematic: "Unknown"),
            traceRefs: [], fallbackUsed: false)
        let plan = RecommendationPlan(frameId: frameID, mode: .pause, inputVerdict: .mixed, primaryAction: nil,
            secondaryActions: [], deferredActions: [], noChangeRationale: nil, planConfidence: 0.5)
        let entities: [VLMGroundedEntity] = [
            .init(entityRef: "person-1", kind: .person, role: .primarySubject,
                  region: primaryRegion, detectorLabel: "person", detectorConfidence: 0.9,
                  displayLabelCandidate: "герой", displayLabelConfidence: 0.9),
            .init(entityRef: "vase-1", kind: .prop, role: .faceContourOccluder,
                  region: .init(x: 0.3, y: 0.4, width: 0.1, height: 0.2), detectorLabel: "vase", detectorConfidence: 0.8,
                  displayLabelCandidate: "ваза", displayLabelConfidence: 0.8),
            .init(entityRef: "frame-1", kind: .frame, role: .primarySubject, region: nil,
                  detectorLabel: nil, detectorConfidence: nil, displayLabelCandidate: "кадр", displayLabelConfidence: 0)]
        let request = VLMVisualEvidenceRequest(schemaVersion: .s1, requestId: "local-request", frameId: frameID,
            mode: .pause, locale: "en", privacyTier: .structuredOnly, trigger: .ambiguousLocalCase, visualInput: nil,
            localContext: .init(frameFeatureSnapshotExcerpt: [:], sceneSemantics: semantics, critique: critique,
                recommendationPlan: plan, semanticTipDrafts: [], groundedEntities: entities, localNeuralEvidenceSummary: nil),
            allowedCatalog: .prS01, constraints: .default,
            correlation: .init(localCritiqueSummaryId: "summary-1", localPlanSummaryId: nil,
                semanticCatalogVersion: VLMAllowedSemanticCatalog.prS01.catalogVersion,
                offloadingSchemaVersion: nil, providerConfigVersion: "fixture", sessionEphemeralId: nil))
        return .init(snapshotID: "snapshot-1", pipelineGeneration: 9, pauseRevision: 3,
                     intentRevision: 5, intentAnswers: ["silhouette": false], localRequest: request)
    }

    private func makeStill(bytes: Data? = nil, hash: String? = nil, width: Int = 160,
                           frameID: String = "frame-1", snapshotID: String = "snapshot-1",
                           timestampFlags: UInt32 = CMTimeFlags.valid.rawValue, generation: UInt64 = 7) -> CameraCloudPreparedStill {
        // Actual 160x96 synthetic sRGB JPEG, generated and metadata-stripped locally.
        // The codec path has its own native tests; this fixture tests transport binding.
        let data = bytes ?? Data(base64Encoded: "/9j/4AAQSkZJRgABAQAASABIAAD/wAARCABgAKADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9sAQwABAQEBAQECAQECAwICAgMEAwMDAwQGBAQEBAQGBwYGBgYGBgcHBwcHBwcHCAgICAgICQkJCQkLCwsLCwsLCwsL/9sAQwECAgIDAwMFAwMFCwgGCAsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsL/90ABAAK/9oADAMBAAIRAxEAPwDzeiiiviz/AEUCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/9Dzeiiiviz/AEUCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/9Hzeiiiviz/AEUCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/9Lzeiiiviz/AEUCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/9Pzeiiiviz/AEUCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/9Tzeiiiviz/AEUCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/9k=")!
        return .init(jpegData: data, sha256: hash ?? CameraCloudTransferPolicy.sha256(data), pixelWidth: width, pixelHeight: 96,
            provenance: .init(snapshotID: snapshotID, sourceFrameID: frameID, capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sessionGeneration: 0, captureGeneration: generation,
                samplePresentationTimestamp: .init(value: 1_201, timescale: 600, flags: timestampFlags, epoch: 2),
                sourceOrientationRawValue: 1, lensID: "fixture-lens", sourcePixelWidth: 160, sourcePixelHeight: 96,
                displayPixelWidth: 160, displayPixelHeight: 96), redaction: .none)
    }

    private func policy(endpoint: URL, version: String = "fixture-v1") throws -> CameraCloudTransferPolicy {
        try XCTUnwrap(.init(serviceEndpoint: endpoint, operatorName: "Synthetic operator", providerName: "fixture-provider",
            providerVersion: "fixture-model", processingRegion: "Fixture region", imageRetention: "No fixture retention",
            requestMetadataRetention: "Fixture request retention", securityIdentityRetention: "Fixture identity retention",
            spendRecordRetention: "Fixture spend retention", deletionRequestProcedure: "Fixture deletion procedure",
            providerRetention: "Fixture provider retention", policyVersion: version,
            policyURL: URL(string: "https://fixture-policy.invalid/privacy")!))
    }

    private func fixture(replacement: String? = "replacement-token", holdToken: Bool = false,
                          entered: XCTestExpectation? = nil, returned: XCTestExpectation? = nil) throws -> Fixture {
        let host = "camera-" + UUID().uuidString.lowercased() + ".invalid"
        let endpoint = URL(string: "https://" + host + "/proxy/v1")!
        let journal = RequestJournal()
        StubProtocol.register(journal, host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        let tokens = TokenProvider(replacement: replacement, hold: holdToken, entered: entered, returned: returned)
        let client = CameraCloudAnalysisClient(policy: try policy(endpoint: endpoint), session: session, tokenProvider: tokens)
        return Fixture(endpoint: endpoint, session: session, tokens: tokens, client: client, journal: journal)
    }
}

private extension CameraCloudAnalysisClientTests {
    struct Fixture {
        let endpoint: URL
        let session: URLSession
        let tokens: TokenProvider
        let client: CameraCloudAnalysisClient
        let journal: RequestJournal
        func close() {
            session.invalidateAndCancel()
            StubProtocol.unregister(host: endpoint.host!)
        }
    }

    actor TokenProvider: SceneServiceTokenProviding {
        private let replacement: String?
        private let hold: Bool
        private let entered: XCTestExpectation?
        private let returned: XCTestExpectation?
        private var current = 0
        private var rejected: [String] = []
        private var waiting: CheckedContinuation<String?, Never>?
        init(replacement: String?, hold: Bool, entered: XCTestExpectation?, returned: XCTestExpectation?) {
            self.replacement = replacement; self.hold = hold; self.entered = entered; self.returned = returned
        }
        func currentServiceToken() async -> String? {
            current += 1
            entered?.fulfill()
            if hold {
                let token = await withCheckedContinuation { waiting = $0 }
                returned?.fulfill()
                return token
            }
            return "first-token"
        }
        func replacementServiceToken(afterRejecting token: String) async -> String? {
            rejected.append(token)
            return replacement
        }
        func release() { waiting?.resume(returning: "late-token"); waiting = nil }
        func counts() -> (current: Int, rejected: [String]) { (current, rejected) }
    }

    final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var storedError: Error?
        var error: Error? { lock.lock(); defer { lock.unlock() }; return storedError }
        func success() { lock.lock(); storedError = nil; lock.unlock() }
        func failure(_ error: Error) { lock.lock(); storedError = error; lock.unlock() }
    }

    struct RecordedRequest: Sendable {
        let method: String
        let path: String
        let body: Data
        let authorization: String?
        let idempotencyKey: String?
        let bodyHash: String?
    }

    enum Reply: Sendable { case complete(Int, Data), idle }

    final class RequestJournal: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [RecordedRequest] = []
        private var handler: @Sendable (RecordedRequest, Int) -> Reply = { _, _ in .complete(500, Data()) }
        private var onStoppedPOST: (@Sendable () -> Void)?
        var requests: [RecordedRequest] { lock.lock(); defer { lock.unlock() }; return values }
        func configure(onStoppedPOST: (@Sendable () -> Void)? = nil,
                       handler: @escaping @Sendable (RecordedRequest, Int) -> Reply) {
            lock.lock(); self.handler = handler; self.onStoppedPOST = onStoppedPOST; lock.unlock()
        }
        func record(_ request: URLRequest) -> Reply {
            let value = RecordedRequest(method: request.httpMethod ?? "GET", path: request.url!.path,
                body: Self.body(request), authorization: request.value(forHTTPHeaderField: "Authorization"),
                idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
                bodyHash: request.value(forHTTPHeaderField: "X-Camera-Request-SHA256"))
            lock.lock()
            let postIndex = values.filter { $0.method == "POST" }.count
            values.append(value)
            let handler = self.handler
            lock.unlock()
            return handler(value, postIndex)
        }
        func stoppedPOST() {
            lock.lock(); let callback = onStoppedPOST; onStoppedPOST = nil; lock.unlock()
            callback?()
        }
        private static func body(_ request: URLRequest) -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open(); defer { stream.close() }
            var output = Data()
            var bytes = [UInt8](repeating: 0, count: 4_096)
            while output.count <= CameraCloudEvidenceWire.maximumRequestBytes {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                output.append(contentsOf: bytes.prefix(count))
            }
            return output
        }
    }

    final class StubProtocol: URLProtocol, @unchecked Sendable {
        private static let registryLock = NSLock()
        private static var registry: [String: RequestJournal] = [:]
        private let queue = DispatchQueue(label: "camera-cloud-client-test-protocol")
        private var stopped = false
        private var journal: RequestJournal?
        static func register(_ journal: RequestJournal, host: String) {
            registryLock.lock(); registry[host] = journal; registryLock.unlock()
        }
        static func unregister(host: String) {
            registryLock.lock(); registry[host] = nil; registryLock.unlock()
        }
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            queue.async { [self] in
                guard !stopped else { return }
                Self.registryLock.lock()
                let value = Self.registry[request.url?.host ?? ""]
                Self.registryLock.unlock()
                guard let value else {
                    client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                    return
                }
                journal = value
                let reply = value.record(request)
                let status: Int
                let data: Data
                switch reply {
                case .complete(let code, let bytes): status = code; data = bytes
                case .idle: status = 200; data = Data()
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                    httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if case .complete = reply {
                    if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
                    client?.urlProtocolDidFinishLoading(self)
                }
            }
        }
        override func stopLoading() {
            queue.async { [self] in
                guard !stopped else { return }
                stopped = true
                if request.httpMethod == "POST" { journal?.stoppedPOST() }
            }
        }
    }
}
