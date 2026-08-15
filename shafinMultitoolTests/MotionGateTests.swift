import Foundation
import XCTest
@testable import shafinMultitool

final class MotionGateTests: XCTestCase {

    func testInitialSnapshotIsStillStableAndCompatibilityReadsMatch() {
        let gate = MotionGate(startMotionUpdates: false)

        let snapshot = gate.snapshot()
        XCTAssertEqual(snapshot, MotionSnapshot(motionState: .still,
                                                shakeLevel: 0.0,
                                                isStable: true))
        assertCoherent(snapshot)
        assertCompatibilityReadsMatchSnapshot(of: gate)
    }

    func testMotionTransitionsUseExactMovingPanningAndStillHysteresisCounts() {
        let gate = MotionGate(startMotionUpdates: false)

        for _ in 1...7 {
            gate.processSyntheticSample(gyroMagnitude: 0.3, accelMagnitude: 1.0)
            XCTAssertEqual(gate.snapshot().motionState, .still)
            assertCoherent(gate.snapshot())
        }
        gate.processSyntheticSample(gyroMagnitude: 0.3, accelMagnitude: 1.0)
        XCTAssertEqual(gate.snapshot().motionState, .moving)
        assertCoherent(gate.snapshot())

        for sample in 1...4 {
            gate.processSyntheticSample(gyroMagnitude: 1.0, accelMagnitude: 0.0)
            XCTAssertEqual(gate.snapshot().motionState, .moving,
                           "Panning must not begin before its gyro/accel conditions are reached (sample \(sample)).")
            assertCoherent(gate.snapshot())
        }
        for sample in 5...15 {
            gate.processSyntheticSample(gyroMagnitude: 1.0, accelMagnitude: 0.0)
            XCTAssertEqual(gate.snapshot().motionState, .moving,
                           "Panning requires 12 consecutive desired-state samples (sample \(sample)).")
            assertCoherent(gate.snapshot())
        }
        gate.processSyntheticSample(gyroMagnitude: 1.0, accelMagnitude: 0.0)
        XCTAssertEqual(gate.snapshot().motionState, .panning)
        assertCoherent(gate.snapshot())

        for sample in 1...14 {
            gate.processSyntheticSample(gyroMagnitude: 0.0, accelMagnitude: 0.0)
            XCTAssertEqual(gate.snapshot().motionState, .panning,
                           "Still requires 12 consecutive desired-state samples (sample \(sample)).")
            assertCoherent(gate.snapshot())
        }
        gate.processSyntheticSample(gyroMagnitude: 0.0, accelMagnitude: 0.0)
        let finalSnapshot = gate.snapshot()
        XCTAssertEqual(finalSnapshot.motionState, .still)
        XCTAssertTrue(finalSnapshot.isStable)
        assertCoherent(finalSnapshot)
        assertCompatibilityReadsMatchSnapshot(of: gate)
    }

    func testExistingThresholdBoundariesRemainUnchanged() {
        let exactStillExitGate = MotionGate(startMotionUpdates: false)
        for _ in 0..<20 {
            exactStillExitGate.processSyntheticSample(gyroMagnitude: 0.6, accelMagnitude: 0.0)
            XCTAssertEqual(exactStillExitGate.snapshot().motionState, .still)
        }
        let exactExitSnapshot = exactStillExitGate.snapshot()
        XCTAssertEqual(exactExitSnapshot.shakeLevel, 0.42, accuracy: 0.0000001)
        XCTAssertFalse(exactExitSnapshot.isStable)
        assertCoherent(exactExitSnapshot)

        let aboveStillExitGate = MotionGate(startMotionUpdates: false)
        for _ in 1...7 {
            aboveStillExitGate.processSyntheticSample(gyroMagnitude: 0.6001, accelMagnitude: 0.0)
            XCTAssertEqual(aboveStillExitGate.snapshot().motionState, .still)
        }
        aboveStillExitGate.processSyntheticSample(gyroMagnitude: 0.6001, accelMagnitude: 0.0)
        XCTAssertEqual(aboveStillExitGate.snapshot().motionState, .moving)

        let exactPanningGyroGate = MotionGate(startMotionUpdates: false)
        for _ in 0..<8 {
            exactPanningGyroGate.processSyntheticSample(gyroMagnitude: 0.85, accelMagnitude: 0.0)
        }
        XCTAssertEqual(exactPanningGyroGate.snapshot().motionState, .moving)

        let exactPanningAccelGate = MotionGate(startMotionUpdates: false)
        for _ in 0..<8 {
            exactPanningAccelGate.processSyntheticSample(gyroMagnitude: 1.0, accelMagnitude: 0.40)
        }
        XCTAssertEqual(exactPanningAccelGate.snapshot().motionState, .moving)
    }

    func testConcurrentSyntheticUpdatesAndSnapshotReadsNeverTearThePublishedTuple() {
        let gate = MotionGate(startMotionUpdates: false)
        let failures = LockedCounter()

        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for sample in 0..<2_000 {
                switch (worker + sample) % 3 {
                case 0:
                    gate.processSyntheticSample(gyroMagnitude: 0.3, accelMagnitude: 1.0)
                case 1:
                    gate.processSyntheticSample(gyroMagnitude: 1.0, accelMagnitude: 0.0)
                default:
                    gate.processSyntheticSample(gyroMagnitude: 0.0, accelMagnitude: 0.0)
                }

                let snapshot = gate.snapshot()
                if snapshot.isStable != (snapshot.motionState == .still && snapshot.shakeLevel < 0.42) {
                    failures.increment()
                }
            }
        }

        XCTAssertEqual(failures.value, 0)
        assertCompatibilityReadsMatchSnapshot(of: gate)
    }

    private func assertCoherent(_ snapshot: MotionSnapshot,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        XCTAssertEqual(snapshot.isStable,
                       snapshot.motionState == .still && snapshot.shakeLevel < 0.42,
                       file: file,
                       line: line)
    }

    private func assertCompatibilityReadsMatchSnapshot(of gate: MotionGate,
                                                       file: StaticString = #filePath,
                                                       line: UInt = #line) {
        let snapshot = gate.snapshot()
        XCTAssertEqual(gate.motionState, snapshot.motionState, file: file, line: line)
        XCTAssertEqual(gate.shakeLevel, snapshot.shakeLevel, accuracy: 0.0, file: file, line: line)
        XCTAssertEqual(gate.isCameraStable, snapshot.isStable, file: file, line: line)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}
