import CoreVideo
import XCTest
@testable import shafinMultitool

/// Synthetic unit input for existing composition and episode fixtures.
/// This declares measurement availability; it is not image-quality ground truth.
enum CameraMeasuredPixelCritiqueFixture {
    static func analyze(snapshot: FrameFeatureSnapshot, semantics: SceneSemanticsReport,
                        signal: TechnicalQualitySignal = .empty) -> CritiqueReport {
        FrameCritiqueEngine().analyze(
            snapshot: snapshot, semantics: semantics,
            technicalEvidence: FrameTechnicalQualityEvidence(
                frameID: snapshot.frameId, capturedAt: snapshot.capturedAt,
                measurement: .measured(signal)
            )
        )
    }
}

final class TechnicalQualityMeasurementTests: XCTestCase {
    func testMissingPixelsRemainUnavailable() {
        let measurement = TechnicalQualityAnalyzer().measurement(pixelBuffer: nil)
        XCTAssertEqual(measurement, .unavailable(.missingPixelBuffer))
        XCTAssertNil(measurement.signal)
    }

    func testUnsupportedRealPixelBufferDoesNotBecomeMeasuredEmpty() throws {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 32, 32,
                                        kCVPixelFormatType_OneComponent8, nil, &buffer)
        XCTAssertEqual(result, kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        let analyzer = TechnicalQualityAnalyzer()
        XCTAssertEqual(analyzer.measurement(pixelBuffer: pixels), .unavailable(.unsupportedPixelFormat))
        XCTAssertNil(analyzer.measurement(pixelBuffer: pixels).signal)
        // Existing correction-only projection remains source compatible.
        XCTAssertEqual(analyzer.signal(pixelBuffer: pixels), .empty)
    }

    func testSuccessfullyMeasuredCleanPixelsRemainDistinctFromUnavailable() throws {
        let pixels = try makePixels { x, y in ((x / 3 + y / 3) % 2 == 0) ? 70 : 190 }
        let analyzer = TechnicalQualityAnalyzer()
        let measurement = analyzer.measurement(pixelBuffer: pixels)
        guard case let .measured(signal) = measurement else {
            return XCTFail("Valid BGRA pixels must be measured")
        }
        XCTAssertEqual(signal, .empty, "This controlled texture must exercise a measured no-issue result")
        XCTAssertEqual(analyzer.signal(pixelBuffer: pixels), signal)
        XCTAssertNotEqual(measurement, .unavailable(.notMeasured))
    }

    func testObservedExposureFaultsKeepTheirSignalAndAction() throws {
        for (luma, type, action) in [
            (UInt8(0), TechnicalQualityIssueType.underexposure, TechnicalQualityActionType.increaseExposure),
            (UInt8(255), TechnicalQualityIssueType.overexposure, TechnicalQualityActionType.reduceExposure)
        ] {
            let pixels = try makePixels { _, _ in luma }
            let analyzer = TechnicalQualityAnalyzer()
            let measurement = analyzer.measurement(pixelBuffer: pixels)
            let signal = try XCTUnwrap(measurement.signal)
            let exposure = try XCTUnwrap(signal.issues.first(where: { $0.type == type }))
            XCTAssertEqual(exposure.actionType, action)
            // The existing underexposure predicate also requires a bright side;
            // a uniformly black raster therefore is not a dominant fault.
            XCTAssertEqual(exposure.isDominant, luma == 255)
            XCTAssertEqual(exposure.confidence, 1)
            XCTAssertEqual(exposure.severity, 1)
            XCTAssertEqual(analyzer.signal(pixelBuffer: pixels), signal)
        }
    }

    func testDarkPixelsDoNotEstablishNoiseOrISOAdvice() throws {
        let fixtures: [(String, (Int, Int) -> UInt8, Double, Bool)] = [
            ("uniform black", { _, _ in 0 }, 0, false),
            ("uniform dark gray", { _, _ in 34 }, 34.0 / 255.0, false),
            ("sharp dark step", { x, _ in x < 48 ? 34 : 42 }, 38.0 / 255.0, false),
            ("dark center with bright side", { x, _ in x < 16 ? 200 : 0 }, 200.0 / 6.0 / 255.0, true)
        ]
        for (name, luma, expectedMean, dominantExposure) in fixtures {
            let measurement = TechnicalQualityAnalyzer().measurement(pixelBuffer: try makePixels(luma))
            guard case let .partial(signal, reason, detail) = measurement else {
                XCTFail("Removing unsupported noise cannot mark insufficient detail as measured-clean: \(name)")
                continue
            }
            XCTAssertEqual(reason, .sharpnessCauseUnobservable, name)
            XCTAssertFalse(measurement.supportsPositiveConfirmation, name)
            XCTAssertEqual(detail.meanLuma, expectedMean, accuracy: 1e-12, name)
            XCTAssertEqual(detail.sampleWidth, 96, name)
            XCTAssertEqual(detail.sampleHeight, 96, name)
            XCTAssertFalse(signal.issues.contains { $0.type == .noise }, name)
            XCTAssertFalse(signal.futureActionIds.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue), name)
            let exposure = try XCTUnwrap(signal.issues.first { $0.type == .underexposure }, name)
            XCTAssertEqual(exposure.actionType, .increaseExposure, name)
            XCTAssertEqual(exposure.isDominant, dominantExposure, name)
            let expectedExposure = dominantExposure ? 26.0 / 27.0 : 1
            XCTAssertEqual(exposure.severity, expectedExposure, accuracy: 1e-12, name)
            XCTAssertEqual(exposure.confidence, expectedExposure, accuracy: 1e-12, name)
            XCTAssertEqual(signal.issues.count, 1, "Only the actual exposure observation is supported: \(name)")
        }
    }

    func testExposureMeasurementCoversReflectedEdgesAtNondivisibleSizes() throws {
        let analyzer = TechnicalQualityAnalyzer()
        for size in [96, 143, 191, 352] {
            for vertical in [false, true] {
                var observed: [TechnicalQualityIssueSignal] = []
                for far in [false, true] {
                    let pixels = try makePixels(width: size, height: size) { x, y in
                        let coordinate = vertical ? y : x
                        let bright = far ? coordinate >= size - size / 8 : coordinate < size / 8
                        return bright ? 255 : 115
                    }
                    let signal = try XCTUnwrap(analyzer.measurement(pixelBuffer: pixels).signal)
                    observed.append(try XCTUnwrap(
                        signal.issues.first(where: { $0.type == .overexposure }),
                        "A controlled bright band must remain observable: size=\(size), vertical=\(vertical), far=\(far)"
                    ))
                }
                XCTAssertEqual(observed[0], observed[1],
                               "Reflection must not change the measured exposure: size=\(size), vertical=\(vertical)")
            }
        }
    }

    func testUninformativeDetailDoesNotInventFocusOrMotionCause() throws {
        let cases: [(name: String, width: Int, height: Int, luma: (Int, Int) -> UInt8)] = [
            ("uniform midgray", 96, 96, { _, _ in 128 }),
            ("sharp low-contrast step", 96, 96, { x, _ in x < 48 ? 118 : 124 }),
            ("sharp low-light step", 96, 96, { x, _ in x < 48 ? 34 : 42 }),
            ("too narrow for central differences", 2, 96, { x, _ in x == 0 ? 70 : 190 }),
            ("too short for central differences", 96, 2, { _, y in y == 0 ? 70 : 190 }),
            ("central-difference checker cancellation", 96, 96, { x, y in (x + y) % 2 == 0 ? 70 : 190 }),
            ("center-sampling checker alias", 192, 192, { x, y in (x + y) % 2 == 0 ? 70 : 190 })
        ]
        let analyzer = TechnicalQualityAnalyzer()
        for fixture in cases {
            let pixels = try makePixels(width: fixture.width, height: fixture.height, fixture.luma)
            let measurement = analyzer.measurement(pixelBuffer: pixels)
            guard case let .partial(signal, reason, detail) = measurement else {
                XCTFail("Insufficient sampled detail must remain partial: \(fixture.name)")
                continue
            }
            XCTAssertEqual(reason, .sharpnessCauseUnobservable, fixture.name)
            XCTAssertEqual(measurement.signal, signal, fixture.name)
            XCTAssertFalse(measurement.supportsPositiveConfirmation, fixture.name)
            XCTAssertEqual(detail.sampleWidth, min(96, fixture.width), fixture.name)
            XCTAssertEqual(detail.sampleHeight, min(96, fixture.height), fixture.name)
            XCTAssertTrue(detail.meanLuma.isFinite && (0...1).contains(detail.meanLuma), fixture.name)
            XCTAssertTrue(detail.gradientMean.isFinite && detail.gradientMean >= 0, fixture.name)
            XCTAssertTrue(detail.gradientVariance.isFinite && detail.gradientVariance >= 0, fixture.name)
            XCTAssertFalse(signal.issues.contains { $0.type == .defocus || $0.type == .motionBlur }, fixture.name)
            XCTAssertFalse(signal.futureActionIds.contains(TechnicalQualityActionType.refocusSubject.rawValue), fixture.name)
            XCTAssertFalse(signal.futureActionIds.contains(TechnicalQualityActionType.stabilizeCamera.rawValue), fixture.name)
        }
    }

    func testKnownSpatialSofteningDoesNotEstablishPhysicalBlurCause() throws {
        let size = 96
        let sharp: [UInt8] = (0..<(size * size)).map { index in
            ((index % size) / 12 + (index / size) / 12) % 2 == 0 ? 70 : 190
        }
        // Explicit normalized 7x7 box filter, with edge-clamped source coordinates.
        // This creates known spatial softening, without a camera-motion observation.
        let softened: [UInt8] = (0..<sharp.count).map { index in
            let x = index % size
            let y = index / size
            var sum = 0
            for dy in -3...3 {
                for dx in -3...3 {
                    let sourceX = min(size - 1, max(0, x + dx))
                    let sourceY = min(size - 1, max(0, y + dy))
                    sum += Int(sharp[sourceY * size + sourceX])
                }
            }
            return UInt8((sum + 24) / 49)
        }
        let left = 6 * size + 11
        let right = left + 1
        let sharpStep = abs(Int(sharp[right]) - Int(sharp[left]))
        let softenedStep = abs(Int(softened[right]) - Int(softened[left]))
        XCTAssertEqual(sharpStep, 120)
        XCTAssertGreaterThan(softenedStep, 0)
        XCTAssertLessThan(softenedStep, sharpStep, "The derivative must actually soften the same source edge")
        XCTAssertNotEqual(softened, sharp)

        let analyzer = TechnicalQualityAnalyzer()
        for (name, values) in [("sharp", sharp), ("box-filtered", softened)] {
            let pixels = try makePixels(width: size, height: size) { x, y in values[y * size + x] }
            let measurement = analyzer.measurement(pixelBuffer: pixels)
            let signal = try XCTUnwrap(measurement.signal, name)
            XCTAssertFalse(signal.issues.contains { $0.type == .defocus || $0.type == .motionBlur }, name)
            switch measurement {
            case .partial(_, let reason, let detail):
                XCTAssertEqual(name, "box-filtered", "The sharp structured reference must retain measured coverage")
                XCTAssertEqual(reason, .sharpnessCauseUnobservable, name)
                XCTAssertFalse(measurement.supportsPositiveConfirmation, name)
                XCTAssertEqual(detail.sampleWidth, size)
                XCTAssertEqual(detail.sampleHeight, size)
                XCTAssertTrue(detail.gradientMean.isFinite && detail.gradientVariance.isFinite, name)
            case .measured:
                XCTAssertEqual(name, "sharp", "Known softened texture remains uncertain about its physical cause")
                XCTAssertTrue(measurement.supportsPositiveConfirmation)
            case .unavailable:
                XCTFail("Valid generated BGRA pixels must retain a measured signal: \(name)")
            }
        }
    }

    func testPartialSharpnessCoveragePreservesMeasuredExposureFaults() throws {
        let analyzer = TechnicalQualityAnalyzer()
        for (luma, type, action) in [
            (UInt8(0), TechnicalQualityIssueType.underexposure, TechnicalQualityActionType.increaseExposure),
            (UInt8(255), TechnicalQualityIssueType.overexposure, TechnicalQualityActionType.reduceExposure)
        ] {
            let pixels = try makePixels { _, _ in luma }
            let measurement = analyzer.measurement(pixelBuffer: pixels)
            guard case let .partial(signal, reason, detail) = measurement else {
                XCTFail("Exposure remains measured while a uniform field supplies no sharpness cause: \(luma)")
                continue
            }
            XCTAssertEqual(reason, .sharpnessCauseUnobservable)
            XCTAssertFalse(measurement.supportsPositiveConfirmation)
            XCTAssertEqual(measurement.signal, signal)
            let exposure = try XCTUnwrap(signal.issues.first { $0.type == type })
            XCTAssertEqual(exposure.actionType, action)
            XCTAssertEqual(exposure.isDominant, luma == 255)
            XCTAssertEqual(exposure.confidence, 1)
            XCTAssertEqual(exposure.severity, 1)
            XCTAssertTrue(signal.futureActionIds.contains(action.rawValue))
            XCTAssertFalse(signal.issues.contains { $0.type == .defocus || $0.type == .motionBlur })
            XCTAssertEqual(detail.meanLuma, Double(luma) / 255, accuracy: 0.000001)
            XCTAssertEqual(detail.gradientMean, 0, accuracy: 0.000001)
            XCTAssertEqual(detail.gradientVariance, 0, accuracy: 0.000001)
        }
    }

    #if DEBUG
    func testDebugCaptureExplainsUnderexposureDominanceWithoutChangingMeasurement() throws {
        let analyzer = TechnicalQualityAnalyzer()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for brightSide in [false, true] {
            let pixels = try makePixels { x, _ in brightSide && x < 16 ? 200 : 0 }
            let captured = analyzer.debugMeasurement(pixelBuffer: pixels, frameID: "pixels", capturedAt: date)
            XCTAssertEqual(captured.evidence.measurement, analyzer.measurement(pixelBuffer: pixels))
            guard case .partial = captured.evidence.measurement else {
                return XCTFail("Exposure observations do not establish sharpness coverage")
            }
            let diagnostics = try XCTUnwrap(captured.diagnostics)
            let metrics = diagnostics.metrics
            XCTAssertEqual(metrics.sourceWidth, 96)
            XCTAssertEqual(metrics.sourceHeight, 96)
            XCTAssertEqual(metrics.sampleWidth, 96)
            XCTAssertEqual(metrics.sampleHeight, 96)
            XCTAssertEqual(metrics.meanLuma, brightSide ? (200.0 / 6.0 / 255.0) : 0, accuracy: 1e-12)
            XCTAssertEqual(metrics.deepShadowRatio, brightSide ? (5.0 / 6.0) : 1, accuracy: 1e-12)
            XCTAssertEqual(metrics.centerMeanLuma, 0)
            XCTAssertEqual(metrics.maxSideBrightRatio, brightSide ? 0.5 : 0)
            XCTAssertEqual(metrics.clippedBrightRatio, 0)
            XCTAssertEqual(metrics.brightHotspotRatio, 0)
            let evaluation = try XCTUnwrap(diagnostics.dominanceEvaluations.first)
            XCTAssertEqual(diagnostics.dominanceEvaluations.count, 1)
            XCTAssertEqual(evaluation.issueType, .underexposure)
            XCTAssertEqual(evaluation.combination, .all)
            XCTAssertEqual(evaluation.conditions, [
                "meanLuma <= 0.36": true, "deepShadowRatio >= 0.40": true,
                "centerMeanLuma <= 0.30": true, "maxSideBrightRatio >= 0.20": brightSide
            ])
            XCTAssertEqual(evaluation.result, brightSide)
            let issue = try XCTUnwrap(captured.evidence.measurement.signal?.issues.first { $0.type == .underexposure })
            XCTAssertEqual(issue.isDominant, evaluation.result)
            XCTAssertEqual(try JSONDecoder().decode(TechnicalQualityPixelDiagnostics.self,
                from: JSONEncoder().encode(diagnostics)), diagnostics)
        }
    }

    func testDebugCaptureDistinguishesUncalledDominanceFromFalseResult() throws {
        let analyzer = TechnicalQualityAnalyzer()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let neutral = analyzer.debugMeasurement(pixelBuffer: try makePixels { _, _ in 128 },
            frameID: "neutral", capturedAt: date)
        XCTAssertTrue(try XCTUnwrap(neutral.diagnostics).dominanceEvaluations.isEmpty,
                      "No exposure issue means its dominance predicate was not invoked")
        let bright = analyzer.debugMeasurement(pixelBuffer: try makePixels { _, _ in 255 },
            frameID: "bright", capturedAt: date)
        let evaluation = try XCTUnwrap(bright.diagnostics?.dominanceEvaluations.first)
        XCTAssertEqual(bright.diagnostics?.dominanceEvaluations.count, 1)
        XCTAssertEqual(evaluation.issueType, .overexposure)
        XCTAssertEqual(evaluation.combination, .any)
        XCTAssertEqual(evaluation.conditions.count, 5)
        XCTAssertTrue(evaluation.conditions.values.allSatisfy { $0 })
        XCTAssertTrue(evaluation.result)
        XCTAssertEqual(bright.evidence.measurement.signal?.issues.first { $0.type == .overexposure }?.isDominant, true)
    }

    func testDebugCaptureUnavailableCannotReusePreviousObservation() throws {
        let analyzer = TechnicalQualityAnalyzer()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotNil(analyzer.debugMeasurement(pixelBuffer: try makePixels { _, _ in 0 },
            frameID: "first", capturedAt: date).diagnostics)
        let missing = analyzer.debugMeasurement(pixelBuffer: nil, frameID: "missing", capturedAt: date)
        XCTAssertEqual(missing.evidence.measurement, .unavailable(.missingPixelBuffer))
        XCTAssertNil(missing.diagnostics)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 32, 32,
            kCVPixelFormatType_OneComponent8, nil, &buffer), kCVReturnSuccess)
        let unsupported = analyzer.debugMeasurement(pixelBuffer: try XCTUnwrap(buffer),
            frameID: "unsupported", capturedAt: date)
        XCTAssertEqual(unsupported.evidence.measurement, .unavailable(.unsupportedPixelFormat))
        XCTAssertNil(unsupported.diagnostics)
    }
    #endif

    private func makePixels(width: Int = 96, height: Int = 96,
                            _ luma: (Int, Int) -> UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                        kCVPixelFormatType_32BGRA, nil, &buffer)
        XCTAssertEqual(result, kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(pixels, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let value = luma(x, y)
                row[x * 4] = value
                row[x * 4 + 1] = value
                row[x * 4 + 2] = value
                row[x * 4 + 3] = 255
            }
        }
        return pixels
    }
}
