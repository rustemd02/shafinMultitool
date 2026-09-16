import CoreGraphics
import Foundation
import ImageIO
import UIKit

enum SETSpacing {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x12: CGFloat = 48
}

enum SETRadius {
    static let editorialPanel: CGFloat = 0
    static let control: CGFloat = 8
    static let chip: CGFloat = 14
    static let capsule: CGFloat = 999
}

enum SETStroke {
    static let hairline: CGFloat = 0.5
    static let standard: CGFloat = 1
    static let guideOuter: CGFloat = 1
    static let guideInner: CGFloat = 2
}

enum SETComponentMetric {
    static let minimumHitTarget: CGFloat = 44
    static let capsuleSegmentWidth: CGFloat = 92
    static let capsuleHeight: CGFloat = 48
    static let chipMaxWidth: CGFloat = 420
    static let galleryCardWidth: CGFloat = 320
    static let galleryCameraPortraitHeight: CGFloat = 586
    static let galleryLandscapeHeight: CGFloat = 300
    static let galleryLandscapeWidth: CGFloat = 720
    static let gallerySectionMaxWidth: CGFloat = 960
    static let cameraPreviewAspect: CGFloat = 16.0 / 9.0
    static let cameraCommandMaxWidth: CGFloat = 360
    static let cameraMarkerWidth: CGFloat = 150
    static let cameraMarkerHeight: CGFloat = 96
    static let entryActionHeight: CGFloat = 56
    static let entryLandscapeRailFraction: CGFloat = 0.34
    static let entryLandscapeAccessibilityRailFraction: CGFloat = 0.24
    static let entryLandscapeMinimumPhaseWidth: CGFloat = 280
    static let entryCompactHeightThreshold: CGFloat = 500
    static let entryMarkerRailHeight: CGFloat = 16
    static let entryLeaderMaximumDimension: CGFloat = 220
    static let selectedReflowFraction: CGFloat = 0.50
    static let neighborReflowFraction: CGFloat = 0.25
    static let reflowMinimumNeighborFraction: CGFloat = 0.20
    static let reflowMinimumTextSize: CGFloat = 17
    static let reflowSelectionEdgeWidth: CGFloat = 2
    static let markerLabelSpacing: CGFloat = 8
    static let markerLabelInset: CGFloat = 12
    static let posterCropOffset: CGFloat = 0
    static let registrationMarkLength: CGFloat = 18
    static let filmEdgeWidth: CGFloat = 6
    static let filmEdgeMarkLength: CGFloat = 16
    static let tallyDimOpacity: Double = 0.46
    static let tallyPulseMinimumOpacity: Double = 0.42
}

/// Text rendered by the live Camera Coach command band. The metric owner
/// measures this exact content so the visible band and its geometry consumers
/// reserve the same height for localized wrapping.
struct SETCameraCoachRailContent: Equatable, Sendable {
    let observation: String
    let actionInstruction: String?
    let explanation: String?
    let whyLabel: String?
    let continueLabel: String?

    init(
        observation: String,
        actionInstruction: String? = nil,
        explanation: String? = nil,
        whyLabel: String? = nil,
        continueLabel: String? = nil
    ) {
        self.observation = observation
        self.actionInstruction = actionInstruction
        self.explanation = explanation
        self.whyLabel = whyLabel
        self.continueLabel = continueLabel
    }
}

/// Geometry shared by the production Camera Coach monitor. Keeping these
/// values with the other SET tokens prevents the live surface from growing
/// unexplained layout literals while still resolving from the actual canvas.
enum SETCameraCoachMetric {
    static let headerHeight: CGFloat = 56
    static let commandBandMinimumHeight: CGFloat = 92
    static let commandBandMaximumHeight: CGFloat = 164
    static let commandHorizontalInset: CGFloat = 16
    static let commandVerticalInset: CGFloat = 12
    static let markerWidth: CGFloat = 180
    static let markerHeight: CGFloat = 132
    static let markerTargetInset: CGFloat = 20
    static let pausePreviewFraction: CGFloat = 0.72
    static let pauseHeaderOpacity: Double = 0.62
    static let pauseBandMinimumHeight: CGFloat = 208
    static let pauseBandMaximumHeight: CGFloat = 300
    static let pauseMarkerWidth: CGFloat = 160
    static let pauseMarkerHeight: CGFloat = 190
    static let compactControlSpacing: CGFloat = 8

    // Camera Coach keeps the controls and the live HUD in separate rows. These
    // typed geometry tokens prevent the bottom command rail from expanding to
    // the whole canvas and keep the camera frame as the visual hero.
    static let topControlRowHeight: CGFloat = 60
    static let topControlTopInset: CGFloat = 8
    static let headerControlHorizontalInset: CGFloat =
        SETComponentMetric.minimumHitTarget + SETSpacing.x3 + SETSpacing.x4

    static let liveRailPortraitHeight: CGFloat = 96
    static let liveRailLandscapeHeight: CGFloat = 84
    static let liveRailPortraitAccessibilityHeight: CGFloat = 120
    static let liveRailLandscapeAccessibilityHeight: CGFloat = 108
    static let liveRailExpandedPortraitHeight: CGFloat = 132
    static let liveRailExpandedLandscapeHeight: CGFloat = 116
    static let liveRailPortraitWidthFraction: CGFloat = 0.88
    static let liveRailLandscapeWidthFraction: CGFloat = 0.48
    static let liveRailAccessibilityPortraitWidthFraction: CGFloat = 0.94
    static let liveRailAccessibilityLandscapeWidthFraction: CGFloat = 0.66
    static let liveRailMaximumWidth: CGFloat = 420
    static let liveRailHorizontalInset: CGFloat = SETSpacing.x4
    static let liveRailBottomInset: CGFloat = SETSpacing.x4
    static let liveRailMarkerClearance: CGFloat = SETSpacing.x3
    static let lensRailTopInset: CGFloat =
        topControlRowHeight + headerHeight + SETSpacing.x2
    static let lensStatusWidth: CGFloat = 288
    static let lensStatusHeight: CGFloat = 56
    static let pauseHeaderHeight: CGFloat = 72

    static func lensRailControlSize(for lensCount: Int) -> CGSize {
        let count = max(1, lensCount)
        let width = CGFloat(count) * SETComponentMetric.minimumHitTarget
            + CGFloat(count + 1) * SETSpacing.x1
            + SETSpacing.x2
        return CGSize(width: width, height: SETComponentMetric.minimumHitTarget + SETSpacing.x2)
    }

    static func liveRailHeight(
        canvasSize: CGSize,
        isAccessibilityType: Bool,
        isExpanded: Bool,
        content: SETCameraCoachRailContent? = nil
    ) -> CGFloat {
        let isLandscape = canvasSize.width > canvasSize.height
        let stableHeight: CGFloat = if isLandscape {
            isAccessibilityType ? liveRailLandscapeAccessibilityHeight : liveRailLandscapeHeight
        } else {
            isAccessibilityType ? liveRailPortraitAccessibilityHeight : liveRailPortraitHeight
        }

        let expandedHeight: CGFloat = if isLandscape {
            liveRailExpandedLandscapeHeight
        } else {
            liveRailExpandedPortraitHeight
        }
        let profileHeight = isExpanded ? max(stableHeight, expandedHeight) : stableHeight
        guard let content else { return profileHeight }
        return max(
            profileHeight,
            measuredLiveRailHeight(
                content: content,
                canvasSize: canvasSize,
                isAccessibilityType: isAccessibilityType
            )
        )
    }

    static func liveRailWidth(canvasSize: CGSize, isAccessibilityType: Bool) -> CGFloat {
        let isLandscape = canvasSize.width > canvasSize.height
        let fraction: CGFloat = if isLandscape {
            isAccessibilityType ? liveRailAccessibilityLandscapeWidthFraction : liveRailLandscapeWidthFraction
        } else {
            isAccessibilityType ? liveRailAccessibilityPortraitWidthFraction : liveRailPortraitWidthFraction
        }
        return min(liveRailMaximumWidth, canvasSize.width * fraction)
    }

    private static func measuredLiveRailHeight(
        content: SETCameraCoachRailContent,
        canvasSize: CGSize,
        isAccessibilityType: Bool
    ) -> CGFloat {
        let railWidth = liveRailWidth(
            canvasSize: canvasSize,
            isAccessibilityType: isAccessibilityType
        )
        let innerWidth = max(1, railWidth - commandHorizontalInset * 2)
        let bodyFont = SETTypography.uiFont(.hudMono, size: SETTypographySize.body)
        let commandFont = weightedFont(
            SETTypography.uiFont(.display, size: SETTypographySize.command),
            traits: .traitBold
        )
        let labelFont = weightedFont(
            SETTypography.uiFont(.hudMono, size: SETTypographySize.label),
            traits: .traitBold
        )

        let controlWidths = [content.whyLabel, content.continueLabel]
            .compactMap { $0 }
            .map { max(SETComponentMetric.minimumHitTarget, measuredTextWidth($0, font: labelFont)) }
        let commandTextWidth = max(
            1,
            innerWidth
                - controlWidths.reduce(0, +)
                - CGFloat(controlWidths.count) * SETSpacing.x3
        )

        let observationHeight = measuredTextHeight(
            content.observation,
            font: bodyFont,
            width: commandTextWidth
        )
        let actionHeight = measuredTextHeight(
            content.actionInstruction,
            font: commandFont,
            width: commandTextWidth,
            maximumLines: 2
        )

        let commandStackHeight = observationHeight
            + (actionHeight > 0 ? SETSpacing.x1 + actionHeight : 0)
        let controlsHeight = controlWidths.isEmpty ? 0 : SETComponentMetric.minimumHitTarget
        let commandContentHeight = max(commandStackHeight, controlsHeight)

        var totalHeight = commandContentHeight + commandVerticalInset * 2
        let explanationHeight = measuredTextHeight(
            content.explanation,
            font: UIFont.preferredFont(forTextStyle: .body),
            width: innerWidth
        )
        if explanationHeight > 0 {
            totalHeight += SETSpacing.x2 + explanationHeight
        }
        return ceil(totalHeight)
    }

    private static func measuredTextHeight(
        _ text: String?,
        font: UIFont,
        width: CGFloat,
        maximumLines: Int? = nil
    ) -> CGFloat {
        guard let text, !text.isEmpty, width > 0 else { return 0 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let measured = max(font.lineHeight, ceil(bounds.height))
        guard let maximumLines else { return measured }
        return min(measured, ceil(font.lineHeight * CGFloat(maximumLines)))
    }

    private static func measuredTextWidth(_ text: String, font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func weightedFont(
        _ font: UIFont,
        traits: UIFontDescriptor.SymbolicTraits
    ) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

struct SETSafeInsets: Equatable, Sendable {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat

    static let zero = Self(top: 0, leading: 0, bottom: 0, trailing: 0)
}

enum SETSubjectSafeControlEdge: Equatable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

/// Pure placement resolver for secondary camera controls. It scores the
/// compact control footprint against transformed subject/face boxes and the
/// command rail, then chooses the least-overlapping safe edge. Keeping this
/// independent of SwiftUI makes portrait/landscape behaviour deterministic.
struct SETSubjectSafeControlPlacement: Equatable, Sendable {
    let edge: SETSubjectSafeControlEdge
    let frame: CGRect

    static func resolve(
        canvasSize: CGSize,
        controlSize: CGSize,
        safeInsets: SETSafeInsets = .zero,
        subjectRegions: [CGRect],
        commandRailFrame: CGRect? = nil,
        reservedFrames: [CGRect] = []
    ) -> Self? {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let safe = CGRect(
            x: min(max(0, safeInsets.leading), canvas.width),
            y: min(max(0, safeInsets.top), canvas.height),
            width: max(0, canvas.width - min(max(0, safeInsets.leading), canvas.width)
                - min(max(0, safeInsets.trailing), canvas.width)),
            height: max(0, canvas.height - min(max(0, safeInsets.top), canvas.height)
                - min(max(0, safeInsets.bottom), canvas.height))
        )
        let width = min(max(0, controlSize.width), safe.width)
        let height = min(max(0, controlSize.height), safe.height)
        guard width > 0, height > 0 else { return nil }
        let rail = commandRailFrame.map { $0.intersection(canvas) }
        let candidates: [(SETSubjectSafeControlEdge, CGRect)] = [
            (.topLeading, CGRect(x: safe.minX, y: safe.minY, width: width, height: height)),
            (.topTrailing, CGRect(x: safe.maxX - width, y: safe.minY, width: width, height: height)),
            (.bottomLeading, CGRect(x: safe.minX, y: safe.maxY - height, width: width, height: height)),
            (.bottomTrailing, CGRect(x: safe.maxX - width, y: safe.maxY - height, width: width, height: height))
        ]

        let protectedFrames = subjectRegions + reservedFrames + (rail.map { [$0] } ?? [])
        let ranked = candidates.enumerated().compactMap { index, candidate -> (score: CGFloat, index: Int, edge: SETSubjectSafeControlEdge, frame: CGRect)? in
            let overlap = protectedFrames.reduce(CGFloat.zero) { partial, region in
                partial + candidate.1.intersection(region).area
            }
            // Secondary controls disappear instead of covering a detected
            // face/subject, the command rail, or another reserved control.
            guard overlap <= 0.001 else { return nil }
            let edgeBias: CGFloat = (candidate.0 == .topLeading || candidate.0 == .topTrailing) ? 0 : 0.01
            let score = overlap + edgeBias
            return (score: score, index: index, edge: candidate.0, frame: candidate.1)
        }

        guard let winner = ranked.min(by: {
            if abs($0.score - $1.score) > 0.001 { return $0.score < $1.score }
            return $0.index < $1.index
        }) else { return nil }
        return Self(edge: winner.edge, frame: winner.frame)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

/// Maps a Vision lower-left region onto the exact oriented image that the
/// pause review displays with `scaledToFill`. Vision receives the capture
/// orientation before producing its normalized boxes, so orientation changes
/// the accepted image dimensions here; it is not applied a second time to the
/// region. Mirroring is opt-in and must only be enabled when the accepted
/// display is actually mirrored.
struct SETAcceptedFrameRegionMapper: Equatable, Sendable {
    static func map(
        _ normalizedRegion: NormalizedRect,
        sourcePixelSize: CGSize,
        orientation: CGImagePropertyOrientation,
        canvasSize: CGSize,
        isMirrored: Bool = false
    ) -> CGRect? {
        guard sourcePixelSize.width > 0,
              sourcePixelSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0,
              !normalizedRegion.isDegenerate else {
            return nil
        }

        let sourceBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let normalizedBounds = CGRect(
            x: CGFloat(normalizedRegion.x),
            y: CGFloat(normalizedRegion.y),
            width: CGFloat(normalizedRegion.width),
            height: CGFloat(normalizedRegion.height)
        ).intersection(sourceBounds)
        guard !normalizedBounds.isNull, !normalizedBounds.isEmpty else { return nil }

        let orientedSize = orientedPixelSize(sourcePixelSize, orientation: orientation)
        let scale = max(canvasSize.width / orientedSize.width,
                        canvasSize.height / orientedSize.height)
        guard scale.isFinite, scale > 0 else { return nil }

        let displayedSize = CGSize(width: orientedSize.width * scale,
                                    height: orientedSize.height * scale)
        let imageOrigin = CGPoint(
            x: (canvasSize.width - displayedSize.width) * 0.5,
            y: (canvasSize.height - displayedSize.height) * 0.5
        )

        var x = normalizedBounds.minX
        if isMirrored {
            x = 1 - normalizedBounds.maxX
        }
        let topY = 1 - normalizedBounds.maxY
        let mapped = CGRect(
            x: imageOrigin.x + x * displayedSize.width,
            y: imageOrigin.y + topY * displayedSize.height,
            width: normalizedBounds.width * displayedSize.width,
            height: normalizedBounds.height * displayedSize.height
        )
        let clipped = mapped.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return clipped
    }

    static func orientedPixelSize(
        _ sourcePixelSize: CGSize,
        orientation: CGImagePropertyOrientation
    ) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: sourcePixelSize.height, height: sourcePixelSize.width)
        default:
            return sourcePixelSize
        }
    }
}

struct SETPauseCutMarkGeometry: Equatable, Sendable {
    let lineCount: Int
    let lineLength: CGFloat
    let labelGap: CGFloat

    static let singleLine = Self(
        lineCount: 1,
        lineLength: SETComponentMetric.filmEdgeMarkLength,
        labelGap: SETSpacing.x2
    )
}

/// Typed geometry for the single corrective command marker. The tail is
/// anchored to the command rail; the arrowhead terminates on the nearest
/// boundary of the requested target region, never at its centre. A straight
/// (collinear quadratic) leader is the safe default: it can be curved by a
/// future owner only when the curve remains outside the target interior.
struct SETCorrectiveArrowGeometry: Equatable {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    let headLeft: CGPoint
    let headRight: CGPoint
    let targetRect: CGRect
    let safeRect: CGRect
    let commandRailFrame: CGRect

    static let headLength: CGFloat = 16
    static let headWidth: CGFloat = 8

    static func resolve(
        canvasSize: CGSize,
        targetRegion: NormalizedRect,
        commandRailFrame: CGRect,
        safeInset: CGFloat = SETCameraCoachMetric.markerTargetInset
    ) -> Self {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let targetRect = CGRect(
            x: CGFloat(targetRegion.x) * canvas.width,
            y: CGFloat(targetRegion.y) * canvas.height,
            width: CGFloat(targetRegion.width) * canvas.width,
            height: CGFloat(targetRegion.height) * canvas.height
        )
        return resolve(
            canvasSize: canvasSize,
            targetRect: targetRect,
            commandRailFrame: commandRailFrame,
            safeInset: safeInset
        )
    }

    /// Runtime uses this overload after `AVCaptureVideoPreviewLayer` has
    /// mapped the validated metadata target into view space. No normalized
    /// fallback is invented here: an empty target is rejected by the caller.
    static func resolve(
        canvasSize: CGSize,
        targetRect: CGRect,
        commandRailFrame: CGRect,
        safeInset: CGFloat = SETCameraCoachMetric.markerTargetInset
    ) -> Self {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let safe = CGRect(
            x: min(max(0, safeInset), canvas.width * 0.5),
            y: min(max(0, safeInset), canvas.height * 0.5),
            width: max(0, canvas.width - min(max(0, safeInset), canvas.width * 0.5) * 2),
            height: max(0, canvas.height - min(max(0, safeInset), canvas.height * 0.5) * 2)
        )
        let clampedRail = commandRailFrame.isNull
            ? .zero
            : commandRailFrame.intersection(canvas)
        let target = targetRect
            .intersection(canvas)
            .intersection(safe)
        let usableTarget = target.isNull || target.isEmpty ? safe : target

        var anchor = CGPoint(
            x: clampedRail.midX,
            y: clampedRail.minY
        )
        anchor = clamp(anchor, to: safe)

        // A malformed/overlapping target must not put the leader's tail inside
        // the subject. Move only the tail to the nearest safe point above or
        // beside that target while retaining the rail's x/y direction.
        if usableTarget.contains(anchor) {
            let candidates = [
                CGPoint(x: usableTarget.midX, y: usableTarget.minY - safeInset),
                CGPoint(x: usableTarget.minX - safeInset, y: usableTarget.midY),
                CGPoint(x: usableTarget.maxX + safeInset, y: usableTarget.midY)
            ]
            anchor = candidates
                .map { clamp($0, to: safe) }
                .min { $0.distance(to: CGPoint(x: clampedRail.midX, y: clampedRail.minY))
                    < $1.distance(to: CGPoint(x: clampedRail.midX, y: clampedRail.minY)) }
                ?? anchor
        }

        let endpoint = nearestBoundaryPoint(from: anchor, in: usableTarget)
        let direction = CGVector(dx: endpoint.x - anchor.x, dy: endpoint.y - anchor.y)
        let length = max(1, hypot(direction.dx, direction.dy))
        let unit = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)
        let base = CGPoint(
            x: endpoint.x - unit.dx * min(headLength, length * 0.35),
            y: endpoint.y - unit.dy * min(headLength, length * 0.35)
        )
        let left = clamp(CGPoint(
            x: base.x + perpendicular.dx * headWidth,
            y: base.y + perpendicular.dy * headWidth
        ), to: safe)
        let right = clamp(CGPoint(
            x: base.x - perpendicular.dx * headWidth,
            y: base.y - perpendicular.dy * headWidth
        ), to: safe)

        return Self(
            start: anchor,
            control: CGPoint(x: (anchor.x + endpoint.x) * 0.5,
                             y: (anchor.y + endpoint.y) * 0.5),
            end: endpoint,
            headLeft: left,
            headRight: right,
            targetRect: usableTarget,
            safeRect: safe,
            commandRailFrame: clampedRail
        )
    }

    static func resolveValidated(
        canvasSize: CGSize,
        targetRect: CGRect,
        commandRailFrame: CGRect,
        safeInset: CGFloat = SETCameraCoachMetric.markerTargetInset
    ) -> Self? {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let inset = min(max(0, safeInset), min(canvas.width, canvas.height) * 0.5)
        let safe = canvas.insetBy(dx: inset, dy: inset)
        let clipped = targetRect.intersection(canvas).intersection(safe)
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return resolve(
            canvasSize: canvasSize,
            targetRect: clipped,
            commandRailFrame: commandRailFrame,
            safeInset: safeInset
        )
    }

    /// Samples the stroke before its arrowhead. This gives deterministic tests
    /// and diagnostics a proof that the leader does not enter the target.
    func strokeAvoidsTarget(interiorInset: CGFloat = 0.5, samples: Int = 32) -> Bool {
        guard samples > 0 else { return true }
        let protectedTarget = targetRect.insetBy(dx: interiorInset, dy: interiorInset)
        for index in 0..<samples {
            let t = CGFloat(index) / CGFloat(samples)
            if protectedTarget.contains(point(at: t)) { return false }
        }
        return true
    }

    func point(at progress: CGFloat) -> CGPoint {
        let t = min(1, max(0, progress))
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    private static func nearestBoundaryPoint(from point: CGPoint, in rect: CGRect) -> CGPoint {
        guard !rect.isEmpty else { return point }
        if rect.contains(point) {
            let distances: [(CGFloat, CGPoint)] = [
                (abs(point.x - rect.minX), CGPoint(x: rect.minX, y: point.y)),
                (abs(rect.maxX - point.x), CGPoint(x: rect.maxX, y: point.y)),
                (abs(point.y - rect.minY), CGPoint(x: point.x, y: rect.minY)),
                (abs(rect.maxY - point.y), CGPoint(x: point.x, y: rect.maxY))
            ]
            return distances.min { $0.0 < $1.0 }?.1 ?? point
        }

        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        return CGPoint(x: x, y: y)
    }

    private static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

enum SETTypographySize {
    static let poster: CGFloat = 64
    static let displayLarge: CGFloat = 48
    static let displayMedium: CGFloat = 34
    static let title: CGFloat = 22
    /// Command labels use the title size at the default Dynamic Type category.
    /// The upper bound keeps actions editorial without allowing them to become
    /// a second poster title at accessibility sizes.
    static let command: CGFloat = title
    static let commandMaximum: CGFloat = displayMedium
    static let body: CGFloat = 17
    static let label: CGFloat = 13
    static let micro: CGFloat = 11
}

enum SETLayoutProfile: Equatable, Sendable {
    case narrow
    case standard
    case wide

    static func resolve(container: CGSize, accessibilityType: Bool = false) -> SETLayoutProfile {
        if accessibilityType || min(container.width, container.height) < 390 {
            return .narrow
        }
        if container.width >= 900 {
            return .wide
        }
        return .standard
    }
}

/// Entry's composition is resolved from the actual available geometry.  The
/// compact-height flag lets the split composition tighten its rhythm without
/// turning landscape into a rotated portrait stack.
enum SETEntryLayoutMode: Equatable, Sendable {
    case stacked
    case split
}

struct SETEntryLayout: Equatable, Sendable {
    let mode: SETEntryLayoutMode
    let isCompactHeight: Bool
    let isAccessibilityType: Bool

    var isSplit: Bool { mode == .split }
    var contentPadding: CGFloat {
        isCompactHeight ? SETSpacing.x4 : SETSpacing.x6
    }
    var sectionSpacing: CGFloat {
        isCompactHeight ? SETSpacing.x3 : SETSpacing.x4
    }
    var columnSpacing: CGFloat {
        isCompactHeight ? SETSpacing.x4 : SETSpacing.x8
    }
    var landscapeRailFraction: CGFloat {
        isAccessibilityType
            ? SETComponentMetric.entryLandscapeAccessibilityRailFraction
            : SETComponentMetric.entryLandscapeRailFraction
    }

    static func resolve(container: CGSize, accessibilityType: Bool = false) -> Self {
        let hasArea = container.width > 0 && container.height > 0
        let isLandscape = hasArea && container.width > container.height
        return Self(
            mode: isLandscape ? .split : .stacked,
            isCompactHeight: container.height < SETComponentMetric.entryCompactHeightThreshold,
            isAccessibilityType: accessibilityType
        )
    }
}
