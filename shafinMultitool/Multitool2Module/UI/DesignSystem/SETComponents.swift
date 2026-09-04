import SwiftUI
import UIKit

enum SETBundledImage {
    static func uiImage(named name: String, in bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    static func image(named name: String, in bundle: Bundle = .main) -> Image {
        guard let uiImage = uiImage(named: name, in: bundle) else {
            return Image(name)
        }
        return Image(uiImage: uiImage)
    }
}

enum SETRegistrationCorner: String, CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case all
}

struct SETRegistrationMarks: View {
    var color: Color = .setOrange
    /// The gallery and live-monitor fixtures keep the four-mark default. Entry
    /// chooses one corner so registration reads as punctuation rather than a
    /// wireframe container.
    var corner: SETRegistrationCorner = .all

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let length = min(
                    SETComponentMetric.registrationMarkLength,
                    min(proxy.size.width, proxy.size.height) / 4
                )
                switch corner {
                case .topLeading:
                    addTopLeading(to: &path, width: proxy.size.width, length: length)
                case .topTrailing:
                    addTopTrailing(to: &path, width: proxy.size.width, length: length)
                case .bottomLeading:
                    addBottomLeading(to: &path, width: proxy.size.width, height: proxy.size.height, length: length)
                case .bottomTrailing:
                    addBottomTrailing(to: &path, width: proxy.size.width, height: proxy.size.height, length: length)
                case .all:
                    addTopLeading(to: &path, width: proxy.size.width, length: length)
                    addTopTrailing(to: &path, width: proxy.size.width, length: length)
                    addBottomLeading(to: &path, width: proxy.size.width, height: proxy.size.height, length: length)
                    addBottomTrailing(to: &path, width: proxy.size.width, height: proxy.size.height, length: length)
                }
            }
            .stroke(color, lineWidth: SETStroke.standard)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func addTopLeading(to path: inout Path, width: CGFloat, length: CGFloat) {
        path.move(to: CGPoint(x: 0, y: length))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: length, y: 0))
    }

    private func addTopTrailing(to path: inout Path, width: CGFloat, length: CGFloat) {
        path.move(to: CGPoint(x: width - length, y: 0))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: length))
    }

    private func addBottomLeading(to path: inout Path, width: CGFloat, height: CGFloat, length: CGFloat) {
        path.move(to: CGPoint(x: length, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: height - length))
    }

    private func addBottomTrailing(to path: inout Path, width: CGFloat, height: CGFloat, length: CGFloat) {
        path.move(to: CGPoint(x: width, y: height - length))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: width - length, y: height))
    }
}

enum SETWordmarkLayout: Sendable {
    case horizontal
    case stacked
}

struct SETWordmark: View {
    let layout: SETWordmarkLayout
    var color: Color = .setTextPrimary

    var body: some View {
        Group {
            switch layout {
            case .horizontal:
                Text("SHAFIN MULTITOOL")
                    .lineLimit(1)
            case .stacked:
                VStack(alignment: .leading, spacing: -SETSpacing.x2) {
                    Text("SHAFIN")
                    Text("MULTITOOL")
                }
            }
        }
        .font(SETTypography.font(.wordmark, size: SETTypographySize.displayMedium))
        .tracking(-0.34)
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SHAFIN MULTITOOL")
    }
}

struct SETPosterTitle: View {
    let key: SETCopyKey
    var color: Color = .setTextPrimary

    var body: some View {
        Text(key.localizedTextKey)
            .font(SETTypography.font(.display, size: SETTypographySize.displayLarge))
            .fontWeight(.bold)
            .textCase(.uppercase)
            .minimumScaleFactor(0.66)
            .foregroundStyle(color)
            .accessibilityLabel(Text(key.localizedTextKey))
    }
}

/// Shared command/action label. The Oswald display role keeps actions in the
/// SET OS editorial register while the scaled size remains bounded for AX text
/// sizes, so a command cannot grow into a second poster title.
struct SETCommandLabel: View {
    let key: SETCopyKey
    var color: Color = .setTextPrimary

    @ScaledMetric(relativeTo: .headline)
    private var scaledFontSize: CGFloat = SETTypographySize.command

    private var fontSize: CGFloat {
        min(
            max(scaledFontSize, SETTypographySize.command),
            SETTypographySize.commandMaximum
        )
    }

    var body: some View {
        Text(key.localizedTextKey)
            .font(SETTypography.font(.display, size: fontSize))
            .fontWeight(.bold)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(color)
    }
}

/// Flat digital action treatment with a dark surface and an optional orange
/// focus edge.
struct SETDigitalAction: View {
    let title: SETCopyKey
    var helper: SETCopyKey?
    /// Keeps the shared action backward-compatible while allowing a focused
    /// field to own the single cinematic accent in a stable state.
    var showsAccentEdge = true
    var action: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        Button(action: action) {
            commandContent
            .foregroundStyle(.setTextPrimary)
            .padding(.horizontal, SETSpacing.x4)
            .frame(minHeight: max(SETComponentMetric.minimumHitTarget, SETComponentMetric.entryActionHeight))
            .background(.setSurfaceSolid)
            .overlay(alignment: .leading) {
                if showsAccentEdge {
                    Rectangle()
                        .fill(.setOrange)
                        .frame(width: SETStroke.standard)
                }
            }
            .overlay {
                Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var commandContent: some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: SETSpacing.x2) {
                SETCommandLabel(key: title)

                if let helper {
                    helperLabel(helper, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: SETSpacing.x3) {
                SETCommandLabel(key: title)

                if let helper {
                    Spacer(minLength: SETSpacing.x2)
                    helperLabel(helper, alignment: .trailing)
                }
            }
        }
    }

    private func helperLabel(_ helper: SETCopyKey, alignment: TextAlignment) -> some View {
        Text(helper.localizedTextKey)
            .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
            .foregroundStyle(.setTextSecondary)
            .tracking(0.25)
            .multilineTextAlignment(alignment)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shared flat pause-review command band. The camera and generator surfaces
/// supply their own copy and action, while this component owns the common SET
/// ink/surface treatment and loading-line behavior.
struct SETPauseReviewBand: View {
    let title: String
    let detail: String?
    let isLoading: Bool
    let actionTitle: SETCopyKey
    let loadingEventID: String
    let eventLedger: SETMotionEventLedger?
    let reduceMotion: Bool
    let actionAccessibilityIdentifier: String?
    let onAction: () -> Void

    @State private var progress: CGFloat = 0
    @State private var loadingOpacity = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            HStack(alignment: .firstTextBaseline, spacing: SETSpacing.x3) {
                Text(title)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.body))
                    .fontWeight(.bold)
                    .foregroundStyle(.setTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: SETSpacing.x2)
            }

            if let detail {
                Text(detail)
                    .font(SETTypography.uiBodyFont())
                    .foregroundStyle(.setTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            if isLoading {
                Rectangle()
                    .fill(.setOrange)
                    .frame(width: max(SETSpacing.x1, SETCameraCoachMetric.commandBandMaximumHeight * progress),
                           height: SETStroke.standard,
                           alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(loadingOpacity)
                    .accessibilityHidden(true)
            }

            if let actionAccessibilityIdentifier {
                SETDigitalAction(
                    title: actionTitle,
                    action: onAction
                )
                .accessibilityIdentifier(actionAccessibilityIdentifier)
            } else {
                SETDigitalAction(
                    title: actionTitle,
                    action: onAction
                )
            }
        }
        .padding(SETSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.setInk)
        .overlay(alignment: .top) {
            Rectangle().fill(.setHairline).frame(height: SETStroke.hairline)
        }
        .task(id: loadingEventID) {
            progress = isLoading ? 0 : 1
            loadingOpacity = isLoading ? 1 : 0
            guard isLoading else { return }

            guard eventLedger?.consume(loadingEventID) ?? true else {
                progress = 1
                loadingOpacity = 1
                return
            }

            guard !reduceMotion else {
                progress = 1
                loadingOpacity = 0
                withAnimation(.easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)) {
                    loadingOpacity = 1
                }
                return
            }

            loadingOpacity = 1
            withAnimation(.linear(duration: SETMotion.markerDrawDuration)) {
                progress = 1
            }
        }
    }
}

enum SETTallyMode: Sendable {
    case live
    case standby
    case eco

    var key: SETCopyKey {
        switch self {
        case .live: .hudLive
        case .standby: .hudStandby
        case .eco: .hudEco
        }
    }
}

struct SETTallyBadge: View {
    let mode: SETTallyMode
    var pulses = false
    var dimmed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride
    @State private var pulseVisible = true

    private var isMotionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    var body: some View {
        HStack(spacing: SETSpacing.x2) {
            if mode == .live {
                Circle()
                    .fill(.setOrange)
                    .frame(width: SETSpacing.x2, height: SETSpacing.x2)
                    .opacity(
                        dimmed
                            ? SETComponentMetric.tallyDimOpacity
                            : (pulseVisible ? 1 : SETComponentMetric.tallyPulseMinimumOpacity)
                    )
                    .accessibilityHidden(true)
            }

            Text(mode.key.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .fontWeight(.semibold)
                .monospacedDigit()
                .tracking(0.65)
        }
        .foregroundStyle(dimmed ? .setTextSecondary : .setTextPrimary)
        .onAppear {
            guard pulses, !isMotionReduced else {
                pulseVisible = true
                return
            }
            withAnimation(.easeInOut(duration: SETMotion.tallyPulseDuration).repeatForever()) {
                pulseVisible = false
            }
        }
        .onChange(of: isMotionReduced) { _, isReduced in
            if isReduced { pulseVisible = true }
        }
    }
}

struct SETTimecodeView: View {
    let value: String
    var showsFrames = true

    var visibleValue: String {
        guard !showsFrames else { return value }
        return String(value.prefix(8))
    }

    var body: some View {
        Text(visibleValue)
            .font(SETTypography.font(.hudMono, size: SETTypographySize.body))
            .monospacedDigit()
            .tracking(0.85)
            .foregroundStyle(.setTextPrimary)
            .accessibilityLabel(visibleValue)
    }
}

enum SETHUDChipStyle: String, CaseIterable, Sendable {
    case seeking
    case keep
    case corrective
    case fallback
    case explanation
}

/// Compact HUD copy retained for the gallery component catalogue. It is a
/// rectangular digital treatment; fallback uses the warm-white edge required
/// by O-5 rather than the retired yellow token.
struct SETHUDChip: View {
    let style: SETHUDChipStyle
    let title: SETCopyKey
    var action: SETCopyKey?
    var detail: SETCopyKey?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.setReduceTransparencyOverride) private var reduceTransparencyOverride

    private var isTransparencyReduced: Bool {
        reduceTransparencyOverride ?? reduceTransparency
    }

    private var edgeColor: Color {
        switch style {
        case .corrective, .explanation:
            return .setOrange
        case .fallback:
            return .setWarmWhite
        case .seeking, .keep:
            return .setHairline
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(title.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))

            if let action {
                Text(action.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: .bold))
            }

            if let detail, style == .explanation {
                Rectangle()
                    .fill(.setOrange)
                    .frame(height: SETStroke.standard)

                Text(detail.localizedTextKey)
                    .font(SETTypography.uiBodyFont())
                    .foregroundStyle(.setTextSecondary)
            }
        }
        .frame(maxWidth: SETComponentMetric.chipMaxWidth, alignment: .leading)
        .padding(SETSpacing.x4)
        .foregroundStyle(.setTextPrimary)
        .background(isTransparencyReduced ? Color.setSurfaceSolid : Color.setHUDScrim)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(edgeColor)
                .frame(width: SETStroke.standard)
        }
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Marker on glass

/// The only marker semantics permitted by SET OS v2.4. `line` is deliberately
/// a separate kind from `arrow`: it can never grow an arrowhead by accident.
enum SETMarkerKind: String, CaseIterable, Sendable {
    case arrow
    case line
    case outline
    case underline
    case bracket

    var hasArrowhead: Bool { self == .arrow }
}

typealias SETMarkerSemantic = SETMarkerKind
typealias SETGlassMarkKind = SETMarkerKind
typealias GlassMarkKind = SETMarkerKind
typealias SETMarkerPrimitive = SETMarkerKind

extension SETMarkerKind {
    static var movementArrow: Self { .arrow }
    static var horizonLine: Self { .line }
    static var selectionOutline: Self { .outline }
}

enum SETMarkerContract {
    static let requiredKinds = SETMarkerKind.allCases
    static let oneAnnotationPerState = true

    static func hasArrowhead(_ kind: SETMarkerKind) -> Bool {
        kind.hasArrowhead
    }
}

/// Pure vector marker layer. It never owns or exposes semantic copy.
struct GlassMarkGuide: View {
    let kind: SETMarkerKind
    var color: Color = .setOrange
    var drawProgress: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                switch kind {
                case .arrow:
                    let start = CGPoint(x: width * 0.88, y: height * 0.24)
                    let end = CGPoint(x: width * 0.22, y: height * 0.66)
                    let control = CGPoint(x: width * 0.60, y: height * 0.34)
                    let deltaX = end.x - start.x
                    let deltaY = end.y - start.y
                    let vectorLength = max(hypot(deltaX, deltaY), 1)
                    let direction = CGVector(dx: deltaX / vectorLength, dy: deltaY / vectorLength)
                    let perpendicular = CGVector(dx: -direction.dy, dy: direction.dx)
                    let headLength = min(width, height) * 0.20
                    let headWidth = headLength * 0.54
                    let headBase = CGPoint(
                        x: end.x - direction.dx * headLength,
                        y: end.y - direction.dy * headLength
                    )
                    let firstHead = CGPoint(
                        x: headBase.x + perpendicular.dx * headWidth,
                        y: headBase.y + perpendicular.dy * headWidth
                    )
                    let secondHead = CGPoint(
                        x: headBase.x - perpendicular.dx * headWidth,
                        y: headBase.y - perpendicular.dy * headWidth
                    )
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: control)
                    path.move(to: firstHead)
                    path.addLine(to: end)
                    path.addLine(to: secondHead)
                case .line:
                    // Axis/horizon: intentionally no arrowhead.
                    let y = height * 0.52
                    path.move(to: CGPoint(x: width * 0.08, y: y))
                    path.addLine(to: CGPoint(x: width * 0.92, y: y))
                case .outline:
                    path.addRoundedRect(
                        in: CGRect(
                            x: width * 0.08,
                            y: height * 0.10,
                            width: width * 0.84,
                            height: height * 0.80
                        ),
                        cornerSize: CGSize(width: SETRadius.control, height: SETRadius.control)
                    )
                case .underline:
                    // A stable two-beat gesture keeps the CTA underline
                    // hand-drawn without introducing runtime randomness.
                    let start = CGPoint(x: width * 0.08, y: height * 0.74)
                    let middle = CGPoint(x: width * 0.51, y: height * 0.78)
                    let end = CGPoint(x: width * 0.92, y: height * 0.72)
                    path.move(to: start)
                    path.addQuadCurve(
                        to: middle,
                        control: CGPoint(x: width * 0.30, y: height * 0.84)
                    )
                    path.addQuadCurve(
                        to: end,
                        control: CGPoint(x: width * 0.73, y: height * 0.66)
                    )
                case .bracket:
                    let inset = width * 0.10
                    let top = height * 0.18
                    let bottom = height * 0.82
                    let arm = min(width, height) * 0.14
                    path.move(to: CGPoint(x: inset + arm, y: top))
                    path.addLine(to: CGPoint(x: inset, y: top))
                    path.addLine(to: CGPoint(x: inset, y: bottom))
                    path.addLine(to: CGPoint(x: inset + arm, y: bottom))
                    path.move(to: CGPoint(x: width - inset - arm, y: top))
                    path.addLine(to: CGPoint(x: width - inset, y: top))
                    path.addLine(to: CGPoint(x: width - inset, y: bottom))
                    path.addLine(to: CGPoint(x: width - inset - arm, y: bottom))
                }
            }
            .trim(from: 0, to: drawProgress)
            .stroke(color, style: StrokeStyle(lineWidth: SETStroke.guideInner, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

typealias SETGlassMarkGuide = GlassMarkGuide

/// Replays one vector drawing gesture for a state event. Only an actionable
/// annotation moves; the live preview and quiet HUD remain still.
struct SETMarkerDrawGuide: View {
    let kind: SETMarkerKind
    let eventID: String
    var color: Color = .setOrange
    /// Production surfaces pass a session-owned ledger. Gallery callers may
    /// omit it because they are static previews rather than domain owners.
    var eventLedger: SETMotionEventLedger? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride
    @State private var drawProgress: CGFloat = 0
    @State private var markerOpacity = 0.0

    private var isMotionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    var body: some View {
        GlassMarkGuide(kind: kind, color: color, drawProgress: drawProgress)
            .opacity(markerOpacity)
            .task(id: "\(eventID)-\(isMotionReduced)") {
                drawProgress = 0
                markerOpacity = 0
                if let eventLedger, !eventLedger.consume(eventID) {
                    drawProgress = 1
                    markerOpacity = 1
                    return
                }
                guard !isMotionReduced else {
                    drawProgress = 1
                    withAnimation(.easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)) {
                        markerOpacity = 1
                    }
                    return
                }
                markerOpacity = 1
                withAnimation(.linear(duration: SETMotion.markerDrawDuration)) {
                    drawProgress = 1
                }
            }
    }
}

/// Draws the production corrective leader from the command rail to the target
/// boundary. Geometry is resolved by the owner; this view only consumes the
/// one-shot event and performs the prescribed line-then-arrowhead reveal.
struct SETCorrectiveArrowDrawGuide: View {
    let geometry: SETCorrectiveArrowGeometry
    let eventID: String
    var color: Color = .setOrange
    var eventLedger: SETMotionEventLedger? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride
    @State private var drawProgress: CGFloat = 0
    @State private var markerOpacity = 0.0

    private var isMotionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Path { path in
                    path.move(to: geometry.start)
                    path.addQuadCurve(to: geometry.end, control: geometry.control)
                }
                .trim(from: 0, to: min(1, drawProgress / 0.72))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: SETStroke.guideInner,
                                       lineCap: .round,
                                       lineJoin: .round)
                )

                Path { path in
                    path.move(to: geometry.headLeft)
                    path.addLine(to: geometry.end)
                    path.addLine(to: geometry.headRight)
                }
                .trim(from: 0, to: max(0, min(1, (drawProgress - 0.72) / 0.28)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: SETStroke.guideInner,
                                       lineCap: .round,
                                       lineJoin: .round)
                )
            }
            .opacity(markerOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: "\(eventID)-\(isMotionReduced)") {
            drawProgress = 0
            markerOpacity = 0
            if let eventLedger, !eventLedger.consume(eventID) {
                drawProgress = 1
                markerOpacity = 1
                return
            }

            guard !isMotionReduced else {
                drawProgress = 1
                withAnimation(.easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)) {
                    markerOpacity = 1
                }
                return
            }

            markerOpacity = 1
            withAnimation(.linear(duration: SETMotion.markerDrawDuration)) {
                drawProgress = 1
            }
        }
    }
}

/// Owner-led pause cut mark. The event ledger, rather than this view's
/// lifetime, owns the one-shot boundary so rotation/recomposition cannot
/// replay the line, label, or rigid haptic.
struct SETPauseCutMark: View {
    let eventID: String
    let eventLedger: SETMotionEventLedger
    let reduceMotion: Bool
    var controller: SETPauseCutMarkController? = nil
    var onTrigger: (() -> Void)? = nil

    @State private var lineProgress: CGFloat = 1
    @State private var labelOpacity = 1.0

    var body: some View {
        let geometry = SETPauseCutMarkGeometry.singleLine
        HStack(spacing: geometry.labelGap) {
            Rectangle()
                .fill(.setOrange)
                .frame(width: geometry.lineLength * lineProgress,
                       height: SETStroke.standard)
                .accessibilityHidden(true)

            Text(SETCopyKey.pauseCutMark.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .foregroundStyle(.setOrange)
                .opacity(labelOpacity)
        }
        .accessibilityHidden(true)
        .task(id: eventID) {
            lineProgress = 0
            labelOpacity = 0
            let didBegin = if let controller {
                controller.begin(eventID: eventID)
            } else {
                eventLedger.consume(eventID)
            }
            guard didBegin else {
                lineProgress = 1
                labelOpacity = 1
                return
            }

            if controller == nil {
                onTrigger?()
            }
            guard !reduceMotion else {
                lineProgress = 1
                withAnimation(.easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)) {
                    labelOpacity = 1
                }
                return
            }

            withAnimation(.linear(duration: SETMotion.pauseCutLineDuration)) {
                lineProgress = 1
            }
            try? await Task.sleep(nanoseconds: UInt64(SETMotion.pauseCutLineDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: SETMotion.pauseCutLabelDuration)) {
                labelOpacity = 1
            }
        }
    }
}

/// A semantic marker pairs one visible copy string with one hidden vector
/// guide. The copy is the complete accessibility label and remains the source
/// of meaning when Reduce Motion fades the annotation as a whole.
struct SETMarkerAnnotation<Content: View>: View {
    let kind: SETMarkerKind
    let label: SETCopyKey
    var color: Color = .setOrange
    var animationEventID: String?
    let content: () -> Content

    init(
        kind: SETMarkerKind,
        label: SETCopyKey,
        color: Color = .setOrange,
        animationEventID: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.kind = kind
        self.label = label
        self.color = color
        self.animationEventID = animationEventID
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
            Group {
                if let animationEventID {
                    SETMarkerDrawGuide(kind: kind, eventID: animationEventID, color: color)
                } else {
                    GlassMarkGuide(kind: kind, color: color)
                }
            }
            .padding(SETComponentMetric.markerLabelInset)
            Text(label.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .foregroundStyle(color)
                .padding(SETComponentMetric.markerLabelInset)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label.localizedTextKey))
    }
}

// MARK: - Montage reflow

enum SETReflowAxis: Sendable {
    case horizontal
    case vertical
}

struct SETReflowLayout: Equatable, Sendable {
    let count: Int
    let selectedIndex: Int
    let axis: SETReflowAxis

    init(count: Int, selectedIndex: Int, axis: SETReflowAxis = .horizontal) {
        self.count = max(1, count)
        self.selectedIndex = min(max(selectedIndex, 0), max(0, count - 1))
        self.axis = axis
    }

    var selectedFraction: CGFloat {
        count == 1 ? 1 : SETComponentMetric.selectedReflowFraction
    }

    var neighborFraction: CGFloat {
        count == 1 ? 0 : (1 - selectedFraction) / CGFloat(count - 1)
    }

    func fraction(for index: Int) -> CGFloat {
        index == selectedIndex ? selectedFraction : neighborFraction
    }

    var selectedShareIsBounded: Bool {
        SETReflowLayoutContract.selectedFractionRange.contains(selectedFraction)
    }

    var hasSingleCutSeam: Bool { count > 1 }
}

typealias ReflowLayout = SETReflowLayout

enum SETReflowLayoutContract {
    static let selectedFractionRange: ClosedRange<CGFloat> = 0.45...0.60
    static let minimumNeighborHitTarget: CGFloat = SETComponentMetric.minimumHitTarget
    static let maximumPhoneItems = 3
    static let usesEqualCardGrid = false
}

typealias ReflowLayoutContract = SETReflowLayoutContract

enum SETCutSeamAxis: Sendable {
    case horizontal
    case vertical
}

/// One thin orange boundary for one montage reflow. The vector is hidden from
/// hit testing and accessibility; selection remains owned by the caller.
struct CutSeam: View {
    let axis: SETCutSeamAxis

    var body: some View {
        Rectangle()
            .fill(.setOrange)
            .frame(
                maxWidth: axis == .horizontal ? .infinity : SETComponentMetric.reflowSelectionEdgeWidth,
                maxHeight: axis == .vertical ? .infinity : SETComponentMetric.reflowSelectionEdgeWidth
            )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

typealias SETCutSeam = CutSeam

/// Animation-only wrapper for semantic copy and its vector guide. Selection
/// remains owned by the screen; this wrapper only sequences the visual reveal.
struct SETReflowAnnotation<Content: View>: View {
    let isVisible: Bool
    let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride

    private var isMotionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    var body: some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .animation(
                isMotionReduced
                    ? .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)
                    : SETMotion.markerReveal.delay(SETMotion.reflowGeometryDuration),
                value: isVisible
            )
            .accessibilityHidden(!isVisible)
    }
}

struct SETMontageReflow<Item: Identifiable, Content: View>: View where Item.ID: Hashable {
    let items: [Item]
    let selectedID: Item.ID
    let axis: SETReflowAxis
    var onSelect: (Item) -> Void
    let content: (Item, Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride

    init(
        items: [Item],
        selectedID: Item.ID,
        axis: SETReflowAxis = .horizontal,
        onSelect: @escaping (Item) -> Void = { _ in },
        content: @escaping (Item, Bool) -> Content
    ) {
        self.items = items
        self.selectedID = selectedID
        self.axis = axis
        self.onSelect = onSelect
        self.content = content
    }

    private var isMotionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            let selectedIndex = items.firstIndex { $0.id == selectedID } ?? 0
            let layout = SETReflowLayout(count: items.count, selectedIndex: selectedIndex, axis: axis)
            Group {
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        cells(layout: layout, crossLength: proxy.size.height, mainLength: proxy.size.width)
                    }
                } else {
                    VStack(spacing: 0) {
                        cells(layout: layout, crossLength: proxy.size.width, mainLength: proxy.size.height)
                    }
                }
            }
            .animation(
                isMotionReduced
                    ? nil
                    : SETMotion.reflowSpring,
                value: selectedID
            )
        }
    }

    @ViewBuilder
    private func cells(layout: SETReflowLayout, crossLength: CGFloat, mainLength: CGFloat) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let isSelected = index == layout.selectedIndex
            Button {
                onSelect(item)
            } label: {
                Group {
                    if isMotionReduced {
                        ZStack {
                            content(item, isSelected)
                        }
                        // Replacing only the content identity gives Reduce
                        // Motion a crossfade while the cell frame below resolves
                        // directly to its final fraction. No geometry, scale, or
                        // rotation animation is attached to this transition.
                        .id("\(String(describing: item.id))-\(isSelected)")
                        .transition(.opacity)
                        .animation(
                            .easeInOut(duration: SETMotion.reducedMotionCrossfadeDuration),
                            value: isSelected
                        )
                    } else {
                        content(item, isSelected)
                    }
                }
                .frame(
                    maxWidth: axis == .horizontal ? .infinity : crossLength,
                    maxHeight: axis == .vertical ? .infinity : crossLength
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(
                width: axis == .horizontal ? mainLength * layout.fraction(for: index) : crossLength,
                height: axis == .vertical ? mainLength * layout.fraction(for: index) : crossLength
            )
            .frame(minWidth: axis == .horizontal ? SETComponentMetric.minimumHitTarget : nil,
                   minHeight: axis == .vertical ? SETComponentMetric.minimumHitTarget : nil)
            .contentShape(Rectangle())
            .clipped()
            .overlay {
                if isSelected, layout.hasSingleCutSeam {
                    CutSeam(axis: axis == .horizontal ? .vertical : .horizontal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.selectedIndex < layout.count - 1
                            ? (axis == .horizontal ? .trailing : .bottom)
                            : (axis == .horizontal ? .leading : .top))
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

// MARK: - Shared shell components

struct SETFilmEdge: View {
    var axis: SETReflowAxis = .horizontal

    var body: some View {
        Group {
            switch axis {
            case .horizontal:
                HStack(spacing: SETSpacing.x2) {
                    Rectangle().fill(.setOrange).frame(width: SETComponentMetric.filmEdgeWidth, height: SETComponentMetric.filmEdgeMarkLength)
                    Rectangle().fill(.setHairline).frame(height: SETStroke.hairline)
                }
            case .vertical:
                VStack(spacing: SETSpacing.x2) {
                    Rectangle().fill(.setOrange).frame(width: SETComponentMetric.filmEdgeMarkLength, height: SETComponentMetric.filmEdgeWidth)
                    Rectangle().fill(.setHairline).frame(width: SETStroke.hairline)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum SETRollSection: String, CaseIterable, Sendable {
    case camera
    case scenes

    var label: SETCopyKey { self == .camera ? .modeCamera : .modeScenes }
    var accessibilityIdentifier: String {
        self == .camera
            ? "commercial-shell-return-camera"
            : "commercial-shell-open-scenes"
    }

    var accessibilityLabelKey: SETCopyKey {
        self == .camera ? .accessibilityCamera : .accessibilityScenes
    }
}

enum SETABRollCapsuleContract {
    static let title = "A/B ROLL"
    static let segments = SETRollSection.allCases
    static let minimumSegmentSize = CGSize(
        width: SETComponentMetric.capsuleSegmentWidth,
        height: SETComponentMetric.capsuleHeight
    )
    static let usesMaterial = false
    static let usesBlur = false
    static let usesShadow = false

    static let minimumControlSize = CGSize(
        width: minimumSegmentSize.width * CGFloat(segments.count),
        height: minimumSegmentSize.height + SETTypographySize.micro + SETSpacing.x1
    )
}

struct SETABRollCapsule: View {
    let selected: SETRollSection
    var isInteractionLocked = false
    var onSelect: (SETRollSection) -> Void = { _ in }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.setReduceTransparencyOverride) private var reduceTransparencyOverride

    private var isTransparencyReduced: Bool {
        reduceTransparencyOverride ?? reduceTransparency
    }

    var body: some View {
        VStack(spacing: SETSpacing.x1) {
            Text(SETABRollCapsuleContract.title)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                .tracking(0.55)
                .foregroundStyle(.setTextSecondary)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                ForEach(SETABRollCapsuleContract.segments, id: \.rawValue) { section in
                    Button {
                        guard !isInteractionLocked, section != selected else { return }
                        onSelect(section)
                    } label: {
                        HStack(spacing: SETSpacing.x2) {
                            Rectangle()
                                .fill(section == selected ? Color.setOrange : Color.clear)
                                .frame(width: SETSpacing.x1, height: SETSpacing.x3)
                                .accessibilityHidden(true)

                            Text(section.label.localizedTextKey)
                                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                                .fontWeight(.semibold)
                                .tracking(0.65)
                                .foregroundStyle(section == selected ? .setTextPrimary : .setTextSecondary)
                        }
                        .frame(
                            minWidth: SETABRollCapsuleContract.minimumSegmentSize.width,
                            minHeight: SETABRollCapsuleContract.minimumSegmentSize.height
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isInteractionLocked)
                    .accessibilityIdentifier(section.accessibilityIdentifier)
                    .accessibilityLabel(Text(section.accessibilityLabelKey.localizedTextKey))
                    .accessibilityHint(Text(
                        (section == .camera
                            ? SETCopyKey.accessibilityReturnCamera
                            : SETCopyKey.accessibilityOpenScenes)
                            .localizedTextKey
                    ))
                    .accessibilityAddTraits(section == selected ? .isSelected : [])
                }
            }
            .background(isTransparencyReduced ? Color.setSurfaceSolid : Color.setHUDScrim)
            .overlay {
                Capsule().stroke(.setHairline, lineWidth: SETStroke.hairline)
            }
            .clipShape(Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(SETCopyKey.accessibilityCapsule.localizedTextKey))
    }
}

enum SETLeaderPhase: Equatable, Sendable {
    case three
    case two
    case one
    case action

    var display: String? {
        switch self {
        case .three: "3"
        case .two: "2"
        case .one: "1"
        case .action: nil
        }
    }
}

struct SETLeaderCountdown: View {
    let phase: SETLeaderPhase

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(.setTextSecondary, lineWidth: SETStroke.standard)
            Rectangle()
                .fill(.setTextTertiary)
                .frame(width: SETStroke.hairline)
            Rectangle()
                .fill(.setTextTertiary)
                .frame(height: SETStroke.hairline)

            if let display = phase.display {
                Text(display)
                    .font(SETTypography.font(.display, size: SETTypographySize.poster))
                    .fontWeight(.bold)
            } else {
                Text(SETCopyKey.actionMain.localizedTextKey)
                    .font(SETTypography.font(.display, size: SETTypographySize.displayLarge))
                    .fontWeight(.bold)
                    .foregroundStyle(.setInk)
                    .padding(.horizontal, SETSpacing.x3)
                    .background(.setOrange)
            }
        }
        .foregroundStyle(.setTextPrimary)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            phase == .action
                ? Text(SETCopyKey.accessibilityLeader.localizedTextKey)
                : Text(verbatim: phase.display ?? "")
        )
    }
}
