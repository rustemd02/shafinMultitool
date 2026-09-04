import XCTest
@testable import shafinMultitool

final class SceneJourneyContractTests: XCTestCase {
    func testProductionContractIsCompleteAndTyped() {
        let contract = SceneJourneyContract.production
        XCTAssertTrue(contract.validate())
        XCTAssertEqual(Set(contract.states.map(\.id)).count, contract.states.count)
        XCTAssertTrue(contract.states.allSatisfy { !$0.owner.rawValue.isEmpty && !$0.persistence.rawValue.isEmpty })
        XCTAssertTrue(contract.states.allSatisfy { !$0.downstreamArtifacts.isEmpty || $0.state == .libraryEmpty })
    }
}
