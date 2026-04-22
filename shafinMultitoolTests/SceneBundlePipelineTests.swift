//
//  SceneBundlePipelineTests.swift
//  shafinMultitoolTests
//
//  Created on 22.04.2026.
//

import XCTest
@testable import shafinMultitool

final class SceneBundlePipelineTests: XCTestCase {
    private var parser: SceneParserService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        parser = SceneParserService.shared
        parser.resetRuntimeContext()
    }

    override func tearDownWithError() throws {
        parser?.resetRuntimeContext()
        parser = nil
        try super.tearDownWithError()
    }

    func testParseBundleReturnsMultipleScenesForHeadings() throws {
        let description = """
        INT. OFFICE - NIGHT
        Человек подходит к столу.

        EXT. STREET - DAY
        Женщина идёт к двери.
        """

        let result = parser.parseBundle(description, markedObjects: [])

        XCTAssertEqual(result.bundleScript.scenes.count, 2)
        XCTAssertEqual(result.documentState.sceneCandidates.count, 2)
        XCTAssertEqual(result.bundleScript.activeSceneIndex, 1)
        XCTAssertEqual(result.bundleScript.scenes.first?.locationName, "OFFICE")
        XCTAssertEqual(result.bundleScript.scenes.last?.locationName, "STREET")
        XCTAssertFalse(result.sceneChunks.isEmpty)
    }

    func testParseCompatibilityReturnsActiveSceneFromBundle() throws {
        let description = """
        INT. OFFICE - NIGHT
        Человек подходит к столу.

        EXT. STREET - DAY
        Женщина идёт к двери.
        """

        let compatibility = parser.parse(description, markedObjects: [])
        let bundle = try XCTUnwrap(parser.lastBundleResult)
        let activeScene = try XCTUnwrap(bundle.activeSceneScript)

        XCTAssertEqual(compatibility.script.locationName, activeScene.locationName)
        XCTAssertEqual(compatibility.script.beats.count, activeScene.beats.count)
        XCTAssertEqual(parser.lastDocumentState?.bundleScript.scenes.count, 2)
    }

    func testParseBundleProducesCanonicalStableRefsInChunks() throws {
        let description = "Человек подходит к столу, затем садится на стул."

        let result = parser.parseBundle(description, markedObjects: [])
        let stitchState = try XCTUnwrap(result.documentState.stitchStates.last)
        let actorRefs = stitchState.actors.map(\.ref)
        let objectRefs = stitchState.objects.map(\.ref)

        XCTAssertFalse(actorRefs.isEmpty)
        XCTAssertTrue(actorRefs.allSatisfy { $0.hasPrefix("actor_scene") })
        XCTAssertTrue(objectRefs.allSatisfy { $0.hasPrefix("object_scene") || $0.hasPrefix("object_marked_") })
        XCTAssertFalse(result.sceneChunks.isEmpty)
    }

    func testParseBundleAppendModeExtendsTailSceneWithoutChangingSceneCount() throws {
        let initialDescription = "Человек подходит к столу."
        let initial = parser.parseBundle(initialDescription, markedObjects: [])
        let appendedDescription = initialDescription + "\nПотом он садится на стул."

        let appended = parser.parseBundle(
            appendedDescription,
            markedObjects: [],
            mode: .append,
            previousState: initial.documentState
        )

        XCTAssertEqual(initial.bundleScript.scenes.count, 1)
        XCTAssertEqual(appended.bundleScript.scenes.count, 1)
        XCTAssertEqual(appended.documentState.sceneCandidates.count, 1)
        XCTAssertTrue(appended.bundleScript.activeSceneScript?.originalDescription.contains("садится на стул") ?? false)

        let initialActorRefs = Set(initial.documentState.stitchStates.last?.actors.map(\.ref) ?? [])
        let appendedActorRefs = Set(appended.documentState.stitchStates.last?.actors.map(\.ref) ?? [])
        XCTAssertEqual(initialActorRefs, appendedActorRefs)
    }

    func testParseBundleAppendModeCreatesNewSceneForNewHeading() throws {
        let initialDescription = "Человек подходит к столу."
        let initial = parser.parseBundle(initialDescription, markedObjects: [])
        let appendedDescription = """
        \(initialDescription)

        EXT. STREET - DAY
        Женщина идёт к двери.
        """

        let appended = parser.parseBundle(
            appendedDescription,
            markedObjects: [],
            mode: .append,
            previousState: initial.documentState
        )

        XCTAssertEqual(initial.bundleScript.scenes.count, 1)
        XCTAssertEqual(appended.bundleScript.scenes.count, 2)
        XCTAssertEqual(appended.documentState.sceneCandidates.count, 2)
        XCTAssertEqual(appended.bundleScript.scenes.last?.locationName, "STREET")
    }

    func testParseBundleSupportsNatHeadingAndGenericLocationDashTimeHeading() throws {
        let natDescription = """
        НАТ. ПЛЯЖ - ВЕЧЕР
        Человек идёт к воде.
        """
        let genericDescription = """
        KITCHEN - NIGHT
        Женщина открывает дверь.
        """

        let natResult = parser.parseBundle(natDescription, markedObjects: [])
        let genericResult = parser.parseBundle(genericDescription, markedObjects: [])

        XCTAssertEqual(natResult.bundleScript.scenes.first?.interiorExterior, "exterior")
        XCTAssertEqual(natResult.bundleScript.scenes.first?.timeOfDay, "evening")
        XCTAssertEqual(genericResult.documentState.sceneCandidates.count, 1)
        XCTAssertEqual(genericResult.bundleScript.scenes.first?.locationName, "KITCHEN")
    }

    func testParseBundleFullModeReusesUnchangedScenesFromPreviousState() throws {
        let initialDescription = """
        INT. OFFICE - NIGHT
        Человек подходит к столу.

        EXT. STREET - DAY
        Женщина идёт к двери.
        """
        let initial = parser.parseBundle(initialDescription, markedObjects: [])
        let changedDescription = """
        INT. OFFICE - NIGHT
        Человек подходит к столу.

        EXT. STREET - DAY
        Женщина быстро идёт к двери.
        """

        let changed = parser.parseBundle(
            changedDescription,
            markedObjects: [],
            mode: .full,
            previousState: initial.documentState
        )

        XCTAssertEqual(initial.bundleScript.scenes.count, 2)
        XCTAssertEqual(changed.bundleScript.scenes.count, 2)
        XCTAssertEqual(
            initial.documentState.stitchStates.first?.chunkLedger,
            changed.documentState.stitchStates.first?.chunkLedger
        )
        XCTAssertNotEqual(
            initial.documentState.stitchStates.last?.sourceText,
            changed.documentState.stitchStates.last?.sourceText
        )
    }
}
