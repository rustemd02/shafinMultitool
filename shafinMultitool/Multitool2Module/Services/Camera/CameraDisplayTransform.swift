import CoreGraphics
import Foundation

/// M2-003 CameraGeometryOwner: the single orientation/mirroring display
/// transform. Every production conversion between the landscape-native sensor
/// space and the y-down display spaces (subject target, preview, SwiftUI
/// canvas) goes through this adapter — no call site re-derives rotation or
/// mirroring.
///
/// Convention (pinned by transform-matrix.json and its tests):
/// - Sensor normalized space: origin TOP-left of the landscape-native sensor
///   image, x-right, y-down.
/// - Display normalized space: origin TOP-left, x-right, y-down.
/// - Sensor→display rotation:
///     portrait            +90° CCW   →  (dx, dy) = (sy, 1 − sx)
///     portraitUpsideDown  −90° CCW   →  (dx, dy) = (1 − sy, sx)
///     landscapeLeft       180°       →  (dx, dy) = (1 − sx, 1 − sy)
///     landscapeRight      identity   →  (dx, dy) = (sx, sy)
/// - Mirroring (front camera preview) flips the display x axis after rotation:
///   dx = 1 − dx. Mirroring is its own inverse.
/// - Aspect-fill between pixel windows composes on top via the M2-002
///   `AspectFillTransform`; this adapter stays in normalized space so the
///   golden matrices are aspect-independent.
struct CameraDisplayTransform: Equatable, Sendable {
    /// Row-major 2×3 affine matrix: (dx, dy) = M · (sx, sy, 1).
    let a: Double
    let b: Double
    let tx: Double
    let c: Double
    let d: Double
    let ty: Double

    let orientation: CameraCoachOrientation
    /// True when the display mirrors the captured scene (front camera preview).
    let isMirrored: Bool

    init(orientation: CameraCoachOrientation, isMirrored: Bool) {
        self.orientation = orientation
        self.isMirrored = isMirrored

        // Rotation without mirroring.
        let (ra, rb, rtx, rc, rd, rty): (Double, Double, Double, Double, Double, Double)
        switch orientation {
        case .portrait:
            (ra, rb, rtx, rc, rd, rty) = (0, 1, 0, -1, 0, 1)
        case .portraitUpsideDown:
            (ra, rb, rtx, rc, rd, rty) = (0, -1, 1, 1, 0, 0)
        case .landscapeLeft:
            (ra, rb, rtx, rc, rd, rty) = (-1, 0, 1, 0, -1, 1)
        case .landscapeRight:
            (ra, rb, rtx, rc, rd, rty) = (1, 0, 0, 0, 1, 0)
        }

        // Mirroring flips the display x axis:
        // dx_mirrored = 1 − (ra·sx + rb·sy + rtx) = −ra·sx − rb·sy + (1 − rtx).
        if isMirrored {
            self.a = -ra
            self.b = -rb
            self.tx = 1 - rtx
            self.c = rc
            self.d = rd
            self.ty = rty
        } else {
            self.a = ra
            self.b = rb
            self.tx = rtx
            self.c = rc
            self.d = rd
            self.ty = rty
        }
    }

    func apply(x: Double, y: Double) -> (x: Double, y: Double) {
        (a * x + b * y + tx, c * x + d * y + ty)
    }

    /// Inverse transform (display → sensor). The golden matrices have
    /// determinant ±1, so the inverse always exists and is exact on the unit
    /// square.
    var inverse: CameraDisplayTransform {
        let determinant = a * d - b * c
        guard determinant != 0 else { return self }
        let ia = d / determinant
        let ib = -b / determinant
        let ic = -c / determinant
        let id = a / determinant
        let itx = -(ia * tx + ib * ty)
        let ity = -(ic * tx + id * ty)
        return CameraDisplayTransform(
            matrix: (ia, ib, itx, ic, id, ity),
            orientation: orientation,
            isMirrored: isMirrored
        )
    }

    /// Test/golden-matrix seam: rebuilds from raw matrix entries.
    init(matrix: (Double, Double, Double, Double, Double, Double),
         orientation: CameraCoachOrientation,
         isMirrored: Bool) {
        self.a = matrix.0
        self.b = matrix.1
        self.tx = matrix.2
        self.c = matrix.3
        self.d = matrix.4
        self.ty = matrix.5
        self.orientation = orientation
        self.isMirrored = isMirrored
    }
}
