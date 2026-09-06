import AVFoundation
import SwiftUI

// MARK: - Ownership contract

/// Failure vocabulary shared by the Library presentation owner and the
/// persistence owner. The associated identity/snapshot values keep recovery
/// actionable without leaking raw NSError values into the UI.
enum SETLibraryFailure: Error, Equatable, Sendable {
    case invalidName
    case duplicateName(name: String, conflictingID: UUID?)
    case missingProject(id: UUID?)
    case staleSnapshot(expectedUpdatedAt: Date, storedUpdatedAt: Date)
    case inUse
    case persistence
    case artifactCleanup
    case previewUnavailable
    case unsupported
}

enum SETLibraryArtifactHealth: String, Codable, Equatable, Sendable {
    case none
    case healthy
    case missing
    case corrupt
    case unavailable
}

/// Preview data is deliberately metadata-only until a real project-owned
/// media preview exists. No fixture image or inferred thumbnail belongs here.
struct SETLibraryPreviewMetadata: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case storyboard
        case screenplay
        case metadataOnly = "metadata-only"
        case unavailable
    }

    let kind: Kind
    let beatCount: Int
    let actorCount: Int
    let objectCount: Int
    let recordingCount: Int
    /// Set only when the persistence owner resolved an existing, project-owned
    /// recording. Absence is the honest metadata-placeholder path.
    let recordingReference: SceneRecordingReference?

    init(
        kind: Kind,
        beatCount: Int,
        actorCount: Int,
        objectCount: Int,
        recordingCount: Int,
        recordingReference: SceneRecordingReference? = nil
    ) {
        self.kind = kind
        self.beatCount = beatCount
        self.actorCount = actorCount
        self.objectCount = objectCount
        self.recordingCount = recordingCount
        self.recordingReference = recordingReference
    }

    static let unavailable = SETLibraryPreviewMetadata(
        kind: .unavailable,
        beatCount: 0,
        actorCount: 0,
        objectCount: 0,
        recordingCount: 0,
        recordingReference: nil
    )
}

struct SETLibrarySceneSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let updatedAt: Date
    let preview: SETLibraryPreviewMetadata
    let artifactHealth: SETLibraryArtifactHealth

    init(
        id: UUID,
        name: String,
        updatedAt: Date,
        preview: SETLibraryPreviewMetadata = .unavailable,
        artifactHealth: SETLibraryArtifactHealth = .unavailable
    ) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.preview = preview
        self.artifactHealth = artifactHealth
    }
}

/// Projection-only bridge from the existing library behavior owners
/// (`SOViewController` + `SOPresenter`/`SOInteractor` + `SORouter`). The SET OS
/// surface never becomes a new state owner: listing, persistence and routing
/// stay behind this protocol.
protocol SETLibrarySceneProviding: AnyObject {
    func librarySceneSummaries() -> [UnifiedSceneProjectSummary]
    func libraryCreateScene(named name: String) -> SETLibraryCreateOutcome
    func libraryDeleteScene(named name: String, completion: @escaping (Bool) -> Void)
    func libraryOpenScene(named name: String)

    /// Typed Package 3 contract. The legacy methods above remain available to
    /// old callers; production models use these Result-based projections.
    func librarySceneSnapshots() -> Result<[SETLibrarySceneSnapshot], SETLibraryFailure>
    func libraryCreateSceneResult(named name: String) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure>
    func libraryRenameSceneResult(
        id: UUID,
        to name: String,
        expectedUpdatedAt: Date
    ) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure>
    func libraryDeleteSceneResult(
        id: UUID,
        expectedUpdatedAt: Date,
        completion: @escaping (Result<Void, SETLibraryFailure>) -> Void
    )
    func libraryOpenSceneResult(id: UUID) -> Result<Void, SETLibraryFailure>
}

enum SETLibraryCreateOutcome: Equatable, Sendable {
    case created
    case invalidName
    case duplicateName
    case persistenceFailure
}

extension SETLibrarySceneProviding {
    func librarySceneSnapshots() -> Result<[SETLibrarySceneSnapshot], SETLibraryFailure> {
        .success(librarySceneSummaries().map {
            SETLibrarySceneSnapshot(id: $0.id, name: $0.name, updatedAt: $0.updatedAt)
        })
    }

    func libraryCreateSceneResult(named name: String) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        switch libraryCreateScene(named: name) {
        case .created:
            guard let summary = librarySceneSummaries().first(where: { $0.name == name }) else {
                return .failure(.persistence)
            }
            return .success(SETLibrarySceneSnapshot(id: summary.id, name: summary.name, updatedAt: summary.updatedAt))
        case .invalidName:
            return .failure(.invalidName)
        case .duplicateName:
            return .failure(.duplicateName(name: name, conflictingID: nil))
        case .persistenceFailure:
            return .failure(.persistence)
        }
    }

    func libraryRenameSceneResult(
        id: UUID,
        to name: String,
        expectedUpdatedAt: Date
    ) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        .failure(.unsupported)
    }

    func libraryDeleteSceneResult(
        id: UUID,
        expectedUpdatedAt: Date,
        completion: @escaping (Result<Void, SETLibraryFailure>) -> Void
    ) {
        guard let summary = librarySceneSummaries().first(where: { $0.id == id }) else {
            completion(.failure(.missingProject(id: id)))
            return
        }
        libraryDeleteScene(named: summary.name) { deleted in
            completion(deleted ? .success(()) : .failure(.persistence))
        }
    }

    func libraryOpenSceneResult(id: UUID) -> Result<Void, SETLibraryFailure> {
        guard let summary = librarySceneSummaries().first(where: { $0.id == id }) else {
            return .failure(.missingProject(id: id))
        }
        libraryOpenScene(named: summary.name)
        return .success(())
    }
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
        case renaming(sceneID: UUID, sceneName: String)
        case renameDuplicate(conflictingName: String)
        case deleting(sceneID: UUID, sceneName: String, expectedUpdatedAt: Date)
        case failure(FailureKind)
    }

    enum FailureKind: Equatable {
        case load(SETLibraryFailure)
        case create(SETLibraryFailure)
        case rename(SETLibraryFailure)
        case delete(SETLibraryFailure)
        case open(SETLibraryFailure)
    }

    private enum RetryOperation: Equatable {
        case load
        case create(name: String)
        case rename(id: UUID, name: String, expectedUpdatedAt: Date)
        case delete(id: UUID, name: String, expectedUpdatedAt: Date)
        case open(id: UUID)
    }

    struct SceneRow: Identifiable, Equatable {
        let id: UUID
        let name: String
        let updatedAt: Date
        let preview: SETLibraryPreviewMetadata
        let artifactHealth: SETLibraryArtifactHealth

        init(snapshot: SETLibrarySceneSnapshot) {
            id = snapshot.id
            name = snapshot.name
            updatedAt = snapshot.updatedAt
            preview = snapshot.preview
            artifactHealth = snapshot.artifactHealth
        }
    }

    @Published private(set) var scenes: [SceneRow] = []
    @Published private(set) var hasLoadedSuccessfully = false
    @Published private(set) var selectedSceneID: UUID?
    @Published private(set) var flow: FlowState = .idle
    @Published var createDraft: String = ""
    @Published var renameDraft: String = ""

    let controlling: SETLibrarySceneProviding

    /// Retry context captures the immutable identity and snapshot used by the
    /// failed operation; retry never re-derives a delete/rename from selection.
    private var pendingRetry: RetryOperation?

    init(controlling: SETLibrarySceneProviding) {
        self.controlling = controlling
    }

    var selectedScene: SceneRow? {
        scenes.first { $0.id == selectedSceneID }
    }

    /// A load failure is a recovery hero, even when a previous projection is
    /// still present. Keeping this decision in the model makes the rendering
    /// rule testable without a UI harness and prevents an empty-state branch
    /// from masking persistence failure.
    var loadFailure: FailureKind? {
        guard case .failure(let kind) = flow,
              case .load = kind else { return nil }
        return kind
    }

    var shouldShowEmptyState: Bool {
        hasLoadedSuccessfully && scenes.isEmpty && flow == .idle && loadFailure == nil
    }

    func reload() {
        switch controlling.librarySceneSnapshots() {
        case .success(let snapshots):
            hasLoadedSuccessfully = true
            scenes = orderedRows(from: snapshots)
            if case .failure(.load) = flow {
                pendingRetry = nil
                flow = .idle
            } else if flow == .idle {
                pendingRetry = nil
            }
        case .failure(let failure):
            pendingRetry = .load
            flow = .failure(.load(failure))
            return
        }
        if let selectedSceneID, !scenes.contains(where: { $0.id == selectedSceneID }) {
            self.selectedSceneID = nil
        }
        if case .deleting(let id, _, _) = flow, !scenes.contains(where: { $0.id == id }) {
            flow = .idle
        }
    }

    private func orderedRows(from snapshots: [SETLibrarySceneSnapshot]) -> [SceneRow] {
        snapshots.map(SceneRow.init).sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func select(_ id: UUID) {
        guard flow == .idle else { return }
        selectedSceneID = id
    }

    func openSelectedScene() {
        guard let selectedScene else { return }
        openScene(id: selectedScene.id)
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
        guard !trimmed.isEmpty else {
            flow = .failure(.create(.invalidName))
            pendingRetry = .create(name: trimmed)
            return
        }
        if scenes.contains(where: { $0.name == trimmed }) {
            flow = .duplicate(conflictingName: trimmed)
            return
        }
        performCreate(named: trimmed)
    }

    private func performCreate(named name: String) {
        switch controlling.libraryCreateSceneResult(named: name) {
        case .success(let snapshot):
            scenes.removeAll { $0.id == snapshot.id }
            scenes.append(SceneRow(snapshot: snapshot))
            scenes.sort {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            selectedSceneID = snapshot.id
            switch controlling.libraryOpenSceneResult(id: snapshot.id) {
            case .success:
                pendingRetry = nil
                flow = .idle
            case .failure(let failure):
                pendingRetry = .open(id: snapshot.id)
                flow = .failure(.open(failure))
            }
        case .failure(let failure):
            if case .duplicateName(let conflictingName, _) = failure {
                flow = .duplicate(conflictingName: conflictingName)
                pendingRetry = nil
            } else {
                pendingRetry = .create(name: name)
                flow = .failure(.create(failure))
            }
        }
    }

    func beginDelete(sceneName: String) {
        guard let scene = scenes.first(where: { $0.name == sceneName }) else {
            flow = .failure(.delete(.missingProject(id: nil)))
            return
        }
        beginDelete(sceneID: scene.id)
    }

    func beginDelete(sceneID: UUID) {
        guard flow == .idle, let scene = scenes.first(where: { $0.id == sceneID }) else { return }
        selectedSceneID = scene.id
        flow = .deleting(sceneID: scene.id, sceneName: scene.name, expectedUpdatedAt: scene.updatedAt)
    }

    func cancelDelete() {
        guard case .deleting = flow else { return }
        flow = .idle
    }

    func confirmDelete() {
        guard case .deleting(let id, let name, let expectedUpdatedAt) = flow else { return }
        pendingRetry = .delete(id: id, name: name, expectedUpdatedAt: expectedUpdatedAt)
        controlling.libraryDeleteSceneResult(id: id, expectedUpdatedAt: expectedUpdatedAt) { [weak self] result in
            Task { @MainActor in
                self?.handleDeleteResult(result, id: id, sceneName: name, expectedUpdatedAt: expectedUpdatedAt)
            }
        }
    }

    private func handleDeleteResult(
        _ result: Result<Void, SETLibraryFailure>,
        id: UUID,
        sceneName: String,
        expectedUpdatedAt: Date
    ) {
        guard case .deleting(let flowID, let flowName, let flowUpdatedAt) = flow,
              flowID == id,
              flowName == sceneName,
              flowUpdatedAt == expectedUpdatedAt else { return }
        switch result {
        case .success:
            flow = .idle
            reload()
        case .failure(let failure):
            pendingRetry = .delete(id: id, name: sceneName, expectedUpdatedAt: expectedUpdatedAt)
            flow = .failure(.delete(failure))
        }
    }

    func beginRename(sceneID: UUID) {
        guard flow == .idle, let scene = scenes.first(where: { $0.id == sceneID }) else { return }
        selectedSceneID = scene.id
        renameDraft = scene.name
        flow = .renaming(sceneID: scene.id, sceneName: scene.name)
    }

    func cancelRename() {
        guard isRenameFlow || isRenameDuplicateFlow else { return }
        renameDraft = ""
        flow = .idle
    }

    private var isRenameFlow: Bool {
        if case .renaming = flow { return true }
        return false
    }

    private var isRenameDuplicateFlow: Bool {
        if case .renameDuplicate = flow { return true }
        return false
    }

    func confirmRename() {
        guard case .renaming(let id, _) = flow,
              let scene = scenes.first(where: { $0.id == id }) else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pendingRetry = .rename(id: id, name: trimmed, expectedUpdatedAt: scene.updatedAt)
            flow = .failure(.rename(.invalidName))
            return
        }
        if scenes.contains(where: { $0.id != id && $0.name == trimmed }) {
            flow = .renameDuplicate(conflictingName: trimmed)
            return
        }
        performRename(id: id, name: trimmed, expectedUpdatedAt: scene.updatedAt)
    }

    private func performRename(id: UUID, name: String, expectedUpdatedAt: Date) {
        switch controlling.libraryRenameSceneResult(id: id, to: name, expectedUpdatedAt: expectedUpdatedAt) {
        case .success(let snapshot):
            scenes = scenes.map { $0.id == id ? SceneRow(snapshot: snapshot) : $0 }
            scenes.sort {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            renameDraft = ""
            pendingRetry = nil
            flow = .idle
        case .failure(let failure):
            if case .duplicateName(let conflictingName, _) = failure {
                flow = .renameDuplicate(conflictingName: conflictingName)
                pendingRetry = nil
            } else {
                pendingRetry = .rename(id: id, name: name, expectedUpdatedAt: expectedUpdatedAt)
                flow = .failure(.rename(failure))
            }
        }
    }

    private func openScene(id: UUID) {
        switch controlling.libraryOpenSceneResult(id: id) {
        case .success:
            pendingRetry = nil
            flow = .idle
        case .failure(let failure):
            pendingRetry = .open(id: id)
            flow = .failure(.open(failure))
        }
    }

    func retry() {
        let operation = pendingRetry
        pendingRetry = nil
        switch operation {
        case .load:
            reload()
        case .create(let name):
            createDraft = name
            flow = .creating
            performCreate(named: name)
        case .rename(let id, let name, let expectedUpdatedAt):
            renameDraft = name
            flow = .renaming(sceneID: id, sceneName: name)
            performRename(id: id, name: name, expectedUpdatedAt: expectedUpdatedAt)
        case .delete(let id, let name, let expectedUpdatedAt):
            flow = .deleting(sceneID: id, sceneName: name, expectedUpdatedAt: expectedUpdatedAt)
            confirmDelete()
        case .open(let id):
            openScene(id: id)
        case nil:
            flow = .idle
        }
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

    func librarySceneSnapshots() -> Result<[SETLibrarySceneSnapshot], SETLibraryFailure> {
        .success(scenes.map {
            SETLibrarySceneSnapshot(
                id: $0.id,
                name: $0.name,
                updatedAt: $0.updatedAt,
                preview: SETLibraryPreviewMetadata(
                    kind: .metadataOnly,
                    beatCount: 0,
                    actorCount: 0,
                    objectCount: 0,
                    recordingCount: 0
                ),
                artifactHealth: .unavailable
            )
        })
    }

    func libraryCreateSceneResult(named name: String) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        switch libraryCreateScene(named: name) {
        case .created:
            guard let summary = scenes.first(where: { $0.name == name }) else { return .failure(.persistence) }
            return librarySceneSnapshots().flatMap { snapshots in
                guard let snapshot = snapshots.first(where: { $0.id == summary.id }) else { return .failure(.persistence) }
                return .success(snapshot)
            }
        case .invalidName: return .failure(.invalidName)
        case .duplicateName: return .failure(.duplicateName(name: name, conflictingID: scenes.first(where: { $0.name == name })?.id))
        case .persistenceFailure: return .failure(.persistence)
        }
    }

    func libraryRenameSceneResult(
        id: UUID,
        to name: String,
        expectedUpdatedAt: Date
    ) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidName) }
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return .failure(.missingProject(id: id)) }
        guard scenes[index].updatedAt == expectedUpdatedAt else {
            return .failure(.staleSnapshot(expectedUpdatedAt: expectedUpdatedAt, storedUpdatedAt: scenes[index].updatedAt))
        }
        if let duplicate = scenes.first(where: { $0.id != id && $0.name == trimmed }) {
            return .failure(.duplicateName(name: trimmed, conflictingID: duplicate.id))
        }
        scenes[index] = UnifiedSceneProjectSummary(id: id, name: trimmed, updatedAt: Date())
        return librarySceneSnapshots().flatMap { snapshots in
            guard let snapshot = snapshots.first(where: { $0.id == id }) else { return .failure(.persistence) }
            return .success(snapshot)
        }
    }

    func libraryDeleteSceneResult(
        id: UUID,
        expectedUpdatedAt: Date,
        completion: @escaping (Result<Void, SETLibraryFailure>) -> Void
    ) {
        guard let scene = scenes.first(where: { $0.id == id }) else {
            completion(.failure(.missingProject(id: id)))
            return
        }
        guard scene.updatedAt == expectedUpdatedAt else {
            completion(.failure(.staleSnapshot(expectedUpdatedAt: expectedUpdatedAt, storedUpdatedAt: scene.updatedAt)))
            return
        }
        libraryDeleteScene(named: scene.name) { deleted in
            completion(deleted ? .success(()) : .failure(.persistence))
        }
    }

    func libraryOpenSceneResult(id: UUID) -> Result<Void, SETLibraryFailure> {
        guard let scene = scenes.first(where: { $0.id == id }) else { return .failure(.missingProject(id: id)) }
        libraryOpenScene(named: scene.name)
        return .success(())
    }
}

enum SETLibraryFixtureData {
    /// Fixed GMT timestamps keep fixture metadata deterministic across runs.
    static let dates: [Date] = [
        Date(timeIntervalSince1970: 1_786_984_800), // 2026-08-17 21:09 GMT minus fixture drift
        Date(timeIntervalSince1970: 1_787_041_320),
        Date(timeIntervalSince1970: 1_787_134_700)
    ]

    static let ids = [
        UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
        UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    ]

    static func summaries(locale: Locale) -> [UnifiedSceneProjectSummary] {
        let nameKeys: [SETCopyKey] = [.librarySceneOne, .librarySceneTwo, .librarySceneThree]
        return zip(zip(nameKeys, dates), ids).map { value, id in
            let (key, date) = value
            return UnifiedSceneProjectSummary(
                id: id,
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

    static func sceneAccessibilityValue(
        scene: SETLibraryModel.SceneRow,
        locale: Locale
    ) -> String {
        "\(scene.id.uuidString) · \(previewStatus(scene.preview).localizedString(locale: locale)) · " +
            "\(artifactStatus(scene.artifactHealth).localizedString(locale: locale)) · " +
            updatedLabel(for: scene.updatedAt, locale: locale)
    }

    private static func previewStatus(_ preview: SETLibraryPreviewMetadata) -> SETCopyKey {
        // A content kind without an owned, resolvable source is metadata only;
        // announce the honest fallback instead of implying a media preview.
        if preview.recordingReference == nil {
            return .libraryPreviewMetadataPlaceholder
        }
        switch preview.kind {
        case .storyboard, .screenplay, .metadataOnly, .unavailable:
            return .libraryPreviewRecording
        }
    }

    private static func artifactStatus(_ health: SETLibraryArtifactHealth) -> SETCopyKey {
        switch health {
        case .none: return .libraryArtifactNone
        case .healthy: return .libraryArtifactHealthy
        case .missing: return .libraryArtifactMissing
        case .corrupt: return .libraryArtifactCorrupt
        case .unavailable: return .libraryArtifactUnavailable
        }
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
    static let failureTitle = "library_failure_title"
    static let failureDetail = "library_failure_detail"
    static let sceneDelete = "library_scene_delete"
    static let sceneOpen = "library_scene_open"
    static let sceneRename = "library_scene_rename"
    static let scenePreview = "library_scene_preview"
    static let deleteDetail = "library_delete_detail"
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
        let scenes = configuration.fixtureID == "library.empty"
            ? []
            : SETLibraryFixtureData.summaries(locale: configuration.locale)
        let provider = SETLibraryFixtureProvider(
            scenes: scenes,
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
            break
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
            model.beginDelete(sceneID: scene.id)
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

                if let loadFailure = model.loadFailure {
                    SETLibraryFailurePanel(model: model, kind: loadFailure)
                        .frame(maxHeight: .infinity)
                } else if model.shouldShowEmptyState {
                    SETLibraryEmptyState(model: model)
                        .frame(maxHeight: .infinity)
                } else if !model.hasLoadedSuccessfully || model.scenes.isEmpty {
                    // A pre-load or mutation-failure surface has no honest row
                    // content to render. Keep the empty hero reserved for a
                    // successful zero-project load.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SETLibrarySceneList(model: model, locale: locale)
                        .frame(maxHeight: .infinity)
                }

                if model.hasLoadedSuccessfully && model.loadFailure == nil {
                    flowPanel
                }
            }
            .padding(SETSpacing.x4)
            .overlay(alignment: .topTrailing) {
                if model.shouldShowEmptyState {
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
        case .renaming, .renameDuplicate:
            // Rename presentation is owned by the later Library rename slice;
            // the contract still keeps these states distinct here.
            EmptyView()
        case .deleting(_, let sceneName, _):
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
                .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// M10-008: regular width uses a two-column contact sheet for density
    /// without stretching phone rows; compact degrades intentionally to the
    /// single column. Reading order stays row-major in both.
    private var columnCount: Int {
        horizontalSizeClass == .regular ? 2 : 1
    }

    var body: some View {
        ScrollView {
            if columnCount == 1 {
                singleColumn
            } else {
                doubleColumn
            }
        }
        .accessibilityIdentifier(SETLibraryAccessibilityID.list)
    }

    private var singleColumn: some View {
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
                    onRename: {
                        model.select(scene.id)
                        model.beginRename(sceneID: scene.id)
                    },
                    onDelete: {
                        model.select(scene.id)
                        model.beginDelete(sceneID: scene.id)
                    }
                )
            }
            .overlay {
                Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
            }
        }
    }

    private var doubleColumn: some View {
        let rows = Array(model.scenes.enumerated())
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
            spacing: 0
        ) {
            ForEach(rows, id: \.element.id) { index, scene in
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
                    onRename: {
                        model.select(scene.id)
                        model.beginRename(sceneID: scene.id)
                    },
                    onDelete: {
                        model.select(scene.id)
                        model.beginDelete(sceneID: scene.id)
                    }
                )
            }
        }
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
    }
}

private struct SETLibrarySceneRow: View {
    let scene: SETLibraryModel.SceneRow
    let position: Int
    let isSelected: Bool
    let locale: Locale
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride

    private var isMotionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Button(action: onSelect) {
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
                .padding(.horizontal, SETSpacing.x4)
                .padding(.vertical, isSelected ? SETSpacing.x3 : SETSpacing.x2)
                .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilitySortPriority(4)
            .accessibilityLabel(Text(scene.name))
            .accessibilityValue(
                Text(SETLibraryLocalizedCopy.sceneAccessibilityValue(scene: scene, locale: locale))
            )
            .accessibilityIdentifier(SETLibraryAccessibilityID.sceneRow(at: position))

            if isSelected {
                selectedContent
                    .padding(.horizontal, SETSpacing.x4)
                    .padding(.bottom, SETSpacing.x3)
            }
        }
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
        .animation(
            isMotionReduced
                ? .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)
                : SETMotion.reflowSpring,
            value: isSelected
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectedContent: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            SETLibraryScenePreview(preview: scene.preview, locale: locale)

            // The row itself is the selection target. These controls are its
            // sibling actions, with a vertical fallback that cannot overlap
            // on compact portrait widths.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SETSpacing.x4) {
                    openAction
                    renameAction
                    deleteAction
                }
                VStack(alignment: .leading, spacing: SETSpacing.x2) {
                    openAction
                    renameAction
                    deleteAction
                }
            }
            .accessibilityElement(children: .contain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openAction: some View {
        SETDigitalAction(title: .libraryOpen, action: onOpen)
            .frame(minWidth: 96, minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityIdentifier(SETLibraryAccessibilityID.sceneOpen)
            .accessibilitySortPriority(3)
    }

    private var renameAction: some View {
        Button(action: onRename) {
            Text(SETCopyKey.libraryRename.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .foregroundStyle(.setTextSecondary)
                .underline()
                .padding(.horizontal, SETSpacing.x3)
                .frame(minWidth: 96, minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(SETLibraryAccessibilityID.sceneRename)
        .accessibilityLabel(
            Text(
                SETLibraryLocalizedCopy.formatted(
                    .accessibilityLibraryRenameScene,
                    locale: locale,
                    arguments: [scene.name]
                )
            )
        )
        .accessibilitySortPriority(2)
    }

    private var deleteAction: some View {
        Button(action: onDelete) {
            Text(SETCopyKey.libraryDelete.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .foregroundStyle(.setTextSecondary)
                .underline()
                .padding(.horizontal, SETSpacing.x3)
                .frame(minWidth: 96, minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
        .accessibilitySortPriority(1)
    }
}

/// Resolves one project-owned recording into a poster frame on demand. The
/// fallback is metadata-only and carries no synthetic image or fixture art.
private struct SETLibraryScenePreview: View {
    let preview: SETLibraryPreviewMetadata
    let locale: Locale

    @State private var image: CGImage?

    private var sourceKey: String {
        preview.recordingReference?.relativePath ?? "metadata"
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text(SETCopyKey.libraryPreviewRecording.localizedString(locale: locale)))
            } else {
                metadataPlaceholder
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 180, alignment: .leading)
        .accessibilityIdentifier(SETLibraryAccessibilityID.scenePreview)
        .task(id: sourceKey) {
            image = await loadPosterFrame()
        }
    }

    private var metadataPlaceholder: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(SETCopyKey.libraryPreviewMetadataPlaceholder.localizedString(locale: locale))
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .tracking(0.35)
                .foregroundStyle(.setTextPrimary)
                .accessibilityHidden(true)
            Text(
                SETCopyKey.libraryPreviewMetadataDetail.localizedFormat(
                    locale: locale,
                    arguments: [
                        preview.beatCount,
                        preview.actorCount,
                        preview.objectCount,
                        preview.recordingCount
                    ]
                )
            )
            .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
            .foregroundStyle(.setTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SETSpacing.x3)
        .background(Color.setSurfaceSolid)
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
        // Expose one deterministic VoiceOver element. The explicit label and
        // value below already carry the two visible text nodes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SETCopyKey.libraryPreviewMetadataPlaceholder.localizedString(locale: locale)))
        .accessibilityValue(
            Text(
                SETCopyKey.libraryPreviewMetadataDetail.localizedFormat(
                    locale: locale,
                    arguments: [
                        preview.beatCount,
                        preview.actorCount,
                        preview.objectCount,
                        preview.recordingCount
                    ]
                )
            )
        )
    }

    private func loadPosterFrame() async -> CGImage? {
        guard let reference = preview.recordingReference else { return nil }
        return await Task.detached(priority: .utility) {
            guard let store = try? RecordingArtifactStore(),
                  let url = store.resolve(reference),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value > 0 else {
                return nil
            }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 768, height: 432)
            return try? generator.copyCGImage(
                at: CMTime(seconds: 0, preferredTimescale: 600),
                actualTime: nil
            )
        }.value
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
        // This is visual annotation only. The selected row already owns the
        // canonical `.isSelected` trait; exposing the marker creates a second
        // VoiceOver element with the same meaning.
        .accessibilityHidden(true)
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
                    .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
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
                .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
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
                .accessibilityIdentifier(SETLibraryAccessibilityID.deleteDetail)

                // One bracket annotation on the scene identity.
                GlassMarkGuide(kind: .bracket, color: .setWarmWhite)
                    .padding(SETSpacing.x1)
            }

            HStack(spacing: SETSpacing.x4) {
                SETDigitalAction(title: .libraryDelete, action: { model.confirmDelete() })
                    .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
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
                .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
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
                .accessibilityIdentifier(SETLibraryAccessibilityID.failureTitle)

            Text(detailKey.localizedTextKey)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(SETLibraryAccessibilityID.failureDetail)

            ZStack(alignment: .bottom) {
                SETDigitalAction(title: .retry, action: { model.retry() })
                    .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
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
        switch kind {
        case .delete: return .libraryFailureDeleteTitle
        case .load, .create, .rename, .open: return .libraryFailureTitle
        }
    }

    private var detailKey: SETCopyKey {
        switch kind {
        case .delete: return .libraryFailureDeleteDetail
        case .load, .create, .rename, .open: return .libraryFailureDetail
        }
    }
}
