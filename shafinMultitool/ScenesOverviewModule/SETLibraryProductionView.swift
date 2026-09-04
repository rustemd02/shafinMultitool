import SwiftUI

// MARK: - Ownership contract

/// Projection-only bridge from the existing library behavior owners
/// (`SOViewController` + `SOPresenter`/`SOInteractor` + `SORouter`). The SET OS
/// surface never becomes a new state owner: listing, persistence and routing
/// stay behind this protocol.
protocol SETLibrarySceneProviding: AnyObject {
    func librarySceneSummaries() -> [UnifiedSceneProjectSummary]
    func libraryCreateScene(named name: String) -> SETLibraryCreateOutcome
    func libraryDeleteScene(named name: String, completion: @escaping (Bool) -> Void)
    func libraryOpenScene(named name: String)
}

enum SETLibraryCreateOutcome: Equatable, Sendable {
    case created
    case invalidName
    case duplicateName
    case persistenceFailure
}

// MARK: - Presentation model

/// Library presentation state machine. Selection, drafts and flow states are
/// presentation projections; every mutation funnels back into the controlling
/// presenter so persistence and routing ownership is unchanged.
@MainActor
final class SETLibraryModel: ObservableObject {
    enum FlowState: Equatable {
        case idle
        case creating
        case duplicate(conflictingName: String)
        case deleting(sceneName: String)
        case failure(FailureKind)
    }

    enum FailureKind: Equatable {
        case create
        case delete
    }

    struct SceneRow: Identifiable, Equatable {
        let id: UUID
        let name: String
        let updatedAt: Date
    }

    @Published private(set) var scenes: [SceneRow] = []
    @Published private(set) var selectedSceneID: UUID?
    @Published private(set) var flow: FlowState = .idle
    @Published var createDraft: String = ""

    let controlling: SETLibrarySceneProviding

    /// Retry context so `library.persistence-failure` can honestly re-run the
    /// failed operation instead of a generic refresh.
    private var pendingRetry: FailureKind?

    init(controlling: SETLibrarySceneProviding) {
        self.controlling = controlling
    }

    var selectedScene: SceneRow? {
        scenes.first { $0.id == selectedSceneID }
    }

    func reload() {
        scenes = controlling.librarySceneSummaries().map {
            SceneRow(id: $0.id, name: $0.name, updatedAt: $0.updatedAt)
        }
        if let selectedSceneID, !scenes.contains(where: { $0.id == selectedSceneID }) {
            self.selectedSceneID = nil
        }
        if case .deleting(let name) = flow, !scenes.contains(where: { $0.name == name }) {
            flow = .idle
        }
    }

    func select(_ id: UUID) {
        guard flow == .idle else { return }
        selectedSceneID = id
    }

    func openSelectedScene() {
        guard let selectedScene else { return }
        controlling.libraryOpenScene(named: selectedScene.name)
    }

    func beginCreate() {
        guard flow == .idle else { return }
        createDraft = ""
        flow = .creating
    }

    func cancelCreate() {
        guard flow == .creating || isDuplicateFlow else { return }
        createDraft = ""
        flow = .idle
    }

    private var isDuplicateFlow: Bool {
        if case .duplicate = flow { return true }
        return false
    }

    func confirmCreate() {
        let trimmed = createDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if scenes.contains(where: { $0.name == trimmed }) {
            flow = .duplicate(conflictingName: trimmed)
            return
        }
        switch controlling.libraryCreateScene(named: trimmed) {
        case .created:
            controlling.libraryOpenScene(named: trimmed)
            flow = .idle
        case .duplicateName:
            flow = .duplicate(conflictingName: trimmed)
        case .invalidName:
            break
        case .persistenceFailure:
            pendingRetry = .create
            flow = .failure(.create)
        }
    }

    func beginDelete(sceneName: String) {
        guard flow == .idle else { return }
        flow = .deleting(sceneName: sceneName)
    }

    func cancelDelete() {
        guard case .deleting = flow else { return }
        flow = .idle
    }

    func confirmDelete() {
        guard case .deleting(let name) = flow else { return }
        controlling.libraryDeleteScene(named: name) { [weak self] deleted in
            Task { @MainActor in
                self?.handleDeleteResult(deleted, sceneName: name)
            }
        }
    }

    private func handleDeleteResult(_ deleted: Bool, sceneName: String) {
        guard case .deleting(let name) = flow, name == sceneName else { return }
        if deleted {
            flow = .idle
            reload()
        } else {
            pendingRetry = .delete
            flow = .failure(.delete)
        }
    }

    func retry() {
        let kind = pendingRetry
        pendingRetry = nil
        switch kind {
        case .create:
            flow = .creating
            confirmCreate()
        case .delete:
            if let scene = scenes.first(where: { $0.name == retryableDeleteName }) {
                flow = .deleting(sceneName: scene.name)
                confirmDelete()
            } else {
                flow = .idle
            }
        case nil:
            flow = .idle
        }
    }

    private var retryableDeleteName: String? {
        if case .failure(.delete) = flow, let selected = selectedScene {
            return selected.name
        }
        return nil
    }
}

// MARK: - Fixture support

/// Deterministic DEBUG fixture input. Fixture payloads are projection-only:
/// they select scenes, forced failures and entry flows without touching the
/// production persistence owner.
struct SETLibraryFixtureConfiguration {
    let fixtureID: String
    let locale: Locale
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let dynamicTypeSize: DynamicTypeSize

    init(
        fixtureID: String,
        localeIdentifier: String = "ru",
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        dynamicTypeSize: DynamicTypeSize = .large
    ) {
        self.fixtureID = fixtureID
        self.locale = Locale(identifier: localeIdentifier)
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.dynamicTypeSize = dynamicTypeSize
    }
}

/// In-memory deterministic provider for the DEBUG fixture route. It mirrors the
/// DBService outcome vocabulary (duplicate name, persistence failure) without
/// touching the file system. Instances are used from the main actor only.
final class SETLibraryFixtureProvider: SETLibrarySceneProviding {
    var scenes: [UnifiedSceneProjectSummary]
    var failCreate = false
    var failDelete = false
    private(set) var openedSceneNames: [String] = []

    init(scenes: [UnifiedSceneProjectSummary], failCreate: Bool = false, failDelete: Bool = false) {
        self.scenes = scenes
        self.failCreate = failCreate
        self.failDelete = failDelete
    }

    func librarySceneSummaries() -> [UnifiedSceneProjectSummary] {
        scenes
    }

    func libraryCreateScene(named name: String) -> SETLibraryCreateOutcome {
        if failCreate {
            return .persistenceFailure
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidName }
        guard !scenes.contains(where: { $0.name == trimmed }) else { return .duplicateName }
        scenes.append(
            UnifiedSceneProjectSummary(
                id: UUID(),
                name: trimmed,
                updatedAt: SETLibraryFixtureData.dates.last ?? Date(timeIntervalSince1970: 0)
            )
        )
        return .created
    }

    func libraryDeleteScene(named name: String, completion: @escaping (Bool) -> Void) {
        if failDelete {
            completion(false)
            return
        }
        guard let index = scenes.firstIndex(where: { $0.name == name }) else {
            completion(false)
            return
        }
        scenes.remove(at: index)
        completion(true)
    }

    func libraryOpenScene(named name: String) {
        openedSceneNames.append(name)
    }
}

enum SETLibraryFixtureData {
    /// Fixed GMT timestamps keep fixture metadata deterministic across runs.
    static let dates: [Date] = [
        Date(timeIntervalSince1970: 1_786_984_800), // 2026-08-17 21:09 GMT minus fixture drift
        Date(timeIntervalSince1970: 1_787_041_320),
        Date(timeIntervalSince1970: 1_787_134_700)
    ]

    static func summaries(locale: Locale) -> [UnifiedSceneProjectSummary] {
        let nameKeys: [SETCopyKey] = [.librarySceneOne, .librarySceneTwo, .librarySceneThree]
        return zip(nameKeys, dates).map { key, date in
            UnifiedSceneProjectSummary(
                id: UUID(),
                name: SETLibraryLocalizedCopy.string(key, locale: locale),
                updatedAt: date
            )
        }
    }
}

// MARK: - Copy resolution

/// Locale-explicit lookup for fixture surfaces and formatted copy. Table
/// lookup must follow the requested language, not the device locale (the
/// Package 2 localization remediation contract).
enum SETLibraryLocalizedCopy {
    static func resolvedBundle(for locale: Locale) -> Bundle {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        for candidate in [languageCode, locale.identifier] {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }

    static func string(_ key: SETCopyKey, locale: Locale) -> String {
        resolvedBundle(for: locale).localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
    }

    static func formatted(_ key: SETCopyKey, locale: Locale, arguments: [CVarArg]) -> String {
        let format = resolvedBundle(for: locale).localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func updatedLabel(for date: Date, locale: Locale, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatted(.libraryMetadataUpdated, locale: locale, arguments: [formatter.string(from: date)])
    }

    static func countLabel(_ count: Int, locale: Locale) -> String {
        formatted(.libraryCount, locale: locale, arguments: [count])
    }
}

// MARK: - Accessibility identifiers

enum SETLibraryAccessibilityID {
    static let root = "library_root"
    static let title = "library_title"
    static let count = "library_count"
    static let list = "library_list"
    static let emptyState = "library_empty_state"
    static let emptyCreate = "library_empty_create"
    static let createField = "library_create_field"
    static let createConfirm = "library_create_confirm"
    static let createCancel = "library_create_cancel"
    static let duplicateNotice = "library_duplicate_notice"
    static let sceneDelete = "library_scene_delete"
    static let sceneOpen = "library_scene_open"
    static let deleteConfirm = "library_delete_confirm"
    static let deleteCancel = "library_delete_cancel"
    static let failureRetry = "library_failure_retry"

    static func sceneRow(at position: Int) -> String {
        "library_scene_row_\(position)"
    }
}

// MARK: - Production surface

/// Production SET OS library surface (Package 3). Runtime and deterministic
/// DEBUG routes share this presentation owner so UI tests exercise the same
/// contact-sheet grammar the commercial shell reaches through SOModuleBuilder.
struct SETLibraryProductionView: View {
    private enum Source {
        case runtime(SETLibraryModel)
        case fixture(SETLibraryFixtureConfiguration)
    }

    private let source: Source

    init(model: SETLibraryModel) {
        source = .runtime(model)
    }

    init(fixtureConfiguration: SETLibraryFixtureConfiguration) {
        source = .fixture(fixtureConfiguration)
    }

    var body: some View {
        Group {
            switch source {
            case .runtime(let model):
                SETLibraryRuntimeSurface(model: model)
            case .fixture(let configuration):
                SETLibraryFixtureSurface(configuration: configuration)
                    .environment(\.locale, configuration.locale)
                    .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
                    .environment(\.setReduceMotionOverride, configuration.reduceMotion)
                    .environment(\.setReduceTransparencyOverride, configuration.reduceTransparency)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Runtime surface

private struct SETLibraryRuntimeSurface: View {
    @ObservedObject var model: SETLibraryModel

    var body: some View {
        SETLibraryContactSheet(model: model)
            .background(.setInk)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(SETLibraryAccessibilityID.root)
    }
}

// MARK: - Fixture surface

private struct SETLibraryFixtureSurface: View {
    let configuration: SETLibraryFixtureConfiguration
    @StateObject private var model: SETLibraryModel

    init(configuration: SETLibraryFixtureConfiguration) {
        self.configuration = configuration
        let provider = SETLibraryFixtureProvider(
            scenes: SETLibraryFixtureData.summaries(locale: configuration.locale),
            failCreate: configuration.fixtureID == "library.persistence-failure"
        )
        _model = StateObject(wrappedValue: SETLibraryModel(controlling: provider))
    }

    var body: some View {
        SETLibraryContactSheet(model: model)
            .background(.setInk)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(configuration.fixtureID)
            .task { await driveFixtureInitialState() }
    }

    @MainActor
    private func driveFixtureInitialState() async {
        guard let provider = model.controlling as? SETLibraryFixtureProvider else { return }
        model.reload()
        switch configuration.fixtureID {
        case "library.empty":
            provider.scenes = []
            model.reload()
        case "library.selected":
            model.select(provider.scenes[1].id)
        case "library.create-name":
            model.beginCreate()
        case "library.duplicate-name":
            model.beginCreate()
            model.createDraft = provider.scenes[1].name
            model.confirmCreate()
        case "library.delete-confirmation":
            let scene = provider.scenes[2]
            model.select(scene.id)
            model.beginDelete(sceneName: scene.name)
        case "library.persistence-failure":
            model.beginCreate()
            model.createDraft = SETLibraryLocalizedCopy.string(.librarySceneFour, locale: configuration.locale)
            model.confirmCreate()
        default:
            break
        }
    }
}

// MARK: - Contact sheet

private struct SETLibraryContactSheet: View {
    @ObservedObject var model: SETLibraryModel

    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: SETSpacing.x3) {
                header

                if model.scenes.isEmpty {
                    SETLibraryEmptyState(model: model)
                        .frame(maxHeight: .infinity)
                } else {
                    SETLibrarySceneList(model: model, locale: locale)
                        .frame(maxHeight: .infinity)
                }

                flowPanel
            }
            .padding(SETSpacing.x4)
            .overlay(alignment: .topTrailing) {
                if model.scenes.isEmpty {
                    SETFilmEdge()
                        .padding(SETSpacing.x3)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: SETSpacing.x3) {
            Text(SETCopyKey.libraryTitle.localizedTextKey)
                .font(SETTypography.font(.display, size: SETTypographySize.displayMedium))
                .fontWeight(.bold)
                .setDisplayTracking()
                .foregroundStyle(.setTextPrimary)
                .accessibilityIdentifier(SETLibraryAccessibilityID.title)

            Spacer(minLength: SETSpacing.x3)

            if !model.scenes.isEmpty {
                Text(SETLibraryLocalizedCopy.countLabel(model.scenes.count, locale: locale))
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                    .monospacedDigit()
                    .tracking(0.65)
                    .foregroundStyle(.setTextSecondary)
                    .accessibilityIdentifier(SETLibraryAccessibilityID.count)
            }
        }
    }

    @ViewBuilder
    private var flowPanel: some View {
        switch model.flow {
        case .idle:
            EmptyView()
        case .creating:
            SETLibraryCreatePanel(model: model, duplicateName: nil)
        case .duplicate(let conflictingName):
            SETLibraryCreatePanel(model: model, duplicateName: conflictingName)
        case .deleting(let sceneName):
            SETLibraryDeletePanel(model: model, sceneName: sceneName)
        case .failure(let kind):
            SETLibraryFailurePanel(model: model, kind: kind)
        }
    }
}

// MARK: - Empty state (`library.empty`)

private struct SETLibraryEmptyState: View {
    @ObservedObject var model: SETLibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x4) {
            Text(SETCopyKey.libraryEmptyTitle.localizedTextKey)
                .font(SETTypography.font(.display, size: SETTypographySize.displayMedium))
                .fontWeight(.bold)
                .setDisplayTracking()
                .foregroundStyle(.setTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(SETCopyKey.libraryEmptyHelper.localizedTextKey)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: SETSpacing.x2)

            ZStack(alignment: .bottom) {
                SETDigitalAction(
                    title: .libraryCreate,
                    helper: .libraryCreatePlaceholder,
                    action: { model.beginCreate() }
                )
                .accessibilityIdentifier(SETLibraryAccessibilityID.emptyCreate)
                .accessibilityLabel(Text(SETCopyKey.accessibilityLibraryCreate.localizedTextKey))

                // One underline annotation tied to the create action.
                GlassMarkGuide(kind: .underline, color: .setOrange)
                    .frame(height: SETSpacing.x2)
                    .padding(.horizontal, SETSpacing.x2)
                    .offset(y: SETSpacing.x1)
            }
            .frame(maxWidth: SETComponentMetric.gallerySectionMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SETLibraryAccessibilityID.emptyState)
    }
}

// MARK: - Scene list (`library.contact-sheet`, `library.selected`)

private struct SETLibrarySceneList: View {
    @ObservedObject var model: SETLibraryModel
    let locale: Locale

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.scenes.enumerated()), id: \.element.id) { index, scene in
                    SETLibrarySceneRow(
                        scene: scene,
                        position: index + 1,
                        isSelected: scene.id == model.selectedSceneID,
                        locale: locale,
                        onSelect: { model.select(scene.id) },
                        onOpen: {
                            model.select(scene.id)
                            model.openSelectedScene()
                        },
                        onDelete: {
                            model.select(scene.id)
                            model.beginDelete(sceneName: scene.name)
                        }
                    )
                }
            }
            .overlay {
                Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
            }
        }
        .accessibilityIdentifier(SETLibraryAccessibilityID.list)
    }
}

private struct SETLibrarySceneRow: View {
    let scene: SETLibraryModel.SceneRow
    let position: Int
    let isSelected: Bool
    let locale: Locale
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride

    private var isMotionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: SETSpacing.x2) {
                HStack(alignment: .firstTextBaseline, spacing: SETSpacing.x3) {
                    Text(String(format: "%02d", position))
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                        .monospacedDigit()
                        .tracking(0.65)
                        .foregroundStyle(isSelected ? Color.setOrange : Color.setTextTertiary)

                    Text(scene.name)
                        .font(SETTypography.uiBodyFont(weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(.setTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: SETSpacing.x3)

                    Text(SETLibraryLocalizedCopy.updatedLabel(for: scene.updatedAt, locale: locale))
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                        .monospacedDigit()
                        .tracking(0.35)
                        .foregroundStyle(.setTextSecondary)
                }

                if isSelected {
                    selectedContent
                }
            }
            .padding(.horizontal, SETSpacing.x4)
            .padding(.vertical, isSelected ? SETSpacing.x3 : SETSpacing.x2)
            .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.setSurfaceSolid)
            .overlay(alignment: .top) {
                // One cut seam marks the expanded-row boundary.
                CutSeam(axis: .horizontal)
            }
            .overlay(alignment: .bottomLeading) {
                SETReflowAnnotation(isVisible: isSelected) {
                    SETLibraryMarkerNote(kind: .bracket, label: .libraryMarker)
                    .padding(SETSpacing.x2)
                }
                .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .animation(
            isMotionReduced
                ? .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)
                : SETMotion.reflowSpring,
            value: isSelected
        )
        .accessibilityIdentifier(SETLibraryAccessibilityID.sceneRow(at: position))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectedContent: some View {
        HStack(spacing: SETSpacing.x4) {
            SETDigitalAction(title: .libraryOpen, action: onOpen)
                .accessibilityIdentifier(SETLibraryAccessibilityID.sceneOpen)

            Button(action: onDelete) {
                Text(SETCopyKey.libraryDelete.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: .semibold))
                    .foregroundStyle(.setTextSecondary)
                    .underline()
                    .padding(.horizontal, SETSpacing.x3)
                        .frame(minHeight: SETComponentMetric.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(SETLibraryAccessibilityID.sceneDelete)
            .accessibilityLabel(
                Text(
                    SETLibraryLocalizedCopy.formatted(
                        .accessibilityLibraryDeleteScene,
                        locale: locale,
                        arguments: [scene.name]
                    )
                )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bracket annotation with a short hand note; meaning is duplicated by the
/// accessible row label, the handwriting never stays the only carrier.
private struct SETLibraryMarkerNote: View {
    let kind: SETMarkerKind
    let label: SETCopyKey
    var handSize: CGFloat = 20

    var body: some View {
        ZStack(alignment: .center) {
            GlassMarkGuide(kind: kind, color: .setWarmWhite)
            Text(label.localizedTextKey)
                .font(SETTypography.font(.hand, size: handSize))
                .fontWeight(.semibold)
                .foregroundStyle(.setWarmWhite)
                .padding(.horizontal, SETSpacing.x4)
        }
        .frame(width: 204, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SETCopyKey.accessibilityLibrarySelectedScene.localizedTextKey))
    }
}

// MARK: - Create-name panel (`library.create-name`, `library.duplicate-name`)

private struct SETLibraryCreatePanel: View {
    @ObservedObject var model: SETLibraryModel
    let duplicateName: String?

    @Environment(\.locale) private var locale
    @FocusState private var fieldFocused: Bool

    private var isDuplicate: Bool { duplicateName != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            HStack(alignment: .firstTextBaseline, spacing: SETSpacing.x3) {
                Text(isDuplicate ? SETCopyKey.libraryDuplicateTitle.localizedTextKey : SETCopyKey.libraryCreateTitle.localizedTextKey)
                    .font(SETTypography.font(.display, size: SETTypographySize.title))
                    .fontWeight(.bold)
                    .setDisplayTracking()
                    .foregroundStyle(.setTextPrimary)

                if isDuplicate, let duplicateName {
                    Text(
                        SETLibraryLocalizedCopy.formatted(
                            .libraryDuplicateDetail,
                            locale: locale,
                            arguments: [duplicateName]
                        )
                    )
                    .font(SETTypography.uiBodyFont())
                    .foregroundStyle(.setTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(SETLibraryAccessibilityID.duplicateNotice)
                }
            }

            ZStack(alignment: .bottom) {
                TextField(
                    "",
                    text: $model.createDraft,
                    prompt: Text(SETCopyKey.libraryCreatePlaceholder.localizedTextKey)
                        .foregroundStyle(.setTextTertiary)
                )
                .font(SETTypography.font(.screenplay, size: SETTypographySize.body))
                .foregroundStyle(.setTextPrimary)
                .padding(SETSpacing.x3)
                .background(Color.setSurfaceSolid)
                .overlay {
                    Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
                }
                .focused($fieldFocused)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .onSubmit { model.confirmCreate() }
                .accessibilityIdentifier(SETLibraryAccessibilityID.createField)

                if isDuplicate {
                    // One circle annotation around the conflicting name.
                    GlassMarkGuide(kind: .outline, color: .setOrange)
                        .padding(SETSpacing.x1)
                } else {
                    // Underline annotation on the active field.
                    GlassMarkGuide(kind: .underline, color: fieldFocused ? .setOrange : .setHairline)
                        .frame(height: SETSpacing.x2)
                        .padding(.horizontal, SETSpacing.x2)
                }
            }

            HStack(spacing: SETSpacing.x4) {
                SETDigitalAction(title: .libraryCreateConfirm, action: { model.confirmCreate() })
                    .accessibilityIdentifier(SETLibraryAccessibilityID.createConfirm)

                Button(action: { model.cancelCreate() }) {
                    Text(SETCopyKey.libraryCancel.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .foregroundStyle(.setTextSecondary)
                        .underline()
                        .padding(.horizontal, SETSpacing.x3)
                        .frame(minHeight: SETComponentMetric.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(SETLibraryAccessibilityID.createCancel)
            }
        }
        .padding(SETSpacing.x4)
        .background(Color.setSurfaceSolid)
        .overlay(alignment: .topLeading) {
            // One registration mark punctuates the create surface.
            SETRegistrationMarks(corner: .topLeading)
                .frame(width: SETComponentMetric.registrationMarkLength * 2, height: SETComponentMetric.registrationMarkLength * 2)
                .padding(SETSpacing.x2)
        }
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
    }
}

// MARK: - Delete confirmation (`library.delete-confirmation`)

private struct SETLibraryDeletePanel: View {
    @ObservedObject var model: SETLibraryModel
    let sceneName: String

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            Text(SETCopyKey.libraryDeleteTitle.localizedTextKey)
                .font(SETTypography.font(.display, size: SETTypographySize.title))
                .fontWeight(.bold)
                .setDisplayTracking()
                .foregroundStyle(.setTextPrimary)

            ZStack(alignment: .leading) {
                Text(
                    SETLibraryLocalizedCopy.formatted(
                        .libraryDeleteDetail,
                        locale: locale,
                        arguments: [sceneName]
                    )
                )
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, SETSpacing.x1)

                // One bracket annotation on the scene identity.
                GlassMarkGuide(kind: .bracket, color: .setWarmWhite)
                    .padding(SETSpacing.x1)
            }

            HStack(spacing: SETSpacing.x4) {
                SETDigitalAction(title: .libraryDelete, action: { model.confirmDelete() })
                    .accessibilityIdentifier(SETLibraryAccessibilityID.deleteConfirm)

                Button(action: { model.cancelDelete() }) {
                    Text(SETCopyKey.libraryCancel.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .foregroundStyle(.setTextSecondary)
                        .underline()
                        .padding(.horizontal, SETSpacing.x3)
                        .frame(minHeight: SETComponentMetric.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(SETLibraryAccessibilityID.deleteCancel)
            }
        }
        .padding(SETSpacing.x4)
        .background(Color.setSurfaceSolid)
        .overlay(alignment: .top) {
            // One cut-mark line accents the destructive boundary.
            CutSeam(axis: .horizontal)
        }
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
    }
}

// MARK: - Persistence failure (`library.persistence-failure`)

private struct SETLibraryFailurePanel: View {
    @ObservedObject var model: SETLibraryModel
    let kind: SETLibraryModel.FailureKind

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            Text(titleKey.localizedTextKey)
                .font(SETTypography.font(.display, size: SETTypographySize.title))
                .fontWeight(.bold)
                .setDisplayTracking()
                .foregroundStyle(.setTextPrimary)

            Text(detailKey.localizedTextKey)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .bottom) {
                SETDigitalAction(title: .retry, action: { model.retry() })
                    .accessibilityIdentifier(SETLibraryAccessibilityID.failureRetry)

                // One underline annotation on the recovery action.
                GlassMarkGuide(kind: .underline, color: .setOrange)
                    .frame(height: SETSpacing.x2)
                    .padding(.horizontal, SETSpacing.x2)
                    .offset(y: SETSpacing.x1)
            }
            .frame(maxWidth: SETComponentMetric.gallerySectionMaxWidth, alignment: .leading)
        }
        .padding(SETSpacing.x4)
        .background(Color.setSurfaceSolid)
        .overlay(alignment: .top) {
            CutSeam(axis: .horizontal)
        }
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
    }

    private var titleKey: SETCopyKey {
        kind == .create ? .libraryFailureTitle : .libraryFailureDeleteTitle
    }

    private var detailKey: SETCopyKey {
        kind == .create ? .libraryFailureDetail : .libraryFailureDeleteDetail
    }
}
