import SwiftUI

/// Draft edits remain local until Apply; Cancel never supplies user intent.
/// The full accepted image is aspect-fit, with the same mapper as pause review.
struct PauseImagePlacementSheet: View {
    let snapshot: LatestFrameEvidenceStore.AcceptedSnapshot
    let candidates: [PauseImagePlacementCandidate]
    let initialGoal: CaptureImagePlacementGoal?
    let initialGoalIsActive: Bool
    let onApply: (CaptureImagePlacementGoal?) -> Bool
    let onClose: () -> Void

    @State private var draft: CaptureImagePlacementGoal?
    @State private var manual = false
    @State private var ambiguous = false
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                control(.cameraPlacementCancel, id: "camera_placement_cancel", action: onClose)
                Spacer(minLength: 0)
                control(.cameraPlacementApply, id: "camera_placement_apply") {
                    if let draft, onApply(draft) { onClose() }
                }
                .disabled(draft?.isValid != true)
            }
            .padding(.horizontal, SETSpacing.x4)
            ScrollView {
                VStack(alignment: .leading, spacing: SETSpacing.x3) {
                    Text(SETCopyKey.cameraPlacementTitle.localizedTextKey)
                        .font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text(SETCopyKey.cameraPlacementScope.localizedTextKey)
                        .fixedSize(horizontal: false, vertical: true)
                    if initialGoal != nil {
                        Text((initialGoalIsActive
                              ? SETCopyKey.cameraPlacementReframe : .cameraPlacementSaved).localizedTextKey)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("camera_placement_saved_goal")
                    }
                    GeometryReader { geometry in
                        imageEditor(canvas: geometry.size)
                    }
                    .frame(height: 260)
                    // Decorative pixels and hidden outlines do not create an
                    // accessibility node. Expose their real editor bounds as
                    // one image; region buttons and coordinate sliders remain
                    // independent, accessible controls outside this element.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SETCopyKey.cameraPlacementTitle.localizedTextKey)
                    .accessibilityHint(SETCopyKey.cameraPlacementScope.localizedTextKey)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("camera_placement_image")

                    HStack(alignment: .top) {
                        Label(SETCopyKey.cameraPlacementObserved.localizedString(locale: locale), systemImage: "square")
                        Label(SETCopyKey.cameraPlacementGoal.localizedString(locale: locale), systemImage: "square.dashed")
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    if ambiguous {
                        Text(SETCopyKey.cameraPlacementAmbiguous.localizedTextKey)
                            .accessibilityIdentifier("camera_placement_ambiguous")
                    }
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                        Button {
                            select(candidate)
                        } label: {
                            HStack {
                                Text(SETCopyKey.cameraPlacementRegion.localizedString(locale: locale) + " \(index + 1)")
                                Spacer()
                                if draft?.entityRef == candidate.id { Image(systemName: "checkmark") }
                            }
                            .frame(minHeight: SETComponentMetric.minimumHitTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft?.entityRef == candidate.id ? .isSelected : [])
                        .accessibilityIdentifier("camera_placement_region_\(index)")
                    }
                    control(.cameraPlacementManual, id: "camera_placement_manual") {
                        manual = true
                        ambiguous = false
                        setManualRegion(draft?.observedRegion ?? .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
                    }
                    if manual {
                        // Accessible alternative to drawing on the image. The
                        // visible draft only becomes intent after explicit Apply.
                        regionSlider(.cameraPlacementLeft, field: 0)
                        regionSlider(.cameraPlacementBottom, field: 1)
                        regionSlider(.cameraPlacementWidth, field: 2)
                        regionSlider(.cameraPlacementHeight, field: 3)
                    }
                    control(.cameraPlacementReset, id: "camera_placement_reset") {
                        if onApply(nil) { onClose() }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(SETSpacing.x4)
                // The outer padding is the available scroll surface when
                // manual drawing owns image drags. Include transparent space
                // in hit testing; keep that gesture outside the image editor.
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("camera_placement_scroll")
        }
        .font(SETTypography.uiBodyFont())
        .foregroundStyle(.setTextPrimary).tint(.setOrange)
        .background(Color.setInk.ignoresSafeArea()).preferredColorScheme(.dark)
        .onAppear {
            draft = initialGoal
            manual = initialGoal?.source == .userRegion
        }
        .accessibilityAction(.escape) { onClose() }
        .transaction {
            if reduceMotionOverride ?? reduceMotion {
                $0.disablesAnimations = true
                $0.animation = nil
            }
        }
    }

    private func control(_ key: SETCopyKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key.localizedTextKey)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: SETComponentMetric.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func imageEditor(canvas: CGSize) -> some View {
        if manual {
            // Drawing is explicit. Only this mode owns drags inside the image;
            // the surrounding padding and controls still scroll normally.
            imageContent(canvas: canvas)
                .highPriorityGesture(DragGesture(minimumDistance: 8).onEnded { value in
                    let rect = CGRect(x: min(value.startLocation.x, value.location.x),
                                      y: min(value.startLocation.y, value.location.y),
                                      width: abs(value.location.x - value.startLocation.x),
                                      height: abs(value.location.y - value.startLocation.y))
                    guard let region = SETAcceptedFrameRegionMapper.unmap(
                        rect, sourcePixelSize: snapshot.sourcePixelSize, orientation: snapshot.orientation,
                        canvasSize: canvas, contentMode: .fit
                    ) else { return }
                    setManualRegion(region)
                })
        } else {
            // A scroll must not be reinterpreted as a tap at its final position.
            imageContent(canvas: canvas)
                .gesture(SpatialTapGesture().onEnded { value in
                    select(at: value.location, canvas: canvas)
                })
        }
    }

    private func imageContent(canvas: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let image = snapshot.displayImage {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable().scaledToFit()
                    .frame(width: canvas.width, height: canvas.height)
            }
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                if let rect = mapped(candidate.region, canvas: canvas) {
                    Rectangle().stroke(.black.opacity(0.9), lineWidth: 3)
                        .overlay {
                            Rectangle().stroke(.white.opacity(0.7), lineWidth: 1)
                        }
                        .overlay(alignment: .topLeading) {
                            Text("\(index + 1)").font(.caption.bold()).padding(3)
                                .background(.black.opacity(0.8))
                        }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .accessibilityHidden(true)
                }
            }
            if let draft, draft.isValid {
                outline(draft.observedRegion, canvas: canvas, destination: false)
                outline(draft.destinationRegion, canvas: canvas, destination: true)
            }
        }
        .frame(width: canvas.width, height: canvas.height).clipped()
        // Manual drawing must not claim the letterboxes before unmap rejects
        // their coordinates. Keep the full canvas coordinate space, but only
        // let the actual oriented image receive selection/drawing gestures.
        .contentShape(imageInteractionShape(canvas: canvas))
    }

    private func imageInteractionShape(canvas: CGSize) -> Path {
        guard let frame = SETAcceptedFrameRegionMapper.imageFrame(
            sourcePixelSize: snapshot.sourcePixelSize, orientation: snapshot.orientation,
            canvasSize: canvas, contentMode: .fit
        ) else { return Path() }
        return Path(frame)
    }

    private func select(at location: CGPoint, canvas: CGSize) {
        // The small square rejects taps in letterboxing without selecting a
        // nearby region. Selection uses only an unambiguous observed region.
        let rect = CGRect(x: location.x - 0.5, y: location.y - 0.5, width: 1, height: 1)
        guard let region = SETAcceptedFrameRegionMapper.unmap(
            rect, sourcePixelSize: snapshot.sourcePixelSize, orientation: snapshot.orientation,
            canvasSize: canvas, contentMode: .fit
        ) else { return }
        if let selected = PauseImagePlacementCandidate.uniqueHit(
            x: region.x + region.width / 2, y: region.y + region.height / 2, in: candidates
        ) { select(selected) } else {
            draft = nil
            ambiguous = true
        }
    }

    @ViewBuilder
    private func outline(_ region: NormalizedRect, canvas: CGSize, destination: Bool) -> some View {
        if let rect = mapped(region, canvas: canvas) {
            Rectangle().stroke(.black.opacity(0.9),
                               style: StrokeStyle(lineWidth: 5, dash: destination ? [6, 4] : []))
                .overlay {
                    Rectangle().stroke(destination ? Color.setOrange : Color.white,
                                       style: StrokeStyle(lineWidth: 3, dash: destination ? [6, 4] : []))
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .accessibilityHidden(true)
        }
    }

    private func mapped(_ region: NormalizedRect, canvas: CGSize) -> CGRect? {
        SETAcceptedFrameRegionMapper.map(region, sourcePixelSize: snapshot.sourcePixelSize,
                                         orientation: snapshot.orientation, canvasSize: canvas, contentMode: .fit)
    }

    private func select(_ candidate: PauseImagePlacementCandidate) {
        draft = .init(snapshotID: snapshot.snapshotID, frameID: snapshot.sourceFrameId,
                      entityRef: candidate.id, observedRegion: candidate.region, source: .observedRegion)
        ambiguous = false
        manual = false
    }

    private func setManualRegion(_ region: NormalizedRect) {
        let ref = draft?.source == .userRegion ? draft!.entityRef : "user-roi-" + UUID().uuidString
        draft = .init(snapshotID: snapshot.snapshotID, frameID: snapshot.sourceFrameId,
                      entityRef: ref, observedRegion: region, source: .userRegion)
    }

    private func regionSlider(_ key: SETCopyKey, field: Int) -> some View {
        VStack(alignment: .leading) {
            Text(key.localizedTextKey)
            Slider(value: Binding(
                get: {
                    guard let r = draft?.observedRegion else { return 0 }
                    return [r.x, r.y, r.width, r.height][field]
                },
                set: { value in
                    guard let r = draft?.observedRegion else { return }
                    var values = [r.x, r.y, r.width, r.height]
                    values[field] = value
                    // All four controls retain the user's exact draft; invalid
                    // combinations disable Apply until adjusted.
                    setManualRegion(.init(x: values[0], y: values[1], width: values[2], height: values[3]))
                }
            ), in: 0...1)
            .accessibilityLabel(Text(key.localizedTextKey))
            .accessibilityIdentifier("camera_placement_coordinate_\(field)")
        }
    }
}
