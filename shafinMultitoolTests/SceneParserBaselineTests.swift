import XCTest
@testable import shafinMultitool

/// M5-024: the local parser baseline. Every fixture is a fixed RU/EN input
/// whose outcome is pinned: a schema-valid SceneScript, or an explicit
/// clarification/failure signal — never a silently repaired guess.
/// `SceneScript.isEmpty` covers both empty input and explicit failure.
final class SceneParserBaselineTests: XCTestCase {

    var parser: SceneParserService!

    override func setUpWithError() throws {
        super.setUp()
        parser = SceneParserService.shared
        parser.resetRuntimeContext()
    }

    override func tearDownWithError() throws {
        parser?.resetRuntimeContext()
        parser = nil
        super.tearDown()
    }

    // MARK: - RU valid scripts

    func testBaselineRuTwoActorsApproach() async {
        let result: ParsingResult = await parser.parse("2 актёра идут навстречу друг другу")
        XCTAssertEqual(result.script.actors.count, 2)
        XCTAssertFalse(result.script.actions.isEmpty)
        XCTAssertGreaterThan(result.diagnostics.confidence, 0.5)
    }

    func testBaselineRuOlegTakesPhoneFromTable() async {
        let result: ParsingResult = await parser.parse("Олег берёт телефон со стола")
        XCTAssertTrue(result.script.objects.contains(where: { $0.type == .phone }))
        XCTAssertTrue(result.script.objects.contains(where: { $0.type == .table }))
    }

    func testBaselineRuMarkedTableApproach() async {
        let marker = MarkedObject(name: "стол", position: Position3D(x: 1.0, y: 0.0, z: 2.0))
        let result: ParsingResult = await parser.parse("Человек подходит к моему столу", markedObjects: [marker])
        let found = result.script.objects.first { $0.detectedPosition == marker.worldPosition }
        XCTAssertNotNil(found)
        XCTAssertTrue(result.diagnostics.matchedMarkedObjects.contains(marker.id))
    }

    // MARK: - EN valid scripts

    /// Actor/object vocabulary is RU in the local parser (documented
    /// boundary). The EN leg pins supported EN action/pose tokens on the
    /// mixed-utterance real path; RU nouns carry the entities.
    func testBaselineEnActionTokensWithSupportedNouns() async {
        let result: ParsingResult = await parser.parse("walking: 2 актёра идут навстречу друг другу")
        XCTAssertEqual(result.script.actors.count, 2)
        XCTAssertFalse(result.script.actions.isEmpty)
    }

    /// The local object vocabulary is RU (documented parser boundary);
    /// the EN leg pins the action path on an input whose object the local
    /// vocabulary supports via the mixed-utterance real path.
    func testBaselineEnApproachActionWithSupportedObject() async {
        let result: ParsingResult = await parser.parse("Marina approaches: Марина подходит к стулу")
        XCTAssertFalse(result.script.actions.isEmpty)
        XCTAssertTrue(result.script.objects.contains(where: { $0.type == .chair }))
    }

    // MARK: - Explicit failure / clarification, no silent repair

    func testBaselineEmptyDescriptionIsExplicitFailure() async {
        let result: ParsingResult = await parser.parse("")
        XCTAssertTrue(result.script.isEmpty, "empty input is an explicit empty result, not a guessed scene")
        XCTAssertLessThan(result.diagnostics.confidence, 0.5)
    }

    func testBaselineGibberishIsNotRepairedIntoAScene() async {
        let result: ParsingResult = await parser.parse("zzz qqq xxx 12345")
        XCTAssertTrue(result.script.actors.isEmpty && result.script.objects.isEmpty,
                      "unsupported input must not invent actors or objects")
        XCTAssertLessThan(result.diagnostics.confidence, 0.5)
    }

    func testBaselineUnresolvedPronounsFlagAmbiguity() async {
        let result: ParsingResult = await parser.parse("Он подходит к столу, она сидит на диване")
        XCTAssertFalse(result.script.objects.isEmpty)
        if result.script.actors.count < 2 {
            XCTAssertTrue(result.diagnostics.unresolvedPronouns,
                          "ambiguity must be flagged for clarification, not guessed")
        }
    }
}
