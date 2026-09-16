//
//  SceneCreateJobRequestBuilderTests.swift
//  shafinMultitoolTests
//
//  M12-004: builder enforces the frozen request limits; oversize,
//  unsupported-locale, and overflow inputs fail closed with typed errors.
//

import XCTest
import CryptoKit
import Foundation
@testable import shafinMultitool

final class SceneCreateJobRequestBuilderTests: XCTestCase {
    private func valid(
        scriptText: String = "МАРА подходит к столу.",
        markedObjectIDs: [String] = ["object_marked_deadbeef"],
        maximumScenes: Int = 2,
        previousJobID: String? = nil
    ) -> SceneCreateJobRequest? {
        try? SceneCreateJobRequestBuilder.build(
            requestID: UUID(uuidString: "123E4567-E89B-42D3-A456-426614174000")!,
            clientBuild: "1.0 (1)",
            locale: "ru",
            scriptText: scriptText,
            markedObjectIDs: markedObjectIDs,
            maximumScenes: maximumScenes,
            previousJobID: previousJobID,
            modelVersion: "scene-model-v1",
            promptVersion: "scene-prompt-v1",
            providerName: "first-party-scene",
            providerVersion: "2026-09-01"
        ).get()
    }

    private func encodedObject(_ request: SceneCreateJobRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testValidRequestBuildsVersionedHash() {
        guard let request = valid() else { return XCTFail("expected valid build") }
        XCTAssertEqual(request.schemaVersionBackend, SceneAPIVersion.backendSchemaVersion)
        XCTAssertEqual(request.schemaVersion, SceneAPIVersion.scriptSchemaVersion)
        XCTAssertNotNil(request.requestHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
    }

    func testHashIsDeterministic() {
        XCTAssertEqual(valid()?.requestHash, valid()?.requestHash)
    }

    func testWireEncodingUsesNestedPayloadAndRoundTrips() throws {
        let request = try XCTUnwrap(valid())
        let object = try encodedObject(request)
        let markedObjects = try XCTUnwrap(object["marked_objects"] as? [[String: String]])
        XCTAssertEqual(markedObjects, [["canonical_id": "object_marked_deadbeef"]])
        let constraints = try XCTUnwrap(object["constraints"] as? [String: Any])
        XCTAssertEqual((constraints["maximum_scenes"] as? NSNumber)?.intValue, 2)
        XCTAssertNil(object["maximum_scenes"])
        XCTAssertNil(object["previous_job_id"])
        XCTAssertEqual(try JSONDecoder().decode(SceneCreateJobRequest.self, from: JSONEncoder().encode(request)), request)
    }

    func testPresentPreviousJobIDIsEncodedAndRoundTrips() throws {
        let request = try XCTUnwrap(valid(previousJobID: "job_demo001"))
        let object = try encodedObject(request)
        XCTAssertEqual(object["previous_job_id"] as? String, "job_demo001")
        XCTAssertEqual(
            try JSONDecoder().decode(SceneCreateJobRequest.self, from: JSONEncoder().encode(request)).previousJobID,
            "job_demo001"
        )
    }

    func testFlattenedWireFormatIsRejected() throws {
        let request = try XCTUnwrap(valid())
        var flattened = try encodedObject(request)
        flattened["marked_objects"] = ["object_marked_deadbeef"]
        flattened["maximum_scenes"] = 2
        flattened.removeValue(forKey: "constraints")
        let data = try JSONSerialization.data(withJSONObject: flattened)
        XCTAssertThrowsError(try JSONDecoder().decode(SceneCreateJobRequest.self, from: data))
    }

    func testHashUsesCanonicalProjectionOfActualEncoding() throws {
        let scriptText = "slash / emoji 😀 NUL \u{0000} backspace \u{0008} formfeed \u{000C} unit \u{001F} line \u{2028}"
        let request = try XCTUnwrap(valid(scriptText: scriptText))
        var object = try encodedObject(request)
        let requestHash = try XCTUnwrap(object.removeValue(forKey: "request_hash") as? String)
        let canonical = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(requestHash, digest)
        XCTAssertFalse(String(decoding: canonical, as: UTF8.self).contains("\\/"))
        let roundTrip = try JSONDecoder().decode(SceneCreateJobRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(roundTrip.scriptText, scriptText)
    }

    func testOversizeTextFailsClosed() {
        let result = SceneCreateJobRequestBuilder.build(
            requestID: UUID(),
            clientBuild: "1.0 (1)",
            locale: "en",
            scriptText: String(repeating: "x", count: 4001),
            markedObjectIDs: [],
            maximumScenes: 1,
            previousJobID: nil,
            modelVersion: "m",
            promptVersion: "p",
            providerName: "n",
            providerVersion: "v"
        )
        XCTAssertEqual(result.failure, .textLengthViolation)
    }

    func testUnsupportedLocaleFailsClosed() {
        let result = SceneCreateJobRequestBuilder.build(
            requestID: UUID(),
            clientBuild: "1.0 (1)",
            locale: "de",
            scriptText: "Text.",
            markedObjectIDs: [],
            maximumScenes: 1,
            previousJobID: nil,
            modelVersion: "m",
            promptVersion: "p",
            providerName: "n",
            providerVersion: "v"
        )
        XCTAssertEqual(result.failure, .unsupportedLocale)
    }

    func testMarkedObjectOverflowFailsClosed() {
        let result = SceneCreateJobRequestBuilder.build(
            requestID: UUID(),
            clientBuild: "1.0 (1)",
            locale: "en",
            scriptText: "Text.",
            markedObjectIDs: (0..<33).map { "object_\($0)" },
            maximumScenes: 1,
            previousJobID: nil,
            modelVersion: "m",
            promptVersion: "p",
            providerName: "n",
            providerVersion: "v"
        )
        XCTAssertEqual(result.failure, .markedObjectsViolation)
    }

    func testConstraintsBoundFailsClosed() {
        let result = SceneCreateJobRequestBuilder.build(
            requestID: UUID(),
            clientBuild: "1.0 (1)",
            locale: "en",
            scriptText: "Text.",
            markedObjectIDs: [],
            maximumScenes: 9,
            previousJobID: nil,
            modelVersion: "m",
            promptVersion: "p",
            providerName: "n",
            providerVersion: "v"
        )
        XCTAssertEqual(result.failure, .constraintsViolation)
    }
}

private extension Result where Success == SceneCreateJobRequest, Failure == SceneRequestBuildError {
    var failure: SceneRequestBuildError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
