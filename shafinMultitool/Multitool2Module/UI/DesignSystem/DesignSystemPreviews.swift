import SwiftUI

#if DEBUG
struct DesignSystemPreviews: View {
    @State private var locale: SETGalleryLocale
    @State private var reduceMotion: Bool
    @State private var reduceTransparency: Bool
    @State private var usesXXL: Bool

    private let requestedFixture: SETFixtureDescriptor?

    init(configuration: SETGalleryLaunchConfiguration = SETGalleryLaunchConfiguration()) {
        requestedFixture = SETFixtureCatalog.fixture(id: configuration.fixtureID)
        _locale = State(initialValue: configuration.locale)
        _reduceMotion = State(initialValue: configuration.reduceMotion)
        _reduceTransparency = State(initialValue: configuration.reduceTransparency)
        _usesXXL = State(initialValue: configuration.dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        ZStack {
            Color.setInk.ignoresSafeArea()

            if let requestedFixture {
                SETFixtureCanvas(descriptor: requestedFixture)
                    .padding(requestedFixture.family.usesEdgeToEdgeMonitor ? 0 : SETSpacing.x4)
            } else {
                gallery
            }
        }
        .environment(\.locale, locale.locale)
        .environment(\.setReduceMotionOverride, reduceMotion)
        .environment(\.setReduceTransparencyOverride, reduceTransparency)
        .dynamicTypeSize(usesXXL ? .accessibility2 : .large)
        .preferredColorScheme(.dark)
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SETSpacing.x12) {
                SETGalleryHeader(
                    locale: $locale,
                    reduceMotion: $reduceMotion,
                    reduceTransparency: $reduceTransparency,
                    usesXXL: $usesXXL
                )
                SETFoundationsGallery()
                SETComponentsGallery()
                SETEntryGallery()
                SETCameraGallery()
                SETEditorialGallery()
                SETAccessibilityGallery()
            }
            .padding(SETSpacing.x6)
        }
        .scrollIndicators(.hidden)
    }
}

private extension SETFixtureFamily {
    /// A live monitor is not a poster placed on an ink field. Its camera and
    /// pause states own the complete usable viewport (O-7 / policy v2.4).
    var usesEdgeToEdgeMonitor: Bool {
        self == .camera || self == .pause
    }
}

private struct SETGalleryHeader: View {
    @Binding var locale: SETGalleryLocale
    @Binding var reduceMotion: Bool
    @Binding var reduceTransparency: Bool
    @Binding var usesXXL: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: SETSpacing.x1) {
                    SETWordmark(layout: .horizontal)
                    Text(SETCopyKey.galleryTitle.localizedTextKey)
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                        .tracking(0.65)
                        .foregroundStyle(.setTextSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SETSpacing.x1) {
                    Text(SETCopyKey.galleryPhase.localizedTextKey)
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                        .tracking(0.55)
                        .foregroundStyle(.setOrange)
                    SETFilmEdge()
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: SETSpacing.x2) {
                    galleryToggle(locale.rawValue.uppercased()) { locale = locale == .ru ? .en : .ru }
                    galleryToggle("RM \(reduceMotion ? "ON" : "OFF")") { reduceMotion.toggle() }
                    galleryToggle("RT \(reduceTransparency ? "ON" : "OFF")") { reduceTransparency.toggle() }
                    galleryToggle(usesXXL ? "XXL" : "TYPE") { usesXXL.toggle() }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, SETSpacing.x4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.setOrange).frame(height: SETStroke.standard)
        }
    }

    private func galleryToggle(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                .tracking(0.55)
                .foregroundStyle(.setTextPrimary)
                .frame(minHeight: SETComponentMetric.minimumHitTarget)
                .padding(.horizontal, SETSpacing.x3)
                .background(.setSurfaceSolid)
                .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
        }
        .buttonStyle(.plain)
    }
}

private struct SETGallerySection<Content: View>: View {
    let number: String
    let title: SETCopyKey
    @ViewBuilder let content: Content

    init(number: String, title: SETCopyKey, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x6) {
            HStack(alignment: .firstTextBaseline, spacing: SETSpacing.x3) {
                Text(number)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                    .foregroundStyle(.setOrange)
                Text(title.localizedTextKey)
                    .font(SETTypography.font(.display, size: SETTypographySize.displayMedium))
                    .fontWeight(.bold)
                    .tracking(-0.34)
            }
            content
        }
        .frame(maxWidth: SETComponentMetric.gallerySectionMaxWidth, alignment: .leading)
    }
}

private struct SETFoundationsGallery: View {
    var body: some View {
        SETGallerySection(number: "01", title: .galleryFoundations) {
            ScrollView(.horizontal) {
                HStack(spacing: SETSpacing.x3) {
                    swatch(.setInk, name: "INK", value: "#0B0B0E", text: .setTextPrimary)
                    swatch(.setWarmWhite, name: "WARM WHITE", value: "#F4F1EA", text: .setInk)
                    swatch(.setOrange, name: "SET ORANGE", value: "#FF5A1F", text: .setInk)
                    swatch(.setSurfaceSolid, name: "SOLID", value: "#141419", text: .setTextPrimary)
                }
            }
            .scrollIndicators(.hidden)

            VStack(alignment: .leading, spacing: SETSpacing.x3) {
                Text(SETCopyKey.fixtureFoundationGlyphs.localizedTextKey)
                    .font(SETTypography.font(.display, size: SETTypographySize.displayLarge))
                    .fontWeight(.bold)
                Text(SETCopyKey.fixtureFoundationTake.localizedTextKey)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.body))
                    .tracking(0.85)
                Text(SETCopyKey.fixtureLocation.localizedTextKey)
                    .font(SETTypography.font(.screenplay, size: SETTypographySize.body))
                Text(SETCopyKey.fixtureEditorNote.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: .semibold))
                    .foregroundStyle(.setOrange)
            }
            .foregroundStyle(.setTextPrimary)
        }
    }

    private func swatch(_ color: Color, name: String, value: String, text: Color) -> some View {
        VStack(alignment: .leading, spacing: SETSpacing.x8) {
            Text(name)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .fontWeight(.semibold)
            Text(value)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
        }
        .foregroundStyle(text)
        .padding(SETSpacing.x4)
        .frame(width: SETGalleryMetric.paletteSwatchWidth, height: SETGalleryMetric.paletteSwatchHeight, alignment: .leading)
        .background(color)
        .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
    }
}

private struct SETComponentsGallery: View {
    var body: some View {
        SETGallerySection(number: "02", title: .galleryComponents) {
            VStack(alignment: .leading, spacing: SETSpacing.x6) {
                HStack(alignment: .top, spacing: SETSpacing.x8) {
                    SETWordmark(layout: .horizontal)
                    SETWordmark(layout: .stacked)
                }

                SETDigitalAction(title: .actionMain, helper: .entryHelper)
                SETABRollCapsule(selected: .camera)
                SETHUDChip(
                    style: .corrective,
                    title: .cameraSeeking,
                    action: .cameraCorrectiveAction
                )

                SETLeaderCountdown(phase: .two)
                    .frame(width: SETGalleryMetric.markerSampleWidth)

                HStack(spacing: SETSpacing.x4) {
                    SETTallyBadge(mode: .live, pulses: true)
                    SETTallyBadge(mode: .standby)
                    SETTallyBadge(mode: .eco)
                    SETTimecodeView(value: "00:03:18:12")
                }

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: SETSpacing.x3) {
                        markerSample(kind: .arrow, key: .galleryMarkerArrow)
                        markerSample(kind: .line, key: .galleryMarkerLine)
                        markerSample(kind: .outline, key: .galleryMarkerOutline)
                        markerSample(kind: .underline, key: .galleryMarkerUnderline)
                        markerSample(kind: .bracket, key: .galleryMarkerBracket)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func markerSample(kind: SETMarkerKind, key: SETCopyKey) -> some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            GlassMarkGuide(kind: kind, color: .setWarmWhite)
                .frame(width: SETGalleryMetric.markerSampleWidth, height: SETGalleryMetric.markerSampleHeight)
            Text(key.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .foregroundStyle(.setTextPrimary)
        }
        .frame(minWidth: SETGalleryMetric.markerSampleWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(key.localizedTextKey))
    }
}

private struct SETEntryGallery: View {
    private let fixtures = [
        "entry.resolving", "entry.requesting", "entry.ready", "entry.intro",
        "entry.permission", "entry.blocked-denied", "entry.blocked-restricted",
        "entry.blocked-unavailable", "entry.blocked-unknown"
    ]

    var body: some View {
        SETGallerySection(number: "03", title: .galleryEditorial) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: SETSpacing.x4) {
                    ForEach(fixtures, id: \.self) { fixture in
                        SETEntryFixtureScreen(fixtureID: fixture)
                            .frame(width: SETComponentMetric.galleryCardWidth, height: SETGalleryMetric.entryHeight)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct SETCameraGallery: View {
    private let fixtures = [
        "camera.starting", "camera.interrupted", "camera.failed", "camera.seeking",
        "camera.keep", "camera.corrective", "camera.fallback", "camera.explanation",
        "camera.lens-switching", "camera.resuming", "camera.eco"
    ]

    var body: some View {
        SETGallerySection(number: "04", title: .galleryCamera) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: SETSpacing.x4) {
                    ForEach(fixtures, id: \.self) { fixture in
                        SETCameraFixtureScreen(fixtureID: fixture)
                            .frame(width: SETComponentMetric.galleryCardWidth, height: SETComponentMetric.galleryCameraPortraitHeight)
                    }
                }
            }
            .scrollIndicators(.hidden)

            SETCameraFixtureScreen(fixtureID: "camera.corrective")
                .frame(maxWidth: SETComponentMetric.gallerySectionMaxWidth)
                .aspectRatio(SETComponentMetric.cameraPreviewAspect, contentMode: .fit)
        }
    }
}

private struct SETEditorialGallery: View {
    var body: some View {
        SETGallerySection(number: "05", title: .galleryEditorial) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: SETSpacing.x4) {
                    ForEach(["camera.pause-loading", "camera.pause-success", "camera.pause-empty", "camera.pause-failure"], id: \.self) { fixture in
                        SETPauseFixtureScreen(fixtureID: fixture)
                            .frame(width: SETComponentMetric.galleryLandscapeWidth, height: SETGalleryMetric.pauseHeight)
                    }
                }
            }
            .scrollIndicators(.hidden)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: SETSpacing.x4) {
                    ForEach(["generator.preflight", "generator.clarification", "generator.progress", "generator.cancelled", "generator.failure", "generator.result"], id: \.self) { fixture in
                        SETGeneratorFixtureScreen(fixtureID: fixture)
                            .frame(width: SETComponentMetric.galleryLandscapeWidth, height: SETComponentMetric.galleryLandscapeHeight)
                    }
                }
            }
            .scrollIndicators(.hidden)

            SETLibraryFixtureScreen()
                .frame(maxWidth: SETComponentMetric.gallerySectionMaxWidth)
                .aspectRatio(SETGalleryMetric.landscapeAspect, contentMode: .fit)

            SETStoryboardFixtureScreen()
                .frame(maxWidth: SETComponentMetric.gallerySectionMaxWidth)
                .aspectRatio(SETGalleryMetric.landscapeAspect, contentMode: .fit)
        }
    }
}

private struct SETAccessibilityGallery: View {
    var body: some View {
        SETGallerySection(number: "06", title: .galleryAccessibility) {
            Text(SETCopyKey.galleryVariant.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .tracking(0.65)
                .foregroundStyle(.setOrange)

            SETMarkerAnnotation(
                kind: .underline,
                label: .storyboardMarker,
                animationEventID: "storyboard-anchor-frame"
            ) {
                Text(SETCopyKey.generatorResult.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: .bold))
                    .foregroundStyle(.setTextPrimary)
                    .padding(SETSpacing.x6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.setSurfaceSolid)
            }
            .frame(minHeight: SETGalleryMetric.accessibilitySampleHeight)

            SETDigitalAction(title: .generatorAction, helper: .generatorHelper)
        }
    }
}

private struct SETFixtureCanvas: View {
    let descriptor: SETFixtureDescriptor

    var body: some View {
        Group {
            switch descriptor.family {
            case .foundations:
                SETFoundationsGallery()
            case .components:
                SETComponentsGallery()
            case .entry:
                SETEntryFixtureScreen(fixtureID: descriptor.id)
            case .camera:
                SETCameraFixtureScreen(fixtureID: descriptor.id)
            case .pause:
                SETPauseFixtureScreen(fixtureID: descriptor.id)
            case .generator:
                SETGeneratorFixtureScreen(fixtureID: descriptor.id)
            case .library:
                SETLibraryFixtureScreen()
            case .storyboard:
                SETStoryboardFixtureScreen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SETEntryFixtureScreen: View {
    let fixtureID: String

    private var title: SETCopyKey {
        switch fixtureID {
        case "entry.permission": .permissionTitle
        case "entry.blocked-denied": .blockedDenied
        case "entry.blocked-restricted": .blockedRestricted
        case "entry.blocked-unavailable": .blockedUnavailable
        case "entry.blocked-unknown": .blockedUnknown
        default: .entryPoster
        }
    }

    private var action: SETCopyKey {
        switch fixtureID {
        case "entry.blocked-denied": .openSettings
        case "entry.blocked-restricted", "entry.blocked-unavailable", "entry.blocked-unknown": .checkAgain
        default: .actionMain
        }
    }

    var body: some View {
        ZStack {
            Color.setInk

            VStack(alignment: .leading, spacing: SETSpacing.x6) {
                HStack {
                    SETWordmark(layout: .stacked)
                    Spacer()
                    Text(SETCopyKey.fixtureEntryMark.localizedTextKey)
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                        .foregroundStyle(.setOrange)
                }

                Spacer(minLength: 0)

                SETPosterTitle(key: title)
                Text(fixtureID == "entry.permission" ? SETCopyKey.permissionBody.localizedTextKey : SETCopyKey.entryBody.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: .medium))
                    .foregroundStyle(.setTextSecondary)
                SETDigitalAction(title: action, helper: fixtureID == "entry.intro" ? .entryHelper : nil)
            }
            .padding(SETSpacing.x6)

            SETRegistrationMarks().padding(SETSpacing.x3)
        }
        .clipped()
        .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
        .accessibilityIdentifier(fixtureID)
    }
}

private struct SETBeatFixture: Identifiable {
    let id: String
    let title: SETCopyKey
    let detail: SETCopyKey
}

private struct SETGeneratorFixtureScreen: View {
    let fixtureID: String
    @State private var selectedBeatID: String

    private let beats = [
        SETBeatFixture(id: "beat-previous", title: .librarySceneOne, detail: .generatorProgressReading),
        SETBeatFixture(id: "beat-active", title: .slateScene, detail: .generatorMarker),
        SETBeatFixture(id: "beat-next", title: .librarySceneTwo, detail: .generatorProgressFrame)
    ]

    init(fixtureID: String) {
        self.fixtureID = fixtureID
        _selectedBeatID = State(initialValue: "beat-active")
    }

    private var title: SETCopyKey {
        switch fixtureID {
        case "generator.clarification": .generatorClarification
        case "generator.failure": .generatorFailure
        case "generator.result": .generatorResult
        case "generator.cancelled": .generatorCancelled
        default: .generatorTitle
        }
    }

    private var status: SETCopyKey {
        switch fixtureID {
        case "generator.progress": .generatorProgressAnchors
        case "generator.failure": .generatorFailure
        case "generator.cancelled": .generatorCancelled
        case "generator.result": .generatorResult
        default: .generatorHelper
        }
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: SETSpacing.x3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SETCopyKey.fixtureGeneratorMark.localizedTextKey)
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                        .foregroundStyle(.setOrange)
                    Spacer()
                    Text(title.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .bold))
                        .foregroundStyle(.setTextPrimary)
                }

                SETMontageReflow(items: beats, selectedID: selectedBeatID, axis: .horizontal, onSelect: { beat in
                    selectedBeatID = beat.id
                }) { beat, selected in
                    SETGeneratorBeatCell(beat: beat, selected: selected)
                }
                .frame(height: proxy.size.height * SETGalleryMetric.generatorReflowHeightFraction)

                HStack(alignment: .center, spacing: SETSpacing.x3) {
                    Text(status.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .foregroundStyle(.setTextSecondary)
                    if fixtureID == "generator.progress" {
                        Text(SETCopyKey.generatorPercentage.localizedTextKey)
                            .font(SETTypography.font(.hudMono, size: SETTypographySize.displayMedium))
                            .foregroundStyle(.setTextPrimary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: SETSpacing.x2)
                    SETDigitalAction(title: .generatorAction)
                }
            }
            .padding(SETSpacing.x4)
        }
        .background(.setInk)
        .overlay(alignment: .topTrailing) { SETFilmEdge() }
        .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
        .accessibilityIdentifier(fixtureID)
    }
}

private struct SETGeneratorBeatCell: View {
    let beat: SETBeatFixture
    let selected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.setSurfaceSolid
            VStack(alignment: .leading, spacing: SETSpacing.x3) {
                Text(beat.title.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: selected ? .bold : .semibold))
                    .foregroundStyle(.setTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !selected {
                    Text(beat.detail.localizedTextKey)
                        .font(SETTypography.uiBodyFont())
                        .foregroundStyle(.setTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: SETSpacing.x2)
                SETReflowAnnotation(isVisible: selected) {
                    SETCompactMarkerNote(kind: .underline, label: .generatorMarker)
                }
            }
            .padding(SETSpacing.x4)
        }
        .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
        .accessibilityElement(children: .combine)
    }
}

private struct SETSceneFixture: Identifiable {
    let id: String
    let title: SETCopyKey
    let metadata: [SETCopyKey]
}

private struct SETLibraryFixtureScreen: View {
    @State private var selectedSceneID: String

    private let scenes = [
        SETSceneFixture(id: "scene-01", title: .librarySceneOne, metadata: [.libraryMetadataDuration, .libraryMetadataShot]),
        SETSceneFixture(id: "scene-02", title: .librarySceneTwo, metadata: [.libraryMetadataDuration, .libraryMetadataShot]),
        SETSceneFixture(id: "scene-03", title: .librarySceneThree, metadata: [.libraryMetadataDuration, .libraryMetadataShot])
    ]

    init() {
        _selectedSceneID = State(initialValue: "scene-02")
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: SETSpacing.x3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SETCopyKey.libraryTitle.localizedTextKey)
                        .font(SETTypography.font(.display, size: SETTypographySize.displayMedium))
                        .fontWeight(.bold)
                        .foregroundStyle(.setTextPrimary)
                    Spacer()
                    SETABRollCapsule(selected: .scenes)
                }

                SETMontageReflow(items: scenes, selectedID: selectedSceneID, axis: .vertical, onSelect: { scene in
                    selectedSceneID = scene.id
                }) { scene, selected in
                    SETLibrarySceneRow(scene: scene, selected: selected)
                }
                .frame(height: proxy.size.height - SETGalleryMetric.libraryHeaderHeight)
            }
            .padding(SETSpacing.x4)
        }
        .background(.setInk)
        .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
        .accessibilityIdentifier("library.contact-sheet")
    }
}

private struct SETLibrarySceneRow: View {
    let scene: SETSceneFixture
    let selected: Bool

    var body: some View {
        HStack(spacing: SETSpacing.x4) {
            if selected {
                SETBundledImage.image(named: "SETCameraFrame")
                    .resizable()
                    .scaledToFill()
                    .frame(width: SETGalleryMetric.libraryPreviewWidth)
                    .clipped()
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: SETSpacing.x2) {
                Text(scene.title.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: selected ? .bold : .semibold))
                    .foregroundStyle(.setTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if selected {
                    ForEach(scene.metadata, id: \.rawValue) { key in
                        Text(key.localizedTextKey)
                            .font(SETTypography.uiBodyFont())
                            .foregroundStyle(.setTextSecondary)
                    }
                } else {
                    Text(scene.metadata[0].localizedTextKey)
                        .font(SETTypography.uiBodyFont())
                        .foregroundStyle(.setTextSecondary)
                }

            }
            .padding(SETSpacing.x4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.setSurfaceSolid)
        .overlay(alignment: .bottomTrailing) {
            SETReflowAnnotation(isVisible: selected) {
                SETCompactMarkerNote(
                    kind: .bracket,
                    label: .libraryMarker,
                    width: SETGalleryMetric.libraryMarkerWidth,
                    height: SETGalleryMetric.libraryMarkerHeight,
                    handSize: SETGalleryMetric.libraryMarkerHandSize
                )
                .padding(SETSpacing.x3)
            }
        }
        .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
        .accessibilityElement(children: .combine)
    }
}

private struct SETStoryboardFrame: Identifiable {
    let id: String
    let title: SETCopyKey
    let cropScale: CGFloat
    let cropOffset: CGFloat
}

private struct SETStoryboardFixtureScreen: View {
    @State private var selectedFrameID: String

    private let frames = [
        SETStoryboardFrame(id: "frame-01", title: .storyboardFrameOne, cropScale: SETGalleryMetric.storyboardCropScaleWide, cropOffset: SETGalleryMetric.storyboardCropOffsetWide),
        SETStoryboardFrame(id: "frame-02", title: .storyboardFrameTwo, cropScale: SETGalleryMetric.storyboardCropScaleSelected, cropOffset: SETGalleryMetric.storyboardCropOffsetSelected),
        SETStoryboardFrame(id: "frame-03", title: .storyboardFrameThree, cropScale: SETGalleryMetric.storyboardCropScaleDetail, cropOffset: SETGalleryMetric.storyboardCropOffsetDetail)
    ]

    init() {
        _selectedFrameID = State(initialValue: "frame-02")
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: SETSpacing.x3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SETCopyKey.generatorResult.localizedTextKey)
                        .font(SETTypography.font(.display, size: SETTypographySize.displayMedium))
                        .fontWeight(.bold)
                        .foregroundStyle(.setTextPrimary)
                    Spacer()
                }

                SETMontageReflow(items: frames, selectedID: selectedFrameID, axis: .horizontal, onSelect: { frame in
                    selectedFrameID = frame.id
                }) { frame, selected in
                    SETStoryboardFrameCell(frame: frame, selected: selected)
                }
                .frame(height: proxy.size.height - SETGalleryMetric.storyboardHeaderHeight)
            }
            .padding(SETSpacing.x4)
        }
        .background(.setInk)
        .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
        .accessibilityIdentifier("storyboard.result")
    }
}

private struct SETStoryboardFrameCell: View {
    let frame: SETStoryboardFrame
    let selected: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                SETBundledImage.image(named: "SETCameraFrame")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(frame.cropScale)
                    .offset(x: frame.cropOffset)
                    .clipped()
                    .accessibilityHidden(true)

                Color.setInk.opacity(
                    selected
                        ? SETGalleryMetric.storyboardSelectedOverlayOpacity
                        : SETGalleryMetric.storyboardNeighborOverlayOpacity
                )
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: SETSpacing.x2) {
                    Text(frame.title.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: selected ? .bold : .semibold))
                        .foregroundStyle(.setTextPrimary)
                    SETReflowAnnotation(isVisible: selected) {
                        SETCompactMarkerNote(kind: .underline, label: .storyboardMarker)
                    }
                }
                .padding(SETSpacing.x4)
            }
        }
        .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
        .accessibilityElement(children: .combine)
    }
}

private struct SETCompactMarkerNote: View {
    let kind: SETMarkerKind
    let label: SETCopyKey
    var width: CGFloat = SETGalleryMetric.compactMarkerWidth
    var height: CGFloat = SETGalleryMetric.compactMarkerHeight
    var handSize: CGFloat = SETGalleryMetric.markerHandSize

    var body: some View {
        ZStack(alignment: .center) {
            GlassMarkGuide(kind: kind, color: .setWarmWhite)
            Text(label.localizedTextKey)
                .font(SETTypography.font(.hand, size: handSize))
                .fontWeight(.semibold)
                .foregroundStyle(.setWarmWhite)
                .padding(.horizontal, SETSpacing.x4)
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label.localizedTextKey))
    }
}

private enum SETGalleryMetric {
    static let paletteSwatchWidth: CGFloat = 176
    static let paletteSwatchHeight: CGFloat = 120
    static let markerSampleWidth: CGFloat = 128
    static let markerSampleHeight: CGFloat = 64
    static let compactMarkerWidth: CGFloat = 204
    static let compactMarkerHeight: CGFloat = 52
    static let markerHandSize: CGFloat = 20
    static let entryHeight: CGFloat = 560
    static let pauseHeight: CGFloat = 248
    static let landscapeAspect: CGFloat = 16.0 / 9.0
    static let accessibilitySampleHeight: CGFloat = 96
    static let cameraScrimHeight: CGFloat = 88
    static let cameraScrimOpacity = 0.72
    static let cameraReducedScrimOpacity = 0.84
    static let cameraPortraitChromeHeight: CGFloat = 148
    static let cameraLandscapeChromeHeight: CGFloat = 76
    static let pausePortraitPreviewFraction: CGFloat = 0.58
    static let pauseLandscapePreviewFraction: CGFloat = 0.52
    static let pauseMarkerWidth: CGFloat = 148
    static let pauseMarkerHeight: CGFloat = 188
    static let generatorReflowHeightFraction: CGFloat = 0.62
    static let libraryHeaderHeight: CGFloat = 116
    static let libraryPreviewWidth: CGFloat = 170
    static let libraryMarkerWidth: CGFloat = 176
    static let libraryMarkerHeight: CGFloat = 44
    static let libraryMarkerHandSize: CGFloat = 18
    static let storyboardHeaderHeight: CGFloat = 96
    static let storyboardSelectedOverlayOpacity = 0.18
    static let storyboardNeighborOverlayOpacity = 0.38
    static let storyboardCropScaleWide: CGFloat = 1.06
    static let storyboardCropScaleSelected: CGFloat = 1.18
    static let storyboardCropScaleDetail: CGFloat = 1.30
    static let storyboardCropOffsetWide: CGFloat = -8
    static let storyboardCropOffsetSelected: CGFloat = -96
    static let storyboardCropOffsetDetail: CGFloat = 12
}

#Preview("SET OS / Visual Policy v2.4") {
    DesignSystemPreviews()
}
#endif
