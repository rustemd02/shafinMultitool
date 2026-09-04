//
//  SemanticDirectionBehaviorTests.swift
//  shafinMultitoolTests
//
//  M2-004 AdvicePlannerOwner: directional tips describe desired SUBJECT
//  displacement. In-plane camera-framed directions invert optically; text and
//  marker share one computed target; the scene-space direction is invariant
//  across all eight display states while the rendered arrow follows the M2-003
//  display transform.
//

import XCTest
@testable import shafinMultitool

final class SemanticDirectionBehaviorTests: XCTestCase {

    // MARK: - Inversion contract

    func testCameraFramedInPlaneDirectionsInvertOptically() {
        XCTAssertEqual(SemanticDirection.left.subjectDisplacement(actionFrame: .moveCamera), .right)
        XCTAssertEqual(SemanticDirection.right.subjectDisplacement(actionFrame: .moveCamera), .left)
        XCTAssertEqual(SemanticDirection.up.subjectDisplacement(actionFrame: .moveCamera), .down)
        XCTAssertEqual(SemanticDirection.down.subjectDisplacement(actionFrame: .moveCamera), .up)
    }

    func testNonCameraFramesPreserveDirection() {
        let directions: [SemanticDirection] = [.left, .right, .up, .down]
        for frame in [SemanticActionFrame.moveSubject, .moveObject, .adjustLight, .wait] {
            for direction in directions {
                XCTAssertEqual(
                    direction.subjectDisplacement(actionFrame: frame),
                    direction,
                    "\(direction) in \(frame) frame must be preserved"
                )
            }
        }
    }

    func testDepthAndNeutralDirectionsAreUnaffected() {
        for frame in SemanticActionFrame.allCases {
            XCTAssertEqual(SemanticDirection.forward.subjectDisplacement(actionFrame: frame), .forward)
            XCTAssertEqual(SemanticDirection.back.subjectDisplacement(actionFrame: frame), .back)
            XCTAssertEqual(SemanticDirection.none.subjectDisplacement(actionFrame: frame), .none)
        }
    }

    func testCatalogCameraFramedTipsPublishInvertedSubjectDirection() throws {
        // The tip catalog carries camera-framed entries; every one of them
        // must publish the optically inverted subject direction.
        let createLookSpaceLeft = try XCTUnwrap(SemanticTipCatalog.definition(for: .createLookSpaceLeft))
        XCTAssertEqual(createLookSpaceLeft.actionFrame, .moveCamera)
        XCTAssertEqual(createLookSpaceLeft.direction, .left)
        XCTAssertEqual(createLookSpaceLeft.subjectDisplacementDirection, .right)

        var invertedCount = 0
        for tipType in SemanticTipType.allCases {
            let definition = try XCTUnwrap(SemanticTipCatalog.definition(for: tipType))
            let published = definition.subjectDisplacementDirection
            XCTAssertEqual(
                published,
                definition.direction.subjectDisplacement(actionFrame: definition.actionFrame)
            )
            if definition.actionFrame == .moveCamera,
               [.left, .right, .up, .down].contains(definition.direction) {
                invertedCount += 1
                XCTAssertNotEqual(published, definition.direction)
            }
        }
        XCTAssertGreaterThan(invertedCount, 0, "the catalog must exercise the inversion")
    }

    // MARK: - Text and marker share one computed target

    func testSubjectTargetPointAimsAtFrameEdgeMidpoint() {
        let subject = NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        XCTAssertEqual(SemanticDirection.left.subjectTargetPoint(from: subject).x, 0, accuracy: 1e-12)
        XCTAssertEqual(SemanticDirection.left.subjectTargetPoint(from: subject).y, 0.5, accuracy: 1e-12)
        XCTAssertEqual(SemanticDirection.right.subjectTargetPoint(from: subject).x, 1, accuracy: 1e-12)
        XCTAssertEqual(SemanticDirection.up.subjectTargetPoint(from: subject).y, 0, accuracy: 1e-12)
        XCTAssertEqual(SemanticDirection.down.subjectTargetPoint(from: subject).y, 1, accuracy: 1e-12)

        let center = SemanticDirection.none.subjectTargetPoint(from: subject)
        XCTAssertEqual(center.x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(center.y, 0.5, accuracy: 1e-12)
    }

    // MARK: - Four-direction × orientation × mirroring behavioral matrix

    func testSceneDirectionInvariantAndArrowFollowsDisplayTransform() {
        let displayStates: [(CameraCoachOrientation, Bool)] = [
            (.portrait, false), (.portrait, true),
            (.portraitUpsideDown, false), (.portraitUpsideDown, true),
            (.landscapeLeft, false), (.landscapeLeft, true),
            (.landscapeRight, false), (.landscapeRight, true),
        ]
        let sceneVectors: [SemanticDirection: (Double, Double)] = [
            .left: (-1, 0), .right: (1, 0), .up: (0, -1), .down: (0, 1),
        ]

        for (cameraDirection, sceneVector) in sceneVectors {
            // The published subject displacement (optical inversion of the
            // camera-framed instruction) is identical across all states.
            let subjectDirection = cameraDirection.subjectDisplacement(actionFrame: .moveCamera)
            let sceneDirections = displayStates.map { _ in subjectDirection }
            XCTAssertTrue(sceneDirections.allSatisfy { $0 == subjectDirection })

            for (orientation, mirrored) in displayStates {
                let transform = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
                // Rendered arrow direction = linear part of the display
                // transform applied to the scene displacement vector.
                let rendered = (
                    transform.a * sceneVector.0 + transform.b * sceneVector.1,
                    transform.c * sceneVector.0 + transform.d * sceneVector.1
                )
                // Composed expectation: rotate the vector, then mirror x.
                var expected = rotate(sceneVector, orientation)
                if mirrored {
                    expected = (-expected.0, expected.1)
                }
                XCTAssertEqual(rendered.0, expected.0, accuracy: 1e-12,
                               "\(cameraDirection) \(orientation) mirrored=\(mirrored) x")
                XCTAssertEqual(rendered.1, expected.1, accuracy: 1e-12,
                               "\(cameraDirection) \(orientation) mirrored=\(mirrored) y")
            }
        }
    }

    private func rotate(_ vector: (Double, Double), _ orientation: CameraCoachOrientation) -> (Double, Double) {
        // Linear (rotation) part of each golden matrix.
        let (a, b, c, d): (Double, Double, Double, Double)
        switch orientation {
        case .portrait:
            (a, b, c, d) = (0, 1, -1, 0)
        case .portraitUpsideDown:
            (a, b, c, d) = (0, -1, 1, 0)
        case .landscapeLeft:
            (a, b, c, d) = (-1, 0, 0, -1)
        case .landscapeRight:
            (a, b, c, d) = (1, 0, 0, 1)
        }
        return (a * vector.0 + b * vector.1, c * vector.0 + d * vector.1)
    }

    // MARK: - Copy migration gate (no duplicate camera direction semantics)

    func testShiftActionCopySpeaksInSubjectDisplacementSemantics() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Resources/Localizable.xcstrings")
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let strings = try XCTUnwrap(data?["strings"] as? [String: Any])

        let migratedKeys = [
            "set.trace.action.shift_left",
            "set.trace.action.shift_right",
            "set.trace.action.shift_up",
            "set.trace.action.shift_down",
        ]
        for key in migratedKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for (lang, unit) in localizations {
                let value = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                // No frame-relative direction phrasing may remain.
                let lower = value.lowercased()
                XCTAssertFalse(lower.contains("кадр"), "\(key) [\(lang)]: \(value)")
                XCTAssertFalse(lower.contains("frame"), "\(key) [\(lang)]: \(value)")
                // The migrated copy names the subject.
                XCTAssertTrue(
                    lower.contains("геро") || lower.contains("subject"),
                    "\(key) [\(lang)] must speak in subject terms: \(value)"
                )
            }
        }
    }
}
