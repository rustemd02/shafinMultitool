import XCTest
@testable import shafinMultitool

final class ThermalGovernorTests: XCTestCase {

    func testNominalBudgetAllowsOnlyReducedLiveCadenceWithHeavyModels() {
        let budget = makeGovernor(thermalState: .nominal, batteryLevel: 1.0).nextBudget()

        XCTAssertEqual(budget.highPriorityFrequency, 6, accuracy: 0.0001)
        XCTAssertEqual(budget.mediumPriorityFrequency, 2, accuracy: 0.0001)
        XCTAssertEqual(budget.lowPriorityFrequency, 0.25, accuracy: 0.0001)
        XCTAssertTrue(budget.heavyModelsEnabled)
    }

    func testFairBudgetDisablesHeavyModelsAndLowPriorityWork() {
        let governor = makeGovernor(thermalState: .fair, batteryLevel: 1.0)
        let budget = governor.nextBudget()

        XCTAssertEqual(governor.currentTier(), .constrained)
        XCTAssertEqual(budget.highPriorityFrequency, 4, accuracy: 0.0001)
        XCTAssertEqual(budget.mediumPriorityFrequency, 1, accuracy: 0.0001)
        XCTAssertEqual(budget.lowPriorityFrequency, 0, accuracy: 0.0001)
        XCTAssertFalse(budget.heavyModelsEnabled)
    }

    func testSeriousBudgetUsesConstrainedCadence() {
        let governor = makeGovernor(thermalState: .serious, batteryLevel: 1.0)
        let budget = governor.nextBudget()

        XCTAssertEqual(governor.currentTier(), .constrained)
        XCTAssertEqual(budget.highPriorityFrequency, 2, accuracy: 0.0001)
        XCTAssertEqual(budget.mediumPriorityFrequency, 0.5, accuracy: 0.0001)
        XCTAssertEqual(budget.lowPriorityFrequency, 0, accuracy: 0.0001)
        XCTAssertFalse(budget.heavyModelsEnabled)
    }

    func testCriticalBudgetKeepsOnlyMinimalHighPriorityWork() {
        let governor = makeGovernor(thermalState: .critical, batteryLevel: 1.0)
        let budget = governor.nextBudget()

        XCTAssertEqual(governor.currentTier(), .critical)
        XCTAssertEqual(budget.highPriorityFrequency, 0.5, accuracy: 0.0001)
        XCTAssertEqual(budget.mediumPriorityFrequency, 0, accuracy: 0.0001)
        XCTAssertEqual(budget.lowPriorityFrequency, 0, accuracy: 0.0001)
        XCTAssertFalse(budget.heavyModelsEnabled)
    }

    func testLowBatteryCapsNominalThermalStateAtSeriousBudget() {
        let budget = makeGovernor(thermalState: .nominal, batteryLevel: 0.19).nextBudget()

        XCTAssertEqual(budget.highPriorityFrequency, 2, accuracy: 0.0001)
        XCTAssertEqual(budget.mediumPriorityFrequency, 0.5, accuracy: 0.0001)
        XCTAssertEqual(budget.lowPriorityFrequency, 0, accuracy: 0.0001)
        XCTAssertFalse(budget.heavyModelsEnabled)
    }

    private func makeGovernor(thermalState: ProcessInfo.ThermalState,
                              batteryLevel: Float) -> ThermalGovernor {
        ThermalGovernor(
            thermalStateProvider: { thermalState },
            batteryLevelProvider: { batteryLevel }
        )
    }
}
