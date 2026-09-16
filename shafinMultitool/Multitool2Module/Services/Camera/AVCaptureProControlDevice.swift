import AVFoundation
import Foundation

/// No capture/session ownership: adapts the current input on CameraManager's queue.
final class AVCaptureProControlDevice: CameraProControlDevice {
    private let device: AVCaptureDevice
    private let sessionQueue: DispatchQueue
    private var focusObservation: NSKeyValueObservation?
    private var focusOperation: UUID?
    private var focusSawAdjustment = false
    private lazy var formatChoices: [(CameraProFormatOption, AVCaptureDevice.Format)] = makeFormatChoices()

    init(device: AVCaptureDevice, sessionQueue: DispatchQueue) {
        self.device = device
        self.sessionQueue = sessionQueue
    }

    var deviceID: String { device.uniqueID }

    func snapshot(generation: UInt64) -> CameraProControlsSnapshot {
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let minimum = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        let maximum = CMTimeGetSeconds(device.activeVideoMaxFrameDuration)
        let fixedFPS: Double? = minimum.isFinite && maximum.isFinite && minimum > 0
            && abs(minimum - maximum) < 0.000001 ? 1 / minimum : nil
        var capabilities = CameraProControlCapabilities()
        capabilities.formats = formatChoices.map(\.0)
        capabilities.autoExposure = device.isExposureModeSupported(.continuousAutoExposure)
        if device.minExposureTargetBias.isFinite, device.maxExposureTargetBias.isFinite,
           device.minExposureTargetBias <= device.maxExposureTargetBias {
            capabilities.exposureBiasRange = device.minExposureTargetBias...device.maxExposureTargetBias
        }
        let minDuration = CMTimeGetSeconds(format.minExposureDuration)
        let maxDuration = CMTimeGetSeconds(format.maxExposureDuration)
        if device.isExposureModeSupported(.custom),
           format.minISO.isFinite, format.maxISO.isFinite, format.minISO <= format.maxISO,
           minDuration.isFinite, maxDuration.isFinite, minDuration > 0, minDuration <= maxDuration {
            capabilities.isoRange = format.minISO...format.maxISO
            capabilities.exposureDurationRange = minDuration...maxDuration
        }
        capabilities.autoFocus = device.isFocusModeSupported(.continuousAutoFocus)
        capabilities.tapFocusLock = device.isFocusPointOfInterestSupported
            && device.isFocusModeSupported(.autoFocus) && device.isFocusModeSupported(.locked)
        capabilities.manualFocus = device.isFocusModeSupported(.locked)
            && device.isLockingFocusWithCustomLensPositionSupported
        capabilities.autoWhiteBalance = device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)
        capabilities.whiteBalanceLock = device.isWhiteBalanceModeSupported(.locked)
        capabilities.customWhiteBalance = capabilities.whiteBalanceLock
            && device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        capabilities.torch = device.hasTorch && device.isTorchAvailable
            && device.isTorchModeSupported(.on) && device.isTorchModeSupported(.off)

        var readback = CameraProControlReadback()
        readback.width = Int(dimensions.width)
        readback.height = Int(dimensions.height)
        readback.fixedFPS = fixedFPS
        readback.formatID = formatChoices.first { choice in
            choice.1 === format && fixedFPS.map { abs($0 - choice.0.fps) < 0.01 } == true
        }?.0.id
        readback.exposureIsAuto = device.exposureMode == .continuousAutoExposure || device.exposureMode == .autoExpose
        readback.exposureIsManual = device.exposureMode == .custom
        readback.exposureBias = device.exposureTargetBias.isFinite ? device.exposureTargetBias : nil
        readback.iso = device.iso.isFinite ? device.iso : nil
        let exposureDuration = CMTimeGetSeconds(device.exposureDuration)
        readback.exposureDuration = exposureDuration.isFinite && exposureDuration > 0 ? exposureDuration : nil
        readback.focusIsAuto = device.focusMode == .continuousAutoFocus || device.focusMode == .autoFocus
        readback.focusIsLocked = device.focusMode == .locked
        readback.lensPosition = device.lensPosition.isFinite ? device.lensPosition : nil
        readback.whiteBalanceIsAuto = device.whiteBalanceMode == .continuousAutoWhiteBalance || device.whiteBalanceMode == .autoWhiteBalance
        readback.whiteBalanceIsLocked = device.whiteBalanceMode == .locked
        let gains = device.deviceWhiteBalanceGains
        if [gains.redGain, gains.greenGain, gains.blueGain].allSatisfy({
            $0.isFinite && $0 >= 1 && $0 <= device.maxWhiteBalanceGain
        }) {
            let temperature = device.temperatureAndTintValues(for: gains).temperature
            readback.temperature = temperature.isFinite && temperature > 0 ? temperature : nil
        }
        readback.torchActive = capabilities.torch ? device.isTorchActive : nil
        return CameraProControlsSnapshot(deviceID: deviceID, captureGeneration: generation,
                                        capabilities: capabilities, readback: readback)
    }

    private func makeFormatChoices() -> [(CameraProFormatOption, AVCaptureDevice.Format)] {
        var seen = Set<String>()
        var values: [(CameraProFormatOption, AVCaptureDevice.Format)] = []
        for (index, format) in device.formats.enumerated() {
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            guard subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                    || subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { continue }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dimensions.width > 0, dimensions.height > 0 else { continue }
            for fps in [24.0, 25, 30, 48, 50, 60, 120, 240] {
                guard format.videoSupportedFrameRateRanges.contains(where: {
                    fps >= $0.minFrameRate && fps <= $0.maxFrameRate
                }) else { continue }
                let key = "\(dimensions.width)x\(dimensions.height):\(fps)"
                guard seen.insert(key).inserted else { continue }
                values.append((CameraProFormatOption(id: "\(index):\(fps)",
                    width: Int(dimensions.width), height: Int(dimensions.height), fps: fps), format))
            }
        }
        return values.sorted {
            if $0.0.width != $1.0.width { return $0.0.width < $1.0.width }
            if $0.0.height != $1.0.height { return $0.0.height < $1.0.height }
            return $0.0.fps < $1.0.fps
        }
    }

    func apply(_ command: CameraProControlCommand, completion: @escaping (Result<Void, CameraProControlError>) -> Void) {
        let state = snapshot(generation: 0)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            switch command {
            case .format(let identifier):
                guard let choice = formatChoices.first(where: { $0.0.id == identifier }) else {
                    throw CameraProControlError.unsupported
                }
                if #available(iOS 18.0, *) { device.isAutoVideoFrameRateEnabled = false }
                device.activeFormat = choice.1
                if choice.1.supportedColorSpaces.contains(.sRGB) { device.activeColorSpace = .sRGB }
                let duration = CMTime(seconds: 1 / choice.0.fps, preferredTimescale: 1_000_000_000)
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                completion(.success(()))
            case .exposureAuto:
                guard state.capabilities.autoExposure else { throw CameraProControlError.unsupported }
                device.exposureMode = .continuousAutoExposure
                completion(.success(()))
            case .exposureBias(let requested):
                guard state.readback.exposureIsAuto, let range = state.capabilities.exposureBiasRange else {
                    throw CameraProControlError.unsupported
                }
                let value = try CameraProControlPolicy.clamp(requested, to: range)
                device.setExposureTargetBias(value) { _ in completion(.success(())) }
            case .exposureManual(let angle, let requestedISO):
                guard let fps = state.readback.fixedFPS, let isoRange = state.capabilities.isoRange,
                      let durations = state.capabilities.exposureDurationRange else {
                    throw CameraProControlError.unsupported
                }
                let duration = try CameraProControlPolicy.exposureDuration(angle: angle, fps: fps, supported: durations)
                let iso = try CameraProControlPolicy.clamp(requestedISO, to: isoRange)
                device.setExposureModeCustom(duration: CMTime(seconds: duration, preferredTimescale: 1_000_000_000), iso: iso) {
                    _ in completion(.success(()))
                }
            case .focusAuto:
                guard state.capabilities.autoFocus else { throw CameraProControlError.unsupported }
                cancelPending()
                device.focusMode = .continuousAutoFocus
                completion(.success(()))
            case .focusPoint(let point):
                guard state.capabilities.tapFocusLock else { throw CameraProControlError.unsupported }
                guard CameraProControlPolicy.validDevicePoint(point) else { throw CameraProControlError.invalidValue }
                startFocusLock(at: point, completion: completion)
            case .focusManual(let requested):
                guard state.capabilities.manualFocus else { throw CameraProControlError.unsupported }
                let position = try CameraProControlPolicy.clamp(requested, to: 0...1)
                device.setFocusModeLocked(lensPosition: position) { _ in completion(.success(())) }
            case .whiteBalanceAuto:
                guard state.capabilities.autoWhiteBalance else { throw CameraProControlError.unsupported }
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                completion(.success(()))
            case .whiteBalanceLock:
                guard state.capabilities.whiteBalanceLock else { throw CameraProControlError.unsupported }
                device.setWhiteBalanceModeLocked(with: AVCaptureDevice.currentWhiteBalanceGains) {
                    _ in completion(.success(()))
                }
            case .whiteBalanceTemperature(let temperature):
                guard state.capabilities.customWhiteBalance else { throw CameraProControlError.unsupported }
                guard temperature.isFinite, (2000...10000).contains(temperature) else {
                    throw CameraProControlError.invalidValue
                }
                let gains = device.deviceWhiteBalanceGains(for: .init(temperature: temperature, tint: 0))
                let normalized = try CameraProControlPolicy.normalizedGains(
                    [gains.redGain, gains.greenGain, gains.blueGain], maximum: device.maxWhiteBalanceGain
                )
                device.setWhiteBalanceModeLocked(with: .init(redGain: normalized[0],
                    greenGain: normalized[1], blueGain: normalized[2])) { _ in completion(.success(())) }
            case .torch(let active):
                guard state.capabilities.torch else { throw CameraProControlError.unsupported }
                device.torchMode = active ? .on : .off
                completion(.success(()))
            }
        } catch let error as CameraProControlError {
            completion(.failure(error))
        } catch {
            completion(.failure(.configurationFailed))
        }
    }

    /// Observation is installed before autofocus starts. Merely seeing a
    /// previously idle device is not evidence that this focus request settled.
    private func startFocusLock(at point: CGPoint, completion: @escaping (Result<Void, CameraProControlError>) -> Void) {
        cancelPending()
        let operation = UUID()
        focusOperation = operation
        focusSawAdjustment = false
        focusObservation = device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] _, change in
            guard let self, let adjusting = change.newValue else { return }
            self.sessionQueue.async { [weak self] in
                guard let self, self.focusOperation == operation else { return }
                if adjusting { self.focusSawAdjustment = true; return }
                guard self.focusSawAdjustment else { return }
                self.cancelPending()
                do {
                    try self.device.lockForConfiguration()
                    defer { self.device.unlockForConfiguration() }
                    self.device.setFocusModeLocked(lensPosition: AVCaptureDevice.currentLensPosition) {
                        _ in completion(.success(()))
                    }
                } catch { completion(.failure(.configurationFailed)) }
            }
        }
        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
        sessionQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.focusOperation == operation else { return }
            self.cancelPending()
            completion(.failure(.focusTimeout))
        }
    }

    func cancelPending() {
        focusOperation = nil
        focusObservation?.invalidate()
        focusObservation = nil
        focusSawAdjustment = false
    }
}

