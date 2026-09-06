import XCTest
@testable import shafinMultitool

/// M10-021: tier budgets degrade monotonically — constrained never exceeds
/// nominal, eco never exceeds constrained; heavy models switch off under
/// pressure; the snapshot mode follows the budget truthfully.
final class iPadPerformanceTierTests: XCTestCase {

    func testBudgetsDegradeMonotonicallyAcrossTiers() {
        let nominalGovernor = ThermalGovernor(thermalStateProvider: { .nominal },
                                              batteryLevelProvider: { 1.0 })
        let fairGovernor = ThermalGovernor(thermalStateProvider: { .fair },
                                            batteryLevelProvider: { 1.0 })
        let criticalGovernor = ThermalGovernor(thermalStateProvider: { .critical },
                                                batteryLevelProvider: { 0.2 })
        let nominal = nominalGovernor.nextBudget()
        let fair = fairGovernor.nextBudget()
        let critical = criticalGovernor.nextBudget()

        XCTAssertLessThanOrEqual(fair.highPriorityFrequency, nominal.highPriorityFrequency)
        XCTAssertLessThanOrEqual(critical.highPriorityFrequency, fair.highPriorityFrequency)
        XCTAssertFalse(critical.heavyModelsEnabled, "critical tier must shed heavy models")
    }

    func testSnapshotModeFollowsBudgetTruthfully() {
        let eco = CameraRuntimePerformanceSnapshot(budget: ThermalGovernor.Budget(
            highPriorityFrequency: 2, mediumPriorityFrequency: 1,
            lowPriorityFrequency: 0.25, heavyModelsEnabled: false))
        XCTAssertTrue(eco.isLimited)
        XCTAssertEqual(eco.mode, .eco)
        XCTAssertFalse(CameraRuntimePerformanceSnapshot.nominal.isLimited)
    }
}
