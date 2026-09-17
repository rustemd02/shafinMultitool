#if DEBUG && targetEnvironment(simulator)
import XCTest
import Vision
import CoreVideo
import CoreGraphics
import ImageIO
import CryptoKit
import Darwin
@testable import shafinMultitool

/// One authenticated frame, six fresh request instances, four synchronous performs.
/// This diagnostic never changes production admission or compute/revision selection.
final class VisionRequestIsolationDiagnosticTests: XCTestCase {
    private static let manifestSHA = "ed652addfd2c661060bb6dfbcab8c9c7f7be1d02a50c1b9a8e518068153e9894"
    private static let imageSHA = "34bbf042c8a8dfd30ad4d48128bbefed9787b4e1692f4273cbc406ff28301a3e"

    func testRecovered184VisionBatchAndIndependentRequests() throws {
        let imageData = try authenticatedImageData()
        let pixels = try pixelBuffer(from: imageData)
        let recorder = VisionDiagnosticCallbackRecorder()
        var runs: [[String: Any]] = []
        let kinds = ["face", "human", "attention_saliency"]

        // Same classes, order, options, pixel conversion and orientation as process().
        runs.append(run(kinds: kinds, label: "original_batch", pixels: pixels, recorder: recorder))
        for kind in kinds {
            runs.append(run(kinds: [kind], label: "independent_" + kind, pixels: pixels, recorder: recorder))
        }

        var system = utsname()
        uname(&system)
        let machineCapacity = MemoryLayout.size(ofValue: system.machine)
        let machine = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: machineCapacity) {
                String(cString: $0)
            }
        }
        let process = ProcessInfo.processInfo
        let report: [String: Any] = [
            "schema": "setos-vision-request-isolation.v1",
            "input_name": "184.jpg",
            "input_sha256": Self.imageSHA,
            "manifest_sha256": Self.manifestSHA,
            "width": CVPixelBufferGetWidth(pixels),
            "height": CVPixelBufferGetHeight(pixels),
            "pixel_format": CVPixelBufferGetPixelFormatType(pixels),
            "orientation": "up",
            "runtime": [
                "target": "simulator",
                "os": process.operatingSystemVersionString,
                "machine": machine,
                "processor_count": process.processorCount,
                "simulator_model": process.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unreported",
                "simulator_runtime": process.environment["SIMULATOR_RUNTIME_VERSION"] ?? "unreported"
            ],
            "compute_policy": "framework_default_no_overrides_no_cpu_retry",
            "request_instances": 6,
            "perform_calls": 4,
            "runs": runs,
            "callbacks_in_observed_order": recorder.snapshot(),
            "claim": "request_execution_diagnostic_only_not_product_or_device_acceptance"
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        let reportText = try XCTUnwrap(String(data: reportData, encoding: .utf8))
        let attachment = XCTAttachment(string: reportText)
        attachment.name = "vision-request-isolation-184.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[VISION_REQUEST_ISOLATION] " + reportText)

        // Keep the failure visible: writing a receipt is not a Vision PASS.
        for run in runs {
            XCTAssertEqual(run["all_requests_succeeded"] as? Bool, true,
                           "Vision execution failed: \(run["label"] ?? "unknown"); inspect diagnostic attachment")
        }
    }

    /// Run as the only Vision diagnostic in a fresh test process. This is an
    /// explicit compute experiment, never a retry or a production fallback.
    func testRecovered184VisionSupportedCPURequests() throws {
        let imageData = try authenticatedImageData()
        let pixels = try pixelBuffer(from: imageData)
        let recorder = VisionDiagnosticCallbackRecorder()
        let runs = ["face", "human", "attention_saliency"].map { kind in
            run(kinds: [kind], label: "cpu_" + kind, pixels: pixels,
                recorder: recorder, supportedCPUOnly: true)
        }
        let process = ProcessInfo.processInfo
        let report: [String: Any] = [
            "schema": "setos-vision-supported-cpu-diagnostic.v1",
            "input_name": "184.jpg", "input_sha256": Self.imageSHA,
            "manifest_sha256": Self.manifestSHA,
            "width": CVPixelBufferGetWidth(pixels), "height": CVPixelBufferGetHeight(pixels),
            "pixel_format": CVPixelBufferGetPixelFormatType(pixels), "orientation": "up",
            "runtime": [
                "target": "simulator", "os": process.operatingSystemVersionString,
                "processor_count": process.processorCount,
                "simulator_model": process.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unreported",
                "simulator_runtime": process.environment["SIMULATOR_RUNTIME_VERSION"] ?? "unreported"
            ],
            "compute_policy": "explicit_supported_cpu_for_every_declared_stage_no_retry",
            "request_instances": 3,
            "perform_calls": runs.filter { $0["perform_attempted"] as? Bool == true }.count,
            "runs": runs, "callbacks_in_observed_order": recorder.snapshot(),
            "claim": "simulator_compute_diagnostic_only_not_production_admission_or_device_acceptance"
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        let reportText = try XCTUnwrap(String(data: data, encoding: .utf8))
        let attachment = XCTAttachment(string: reportText)
        attachment.name = "vision-supported-cpu-184.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[VISION_SUPPORTED_CPU_DIAGNOSTIC] " + reportText)
        for run in runs {
            XCTAssertEqual(run["all_requests_succeeded"] as? Bool, true,
                           "Explicit supported CPU execution failed: \(run["label"] ?? "unknown"); inspect diagnostic attachment")
        }
    }

    /// The same production owner used by high-lane and still replay, one batch.
    /// Counts/geometry here qualify execution and normalized coordinates only.
    func testRecovered184ProductionVisionSimulatorConfiguration() throws {
        let pixels = try pixelBuffer(from: authenticatedImageData())
        let result = VisionTracking().process(pixelBuffer: pixels, orientation: .up)
        func box(_ rectangle: CGRect) -> [String: Double] {
            ["x": Double(rectangle.origin.x), "y": Double(rectangle.origin.y),
             "width": Double(rectangle.size.width), "height": Double(rectangle.size.height)]
        }
        let report: [String: Any] = [
            "schema": "setos-production-vision-simulator.v1",
            "input_name": "184.jpg", "input_sha256": Self.imageSHA,
            "width": CVPixelBufferGetWidth(pixels), "height": CVPixelBufferGetHeight(pixels),
            "orientation": "up", "coordinates": "Vision_normalized_bottom_left",
            "processing_status": result.processingStatus.rawValue,
            "face_count": result.faceCount, "person_count_after_existing_overlap_filter": result.personCount,
            "subjects": result.subjects.map {
                ["box": box($0.boundingBox), "is_face": $0.isFace, "raw_confidence": $0.confidence] as [String: Any]
            },
            "saliency_region": result.saliencyRegion.map { box($0) as Any } ?? NSNull(),
            "saliency_center": result.saliencyCenter.map {
                ["x": Double($0.x), "y": Double($0.y)] as Any
            } ?? NSNull(),
            "claim": "production_owner_simulator_execution_and_coordinate_sanity_only"
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        let reportText = try XCTUnwrap(String(data: data, encoding: .utf8))
        let attachment = XCTAttachment(string: reportText)
        attachment.name = "production-vision-simulator-184.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[PRODUCTION_VISION_SIMULATOR] " + reportText)
        XCTAssertEqual(result.processingStatus, .completed)
        XCTAssertEqual(result.faceCount, 1, "Matches the separate CPU face request on these exact bytes")
        XCTAssertGreaterThanOrEqual(result.personCount, 1)
        XCTAssertFalse(result.subjects.isEmpty)
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        for subject in result.subjects {
            XCTAssertTrue(subject.confidence.isFinite)
            XCTAssertTrue(box(subject.boundingBox).values.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(subject.boundingBox.width, 0)
            XCTAssertGreaterThan(subject.boundingBox.height, 0)
            XCTAssertTrue(bounds.contains(subject.boundingBox))
        }
        if let saliency = result.saliencyRegion {
            XCTAssertTrue(box(saliency).values.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(saliency.width, 0)
            XCTAssertGreaterThan(saliency.height, 0)
            XCTAssertTrue(bounds.contains(saliency))
        }
    }

    private func run(kinds: [String], label: String, pixels: CVPixelBuffer,
                     recorder: VisionDiagnosticCallbackRecorder,
                     supportedCPUOnly: Bool = false) -> [String: Any] {
        let requests: [VNRequest] = kinds.map { kind in
            let completion: VNRequestCompletionHandler = { request, error in
                recorder.record(label: label, kind: kind, request: request, error: error)
            }
            switch kind {
            case "face": return VNDetectFaceRectanglesRequest(completionHandler: completion)
            case "human": return VNDetectHumanRectanglesRequest(completionHandler: completion)
            default: return VNGenerateAttentionBasedSaliencyImageRequest(completionHandler: completion)
            }
        }
        var configurationError: Error?
        if supportedCPUOnly {
            do {
                guard #available(iOS 17.0, *) else {
                    throw diagnosticError("Per-stage compute assignment is unavailable before iOS 17")
                }
                for request in requests {
                    let supported = try request.supportedComputeStageDevices
                    guard !supported.isEmpty else { throw diagnosticError("Request declared no supported compute stages") }
                    for (stage, devices) in supported.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                        guard let cpu = devices.first(where: { device in
                            if case .cpu = device { return true }
                            return false
                        }) else {
                            throw diagnosticError("No supported CPU for \(stage.rawValue)")
                        }
                        request.setComputeDevice(cpu, for: stage)
                        guard let configured = request.computeDevice(for: stage),
                              case .cpu = configured else {
                            throw diagnosticError("CPU assignment was not retained for \(stage.rawValue)")
                        }
                    }
                }
            } catch { configurationError = error }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
        let start = ProcessInfo.processInfo.systemUptime
        var performError: Error?
        if configurationError == nil {
            do { try handler.perform(requests) } catch { performError = error }
        }
        let duration = ProcessInfo.processInfo.systemUptime - start
        let callbacks = recorder.snapshot().filter { $0["run"] as? String == label }
        let requestRows: [[String: Any]] = zip(kinds, requests).map { kind, request in
            let matching = callbacks.filter { $0["kind"] as? String == kind }
            let callbackSucceeded = matching.count == 1 && matching[0]["error"] is NSNull
            let resultsPresent = request.results != nil
            // An empty successful results array is observed zero. Missing/failed is unknown.
            let succeeded = callbackSucceeded && resultsPresent
            var row: [String: Any] = [
                "kind": kind,
                "request_class": String(describing: type(of: request)),
                "revision": request.revision,
                "prefer_background_processing": request.preferBackgroundProcessing,
                "callback_count": matching.count,
                "callback_succeeded": callbackSucceeded,
                "results_property_present": resultsPresent,
                "raw_result_count": request.results.map { $0.count as Any } ?? NSNull(),
                "observed_result_count": succeeded ? ((request.results?.count ?? 0) as Any) : NSNull(),
                "status": succeeded ? "completed" : "unavailable",
                "cpu_assignment_requested": supportedCPUOnly,
                "explicit_compute_override": supportedCPUOnly ? NSNull() : (false as Any)
            ]
            if #available(iOS 17.0, *) {
                // Read back actual supported/assigned devices for this exact request.
                do {
                    let supported = try request.supportedComputeStageDevices
                    row["explicit_compute_override"] = supported.keys.contains {
                        request.computeDevice(for: $0) != nil
                    }
                    row["supported_compute_stages"] = supported.map { stage, devices in
                        ["stage": stage.rawValue,
                         "devices": devices.map { String(describing: $0) },
                         "configured_device": request.computeDevice(for: stage).map { String(describing: $0) } ?? "framework_default"] as [String: Any]
                    }.sorted { ($0["stage"] as? String ?? "") < ($1["stage"] as? String ?? "") }
                } catch {
                    row["compute_metadata_error"] = VisionDiagnosticCallbackRecorder.errorDetails(error)
                }
            }
            return row
        }
        return [
            "label": label,
            "elapsed_ms": duration * 1000,
            "perform_attempted": configurationError == nil,
            "configuration_error": VisionDiagnosticCallbackRecorder.errorDetails(configurationError),
            "perform_error": VisionDiagnosticCallbackRecorder.errorDetails(performError),
            "requests": requestRows,
            "all_requests_succeeded": performError == nil && requestRows.allSatisfy { $0["status"] as? String == "completed" }
        ]
    }

    private func authenticatedImageData() throws -> Data {
        let caches = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let root = caches.standardizedFileURL
            .appendingPathComponent("SETOSLegacyCameraReferences", isDirectory: true)
            .appendingPathComponent(Self.manifestSHA, isDirectory: true)
        guard root.resolvingSymlinksInPath().path == root.path else {
            throw diagnosticError("Reference cache must not traverse a symlink")
        }
        let manifestURL = root.appendingPathComponent("manifest.json")
        let imageURL = root.appendingPathComponent("184.jpg")
        for url in [manifestURL, imageURL] {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw diagnosticError("Reference input must be a regular file")
            }
        }
        let manifestData = try Data(contentsOf: manifestURL)
        guard sha(manifestData) == Self.manifestSHA else { throw diagnosticError("Manifest SHA mismatch") }
        struct Manifest: Decodable { let schema: String; let images: [String: String] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schema == "setos-legacy-camera-references.v1",
              manifest.images["184.jpg"] == Self.imageSHA else { throw diagnosticError("Reference manifest identity mismatch") }
        let data = try Data(contentsOf: imageURL)
        guard sha(data) == Self.imageSHA else { throw diagnosticError("184.jpg SHA mismatch") }
        return data
    }

    private func pixelBuffer(from data: Data) throws -> CVPixelBuffer {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var value: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
                                        kCVPixelFormatType_32BGRA, attributes as CFDictionary, &value)
        guard status == kCVReturnSuccess else { throw diagnosticError("Pixel allocation failed: \(status)") }
        let pixels = try XCTUnwrap(value)
        let lockStatus = CVPixelBufferLockBaseAddress(pixels, [])
        guard lockStatus == kCVReturnSuccess else { throw diagnosticError("Pixel lock failed: \(lockStatus)") }
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(pixels),
            width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        // Exactly the legacy replay's draw; no resize, auto-orientation or extra flip.
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func diagnosticError(_ message: String) -> NSError {
        NSError(domain: "VisionRequestIsolationDiagnostic", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Vision invokes individual callbacks off the perform caller's queue.
private final class VisionDiagnosticCallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [[String: Any]] = []

    func record(label: String, kind: String, request: VNRequest, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        rows.append([
            "callback_order": rows.count,
            "run": label,
            "kind": kind,
            "request_class": String(describing: type(of: request)),
            "revision": request.revision,
            "error": Self.errorDetails(error),
            "results_property_present": request.results != nil,
            "raw_result_count": request.results.map { $0.count as Any } ?? NSNull()
        ])
    }

    func snapshot() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }

    static func errorDetails(_ error: Error?, depth: Int = 0) -> Any {
        guard let error else { return NSNull() }
        let ns = error as NSError
        var row: [String: Any] = ["domain": ns.domain, "code": ns.code,
                                  "description": ns.localizedDescription]
        // Avoid unrelated userInfo or private payloads; include only the bounded cause chain.
        if depth < 3, let cause = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            row["underlying_error"] = errorDetails(cause, depth: depth + 1)
        }
        return row
    }
}
#endif
