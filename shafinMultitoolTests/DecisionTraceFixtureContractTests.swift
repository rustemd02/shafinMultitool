import XCTest
@testable import shafinMultitool

/// M5-035: the seeded decision-trace fixture builds the full chosen-action
/// contract — one action row with linked evidence, one evidence row, and the
/// domain trace ID — through the production `makeHintDecisionTrace` owner.
@MainActor
final class DecisionTraceFixtureContractTests: XCTestCase {

    func testSeededFixtureBuildsChosenActionContract() {
        let viewModel = SceneGeneratorViewModel(projectName: "trace-fixture-\(UUID().uuidString)")
        viewModel.seedDebugDecisionTraceFixtureForTesting()

        let trace = viewModel.makeHintDecisionTrace()
        let unwrapped = try! XCTUnwrap(trace)
        XCTAssertEqual(unwrapped.actionRows.count, 1)
        XCTAssertEqual(unwrapped.evidenceRows.count, 1)
        XCTAssertEqual(unwrapped.actionRows.first?.semanticActionId, "simplify_background")
        XCTAssertFalse(unwrapped.traceIds.isEmpty, "linked domain trace ID must travel with the action")
        XCTAssertEqual(unwrapped.actionRows.first?.linkedEvidenceIds.count, 1)
    }

    func testSeededFixtureContractHoldsInEnglishLocale() {
        let viewModel = SceneGeneratorViewModel(projectName: "trace-fixture-en-\(UUID().uuidString)")
        viewModel.setPresentationLocale(Locale(identifier: "en"))
        viewModel.seedDebugDecisionTraceFixtureForTesting()

        let trace = try! XCTUnwrap(viewModel.makeHintDecisionTrace())
        XCTAssertEqual(trace.actionRows.count, 1)
        XCTAssertFalse(trace.traceIds.isEmpty)
    }
}
