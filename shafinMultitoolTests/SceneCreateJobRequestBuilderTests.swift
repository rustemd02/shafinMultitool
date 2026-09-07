//
//  SceneCreateJobRequestBuilderTests.swift
//  shafinMultitoolTests
//
//  M12-004: builder enforces the frozen request limits; oversize,
//  unsupported-locale, and overflow inputs fail closed with typed errors.
//

import XCTest
@testable import shafinMultitool

final class SceneCreateJobRequestBuilderTests: XCTestCase {
    private func valid() -> SceneCreateJobRequest? {
        try? SceneCreateJobRequestBuilder.build(
            requestID: UUID(uuidString: "123E4567-E89B-42D3-A456-426614174000")!,
            clientBuild: "1.0 (1)",
            locale: "ru",
            scriptText: "МАРА подходит к столу.",
            markedObjectIDs: ["object_marked_deadbeef"],
            maximumScenes: 2,
            previousJobID: nil,
            modelVersion: "scene-model-v1",
            promptVersion: "scene-prompt-v1",
            providerName: "first-party-scene",
            providerVersion: "2026-09-01"
        ).get()
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
