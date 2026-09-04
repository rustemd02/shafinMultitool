//
//  MotionGateTimelineTests.swift
//  shafinMultitoolTests
//
//  M2-015 TechnicalFeatureOwner: recorded synthetic motion traces under a
//  deterministic clock — hysteresis prevents flicker, transitions are
//  timestamped and retained, dwell time is measurable.
//

import XCTest
@testable import shafinMultitool

final class MotionGateTimelineTests: XCTestCase {

    /// Deterministic clock the test advances manually.
    private final class ScriptedClock {
        private(set) var now: Date
        private let start: TimeInterval
        private var step: TimeInterval

        init(start: TimeInterval = 10_000, step: TimeInterval = 1.0 / 60.0) {
            self.start = start
            self.step = step
            self.now = Date(timeIntervalSince1970: start)
        }

        func tick() -> Date {
            now = now.addingTimeInterval(step)
            return now
        }
    }

    private func gate(with clock: @escaping @Sendable () -> Date) -> MotionGate {
        MotionGate(startMotionUpdates: false, clock: clock)
    }

    // MARK: - Hysteresis: brief noise must not flicker the state

    func testBriefNoiseDoesNotFlickerStillState() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        let gate = gate(with: { now() })

        // 5 noisy samples: below the 8-sample moving commit threshold.
        for _ in 0..<5 {
            gate.processSyntheticSample(gyroMagnitude: 1.5, accelMagnitude: 1.0)
            _ = now()
        }
        XCTAssertEqual(gate.motionState, .still, "brief noise must not flicker the state")
        XCTAssertEqual(gate.timeline().count, 0, "no transition may be recorded for noise")
    }

    func testSustainedMotionCommitsAndIsTimestamped() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        let gate = gate(with: { now() })
        let before = now()

        // 8+ sustained moving samples commit the transition.
        for _ in 0..<10 {
            gate.processSyntheticSample(gyroMagnitude: 1.5, accelMagnitude: 1.0)
            _ = now()
        }
        XCTAssertEqual(gate.motionState, .moving)

        let timeline = gate.timeline()
        XCTAssertEqual(timeline.count, 1)
        XCTAssertEqual(timeline.first?.state, .moving)
        XCTAssertGreaterThanOrEqual(timeline.first?.timestamp ?? Date(), before)
    }

    // MARK: - Movement timestamps are retained

    func testStillToMovingToStillTransitionsAreAllRetained() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        let gate = gate(with: { now() })

        // Commit moving.
        for _ in 0..<10 {
            gate.processSyntheticSample(gyroMagnitude: 1.5, accelMagnitude: 1.0)
            _ = now()
        }
        // Commit still again: the gyro EMA decays over the burst, so only
        // the tail satisfies the still thresholds; 20 samples leave room.
        for _ in 0..<20 {
            gate.processSyntheticSample(gyroMagnitude: 0.0, accelMagnitude: 0.0)
            _ = now()
        }

        XCTAssertEqual(gate.motionState, .still)
        let timeline = gate.timeline()
        XCTAssertEqual(timeline.count, 2, "moving and still transitions must both be retained")
        XCTAssertEqual(timeline[0].state, .moving)
        XCTAssertEqual(timeline[1].state, .still)
        XCTAssertGreaterThanOrEqual(timeline[1].timestamp, timeline[0].timestamp)
    }

    // MARK: - Dwell time

    func testDwellSecondsMeasuresCurrentStateAge() {
        let clock = ScriptedClock(step: 1.0)
        var now = { clock.tick() }
        let gate = gate(with: { now() })

        // Commit panning: 12 samples at 1s each.
        for _ in 0..<12 {
            gate.processSyntheticSample(gyroMagnitude: 1.5, accelMagnitude: 0.05)
            _ = now()
        }
        XCTAssertEqual(gate.motionState, .panning)

        // Dwell measured 3 ticks after the commit: state began ~12s in.
        let asOf = now()
        let dwell = gate.dwellSeconds(asOf: asOf) ?? -1
        XCTAssertGreaterThanOrEqual(dwell, 0)
        XCTAssertLessThanOrEqual(dwell, 13, "dwell must measure the current state's age")
    }

    func testDwellIsNilBeforeTheStateStarted() {
        let clock = ScriptedClock()
        let gate = gate(with: { clock.now })
        // asOf before the gate's state start time.
        XCTAssertNil(gate.dwellSeconds(asOf: Date(timeIntervalSince1970: 0)))
    }

    // MARK: - State machine sanity under the calibrated thresholds

    func testPanningRequiresLowAccelAndStaysThroughHysteresis() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        let gate = gate(with: { now() })

        // Commit panning: high gyro, low accel.
        for _ in 0..<14 {
            gate.processSyntheticSample(gyroMagnitude: 1.2, accelMagnitude: 0.05)
            _ = now()
        }
        XCTAssertEqual(gate.motionState, .panning)

        // A couple of gyro dips below the exit threshold are absorbed by
        // hysteresis (exit needs sustained low gyro — sample-count based).
        gate.processSyntheticSample(gyroMagnitude: 0.3, accelMagnitude: 0.05)
        XCTAssertEqual(gate.motionState, .panning)
    }
}
