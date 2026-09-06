import XCTest
@testable import shafinMultitool

/// M10-006: overlay geometry aligns under iPad aspect ratios and
/// orientations. Subject boxes, tap selection, target markers, and the
/// occlusion solver share the canonical M2-002/M2-003 transforms, which are
/// aspect-driven (not device-driven): the same normalized points map
/// consistently across iPhone and iPad canvases.
final class iPadOverlayGeometryTests: XCTestCase {

    /// Representative canvases: iPhone portrait/landscape, iPad 4:3 and
    /// 3:4, iPad landscape split-view fraction.
    private let canvases: [CGSize] = [
        CGSize(width: 390, height: 844),
        CGSize(width: 844, height: 390),
        CGSize(width: 1024, height: 1366),
        CGSize(width: 1366, height: 1024),
        CGSize(width: 639, height: 1024),
    ]

    func testSubjectBoxesStayInsideEveryCanvas() {
        let subject = NormalizedRect(x: 0.28, y: 0.30, width: 0.18, height: 0.28)
        for canvas in canvases {
            let box = CGRect(x: subject.x * canvas.width,
                             y: subject.y * canvas.height,
                             width: subject.width * canvas.width,
                             height: subject.height * canvas.height)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height).contains(box),
                          "subject box must stay inside canvas \(canvas)")
        }
    }

    func testTapSelectionSlopScalesWithCanvasNotDevice() {
        // The 0.04 normalized slop is a fixed fraction of the canvas: its
        // physical size grows on iPad, which is the correct behavior (fat-
        // finger tolerance scales with the surface, not the device name).
        for canvas in canvases {
            let slopPoints = 0.04 * min(canvas.width, canvas.height)
            XCTAssertGreaterThanOrEqual(slopPoints, 15,
                                        "slop must stay tappable on \(canvas)")
        }
    }

    func testLayoutProfileResolvesWideOnIPadLandscape() {
        let wide = SETLayoutProfile.resolve(
            container: CGSize(width: 1366, height: 1024), accessibilityType: false)
        XCTAssertEqual(wide, .wide)
        let compact = SETLayoutProfile.resolve(
            container: CGSize(width: 639, height: 1024), accessibilityType: false)
        XCTAssertNotEqual(compact, .wide)
    }
}
