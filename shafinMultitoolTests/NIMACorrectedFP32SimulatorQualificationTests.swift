import XCTest
import Foundation
import CoreML
import Vision
import ImageIO
import CoreVideo
import CryptoKit
@testable import shafinMultitool

#if DEBUG
@MainActor
final class NIMACorrectedFP32SimulatorQualificationTests: XCTestCase {
    private let protocolSHA = "203aeed91ee401d988714cc3c2abb6c77d64e3eba75465a3829c832f6f682d02"
    private let canonicalIDs = [
        "constant_gray_64", "constant_gray_128", "checkerboard_16", "rgb_ramps",
        "seeded_noise", "corner_patch", "left_stripe", "center_square", "lasiesta_I_OC_01_121"
    ]
    private let orientationIDs = ["original_public_lasiesta_up", "original_public_lasiesta_right"]

    func testExternalFP32CanonicalDistributionAndActualScorerCPUParity() async throws {
        try await run(mode: "cpuOnly", computeUnits: .cpuOnly, canonical: true)
    }

    func testExternalFP32CanonicalDistributionAndActualScorerProductionComputeParity() async throws {
        // This requests the production configuration. Simulator execution does not prove ANE use.
        try await run(mode: "cpuAndNeuralEngine", computeUnits: .cpuAndNeuralEngine, canonical: true)
    }

    func testExternalFP32NonSquareOrientationAndScorerAgreement() async throws {
        try await run(mode: "orientationCPUOnly", computeUnits: .cpuOnly, canonical: false)
    }

    private struct Specification: Decodable {
        let schema: String
        let modelPackage: String
        let modelFiles: [String: String]
        let maxAbsProbability: Double
        let maxAbsScore: Double
        let maxProbabilitySumError: Double
        let maxWrapperScoreDifference: Double
        let canonicalIds: [String]
        let orientationIds: [String]
        let inputs: [Input]
    }

    private struct Input: Decodable {
        let id: String
        let inputFile: String
        let inputSha256: String
        let rgbSha256: String
        let width: Int
        let height: Int
        let orientation: String
        let sourceSha256: String
        let reference: [Double]?
        let pixelSamples: [PixelSample]
    }

    private struct PixelSample: Decodable {
        let x: Int
        let y: Int
        let rgb: [Int]
    }

    private enum Failure: Error {
        case invalid(String)
    }

    private final class CallbackValues: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double?] = []
        func append(_ value: Double?) {
            lock.lock()
            defer { lock.unlock() }
            values.append(value)
        }
        func snapshot() -> [Double?] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.invalid(message) }
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fixtureRoot() throws -> URL {
        #if !targetEnvironment(simulator)
        throw Failure.invalid("This qualification is simulator-only; physical-device admission is separate.")
        #else
        let caches = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        return caches.appendingPathComponent("SETOSNIMAQualification", isDirectory: true)
            .appendingPathComponent(String(protocolSHA.prefix(12)), isDirectory: true)
        #endif
    }

    private func loadSpecification(root: URL) throws -> Specification {
        let data = try Data(contentsOf: root.appendingPathComponent("protocol.json"))
        try require(sha(data) == protocolSHA, "Qualification protocol SHA mismatch or unstaged input.")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try decoder.decode(Specification.self, from: data)
        try require(value.schema == "setos-nima-ios-simulator-qualification.v1", "Wrong protocol schema.")
        try require(value.canonicalIds == canonicalIDs && value.orientationIds == orientationIDs, "Missing or extra declared IDs.")
        try require(value.inputs.map(\.id) == canonicalIDs + orientationIDs, "Input membership/order differs.")
        try require(value.maxAbsProbability == 0.0001 && value.maxAbsScore == 0.001 &&
                    value.maxProbabilitySumError == 0.005 && value.maxWrapperScoreDifference == 0.001,
                    "Numerical thresholds differ from the declared protocol.")
        for input in value.inputs {
            try require(input.width > 0 && input.height > 0 && input.width <= 4096 && input.height <= 4096,
                        "Invalid source dimensions.")
            if canonicalIDs.contains(input.id) {
                let reference = try XCTUnwrap(input.reference)
                try require(reference.count == 10 && reference.allSatisfy { $0.isFinite && $0 >= 0 },
                            "Missing/nonfinite canonical reference.")
                try require(input.width == 224 && input.height == 224 && input.orientation == "up",
                            "Canonical pixels/orientation differ from reference.")
            } else {
                try require(input.reference == nil && input.width != input.height,
                            "Non-square case must not claim a reference-resampling parity.")
            }
        }
        return value
    }

    private func loadModel(root: URL, specification: Specification,
                           computeUnits: MLComputeUnits) throws -> MLModel {
        let package = root.appendingPathComponent(specification.modelPackage, isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: package, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
        var observed: [String: String] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            try require(values.isSymbolicLink != true, "Symlink in model package.")
            if values.isRegularFile == true {
                let relative = String(url.path.dropFirst(package.path.count + 1))
                observed[relative] = sha(try Data(contentsOf: url))
            }
        }
        try require(observed == specification.modelFiles && observed.count == 3, "Model bytes or membership differ.")
        let compiled = try MLModel.compileModel(at: package)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        // Any unsupported nominal configuration throws and fails this selector.
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        let description = model.modelDescription
        try require(Set(description.inputDescriptionsByName.keys) == Set(["image"]), "Unexpected model input.")
        let input = try XCTUnwrap(description.inputDescriptionsByName["image"]?.imageConstraint)
        try require(input.pixelsWide == 224 && input.pixelsHigh == 224, "Unexpected model image dimensions.")
        try require(Set(description.outputDescriptionsByName.keys) == Set(["Identity"]), "Unexpected output feature.")
        let output = try XCTUnwrap(description.outputDescriptionsByName["Identity"]?.multiArrayConstraint)
        try require(output.shape.map(\.intValue) == [1, 10] && output.dataType == .float32,
                    "Expected Float32 [1,10] output.")
        return model
    }

    private func pixelBuffer(root: URL, input: Input) throws -> CVPixelBuffer {
        let raw = try Data(contentsOf: root.appendingPathComponent(input.inputFile))
        try require(sha(raw) == input.inputSha256 && raw.count == input.width * input.height * 4,
                    "Input byte SHA/dimensions mismatch.")
        let bytes = [UInt8](raw)
        var rgb = Data(capacity: input.width * input.height * 3)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            try require(bytes[offset + 3] == 255, "Fixture must be opaque BGRA.")
            rgb.append(contentsOf: [bytes[offset + 2], bytes[offset + 1], bytes[offset]])
        }
        try require(sha(rgb) == input.rgbSha256, "BGRA channel order does not match canonical RGB.")
        try require(input.pixelSamples.count == 5, "Missing corner/center coordinate controls.")
        for sample in input.pixelSamples {
            try require((0..<input.width).contains(sample.x) && (0..<input.height).contains(sample.y),
                        "Sample coordinate outside source.")
            let index = (sample.y * input.width + sample.x) * 4
            try require([Int(bytes[index + 2]), Int(bytes[index + 1]), Int(bytes[index])] == sample.rgb,
                        "Top-left coordinate/channel control mismatch.")
        }
        var allocated: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        try require(CVPixelBufferCreate(kCFAllocatorDefault, input.width, input.height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &allocated) == kCVReturnSuccess,
            "Pixel buffer allocation failed.")
        let result = try XCTUnwrap(allocated)
        try require(CVPixelBufferLockBaseAddress(result, []) == kCVReturnSuccess, "Pixel buffer lock failed.")
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(result))
        let stride = CVPixelBufferGetBytesPerRow(result)
        try require(stride >= input.width * 4, "Invalid pixel buffer row stride.")
        raw.withUnsafeBytes { source in
            for row in 0..<input.height {
                address.advanced(by: row * stride).copyMemory(
                    from: source.baseAddress!.advanced(by: row * input.width * 4),
                    byteCount: input.width * 4)
            }
        }
        var copied = Data(capacity: raw.count)
        for row in 0..<input.height {
            copied.append(address.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self),
                          count: input.width * 4)
        }
        try require(sha(copied) == input.inputSha256, "Actual CVPixelBuffer rows differ from source bytes.")
        return result
    }

    private func run(mode: String, computeUnits: MLComputeUnits, canonical: Bool) async throws {
        let root = try fixtureRoot()
        let specification = try loadSpecification(root: root)
        let model = try loadModel(root: root, specification: specification, computeUnits: computeUnits)
        let visionModel = try VNCoreMLModel(for: model)
        let scorer = try AestheticScorer(testingModel: model)
        let selectedIDs = canonical ? canonicalIDs : orientationIDs
        let inputs = specification.inputs.filter { selectedIDs.contains($0.id) }
        try require(inputs.count == (canonical ? 9 : 2), "Empty/incomplete input selection.")
        var rows: [[String: Any]] = []
        for input in inputs {
            var row: [String: Any] = ["id": input.id, "status": "FAIL"]
            do {
                let buffer = try pixelBuffer(root: root, input: input)
                let orientation: CGImagePropertyOrientation
                switch input.orientation {
                case "up": orientation = .up
                case "right": orientation = .right
                default: throw Failure.invalid("Unsupported orientation; no silent fallback.")
                }
                let request = VNCoreMLRequest(model: visionModel)
                request.imageCropAndScaleOption = .scaleFill
                let start = CFAbsoluteTimeGetCurrent()
                try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation,
                                          options: [:]).perform([request])
                let observations = try XCTUnwrap(request.results as? [VNCoreMLFeatureValueObservation])
                try require(observations.count == 1 && observations[0].featureName == "Identity",
                            "Missing or unexpected Vision probability feature.")
                let array = try XCTUnwrap(observations[0].featureValue.multiArrayValue)
                try require(array.count == 10 && array.dataType == .float32 &&
                            array.shape.map(\.intValue) == [1, 10], "Invalid output tensor.")
                let probabilities = (0..<10).map { array[$0].doubleValue }
                try require(probabilities.allSatisfy { $0.isFinite && $0 >= 0 }, "Nonfinite/negative probability.")
                let total = probabilities.reduce(0, +)
                let score = probabilities.enumerated().reduce(0.0) { $0 + $1.element * Double($1.offset + 1) }
                try require(abs(total - 1) <= specification.maxProbabilitySumError && (1...10).contains(score),
                            "Invalid probability normalization or score.")
                let values = CallbackValues()
                let completed = expectation(description: "Actual AestheticScorer \(input.id)")
                completed.assertForOverFulfill = true
                scorer.score(pixelBuffer: buffer, orientation: orientation) { score in
                    values.append(score)
                    completed.fulfill()
                }
                await fulfillment(of: [completed], timeout: 30)
                let callbacks = values.snapshot()
                try require(callbacks.count == 1, "Missing or duplicate actual scorer callback.")
                let wrapperScore = try XCTUnwrap(callbacks[0])
                try require(wrapperScore.isFinite &&
                            abs(wrapperScore - score) <= specification.maxWrapperScoreDifference,
                            "Actual wrapper score differs from direct Vision distribution.")
                row = [
                    "id": input.id, "status": "PASS", "width": input.width, "height": input.height,
                    "orientation": input.orientation, "orientation_raw_value": orientation.rawValue,
                    "pixel_format": "32BGRA", "pixel_rows_verified": true,
                    "input_sha256": input.inputSha256, "rgb_sha256": input.rgbSha256,
                    "source_sha256": input.sourceSha256, "crop_and_scale": "scaleFill",
                    "distribution": probabilities, "score10": score, "wrapper_score10": wrapperScore,
                    "wrapper_callback_count": callbacks.count,
                    "wrapper_score_difference": abs(wrapperScore - score),
                    "seconds_two_invocations": CFAbsoluteTimeGetCurrent() - start
                ]
                if let reference = input.reference {
                    let differences = zip(probabilities, reference).map { abs($0 - $1) }
                    let maximum = try XCTUnwrap(differences.max())
                    let referenceScore = reference.enumerated().reduce(0.0) { $0 + $1.element * Double($1.offset + 1) }
                    let scoreError = abs(score - referenceScore)
                    row["max_abs_probability"] = maximum
                    row["abs_score_difference"] = scoreError
                    row["scope"] = "matched canonical pixels; reconstructed pinned reference"
                    try require(maximum <= specification.maxAbsProbability &&
                                scoreError <= specification.maxAbsScore &&
                                abs(wrapperScore - referenceScore) <= specification.maxAbsScore,
                                "Declared canonical numerical parity failed.")
                } else {
                    row["scope"] = "non-square orientation invocation and wrapper agreement; no reference resampling parity"
                }
            } catch {
                row["status"] = "FAIL"
                row["error"] = String(describing: error)
            }
            rows.append(row)
        }
        let failures = rows.filter { ($0["status"] as? String) != "PASS" }.count
        let report: [String: Any] = [
            "schema": "setos-nima-ios-simulator-result.v1", "protocol_sha256": protocolSHA,
            "mode": mode, "simulator": true, "ane_execution_observed": false,
            "configuration_is_nominal": computeUnits == .cpuAndNeuralEngine,
            "model_files": specification.modelFiles, "cases": rows, "expected_count": inputs.count,
            "case_count": rows.count, "failures": failures, "status": failures == 0 ? "PASS" : "FAIL",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "simulator_model": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown",
            "app_bundle": Bundle.main.bundleIdentifier ?? "unknown",
            "production_weights_replaced": false, "release_admitted": false,
            "physical_device_gate_closed": false, "quality_gate_closed": false
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "nima-simulator-\(mode)-\(inputs.count)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(rows.count, canonical ? 9 : 2)
        XCTAssertEqual(failures, 0, "Every declared input must execute and pass; inspect the retained attachment.")
    }
}
#endif
