import CoreGraphics
import UIKit
import XCTest
@testable import shafinMultitool

/// UI-007 — Camera Coach zones B/C must stay free of fixed-size layouts on the
/// critical lines: the observation line scales and wraps at every Dynamic Type
/// category (XS…AX5/XXXL, RU/EN), the rail reservation is measured from the
/// same scaled copy the band renders, and the primary action stays reachable.
final class CameraCoachDynamicTypeLayoutTests: XCTestCase {
    private let categories: [UIContentSizeCategory] = [
        .extraSmall,
        .large,
        .extraExtraExtraLarge,
        .accessibilityMedium,
        .accessibilityExtraExtraExtraLarge
    ]

    // MARK: - Source contract: no fixed-size observation line

    func testProductionObservationLinesScaleAndNeverLineLimitToOne() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/UI")
        let coachSource = try String(
            contentsOf: root.appendingPathComponent("Overlay/SETCameraCoachProductionView.swift"),
            encoding: .utf8
        )
        let componentsSource = try String(
            contentsOf: root.appendingPathComponent("DesignSystem/SETComponents.swift"),
            encoding: .utf8
        )

        // The supporting observation was the last single-line critical copy.
        XCTAssertFalse(
            coachSource.contains(".lineLimit(1)"),
            "zone B/C critical copy must never hard-limit to one line"
        )
        // Fixed-size body observation (SETTypography.font == .custom(fixedSize:))
        // must not render the live observation.
        let fixedBodyObservation = "SETTypography.font(.hudMono, size: SETTypographySize.body))"
        XCTAssertFalse(
            coachSource.contains(fixedBodyObservation),
            "observation lines must use SETTypography.scaledFont, not a fixed-size custom font"
        )
        // The shared pause band title: its old fixed-size + lineLimit(2) +
        // 0.82 scale-down combination is the exact clipping UI-007 removes.
        let scaledObservation = "scaledFont(.hudMono, size: SETTypographySize.body, relativeTo: .body)"
        XCTAssertTrue(
            componentsSource.contains(scaledObservation),
            "the pause review band title must follow Dynamic Type"
        )
        XCTAssertFalse(
            componentsSource.contains("minimumScaleFactor(0.82)"),
            "the pause band title must wrap instead of scaling down and truncating"
        )
        // Both production observation call sites (command band + status
        // overlay) must render the scaled face.
        let coachScaledCount = coachSource.components(separatedBy: scaledObservation).count - 1
        XCTAssertGreaterThanOrEqual(
            coachScaledCount, 2,
            "both production observation call sites (command band + status overlay) must scale"
        )
        // The status rail must reserve height from its rendered copy.
        XCTAssertTrue(
            coachSource.contains("content: statusRailContent"),
            "the status overlay must measure its rail from the rendered copy"
        )
    }

    // MARK: - Measured rail follows Dynamic Type (XS…AX5, RU/EN)

    func testMeasuredRailHeightGrowsMonotonicallyAcrossXSAX5ForLocalizedCopy() {
        for locale in [Locale(identifier: "en"), Locale(identifier: "ru")] {
            let observation = SETCopyKey.cameraEpisodeAwaitingMovement.localizedString(locale: locale)
            let action = SETCopyKey.cameraCorrectiveMoveLeft.localizedString(locale: locale)
            // RU copy runs longer than EN; the stress tail forces wrapping at
            // every category so the measurement contract is exercised hard.
            let content = SETCameraCoachRailContent(
                observation: observation + " " + observation,
                actionInstruction: action,
                whyLabel: SETCopyKey.cameraWhy.localizedString(locale: locale)
            )

            var previousHeight: CGFloat = 0
            for category in categories {
                let height = SETCameraCoachMetric.liveRailHeight(
                    canvasSize: CGSize(width: 390, height: 844),
                    isAccessibilityType: category.isAccessibilityCategory,
                    isExpanded: false,
                    content: content,
                    contentSizeCategory: category
                )
                XCTAssertGreaterThanOrEqual(
                    height, previousHeight,
                    "\(locale.identifier): rail height must not shrink as type grows (\(category.rawValue))"
                )
                previousHeight = height
            }
            XCTAssertGreaterThan(
                previousHeight,
                SETCameraCoachMetric.liveRailHeight(
                    canvasSize: CGSize(width: 390, height: 844),
                    isAccessibilityType: false,
                    isExpanded: false
                ),
                "\(locale.identifier): AX5 copy must reserve more than the static profile rail"
            )
        }
    }

    /// Anti-clipping floor: at AX5 with the longest supported copy, the rail
    /// must reserve at least the scaled observation + action stack it renders.
    /// If the measurement ever reverts to fixed fonts, this floor goes red.
    func testAccessibilityRailReservesTheScaledObservationAndActionFloor() {
        let category = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let canvas = CGSize(width: 390, height: 844)
        for locale in [Locale(identifier: "en"), Locale(identifier: "ru")] {
            let observation = SETCopyKey.cameraEpisodeAwaitingMovement.localizedString(locale: locale)
            let action = SETCopyKey.cameraCorrectiveMoveLeft.localizedString(locale: locale)
            let content = SETCameraCoachRailContent(
                observation: observation + " " + observation,
                actionInstruction: action,
                whyLabel: SETCopyKey.cameraWhy.localizedString(locale: locale),
                continueLabel: SETCopyKey.cameraContinue.localizedString(locale: locale)
            )
            let railHeight = SETCameraCoachMetric.liveRailHeight(
                canvasSize: canvas,
                isAccessibilityType: true,
                isExpanded: false,
                content: content,
                contentSizeCategory: category
            )

            let railWidth = min(
                SETCameraCoachMetric.liveRailMaximumWidth,
                canvas.width * SETCameraCoachMetric.liveRailAccessibilityPortraitWidthFraction
            )
            let innerWidth = railWidth - SETCameraCoachMetric.commandHorizontalInset * 2
            let observationFont = SETCameraCoachMetric.scaledUIFont(
                role: .hudMono,
                size: SETTypographySize.body,
                relativeTo: .body,
                compatibleWith: category
            )
            let commandFont = SETCameraCoachMetric.clampedScaledCommandUIFont(compatibleWith: category)
            let floor = ceil(Self.measuredHeight(observation + " " + observation, font: observationFont, width: innerWidth)
                + SETSpacing.x1
                + Self.measuredHeight(action, font: commandFont, width: innerWidth, maximumLines: 2)
                + SETCameraCoachMetric.commandVerticalInset * 2)

            XCTAssertGreaterThanOrEqual(
                railHeight, floor,
                "\(locale.identifier): AX5 rail reservation must cover the rendered scaled copy"
            )
        }
    }

    // MARK: - Status rail stacked action + supporting line

    func testStatusRailMeasurementReservesStackedActionAndSupportingLine() {
        let canvas = CGSize(width: 390, height: 844)
        let category = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let observation = "Проверяю кадр. Keep the frame steady while I compare"
        let supporting = "Сравнение выполняется по подтверждённому кадру, а не по живой ленте"
        let action = "Возобновить съёмку"

        let plain = SETCameraCoachRailContent(observation: observation)
        let stacked = SETCameraCoachRailContent(
            observation: observation,
            supportingObservation: supporting,
            stackedActionLabel: action
        )

        let plainHeight = SETCameraCoachMetric.liveRailHeight(
            canvasSize: canvas,
            isAccessibilityType: true,
            isExpanded: false,
            content: plain,
            contentSizeCategory: category
        )
        let stackedHeight = SETCameraCoachMetric.liveRailHeight(
            canvasSize: canvas,
            isAccessibilityType: true,
            isExpanded: false,
            content: stacked,
            contentSizeCategory: category
        )

        // The stacked action always keeps at least its 44pt reachable target.
        XCTAssertGreaterThanOrEqual(
            stackedHeight - plainHeight,
            SETComponentMetric.minimumHitTarget,
            "the stacked primary action must stay reachable at AX5"
        )
        // Copy-free content still falls back to the static profile rail.
        XCTAssertEqual(
            SETCameraCoachMetric.liveRailHeight(
                canvasSize: canvas,
                isAccessibilityType: true,
                isExpanded: false
            ),
            SETCameraCoachMetric.liveRailPortraitAccessibilityHeight
        )
    }

    private static func measuredHeight(
        _ text: String,
        font: UIFont,
        width: CGFloat,
        maximumLines: Int? = nil
    ) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let measured = max(font.lineHeight, ceil(bounds.height))
        guard let maximumLines else { return measured }
        return min(measured, ceil(font.lineHeight * CGFloat(maximumLines)))
    }
}
