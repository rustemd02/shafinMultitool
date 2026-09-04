import CoreGraphics
import Foundation
import XCTest
@testable import shafinMultitool

@MainActor
private final class TestHapticRecorder: SETHapticPerforming {
    private(set) var events: [SETHapticEvent] = []

    func perform(_ event: SETHapticEvent) {
        events.append(event)
    }
}

final class SETDesignSystemTokenTests: XCTestCase {
    func testPaletteUsesThePublishedSETOSValues() {
        XCTAssertEqual(SETPalette.ink, SETRGBA(hex: 0x0B0B0E))
        XCTAssertEqual(SETPalette.warmWhite, SETRGBA(hex: 0xF4F1EA))
        XCTAssertEqual(SETPalette.setOrange, SETRGBA(hex: 0xFF5A1F))
        XCTAssertEqual(SETPalette.surfaceSolid, SETRGBA(hex: 0x141419))
        XCTAssertEqual(SETPalette.textPrimary, SETPalette.warmWhite)
        XCTAssertEqual(SETPalette.hudScrim.alpha, 0.72, accuracy: 0.0001)
        XCTAssertEqual(SETPalette.hairline.alpha, 0.14, accuracy: 0.0001)
    }

    func testSemanticContrastPairsMeetTheirPublishedBounds() {
        XCTAssertGreaterThanOrEqual(
            SETRGBA.contrastRatio(SETPalette.ink, SETPalette.warmWhite),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            SETRGBA.contrastRatio(SETPalette.ink, SETPalette.setOrange),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            SETRGBA.contrastRatio(SETPalette.textSecondary, SETPalette.ink),
            4.5
        )
        XCTAssertLessThan(
            SETRGBA.contrastRatio(SETPalette.setOrange, SETPalette.warmWhite),
            3
        )
    }

    func testMetricsKeepThePhaseZeroGeometryContract() {
        XCTAssertEqual(SETSpacing.x1, 4)
        XCTAssertEqual(SETSpacing.x2, 8)
        XCTAssertEqual(SETSpacing.x3, 12)
        XCTAssertEqual(SETSpacing.x4, 16)
        XCTAssertEqual(SETSpacing.x6, 24)
        XCTAssertEqual(SETSpacing.x8, 32)
        XCTAssertEqual(SETSpacing.x12, 48)
        XCTAssertEqual(SETRadius.editorialPanel, 0)
        XCTAssertEqual(SETRadius.control, 8)
        XCTAssertEqual(SETRadius.chip, 14)
        XCTAssertEqual(SETRadius.capsule, 999)
        XCTAssertEqual(SETComponentMetric.minimumHitTarget, 44)
        XCTAssertGreaterThanOrEqual(
            SETABRollCapsuleContract.minimumSegmentSize.width,
            SETComponentMetric.minimumHitTarget
        )
        XCTAssertGreaterThanOrEqual(
            SETABRollCapsuleContract.minimumSegmentSize.height,
            SETComponentMetric.minimumHitTarget
        )
        XCTAssertFalse(SETABRollCapsuleContract.usesMaterial)
        XCTAssertFalse(SETABRollCapsuleContract.usesBlur)
        XCTAssertFalse(SETABRollCapsuleContract.usesShadow)
        XCTAssertTrue(SETMarkerContract.oneAnnotationPerState)
        XCTAssertEqual(SETMarkerContract.requiredKinds, [.arrow, .line, .outline, .underline, .bracket])
        XCTAssertTrue(SETMarkerContract.hasArrowhead(.arrow))
        XCTAssertFalse(SETMarkerContract.hasArrowhead(.line))
        XCTAssertTrue(SETReflowLayout(count: 3, selectedIndex: 1).selectedShareIsBounded)
        XCTAssertEqual(SETReflowLayout(count: 3, selectedIndex: 1).fraction(for: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SETReflowLayout(count: 3, selectedIndex: 1).fraction(for: 0), 0.25, accuracy: 0.0001)
        XCTAssertTrue(SETReflowLayout(count: 3, selectedIndex: 1).hasSingleCutSeam)
    }

    func testMotionAndTypographyPresetsStayTyped() {
        XCTAssertEqual(SETMotion.springResponse, 0.4, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.springDampingFraction, 0.85, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.reflowGeometryDuration, 0.28, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.markerRevealDuration, 0.15, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.markerDrawDuration, 0.32, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.reducedMotionCrossfadeDuration, 0.12, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.pauseCutLineDuration, 0.22, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.pauseCutLabelDuration, 0.16, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.tallyPulseDuration, 1.2, accuracy: 0.0001)
        XCTAssertEqual(SETFontRole.allCases.count, 5)
        XCTAssertFalse(SETFontRole.wordmark.localizedTextAllowed)
        XCTAssertTrue(SETFontRole.allCases.filter(\.localizedTextAllowed).count == 4)
    }

    func testCommandTypographyUsesTheOwnedBoundedScale() {
        XCTAssertEqual(SETTypographySize.command, SETTypographySize.title)
        XCTAssertEqual(SETTypographySize.commandMaximum, SETTypographySize.displayMedium)
        XCTAssertEqual(SETTypographySize.command, 22)
        XCTAssertEqual(SETTypographySize.commandMaximum, 34)
        XCTAssertLessThanOrEqual(SETTypographySize.command, SETTypographySize.commandMaximum)
    }

    func testMarkerLedgerConsumesOneDomainEventAcrossRecomposition() {
        let ledger = SETMotionEventLedger()

        XCTAssertTrue(ledger.consume("camera.corrective.hint-42"))
        XCTAssertFalse(ledger.consume("camera.corrective.hint-42"))
        XCTAssertTrue(ledger.hasConsumed("camera.corrective.hint-42"))
        XCTAssertEqual(ledger.consumedCount, 1)
    }

    @MainActor
    func testPauseCutMarkOwnerEmitsOneRigidHapticAcrossRecreatedViews() {
        let ledger = SETMotionEventLedger()
        let eventID = "frame-a.take-2.cut"
        let haptic = TestHapticRecorder()
        let controller = SETPauseCutMarkController(eventLedger: ledger, haptic: haptic)
        XCTAssertTrue(controller.begin(eventID: eventID))
        XCTAssertFalse(controller.begin(eventID: eventID))
        XCTAssertTrue(ledger.hasConsumed(eventID))
        XCTAssertEqual(ledger.consumedCount, 1)
        XCTAssertEqual(haptic.events, [.rigid])
        XCTAssertEqual(SETMotion.pauseCutLineDuration + SETMotion.pauseCutLabelDuration, 0.38, accuracy: 0.0001)
        XCTAssertEqual(SETMotion.reducedMotionCrossfadeDuration, 0.12, accuracy: 0.0001)
    }

    func testCorrectiveArrowTerminatesAtTargetBoundaryWithoutCrossingPortraitSubject() {
        let geometry = SETCorrectiveArrowGeometry.resolve(
            canvasSize: CGSize(width: 390, height: 844),
            targetRegion: NormalizedRect(x: 0.42, y: 0.25, width: 0.24, height: 0.36),
            commandRailFrame: CGRect(x: 16, y: 700, width: 250, height: 96)
        )

        XCTAssertTrue(
            geometry.end.x >= geometry.targetRect.minX
                && geometry.end.x <= geometry.targetRect.maxX
                && geometry.end.y >= geometry.targetRect.minY
                && geometry.end.y <= geometry.targetRect.maxY
        )
        XCTAssertTrue(
            geometry.end.x == geometry.targetRect.minX
                || geometry.end.x == geometry.targetRect.maxX
                || geometry.end.y == geometry.targetRect.minY
                || geometry.end.y == geometry.targetRect.maxY
        )
        XCTAssertTrue(geometry.safeRect.contains(geometry.start))
        XCTAssertTrue(geometry.safeRect.contains(geometry.headLeft))
        XCTAssertTrue(geometry.safeRect.contains(geometry.headRight))
        XCTAssertTrue(geometry.strokeAvoidsTarget())
    }

    func testCorrectiveArrowTerminatesAtTargetBoundaryWithoutCrossingLandscapeSubject() {
        let geometry = SETCorrectiveArrowGeometry.resolve(
            canvasSize: CGSize(width: 844, height: 390),
            targetRegion: NormalizedRect(x: 0.62, y: 0.18, width: 0.28, height: 0.48),
            commandRailFrame: CGRect(x: 16, y: 250, width: 480, height: 112)
        )

        XCTAssertTrue(geometry.safeRect.contains(geometry.start))
        XCTAssertTrue(geometry.safeRect.contains(geometry.end))
        XCTAssertTrue(geometry.safeRect.contains(geometry.headLeft))
        XCTAssertTrue(geometry.safeRect.contains(geometry.headRight))
        XCTAssertTrue(geometry.strokeAvoidsTarget())
    }

    func testSubjectSafeControlChoosesOppositeTopEdgeInPortraitAndLandscape() {
        let portraitTopLeft = SETSubjectSafeControlPlacement.resolve(
            canvasSize: CGSize(width: 390, height: 844),
            controlSize: CGSize(width: 180, height: 52),
            safeInsets: SETSafeInsets(top: 84, leading: 8, bottom: 8, trailing: 8),
            subjectRegions: [CGRect(x: 12, y: 110, width: 170, height: 300)],
            commandRailFrame: CGRect(x: 16, y: 700, width: 280, height: 96)
        )
        XCTAssertEqual(portraitTopLeft?.edge, .topTrailing)
        if let portraitTopLeft {
            XCTAssertEqual(portraitTopLeft.frame.maxY, 136, accuracy: 0.001)
        }

        let landscapeTopRight = SETSubjectSafeControlPlacement.resolve(
            canvasSize: CGSize(width: 844, height: 390),
            controlSize: CGSize(width: 180, height: 52),
            safeInsets: SETSafeInsets(top: 84, leading: 8, bottom: 8, trailing: 8),
            subjectRegions: [CGRect(x: 650, y: 96, width: 180, height: 160)],
            commandRailFrame: CGRect(x: 16, y: 250, width: 480, height: 112)
        )
        XCTAssertEqual(landscapeTopRight?.edge, .topLeading)
        XCTAssertGreaterThanOrEqual(landscapeTopRight?.frame.minX ?? 0, 8)
        XCTAssertLessThanOrEqual(landscapeTopRight?.frame.maxX ?? 0, 836)
    }

    func testSubjectSafeControlReturnsNilWhenEveryEdgeOverlapsSubjectOrRail() {
        let placement = SETSubjectSafeControlPlacement.resolve(
            canvasSize: CGSize(width: 390, height: 844),
            controlSize: CGSize(width: 180, height: 52),
            safeInsets: SETSafeInsets(top: 84, leading: 8, bottom: 8, trailing: 8),
            subjectRegions: [CGRect(x: 8, y: 84, width: 374, height: 676)],
            commandRailFrame: CGRect(x: 8, y: 760, width: 374, height: 76)
        )
        XCTAssertNil(placement)
    }

    func testPreviewMappingConvertsVisionLowerLeftOnceForPortraitAndMirroredLandscape() {
        let region = NormalizedRect(x: 0.18, y: 0.25, width: 0.22, height: 0.30)
        let metadata = CameraPreviewRegionMapper.metadataOutputRect(for: region)
        XCTAssertEqual(metadata?.minX ?? -1, 0.18, accuracy: 0.0001)
        XCTAssertEqual(metadata?.minY ?? -1, 0.45, accuracy: 0.0001)

        let portrait = CameraPreviewRegionMapper.map(
            region,
            using: { rect in
                CGRect(x: rect.minX * 400, y: rect.minY * 900,
                       width: rect.width * 400, height: rect.height * 900)
            },
            bounds: CGRect(x: 0, y: 0, width: 400, height: 900)
        )
        XCTAssertEqual(portrait?.minY ?? -1, 405, accuracy: 0.001)

        let landscapeMirrored = CameraPreviewRegionMapper.map(
            region,
            using: { rect in
                CGRect(x: (1 - rect.maxX) * 900, y: rect.minY * 400,
                       width: rect.width * 900, height: rect.height * 400)
            },
            bounds: CGRect(x: 0, y: 0, width: 900, height: 400)
        )
        XCTAssertEqual(landscapeMirrored?.minX ?? -1, 540, accuracy: 0.001)
        XCTAssertEqual(landscapeMirrored?.maxX ?? -1, 738, accuracy: 0.001)
    }

    func testAcceptedFrameMapperUsesOrientedAspectFillPixelsAndMirrorsOnce() {
        let region = NormalizedRect(x: 0.18, y: 0.25, width: 0.22, height: 0.30)

        // A 2×4 portrait image fills a 400×900 canvas at 225 points per source
        // pixel, leaving the expected 25-point horizontal crop on each side.
        let portrait = SETAcceptedFrameRegionMapper.map(
            region,
            sourcePixelSize: CGSize(width: 2, height: 4),
            orientation: .up,
            canvasSize: CGSize(width: 400, height: 900)
        )
        XCTAssertNotNil(portrait)
        XCTAssertEqual(portrait?.minX ?? -1, 56, accuracy: 0.001)
        XCTAssertEqual(portrait?.minY ?? -1, 405, accuracy: 0.001)
        XCTAssertEqual(portrait?.width ?? -1, 99, accuracy: 0.001)
        XCTAssertEqual(portrait?.height ?? -1, 270, accuracy: 0.001)
        XCTAssertEqual(portrait?.midX ?? -1, 105.5, accuracy: 0.001)
        XCTAssertEqual(portrait?.midY ?? -1, 540, accuracy: 0.001)

        // The right-oriented source becomes 4×2. The lower-left Vision Y is
        // flipped exactly once, and the accepted display mirror is opt-in.
        let landscapeMirrored = SETAcceptedFrameRegionMapper.map(
            region,
            sourcePixelSize: CGSize(width: 2, height: 4),
            orientation: .right,
            canvasSize: CGSize(width: 900, height: 400),
            isMirrored: true
        )
        XCTAssertNotNil(landscapeMirrored)
        XCTAssertEqual(landscapeMirrored?.minX ?? -1, 540, accuracy: 0.001)
        XCTAssertEqual(landscapeMirrored?.maxX ?? -1, 738, accuracy: 0.001)
        XCTAssertEqual(landscapeMirrored?.minY ?? -1, 177.5, accuracy: 0.001)
        XCTAssertEqual(landscapeMirrored?.maxY ?? -1, 312.5, accuracy: 0.001)
        XCTAssertEqual(landscapeMirrored?.midX ?? -1, 639, accuracy: 0.001)
        XCTAssertEqual(landscapeMirrored?.midY ?? -1, 245, accuracy: 0.001)

        let canvas = CGRect(x: 0, y: 0, width: 400, height: 900)
        let clipped = SETAcceptedFrameRegionMapper.map(
            // NormalizedRect clamps fields to [0,1] at init, so out-of-frame overscan is exercised through aspect-fill display overscan (displayed width 450 > canvas 400), not negative normalized coordinates.
            NormalizedRect(x: 0.00, y: 0.80, width: 0.50, height: 0.20),
            sourcePixelSize: CGSize(width: 2, height: 4),
            orientation: .up,
            canvasSize: canvas.size
        )
        XCTAssertNotNil(clipped)
        XCTAssertEqual(clipped?.minX ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(clipped?.minY ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(clipped?.maxX ?? -1, 200, accuracy: 0.001)
        XCTAssertEqual(clipped?.maxY ?? -1, 180, accuracy: 0.001)
        if let clipped {
            XCTAssertTrue(canvas.contains(clipped))
            XCTAssertTrue([
                clipped.minX, clipped.minY, clipped.maxX, clipped.maxY,
                clipped.midX, clipped.midY
            ].allSatisfy { $0.isFinite })
        }
        XCTAssertNil(
            SETAcceptedFrameRegionMapper.map(
                NormalizedRect(x: 0.2, y: 0.2, width: 0, height: 0.2),
                sourcePixelSize: CGSize(width: 2, height: 4),
                orientation: .up,
                canvasSize: canvas.size
            )
        )
    }

    func testPauseSummaryUsesLocalizedSemanticFallbackInsteadOfRawVerdict() {
        let critique = PauseCritiquePresentation(
            frameId: "locale-frame",
            verdict: .mixed,
            verdictConfidence: 0.7,
            summaryId: "locale-summary",
            shortVerdict: "Injected pipeline verdict must never render",
            whyGood: nil,
            whyProblematic: nil,
            strengths: [],
            issues: [],
            actions: [],
            noChangeRationale: nil,
            assumptions: [],
            traceRootIds: [],
            fallbackUsed: false
        )

        let english = SETLocalizedPauseCopy.summary(for: critique, locale: Locale(identifier: "en"))
        let russian = SETLocalizedPauseCopy.summary(for: critique, locale: Locale(identifier: "ru"))

        XCTAssertEqual(english, "NO CHANGE NEEDED")
        XCTAssertEqual(russian, "ИЗМЕНЕНИЙ НЕ ТРЕБУЕТСЯ")
        XCTAssertFalse(english.contains("Injected"))
        XCTAssertFalse(russian.contains("Injected"))
    }

    func testPauseSummaryPrefersNonEmptyExpectedOutcomeAndFallsBackWhenBlank() {
        let outcome = "The subject will fill more of the frame."
        let action = PauseActionRow(
            actionId: "semantic-action",
            actionType: .increaseSubjectSize,
            semanticActionType: .stepCloser,
            priority: 1,
            confidence: 0.9,
            linkedIssueIds: [],
            expectedOutcome: "  \(outcome)  ",
            targetRegion: nil,
            overlayHintId: nil,
            traceRefId: nil
        )
        let critique = PauseCritiquePresentation(
            frameId: "semantic-frame",
            verdict: .needsFix,
            verdictConfidence: 0.8,
            summaryId: "semantic-summary",
            shortVerdict: "Raw verdict must not render",
            whyGood: nil,
            whyProblematic: nil,
            strengths: [],
            issues: [],
            actions: [action],
            noChangeRationale: nil,
            assumptions: [],
            traceRootIds: [],
            fallbackUsed: false
        )

        XCTAssertEqual(
            SETLocalizedPauseCopy.summary(for: critique, locale: Locale(identifier: "en")),
            SETCopyKey.traceActionStepCloser.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertFalse(
            SETLocalizedPauseCopy.summary(for: critique, locale: Locale(identifier: "en"))
                .contains(outcome)
        )

        let blankAction = PauseActionRow(
            actionId: "blank-action",
            actionType: .increaseSubjectSize,
            semanticActionType: .stepCloser,
            priority: 1,
            confidence: 0.9,
            linkedIssueIds: [],
            expectedOutcome: " \n\t",
            targetRegion: nil,
            overlayHintId: nil,
            traceRefId: nil
        )
        let blankCritique = PauseCritiquePresentation(
            frameId: "blank-frame",
            verdict: .needsFix,
            verdictConfidence: 0.8,
            summaryId: "blank-summary",
            shortVerdict: "Raw verdict must not render",
            whyGood: nil,
            whyProblematic: nil,
            strengths: [],
            issues: [],
            actions: [blankAction],
            noChangeRationale: nil,
            assumptions: [],
            traceRootIds: [],
            fallbackUsed: false
        )

        XCTAssertEqual(
            SETLocalizedPauseCopy.summary(for: blankCritique, locale: Locale(identifier: "en")),
            SETCopyKey.traceActionStepCloser.localizedString(locale: Locale(identifier: "en"))
        )
    }

    func testNominalTimecodeUsesTwentyFourFramesAndFreezesAtWholeFrames() {
        XCTAssertEqual(CameraNominalTimecode.string(elapsed: 0), "00:00:00:00")
        XCTAssertEqual(CameraNominalTimecode.string(elapsed: 1), "00:00:01:00")
        XCTAssertEqual(CameraNominalTimecode.string(elapsed: 1.5), "00:00:01:12")
        XCTAssertEqual(CameraNominalTimecode.string(elapsed: 3_661.25), "01:01:01:06")
        XCTAssertEqual(CameraNominalTimecode.string(elapsed: 3_661.25, showsFrames: false), "01:01:01")
    }
}
