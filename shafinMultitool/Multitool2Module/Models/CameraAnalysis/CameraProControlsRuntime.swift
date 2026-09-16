import Foundation
import CoreGraphics

/// Commands and observations of the one CameraManager capture device.
/// A requested value is never a readback or proof of visual improvement.
enum CameraProControlCommand: Equatable, Sendable {
    case format(String)
    case exposureAuto
    case exposureBias(Float)
    case exposureManual(shutterAngle: Double, iso: Float)
    case focusAuto
    case focusPoint(CGPoint)
    case focusManual(Float)
    case whiteBalanceAuto
    case whiteBalanceLock
    case whiteBalanceTemperature(Float)
    case torch(Bool)

    var changesFormat: Bool {
        if case .format = self { return true }
        return false
    }
}

enum CameraProControlError: Error, Equatable, Sendable {
    case unavailable, unsupported, invalidValue, configurationFailed
    case stale, busy, focusTimeout, applicationTimeout, microphoneDenied
}

struct CameraProFormatOption: Equatable, Identifiable, Sendable {
    let id: String
    let width: Int
    let height: Int
    let fps: Double
    var label: String { "\(width)×\(height) · \(String(format: "%.0f", fps)) FPS" }
}

struct CameraProControlCapabilities: Equatable, Sendable {
    var formats: [CameraProFormatOption] = []
    var autoExposure = false
    var exposureBiasRange: ClosedRange<Float>?
    var isoRange: ClosedRange<Float>?
    var exposureDurationRange: ClosedRange<Double>?
    var autoFocus = false
    var tapFocusLock = false
    var manualFocus = false
    var autoWhiteBalance = false
    var whiteBalanceLock = false
    var customWhiteBalance = false
    var torch = false
}

struct CameraProControlReadback: Equatable, Sendable {
    var width = 0
    var height = 0
    var formatID: String?
    /// Present only when min/max configured frame periods agree.
    var fixedFPS: Double?
    var exposureIsAuto = false
    var exposureIsManual = false
    var exposureBias: Float?
    var iso: Float?
    var exposureDuration: Double?
    var focusIsAuto = false
    var focusIsLocked = false
    var lensPosition: Float?
    var whiteBalanceIsAuto = false
    var whiteBalanceIsLocked = false
    var temperature: Float?
    var torchActive: Bool?

    var shutterAngle: Double? {
        guard let fixedFPS, let exposureDuration else { return nil }
        let angle = exposureDuration * fixedFPS * 360
        return angle.isFinite && angle > 0 ? angle : nil
    }
}

struct CameraProControlsSnapshot: Equatable, Sendable {
    let deviceID: String
    let captureGeneration: UInt64
    let capabilities: CameraProControlCapabilities
    let readback: CameraProControlReadback
}

enum CameraProControlPolicy {
    static func clamp(_ value: Float, to range: ClosedRange<Float>) throws -> Float {
        guard value.isFinite, range.lowerBound.isFinite, range.upperBound.isFinite else {
            throw CameraProControlError.invalidValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func exposureDuration(
        angle: Double, fps: Double, supported: ClosedRange<Double>
    ) throws -> Double {
        guard angle.isFinite, fps.isFinite, 0 < angle, angle <= 360, fps > 0,
              supported.lowerBound.isFinite, supported.upperBound.isFinite,
              supported.lowerBound > 0 else { throw CameraProControlError.invalidValue }
        let maximum = min(supported.upperBound, 1 / fps)
        guard supported.lowerBound <= maximum else { throw CameraProControlError.unsupported }
        return min(max(angle / (360 * fps), supported.lowerBound), maximum)
    }

    static func validDevicePoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    static func normalizedGains(_ values: [Float], maximum: Float) throws -> [Float] {
        guard values.count == 3, maximum.isFinite, maximum >= 1,
              values.allSatisfy({ $0.isFinite && $0 > 0 }),
              let minimum = values.min() else { throw CameraProControlError.invalidValue }
        return values.map { min(max($0 / minimum, 1), maximum) }
    }
}

/// Injected device seam. Calls, snapshots and cancellation belong to the
/// manager's session queue; implementations never start a second session.
protocol CameraProControlDevice: AnyObject {
    var deviceID: String { get }
    func snapshot(generation: UInt64) -> CameraProControlsSnapshot
    func apply(_ command: CameraProControlCommand, completion: @escaping (Result<Void, CameraProControlError>) -> Void)
    func cancelPending()
}

