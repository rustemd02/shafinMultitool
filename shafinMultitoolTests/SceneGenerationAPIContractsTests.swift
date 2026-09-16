//
//  SceneGenerationAPIContractsTests.swift
//  shafinMultitoolTests
//
//  M12-003: contract tests for the frozen Scene Generation job API.
//  Decodes the backend/schemas/fixtures job envelopes and asserts the
//  fail-closed validation verdicts. No network, no provider, no host.
//

import XCTest
@testable import shafinMultitool

final class SceneGenerationAPIContractsTests: XCTestCase {
    private func jobFixture(_ name: String) throws -> SceneJobStatus {
        let thisFile = URL(fileURLWithPath: #filePath)
        let root = thisFile
            .deletingLastPathComponent() // shafinMultitoolTests
            .deletingLastPathComponent() // repo root
        let url = root
            .appendingPathComponent("backend/schemas/fixtures")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SceneJobStatus.self, from: data)
    }

    func testPendingHasNoTerminalPayload() throws {
        let status = try jobFixture("job-valid-pending.json")
        XCTAssertEqual(status.status, .pending)
        XCTAssertEqual(status.schemaVersionBackend, SceneAPIVersion.backendSchemaVersion)
        XCTAssertEqual(SceneJobValidation.validate(status), .notTerminal)
    }

    func testRunningHasNoTerminalPayload() throws {
        let status = try jobFixture("job-valid-running.json")
        XCTAssertEqual(SceneJobValidation.validate(status), .notTerminal)
    }

    func testCompleteCarriesVersionMatchedResult() throws {
        let status = try jobFixture("job-valid-complete.json")
        guard case .complete(let result) = SceneJobValidation.validate(status) else {
            return XCTFail("expected complete, got \(SceneJobValidation.validate(status))")
        }
        XCTAssertEqual(result.modelVersion, status.modelVersion)
        XCTAssertEqual(result.promptVersion, status.promptVersion)
        XCTAssertEqual(result.schemaVersion, SceneAPIVersion.scriptSchemaVersion)
        XCTAssertFalse(result.sceneScript.beats.isEmpty)
    }

    func testAwaitingClarificationBindsSameRequest() throws {
        let status = try jobFixture("job-valid-awaiting-clarification.json")
        guard case .awaitingClarification(let payload) = SceneJobValidation.validate(status) else {
            return XCTFail("expected clarification, got \(SceneJobValidation.validate(status))")
        }
        XCTAssertEqual(payload.requestID, status.requestID)
    }

    func testFailedAndCancelledSurfaceTypedFailure() throws {
        let failed = try jobFixture("job-valid-failed.json")
        guard case .failed(let failure) = SceneJobValidation.validate(failed) else {
            return XCTFail("expected failed, got \(SceneJobValidation.validate(failed))")
        }
        XCTAssertEqual(failure.code, .providerError)
        let cancelled = try jobFixture("job-valid-cancelled.json")
        guard case .failed(let cancelledFailure) = SceneJobValidation.validate(cancelled) else {
            return XCTFail("expected failed, got \(SceneJobValidation.validate(cancelled))")
        }
        XCTAssertEqual(cancelledFailure.code, .cancelled)
    }

    func testClarificationRejectsDuplicateChoicesAndUnanswerableQuestion() throws {
        let original = try jobFixture("job-valid-awaiting-clarification.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        let originalQuestion = try XCTUnwrap(source["clarification"] as? [String: Any])
        let duplicateChoice = ["id": "same", "label": "A subject"]
        for mutation: [String: Any] in [
            ["options": [duplicateChoice, duplicateChoice]],
            ["options": [], "allowsFreeText": false],
            ["options": [], "allowsFreeText": true, "maximumFreeTextCharacters": 0],
            ["prompt": "   "]
        ] {
            var envelope = source
            var question = originalQuestion
            question.merge(mutation) { _, new in new }
            envelope["clarification"] = question
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let status = try decoder.decode(SceneJobStatus.self, from: JSONSerialization.data(withJSONObject: envelope))
            XCTAssertEqual(SceneJobValidation.validate(status), .rejected(.invalidClarificationPayload))
        }
    }

    func testCompleteWithoutResultIsRejected() throws {
        let status = try jobFixture("job-invalid-complete-missing-result.json")
        XCTAssertEqual(
            SceneJobValidation.validate(status),
            .rejected(.missingOrMixedTerminalPayload)
        )
    }

    func testCompleteWithFailureIsRejected() throws {
        let status = try jobFixture("job-invalid-complete-with-failure.json")
        XCTAssertEqual(
            SceneJobValidation.validate(status),
            .rejected(.missingOrMixedTerminalPayload)
        )
    }

    func testWrongBackendVersionIsRejected() throws {
        let status = try jobFixture("job-invalid-version.json")
        XCTAssertEqual(
            SceneJobValidation.validate(status),
            .rejected(.unknownBackendSchemaVersion)
        )
    }

    func testMalformedHashIsRejected() throws {
        let status = try jobFixture("job-invalid-hash.json")
        XCTAssertEqual(
            SceneJobValidation.validate(status),
            .rejected(.malformedRequestHash)
        )
    }

    func testStaleClarificationBindingIsRejected() throws {
        let status = try jobFixture("job-invalid-clarification-stale.json")
        XCTAssertEqual(
            SceneJobValidation.validate(status),
            .rejected(.staleClarificationBinding)
        )
    }

    func testKillSwitchFailureIsTerminalRejection() throws {
        var status = try jobFixture("job-valid-failed.json")
        status = SceneJobStatus(
            jobID: status.jobID,
            requestID: status.requestID,
            status: .failed,
            result: nil,
            clarification: nil,
            failure: SceneJobFailure(code: .killSwitch, message: "Service paused."),
            schemaVersionBackend: status.schemaVersionBackend,
            modelVersion: status.modelVersion,
            promptVersion: status.promptVersion,
            providerName: status.providerName,
            providerVersion: status.providerVersion,
            requestHash: status.requestHash,
            idempotencyKey: status.idempotencyKey,
            serverTime: status.serverTime
        )
        XCTAssertEqual(
            SceneJobValidation.validate(status),
            .rejected(.killSwitchEngaged)
        )
    }
}
