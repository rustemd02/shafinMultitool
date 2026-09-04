//
//  SubjectTapSelectorTests.swift
//  shafinMultitoolTests
//
//  M2-009 SubjectSelectionOwner: geometry tests (display→scene through the
//  M2-003 inverse transform, touch slop, nearest-wins) and the tap intent
//  routing matrix with injected candidates.
//

import XCTest
@testable import shafinMultitool

final class SubjectTapSelectorTests: XCTestCase {

    private func candidate(id: String, x: Double, y: Double = 0.3, w: Double = 0.2, h: Double = 0.4) -> SubjectCandidate {
        SubjectCandidate(id: id, kind: .person, region: NormalizedRect(x: x, y: y, width: w, height: h), confidence: 0.8)
    }

    // MARK: - Geometry: display → scene through inverse transform

    func testPortraitDisplayTapMapsThroughInverseTransform() {
        // Portrait display: sensor right edge is display top. A tap at the
        // display top edge center maps to the scene/sensor x ≈ 1 side.
        // Display top edge center corresponds to the sensor right edge
        // (portrait rotates the landscape sensor +90° CCW).
        let portrait = CameraDisplayTransform(orientation: .portrait, isMirrored: false)
        let scene = portrait.inverse.apply(x: 0.5, y: 0.0)
        XCTAssertEqual(scene.x, 1.0, accuracy: 1e-12)
        XCTAssertEqual(scene.y, 0.5, accuracy: 1e-12)

        // Mirroring flips display x: display top LEFT corner maps to sensor
        // (1, 0) while top RIGHT corner maps to sensor (1, 1)... inverted:
        let mirrored = CameraDisplayTransform(orientation: .portrait, isMirrored: true)
        let mirroredScene = mirrored.inverse.apply(x: 0.5, y: 0.0)
        XCTAssertEqual(mirroredScene.x, scene.x, accuracy: 1e-12)
        XCTAssertEqual(mirroredScene.y, scene.y, accuracy: 1e-12)
    }

    func testSamePhysicalCandidateSelectedInAllEightDisplayStates() throws {
        // One candidate centered in scene space; compute its display point for
        // every orientation/mirroring state and tap exactly there. The same
        // candidate must be selected every time (orientation/mirror invariance).
        let subject = candidate(id: "hero", x: 0.4, y: 0.3, w: 0.2, h: 0.4)
        let centerScene = CGPoint(x: 0.5, y: 0.5)

        for orientation in CameraCoachOrientation.allCases {
            for mirrored in [false, true] {
                let transform = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
                let display = transform.apply(x: Double(centerScene.x), y: Double(centerScene.y))
                let outcome = SubjectTapSelector.route(
                    displayX: display.x,
                    displayY: display.y,
                    candidates: [subject],
                    clarificationActive: true,
                    focusEnabled: true,
                    transform: transform
                )
                guard case let .subjectSelected(selected) = outcome else {
                    return XCTFail("\(orientation) mirrored=\(mirrored): expected selection, got \(outcome)")
                }
                XCTAssertEqual(selected.id, "hero", "\(orientation) mirrored=\(mirrored)")
            }
        }
    }

    // MARK: - Hit-test geometry

    func testTouchSlopIsForgivingAtRegionEdges() {
        let candidates = [candidate(id: "edge", x: 0.4, y: 0.4, w: 0.2, h: 0.2)]
        // Just outside the region but inside the slop band.
        XCTAssertNotNil(SubjectTapSelector.hitTest(sceneX: 0.615, sceneY: 0.5, candidates: candidates))
        // Far outside: no hit.
        XCTAssertNil(SubjectTapSelector.hitTest(sceneX: 0.9, sceneY: 0.5, candidates: candidates))
    }

    func testNearestCenterWins() {
        // Regions 0.1-0.3 and 0.32-0.52: their slop bands overlap around 0.3,
        // so both are hits and the nearer center wins.
        let left = candidate(id: "left", x: 0.1, y: 0.4, w: 0.2, h: 0.2)
        let right = candidate(id: "right", x: 0.32, y: 0.4, w: 0.2, h: 0.2)
        XCTAssertEqual(SubjectTapSelector.hitTest(sceneX: 0.295, sceneY: 0.5, candidates: [left, right])?.id, "left")
        XCTAssertEqual(SubjectTapSelector.hitTest(sceneX: 0.325, sceneY: 0.5, candidates: [left, right])?.id, "right")
    }

    func testEqualDistanceResolvesDeterministicallyById() {
        // Centers at 0.4 and 0.6: a tap at 0.5 is equidistant; ascending id
        // ("a") must win regardless of candidate order.
        let b = candidate(id: "b", x: 0.3, y: 0.4, w: 0.2, h: 0.2)
        let a = candidate(id: "a", x: 0.5, y: 0.4, w: 0.2, h: 0.2)
        XCTAssertEqual(SubjectTapSelector.hitTest(sceneX: 0.5, sceneY: 0.5, candidates: [b, a])?.id, "a")
        XCTAssertEqual(SubjectTapSelector.hitTest(sceneX: 0.5, sceneY: 0.5, candidates: [a, b])?.id, "a")
    }

    func testCandidatesWithoutRegionNeverHit() {
        let regionless = SubjectCandidate(id: "r", kind: .unknown, confidence: 0.5)
        XCTAssertNil(SubjectTapSelector.hitTest(sceneX: 0.5, sceneY: 0.5, candidates: [regionless]))
    }

    // MARK: - Intent routing matrix

    func testClarificationEmptyTapProducesFeedbackAndNeverFocus() {
        let outcome = SubjectTapSelector.route(
            displayX: 0.5, displayY: 0.95,
            candidates: [candidate(id: "p1", x: 0.1, y: 0.3)],
            clarificationActive: true,
            focusEnabled: true,
            transform: CameraDisplayTransform(orientation: .portrait, isMirrored: false)
        )
        XCTAssertEqual(outcome, .clarificationEmptyTap)
    }

    func testNormalModeTapCoordinatesFocusExplicitly() {
        let outcome = SubjectTapSelector.route(
            displayX: 0.5, displayY: 0.5,
            candidates: [candidate(id: "p1", x: 0.1, y: 0.3)],
            clarificationActive: false,
            focusEnabled: true,
            transform: CameraDisplayTransform(orientation: .portrait, isMirrored: false)
        )
        guard case let .focusRequested(sceneX, sceneY) = outcome else {
            return XCTFail("normal tap must route to coordinated focus, got \(outcome)")
        }
        // Portrait display center maps to scene center.
        XCTAssertEqual(sceneX, 0.5, accuracy: 1e-12)
        XCTAssertEqual(sceneY, 0.5, accuracy: 1e-12)
    }

    func testNormalModeTapWithoutFocusIsIgnored() {
        let outcome = SubjectTapSelector.route(
            displayX: 0.5, displayY: 0.5,
            candidates: [],
            clarificationActive: false,
            focusEnabled: false,
            transform: CameraDisplayTransform(orientation: .portrait, isMirrored: false)
        )
        XCTAssertEqual(outcome, .ignored)
    }

    func testNonFiniteDisplayTapFailsClosedToCenter() {
        let transform = CameraDisplayTransform(orientation: .portrait, isMirrored: false)
        let outcome = SubjectTapSelector.route(
            displayX: .nan, displayY: .infinity,
            candidates: [candidate(id: "hero", x: 0.4, y: 0.3, w: 0.2, h: 0.4)],
            clarificationActive: true,
            focusEnabled: true,
            transform: transform
        )
        // Center tap hits the centered candidate.
        guard case .subjectSelected = outcome else {
            return XCTFail("expected selection at clamped center, got \(outcome)")
        }
    }
}
