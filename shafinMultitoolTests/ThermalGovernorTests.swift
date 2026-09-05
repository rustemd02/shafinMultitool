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

    func testNextBudgetPublishesEffectiveNominalAndEcoModes() {
        let store = CameraRuntimePerformanceStore.shared
        store.resetForTesting()

        _ = makeGovernor(thermalState: .nominal, batteryLevel: 1.0).nextBudget()
        XCTAssertEqual(store.currentSnapshot.mode, .nominal)
        XCTAssertEqual(store.currentSnapshot.thermalTier, .unrestricted)

        _ = makeGovernor(thermalState: .serious, batteryLevel: 1.0).nextBudget()
        XCTAssertEqual(store.currentSnapshot.mode, .eco)
        XCTAssertEqual(store.currentSnapshot.thermalTier, .constrained)

        store.resetForTesting()
    }

    func testConcurrentFixedProviderGovernorsReturnExactPolicyBudgets() {
        let fixtures: [(governor: ThermalGovernor, expected: BudgetTuple)] = [
            (makeGovernor(thermalState: .nominal, batteryLevel: 1.0),
             BudgetTuple(highPriorityFrequency: 6,
                         mediumPriorityFrequency: 2,
                         lowPriorityFrequency: 0.25,
                         heavyModelsEnabled: true)),
            (makeGovernor(thermalState: .fair, batteryLevel: 1.0),
             BudgetTuple(highPriorityFrequency: 4,
                         mediumPriorityFrequency: 1,
                         lowPriorityFrequency: 0,
                         heavyModelsEnabled: false)),
            (makeGovernor(thermalState: .serious, batteryLevel: 1.0),
             BudgetTuple(highPriorityFrequency: 2,
                         mediumPriorityFrequency: 0.5,
                         lowPriorityFrequency: 0,
                         heavyModelsEnabled: false)),
            (makeGovernor(thermalState: .critical, batteryLevel: 1.0),
             BudgetTuple(highPriorityFrequency: 0.5,
                         mediumPriorityFrequency: 0,
                         lowPriorityFrequency: 0,
                         heavyModelsEnabled: false)),
            (makeGovernor(thermalState: .nominal, batteryLevel: 0.19),
             BudgetTuple(highPriorityFrequency: 2,
                         mediumPriorityFrequency: 0.5,
                         lowPriorityFrequency: 0,
                         heavyModelsEnabled: false))
        ]
        let expectedPolicyTuples = fixtures.map { $0.expected }
        let iterationsPerFixture = 512

        DispatchQueue.concurrentPerform(iterations: fixtures.count * iterationsPerFixture) { index in
            let fixture = fixtures[index % fixtures.count]
            let actual = BudgetTuple(fixture.governor.nextBudget())

            XCTAssertTrue(expectedPolicyTuples.contains(actual), "Unexpected budget tuple: \(actual)")
            XCTAssertEqual(actual, fixture.expected)
        }
    }

    private func makeGovernor(thermalState: ProcessInfo.ThermalState,
                              batteryLevel: Float) -> ThermalGovernor {
        ThermalGovernor(
            thermalStateProvider: { thermalState },
            batteryLevelProvider: { batteryLevel }
        )
    }

    private struct BudgetTuple: Equatable {
        let highPriorityFrequency: Double
        let mediumPriorityFrequency: Double
        let lowPriorityFrequency: Double
        let heavyModelsEnabled: Bool

        init(highPriorityFrequency: Double,
             mediumPriorityFrequency: Double,
             lowPriorityFrequency: Double,
             heavyModelsEnabled: Bool) {
            self.highPriorityFrequency = highPriorityFrequency
            self.mediumPriorityFrequency = mediumPriorityFrequency
            self.lowPriorityFrequency = lowPriorityFrequency
            self.heavyModelsEnabled = heavyModelsEnabled
        }

        init(_ budget: ThermalGovernor.Budget) {
            self.init(highPriorityFrequency: budget.highPriorityFrequency,
                      mediumPriorityFrequency: budget.mediumPriorityFrequency,
                      lowPriorityFrequency: budget.lowPriorityFrequency,
                      heavyModelsEnabled: budget.heavyModelsEnabled)
        }
    }
}
