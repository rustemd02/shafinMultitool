//
//  SceneGeneratorViewModel.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import Foundation
import SwiftUI
import Combine
import ARKit
import RealityKit
import CoreMedia
import ImageIO
import UIKit

struct BeatPlaybackTimelineItem: Identifiable, Equatable {
    var id: String { "\(index)-\(beatID)" }
    let beatID: String
    let index: Int
    let startTime: TimeInterval
    let duration: TimeInterval
    let hasDialogueCaption: Bool
    let hasActionCaption: Bool

    var kindTitle: String {
        if hasDialogueCaption && hasActionCaption { return "сцена" }
        if hasDialogueCaption { return "диалог" }
        if hasActionCaption { return "действие" }
        return "движение"
    }

    var kindCopyKey: SETCopyKey {
        if hasDialogueCaption && hasActionCaption { return .storyboardKindScene }
        if hasDialogueCaption { return .storyboardKindDialogue }
        if hasActionCaption { return .storyboardKindAction }
        return .storyboardKindMovement
    }
}

struct BeatPlaybackProgressState: Equatable {
    let activeBeatIndex: Int
    let beatProgress: Double
    let elapsedTime: TimeInterval
}

enum SceneObjectRenderKind: Equatable {
    case standardPlaceholder
    case phoneProxy
}

struct SceneObjectRenderStyle: Equatable {
    let kind: SceneObjectRenderKind
    let targetCueRadius: Float
}

struct ARObjectLabelPresentation: Identifiable, Equatable {
    let id: String
    let text: String
    let x: CGFloat
    let y: CGFloat
    let tint: SIMD3<Float>
    let priority: Int

    var position: CGPoint {
        CGPoint(x: x, y: y)
    }

    var swiftUIColor: Color {
        Color(
            red: Double(tint.x),
            green: Double(tint.y),
            blue: Double(tint.z)
        )
    }

    func withPosition(x: CGFloat, y: CGFloat) -> ARObjectLabelPresentation {
        ARObjectLabelPresentation(id: id, text: text, x: x, y: y, tint: tint, priority: priority)
    }
}

struct StoryboardEntityOption: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case none
        case actor
        case object
    }

    let id: String
    let label: String
    let kind: Kind
}

struct StoryboardBeatPresentationItem: Identifiable, Equatable {
    var id: String { beatID }
    let beatID: String
    let index: Int
    let kindTitle: String
    let summary: String
    let hasDialogueCaption: Bool
    let hasActionCaption: Bool
    let actionCount: Int

    var kindCopyKey: SETCopyKey {
        switch kindTitle {
        case "сцена": .storyboardKindScene
        case "диалог": .storyboardKindDialogue
        case "действие": .storyboardKindAction
        default: .storyboardKindMovement
        }
    }
}

struct StoryboardActionEditDraft: Identifiable, Equatable {
    let id: String
    var actorId: String
    var type: SceneAction.ActionType
    var target: String?
    var text: String
    var isDeleted: Bool = false
    var isNew: Bool = false
}

struct StoryboardBeatEditDraft: Identifiable, Equatable {
    var id: String { beatID }
    let beatID: String
    var title: String
    var actions: [StoryboardActionEditDraft]
    var actorOptions: [StoryboardEntityOption]
    var targetOptions: [StoryboardEntityOption]
}

enum StoryboardValidationField: Equatable {
    case actor(actionID: String)
    case target(actionID: String)
}

struct StoryboardBeatInspectorPresentation: Equatable {
    let kindTitle: String
    let summary: String
    let durationText: String
    let actorLabels: [String]
    let targetLabels: [String]
    let warnings: [String]
    let dragHint: String

    var kindCopyKey: SETCopyKey {
        switch kindTitle {
        case "сцена": .storyboardKindScene
        case "диалог": .storyboardKindDialogue
        case "действие": .storyboardKindAction
        default: .storyboardKindMovement
        }
    }
}

struct SceneActorRenderStyle: Equatable {
    let color: SIMD3<Float>
    let paletteIndex: Int

    var uiColor: UIColor {
        UIColor(
            red: CGFloat(color.x),
            green: CGFloat(color.y),
            blue: CGFloat(color.z),
            alpha: 1.0
        )
    }
}

enum SceneWorkspaceMode: Equatable {
    case editingScene
    case marking
    case generatedReady
    case shooting
    case recording
    case previewPlayback
}

enum SceneRecordingPermissionRecovery: Equatable {
    case openSettings
    case recheck
}

enum SceneGenerationStage: String, Codable, CaseIterable, Equatable {
    case reading
    case planning
    case placing
}

/// Bridges callback-only ARKit APIs into one cancellable, bounded result.
///
/// ARSession may call its completion on a framework-owned queue, may call it
/// after a timeout, or may never call it on unsupported configurations. The
/// resolver is deliberately small: callback, timeout and cancellation all
/// commit through the same lock and only the first terminal outcome resumes
/// the waiting task.
final class SETWorldMapCaptureResolver<Value>: @unchecked Sendable {
    typealias Outcome = Result<Value, SceneWorkspaceTeardownFailure>
    typealias Completion = (Outcome) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var terminalOutcome: Outcome?
    private var timeoutTask: Task<Void, Never>?

    static func resolve(
        timeoutNanoseconds: UInt64,
        request: @escaping (@escaping Completion) -> Void,
        sleep: @escaping @Sendable (UInt64) async -> Void = { interval in
            try? await Task.sleep(nanoseconds: interval)
        }
    ) async -> Outcome {
        let resolver = Self()

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
                resolver.install(continuation)
                request { outcome in
                    resolver.resolve(outcome)
                }
                resolver.scheduleTimeout(
                    nanoseconds: timeoutNanoseconds,
                    sleep: sleep
                )
                if Task.isCancelled {
                    resolver.resolve(.failure(.worldMapSnapshotFailed))
                }
            }
        }, onCancel: {
            resolver.resolve(.failure(.worldMapSnapshotFailed))
        })
    }

    private func install(_ continuation: CheckedContinuation<Outcome, Never>) {
        lock.lock()
        if let terminalOutcome {
            lock.unlock()
            continuation.resume(returning: terminalOutcome)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    private func scheduleTimeout(
        nanoseconds: UInt64,
        sleep: @escaping @Sendable (UInt64) async -> Void
    ) {
        let timeoutTask = Task { [weak self] in
            await sleep(nanoseconds)
            guard !Task.isCancelled else { return }
            self?.resolve(.failure(.worldMapSnapshotFailed))
        }

        lock.lock()
        guard terminalOutcome == nil else {
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    private func resolve(_ outcome: Outcome) {
        lock.lock()
        guard terminalOutcome == nil else {
            lock.unlock()
            return
        }
        terminalOutcome = outcome
        let continuation = self.continuation
        self.continuation = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        continuation?.resume(returning: outcome)
    }
}

/// Trust-boundary result for the screenplay draft. The raw `String` remains
/// untouched so valid Unicode, including composed characters and emoji, is
/// preserved for the parser and project persistence owner.
enum SceneInputValidationIssue: Equatable {
    case empty
    case tooLong(maximum: Int)
    case invalidText
}

/// ViewModel для управления генерацией AR сцены из текстового описания
@MainActor
final class SceneGeneratorViewModel: ObservableObject, SceneWorkspaceTeardownProviding {
    /// The input contract uses user-perceived `Character` units. This keeps
    /// the editor and persistence boundary aligned for RU/EN text and emoji.
    /// Five thousand characters also matches the existing screenplay chunk
    /// smoke boundary without changing the parser or persistence schemas.
    static let maximumSceneDescriptionCharacters = 5_000

    // MARK: - Published Properties
    
    /// Текущее описание сцены
    @Published var sceneDescription: String = ""

    /// Название проекта сцены
    @Published private(set) var sceneTitle: String
    
    /// Распознанный скрипт сцены
    @Published var parsedScript: SceneScript?
    
    /// Результат парсинга с диагностикой
    @Published var parsingResult: ParsingResult?

    /// Компактное состояние сцены между последовательными перегенерациями
    @Published var sceneChunkState: SceneChunkState?
    
    /// Спланированная сцена с координатами
    @Published var plannedScene: PlannedScene?
    
    /// Обнаруженные объекты в кадре
    @Published var detectedObjects: [DetectedObject] = []
    
    /// Размеченные пользователем объекты в реальном пространстве
    @Published var markedObjects: [MarkedObject] = []

    /// Immutable object binding result for the active generator request.
    /// Missing/ambiguous entries remain typed and are never replaced by a
    /// guessed placeholder or array-position match.
    @Published private(set) var objectBindingResult: SceneObjectBindingResult?
    
    /// The request-owned generator state. Compatibility projections below are
    /// updated only by the state owner so a stale task cannot contradict them.
    @Published private(set) var generationRequestState: SceneGenerationRequestState = .idle

    /// Статус генерации (compatibility projection of `generationRequestState`).
    @Published private(set) var isGenerating: Bool = false

    /// Этап генерации, независимый от локализованного текста статуса.
    @Published private(set) var generationStage: SceneGenerationStage?
    
    /// Статус воспроизведения анимации
    @Published var isPlaying: Bool = false

    /// Активный режим unified workspace
    @Published private(set) var workspaceMode: SceneWorkspaceMode = .editingScene

    /// Идёт ли запись видео
    @Published var isRecording: Bool = false

    /// Audio is opt-out and the choice is sampled once at the REC boundary.
    /// It cannot change while a take is starting, recording, or finalizing.
    @Published private(set) var recordingSoundEnabled = true

    /// REC tap has passed the identity gate and is waiting on microphone
    /// permission/writer preparation.
    @Published private(set) var isRecordingStarting: Bool = false

    /// Writer finalization is still in flight after REC is hidden.
    @Published private(set) var isRecordingFinalizing: Bool = false

    /// Latest dimensions observed from the raw AR buffer. AUTO is the honest
    /// value until a source frame has established real dimensions.
    @Published private(set) var recordingResolutionLabel: String = "AUTO"

    /// Actual FPS reported by the active ARSession video format. Recording is
    /// unavailable until this source fact is published.
    @Published private(set) var recordingSourceFPS: Int?
    private(set) var activeRecordingSourceID: UUID?

    /// Включены ли live hints
    @Published var isHintsEnabled: Bool = false

    /// Длительность текущей записи
    @Published var recordingElapsedTime: TimeInterval = 0

    /// Ordered project-owned takes. Missing files remain in this ledger so a
    /// persisted reference is never silently discarded.
    @Published private(set) var recordingReferences: [SceneRecordingReference] = []

    /// Newest persisted take whose file still resolves inside the recording
    /// store. Failed/recoverable pending artifacts are never published here.
    @Published private(set) var latestAvailableRecordingArtifact: RecordingArtifact?

    var latestRecordingArtifact: RecordingArtifact? {
        latestAvailableRecordingArtifact
    }

    /// Состояние live-hints overlay
    @Published var coachingOverlayState: OverlayState = .init(primaryBoundingBox: nil,
                                                              horizonAngle: 0,
                                                              horizonConfidence: 0,
                                                              saliencyBalance: 0)

    /// Transform from normalized camera-image coordinates to the ARView display space.
    @Published var hintDisplayTransform: CGAffineTransform?

    /// Текущая live-подсказка по кадру
    @Published var liveHint: LiveHintPresentation?

    /// Запущен ли углубленный разбор последнего кадра.
    @Published var isHintPauseAnalysisActive: Bool = false

    /// The one immutable frame handoff owned by the generator pause review.
    /// The accepted envelope and its display image are filled by the existing
    /// AnalysisPipeline owner; no parallel frame store is created here.
    @Published private(set) var acceptedHintPauseSnapshot: LatestFrameEvidenceStore.AcceptedSnapshot?

    /// Terminal/loading projection for the generator pause review. The shared
    /// CameraPausePresentationState keeps empty and failure states distinct.
    @Published private(set) var hintPausePresentationState: CameraPausePresentationState = .idle

    @Published private(set) var hintPauseFailureReason: CameraPauseFailureReason?
    @Published private(set) var hintPauseTakeNumber: Int = 0

    /// One owner-side ledger for the single pause-resume underline motif.
    let hintPauseMotionEventLedger = SETMotionEventLedger()

    /// Карточка углубленного разбора последнего кадра.
    @Published var hintPauseCritique: PauseCritiquePresentation?

    /// Быстрые legacy-подсказки, доступные во время углубленного разбора.
    @Published var hintPreviewSuggestions: [Suggestion] = []

    /// Визуальные аннотации для hints
    @Published var coachingOverlayAnnotations: [OverlayAnnotationPresentation] = []

    /// Скрытый режим демо-коуча для страховки записи.
    @Published var cameraDemoSceneMode: CameraDemoSceneMode = .auto

    /// Текущий диалоговый субтитр во время playback.
    @Published var activeDialogueCaption: String?

    /// Текущее описательное действие во время playback.
    @Published var activeActionCaption: String?

    /// Текущая экранная надпись/montage overlay во время playback.
    @Published var activeScreenTextCaption: String?

    /// Bundle-level overlays из screenplay front-end.
    @Published var visualOverlays: [SceneVisualOverlay] = []

    /// Beat timeline во время playback.
    @Published var beatTimelineItems: [BeatPlaybackTimelineItem] = []

    /// Индекс активного beat во время playback.
    @Published var activeBeatIndex: Int = 0

    /// Прогресс активного beat от 0 до 1.
    @Published var beatProgress: Double = 0

    /// Прошедшее время текущего playback.
    @Published var playbackElapsedTime: TimeInterval = 0

    /// Компактная лента раскадровки для демо-просмотра и ручного редактирования.
    @Published var storyboardBeatItems: [StoryboardBeatPresentationItem] = []

    /// 2D-подписи объектов, спроецированные из AR-пространства в экран.
    @Published var objectLabelItems: [ARObjectLabelPresentation] = []

    /// Draft текущего такта, открытого в ручном редакторе.
    @Published var activeStoryboardEditDraft: StoryboardBeatEditDraft?

    /// Storyboard selection is domain state so a SwiftUI re-render or rotation
    /// cannot replay the editor handoff.
    @Published private(set) var selectedStoryboardBeatID: String?
    @Published private(set) var pendingStoryboardBeatID: String?
    private(set) var storyboardSelectionEventID: String?
    private(set) var storyboardEditorHandoffEventID: String?

    /// The storyboard editor is busy with one owner-side mutation. Views only
    /// render this state and disable their controls from it.
    @Published private(set) var isStoryboardMutationInFlight = false

    /// Короткая подсказка/ошибка ручного перемещения актёра для открытого такта.
    @Published var storyboardDragFeedback: String?

    private var generationLogCounter = 0
    private var playbackLogCounter = 0
    private var currentPlaybackLogID: String?
    private var lastLoggedPlaybackBeatIndex: Int?
    private var hintPauseRequestToken: UUID?
    private var acceptedHintPauseRequestToken: UUID?
    private var hintPauseRequestGeneration: Int?
    private var hintPauseDisplayRenderTask: Task<Void, Never>?
    private var pendingHintPauseAnalysis: PendingHintPauseAnalysis?

    private struct PendingHintPauseAnalysis {
        let result: PauseAnalysisResult
        let suggestions: [Suggestion]
        let critique: PauseCritiquePresentation?
    }
    
    /// Статус AR сессии
    @Published var isARSessionReady: Bool = false

    /// AR interruption/recovery projection owned by the workspace. Readiness
    /// stays false until a post-interruption frame exposes a real plane.
    @Published private(set) var isARSessionInterrupted: Bool = false
    @Published private(set) var isARSessionRecovering: Bool = false
    
    /// Текст ошибки
    @Published var errorMessage: String? {
        didSet {
            // A non-recording error must retire any microphone-specific
            // recovery affordance before its own flow is rendered.
            recordingPermissionRecovery = nil
            recordingVideoOnlyRecoveryAvailable = false
        }
    }

    /// Recovery action for a microphone permission failure. The generator
    /// keeps this separate from the error copy so a view can offer the right
    /// native action without parsing localized text.
    @Published private(set) var recordingPermissionRecovery: SceneRecordingPermissionRecovery?

    /// Ошибка, относящаяся только к вводу сценария.
    @Published private(set) var inputValidationMessage: String?

    /// Structured projection of the current draft validation. It is derived
    /// from `sceneDescription`; the existing validation message remains the
    /// single published owner used by the sheet.
    var sceneDescriptionValidationIssue: SceneInputValidationIssue? {
        sceneDescriptionValidationIssue(for: sceneDescription)
    }

    /// Storyboard fixtures are domain evidence, not an AR substitute. On a
    /// simulator ARKit may still report an unsupported configuration; keep
    /// only that fixture-owned projection out of the error band while leaving
    /// production and Package 5 AR failure behavior unchanged.
    var isGeneratorErrorBandVisible: Bool {
#if DEBUG
        if debugFixtureID != nil,
           let errorMessage,
           errorMessage.hasPrefix(localizedCopy(.arErrorPrefix) + ":") {
            return false
        }
#endif
        return errorMessage != nil
    }

    /// Canonical validation copy for the active storyboard editor. This is
    /// kept separate from the workspace-wide error band so an asynchronous AR
    /// callback cannot replace the editor's validation result.
    @Published private(set) var storyboardValidationMessage: String?
    @Published private(set) var storyboardValidationField: StoryboardValidationField?
    
    /// Показать sheet ввода
    @Published var showInputSheet: Bool = false
    
    /// Показать popup для ввода имени маркера
    @Published var showMarkerNameInput: Bool = false
    
    /// Позиция для нового маркера (временная)
    @Published var pendingMarkerPosition: Position3D?
    
    /// Режим разметки объектов
    @Published var isMarkingMode: Bool = false
    
    /// Статус загрузки
    @Published var statusMessage: String = ""
    
    // MARK: - Services
    
    private let parserService = SceneParserService.shared
    private let objectBindingExtractor = SceneAnchorExtractor()
    private let plannerService = SpatialPlannerService.shared
    private let projectStore: DBService
    private let permissionClient: any PermissionClient
    private let recordingController: SceneRecordingController?
    private let audioSessionCoordinator: AudioSessionCoordinator
    private let recordingAudioOwnerID = UUID()
    private var recordingAudioLease: AudioSessionLease?
    private var recordingPlaybackLease: AudioSessionLease?
    private let hintThermalGovernor = ThermalGovernor()
    private lazy var analysisPipeline = AnalysisPipeline(
        thermalGovernor: hintThermalGovernor,
        neuralHeavyModelsEnabledProvider: { [weak self] in
            self?.hintThermalGovernor.nextBudget().heavyModelsEnabled ?? true
        },
        liveHybridFusionEnabled: false,
        demoLiveCoachEnabled: true
    )
    private let isObjectDetectionEnabled = false
    private var detectionBridge: ObjectDetectionBridge? {
        guard isObjectDetectionEnabled else { return nil }
        return ObjectDetectionBridge.shared
    }
    
    // MARK: - AR Properties
    
    /// Ссылка на ARView (устанавливается из ARSceneContainer)
    weak var arView: ARView?

    /// The view model only requests release; the coordinator remains the sole
    /// owner of ARSession delegate/run/pause mutations.
    private weak var arSessionOwner: (any ARSessionOwnerReleaseHandling)?

    /// Once released, AR callbacks and SwiftUI updates must not reattach the session.
    private(set) var isWorkspaceReleased = false

#if DEBUG
    /// Test-only callback seam for exercising ARKit completion races without a
    /// physical camera or a simulator AR session.
    var testingWorldMapCaptureOverride: (@MainActor () async -> Result<ARWorldMap?, SceneWorkspaceTeardownFailure>)?
    private(set) var testingProjectSnapshotSaveCount = 0

    /// Test-only state seam for validating stale-map retirement when a real
    /// ARWorldMap is supplied by an AR-capable test environment.
    var testingInitialWorldMapIsPresent: Bool {
        initialWorldMap != nil
    }

    func testingSetInitialWorldMap(_ worldMap: ARWorldMap?) {
        initialWorldMap = worldMap
    }
#endif

    /// Legacy stopRecording() persists for ordinary user actions. Teardown owns the
    /// one awaited persistence operation and suppresses that fire-and-forget side effect.
    private var suppressAutomaticPersistence = false

    private lazy var workspaceTeardownCoordinator = SceneWorkspaceTeardownCoordinator(
        stopRecordingIfNeeded: { [weak self] in
            guard let self else { return }
            _ = await self.stopRecordingAndWait(reason: .routeExit)
        },
        stopPlaybackIfNeeded: { [weak self] in
            guard let self, self.isPlaying else { return }
            self.stopScene()
        },
        persist: { [weak self] in
            guard let self else {
                return .failure(.workspaceOwnerUnavailable)
            }
            return await self.persistProjectSnapshot()
        },
        pauseAndDetach: { [weak self] in
            self?.pauseAndDetachARSession()
        },
        releaseRecordingIfNeeded: { [weak self] in
            _ = await self?.recordingController?.releaseAndWait()
        }
    )

    /// Сохранённая world map для восстановления проекта
    private var initialWorldMap: ARWorldMap?
    
    /// Текущая трансформация камеры
    private var currentCameraTransform: simd_float4x4?
    
    /// Обнаруженные плоскости
    private var detectedPlanes: [ScenePlaneSnapshot] = []
    private var lastPlaneUpdateTimestamp: TimeInterval = 0
    private let planeRefreshInterval: TimeInterval = 0.35
    private let disabledHintFrameInterval: TimeInterval = .greatestFiniteMagnitude
    
    /// Размещённые entity
    private var placedEntities: [String: ModelEntity] = [:]
    private var cachedPersonPrototype: ModelEntity?
    private var actorRenderStyles: [String: SceneActorRenderStyle] = [:]
    private var sceneBillboardEntities: [Entity] = []
    private var pathGuideEntities: [ModelEntity] = []
    private var actorFocusEntities: [String: ModelEntity] = [:]
    private var activeTargetCueEntities: [ModelEntity] = []
    private var activeTargetCueID: UUID?
    private var activeStoryboardActorDrag: StoryboardActorDragState?
    private var lastPresentationFrameTimestamp: TimeInterval = 0
    private var lastObjectLabelProjectionTimestamp: TimeInterval?
    private let objectLabelProjectionInterval: TimeInterval = 1.0 / 15.0
    private var expectedARFrameGeneration = 0
    private let storyboardActorScreenPickRadius: CGFloat = 86

    private struct StoryboardActorDragState {
        let actorPlacedID: String
        let actorID: String
        let beatID: String?
        let originalPosition: SIMD3<Float>
        var latestPosition: Position3D
    }
    
    /// Anchor для всей сцены
    private var sceneAnchor: AnchorEntity?
    
    /// Entity для маркеров объектов
    private var markerEntities: [UUID: ModelEntity] = [:]
    
    /// Anchor для маркеров (сохраняется отдельно от сцены)
    private var markersAnchor: AnchorEntity?
    
    /// Work items для анимаций (для отмены)
    private var animationWorkItems: [DispatchWorkItem] = []

    /// ID текущего диалога/действия, чтобы старые delayed-clear не гасили новый текст.
    private var activeDialogueCaptionID: UUID?
    private var activeActionCaptionID: UUID?
    private var activeScreenTextCaptionID: UUID?
    private var playbackTimelineTimer: Timer?
    private var playbackStartDate: Date?
    private var recordingTimer: Timer?
    private var recordingStartDate: Date?
    private var recordingStartTask: Task<Void, Never>?
    private var recordingStopTask: Task<RecordingStopResult?, Never>?
    private var promotedRecordingIDs = Set<UUID>()
    private var pendingRecordingArtifacts: [RecordingArtifact] = []
    private var projectSnapshotTask: Task<Result<Void, SceneWorkspaceTeardownFailure>, Never>?
    private var generationTask: Task<Void, Never>?
    /// M1-016: active workspace deletion lease; non-nil while this VM owns the project.
    private var projectLeaseToken: UUID?
    /// The registry is supplied by the persistence owner when Library opens a
    /// project, so the transferred token is released through the same lease
    /// authority that guarded the read/validation boundary.
    private let projectLeaseRegistry: ProjectLifecycleRegistry
    private var generationEpoch: UInt = 0
    private var teardownTask: Task<SceneWorkspaceTeardownResult, Never>?
    private var teardownTaskID: UUID?
    private static let worldMapCaptureTimeoutNanoseconds: UInt64 = 3_000_000_000
    private var hasRestoredPersistedEntities = false
    private var hasAutoPromptedDescription = false
    private var currentProject: UnifiedSceneProject
    private var presentationLocale: Locale
    private var lastHighHintTimestamp: TimeInterval = 0
    private var lastMediumHintTimestamp: TimeInterval = 0
    private var lastLowHintTimestamp: TimeInterval = 0
    private var arInterfaceOrientation: UIInterfaceOrientation = .portrait
    private var hintFrameDebugCounter = 0
    private var lastHintFrameDebugLogTimestamp: TimeInterval = 0
    private let objectDemoDetrHintFrameInterval: TimeInterval = 1.2
    private let lidarDepthMarkingEnabledDefaultsKey = "scene_generator_lidar_marking_enabled"
    private let storyboardMotionEventLedger = SETMotionEventLedger()
    private var storyboardSelectionSequence = 0
    private var storyboardSelectionTask: Task<Void, Never>?
#if DEBUG
    private var debugFixtureID: String?
    private var storyboardDebugMutationDelay: TimeInterval = 0
    private var generationDebugDelay: TimeInterval = 0
    private var testingParserResultOverride: ((String, [MarkedObject]) async -> ParsingResult)?
    private(set) var testingGenerationOwnerCount = 0
    private(set) var testingGenerationStateTrace: [SceneGenerationRequestState] = [.idle]
#endif
    
    // MARK: - Cancellables
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(projectName: String = "Новая сцена",
         isNewProject: Bool = true,
         projectStore: DBService = .shared,
         presentationLocale: Locale? = nil,
         permissionClient: any PermissionClient = PermissionCoordinator(client: SystemPermissionClient()),
         recordingController: SceneRecordingController? = nil,
         audioSessionCoordinator: AudioSessionCoordinator = .shared,
         persistedProject: UnifiedSceneProject? = nil,
         persistedWorldMap: ARWorldMap? = nil,
         projectLeaseToken: UUID? = nil,
         projectLeaseRegistry: ProjectLifecycleRegistry = .shared) {
        self.projectStore = projectStore
        self.projectLeaseRegistry = projectLeaseRegistry
        self.permissionClient = permissionClient
        self.audioSessionCoordinator = audioSessionCoordinator
        if let recordingController {
            self.recordingController = recordingController
        } else if let artifactStore = try? RecordingArtifactStore() {
            self.recordingController = SceneRecordingController(artifactStore: artifactStore)
        } else {
            self.recordingController = nil
        }
        // The route updates this value as soon as its injected locale is
        // available. RU remains the deterministic standalone/default surface,
        // preserving existing generator behavior before route composition.
        self.presentationLocale = presentationLocale ?? Locale(identifier: "ru")
        let loadedProject: (UnifiedSceneProject, ARWorldMap?)?
        if let persistedProject {
            loadedProject = (persistedProject, persistedWorldMap)
        } else if isNewProject {
            loadedProject = nil
        } else {
            loadedProject = projectStore.loadUnifiedSceneProject(named: projectName)
        }
        if let loadedProject {
            self.currentProject = loadedProject.0
            self.initialWorldMap = loadedProject.1
        } else {
            self.currentProject = UnifiedSceneProject(name: projectName)
            self.initialWorldMap = nil
        }
        // M1-016 ProjectLifecycleOwner: the workspace holds the deletion lease
        // for as long as it can mutate this project. A nil token means another
        // owner already held it; deletion stays blocked by that owner.
        if let projectLeaseToken {
            self.projectLeaseToken = projectLeaseToken
        } else {
            self.projectLeaseToken = projectLeaseRegistry.acquire(projectID: currentProject.id)
        }
        if self.projectLeaseToken == nil {
            print("Project lease unavailable for \(currentProject.name); deletion stays blocked by the active owner")
        }
        self.sceneTitle = currentProject.name
        self.sceneDescription = currentProject.sceneDescription
        self.markedObjects = currentProject.markedObjects
        self.parsedScript = currentProject.parsedScript
        self.plannedScene = currentProject.plannedScene
        self.sceneChunkState = currentProject.sceneChunkState
        self.visualOverlays = currentProject.visualOverlays
        self.recordingReferences = currentProject.recordingReferences
        self.promotedRecordingIDs = Set(currentProject.recordingReferences.map(\.recordingID))
#if DEBUG
        let launchFixtureID = Self.storyboardFixtureID(from: ProcessInfo.processInfo.arguments)
        self.debugFixtureID = launchFixtureID
        if let launchFixtureID {
            loadDebugStoryboardFixture(launchFixtureID)
        }
#endif
        setupBindings()
        if !sceneDescription.isEmpty {
            updateGenerationInputState(for: sceneDescription)
        }
#if DEBUG
        if launchFixtureID == "sheet.decision-trace" {
            seedDebugDecisionTraceFixture()
        }
#endif
        refreshStoryboardBeatItems()
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
        refreshLatestAvailableRecordingArtifact()
#if DEBUG
        if launchFixtureID == "storyboard.validation-failure" {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, let draft = self.activeStoryboardEditDraft else { return }
                _ = await self.applyStoryboardBeatEdit(draft)
            }
        }
#endif
    }

    /// Stable identity of the aggregate currently owned by this workspace.
    /// Library routing supplies the already validated project so this value is
    /// never re-derived from the mutable display name during open.
    var projectID: UUID { currentProject.id }
    
    private func setupBindings() {
        $markedObjects
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshIdleStatusMessage()
                self?.persistProjectMetadata()
            }
            .store(in: &cancellables)

        $sceneDescription
            .dropFirst()
            .sink { [weak self] description in
                guard let self else { return }
                updateGenerationInputState(for: description)
                sceneChunkState = nil
                refreshIdleStatusMessage()
                persistProjectMetadata()
            }
            .store(in: &cancellables)

        analysisPipeline.$overlayState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] overlayState in
                self?.coachingOverlayState = overlayState
            }
            .store(in: &cancellables)

        analysisPipeline.$currentLiveHint
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hint in
#if DEBUG
                // The production-route Decision Trace fixture owns its
                // deterministic presentation. Ignore the pipeline's initial
                // nil projection (and later simulator-only clears) so the
                // real generator button remains reachable without AR frames.
                guard self?.debugFixtureID != "sheet.decision-trace" else { return }
#endif
                self?.liveHint = hint
            }
            .store(in: &cancellables)

        analysisPipeline.$currentOverlayAnnotations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] annotations in
#if DEBUG
                guard self?.debugFixtureID != "sheet.decision-trace" else { return }
#endif
                self?.coachingOverlayAnnotations = annotations
            }
            .store(in: &cancellables)

        Task { @MainActor in
            analysisPipeline.setCameraDemoSceneMode(cameraDemoSceneMode)
        }
    }

    static func actorRenderStyle(for actor: PlannedScene.PlacedActor, at index: Int) -> SceneActorRenderStyle {
        let palette: [SIMD3<Float>] = [
            SIMD3<Float>(0.20, 0.62, 1.00),
            SIMD3<Float>(1.00, 0.46, 0.30),
            SIMD3<Float>(0.22, 0.76, 0.48),
            SIMD3<Float>(0.74, 0.50, 1.00),
            SIMD3<Float>(1.00, 0.75, 0.22),
        ]
        let numericSuffix = actor.actorId
            .split(separator: "_")
            .last
            .flatMap { Int($0) }
        let paletteIndex = max((numericSuffix ?? (index + 1)) - 1, 0) % palette.count
        return SceneActorRenderStyle(color: palette[paletteIndex], paletteIndex: paletteIndex)
    }

    static let supportedStoryboardEditActionTypes: [SceneAction.ActionType] = [
        .stand,
        .walk,
        .lookAt,
        .pickUp,
        .give,
        .talk,
        .describedAction,
    ]

    static let storyboardTargetActionTypes: Set<SceneAction.ActionType> = [
        .walk,
        .lookAt,
        .pickUp,
        .give,
    ]

    static func objectRenderStyle(for type: SceneObject.ObjectType) -> SceneObjectRenderStyle {
        switch type {
        case .phone:
            return SceneObjectRenderStyle(kind: .phoneProxy, targetCueRadius: 0.074)
        default:
            return SceneObjectRenderStyle(kind: .standardPlaceholder, targetCueRadius: 0.045)
        }
    }

    static func yawAngle(from start: SIMD3<Float>, toward end: SIMD3<Float>, minDistance: Float = 0.01) -> Float? {
        let delta = end - start
        let planarLength = sqrt(delta.x * delta.x + delta.z * delta.z)
        guard planarLength > minDistance else { return nil }
        return atan2(delta.x, delta.z)
    }

    static func layoutObjectLabels(
        _ labels: [ARObjectLabelPresentation],
        canvasSize: CGSize,
        minVerticalSpacing: CGFloat = 28,
        horizontalCollisionRange: CGFloat = 120,
        edgeInsets: UIEdgeInsets = UIEdgeInsets(top: 48, left: 36, bottom: 94, right: 36)
    ) -> [ARObjectLabelPresentation] {
        guard !labels.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return labels }

        let minX = edgeInsets.left
        let maxX = max(minX, canvasSize.width - edgeInsets.right)
        let minY = edgeInsets.top
        let maxY = max(minY, canvasSize.height - edgeInsets.bottom)
        var arranged: [ARObjectLabelPresentation] = []

        for label in labels.sorted(by: objectLabelSort) {
            let clampedX = min(max(label.x, minX), maxX)
            var candidateY = min(max(label.y, minY), maxY)

            for placed in arranged where abs(placed.x - clampedX) < horizontalCollisionRange {
                if abs(placed.y - candidateY) < minVerticalSpacing {
                    candidateY = placed.y + minVerticalSpacing
                }
            }

            if candidateY > maxY {
                let overflow = candidateY - maxY
                arranged = arranged.map { placed in
                    guard abs(placed.x - clampedX) < horizontalCollisionRange else { return placed }
                    return placed.withPosition(x: placed.x, y: max(minY, placed.y - overflow))
                }
                candidateY = maxY
            }

            arranged.append(label.withPosition(x: clampedX, y: min(max(candidateY, minY), maxY)))
        }

        return arranged.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority < $1.priority }
    }

    private static func objectLabelSort(_ lhs: ARObjectLabelPresentation, _ rhs: ARObjectLabelPresentation) -> Bool {
        if abs(lhs.y - rhs.y) > 1 {
            return lhs.y < rhs.y
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.id < rhs.id
    }

    private func actorRenderStyle(for actor: PlannedScene.PlacedActor) -> SceneActorRenderStyle {
        if let style = actorRenderStyles[actor.id] {
            return style
        }
        let index = plannedScene?.placedActors.firstIndex { $0.id == actor.id } ?? 0
        return Self.actorRenderStyle(for: actor, at: index)
    }
    
    // MARK: - Public API

    /// Обновляет только лёгкий presentation-layer AR: 2D object labels и billboard-подписи.
    /// Этот путь вызывается на каждый AR frame, в отличие от тяжёлого `processARFrameSnapshot`.
    func updateARPresentationFrame(cameraTransform: simd_float4x4,
                                   timestamp: TimeInterval,
                                   generation: Int? = nil) {
        guard !isWorkspaceReleased else { return }
        guard generation == nil || generation == expectedARFrameGeneration else { return }
        if timestamp < lastPresentationFrameTimestamp {
            guard lastPresentationFrameTimestamp - timestamp > 2 else { return }
        }
        lastPresentationFrameTimestamp = timestamp
        currentCameraTransform = cameraTransform
        updateBillboardEntities(cameraTransform: cameraTransform)
        let shouldUpdateObjectLabels = lastObjectLabelProjectionTimestamp.map { lastTimestamp in
            timestamp - lastTimestamp >= objectLabelProjectionInterval
                || timestamp < lastTimestamp - 2
        } ?? true
        if !isMarkerNameInputActive, shouldUpdateObjectLabels {
            lastObjectLabelProjectionTimestamp = timestamp
            updateObjectLabelOverlays()
        }
    }
    
    /// Обрабатывает snapshot AR-кадра без удержания ARFrame в очереди MainActor.
    func processARFrameSnapshot(
        cameraTransform: simd_float4x4,
        planeSnapshots: [ScenePlaneSnapshot],
        timestamp: TimeInterval,
        capturedImage: CVPixelBuffer? = nil,
        interfaceOrientation: UIInterfaceOrientation? = nil,
        displayTransform: CGAffineTransform? = nil,
        generation: Int? = nil
    ) {
        guard !isWorkspaceReleased else { return }
        guard generation == nil || generation == expectedARFrameGeneration else { return }
        guard !isARSessionInterrupted else { return }
        currentCameraTransform = cameraTransform
        if let interfaceOrientation, interfaceOrientation != .unknown {
            arInterfaceOrientation = interfaceOrientation
        }
        if let displayTransform,
           hintDisplayTransform != displayTransform {
            hintDisplayTransform = displayTransform
        }
        
        // Обновляем плоскости с ограничением частоты, чтобы не перегружать main thread.
        if timestamp - lastPlaneUpdateTimestamp >= planeRefreshInterval || detectedPlanes.isEmpty {
            detectedPlanes = planeSnapshots
            lastPlaneUpdateTimestamp = timestamp
        }
        
        // Проверяем готовность AR сессии
        if !isARSessionInterrupted,
           !isARSessionReady,
           !detectedPlanes.isEmpty {
            isARSessionReady = true
            isARSessionRecovering = false
            refreshWorkspaceMode()
            refreshIdleStatusMessage()
        }
        
        if let capturedImage {
            if !isARSessionRecovering {
                processHintFrameIfNeeded(pixelBuffer: capturedImage, timestamp: timestamp)
            }
        }

        updateARPresentationFrame(
            cameraTransform: cameraTransform,
            timestamp: timestamp,
            generation: generation
        )
        
        // DETR детекция отключена - используем только ручную разметку и LiDAR
    }

    /// Backward-compatible обёртка для существующих call-sites.
    func processARFrame(_ frame: ARFrame, generation: Int? = nil) {
        processARFrameSnapshot(
            cameraTransform: frame.camera.transform,
            planeSnapshots: frame.anchors.compactMap { ($0 as? ARPlaneAnchor).map(ScenePlaneSnapshot.init(anchor:)) },
            timestamp: frame.timestamp,
            capturedImage: nil,
            generation: generation
        )
    }

    func prepareWorkspace() {
        prepareWorkspaceIfNeeded()
    }

    func setARSessionOwner(_ owner: (any ARSessionOwnerReleaseHandling)?) {
        arSessionOwner = owner
    }

    func clearARSessionOwner(_ owner: any ARSessionOwnerReleaseHandling) {
        guard let currentOwner = arSessionOwner, currentOwner === owner else { return }
        arSessionOwner = nil
        arView = nil
    }

    func setExpectedARSessionGeneration(_ generation: Int) {
        guard generation >= expectedARFrameGeneration else { return }
        expectedARFrameGeneration = generation
    }

    /// Concrete capture sink used directly by ARSceneContainer.Coordinator.
    /// It is intentionally not a protocol so the reachable path has one
    /// recording owner.
    var sceneRecordingController: SceneRecordingController? {
        recordingController
    }

    /// A newly created AR coordinator becomes the sole owner of the source
    /// fact. Teardown/released workspaces cannot be claimed again.
    @discardableResult
    func claimRecordingSource(ownerID: UUID, fps: Int?) -> Bool {
        guard teardownTask == nil, !isWorkspaceReleased else { return false }
        activeRecordingSourceID = ownerID
        updateRecordingSourceFPS(fps, ownerID: ownerID)
        return true
    }

    /// Publishes only changes from the currently active AR coordinator.
    func updateRecordingSourceFPS(_ fps: Int?, ownerID: UUID) {
        guard activeRecordingSourceID == ownerID else { return }
        let normalizedFPS = fps.flatMap { $0 > 0 ? $0 : nil }
        guard recordingSourceFPS != normalizedFPS else { return }
        recordingSourceFPS = normalizedFPS
    }

    /// Clears the source fact only when the caller still owns it. A stale
    /// coordinator must not clear a replacement session's actual FPS.
    func releaseRecordingSource(ownerID: UUID) {
        guard activeRecordingSourceID == ownerID else { return }
        updateRecordingSourceFPS(nil, ownerID: ownerID)
        activeRecordingSourceID = nil
    }

    /// UIKit-owned callbacks cannot read SwiftUI's locale environment. Keep
    /// their catalog lookup aligned with the locale injected by the route so
    /// runtime status/error copy does not fall back to Russian in EN captures.
    func localizedCopy(_ key: SETCopyKey) -> String {
        key.localizedString(locale: presentationLocale)
    }

    func localizedCopy(_ key: SETCopyKey, arguments: [CVarArg]) -> String {
        key.localizedFormat(locale: presentationLocale, arguments: arguments)
    }

    func setPresentationLocale(_ locale: Locale) {
        guard presentationLocale.identifier != locale.identifier else { return }
        presentationLocale = locale
        if !isGenerating {
            refreshIdleStatusMessage()
        }
    }

    /// Re-resolves the newest persisted take after a project load or when a
    /// review surface is reattached. The reference ledger itself is retained
    /// even when every file is missing.
    func refreshLatestAvailableRecordingArtifact() {
        latestAvailableRecordingArtifact = recordingReferences.reversed().compactMap {
            recordingController?.resolve($0)
        }.first
    }

    func clearGeneratorError() {
        errorMessage = nil
        recordingPermissionRecovery = nil
    }

    func retryRecording() {
        clearGeneratorError()
        startRecording()
    }

    func persistWorkspaceState() {
        Task { _ = await persistProjectSnapshot() }
    }

#if DEBUG
    func testingPersistProjectSnapshot() async -> Result<Void, SceneWorkspaceTeardownFailure> {
        await persistProjectSnapshot()
    }
#endif

    func teardownAndWait() async -> SceneWorkspaceTeardownResult {
        if let teardownTask {
            let taskID = teardownTaskID
            let result = await teardownTask.value
            clearBlockedTeardownTask(result, taskID: taskID)
            return result
        }

        let taskID = UUID()
        let task: Task<SceneWorkspaceTeardownResult, Never> = Task { @MainActor [weak self] in
            guard let self else {
                return .blocked(.workspaceOwnerUnavailable)
            }
            return await self.performTeardown()
        }
        teardownTaskID = taskID
        teardownTask = task

        let result = await task.value
        clearBlockedTeardownTask(result, taskID: taskID)
        return result
    }

    private func performTeardown() async -> SceneWorkspaceTeardownResult {
        clearHintPresentation()
        suppressAutomaticPersistence = true
        objectBindingResult = nil

        let generationWasInFlight = generationRequestState.isExecutionInFlight
        let cancellationPublished: Bool
        if generationWasInFlight,
           let requestID = generationRequestState.requestID,
           let epoch = generationRequestState.epoch {
            cancellationPublished = publishGenerationState(
                .cancelling(requestID: requestID, epoch: epoch),
                expectedRequestID: requestID,
                expectedEpoch: epoch
            )
        } else {
            cancellationPublished = !generationWasInFlight
        }
        generationEpoch &+= 1
        generationTask?.cancel()
        if let generationTask {
            await generationTask.value
            self.generationTask = nil
        }
        if !cancellationPublished {
            diagnosticsLog("[GENERATION] cancellation publication failed during teardown; retiring request")
        }
        if generationRequestState.phase != .idle {
            // Teardown clears any non-running draft/result as well. This keeps
            // a released workspace from retaining a request state that cannot
            // accept a later completion. The explicit reset also guarantees
            // projections are inactive if the cancellation edge was rejected.
            let retired = publishGenerationState(.idle, allowTeardownReset: true)
            if !retired {
                diagnosticsLog("[GENERATION] teardown could not retire request state")
            } else {
                refreshWorkspaceMode()
                refreshIdleStatusMessage()
            }
        }

        await releaseRecordingPlaybackLease()
        let result = await workspaceTeardownCoordinator.teardownAndWait()
        if result == .released {
            isWorkspaceReleased = true
            releaseProjectLeaseIfNeeded()
        } else {
            suppressAutomaticPersistence = false
        }
        return result
    }

    private func clearBlockedTeardownTask(
        _ result: SceneWorkspaceTeardownResult,
        taskID: UUID?
    ) {
        guard case .blocked = result,
              teardownTaskID == taskID else { return }
        teardownTask = nil
        teardownTaskID = nil
    }

    /// M1-016: drops the deletion lease once the workspace no longer owns
    /// project state. Safe to call repeatedly; a stale token cannot drop a
    /// newer lease.
    private func releaseProjectLeaseIfNeeded() {
        guard let projectLeaseToken else { return }
        projectLeaseRegistry.release(projectID: currentProject.id, token: projectLeaseToken)
        self.projectLeaseToken = nil
    }

    deinit {
        if let projectLeaseToken {
            projectLeaseRegistry.release(projectID: currentProject.id, token: projectLeaseToken)
        }
    }

    private func pauseAndDetachARSession() {
        arSessionOwner?.releaseSession()
        arView = nil
    }

    func attachARView(_ arView: ARView) {
        guard !isWorkspaceReleased else { return }
        let isNewAttachment = self.arView !== arView
        self.arView = arView
        prepareWorkspaceIfNeeded()
        if isNewAttachment {
            hasRestoredPersistedEntities = false
        }
        restorePersistedEntitiesIfNeeded()
    }

    var isDepthMarkingEnabled: Bool {
        isMarkingMode && UserDefaults.standard.bool(forKey: lidarDepthMarkingEnabledDefaultsKey)
    }

    func makeARSessionConfigurationRequest() -> ARWorldTrackingConfigurationRequest {
        ARWorldTrackingConfigurationRequest(
            depthRequested: isDepthMarkingEnabled,
            initialWorldMap: initialWorldMap
        )
    }

    func handleARSessionConfigurationFailure(_ failure: ARWorldTrackingConfigurationFailure) {
        guard !isWorkspaceReleased else { return }
        isARSessionReady = false
        isARSessionInterrupted = false
        isARSessionRecovering = false
        refreshWorkspaceMode()
        let recovery = localizedCopy(failure.recoveryCopyKey)
        errorMessage = recovery
        statusMessage = recovery
    }

    /// Called by the AR coordinator when the operating system suspends the
    /// camera session. The interruption is visible in the existing status
    /// owner; playback, recording, and hint analysis are stopped here so no
    /// child surface can invent a recovery path.
    func handleARSessionInterruption(generation: Int? = nil) {
        guard !isWorkspaceReleased else { return }
        let nextGeneration = generation ?? (expectedARFrameGeneration + 1)
        guard nextGeneration >= expectedARFrameGeneration else { return }
        expectedARFrameGeneration = nextGeneration

        isARSessionInterrupted = true
        isARSessionRecovering = false
        isARSessionReady = false
        detectedPlanes.removeAll()
        currentCameraTransform = nil
        lastPlaneUpdateTimestamp = 0

        if isPlaying {
            stopScene()
        }
        if isRecording || isRecordingStarting || isRecordingFinalizing {
            requestStopRecording(reason: .interruption)
        }
        clearHintPresentation()
        refreshWorkspaceMode()
        statusMessage = localizedCopy(.cameraInterrupted)
    }

    /// Ends the visible interruption state but does not claim readiness. A
    /// subsequent AR frame with a real detected plane completes recovery.
    func handleARSessionInterruptionEnded(generation: Int? = nil) {
        guard !isWorkspaceReleased else { return }
        let nextGeneration = generation ?? (expectedARFrameGeneration + 1)
        guard nextGeneration >= expectedARFrameGeneration else { return }
        expectedARFrameGeneration = nextGeneration

        isARSessionInterrupted = false
        isARSessionRecovering = true
        isARSessionReady = false
        detectedPlanes.removeAll()
        currentCameraTransform = nil
        lastPlaneUpdateTimestamp = 0
        clearHintPresentation()
        refreshWorkspaceMode()
        statusMessage = localizedCopy(.cameraResuming)
    }

    /// Record is a real camera action, so every prerequisite is checked here
    /// as well as in the UIKit rail that exposes the button.
    private var isSceneMutationBlocked: Bool {
        isRecording
            || isRecordingStarting
            || isRecordingFinalizing
            || isPlaying
            || isGenerating
            || isARSessionInterrupted
            || isARSessionRecovering
    }

    var canToggleMarkingMode: Bool {
        !isSceneMutationBlocked || isMarkingMode
    }

    var canGenerateScene: Bool {
        teardownTask == nil
            && !isWorkspaceReleased
            && !isSceneMutationBlocked
            && !isMarkingMode
    }

    /// UI-facing projection of the same trust-boundary checks used by
    /// `generateScene()`. The action remains disabled for every rejected
    /// draft, while the submit method repeats the check before request
    /// identity is allocated.
    var canSubmitScene: Bool {
        canGenerateScene && sceneDescriptionValidationIssue == nil
    }

    var canToggleHints: Bool {
        !isPlaying
            && !isGenerating
            && !isMarkingMode
            && !isRecordingFinalizing
            && !isARSessionInterrupted
            && !isARSessionRecovering
    }

    var canStartRecording: Bool {
        plannedScene != nil
            && teardownTask == nil
            && !isWorkspaceReleased
            && recordingSourceFPS.map { $0 > 0 } == true
            && isARSessionReady
            && !isARSessionInterrupted
            && !isARSessionRecovering
            && !isGenerating
            && !isPlaying
            && !isRecording
            && !isRecordingStarting
            && !isRecordingFinalizing
            && !isMarkingMode
            && recordingPlaybackLease == nil
    }

    var canToggleRecordingSound: Bool {
        teardownTask == nil
            && !isWorkspaceReleased
            && !isRecordingStarting
            && !isRecording
            && !isRecordingFinalizing
    }

    /// M7-001 keeps required audio fail-closed. The only video-only policy is
    /// the user-selected sound-off attempt; it is never inferred from a
    /// permission or audio-session failure.
    private var selectedRecordingAudioPolicy: RecordingAudioPolicy {
        recordingSoundEnabled
            ? RecordingAudioPolicy(mode: .required, unavailableBehavior: .failRecording)
            : RecordingAudioPolicy(mode: .disabled, unavailableBehavior: .explicitVideoOnlySelection)
    }

    /// A permission/session failure may offer an explicit silent retry. The
    /// fallback is never selected by the required-audio start path itself.
    @Published private(set) var recordingVideoOnlyRecoveryAvailable = false

    func setRecordingSoundEnabled(_ enabled: Bool) {
        guard canToggleRecordingSound else { return }
        recordingSoundEnabled = enabled
        if !enabled {
            recordingVideoOnlyRecoveryAvailable = false
        }
    }

    func startRecordingWithoutSound() {
        guard canStartRecording else { return }
        setRecordingSoundEnabled(false)
        clearGeneratorError()
        startRecording()
    }

    var canStartPlayback: Bool {
        plannedScene != nil
            && isARSessionReady
            && !isARSessionInterrupted
            && !isARSessionRecovering
            && !isGenerating
            && !isPlaying
            && !isRecording
            && !isRecordingStarting
            && !isRecordingFinalizing
            && !isMarkingMode
    }

    private func updateGenerationInputState(for description: String) {
        guard !generationRequestState.isExecutionInFlight else { return }

        let issue = sceneDescriptionValidationIssue(for: description)
        if let issue, !(issue == .empty && description.isEmpty) {
            let message = localizedInputValidationCopy(for: issue)
            enterGenerationInputState()
            _ = publishGenerationState(
                .input(),
                validation: message
            )
        } else {
            enterGenerationInputState(clearValidation: true)
        }
    }

    /// Validates the editable draft without normalizing or truncating it.
    /// `String.count` is the user-perceived `Character` count required by the
    /// input contract. Swift `String` does not expose unpaired UTF-16
    /// surrogates as valid scalar input, so this check deliberately makes no
    /// impossible coverage claim for them.
    private func sceneDescriptionValidationIssue(for description: String) -> SceneInputValidationIssue? {
        guard !description.isEmpty else { return .empty }
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard description.count <= Self.maximumSceneDescriptionCharacters else {
            return .tooLong(maximum: Self.maximumSceneDescriptionCharacters)
        }
        guard !description.unicodeScalars.contains(where: Self.isDisallowedInputScalar) else {
            return .invalidText
        }
        return nil
    }

    private static func isDisallowedInputScalar(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        if value == 0 || (CharacterSet.controlCharacters.contains(scalar) && value != 0x0A && value != 0x0D) {
            return true
        }

        return (0xFDD0...0xFDEF).contains(value)
            || (value & 0xFFFF) == 0xFFFE
            || (value & 0xFFFF) == 0xFFFF
    }

    private func localizedInputValidationCopy(for issue: SceneInputValidationIssue) -> String {
        let bundle = SETLibraryLocalizedCopy.resolvedBundle(for: presentationLocale)
        switch issue {
        case .empty:
            return localizedCopy(.generatorInputInvalid)
        case .tooLong(let maximum):
            let format = bundle.localizedString(
                forKey: "set.generator.input.too_long",
                value: "Use %@ characters or fewer",
                table: nil
            )
            return String(
                format: format,
                locale: presentationLocale,
                arguments: [localizedCharacterCount(maximum)]
            )
        case .invalidText:
            return bundle.localizedString(
                forKey: "set.generator.input.invalid_text",
                value: "Remove unsupported hidden or control characters and invalid Unicode characters",
                table: nil
            )
        }
    }

    private func localizedCharacterCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = presentationLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }

    private func enterGenerationInputState(clearValidation: Bool = false) {
        _ = publishGenerationState(.input(), clearValidation: clearValidation)
    }

    /// The only writer for generator state and its compatibility projections.
    /// A rejected transition leaves every projection untouched. Teardown may
    /// explicitly retire to `idle` after the cancellation edge is unavailable
    /// (for example, if a future state was malformed); that is a lifecycle
    /// reset, not a normal transition, and still goes through this owner.
    @discardableResult
    private func publishGenerationState(
        _ next: SceneGenerationRequestState,
        expectedRequestID: UUID? = nil,
        expectedEpoch: UInt? = nil,
        status: String? = nil,
        error: String? = nil,
        validation: String? = nil,
        clearError: Bool = false,
        clearValidation: Bool = false,
        allowTeardownReset: Bool = false
    ) -> Bool {
        if let expectedRequestID, generationRequestState.requestID != expectedRequestID {
            return false
        }
        if let expectedEpoch,
           (generationRequestState.epoch != expectedEpoch || generationEpoch != expectedEpoch) {
            return false
        }
        let isTeardownReset = allowTeardownReset && next.phase == .idle
        let validTransition = SceneGenerationRequestState.transition(
            from: generationRequestState,
            to: next
        ) != nil
        guard validTransition || isTeardownReset else {
            diagnosticsLog(
                "[GENERATION] rejected transition \(generationRequestState.phase.rawValue) -> \(next.phase.rawValue)"
            )
            return false
        }

        generationRequestState = next
        isGenerating = next.isExecutionInFlight
        generationStage = next.stage
#if DEBUG
        testingGenerationStateTrace.append(next)
#endif
        if let status {
            statusMessage = status
        }
        if clearError {
            errorMessage = nil
        } else if let error {
            errorMessage = error
        }
        if clearValidation {
            inputValidationMessage = nil
        } else if let validation {
            inputValidationMessage = validation
        }
        return true
    }

    @discardableResult
    private func publishGenerationFailure(
        _ failure: SceneGenerationFailureKind,
        retryable: Bool,
        message: String,
        expectedRequestID: UUID? = nil,
        expectedEpoch: UInt? = nil,
        validation: String? = nil
    ) -> Bool {
        let next: SceneGenerationRequestState
        if !retryable,
           failure == .emptyInput,
           generationRequestState.requestID == nil,
           generationRequestState.epoch == nil {
            next = .emptyInputFailure()
        } else {
            guard let requestID = generationRequestState.requestID,
                  let epoch = generationRequestState.epoch else {
                return false
            }
            next = retryable
                ? .retryableFailure(requestID: requestID, epoch: epoch, failure: failure)
                : .terminalFailure(requestID: requestID, epoch: epoch, failure: failure)
        }
        return publishGenerationState(
            next,
            expectedRequestID: expectedRequestID,
            expectedEpoch: expectedEpoch,
            status: message,
            error: message,
            validation: validation
        )
    }

    @discardableResult
    private func publishGenerationStage(
        _ stage: SceneGenerationStage,
        status: String,
        requestID: UUID,
        generationToken: UInt
    ) -> Bool {
        guard generationIsCurrent(generationToken, requestID: requestID) else { return false }
        return publishGenerationState(
            .generating(requestID: requestID, epoch: generationToken, stage: stage),
            expectedRequestID: requestID,
            expectedEpoch: generationToken,
            status: status
        )
    }

    @discardableResult
    private func publishGenerationStatus(
        _ status: String,
        requestID: UUID,
        generationToken: UInt
    ) -> Bool {
        guard generationIsCurrent(generationToken, requestID: requestID),
              generationRequestState.phase == .generating,
              let stage = generationRequestState.stage else {
            return false
        }
        return publishGenerationState(
            .generating(requestID: requestID, epoch: generationToken, stage: stage),
            expectedRequestID: requestID,
            expectedEpoch: generationToken,
            status: status
        )
    }

    /// Генерирует сцену из текстового описания
    func generateScene() async {
        if let generationTask {
            await generationTask.value
            return
        }

        guard canGenerateScene else {
            diagnosticsLog("[GENERATION] ignored while workspace is busy")
            return
        }

        // A submit always starts from the editable draft, including after a
        // terminal/retryable result. This clears the previous request identity
        // before issuing the next epoch.
        enterGenerationInputState()
        if let issue = sceneDescriptionValidationIssue {
            let message = localizedInputValidationCopy(for: issue)
            if issue == .empty {
                _ = publishGenerationFailure(
                    .emptyInput,
                    retryable: false,
                    message: message,
                    validation: message
                )
            } else {
                _ = publishGenerationState(
                    .input(),
                    validation: message
                )
            }
            return
        }
        let submittedDescription = sceneDescription

        objectBindingResult = nil
        generationEpoch &+= 1
        let generationToken = generationEpoch
        let requestID = UUID()
        guard publishGenerationState(
            .validating(requestID: requestID, epoch: generationToken),
            status: localizedCopy(.generatorStatusAnalyzing),
            clearError: true,
            clearValidation: true
        ) else {
            return
        }

        guard isARSessionReady else {
            _ = publishGenerationFailure(
                .arNotReady,
                retryable: true,
                message: localizedCopy(.generatorErrorARNotReady),
                expectedRequestID: requestID,
                expectedEpoch: generationToken
            )
            return
        }

        guard let cameraTransform = currentCameraTransform else {
            _ = publishGenerationFailure(
                .cameraPosition,
                retryable: true,
                message: localizedCopy(.generatorErrorCameraPosition),
                expectedRequestID: requestID,
                expectedEpoch: generationToken
            )
            return
        }

        generationLogCounter += 1
        let generationID = "generation_\(generationLogCounter)"
        let submittedMarkedObjects = markedObjects
        let submittedDetectedObjects = detectedObjects
        let submittedDetectedPlanes = detectedPlanes
        let bindingRequestSnapshot = objectBindingExtractor.makeObjectBindingRequestSnapshot(
            requestID: requestID,
            epoch: generationToken,
            description: submittedDescription,
            markedObjects: submittedMarkedObjects,
            detectedObjects: submittedDetectedObjects,
            aliasToObjectRef: MarkedObjectMatcher.uniqueAliasBindings(
                submittedMarkedObjects.map { ($0.name, $0.canonicalMarkedObjectID) }
            )
        )

        // These seams are request-owned even though the current local parser
        // has no separate queue/leader backend yet.
        guard publishGenerationState(
            .accepted(requestID: requestID, epoch: generationToken),
            expectedRequestID: requestID,
            expectedEpoch: generationToken
        ), publishGenerationState(
            .queued(requestID: requestID, epoch: generationToken),
            expectedRequestID: requestID,
            expectedEpoch: generationToken
        ), publishGenerationState(
            .leader(requestID: requestID, epoch: generationToken),
            expectedRequestID: requestID,
            expectedEpoch: generationToken
        ), publishGenerationState(
            .generating(requestID: requestID, epoch: generationToken, stage: .reading),
            expectedRequestID: requestID,
            expectedEpoch: generationToken,
            status: localizedCopy(.generatorStatusAnalyzing)
        ) else {
            return
        }

        #if DEBUG
        testingGenerationOwnerCount += 1
        #endif

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performGeneration(
                generationID: generationID,
                requestID: requestID,
                generationToken: generationToken,
                submittedDescription: submittedDescription,
                cameraTransform: cameraTransform,
                markedObjects: submittedMarkedObjects,
                detectedObjects: submittedDetectedObjects,
                detectedPlanes: submittedDetectedPlanes,
                bindingRequestSnapshot: bindingRequestSnapshot
            )
        }
        generationTask = task
        await task.value
        if generationEpoch == generationToken {
            generationTask = nil
        }
    }

    private func performGeneration(
        generationID: String,
        requestID: UUID,
        generationToken: UInt,
        submittedDescription: String,
        cameraTransform: simd_float4x4,
        markedObjects: [MarkedObject],
        detectedObjects: [DetectedObject],
        detectedPlanes: [ScenePlaneSnapshot],
        bindingRequestSnapshot: SceneObjectBindingRequestSnapshot
    ) async {
        guard generationIsCurrent(generationToken, requestID: requestID) else { return }

        // Логирование входных данных
        print("🔍 [VIEWMODEL][\(generationID)] === НАЧАЛО ГЕНЕРАЦИИ СЦЕНЫ ===")
        SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] start descriptionChars=\(submittedDescription.count), markedObjects=\(markedObjects.count)")
        print("🔍 [VIEWMODEL] Описание: '\(submittedDescription)'")
        print("🔍 [VIEWMODEL] Размеченных объектов: \(markedObjects.count)")
        for (index, marker) in markedObjects.enumerated() {
            print("🔍 [VIEWMODEL]   MarkedObject[\(index)]: name='\(marker.name)', type=\(marker.type.rawValue), id=\(marker.id.uuidString.prefix(8))")
        }

        // 1. Парсим описание с учётом markedObjects (async — поддержка LLM fallback)
        print("🔍 [VIEWMODEL] Вызов parserService.parseAsync()...")
        guard publishGenerationStage(
            .reading,
            status: localizedCopy(.generatorStatusReading),
            requestID: requestID,
            generationToken: generationToken
        ) else { return }
#if DEBUG
        if generationDebugDelay > 0 {
            let delay = UInt64(generationDebugDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard generationIsCurrent(generationToken, requestID: requestID) else { return }
        }
#endif
        await Task.yield()
        guard generationIsCurrent(generationToken, requestID: requestID) else { return }

        let parserOutput: (
            result: ParsingResult,
            runtimeTrace: SceneRuntimeTrace?,
            chunkState: SceneChunkState?,
            visualOverlays: [SceneVisualOverlay]
        )
#if DEBUG
        if let testingParserResultOverride {
            parserOutput = (
                result: await testingParserResultOverride(submittedDescription, markedObjects),
                runtimeTrace: nil,
                chunkState: nil,
                visualOverlays: []
            )
        } else {
            parserOutput = await parserService.parseAsyncForGeneration(
                submittedDescription,
                markedObjects: markedObjects
            )
        }
#else
        parserOutput = await parserService.parseAsyncForGeneration(
            submittedDescription,
            markedObjects: markedObjects
        )
#endif
        guard generationIsCurrent(generationToken, requestID: requestID) else { return }
        parserService.releaseLocalModelResources(reason: "scene_generation_parse_complete")
        SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] parser finished and LLM resources requested for release")
        let result = parserOutput.result
        let script = result.script
        let runtimeTrace = parserOutput.runtimeTrace

        logParsedScriptDetails(script, diagnostics: result.diagnostics, generationID: generationID)
        print("🔍 [VIEWMODEL] Результат парсинга:")
        print("🔍 [VIEWMODEL]   Actors: \(script.actors.count)")
        for (index, actor) in script.actors.enumerated() {
            print("🔍 [VIEWMODEL]     Actor[\(index)]: id='\(actor.id)', type=\(actor.type.rawValue), name='\(actor.name ?? "nil")'")
        }
        print("🔍 [VIEWMODEL]   Objects: \(script.objects.count)")
        for (index, object) in script.objects.enumerated() {
            print("🔍 [VIEWMODEL]     Object[\(index)]: id='\(object.id)', type=\(object.type.rawValue), name='\(object.name ?? "nil")', detectedPosition=\(object.detectedPosition != nil ? "YES" : "NO")")
        }
        print("🔍 [VIEWMODEL]   Beats: \(script.beats.count), Actions: \(script.actions.count)")
        for (beatIndex, beat) in script.beats.enumerated() {
            print("🔍 [VIEWMODEL]     Beat[\(beatIndex)]: id='\(beat.id)', actions=\(beat.actions.count)")
            for (actionIndex, action) in beat.actions.enumerated() {
                print("🔍 [VIEWMODEL]       Action[\(actionIndex)]: id='\(action.id)', actorId='\(action.actorId)', type=\(action.type.rawValue), target=\(action.target ?? "nil"), holding=\(action.holdingObject ?? "nil"), direction=\(action.direction?.rawValue ?? "nil"), dialogue='\(action.dialogue ?? "nil")', fallback='\(action.fallbackText ?? "nil")', source='\(action.sourceText ?? "nil")'")
            }
        }
        print("🔍 [VIEWMODEL]   Confidence: \(result.diagnostics.confidence)")
        print("🔍 [VIEWMODEL]   Matched markedObjects: \(result.diagnostics.matchedMarkedObjects.count)")
        if let runtimeTrace {
            print("🔍 [VIEWMODEL]   Runtime route: \(runtimeTrace.route.rawValue)")
            print("🔍 [VIEWMODEL]   Runtime reasons: \(runtimeTrace.reasons.joined(separator:","))")
        }

        // Отображаем диагностику в статусе
        if runtimeTrace?.route == .needsClarification {
            let clarification = parserService.clarificationMessage(for: runtimeTrace)
                ?? localizedCopy(.generatorClarification)
            guard publishGenerationState(
                .clarification(
                    requestID: requestID,
                    epoch: generationToken,
                    message: clarification
                ),
                expectedRequestID: requestID,
                expectedEpoch: generationToken,
                status: localizedCopy(.generatorClarification),
                error: clarification
            ) else { return }
            SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] awaiting clarification")
            SceneGeneratorDiagnosticsLogger.shared.flush()
            return
        } else if runtimeTrace?.route == .offloadRemote {
            guard publishGenerationStatus(
                localizedCopy(.generatorStatusParserFallback),
                requestID: requestID,
                generationToken: generationToken
            ) else { return }
        } else if result.diagnostics.confidence < 0.6 {
            guard publishGenerationStatus(
                localizedCopy(
                    .generatorStatusLowConfidence,
                    arguments: [Int(result.diagnostics.confidence * 100)]
                ),
                requestID: requestID,
                generationToken: generationToken
            ) else { return }
            // M1-018 ErrorPresentationOwner: parse notes are internal English
            // diagnostics ("router=…", "trace:…"); the localized low-confidence
            // status is the user-facing signal. Notes stay in the diagnostics
            // log and the debug decision trace, never in production errors.
        } else {
            guard publishGenerationStatus(
                localizedCopy(
                    .generatorStatusParsed,
                    arguments: [Int(result.diagnostics.confidence * 100)]
                ),
                requestID: requestID,
                generationToken: generationToken
            ) else { return }
        }

        if script.isEmpty {
            let message = localizedCopy(.generatorErrorParseEmpty)
            let validation = sceneDescription == submittedDescription ? message : nil
            _ = publishGenerationFailure(
                .parse,
                retryable: false,
                message: message,
                expectedRequestID: requestID,
                expectedEpoch: generationToken,
                validation: validation
            )
            SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] failed empty script")
            SceneGeneratorDiagnosticsLogger.shared.flush()
            return
        }

        let resolvedObjectBindings = objectBindingExtractor.resolveObjectBindings(
            scriptObjects: script.objects,
            request: bindingRequestSnapshot
        )
        guard generationIsCurrent(generationToken, requestID: requestID) else { return }
        objectBindingResult = resolvedObjectBindings
        diagnosticsLog(
            "[GENERATION][\(generationID)] object binding bound=\(resolvedObjectBindings.boundBindings.count), diagnostics=\(resolvedObjectBindings.diagnostics.count)"
        )
        if stopForUnresolvedObjectBindings(
            resolvedObjectBindings,
            requestID: requestID,
            generationToken: generationToken
        ) {
            SceneGeneratorDiagnosticsLogger.shared.log(
                "[GENERATION][\(generationID)] stopped before planning because object binding was unresolved"
            )
            SceneGeneratorDiagnosticsLogger.shared.flush()
            return
        }

        guard publishGenerationStage(
            .planning,
            status: localizedCopy(.generatorStatusPlanning),
            requestID: requestID,
            generationToken: generationToken
        ) else { return }
        await Task.yield()
        guard generationIsCurrent(generationToken, requestID: requestID) else { return }

        // 2. Сопоставляем объекты с размеченными (приоритет) и детекциями
        // Объекты из markedObjects уже включены в script.objects с detectedPosition
        print("🔍 [VIEWMODEL] Сопоставление объектов с markedObjects и детекциями...")
        print("🔍 [VIEWMODEL]   До сопоставления: objects.count=\(script.objects.count)")
        let matchedObjects = matchObjectsWithMarkedAndDetected(
            script.objects,
            bindingResult: resolvedObjectBindings
        )
        print("🔍 [VIEWMODEL]   После сопоставления: objects.count=\(matchedObjects.count)")
        for (index, object) in matchedObjects.enumerated() {
            print("🔍 [VIEWMODEL]     MatchedObject[\(index)]: id='\(object.id)', type=\(object.type.rawValue), detectedPosition=\(object.detectedPosition != nil ? "YES" : "NO")")
        }

        let updatedScript = SceneScript(
            sceneHeading: script.sceneHeading,
            locationName: script.locationName,
            interiorExterior: script.interiorExterior,
            timeOfDay: script.timeOfDay,
            actors: script.actors,
            objects: matchedObjects,
            beats: script.beats,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )

        // 3. Планируем размещение с учётом размеченных объектов
        print("🔍 [VIEWMODEL] Планирование размещения...")
        print("🔍 [VIEWMODEL]   Script для планирования: actors=\(updatedScript.actors.count), objects=\(updatedScript.objects.count), beats=\(updatedScript.beats.count), actions=\(updatedScript.actions.count)")
        let planned = plannerService.planScene(
            script: updatedScript,
            cameraTransform: cameraTransform,
            // All real-world inputs were resolved above.  Passing the raw
            // arrays here would re-enable SpatialPlanner's historical
            // first-same-type fallback for ambiguous objects.
            detectedObjects: [],
            availablePlanes: detectedPlanes,
            markedObjects: []
        )
        let plannedWithBindingSources = applyBindingSources(
            to: planned,
            bindingResult: resolvedObjectBindings
        )
        guard generationIsCurrent(generationToken, requestID: requestID) else { return }

        print("🔍 [VIEWMODEL] Результат планирования:")
        print("🔍 [VIEWMODEL]   PlacedActors: \(plannedWithBindingSources.placedActors.count)")
        for (index, actor) in plannedWithBindingSources.placedActors.enumerated() {
            print("🔍 [VIEWMODEL]     PlacedActor[\(index)]: id='\(actor.id)', actorId='\(actor.actorId)', type=\(actor.type.rawValue), name='\(actor.name ?? "nil")', label='\(displayName(for: actor))', path.count=\(actor.path.count)")
        }
        print("🔍 [VIEWMODEL]   PlacedObjects: \(plannedWithBindingSources.placedObjects.count)")
        for (index, object) in plannedWithBindingSources.placedObjects.enumerated() {
            print("🔍 [VIEWMODEL]     PlacedObject[\(index)]: id='\(object.id)', objectId='\(object.objectId)', type=\(object.type.rawValue), isRealWorld=\(object.isRealWorld), placementSource=\(object.placementSource.rawValue)")
        }
        logPlannedSceneDetails(plannedWithBindingSources, script: updatedScript, generationID: generationID)

        guard publishGenerationStage(
            .placing,
            status: localizedCopy(.generatorStatusPlacing),
            requestID: requestID,
            generationToken: generationToken
        ) else { return }
        await Task.yield()
        guard generationIsCurrent(generationToken, requestID: requestID) else { return }

        // The model and AR replacement stay in one MainActor commit block.
        cancelAllAnimations()
        resetPlaybackUIState(clearTimeline: true)
        removePlacedSceneEntities(reason: "generation_commit \(generationID)")
        parsedScript = updatedScript
        parsingResult = result
        sceneChunkState = parserOutput.chunkState
        visualOverlays = parserOutput.visualOverlays
        plannedScene = plannedWithBindingSources
        beatTimelineItems = buildBeatTimelineItems(for: plannedWithBindingSources, script: updatedScript)
        refreshStoryboardBeatItems()
        activeStoryboardEditDraft = nil
        storyboardDragFeedback = nil

        // 4. Создаём 3D объекты в AR
        placeObjectsInAR(plannedWithBindingSources)

        guard generationIsCurrent(generationToken, requestID: requestID) else { return }
        // The success edge is published only after the existing atomic
        // model/AR commit and persistence handoff have both been reached.
        persistProjectMetadata()
        guard generationIsCurrent(generationToken, requestID: requestID),
              publishGenerationState(
                  .success(requestID: requestID, epoch: generationToken),
                  expectedRequestID: requestID,
                  expectedEpoch: generationToken,
                  clearError: true,
                  clearValidation: true
              ) else { return }
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
        SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] complete actors=\(plannedWithBindingSources.placedActors.count), objects=\(plannedWithBindingSources.placedObjects.count)")
        SceneGeneratorDiagnosticsLogger.shared.flush()
        guard generationIsCurrent(generationToken, requestID: requestID) else { return }

        // Закрываем sheet
        showInputSheet = false
    }

    private func generationIsCurrent(_ generationToken: UInt, requestID: UUID? = nil) -> Bool {
        guard !Task.isCancelled,
              !isWorkspaceReleased,
              generationEpoch == generationToken else {
            return false
        }
        guard let requestID else { return true }
        return generationRequestState.requestID == requestID
            && generationRequestState.epoch == generationToken
    }

    /// Missing/ambiguous real-world references are a closed gate for the
    /// current request. M5-017 may consume objectBindingResult to present
    /// clarification, but no planning, AR replacement, persistence, or
    /// success edge is allowed past this method.
    @discardableResult
    private func stopForUnresolvedObjectBindings(
        _ result: SceneObjectBindingResult,
        requestID: UUID,
        generationToken: UInt
    ) -> Bool {
        let unresolved = result.resolutions.filter { $0.state != .bound }
        guard !unresolved.isEmpty else { return false }
        let message = localizedCopy(.generatorClarification)
        let detail = unresolved
            .map { "\($0.reference)=\($0.state.rawValue)" }
            .sorted()
            .joined(separator: ",")
        diagnosticsLog("[GENERATION] object binding clarification required: \(detail)")
        _ = publishGenerationState(
            .clarification(requestID: requestID, epoch: generationToken, message: message),
            expectedRequestID: requestID,
            expectedEpoch: generationToken,
            status: message,
            error: message
        )
        return true
    }

    /// Запускает воспроизведение анимации
    func playScene() {
        guard plannedScene != nil else {
            errorMessage = localizedCopy(.generatorErrorNoScene)
            diagnosticsLog("🎬 [PLAYBACK] playScene rejected: plannedScene=nil")
            return
        }

        guard !isGenerating, !isPlaying, !isRecording, !isRecordingFinalizing, !isMarkingMode else {
            diagnosticsLog("🎬 [PLAYBACK] playScene ignored: busy generating=\(isGenerating) playing=\(isPlaying) recording=\(isRecording) finalizing=\(isRecordingFinalizing) marking=\(isMarkingMode)")
            return
        }

        guard isARSessionReady, !isARSessionInterrupted, !isARSessionRecovering else {
            errorMessage = localizedCopy(.generatorErrorARNotReady)
            diagnosticsLog("🎬 [PLAYBACK] playScene rejected: AR not ready interrupted=\(isARSessionInterrupted) recovering=\(isARSessionRecovering)")
            return
        }

        guard let planned = plannedScene else { return }

        playbackLogCounter += 1
        let playbackID = "playback_\(playbackLogCounter)"
        diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] playScene requested actors=\(planned.placedActors.count), objects=\(planned.placedObjects.count)")
        
        // Отменяем все предыдущие анимации
        cancelAllAnimations()
        if activeStoryboardEditDraft != nil {
            cancelActiveStoryboardActorDrag()
            activeStoryboardEditDraft = nil
            storyboardDragFeedback = nil
            diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] storyboard editor closed before playback")
        }
        isHintsEnabled = false
        clearHintPresentation()
        currentPlaybackLogID = playbackID
        lastLoggedPlaybackBeatIndex = nil
        
        beatTimelineItems = buildBeatTimelineItems(for: planned, script: parsedScript)
        logPlaybackPlan(planned, timeline: beatTimelineItems, playbackID: playbackID)
        SceneGeneratorDiagnosticsLogger.shared.flush()
        isPlaying = true
        resetPlaybackUIState(clearTimeline: false)
        refreshWorkspaceMode()
        statusMessage = localizedCopy(.generatorStatusPlayback)
        
        // Инициализируем счётчики анимаций
        completedActorAnimations = 0
        totalActorAnimations = planned.placedActors.filter { $0.path.count > 1 }.count
        if totalActorAnimations == 0 {
            diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] no animated actors: actors=\(planned.placedActors.count)")
            isPlaying = false
            statusMessage = localizedCopy(.generatorStatusNoActions)
            setActorsToInitialPositionsInstantly()
            currentPlaybackLogID = nil
            lastLoggedPlaybackBeatIndex = nil
            SceneGeneratorDiagnosticsLogger.shared.flush()
            return
        }
        
        // Мгновенно устанавливаем актёров на начальные позиции (без анимации)
        setActorsToInitialPositionsInstantly()
        
        // Небольшая задержка чтобы позиции успели примениться
        let startWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPlaying else { return }
            self.diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] start animations actors=\(planned.placedActors.count), animatedActors=\(self.totalActorAnimations)")
            
            // Анимируем каждого актёра по его траектории
            for actor in planned.placedActors {
                self.animateActor(actor)
            }
            self.startPlaybackTimelineTimer()
            self.schedulePlaybackCaptions(for: planned)
            self.scheduleScreenTextOverlays()
        }
        animationWorkItems.append(startWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: startWorkItem)
    }
    
    /// Останавливает воспроизведение
    func stopScene() {
        let playbackID = currentPlaybackLogID
        diagnosticsLog("🎬 [PLAYBACK][\(playbackID ?? "nil")] stopScene requested elapsed=\(formatSeconds(playbackElapsedTime))")
        // Отменяем все запланированные анимации
        cancelAllAnimations()
        
        isPlaying = false
        resetPlaybackUIState(clearTimeline: true)
        refreshWorkspaceMode()
        refreshIdleStatusMessage()

        // Мгновенно возвращаем актёров на начальные позиции
        currentPlaybackLogID = playbackID
        setActorsToInitialPositionsInstantly()
        diagnosticsLog("🎬 [PLAYBACK][\(playbackID ?? "nil")] stopScene complete")
        currentPlaybackLogID = nil
        lastLoggedPlaybackBeatIndex = nil
        SceneGeneratorDiagnosticsLogger.shared.flush()
    }
    
    /// Отменяет все запланированные анимации
    private func cancelAllAnimations() {
        if !animationWorkItems.isEmpty || playbackTimelineTimer != nil || isPlaying {
            diagnosticsLog("🎬 [PLAYBACK][\(currentPlaybackLogID ?? "nil")] cancel animations workItems=\(animationWorkItems.count), isPlaying=\(isPlaying)")
        }
        // Отменяем все DispatchWorkItems
        for workItem in animationWorkItems {
            workItem.cancel()
        }
        animationWorkItems.removeAll()
        
        // Сбрасываем счётчики
        completedActorAnimations = 0
        totalActorAnimations = 0
        invalidatePlaybackTimelineTimer()
        activeDialogueCaptionID = nil
        activeActionCaptionID = nil
        activeScreenTextCaptionID = nil
        currentPlaybackLogID = nil
        lastLoggedPlaybackBeatIndex = nil
        
        // Останавливаем все текущие RealityKit анимации
        stopAllEntityAnimations()
    }
    
    /// Останавливает все RealityKit анимации, фиксируя текущие позиции
    private func stopAllEntityAnimations() {
        for (_, entity) in placedEntities {
            // Устанавливаем текущую трансформацию как конечную (останавливает анимацию)
            entity.stopAllAnimations()
        }
        for (_, entity) in actorFocusEntities {
            entity.stopAllAnimations()
        }
    }

    private func resetPlaybackUIState(clearTimeline: Bool) {
        activeDialogueCaption = nil
        activeActionCaption = nil
        activeScreenTextCaption = nil
        activeDialogueCaptionID = nil
        activeActionCaptionID = nil
        activeScreenTextCaptionID = nil
        activeBeatIndex = 0
        beatProgress = 0
        playbackElapsedTime = 0
        playbackStartDate = nil
        hideActorFocus()
        removeActiveTargetCue()
        if clearTimeline {
            beatTimelineItems = []
        }
    }

    private func invalidatePlaybackTimelineTimer() {
        playbackTimelineTimer?.invalidate()
        playbackTimelineTimer = nil
        playbackStartDate = nil
    }

    private func diagnosticsLog(_ message: String) {
        SceneGeneratorDiagnosticsLogger.shared.log(message)
    }

    private func logParsedScriptDetails(_ script: SceneScript, diagnostics: ParsingDiagnostics, generationID: String) {
        diagnosticsLog("🧭 [TRACE][\(generationID)] parsed script summary: actors=\(script.actors.count), objects=\(script.objects.count), beats=\(script.beats.count), actions=\(script.actions.count), confidence=\(diagnostics.confidence)")
        for actor in script.actors {
            diagnosticsLog("🧭 [TRACE][\(generationID)] script.actor id=\(actor.id), type=\(actor.type.rawValue), name=\(actor.name ?? "nil")")
        }
        for object in script.objects {
            diagnosticsLog("🧭 [TRACE][\(generationID)] script.object id=\(object.id), type=\(object.type.rawValue), name=\(object.name ?? "nil"), relative=\(object.relativePosition.rawValue), detected=\(object.detectedPosition.map(formatPosition) ?? "nil")")
        }
        for (beatIndex, beat) in script.beats.enumerated() {
            diagnosticsLog("🧭 [TRACE][\(generationID)] script.beat[\(beatIndex)] id=\(beat.id), minDuration=\(beat.minDuration.map(formatSeconds) ?? "nil"), actions=\(beat.actions.count)")
            for action in beat.actions {
                diagnosticsLog("🧭 [TRACE][\(generationID)] script.action beat=\(beat.id), id=\(action.id), actor=\(action.actorId), type=\(action.type.rawValue), target=\(action.target ?? "nil"), holding=\(action.holdingObject ?? "nil"), direction=\(action.direction?.rawValue ?? "nil"), pose=\(action.resultingPose?.rawValue ?? "nil"), dialogue=\(quotedForLog(action.dialogue)), fallback=\(quotedForLog(action.fallbackText)), source=\(quotedForLog(action.sourceText))")
            }
        }
    }

    private func logPlannedSceneDetails(_ planned: PlannedScene, script: SceneScript, generationID: String) {
        diagnosticsLog("🧭 [TRACE][\(generationID)] planned scene summary: actors=\(planned.placedActors.count), objects=\(planned.placedObjects.count), scriptBeats=\(script.beats.count)")
        for object in planned.placedObjects {
            diagnosticsLog("🧭 [TRACE][\(generationID)] placed.object id=\(object.id), objectId=\(object.objectId), type=\(object.type.rawValue), position=\(formatPosition(object.position)), rotation=\(formatFloat(object.rotation)), source=\(object.placementSource.rawValue), isDetected=\(object.isDetected)")
        }
        for actor in planned.placedActors {
            diagnosticsLog("🧭 [TRACE][\(generationID)] placed.actor id=\(actor.id), actorId=\(actor.actorId), label=\(displayName(for: actor)), type=\(actor.type.rawValue), initial=\(formatPosition(actor.initialPosition)), initialRotation=\(formatFloat(actor.initialRotation)), pathPoints=\(actor.path.count), durations=\(actor.pathDurations.map(formatSeconds).joined(separator: ","))")
            for pointIndex in actor.path.indices {
                let beatID = actor.pathBeatIDs.indices.contains(pointIndex) ? actor.pathBeatIDs[pointIndex] : nil
                let pose = actor.pathPoses.indices.contains(pointIndex) ? actor.pathPoses[pointIndex].rawValue : "nil"
                let annotation = actor.pathAnnotations.indices.contains(pointIndex) ? actor.pathAnnotations[pointIndex] : nil
                diagnosticsLog("🧭 [TRACE][\(generationID)] placed.actor.path actor=\(displayName(for: actor)), point=\(pointIndex), position=\(formatPosition(actor.path[pointIndex])), beat=\(beatID ?? "nil"), pose=\(pose), annotationKind=\(annotation?.kind.rawValue ?? "nil"), annotation=\(quotedForLog(annotation?.text))")
            }
        }
    }

    private func logPlaybackPlan(_ planned: PlannedScene, timeline: [BeatPlaybackTimelineItem], playbackID: String) {
        diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] plan summary: actors=\(planned.placedActors.count), objects=\(planned.placedObjects.count), timelineBeats=\(timeline.count)")
        for item in timeline {
            diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] timeline beatIndex=\(item.index), beatID=\(item.beatID), start=\(formatSeconds(item.startTime)), duration=\(formatSeconds(item.duration)), dialogue=\(item.hasDialogueCaption), action=\(item.hasActionCaption)")
        }
        for actor in planned.placedActors {
            diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] actor plan label=\(displayName(for: actor)), id=\(actor.id), actorId=\(actor.actorId), pathPoints=\(actor.path.count), segments=\(actor.pathDurations.count)")
            for segmentIndex in 0..<actor.pathDurations.count {
                let from = actor.path.indices.contains(segmentIndex) ? formatPosition(actor.path[segmentIndex]) : "nil"
                let to = actor.path.indices.contains(segmentIndex + 1) ? formatPosition(actor.path[segmentIndex + 1]) : "nil"
                let beatID = actor.pathBeatIDs.indices.contains(segmentIndex + 1) ? actor.pathBeatIDs[segmentIndex + 1] : nil
                let annotation = actor.pathAnnotations.indices.contains(segmentIndex + 1) ? actor.pathAnnotations[segmentIndex + 1] : nil
                diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] actor segment label=\(displayName(for: actor)), segment=\(segmentIndex), beat=\(beatID ?? "nil"), duration=\(formatSeconds(actor.pathDurations[segmentIndex])), from=\(from), to=\(to), annotationKind=\(annotation?.kind.rawValue ?? "nil"), annotation=\(quotedForLog(annotation?.text))")
            }
        }
    }
    
    /// Сбрасывает сцену
    func resetScene() {
        if isRecording {
            stopRecording()
        }

        // Отменяем все анимации
        cancelAllAnimations()
        
        // Удаляем все размещённые объекты
        sceneAnchor?.removeFromParent()
        sceneAnchor = nil
        placedEntities.removeAll()
        clearSceneVisualState()
        
        plannedScene = nil
        parsedScript = nil
        sceneChunkState = nil
        visualOverlays = []
        storyboardBeatItems = []
        activeStoryboardEditDraft = nil
        isPlaying = false
        isHintsEnabled = false
        clearHintPresentation()
        resetPlaybackUIState(clearTimeline: true)
        if !generationRequestState.isExecutionInFlight {
            _ = publishGenerationState(.idle)
        }
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
        Task { _ = await persistProjectSnapshot() }
    }
    
    /// Показывает sheet ввода
    func showInput() {
        let issue = sceneDescriptionValidationIssue
        enterGenerationInputState(clearValidation: issue == nil || issue == .empty)
        if let issue, issue != .empty {
            _ = publishGenerationState(
                .input(),
                validation: localizedInputValidationCopy(for: issue)
            )
        }
        showInputSheet = true
    }
    
    // MARK: - Object Marking
    
    /// Включает/выключает режим разметки
    func toggleMarkingMode() {
        guard canToggleMarkingMode else {
            diagnosticsLog("[MARKER] mode toggle ignored while workspace is busy")
            return
        }
        if !isMarkingMode {
            isHintsEnabled = false
            clearHintPresentation()
        }
        isMarkingMode.toggle()
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
    }
    
    /// Обрабатывает tap для размещения маркера
    func handleTapForMarker(at screenPoint: CGPoint) {
        diagnosticsLog("[TOUCH_TRACE] marker tap received point=(\(formatFloat(Float(screenPoint.x))), \(formatFloat(Float(screenPoint.y)))), marking=\(isMarkingMode), hasARView=\(arView != nil)")
        guard isMarkingMode, let arView = arView else {
            diagnosticsLog("[MARKER] tap rejected before raycast: marking=\(isMarkingMode), hasARView=\(arView != nil)")
            return
        }

        // Demo-fast path: raycast не требует удерживать depth CVPixelBuffer между AR-кадрами.
        var results = arView.raycast(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any)
        if results.isEmpty {
            results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        }

        let worldPosition: Position3D
        if let firstResult = results.first {
            let transform = firstResult.worldTransform
            let position = transform.columns.3
            worldPosition = Position3D(x: position.x, y: position.y, z: position.z)
        } else if let fallbackPosition = fallbackSurfacePosition(from: screenPoint) {
            worldPosition = fallbackPosition
            diagnosticsLog("[MARKER] raycast fallback used position=\(formatPosition(fallbackPosition))")
        } else {
            statusMessage = localizedCopy(.generatorErrorMarkFailed)
            diagnosticsLog("[MARKER] tap rejected: no raycast or fallback at point=(\(formatFloat(Float(screenPoint.x))), \(formatFloat(Float(screenPoint.y))))")
            return
        }

        print("🔍 [MARKER] Позиция маркера определена: x=\(worldPosition.x), y=\(worldPosition.y), z=\(worldPosition.z)")
        diagnosticsLog("[MARKER] tap accepted position=\(formatPosition(worldPosition))")
        pendingMarkerPosition = worldPosition
        showMarkerNameInput = true
    }
    
    /// Создаёт маркер с указанным именем
    func createMarker(withName name: String) {
        guard let position = pendingMarkerPosition else { return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = localizedCopy(.generatorErrorMarkerName)
            return
        }
        
        let marker = MarkedObject(name: name, position: position)
        markedObjects.append(marker)
        
        // Создаём визуальный маркер в AR
        placeMarkerEntity(for: marker)
        
        pendingMarkerPosition = nil
        showMarkerNameInput = false
        isMarkingMode = false
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
    }
    
    /// Отменяет создание маркера
    func cancelMarkerCreation() {
        pendingMarkerPosition = nil
        showMarkerNameInput = false
    }
    
    /// Удаляет маркер
    func removeMarker(_ marker: MarkedObject) {
        markedObjects.removeAll { $0.id == marker.id }
        
        // Удаляем визуальный маркер
        if let entity = markerEntities[marker.id] {
            entity.removeFromParent()
            markerEntities.removeValue(forKey: marker.id)
        }
        updateObjectLabelOverlays()
        
        cleanupMarkersAnchorIfNeeded()
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
    }
    
    /// Удаляет все маркеры
    func clearAllMarkers() {
        markedObjects.removeAll()
        
        // Удаляем все визуальные маркеры
        for (_, entity) in markerEntities {
            entity.removeFromParent()
        }
        markerEntities.removeAll()
        updateObjectLabelOverlays()
        
        cleanupMarkersAnchorIfNeeded()
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
    }
    
    /// Размещает визуальный маркер в AR (точно в указанной позиции)
    private func placeMarkerEntity(for marker: MarkedObject) {
        guard let arView = arView else { return }
        
        // Создаём anchor для маркеров если его ещё нет
        if markersAnchor == nil {
            let anchor = AnchorEntity(world: .zero)
            markersAnchor = anchor
            arView.scene.addAnchor(anchor)
        }
        
        // Создаём визуальный маркер - сфера с подписью (отличается от виртуальных объектов)
        let markerEntity = createMarkerEntity(for: marker)
        
        // marker.worldPosition хранит точку попадания raycast; proxy поднимаем только на свою толщину.
        markerEntity.position = marker.worldPosition.simdVector + SIMD3<Float>(
            0,
            markerProxyVerticalOffset(for: marker.type),
            0
        )
        
        print("🔍 [MARKER] Размещение маркера '\(marker.name)' в позиции: x=\(marker.worldPosition.x), y=\(marker.worldPosition.y), z=\(marker.worldPosition.z)")
        
        markersAnchor?.addChild(markerEntity)
        markerEntities[marker.id] = markerEntity
        updateObjectLabelOverlays()
    }

    private func cleanupMarkersAnchorIfNeeded() {
        if markerEntities.isEmpty {
            markersAnchor?.removeFromParent()
            markersAnchor = nil
        }
    }
    
    /// Создаёт entity для маркера (отличается от виртуальных объектов)
    private func createMarkerEntity(for marker: MarkedObject) -> ModelEntity {
        let proxySize = markerProxySize(for: marker.type)
        let mesh: MeshResource
        switch marker.type {
        case .generic:
            mesh = .generateSphere(radius: proxySize.x / 2)
        default:
            mesh = .generateBox(size: proxySize)
        }

        let markerColor = marker.markerColor.withAlphaComponent(marker.type == .generic ? 0.82 : 0.34)
        let material = SimpleMaterial(
            color: markerColor,
            roughness: 0.35,
            isMetallic: false
        )
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.generateCollisionShapes(recursive: true)

        if marker.type == .table {
            addTableMarkerOutline(to: entity, size: proxySize, color: marker.markerColor)
        }

        diagnosticsLog("[AR_VISUAL] marker proxy created id=\(marker.id.uuidString.prefix(8)), type=\(marker.type.rawValue), size=\(formatVector(proxySize))")
        return entity
    }

    private func markerProxySize(for type: SceneObject.ObjectType) -> SIMD3<Float> {
        switch type {
        case .table:
            return SIMD3<Float>(0.72, 0.014, 0.46)
        case .phone:
            return SIMD3<Float>(0.20, 0.018, 0.11)
        default:
            return SIMD3<Float>(0.10, 0.10, 0.10)
        }
    }

    private func markerProxyVerticalOffset(for type: SceneObject.ObjectType) -> Float {
        markerProxySize(for: type).y / 2 + 0.002
    }

    private func addTableMarkerOutline(to entity: Entity, size: SIMD3<Float>, color: UIColor) {
        let barThickness: Float = 0.018
        let barHeight: Float = 0.018
        let material = SimpleMaterial(color: color.withAlphaComponent(0.86), roughness: 0.3, isMetallic: false)
        let bars: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3<Float>(size.x, barHeight, barThickness), SIMD3<Float>(0, size.y / 2 + 0.006, size.z / 2)),
            (SIMD3<Float>(size.x, barHeight, barThickness), SIMD3<Float>(0, size.y / 2 + 0.006, -size.z / 2)),
            (SIMD3<Float>(barThickness, barHeight, size.z), SIMD3<Float>(size.x / 2, size.y / 2 + 0.006, 0)),
            (SIMD3<Float>(barThickness, barHeight, size.z), SIMD3<Float>(-size.x / 2, size.y / 2 + 0.006, 0)),
        ]
        for (barSize, position) in bars {
            let bar = ModelEntity(mesh: .generateBox(size: barSize), materials: [material])
            bar.position = position
            entity.addChild(bar)
        }
    }
    
    /// Находит размеченный объект по ключевому слову
    func findMarkedObject(forKeyword keyword: String) -> MarkedObject? {
        let lemmatizer = Lemmatizer()
        // Используем улучшенный метод с лемматизацией
        return markedObjects.first { $0.matches(keyword: keyword, lemmatizer: lemmatizer) }
    }
    
    // MARK: - AR Object Placement
    
    private func placeObjectsInAR(_ planned: PlannedScene) {
        guard let arView = arView else { return }
        
        print("🔍 [VIEWMODEL] === РАЗМЕЩЕНИЕ В AR ===")
        print("🔍 [VIEWMODEL] PlacedActors для размещения: \(planned.placedActors.count)")
        print("🔍 [VIEWMODEL] PlacedObjects для размещения: \(planned.placedObjects.count)")
        print("🔍 [VIEWMODEL]   Виртуальных объектов (isRealWorld=false): \(planned.placedObjects.filter { !$0.isRealWorld }.count)")
        print("🔍 [VIEWMODEL]   Реальных объектов (isRealWorld=true): \(planned.placedObjects.filter { $0.isRealWorld }.count)")
        
        // Удаляем предыдущую сцену
        removePlacedSceneEntities(reason: "place_objects")
        
        // Создаём anchor для сцены
        let anchor = AnchorEntity(world: .zero)
        sceneAnchor = anchor
        arView.scene.addAnchor(anchor)
        
        var virtualObjectsPlaced = 0
        // Размещаем только виртуальные объекты (реальные не дублируем)
        for object in planned.placedObjects where !object.isRealWorld {
            print("🔍 [VIEWMODEL] Размещаю виртуальный объект: id='\(object.id)', type=\(object.type.rawValue)")
            diagnosticsLog("[AR_VISUAL] placing object id=\(object.id), objectId=\(object.objectId), type=\(object.type.rawValue), position=\(formatPosition(object.position)), size=\(formatVector(object.size)), source=\(object.placementSource.rawValue), isRealWorld=\(object.isRealWorld)")
            let entity = createSceneObjectEntity(for: object)
            
            entity.position = object.position.simdVector
            entity.orientation = simd_quatf(angle: object.rotation, axis: [0, 1, 0])
            
            anchor.addChild(entity)
            placedEntities[object.id] = entity
            virtualObjectsPlaced += 1
        }
        print("🔍 [VIEWMODEL] Размещено виртуальных объектов: \(virtualObjectsPlaced)")
        
        var actorsPlaced = 0
        // Размещаем актёров
        print("🔍 [VIEWMODEL] Начало размещения актёров, всего в planned.placedActors: \(planned.placedActors.count)")
        for (index, actor) in planned.placedActors.enumerated() {
            let previewPosition = playbackStartPosition(for: actor)
            print("🔍 [VIEWMODEL] Обработка актёра[\(index)]: id='\(actor.id)', actorId='\(actor.actorId)', type=\(actor.type.rawValue), initialPosition=(\(actor.initialPosition.x), \(actor.initialPosition.y), \(actor.initialPosition.z)), previewPosition=(\(previewPosition.x), \(previewPosition.y), \(previewPosition.z))")
            let style = Self.actorRenderStyle(for: actor, at: index)
            actorRenderStyles[actor.id] = style
            let entity = createActorEntity(
                size: actor.size,
                style: style,
                label: displayName(for: actor)
            )
            entity.name = "storyboard_actor|\(actor.id)|\(actor.actorId)"
            
            entity.position = previewPosition.simdVector
            entity.orientation = simd_quatf(angle: actor.initialRotation, axis: [0, 1, 0])
            
            print("🔍 [VIEWMODEL] Создан entity для актёра[\(index)], добавляю в anchor...")
            anchor.addChild(entity)
            placedEntities[actor.id] = entity
            let focusEntity = createActorFocusEntity(style: style, size: actor.size)
            focusEntity.position = previewPosition.simdVector + SIMD3<Float>(0, 0.025, 0)
            focusEntity.isEnabled = false
            anchor.addChild(focusEntity)
            actorFocusEntities[actor.id] = focusEntity
            diagnosticsLog("[AR_VISUAL] actor placed actor=\(displayName(for: actor)), id=\(actor.actorId), initial=\(formatPosition(actor.initialPosition)), preview=\(formatPosition(previewPosition)), pathFirst=\(actor.path.first.map(formatPosition) ?? "nil"), palette=\(style.paletteIndex), color=\(formatVector(style.color))")
            print("🔍 [VIEWMODEL] Актёр[\(index)] добавлен в placedEntities с ключом '\(actor.id)', теперь placedEntities.count=\(placedEntities.count)")
            actorsPlaced += 1
        }
        placePathGuides(for: planned, anchor: anchor)
        updateObjectLabelOverlays()
        print("🔍 [VIEWMODEL] Размещено актёров: \(actorsPlaced) из \(planned.placedActors.count)")
        print("🔍 [VIEWMODEL] Всего entities в placedEntities: \(placedEntities.count)")
        print("🔍 [VIEWMODEL] Ключи в placedEntities: \(placedEntities.keys.sorted().joined(separator: ", "))")
        print("🔍 [VIEWMODEL] === РАЗМЕЩЕНИЕ ЗАВЕРШЕНО ===")
    }

    private func createSceneObjectEntity(for object: PlannedScene.PlacedObject) -> ModelEntity {
        let style = Self.objectRenderStyle(for: object.type)
        diagnosticsLog("[AR_VISUAL] object style id=\(object.id), type=\(object.type.rawValue), kind=\(style.kind), cueRadius=\(formatFloat(style.targetCueRadius))")
        switch style.kind {
        case .phoneProxy:
            return createPhoneProxyEntity(size: object.size, color: object.color)
        case .standardPlaceholder:
            return createPlaceholderEntity(
                size: object.size,
                color: object.color
            )
        }
    }
    
    private func createPlaceholderEntity(
        size: simd_float3,
        color: (r: Float, g: Float, b: Float)
    ) -> ModelEntity {
        // Создаём куб
        let mesh = MeshResource.generateBox(size: size)
        let material = SimpleMaterial(
            color: UIColor(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 0.8),
            roughness: 0.5,
            isMetallic: false
        )
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.generateCollisionShapes(recursive: true)
        
        return entity
    }

    private func createPhoneProxyEntity(
        size: SIMD3<Float>,
        color: (r: Float, g: Float, b: Float)
    ) -> ModelEntity {
        let bodyColor = UIColor(
            red: CGFloat(color.r),
            green: CGFloat(color.g),
            blue: CGFloat(color.b),
            alpha: 0.94
        )
        let body = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: bodyColor, roughness: 0.22, isMetallic: false)]
        )

        let screenSize = SIMD3<Float>(size.x * 0.78, max(size.y * 0.16, 0.006), size.z * 0.68)
        let screen = ModelEntity(
            mesh: .generateBox(size: screenSize),
            materials: [SimpleMaterial(color: UIColor.white.withAlphaComponent(0.92), roughness: 0.12, isMetallic: false)]
        )
        screen.position = SIMD3<Float>(0, size.y / 2 + screenSize.y / 2 + 0.002, 0)
        body.addChild(screen)

        let glow = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(size.x * 1.18, 0.006, size.z * 1.28)),
            materials: [SimpleMaterial(color: UIColor.systemCyan.withAlphaComponent(0.34), roughness: 0.18, isMetallic: false)]
        )
        glow.position = SIMD3<Float>(0, -size.y / 2 - 0.005, 0)
        body.addChild(glow)

        let outlineMaterial = SimpleMaterial(color: UIColor.systemCyan.withAlphaComponent(0.82), roughness: 0.2, isMetallic: false)
        let edgeThickness: Float = 0.008
        let edges: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3<Float>(size.x, edgeThickness, edgeThickness), SIMD3<Float>(0, size.y / 2 + 0.009, size.z / 2)),
            (SIMD3<Float>(size.x, edgeThickness, edgeThickness), SIMD3<Float>(0, size.y / 2 + 0.009, -size.z / 2)),
            (SIMD3<Float>(edgeThickness, edgeThickness, size.z), SIMD3<Float>(size.x / 2, size.y / 2 + 0.009, 0)),
            (SIMD3<Float>(edgeThickness, edgeThickness, size.z), SIMD3<Float>(-size.x / 2, size.y / 2 + 0.009, 0)),
        ]
        for (edgeSize, position) in edges {
            let edge = ModelEntity(mesh: .generateBox(size: edgeSize), materials: [outlineMaterial])
            edge.position = position
            body.addChild(edge)
        }

        body.generateCollisionShapes(recursive: true)
        return body
    }
    
    private func createActorEntity(
        size: simd_float3,
        style: SceneActorRenderStyle,
        label: String
    ) -> ModelEntity {
        let actorColor = style.uiColor
        
        if let personEntity = makePersonEntity() {
            // Используем ту же модель, что и в CameraScreenModule.
            // Нормализуем масштаб по высоте, чтобы анимация и размещение остались предсказуемыми.
            let bounds = personEntity.visualBounds(relativeTo: personEntity)
            let sourceHeight = max(bounds.extents.y, 0.001)
            let scaleFactor = max(size.y, 0.1) / sourceHeight
            personEntity.scale = simd_float3(repeating: scaleFactor)
            applyTintRecursively(entity: personEntity, color: actorColor)
            personEntity.generateCollisionShapes(recursive: true)

            let badge = createBadgeEntity(
                text: label,
                accentColor: actorColor,
                fontSize: 0.068,
                maxWidth: 0.78
            )
            let scaledHeight = bounds.extents.y * scaleFactor
            badge.position = simd_float3(0, scaledHeight / 2 + 0.22, 0)
            personEntity.addChild(badge)
            sceneBillboardEntities.append(badge)
            
            return personEntity
        }
        
        // Fallback, если ассет недоступен.
        let fallbackMesh = MeshResource.generateBox(
            width: size.x,
            height: size.y,
            depth: size.z,
            cornerRadius: min(size.x, size.z) / 4
        )
        let fallbackMaterial = SimpleMaterial(color: actorColor, roughness: 0.3, isMetallic: false)
        let fallbackEntity = ModelEntity(mesh: fallbackMesh, materials: [fallbackMaterial])
        fallbackEntity.generateCollisionShapes(recursive: true)

        let badge = createBadgeEntity(
            text: label,
            accentColor: actorColor,
            fontSize: 0.068,
            maxWidth: 0.78
        )
        badge.position = simd_float3(0, size.y / 2 + 0.22, 0)
        fallbackEntity.addChild(badge)
        sceneBillboardEntities.append(badge)
        
        return fallbackEntity
    }

    private func createBadgeEntity(
        text: String,
        accentColor: UIColor,
        fontSize: CGFloat,
        maxWidth: Float
    ) -> ModelEntity {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeText = trimmed.isEmpty ? localizedCopy(.generatorDefaultObject) : trimmed
        let estimatedTextWidth = min(maxWidth, max(0.24, Float(safeText.count) * Float(fontSize) * 0.62))
        let backgroundSize = SIMD3<Float>(estimatedTextWidth + 0.18, 0.15, 0.022)
        let background = ModelEntity(
            mesh: .generateBox(size: backgroundSize),
            materials: [SimpleMaterial(color: UIColor.black.withAlphaComponent(0.80), roughness: 0.28, isMetallic: false)]
        )

        let accent = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.04, 0.118, 0.027)),
            materials: [SimpleMaterial(color: accentColor.withAlphaComponent(0.96), roughness: 0.25, isMetallic: false)]
        )
        accent.position = SIMD3<Float>(-backgroundSize.x / 2 + 0.04, 0, 0.014)
        background.addChild(accent)

        let textMesh = MeshResource.generateText(
            safeText,
            extrusionDepth: 0.0025,
            font: .boldSystemFont(ofSize: fontSize)
        )
        let textEntity = ModelEntity(
            mesh: textMesh,
            materials: [SimpleMaterial(color: .white, roughness: 0.45, isMetallic: false)]
        )
        textEntity.position = SIMD3<Float>(-estimatedTextWidth / 2 + 0.025, -Float(fontSize) * 0.38, 0.024)
        background.addChild(textEntity)

        return background
    }

    private func createActorFocusEntity(style: SceneActorRenderStyle, size: SIMD3<Float>) -> ModelEntity {
        let focusSize = max(size.x, size.z) + 0.28
        let material = SimpleMaterial(color: style.uiColor.withAlphaComponent(0.26), roughness: 0.25, isMetallic: false)
        let entity = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(focusSize, 0.012, focusSize)),
            materials: [material]
        )
        return entity
    }

    private func clearSceneVisualState() {
        sceneBillboardEntities.removeAll()
        pathGuideEntities.removeAll()
        actorFocusEntities.removeAll()
        actorRenderStyles.removeAll()
        if !objectLabelItems.isEmpty {
            objectLabelItems = []
        }
        removeActiveTargetCue()
    }

    private func removePlacedSceneEntities(reason: String) {
        sceneAnchor?.removeFromParent()
        sceneAnchor = nil
        placedEntities.removeAll()
        clearSceneVisualState()
        diagnosticsLog("[AR_VISUAL] cleared placed scene reason=\(reason)")
    }

    private func playbackStartPosition(for actor: PlannedScene.PlacedActor) -> Position3D {
        actor.path.first ?? actor.initialPosition
    }

    private func placePathGuides(for planned: PlannedScene, anchor: AnchorEntity) {
        var created = 0
        for (index, actor) in planned.placedActors.enumerated() {
            let style = actorRenderStyles[actor.id] ?? Self.actorRenderStyle(for: actor, at: index)
            for segmentIndex in 0..<actor.pathDurations.count {
                guard actor.path.indices.contains(segmentIndex),
                      actor.path.indices.contains(segmentIndex + 1)
                else { continue }

                let start = actor.path[segmentIndex].simdVector
                let end = actor.path[segmentIndex + 1].simdVector
                guard planarDistance(from: start, to: end) > 0.03 else { continue }

                let guide = createLineEntity(
                    from: start + SIMD3<Float>(0, 0.025, 0),
                    to: end + SIMD3<Float>(0, 0.025, 0),
                    thickness: 0.022,
                    color: style.uiColor.withAlphaComponent(0.34)
                )
                anchor.addChild(guide)
                pathGuideEntities.append(guide)
                created += 1
            }
        }
        diagnosticsLog("[AR_VISUAL] path guides created=\(created)")
    }

    private func createLineEntity(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        thickness: Float,
        color: UIColor
    ) -> ModelEntity {
        let delta = end - start
        let length = max(simd_length(delta), 0.001)
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(thickness, thickness, length))
        let material = SimpleMaterial(color: color, roughness: 0.3, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = (start + end) / 2
        entity.orientation = simd_quatf(angle: atan2(delta.x, delta.z), axis: [0, 1, 0])
        return entity
    }

    private func planarDistance(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Float {
        let dx = end.x - start.x
        let dz = end.z - start.z
        return sqrt(dx * dx + dz * dz)
    }

    private func updateBillboardEntities(cameraTransform: simd_float4x4) {
        guard !sceneBillboardEntities.isEmpty else { return }
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        for entity in sceneBillboardEntities where entity.parent != nil {
            orientBillboard(entity, toward: cameraPosition)
        }
    }

    private func updateObjectLabelOverlays() {
        guard let arView else {
            if !objectLabelItems.isEmpty {
                objectLabelItems = []
            }
            return
        }

        let rawLabels: [ARObjectLabelPresentation]
        if let plannedScene {
            rawLabels = plannedScene.placedObjects.compactMap { object in
                makeObjectLabel(
                    id: object.id,
                    text: displayName(for: object),
                    type: object.type,
                    position: object.position,
                    size: object.size,
                    tint: SIMD3<Float>(object.color.r, object.color.g, object.color.b),
                    placementSource: object.placementSource,
                    arView: arView
                )
            }
        } else {
            rawLabels = markedObjects.compactMap { marker in
                makeObjectLabel(
                    id: "marker_\(marker.id.uuidString)",
                    text: marker.name,
                    type: marker.type,
                    position: marker.worldPosition,
                    size: markerProxySize(for: marker.type),
                    tint: rgbVector(from: marker.markerColor),
                    placementSource: .marked,
                    arView: arView
                )
            }
        }

        let nextItems = Self.layoutObjectLabels(rawLabels, canvasSize: arView.bounds.size)
        if objectLabelItems != nextItems {
            objectLabelItems = nextItems
        }
    }

    private var isMarkerNameInputActive: Bool {
        showMarkerNameInput || pendingMarkerPosition != nil
    }

    private func makeObjectLabel(
        id: String,
        text: String,
        type: SceneObject.ObjectType,
        position: Position3D,
        size: SIMD3<Float>,
        tint: SIMD3<Float>,
        placementSource: PlannedScene.PlacedObject.PlacementSource,
        arView: ARView
    ) -> ARObjectLabelPresentation? {
        let labelPosition = position.simdVector + SIMD3<Float>(
            0,
            objectLabelVerticalOffset(type: type, size: size, placementSource: placementSource),
            0
        )
        guard let projected = arView.project(labelPosition),
              projected.x.isFinite,
              projected.y.isFinite
        else { return nil }

        let bounds = arView.bounds.insetBy(dx: -42, dy: -42)
        guard bounds.contains(projected) else { return nil }

        let cleanText = objectLabelText(text, fallback: displayName(for: type))
        return ARObjectLabelPresentation(
            id: id,
            text: cleanText,
            x: projected.x,
            y: projected.y - 24,
            tint: tint,
            priority: objectLabelPriority(for: type)
        )
    }

    private func objectLabelVerticalOffset(
        type: SceneObject.ObjectType,
        size: SIMD3<Float>,
        placementSource: PlannedScene.PlacedObject.PlacementSource
    ) -> Float {
        switch (type, placementSource) {
        case (.table, .marked), (.table, .detected):
            return 0.08
        case (.phone, _):
            return size.y / 2 + 0.12
        default:
            return size.y / 2 + 0.12
        }
    }

    private func objectLabelPriority(for type: SceneObject.ObjectType) -> Int {
        switch type {
        case .phone:
            return 0
        case .table:
            return 1
        default:
            return 2
        }
    }

    private func objectLabelText(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? fallback : trimmed
        return value.prefix(1).uppercased() + value.dropFirst()
    }

    private func displayName(for object: PlannedScene.PlacedObject) -> String {
        if let scriptObject = parsedScript?.objects.first(where: { $0.id == object.objectId }) {
            return displayName(for: scriptObject)
        }
        return displayName(for: object.type)
    }

    private func rgbVector(from color: UIColor) -> SIMD3<Float> {
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return SIMD3<Float>(Float(red), Float(green), Float(blue))
        }
        return SIMD3<Float>(1, 1, 1)
    }

    private func orientBillboard(_ entity: Entity, toward cameraPosition: SIMD3<Float>) {
        let position = entity.position(relativeTo: nil)
        let delta = cameraPosition - position
        let planarDistanceSquared = delta.x * delta.x + delta.z * delta.z
        guard planarDistanceSquared > 0.0001 else { return }

        let desiredYaw = atan2(delta.x, delta.z)
        let parentYaw = entity.parent.map { yaw(from: $0.orientation(relativeTo: nil)) } ?? 0
        entity.orientation = simd_quatf(angle: desiredYaw - parentYaw, axis: [0, 1, 0])
    }

    private func yaw(from quaternion: simd_quatf) -> Float {
        let q = quaternion.vector
        let siny = 2 * (q.w * q.y + q.z * q.x)
        let cosy = 1 - 2 * (q.y * q.y + q.x * q.x)
        return atan2(siny, cosy)
    }

    private func makePersonEntity() -> ModelEntity? {
        if let cachedPersonPrototype {
            return cachedPersonPrototype.clone(recursive: true)
        }
        guard let loaded = try? ModelEntity.loadModel(named: "Person") else {
            return nil
        }
        cachedPersonPrototype = loaded
        return loaded.clone(recursive: true)
    }
    
    private func applyTintRecursively(entity: Entity, color: UIColor) {
        if let modelEntity = entity as? ModelEntity, let model = modelEntity.model {
            let material = SimpleMaterial(color: color, roughness: 0.3, isMetallic: false)
            modelEntity.model?.materials = Array(repeating: material, count: max(model.materials.count, 1))
        }
        
        for child in entity.children {
            applyTintRecursively(entity: child, color: color)
        }
    }
    
    // MARK: - Animation

    private func updatePlaybackVisualFocus(
        entity: ModelEntity,
        for actor: PlannedScene.PlacedActor,
        beatID: String?,
        annotation: PlaybackPathAnnotation?,
        startPosition: SIMD3<Float>,
        targetPosition: SIMD3<Float>,
        duration: TimeInterval
    ) {
        let style = actorRenderStyle(for: actor)
        if let focus = actorFocusEntities[actor.id] {
            focus.stopAllAnimations()
            focus.isEnabled = true
            focus.position = startPosition + SIMD3<Float>(0, 0.025, 0)
            var transform = Transform()
            transform.translation = targetPosition + SIMD3<Float>(0, 0.025, 0)
            focus.move(to: transform, relativeTo: focus.parent, duration: duration, timingFunction: .linear)
        }

        guard annotation?.kind == .action,
              let action = matchingTargetAction(for: actor, beatID: beatID, annotationText: annotation?.text),
              let targetID = action.target,
              let cueTarget = cueTargetPosition(for: targetID)
        else {
            removeActiveTargetCue()
            return
        }

        orientActorEntity(
            entity,
            from: targetPosition,
            toward: cueTarget,
            actorLabel: displayName(for: actor),
            action: action,
            duration: duration
        )
        showTargetCue(
            from: targetPosition + SIMD3<Float>(0, actor.size.y * 0.45, 0),
            to: cueTarget,
            color: style.uiColor.withAlphaComponent(0.82),
            reticleRadius: targetCueRadius(for: targetID),
            duration: duration,
            actorLabel: displayName(for: actor),
            action: action
        )
    }

    private func orientActorEntity(
        _ entity: ModelEntity,
        from position: SIMD3<Float>,
        toward target: SIMD3<Float>,
        actorLabel: String,
        action: SceneAction,
        duration: TimeInterval
    ) {
        guard let angle = Self.yawAngle(from: position, toward: target) else { return }
        let rotationDuration = min(max(duration * 0.22, 0.22), 0.55)
        animateActorRotation(entity, yaw: angle, duration: rotationDuration)
        diagnosticsLog("[AR_VISUAL] actor oriented actor=\(actorLabel), action=\(action.type.rawValue), target=\(action.target ?? "nil"), yaw=\(formatFloat(angle)), duration=\(formatSeconds(rotationDuration))")
    }

    private func animateActorRotation(_ entity: ModelEntity, yaw angle: Float, duration: TimeInterval) {
        var transform = Transform()
        transform.translation = entity.position
        transform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
        transform.scale = entity.scale
        entity.move(to: transform, relativeTo: entity.parent, duration: duration, timingFunction: .easeInOut)
    }

    private func hideActorFocus() {
        for (_, entity) in actorFocusEntities {
            entity.stopAllAnimations()
            entity.isEnabled = false
        }
    }

    private func removeActiveTargetCue() {
        for entity in activeTargetCueEntities {
            entity.removeFromParent()
        }
        activeTargetCueEntities.removeAll()
        activeTargetCueID = nil
    }

    private func matchingTargetAction(
        for actor: PlannedScene.PlacedActor,
        beatID: String?,
        annotationText: String?
    ) -> SceneAction? {
        guard let beatID,
              let beat = parsedScript?.beats.first(where: { $0.id == beatID })
        else { return nil }

        let supportedTypes: Set<SceneAction.ActionType> = [.lookAt, .pickUp, .give, .putDown, .open, .close]
        let candidates = beat.actions.filter {
            $0.actorId == actor.actorId &&
            $0.target != nil &&
            supportedTypes.contains($0.type)
        }
        guard !candidates.isEmpty else { return nil }

        if let annotationText,
           let preferredType = preferredTargetCueActionType(for: annotationText),
           let matched = candidates.first(where: { $0.type == preferredType }) {
            return matched
        }

        if let annotationText,
           let matched = candidates.first(where: { action in
               [action.sourceText, action.fallbackText, action.dialogue]
                   .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                   .contains(annotationText.trimmingCharacters(in: .whitespacesAndNewlines))
           }) {
            return matched
        }

        return candidates.first
    }

    private func preferredTargetCueActionType(for annotationText: String) -> SceneAction.ActionType? {
        let text = annotationText.lowercased()
        if text.contains("переда") || text.contains("даёт") || text.contains("дает") {
            return .give
        }
        if text.contains("берёт") || text.contains("берет") || text.contains("поднима") || text.contains("взял") {
            return .pickUp
        }
        if text.contains("кладёт") || text.contains("кладет") || text.contains("полож") {
            return .putDown
        }
        return nil
    }

    private func cueTargetPosition(for targetID: String) -> SIMD3<Float>? {
        guard let plannedScene else { return nil }

        if let object = plannedScene.placedObjects.first(where: { $0.objectId == targetID || $0.id == targetID }) {
            return object.position.simdVector + SIMD3<Float>(0, max(object.size.y / 2, 0.05), 0)
        }

        if let actor = plannedScene.placedActors.first(where: { $0.actorId == targetID || $0.id == targetID }) {
            let basePosition = placedEntities[actor.id]?.position(relativeTo: nil) ?? actor.initialPosition.simdVector
            return basePosition + SIMD3<Float>(0, actor.size.y * 0.45, 0)
        }

        return nil
    }

    private func targetCueRadius(for targetID: String) -> Float {
        guard let plannedScene else { return 0.045 }
        if let object = plannedScene.placedObjects.first(where: { $0.objectId == targetID || $0.id == targetID }) {
            return Self.objectRenderStyle(for: object.type).targetCueRadius
        }
        return 0.055
    }

    private func showTargetCue(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        color: UIColor,
        reticleRadius: Float,
        duration: TimeInterval,
        actorLabel: String,
        action: SceneAction
    ) {
        guard let sceneAnchor else { return }
        removeActiveTargetCue()
        let cueID = UUID()
        activeTargetCueID = cueID

        let line = createLineEntity(from: start, to: end, thickness: 0.018, color: color)
        let reticle = ModelEntity(
            mesh: .generateSphere(radius: reticleRadius),
            materials: [SimpleMaterial(color: color, roughness: 0.2, isMetallic: false)]
        )
        reticle.position = end
        sceneAnchor.addChild(line)
        sceneAnchor.addChild(reticle)
        activeTargetCueEntities = [line, reticle]
        diagnosticsLog("[AR_VISUAL] target cue actor=\(actorLabel), action=\(action.type.rawValue), target=\(action.target ?? "nil"), radius=\(formatFloat(reticleRadius)), duration=\(formatSeconds(duration))")

        let hideDelay = min(max(duration, 0.7), 2.2)
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard self?.activeTargetCueID == cueID else { return }
            self?.removeActiveTargetCue()
        }
        animationWorkItems.append(hideWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: hideWorkItem)
    }

    private func animateActor(_ actor: PlannedScene.PlacedActor) {
        let playbackID = currentPlaybackLogID ?? "nil"
        guard let entity = placedEntities[actor.id] else {
            print("🎬 [PLAYBACK][\(playbackID)] actor animation skipped: entity missing actor=\(displayName(for: actor)), id=\(actor.id)")
            return
        }
        guard actor.path.count > 1 else {
            print("🎬 [PLAYBACK][\(playbackID)] actor animation skipped: path too short actor=\(displayName(for: actor)), points=\(actor.path.count)")
            return
        }
        print("🎬 [PLAYBACK][\(playbackID)] actor animation start actor=\(displayName(for: actor)), segments=\(actor.path.count - 1)")
        
        // Анимируем последовательно по всем точкам пути
        animateActorSegment(entity: entity, actor: actor, segmentIndex: 0)
    }
    
    /// Анимирует один сегмент пути актёра и рекурсивно переходит к следующему
    private func animateActorSegment(entity: ModelEntity, actor: PlannedScene.PlacedActor, segmentIndex: Int) {
        // Проверяем, что есть следующий сегмент
        guard segmentIndex < actor.path.count - 1 else {
            // Все сегменты завершены - устанавливаем финальную позицию точно
            if let lastPosition = actor.path.last {
                entity.position = lastPosition.simdVector
                print("🎬 [PLAYBACK][\(currentPlaybackLogID ?? "nil")] actor animation complete actor=\(displayName(for: actor)), final=\(formatPosition(lastPosition))")
            }
            checkIfAllAnimationsComplete()
            return
        }
        
        guard isPlaying else {
            print("🎬 [PLAYBACK][\(currentPlaybackLogID ?? "nil")] segment skipped: playback stopped actor=\(displayName(for: actor)), segment=\(segmentIndex)")
            return
        }
        
        let startPosition = actor.path[segmentIndex].simdVector
        let targetPosition = actor.path[segmentIndex + 1].simdVector
        let duration = max(actor.pathDurations[segmentIndex], 0.1) // Минимум 0.1 сек
        let playbackID = currentPlaybackLogID ?? "nil"
        let annotation = actor.pathAnnotations.indices.contains(segmentIndex + 1) ? actor.pathAnnotations[segmentIndex + 1] : nil
        let beatID = actor.pathBeatIDs.indices.contains(segmentIndex + 1) ? actor.pathBeatIDs[segmentIndex + 1] : nil
        diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] segment start actor=\(displayName(for: actor)), segment=\(segmentIndex), beat=\(beatID ?? "nil"), duration=\(formatSeconds(duration)), from=\(formatVector(startPosition)), to=\(formatVector(targetPosition)), annotationKind=\(annotation?.kind.rawValue ?? "nil"), annotation=\(quotedForLog(annotation?.text))")

        // Сначала устанавливаем точную начальную позицию сегмента
        entity.stopAllAnimations()
        entity.position = startPosition
        updatePlaybackVisualFocus(
            entity: entity,
            for: actor,
            beatID: beatID,
            annotation: annotation,
            startPosition: startPosition,
            targetPosition: targetPosition,
            duration: duration
        )
        
        // Вычисляем угол поворота в направлении движения
        let delta = targetPosition - startPosition
        let distance = simd_length(delta)
        
        // Если расстояние слишком маленькое, пропускаем этот сегмент
        guard distance > 0.01 else {
            diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] segment wait/no-move actor=\(displayName(for: actor)), segment=\(segmentIndex), distance=\(formatFloat(distance)), duration=\(formatSeconds(duration))")
            let waitWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isPlaying else { return }
                entity.position = targetPosition
                self.diagnosticsLog("🎬 [PLAYBACK][\(self.currentPlaybackLogID ?? "nil")] segment complete/no-move actor=\(self.displayName(for: actor)), segment=\(segmentIndex), position=\(self.formatVector(targetPosition))")
                self.animateActorSegment(entity: entity, actor: actor, segmentIndex: segmentIndex + 1)
            }
            animationWorkItems.append(waitWorkItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: waitWorkItem)
            return
        }
        
        let angle = Self.yawAngle(from: startPosition, toward: targetPosition) ?? yaw(from: entity.orientation(relativeTo: nil))
        
        // Создаём целевую трансформацию
        var targetTransform = Transform()
        targetTransform.translation = targetPosition
        targetTransform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
        targetTransform.scale = entity.scale
        
        // Запускаем анимацию
        entity.move(to: targetTransform, relativeTo: entity.parent, duration: duration, timingFunction: .linear)
        
        // Планируем следующий сегмент после завершения текущего
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPlaying else { return }
            // Устанавливаем точную конечную позицию перед следующим сегментом
            entity.position = targetPosition
            self.diagnosticsLog("🎬 [PLAYBACK][\(self.currentPlaybackLogID ?? "nil")] segment complete actor=\(self.displayName(for: actor)), segment=\(segmentIndex), position=\(self.formatVector(targetPosition))")
            self.animateActorSegment(entity: entity, actor: actor, segmentIndex: segmentIndex + 1)
        }
        animationWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
    
    /// Счётчик завершённых анимаций актёров
    private var completedActorAnimations = 0
    private var totalActorAnimations = 0
    
    /// Проверяет, завершились ли все анимации
    private func checkIfAllAnimationsComplete() {
        completedActorAnimations += 1
        diagnosticsLog("🎬 [PLAYBACK][\(currentPlaybackLogID ?? "nil")] actor animation counter \(completedActorAnimations)/\(totalActorAnimations)")
        
        // Все актёры завершили анимацию
        if completedActorAnimations >= totalActorAnimations && isPlaying {
            diagnosticsLog("🎬 [PLAYBACK][\(currentPlaybackLogID ?? "nil")] playback complete elapsed=\(formatSeconds(playbackElapsedTime))")
            isPlaying = false
            invalidatePlaybackTimelineTimer()
            resetPlaybackUIState(clearTimeline: true)
            currentPlaybackLogID = nil
            lastLoggedPlaybackBeatIndex = nil
            refreshWorkspaceMode()
            refreshIdleStatusMessage()
            SceneGeneratorDiagnosticsLogger.shared.flush()
        }
    }

    private struct PlaybackCaptionEvent {
        let startTime: TimeInterval
        let duration: TimeInterval
        let kind: PlaybackPathAnnotation.Kind
        let actorLabel: String
        let caption: String

        var renderedText: String {
            switch kind {
            case .dialogue:
                return "\(actorLabel): \(caption)"
            case .action:
                return caption
            }
        }
    }

    func buildBeatTimelineItems(for planned: PlannedScene, script: SceneScript?) -> [BeatPlaybackTimelineItem] {
        let beats = script?.beats ?? []
        guard !beats.isEmpty else {
            return buildFallbackBeatTimelineItems(for: planned)
        }

        var items: [BeatPlaybackTimelineItem] = []
        var startTime: TimeInterval = 0

        for (index, beat) in beats.enumerated() {
            var duration: TimeInterval = fallbackDuration(for: beat)
            var hasDialogueCaption = false
            var hasActionCaption = false
            var hasSegmentOutput = false
            var hasMotion = false

            for actor in planned.placedActors {
                var actorBeatDuration: TimeInterval = 0
                for segmentIndex in 0..<actor.pathDurations.count {
                    let annotationIndex = segmentIndex + 1
                    guard actor.pathBeatIDs.indices.contains(annotationIndex),
                          actor.pathBeatIDs[annotationIndex] == beat.id
                    else {
                        continue
                    }

                    hasSegmentOutput = true
                    actorBeatDuration += max(actor.pathDurations[segmentIndex], 0.1)
                    if actor.path.indices.contains(segmentIndex),
                       actor.path.indices.contains(segmentIndex + 1),
                       planarDistance(
                           from: actor.path[segmentIndex].simdVector,
                           to: actor.path[segmentIndex + 1].simdVector
                       ) > 0.03 {
                        hasMotion = true
                    }
                    if actor.pathAnnotations.indices.contains(annotationIndex),
                       let annotation = actor.pathAnnotations[annotationIndex] {
                        hasDialogueCaption = hasDialogueCaption || annotation.kind == .dialogue
                        hasActionCaption = hasActionCaption || annotation.kind == .action
                    }
                }
                duration = max(duration, actorBeatDuration)
            }

            let hasUsefulText = beat.actions.contains { action in
                [action.dialogue, action.sourceText, action.fallbackText]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .contains { !$0.isEmpty }
            }
            let shouldKeepBeat = hasSegmentOutput && (hasMotion || hasDialogueCaption || hasActionCaption || hasUsefulText)

            if shouldKeepBeat {
                items.append(
                    BeatPlaybackTimelineItem(
                        beatID: beat.id.isEmpty ? "beat_\(index + 1)" : beat.id,
                        index: items.count,
                        startTime: startTime,
                        duration: duration,
                        hasDialogueCaption: hasDialogueCaption,
                        hasActionCaption: hasActionCaption
                    )
                )
            }

            if hasSegmentOutput {
                startTime += duration
            }
        }

        diagnosticsLog("[AR_VISUAL] beat timeline filtered source=\(beats.count), visible=\(items.count)")
        return items
    }

    func playbackProgressState(at elapsedTime: TimeInterval, items: [BeatPlaybackTimelineItem]) -> BeatPlaybackProgressState {
        guard !items.isEmpty else {
            return BeatPlaybackProgressState(activeBeatIndex: 0, beatProgress: 0, elapsedTime: elapsedTime)
        }

        let lastIndex = items.count - 1
        guard let activeItem = items.last(where: { elapsedTime >= $0.startTime }) else {
            return BeatPlaybackProgressState(activeBeatIndex: 0, beatProgress: 0, elapsedTime: elapsedTime)
        }

        let rawProgress = activeItem.duration > 0 ? (elapsedTime - activeItem.startTime) / activeItem.duration : 1
        let progress = min(max(rawProgress, 0), 1)
        return BeatPlaybackProgressState(
            activeBeatIndex: min(activeItem.index, lastIndex),
            beatProgress: progress,
            elapsedTime: elapsedTime
        )
    }

    private func buildFallbackBeatTimelineItems(for planned: PlannedScene) -> [BeatPlaybackTimelineItem] {
        let orderedBeatIDs = planned.placedActors
            .flatMap(\.pathBeatIDs)
            .compactMap { $0 }
            .reduce(into: [String]()) { result, beatID in
                if !result.contains(beatID) {
                    result.append(beatID)
                }
            }

        guard !orderedBeatIDs.isEmpty else { return [] }

        let syntheticBeats = orderedBeatIDs.enumerated().map { index, beatID in
            SceneBeat(id: beatID.isEmpty ? "beat_\(index + 1)" : beatID, actions: [], minDuration: 0.4)
        }
        return buildBeatTimelineItems(for: planned, script: SceneScript(actors: [], objects: [], beats: syntheticBeats, spatialRelations: [], originalDescription: ""))
    }

    private func fallbackDuration(for beat: SceneBeat) -> TimeInterval {
        min(max(beat.minDuration ?? 0.4, 0.4), 4.0)
    }

    // MARK: - Storyboard Strip & Manual Editing

    func buildStoryboardBeatPresentationItems(for script: SceneScript?) -> [StoryboardBeatPresentationItem] {
        guard let script, !script.beats.isEmpty else { return [] }
        let visibleBeatIDs: Set<String>?
        if let plannedScene {
            visibleBeatIDs = Set(buildBeatTimelineItems(for: plannedScene, script: script).map(\.beatID))
        } else {
            visibleBeatIDs = nil
        }

        var items: [StoryboardBeatPresentationItem] = []
        for beat in script.beats {
            let hasDialogue = beat.actions.contains { $0.type == .talk && !storyboardActionText($0).isEmpty }
            let hasAction = beat.actions.contains { action in
                action.type != .talk && !storyboardActionText(action).isEmpty
            }
            let hasNonTextAction = beat.actions.contains { action in
                action.type != .talk && (action.type != .stand || action.target != nil)
            }
            let shouldShow = visibleBeatIDs?.contains(beat.id) ?? (hasDialogue || hasAction || hasNonTextAction)
            guard shouldShow else { continue }

            items.append(
                StoryboardBeatPresentationItem(
                    beatID: beat.id,
                    index: items.count,
                    kindTitle: storyboardKindTitle(hasDialogue: hasDialogue, hasAction: hasAction || hasNonTextAction),
                    summary: storyboardSummary(for: beat, in: script),
                    hasDialogueCaption: hasDialogue,
                    hasActionCaption: hasAction || hasNonTextAction,
                    actionCount: beat.actions.count
                )
            )
        }
        diagnosticsLog("[STORYBOARD] presentation built source=\(script.beats.count), visible=\(items.count)")
        return items
    }

    func refreshStoryboardBeatItems() {
        storyboardBeatItems = buildStoryboardBeatPresentationItems(for: parsedScript)
        if let selectedStoryboardBeatID,
           storyboardBeatItems.contains(where: { $0.beatID == selectedStoryboardBeatID }) {
            return
        }
        selectedStoryboardBeatID = storyboardBeatItems.first?.beatID
    }

    func buildStoryboardBeatInspector(for draft: StoryboardBeatEditDraft) -> StoryboardBeatInspectorPresentation {
        let nonDeletedActions = draft.actions.filter { !$0.isDeleted }
        let actorLabelByID = Dictionary(uniqueKeysWithValues: draft.actorOptions.map { ($0.id, $0.label) })
        let targetLabelByID = Dictionary(uniqueKeysWithValues: draft.targetOptions.map { ($0.id, $0.label) })
        let actorLabels = uniqueLabels(
            nonDeletedActions.compactMap { actorLabelByID[$0.actorId] }
        )
        let targetLabels = uniqueLabels(
            nonDeletedActions.compactMap { action in
                guard let target = normalizedStoryboardTarget(action.target) else { return nil }
                return targetLabelByID[target] ?? target
            }
        )
        let hasDialogue = nonDeletedActions.contains { $0.type == .talk && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasAction = nonDeletedActions.contains { $0.type != .talk }
        let summary = storyboardDraftSummary(for: nonDeletedActions, actorLabelByID: actorLabelByID)
        let warnings = storyboardInspectorWarnings(
            for: draft,
            actions: nonDeletedActions,
            actorLabelByID: actorLabelByID
        )
        let duration = storyboardBeatDurationText(for: draft.beatID)
        let dragHint = storyboardDragFeedback ?? localizedCopy(.storyboardDragHint)

        return StoryboardBeatInspectorPresentation(
            kindTitle: storyboardKindTitle(hasDialogue: hasDialogue, hasAction: hasAction),
            summary: summary,
            durationText: duration,
            actorLabels: actorLabels,
            targetLabels: targetLabels,
            warnings: warnings,
            dragHint: dragHint
        )
    }

    /// Records one user selection and owns the delayed editor handoff. The
    /// presentation layer may be recreated while the task is pending; only
    /// this owner can consume the stable event and open the sheet.
    func selectStoryboardBeat(beatID: String, reduceMotion: Bool) {
        guard storyboardBeatItems.contains(where: { $0.beatID == beatID }) else { return }

        storyboardSelectionTask?.cancel()
        storyboardSelectionSequence += 1
        let eventID = "storyboard.selection.\(storyboardSelectionSequence).\(beatID)"
        storyboardSelectionEventID = eventID
        storyboardEditorHandoffEventID = nil
        selectedStoryboardBeatID = beatID
        pendingStoryboardBeatID = beatID

        let delay = reduceMotion
            ? SETMotion.reducedMotionCrossfadeDuration
            : SETMotion.reflowGeometryDuration
        storyboardSelectionTask = Task { @MainActor [weak self] in
            guard delay > 0 else {
                self?.completeStoryboardSelection(beatID: beatID, eventID: eventID)
                return
            }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self else { return }
            self.completeStoryboardSelection(beatID: beatID, eventID: eventID)
        }
    }

    private func completeStoryboardSelection(beatID: String, eventID: String) {
        guard pendingStoryboardBeatID == beatID,
              storyboardSelectionEventID == eventID,
              storyboardMotionEventLedger.consume(eventID) else { return }
        pendingStoryboardBeatID = nil
        storyboardEditorHandoffEventID = eventID
        storyboardSelectionTask = nil
        openStoryboardEditor(for: beatID)
    }

    private func cancelPendingStoryboardSelection() {
        storyboardSelectionTask?.cancel()
        storyboardSelectionTask = nil
        pendingStoryboardBeatID = nil
    }

    func openStoryboardEditor(for beatID: String) {
        errorMessage = nil
        storyboardValidationMessage = nil
        storyboardValidationField = nil
        guard let draft = makeStoryboardEditDraft(for: beatID) else {
            errorMessage = localizedCopy(.storyboardErrorOpen)
            return
        }
        activeStoryboardEditDraft = draft
        storyboardDragFeedback = nil
        diagnosticsLog("[STORYBOARD_EDIT] open beat=\(beatID), actions=\(draft.actions.count)")
    }

    func cancelStoryboardEditor() {
        cancelPendingStoryboardSelection()
        cancelActiveStoryboardActorDrag()
        activeStoryboardEditDraft = nil
        storyboardDragFeedback = nil
        errorMessage = nil
        storyboardValidationMessage = nil
        storyboardValidationField = nil
    }

    func applyStoryboardBeatEdit(_ draft: StoryboardBeatEditDraft) async -> Bool {
        guard !isStoryboardMutationInFlight else { return false }
        isStoryboardMutationInFlight = true
        defer { isStoryboardMutationInFlight = false }
        errorMessage = nil
        storyboardValidationMessage = nil
        storyboardValidationField = nil
#if DEBUG
        let debugMutationDelay = max(
            storyboardDebugMutationDelay,
            debugFixtureID == "storyboard.saving" ? 3.0 : 0
        )
        if debugMutationDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(debugMutationDelay * 1_000_000_000))
        }
#endif
        guard let script = parsedScript,
              let beatIndex = script.beats.firstIndex(where: { $0.id == draft.beatID })
        else {
            errorMessage = localizedCopy(.storyboardErrorNotFound)
            return false
        }

        var updatedActions: [SceneAction] = []
        let originalActions = Dictionary(uniqueKeysWithValues: script.beats[beatIndex].actions.map { ($0.id, $0) })
        for actionDraft in draft.actions where !actionDraft.isDeleted {
            if !validateStoryboardActionDraft(actionDraft) {
                return false
            }
            updatedActions.append(makeSceneAction(from: actionDraft, original: originalActions[actionDraft.id]))
        }

        var beats = script.beats
        let originalBeat = beats[beatIndex]
        beats[beatIndex] = SceneBeat(
            id: originalBeat.id,
            actions: updatedActions,
            camera: originalBeat.camera,
            minDuration: originalBeat.minDuration
        )
        diagnosticsLog("[STORYBOARD_EDIT] save beat=\(draft.beatID), actions=\(updatedActions.count)")
        return await applyManualStoryboardScriptEdit(beats: beats, reason: "save_beat")
    }

    func deleteStoryboardBeat(beatID: String) async -> Bool {
        guard !isStoryboardMutationInFlight else { return false }
        isStoryboardMutationInFlight = true
        defer { isStoryboardMutationInFlight = false }
        errorMessage = nil
        storyboardValidationMessage = nil
        storyboardValidationField = nil
#if DEBUG
        let debugMutationDelay = max(
            storyboardDebugMutationDelay,
            debugFixtureID == "storyboard.saving" ? 1.2 : 0
        )
        if debugMutationDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(debugMutationDelay * 1_000_000_000))
        }
#endif
        guard let script = parsedScript,
              let index = script.beats.firstIndex(where: { $0.id == beatID })
        else {
            errorMessage = localizedCopy(.storyboardErrorNotFound)
            return false
        }
        guard script.beats.count > 1 else {
            errorMessage = localizedCopy(.storyboardErrorDeleteLast)
            return false
        }

        var beats = script.beats
        beats.remove(at: index)
        diagnosticsLog("[STORYBOARD_EDIT] delete beat=\(beatID)")
        return await applyManualStoryboardScriptEdit(beats: beats, reason: "delete_beat")
    }

    func moveStoryboardBeat(beatID: String, offset: Int) async -> Bool {
        guard !isStoryboardMutationInFlight else { return false }
        isStoryboardMutationInFlight = true
        defer { isStoryboardMutationInFlight = false }
        errorMessage = nil
        storyboardValidationMessage = nil
        storyboardValidationField = nil
#if DEBUG
        let debugMutationDelay = max(
            storyboardDebugMutationDelay,
            debugFixtureID == "storyboard.saving" ? 1.2 : 0
        )
        if debugMutationDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(debugMutationDelay * 1_000_000_000))
        }
#endif
        guard offset != 0,
              let script = parsedScript,
              let index = script.beats.firstIndex(where: { $0.id == beatID })
        else { return false }

        let destination = index + offset
        guard script.beats.indices.contains(destination) else { return false }

        var beats = script.beats
        beats.swapAt(index, destination)
        diagnosticsLog("[STORYBOARD_EDIT] move beat=\(beatID), from=\(index), to=\(destination)")
        return await applyManualStoryboardScriptEdit(beats: beats, reason: "move_beat")
    }

    private func makeStoryboardEditDraft(for beatID: String) -> StoryboardBeatEditDraft? {
        guard let script = parsedScript,
              let beat = script.beats.first(where: { $0.id == beatID })
        else { return nil }

        let actorOptions = script.actors.map {
            StoryboardEntityOption(id: $0.id, label: displayName(for: $0.id, in: script), kind: .actor)
        }
        let targetOptions = [StoryboardEntityOption(id: "none", label: localizedCopy(.storyboardNoTarget), kind: .none)] +
            script.actors.map { StoryboardEntityOption(id: $0.id, label: displayName(for: $0.id, in: script), kind: .actor) } +
            script.objects.map { StoryboardEntityOption(id: $0.id, label: displayName(for: $0), kind: .object) }
        let actions = beat.actions.map { action in
            StoryboardActionEditDraft(
                id: action.id,
                actorId: action.actorId,
                type: action.type,
                target: action.target,
                text: storyboardActionText(action),
                isDeleted: false,
                isNew: false
            )
        }

        return StoryboardBeatEditDraft(
            beatID: beat.id,
            title: localizedCopy(
                .storyboardBeatTitle,
                arguments: [script.beats.firstIndex(where: { $0.id == beat.id }).map { $0 + 1 } ?? 1]
            ),
            actions: actions,
            actorOptions: actorOptions,
            targetOptions: targetOptions
        )
    }

    private func storyboardDraftSummary(
        for actions: [StoryboardActionEditDraft],
        actorLabelByID: [String: String]
    ) -> String {
        if let dialogue = actions.first(where: { $0.type == .talk && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "\(actorLabelByID[dialogue.actorId] ?? dialogue.actorId): \(dialogue.text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        if let action = actions.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return action.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let action = actions.first {
            return "\(actorLabelByID[action.actorId] ?? action.actorId) · \(action.type.rawValue)"
        }
        return localizedCopy(.storyboardEmptyBeat)
    }

    private func storyboardInspectorWarnings(
        for draft: StoryboardBeatEditDraft,
        actions: [StoryboardActionEditDraft],
        actorLabelByID: [String: String]
    ) -> [String] {
        var warnings: [String] = []

        for action in actions {
            if Self.storyboardTargetActionTypes.contains(action.type),
               normalizedStoryboardTarget(action.target) == nil {
                warnings.append(
                    localizedCopy(
                        .storyboardWarningNoTarget,
                        arguments: [action.type.rawValue]
                    )
                )
            }
            if (action.type == .talk || action.type == .describedAction),
               action.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(
                    localizedCopy(
                        .storyboardWarningEmptyText,
                        arguments: [actorLabelByID[action.actorId] ?? action.actorId]
                    )
                )
            }
        }

        for actorID in Set(actions.map(\.actorId)).sorted()
        where !storyboardActorParticipatesInPlannedBeat(actorID: actorID, beatID: draft.beatID) {
            warnings.append(
                localizedCopy(
                    .storyboardWarningNoPoint,
                    arguments: [actorLabelByID[actorID] ?? actorID]
                )
            )
        }

        if let storyboardDragFeedback,
           !storyboardDragFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           storyboardDragFeedback.hasPrefix(localizedCopy(.storyboardDragFailureUnablePrefix))
                || storyboardDragFeedback.hasPrefix(localizedCopy(.storyboardDragFailureCannotPrefix)) {
            warnings.append(storyboardDragFeedback)
        }

        return uniqueLabels(warnings)
    }

    private func storyboardBeatDurationText(for beatID: String) -> String {
        if let item = beatTimelineItems.first(where: { $0.beatID == beatID }) {
            return formatSeconds(item.duration)
        }
        if let plannedScene,
           let item = buildBeatTimelineItems(for: plannedScene, script: parsedScript).first(where: { $0.beatID == beatID }) {
            return formatSeconds(item.duration)
        }
        if let beat = parsedScript?.beats.first(where: { $0.id == beatID }) {
            return formatSeconds(fallbackDuration(for: beat))
        }
        return "0.00s"
    }

    private func storyboardActorParticipatesInPlannedBeat(actorID: String, beatID: String) -> Bool {
        guard let actor = plannedScene?.placedActors.first(where: { $0.actorId == actorID || $0.id == actorID }) else {
            return false
        }
        return actor.pathBeatIDs.contains(beatID)
    }

    private func uniqueLabels(_ labels: [String]) -> [String] {
        var result: [String] = []
        for label in labels {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { continue }
            result.append(trimmed)
        }
        return result
    }

    private func applyManualStoryboardScriptEdit(beats: [SceneBeat], reason: String) async -> Bool {
        guard let script = parsedScript else { return false }
        guard let cameraTransform = currentCameraTransform ?? arView?.session.currentFrame?.camera.transform else {
            errorMessage = localizedCopy(.generatorErrorCameraPosition)
            return false
        }

        let scriptObjectIDs = script.objects.map(\.id)
        let acceptedBindingResult: SceneObjectBindingResult? = {
            guard let result = objectBindingResult,
                  let currentRequestID = generationRequestState.requestID,
                  let currentEpoch = generationRequestState.epoch,
                  result.requestID == currentRequestID,
                  result.epoch == currentEpoch,
                  result.request.description == sceneDescription,
                  scriptObjectIDs.count == Set(scriptObjectIDs).count,
                  result.resolutions.count == scriptObjectIDs.count,
                  Set(result.resolutions.map(\.reference)) == Set(scriptObjectIDs),
                  result.resolutions.allSatisfy(\.isBound) else {
                return nil
            }
            return result
        }()
        let existingPlannedScene = plannedScene
        let existingPlacedObjects = existingPlannedScene?.placedObjects ?? []
        let existingObjectIDs = existingPlacedObjects.map(\.objectId)
        let canReuseExistingObjects: Bool = {
            guard !script.objects.isEmpty else { return true }
            guard existingObjectIDs.count == scriptObjectIDs.count,
                  existingObjectIDs.count == Set(existingObjectIDs).count,
                  Set(existingObjectIDs) == Set(scriptObjectIDs) else {
                return false
            }
            let existingTypes = Dictionary(uniqueKeysWithValues: existingPlacedObjects.map { ($0.objectId, $0.type) })
            return script.objects.allSatisfy { existingTypes[$0.id] == $0.type }
        }()
        let staleBindingResult = objectBindingResult != nil && acceptedBindingResult == nil
        guard !staleBindingResult && (acceptedBindingResult != nil || canReuseExistingObjects) else {
            let message = localizedCopy(.generatorClarification)
            storyboardValidationMessage = message
            errorMessage = message
            diagnosticsLog("[STORYBOARD_EDIT] accepted binding/planned object identity unavailable; edit not committed")
            return false
        }

        let editedObjects = acceptedBindingResult.map {
            matchObjectsWithMarkedAndDetected(script.objects, bindingResult: $0)
        } ?? script.objects
        let editedScript = SceneScript(
            sceneHeading: script.sceneHeading,
            locationName: script.locationName,
            interiorExterior: script.interiorExterior,
            timeOfDay: script.timeOfDay,
            actors: script.actors,
            objects: editedObjects,
            beats: beats,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )
        let planned = plannerService.planScene(
            script: editedScript,
            cameraTransform: cameraTransform,
            // The object resolver above is the only source of physical
            // positions; raw arrays would re-enable first-same-type fallback.
            detectedObjects: [],
            availablePlanes: detectedPlanes,
            markedObjects: []
        )
        let plannedWithBindingSources: PlannedScene
        if let acceptedBindingResult {
            plannedWithBindingSources = applyBindingSources(
                to: planned,
                bindingResult: acceptedBindingResult
            )
        } else if let existingPlannedScene {
            // Beat edits do not own object identity. Preserve the accepted
            // planned objects when the immutable request binding is absent.
            plannedWithBindingSources = PlannedScene(
                placedActors: planned.placedActors,
                placedObjects: existingPlannedScene.placedObjects
            )
        } else {
            plannedWithBindingSources = planned
        }

        // Validation and pure replanning complete before playback/model state
        // is touched. A rejected binding therefore leaves the current scene
        // and animations unchanged.
        if isPlaying {
            stopScene()
        } else {
            cancelAllAnimations()
            resetPlaybackUIState(clearTimeline: true)
        }

        parsedScript = editedScript
        if let parsingResult {
            self.parsingResult = ParsingResult(script: editedScript, diagnostics: parsingResult.diagnostics)
        }
        plannedScene = plannedWithBindingSources
        placeObjectsInAR(plannedWithBindingSources)
        beatTimelineItems = buildBeatTimelineItems(for: plannedWithBindingSources, script: editedScript)
        refreshStoryboardBeatItems()
        activeStoryboardEditDraft = nil
        storyboardValidationMessage = nil
        storyboardValidationField = nil
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
        persistProjectMetadata()
        diagnosticsLog("[STORYBOARD_EDIT] replan complete reason=\(reason), beats=\(editedScript.beats.count), visible=\(storyboardBeatItems.count), actors=\(plannedWithBindingSources.placedActors.count), objects=\(plannedWithBindingSources.placedObjects.count)")
        SceneGeneratorDiagnosticsLogger.shared.flush()
        return true
    }

    func handleStoryboardActorDragGesture(state: UIGestureRecognizer.State, at screenPoint: CGPoint) {
        if shouldLogStoryboardActorDragGestureState(state) {
            diagnosticsLog(
                "[STORYBOARD_EDIT] actor drag gesture received state=\(storyboardActorDragGestureStateDescription(state)), point=(\(formatFloat(Float(screenPoint.x))), \(formatFloat(Float(screenPoint.y)))), activeBeat=\(activeStoryboardEditDraft?.beatID ?? "nil"), hasARView=\(arView != nil), playing=\(isPlaying), generating=\(isGenerating), recording=\(isRecording)"
            )
        }
        switch state {
        case .began:
            beginStoryboardActorDrag(at: screenPoint)
        case .changed:
            updateStoryboardActorDrag(at: screenPoint)
        case .ended:
            finishStoryboardActorDrag(commit: true)
        case .cancelled, .failed:
            finishStoryboardActorDrag(commit: false)
        default:
            break
        }
    }

    private func shouldLogStoryboardActorDragGestureState(_ state: UIGestureRecognizer.State) -> Bool {
        switch state {
        case .began, .ended, .cancelled, .failed:
            return true
        default:
            return false
        }
    }

    private func storyboardActorDragGestureStateDescription(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible:
            return "possible"
        case .began:
            return "began"
        case .changed:
            return "changed"
        case .ended:
            return "ended"
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }

    @discardableResult
    func commitStoryboardActorDrag(actorID: String, beatID: String, to position: Position3D) -> Bool {
        guard activeStoryboardEditDraft?.beatID == beatID else {
            storyboardDragFeedback = localizedCopy(.storyboardDragBeatClosed)
            diagnosticsLog("[STORYBOARD_EDIT] actor drag rejected: beat not active actor=\(actorID), beat=\(beatID)")
            return false
        }
        guard !isPlaying, !isGenerating, !isRecording else {
            storyboardDragFeedback = localizedCopy(.storyboardDragBusy)
            diagnosticsLog("[STORYBOARD_EDIT] actor drag rejected: busy actor=\(actorID), beat=\(beatID)")
            return false
        }
        guard let plannedScene,
              let actorIndex = plannedScene.placedActors.firstIndex(where: { $0.actorId == actorID || $0.id == actorID })
        else {
            storyboardDragFeedback = localizedCopy(.storyboardDragActorMissing)
            diagnosticsLog("[STORYBOARD_EDIT] actor drag rejected: actor missing actor=\(actorID), beat=\(beatID)")
            return false
        }

        let actor = plannedScene.placedActors[actorIndex]
        var changedPoints = 0
        let updatedPath = actor.path.enumerated().map { index, point -> Position3D in
            guard actor.pathBeatIDs.indices.contains(index),
                  actor.pathBeatIDs[index] == beatID
            else { return point }
            changedPoints += 1
            return Position3D(x: position.x, y: point.y, z: position.z)
        }

        guard changedPoints > 0 else {
            storyboardDragFeedback = localizedCopy(
                .storyboardDragActorNotInBeat,
                arguments: [displayName(for: actor)]
            )
            diagnosticsLog("[STORYBOARD_EDIT] actor drag rejected: no beat point actor=\(displayName(for: actor)), beat=\(beatID)")
            return false
        }

        var actors = plannedScene.placedActors
        actors[actorIndex] = PlannedScene.PlacedActor(
            id: actor.id,
            actorId: actor.actorId,
            type: actor.type,
            name: actor.name,
            initialPosition: actor.initialPosition,
            initialRotation: actor.initialRotation,
            path: updatedPath,
            pathDurations: actor.pathDurations,
            pathPoses: actor.pathPoses,
            pathCameras: actor.pathCameras,
            pathAnnotations: actor.pathAnnotations,
            pathBeatIDs: actor.pathBeatIDs
        )

        let updatedScene = PlannedScene(
            placedActors: actors,
            placedObjects: plannedScene.placedObjects
        )
        self.plannedScene = updatedScene
        beatTimelineItems = buildBeatTimelineItems(for: updatedScene, script: parsedScript)
        refreshStoryboardBeatItems()
        refreshPathGuides(for: updatedScene)
        persistProjectMetadata()
        storyboardDragFeedback = localizedCopy(
            .storyboardDragCommittedInBeat,
            arguments: [
                displayName(for: actor),
                activeStoryboardEditDraft?.title.lowercased() ?? localizedCopy(.storyboardBeatTitle, arguments: [""])
            ]
        )
        diagnosticsLog("[STORYBOARD_EDIT] actor drag committed actor=\(displayName(for: actor)), beat=\(beatID), points=\(changedPoints), position=\(formatPosition(position))")
        SceneGeneratorDiagnosticsLogger.shared.flush()
        return true
    }

    @discardableResult
    func commitStoryboardActorTrackDrag(actorID: String, from originalPosition: SIMD3<Float>, to position: Position3D) -> Bool {
        guard !isPlaying, !isGenerating, !isRecording else {
            storyboardDragFeedback = localizedCopy(.storyboardDragBusy)
            diagnosticsLog("[STORYBOARD_EDIT] actor track drag rejected: busy actor=\(actorID)")
            return false
        }
        guard let plannedScene,
              let actorIndex = plannedScene.placedActors.firstIndex(where: { $0.actorId == actorID || $0.id == actorID })
        else {
            storyboardDragFeedback = localizedCopy(.storyboardDragActorMissing)
            diagnosticsLog("[STORYBOARD_EDIT] actor track drag rejected: actor missing actor=\(actorID)")
            return false
        }

        let actor = plannedScene.placedActors[actorIndex]
        let deltaX = position.x - originalPosition.x
        let deltaZ = position.z - originalPosition.z
        let updatedInitial = Position3D(
            x: actor.initialPosition.x + deltaX,
            y: actor.initialPosition.y,
            z: actor.initialPosition.z + deltaZ
        )
        let updatedPath = actor.path.map { point in
            Position3D(x: point.x + deltaX, y: point.y, z: point.z + deltaZ)
        }

        var actors = plannedScene.placedActors
        actors[actorIndex] = PlannedScene.PlacedActor(
            id: actor.id,
            actorId: actor.actorId,
            type: actor.type,
            name: actor.name,
            initialPosition: updatedInitial,
            initialRotation: actor.initialRotation,
            path: updatedPath,
            pathDurations: actor.pathDurations,
            pathPoses: actor.pathPoses,
            pathCameras: actor.pathCameras,
            pathAnnotations: actor.pathAnnotations,
            pathBeatIDs: actor.pathBeatIDs
        )

        let updatedScene = PlannedScene(
            placedActors: actors,
            placedObjects: plannedScene.placedObjects
        )
        self.plannedScene = updatedScene
        beatTimelineItems = buildBeatTimelineItems(for: updatedScene, script: parsedScript)
        refreshStoryboardBeatItems()
        refreshPathGuides(for: updatedScene)
        persistProjectMetadata()
        storyboardDragFeedback = localizedCopy(
            .storyboardDragCommitted,
            arguments: [displayName(for: actor)]
        )
        diagnosticsLog("[STORYBOARD_EDIT] actor track drag committed actor=\(displayName(for: actor)), delta=(\(formatFloat(deltaX)), \(formatFloat(deltaZ))), position=\(formatPosition(position))")
        SceneGeneratorDiagnosticsLogger.shared.flush()
        return true
    }

    private func beginStoryboardActorDrag(at screenPoint: CGPoint) {
        diagnosticsLog("[STORYBOARD_EDIT] actor drag begin requested point=(\(formatFloat(Float(screenPoint.x))), \(formatFloat(Float(screenPoint.y))))")
        guard !isPlaying, !isGenerating, !isRecording else {
            storyboardDragFeedback = localizedCopy(.storyboardDragBusy)
            diagnosticsLog("[STORYBOARD_EDIT] actor drag begin rejected: busy")
            return
        }
        guard arView != nil else {
            storyboardDragFeedback = localizedCopy(.storyboardDragARNotReady)
            diagnosticsLog("[STORYBOARD_EDIT] actor drag begin rejected: no arView")
            return
        }
        let beatID = activeStoryboardEditDraft?.beatID
        guard let actor = storyboardActorHit(at: screenPoint, beatID: beatID)
        else {
            storyboardDragFeedback = localizedCopy(.storyboardDragHoldActor)
            diagnosticsLog("[STORYBOARD_EDIT] actor drag begin rejected: actor hit missing beat=\(beatID ?? "global"), point=(\(formatFloat(Float(screenPoint.x))), \(formatFloat(Float(screenPoint.y))))")
            return
        }
        if let beatID {
            guard actor.pathBeatIDs.contains(beatID) else {
                storyboardDragFeedback = localizedCopy(
                    .storyboardDragActorNotInBeat,
                    arguments: [displayName(for: actor)]
                )
                diagnosticsLog("[STORYBOARD_EDIT] actor drag begin rejected: no beat point actor=\(displayName(for: actor)), beat=\(beatID)")
                return
            }
        }
        guard let entity = placedEntities[actor.id],
              let position = storyboardActorDragPosition(at: screenPoint, for: actor, beatID: beatID)
        else {
            storyboardDragFeedback = localizedCopy(.storyboardDragSurfaceMissing)
            return
        }

        activeStoryboardActorDrag = StoryboardActorDragState(
            actorPlacedID: actor.id,
            actorID: actor.actorId,
            beatID: beatID,
            originalPosition: entity.position(relativeTo: entity.parent),
            latestPosition: position
        )
        actorFocusEntities[actor.id]?.isEnabled = true
        updateStoryboardActorDragPreview(actor: actor, position: position)
        storyboardDragFeedback = beatID == nil
            ? localizedCopy(.storyboardDragMoving, arguments: [displayName(for: actor)])
            : localizedCopy(
                .storyboardDragMovingToBeat,
                arguments: [
                    displayName(for: actor),
                    activeStoryboardEditDraft?.title.lowercased() ?? localizedCopy(.storyboardBeatTitle, arguments: [""])
                ]
            )
        diagnosticsLog("[STORYBOARD_EDIT] actor drag began actor=\(displayName(for: actor)), beat=\(beatID ?? "global"), position=\(formatPosition(position))")
    }

    private func updateStoryboardActorDrag(at screenPoint: CGPoint) {
        guard var drag = activeStoryboardActorDrag,
              let actor = plannedScene?.placedActors.first(where: { $0.id == drag.actorPlacedID }),
              let position = storyboardActorDragPosition(at: screenPoint, for: actor, beatID: drag.beatID)
        else { return }

        drag.latestPosition = position
        activeStoryboardActorDrag = drag
        updateStoryboardActorDragPreview(actor: actor, position: position)
    }

    private func finishStoryboardActorDrag(commit: Bool) {
        guard let drag = activeStoryboardActorDrag else { return }
        activeStoryboardActorDrag = nil
        actorFocusEntities[drag.actorPlacedID]?.isEnabled = false

        if commit {
            if let beatID = drag.beatID {
                _ = commitStoryboardActorDrag(actorID: drag.actorID, beatID: beatID, to: drag.latestPosition)
            } else {
                _ = commitStoryboardActorTrackDrag(actorID: drag.actorID, from: drag.originalPosition, to: drag.latestPosition)
            }
        } else {
            if let entity = placedEntities[drag.actorPlacedID] {
                entity.position = drag.originalPosition
            }
            storyboardDragFeedback = localizedCopy(.storyboardDragCancelled)
            diagnosticsLog("[STORYBOARD_EDIT] actor drag cancelled actor=\(drag.actorID), beat=\(drag.beatID ?? "global")")
        }
    }

    private func cancelActiveStoryboardActorDrag() {
        finishStoryboardActorDrag(commit: false)
    }

    private func storyboardActorHit(at screenPoint: CGPoint, beatID: String?) -> PlannedScene.PlacedActor? {
        guard let arView else { return nil }
        let beatLabel = beatID ?? "global"

        let sampleOffsets: [CGPoint] = [
            .zero,
            CGPoint(x: 22, y: 0),
            CGPoint(x: -22, y: 0),
            CGPoint(x: 0, y: 22),
            CGPoint(x: 0, y: -22),
            CGPoint(x: 38, y: 22),
            CGPoint(x: -38, y: 22),
            CGPoint(x: 38, y: -22),
            CGPoint(x: -38, y: -22),
        ]

        for offset in sampleOffsets {
            let point = CGPoint(x: screenPoint.x + offset.x, y: screenPoint.y + offset.y)
            guard arView.bounds.contains(point),
                  let hitEntity = arView.entity(at: point),
                  let actor = placedActor(forHitEntity: hitEntity)
            else { continue }
            diagnosticsLog("[STORYBOARD_EDIT] actor drag hit entity actor=\(displayName(for: actor)), beat=\(beatLabel), offset=(\(formatFloat(Float(offset.x))), \(formatFloat(Float(offset.y))))")
            return actor
        }

        guard let projected = projectedStoryboardActorHit(at: screenPoint) else { return nil }
        diagnosticsLog("[STORYBOARD_EDIT] actor drag hit projection actor=\(displayName(for: projected.actor)), beat=\(beatLabel), distance=\(formatFloat(Float(projected.distance)))")
        return projected.actor
    }

    private func projectedStoryboardActorHit(at screenPoint: CGPoint) -> (actor: PlannedScene.PlacedActor, distance: CGFloat)? {
        guard let arView,
              let plannedScene
        else { return nil }

        var bestMatch: (actor: PlannedScene.PlacedActor, distance: CGFloat)?
        for actor in plannedScene.placedActors {
            let basePosition = placedEntities[actor.id]?.position(relativeTo: nil) ?? actor.initialPosition.simdVector
            let sampleWorldPoints = [
                basePosition + SIMD3<Float>(0, max(actor.size.y * 0.18, 0.12), 0),
                basePosition + SIMD3<Float>(0, max(actor.size.y * 0.48, 0.28), 0),
                basePosition + SIMD3<Float>(0, max(actor.size.y * 0.78, 0.44), 0),
            ]

            let actorDistance = sampleWorldPoints.compactMap { point -> CGFloat? in
                guard let projected = arView.project(point),
                      projected.x.isFinite,
                      projected.y.isFinite
                else { return nil }
                let dx = projected.x - screenPoint.x
                let dy = projected.y - screenPoint.y
                return sqrt(dx * dx + dy * dy)
            }.min()

            guard let actorDistance,
                  actorDistance <= storyboardActorScreenPickRadius
            else { continue }

            if bestMatch == nil || actorDistance < bestMatch!.distance {
                bestMatch = (actor, actorDistance)
            }
        }

        return bestMatch
    }

    private func placedActor(forHitEntity entity: Entity) -> PlannedScene.PlacedActor? {
        guard let plannedScene else { return nil }
        for actor in plannedScene.placedActors {
            guard let actorEntity = placedEntities[actor.id],
                  entity === actorEntity || isEntity(entity, descendantOf: actorEntity)
            else { continue }
            return actor
        }
        return nil
    }

    private func isEntity(_ entity: Entity, descendantOf root: Entity) -> Bool {
        var current: Entity? = entity
        while let node = current {
            if node === root { return true }
            current = node.parent
        }
        return false
    }

    private func storyboardActorDragPosition(
        at screenPoint: CGPoint,
        for actor: PlannedScene.PlacedActor,
        beatID: String?
    ) -> Position3D? {
        guard let arView else { return nil }
        var results = arView.raycast(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .horizontal)
        if results.isEmpty {
            results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .horizontal)
        }
        if results.isEmpty {
            results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        }
        let y = if let beatID {
            actor.path.enumerated().first { index, _ in
                actor.pathBeatIDs.indices.contains(index) && actor.pathBeatIDs[index] == beatID
            }?.element.y ?? actor.initialPosition.y
        } else {
            actor.initialPosition.y
        }
        if let result = results.first {
            let hit = result.worldTransform.columns.3
            return Position3D(x: hit.x, y: y, z: hit.z)
        }
        guard let fallback = fallbackSurfacePosition(from: screenPoint, yOverride: y) else { return nil }
        diagnosticsLog("[STORYBOARD_EDIT] actor drag raycast fallback used beat=\(beatID ?? "global"), position=\(formatPosition(fallback))")
        return fallback
    }

    private func fallbackSurfacePosition(from screenPoint: CGPoint, yOverride: Float? = nil) -> Position3D? {
        guard let arView else { return nil }
        let planeY = yOverride
            ?? detectedPlanes.filter { $0.alignment == .horizontal }.map(\.y).min()
            ?? currentCameraTransform.map { $0.columns.3.y - 1.25 }
            ?? 0

        if let ray = arView.ray(through: screenPoint) {
            let origin = ray.origin
            let direction = simd_normalize(ray.direction)
            if abs(direction.y) > 0.0001 {
                let t = (planeY - origin.y) / direction.y
                if t.isFinite, t > 0 {
                    let hit = origin + direction * t
                    return Position3D(x: hit.x, y: planeY, z: hit.z)
                }
            }
        }

        guard let transform = currentCameraTransform else { return nil }
        let origin = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let projected = origin + simd_normalize(forward) * 1.2
        return Position3D(x: projected.x, y: planeY, z: projected.z)
    }

    private func updateStoryboardActorDragPreview(actor: PlannedScene.PlacedActor, position: Position3D) {
        let vector = position.simdVector
        placedEntities[actor.id]?.position = vector
        actorFocusEntities[actor.id]?.position = vector + SIMD3<Float>(0, 0.025, 0)
    }

    private func refreshPathGuides(for planned: PlannedScene) {
        for entity in pathGuideEntities {
            entity.removeFromParent()
        }
        pathGuideEntities.removeAll()
        guard let sceneAnchor else { return }
        placePathGuides(for: planned, anchor: sceneAnchor)
    }

    private func validateStoryboardActionDraft(_ draft: StoryboardActionEditDraft) -> Bool {
        guard draft.actorId != "none", !draft.actorId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = localizedCopy(.storyboardValidationActor)
            storyboardValidationMessage = message
            storyboardValidationField = .actor(actionID: draft.id)
            errorMessage = message
            return false
        }
        if draft.type == .give {
            guard let target = draft.target, target != "none", !target.isEmpty else {
                let message = localizedCopy(.storyboardValidationTarget)
                storyboardValidationMessage = message
                storyboardValidationField = .target(actionID: draft.id)
                errorMessage = message
                return false
            }
            guard target != draft.actorId else {
                let message = localizedCopy(.storyboardValidationSelfTarget)
                storyboardValidationMessage = message
                storyboardValidationField = .target(actionID: draft.id)
                errorMessage = message
                return false
            }
        }
        return true
    }

    private func makeSceneAction(from draft: StoryboardActionEditDraft, original: SceneAction?) -> SceneAction {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = normalizedStoryboardTarget(draft.target)
        return SceneAction(
            id: original?.id ?? draft.id,
            actorId: draft.actorId,
            type: draft.type,
            target: target,
            direction: draft.type == .walk && target != nil ? .toTarget : original?.direction,
            modifier: original?.modifier,
            resultingPose: original?.resultingPose,
            holdingObject: draft.type == .pickUp ? target : original?.holdingObject,
            dialogue: draft.type == .talk && !text.isEmpty ? text : nil,
            fallbackText: draft.type == .describedAction && !text.isEmpty ? text : nil,
            sourceText: draft.type != .talk && !text.isEmpty ? text : nil
        )
    }

    private func normalizedStoryboardTarget(_ target: String?) -> String? {
        guard let target = target?.trimmingCharacters(in: .whitespacesAndNewlines),
              !target.isEmpty,
              target != "none"
        else { return nil }
        return target
    }

    private func storyboardKindTitle(hasDialogue: Bool, hasAction: Bool) -> String {
        if hasDialogue && hasAction { return "сцена" }
        if hasDialogue { return "диалог" }
        if hasAction { return "действие" }
        return "движение"
    }

    private func storyboardSummary(for beat: SceneBeat, in script: SceneScript) -> String {
        if let dialogue = beat.actions.first(where: { $0.type == .talk && !storyboardActionText($0).isEmpty }) {
            return "\(displayName(for: dialogue.actorId, in: script)): \(storyboardActionText(dialogue))"
        }
        if let action = beat.actions.first(where: { !storyboardActionText($0).isEmpty }) {
            return storyboardActionText(action)
        }
        if let action = beat.actions.first {
            return "\(displayName(for: action.actorId, in: script)) · \(action.type.rawValue)"
        }
        return localizedCopy(.storyboardEmptyBeat)
    }

    private func storyboardActionText(_ action: SceneAction) -> String {
        [action.dialogue, action.sourceText, action.fallbackText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func displayName(for actorId: String, in script: SceneScript) -> String {
        if let actor = script.actors.first(where: { $0.id == actorId }),
           let name = actor.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let suffix = actorId.split(separator: "_").last, Int(suffix) != nil {
            return localizedCopy(.storyboardActorNumber, arguments: [String(suffix)])
        }
        return actorId
    }

    private func displayName(for object: SceneObject) -> String {
        if let name = object.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           name.lowercased() != object.type.rawValue.lowercased() {
            return name
        }
        return displayName(for: object.type)
    }

    private func displayName(for objectType: SceneObject.ObjectType) -> String {
        switch objectType {
        case .table:
            return localizedCopy(.storyboardObjectTable)
        case .phone:
            return localizedCopy(.storyboardObjectPhone)
        default:
            return objectType.rawValue
        }
    }

    private func startPlaybackTimelineTimer() {
        invalidatePlaybackTimelineTimer()
        playbackStartDate = Date()
        updatePlaybackTimeline(elapsedTime: 0)

        playbackTimelineTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPlaying, let playbackStartDate = self.playbackStartDate else { return }
                self.updatePlaybackTimeline(elapsedTime: Date().timeIntervalSince(playbackStartDate))
            }
        }
    }

    private func updatePlaybackTimeline(elapsedTime: TimeInterval) {
        let state = playbackProgressState(at: elapsedTime, items: beatTimelineItems)
        if lastLoggedPlaybackBeatIndex != state.activeBeatIndex,
           beatTimelineItems.indices.contains(state.activeBeatIndex) {
            let item = beatTimelineItems[state.activeBeatIndex]
            diagnosticsLog("🎬 [PLAYBACK][\(currentPlaybackLogID ?? "nil")] active beat changed index=\(state.activeBeatIndex), beatID=\(item.beatID), elapsed=\(formatSeconds(state.elapsedTime)), duration=\(formatSeconds(item.duration)), dialogue=\(item.hasDialogueCaption), action=\(item.hasActionCaption)")
            lastLoggedPlaybackBeatIndex = state.activeBeatIndex
        }
        playbackElapsedTime = state.elapsedTime
        activeBeatIndex = state.activeBeatIndex
        beatProgress = state.beatProgress
    }

    private func schedulePlaybackCaptions(for planned: PlannedScene) {
        let events = buildPlaybackCaptionEvents(for: planned)
        var nextAvailableTimeByKind: [PlaybackPathAnnotation.Kind: TimeInterval] = [
            .dialogue: 0,
            .action: 0
        ]

        for event in events {
            let captionID = UUID()
            let startTime = max(event.startTime, nextAvailableTimeByKind[event.kind] ?? 0)
            let displayDuration = min(max(event.duration, 1.15), 2.8)
            nextAvailableTimeByKind[event.kind] = startTime + displayDuration + 0.15

            let showWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isPlaying else { return }
                switch event.kind {
                case .dialogue:
                    self.activeDialogueCaptionID = captionID
                    self.activeDialogueCaption = event.renderedText
                    self.diagnosticsLog("🎬 [PLAYBACK][\(self.currentPlaybackLogID ?? "nil")] show dialogue caption start=\(self.formatSeconds(startTime)), duration=\(self.formatSeconds(displayDuration)), text=\(self.quotedForLog(event.renderedText))")
                case .action:
                    self.activeActionCaptionID = captionID
                    self.activeActionCaption = event.renderedText
                    self.diagnosticsLog("🎬 [PLAYBACK][\(self.currentPlaybackLogID ?? "nil")] show action caption start=\(self.formatSeconds(startTime)), duration=\(self.formatSeconds(displayDuration)), text=\(self.quotedForLog(event.renderedText))")
                }
            }
            animationWorkItems.append(showWorkItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + startTime, execute: showWorkItem)

            let hideWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isPlaying else { return }
                switch event.kind {
                case .dialogue:
                    guard self.activeDialogueCaptionID == captionID else { return }
                    self.diagnosticsLog("🎬 [PLAYBACK][\(self.currentPlaybackLogID ?? "nil")] hide dialogue caption text=\(self.quotedForLog(event.renderedText))")
                    self.activeDialogueCaption = nil
                    self.activeDialogueCaptionID = nil
                case .action:
                    guard self.activeActionCaptionID == captionID else { return }
                    self.diagnosticsLog("🎬 [PLAYBACK][\(self.currentPlaybackLogID ?? "nil")] hide action caption text=\(self.quotedForLog(event.renderedText))")
                    self.activeActionCaption = nil
                    self.activeActionCaptionID = nil
                }
            }
            animationWorkItems.append(hideWorkItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + startTime + displayDuration, execute: hideWorkItem)
        }
    }

    private func scheduleScreenTextOverlays() {
        let screenTextOverlays = visualOverlays
            .filter { $0.kind == .screenText }
            .sorted { $0.displayOrder < $1.displayOrder }

        for (index, overlay) in screenTextOverlays.enumerated() {
            let captionID = UUID()
            let startTime = TimeInterval(index) * 2.2
            let displayDuration: TimeInterval = 2.0

            let showWorkItem = DispatchWorkItem { [weak self] in
                guard let self, self.isPlaying else { return }
                self.activeScreenTextCaptionID = captionID
                self.activeScreenTextCaption = overlay.text
                self.diagnosticsLog("🎬 [PLAYBACK][\(self.currentPlaybackLogID ?? "nil")] show screen text start=\(self.formatSeconds(startTime)), duration=\(self.formatSeconds(displayDuration)), text=\(self.quotedForLog(overlay.text))")
            }
            animationWorkItems.append(showWorkItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + startTime, execute: showWorkItem)

            let hideWorkItem = DispatchWorkItem { [weak self] in
                guard let self, self.isPlaying, self.activeScreenTextCaptionID == captionID else { return }
                self.diagnosticsLog("🎬 [PLAYBACK][\(self.currentPlaybackLogID ?? "nil")] hide screen text text=\(self.quotedForLog(overlay.text))")
                self.activeScreenTextCaption = nil
                self.activeScreenTextCaptionID = nil
            }
            animationWorkItems.append(hideWorkItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + startTime + displayDuration, execute: hideWorkItem)
        }
    }

    private func buildPlaybackCaptionEvents(for planned: PlannedScene) -> [PlaybackCaptionEvent] {
        var events: [PlaybackCaptionEvent] = []
        var seenKeys = Set<String>()

        for actor in planned.placedActors {
            var elapsed: TimeInterval = 0
            for segmentIndex in 0..<actor.pathDurations.count {
                let duration = max(actor.pathDurations[segmentIndex], 0.1)
                let annotationIndex = segmentIndex + 1
                defer { elapsed += duration }

                guard actor.pathAnnotations.indices.contains(annotationIndex),
                      let rawAnnotation = actor.pathAnnotations[annotationIndex],
                      !rawAnnotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    continue
                }

                let caption = sanitizeCaption(rawAnnotation.text)
                guard !caption.isEmpty else { continue }

                let roundedStart = Int((elapsed * 10).rounded())
                let key = "\(rawAnnotation.kind.rawValue)|\(roundedStart)|\(caption)"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)

                events.append(
                    PlaybackCaptionEvent(
                        startTime: elapsed,
                        duration: duration,
                        kind: rawAnnotation.kind,
                        actorLabel: displayName(for: actor),
                        caption: caption
                    )
                )
            }
        }

        return events.sorted {
            if abs($0.startTime - $1.startTime) > 0.001 {
                return $0.startTime < $1.startTime
            }
            return $0.actorLabel < $1.actorLabel
        }
    }

    private func displayName(for actor: PlannedScene.PlacedActor) -> String {
        if let name = actor.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let suffix = actor.actorId.split(separator: "_").last, Int(suffix) != nil {
            return localizedCopy(.storyboardActorNumber, arguments: [String(suffix)])
        }
        return localizedCopy(.storyboardActor)
    }

    private func formatPosition(_ position: Position3D) -> String {
        "(\(formatFloat(position.x)), \(formatFloat(position.y)), \(formatFloat(position.z)))"
    }

    private func formatVector(_ vector: simd_float3) -> String {
        "(\(formatFloat(vector.x)), \(formatFloat(vector.y)), \(formatFloat(vector.z)))"
    }

    private func formatFloat(_ value: Float) -> String {
        String(format: "%.3f", Double(value))
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }

    private func quotedForLog(_ value: String?) -> String {
        guard let value else { return "nil" }
        let sanitized = value
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "'\(sanitized)'"
    }

    private func sanitizeCaption(_ caption: String) -> String {
        caption
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Мгновенно устанавливает актёров на стартовые позиции playback (без анимации)
    private func setActorsToInitialPositionsInstantly() {
        guard let planned = plannedScene else { return }
        
        for actor in planned.placedActors {
            guard let entity = placedEntities[actor.id] else {
                print("🎬 [PLAYBACK][\(currentPlaybackLogID ?? "nil")] initial position skipped: entity missing actor=\(displayName(for: actor)), id=\(actor.id)")
                continue
            }
            
            // Останавливаем любые текущие анимации этого entity
            entity.stopAllAnimations()
            
            // Мгновенно устанавливаем позицию
            let startPosition = playbackStartPosition(for: actor)
            entity.position = startPosition.simdVector
            entity.orientation = simd_quatf(angle: actor.initialRotation, axis: [0, 1, 0])
            actorFocusEntities[actor.id]?.position = startPosition.simdVector + SIMD3<Float>(0, 0.025, 0)
            diagnosticsLog("🎬 [PLAYBACK][\(currentPlaybackLogID ?? "nil")] start position actor=\(displayName(for: actor)), position=\(formatPosition(startPosition)), initial=\(formatPosition(actor.initialPosition)), rotation=\(formatFloat(actor.initialRotation))")
        }
    }
    
    // MARK: - Object Matching
    
    /// Applies the typed resolver output to persisted-compatible SceneObject
    /// values.  A parser-provided position is cleared before the result is
    /// consulted so an ambiguous marker can never leak through the old parser
    /// fallback.
    private func matchObjectsWithMarkedAndDetected(
        _ scriptObjects: [SceneObject],
        bindingResult: SceneObjectBindingResult
    ) -> [SceneObject] {
        scriptObjects.map { scriptObject in
            var updatedObject = scriptObject
            updatedObject.detectedPosition = nil
            guard let resolution = bindingResult.resolution(for: scriptObject.id),
                  resolution.state == .bound,
                  let binding = resolution.binding else {
                return updatedObject
            }
            updatedObject.name = binding.name
            if binding.source != .virtual {
                updatedObject.detectedPosition = binding.worldPosition
            }
            return updatedObject
        }
    }

    /// Reattaches source metadata after planning.  SpatialPlanner uses the
    /// already-resolved positions but has no knowledge of binding provenance.
    private func applyBindingSources(
        to plannedScene: PlannedScene,
        bindingResult: SceneObjectBindingResult
    ) -> PlannedScene {
        let placedObjects = plannedScene.placedObjects.map { placedObject in
            guard let resolution = bindingResult.resolution(for: placedObject.objectId),
                  resolution.state == .bound,
                  let binding = resolution.binding else {
                return PlannedScene.PlacedObject(
                    id: placedObject.id,
                    objectId: placedObject.objectId,
                    type: placedObject.type,
                    position: placedObject.position,
                    rotation: placedObject.rotation,
                    isDetected: false,
                    placementSource: .virtual
                )
            }

            let source: PlannedScene.PlacedObject.PlacementSource
            switch binding.source {
            case .marked:
                source = .marked
            case .detected:
                source = .detected
            case .virtual:
                source = .virtual
            }
            return PlannedScene.PlacedObject(
                id: placedObject.id,
                objectId: placedObject.objectId,
                type: placedObject.type,
                position: binding.worldPosition ?? placedObject.position,
                rotation: placedObject.rotation,
                isDetected: source != .virtual,
                placementSource: source
            )
        }
        return PlannedScene(
            placedActors: plannedScene.placedActors,
            placedObjects: placedObjects
        )
    }
    
    /// Устаревший метод - теперь addObjectsFromMarkedObjects выполняется внутри парсера
    /// Оставлен для обратной совместимости, но больше не используется
    @available(*, deprecated, message: "Размеченные объекты теперь обрабатываются внутри парсера")
    private func addObjectsFromMarkedObjects(
        description: String,
        existingObjects: [SceneObject]
    ) -> [SceneObject] {
        // Метод больше не используется - парсер сам обрабатывает markedObjects
        return []
    }

    private func prepareWorkspaceIfNeeded() {
        if !hasAutoPromptedDescription {
            hasAutoPromptedDescription = true
        }
    }

    func toggleHintsEnabled() {
        guard canToggleHints else {
            print("[CA_DEBUG][HINT_TOGGLE] ignored while workspace is busy")
            return
        }
        isHintsEnabled.toggle()
        print("[CA_DEBUG][HINT_TOGGLE] enabled=\(isHintsEnabled) recording=\(isRecording) pause=\(isHintPauseAnalysisActive)")
        if !isHintsEnabled {
            clearHintPresentation()
        }
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
    }

    func startHintPauseAnalysis() {
        guard isHintsEnabled else { return }
        guard !isHintPauseAnalysisActive, hintPauseDisplayRenderTask == nil else { return }

        // Accept the current evidence synchronously, before any asynchronous
        // work can advance the live frame owner. The same accepted envelope is
        // later rendered and passed to the typed pause-analysis entry point.
        let acceptedSnapshot = analysisPipeline.acceptPauseSnapshot()
        let requestToken = UUID()
        let requestGeneration = expectedARFrameGeneration
        hintPauseRequestToken = requestToken
        acceptedHintPauseRequestToken = acceptedSnapshot == nil ? nil : requestToken
        hintPauseRequestGeneration = requestGeneration
        acceptedHintPauseSnapshot = acceptedSnapshot
        pendingHintPauseAnalysis = nil
        hintPauseFailureReason = nil
        hintPausePresentationState = .loading(
            snapshotID: acceptedSnapshot?.snapshotID ?? requestToken.uuidString
        )
        isHintPauseAnalysisActive = acceptedSnapshot != nil
        if acceptedSnapshot != nil {
            hintPauseTakeNumber += 1
        }
        hintPreviewSuggestions = []
        hintPauseCritique = nil
        print("[CA_DEBUG][PAUSE_START] token=\(requestToken.uuidString) snapshot=\(acceptedSnapshot?.snapshotID ?? "nil") liveHint=\(liveHint?.text ?? "nil") overlayBBox=\(formatDebugRect(coachingOverlayState.primaryBoundingBox))")
        analysisPipeline.clearLivePresentationState()

        guard let acceptedSnapshot else {
            // Keep the failure visible so the user gets an honest recovery
            // action, but never fabricate an active review or a frame image.
            hintPauseRequestToken = nil
            hintPauseRequestGeneration = nil
            isHintPauseAnalysisActive = true
            hintPauseFailureReason = .noAcceptedEvidence
            hintPausePresentationState = .failure(snapshotID: requestToken.uuidString)
            return
        }

        let pipeline = analysisPipeline
        hintPauseDisplayRenderTask = Task { [weak self, pipeline] in
            let renderedSnapshot = await pipeline.renderPauseDisplayImage(for: acceptedSnapshot)
            guard let self,
                  !self.isWorkspaceReleased,
                  self.isHintPauseAnalysisActive,
                  self.hintPauseRequestToken == requestToken,
                  self.acceptedHintPauseRequestToken == requestToken,
                  self.hintPauseRequestGeneration == requestGeneration,
                  self.expectedARFrameGeneration == requestGeneration,
                  self.acceptedHintPauseSnapshot?.snapshotID == acceptedSnapshot.snapshotID else {
                return
            }

            self.hintPauseDisplayRenderTask = nil
            guard let renderedSnapshot,
                  renderedSnapshot.displayImage != nil else {
                self.acceptedHintPauseSnapshot = nil
                self.acceptedHintPauseRequestToken = nil
                self.hintPauseRequestToken = nil
                self.hintPauseRequestGeneration = nil
                self.pendingHintPauseAnalysis = nil
                self.hintPauseFailureReason = .displayRenderFailed
                self.hintPausePresentationState = .failure(
                    snapshotID: acceptedSnapshot.snapshotID
                )
                return
            }

            self.acceptedHintPauseSnapshot = renderedSnapshot
            pipeline.runPauseAnalysisResult(acceptedSnapshot: renderedSnapshot) { [weak self] result, suggestions, critique in
                Task { @MainActor [weak self] in
                    guard let self,
                          !self.isWorkspaceReleased,
                          self.isHintPauseAnalysisActive,
                          self.hintPauseRequestToken == requestToken,
                          self.acceptedHintPauseRequestToken == requestToken,
                          self.hintPauseRequestGeneration == requestGeneration,
                          self.expectedARFrameGeneration == requestGeneration,
                          self.acceptedHintPauseSnapshot?.snapshotID == renderedSnapshot.snapshotID else {
                        return
                    }
                    guard result != .cancelled else { return }

                    self.pendingHintPauseAnalysis = PendingHintPauseAnalysis(
                        result: result,
                        suggestions: suggestions,
                        critique: critique
                    )
                    self.applyPendingHintPauseAnalysisIfReady()

                    let critiqueText = critique.map {
                        "verdict=\($0.verdict.rawValue) confidence=\(self.formatDebugDouble($0.verdictConfidence)) short=\($0.shortVerdict)"
                    } ?? "nil"
                    print("[CA_DEBUG][PAUSE_RESULT] token=\(requestToken.uuidString) snapshot=\(renderedSnapshot.snapshotID) result=\(result) suggestions=\(suggestions.count) critique=\(critiqueText)")
                }
            }
        }
    }

    func resumeHintLiveAnalysis() {
        guard isHintPauseAnalysisActive
            || acceptedHintPauseSnapshot != nil
            || hintPausePresentationState != .idle else { return }

        hintPauseDisplayRenderTask?.cancel()
        hintPauseDisplayRenderTask = nil
        isHintPauseAnalysisActive = false
        hintPauseRequestToken = nil
        acceptedHintPauseRequestToken = nil
        hintPauseRequestGeneration = nil
        acceptedHintPauseSnapshot = nil
        pendingHintPauseAnalysis = nil
        hintPauseFailureReason = nil
        hintPausePresentationState = .idle
        hintPreviewSuggestions = []
        hintPauseCritique = nil
        print("[CA_DEBUG][PAUSE_RESUME_LIVE] liveStateReset=true")
        analysisPipeline.clearPausePresentationState()
        analysisPipeline.clearLivePresentationState()
    }

    @MainActor
    func setCameraDemoSceneMode(_ mode: CameraDemoSceneMode) {
        cameraDemoSceneMode = mode
        analysisPipeline.setCameraDemoSceneMode(mode)
        analysisPipeline.clearLivePresentationState()
    }

    func makeHintDecisionTrace() -> DecisionTracePresentation? {
        DecisionTracePresentation.current(
            liveHint: liveHint,
            pauseCritique: hintPauseCritique,
            isPaused: isHintPauseAnalysisActive,
            overlayAnnotations: coachingOverlayAnnotations,
            debugSignals: makeHintDecisionDebugSignals(),
            locale: presentationLocale
        )
    }

    /// UIKit keeps its existing synchronous target; the owner Task below is
    /// the only start identity and microphone request is reached only here.
    func startRecording() {
        guard !isRecordingStarting else { return }
        recordingPermissionRecovery = nil
        guard plannedScene != nil else {
            errorMessage = localizedCopy(.generatorErrorNoScene)
            return
        }
        guard canStartRecording else {
            if !isARSessionReady || isARSessionInterrupted || isARSessionRecovering {
                errorMessage = localizedCopy(.generatorErrorARNotReady)
            }
            return
        }

        isRecordingStarting = true
        recordingStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRecordingStarting = false
                self.recordingStartTask = nil
            }
            await self.beginRecordingAfterMicrophonePermission()
        }
    }

    private func beginRecordingAfterMicrophonePermission() async {
        guard !Task.isCancelled,
              teardownTask == nil,
              !isWorkspaceReleased,
              plannedScene != nil,
              !isRecording,
              !isRecordingFinalizing,
              !isPlaying,
              !isARSessionInterrupted,
              !isARSessionRecovering else { return }
        guard let recordingController else {
            errorMessage = localizedCopy(.generatorErrorRecorder)
            recordingPermissionRecovery = nil
            return
        }

        let audioPolicy = selectedRecordingAudioPolicy
        let audioLease: AudioSessionLease?
        if audioPolicy.mode == .required {
            let currentMicrophone = await permissionClient.snapshot(for: .microphone)
            guard !Task.isCancelled else { return }
            guard currentMicrophone.availability == .available else {
                publishRecordingAudioFailure(
                    copy: .generatorErrorRecorder,
                    recovery: nil,
                    offerVideoOnly: true
                )
                return
            }

            let microphone = currentMicrophone.authorization == .notDetermined
                ? await permissionClient.request(.microphone)
                : currentMicrophone
            guard !Task.isCancelled else { return }
            guard microphone.availability == .available else {
                publishRecordingAudioFailure(
                    copy: .generatorErrorRecorder,
                    recovery: nil,
                    offerVideoOnly: true
                )
                return
            }
            guard microphone.authorization == .authorized else {
                switch microphone.authorization {
                case .denied:
                    publishRecordingAudioFailure(
                        copy: .generatorErrorMicrophoneDenied,
                        recovery: .openSettings,
                        offerVideoOnly: true
                    )
                case .restricted:
                    publishRecordingAudioFailure(
                        copy: .generatorErrorMicrophoneRestricted,
                        recovery: .recheck,
                        offerVideoOnly: true
                    )
                default:
                    publishRecordingAudioFailure(
                        copy: .generatorErrorRecorder,
                        recovery: nil,
                        offerVideoOnly: true
                    )
                }
                return
            }

            do {
                let lease = try await audioSessionCoordinator.acquire(
                    ownerID: recordingAudioOwnerID,
                    purpose: .recording
                )
                try await audioSessionCoordinator.activate(
                    lease,
                    configuration: .recording
                )
                audioLease = lease
            } catch {
                publishRecordingAudioFailure(
                    copy: .generatorErrorRecorder,
                    recovery: nil,
                    offerVideoOnly: true
                )
                return
            }
        } else {
            audioLease = nil
        }

        guard !Task.isCancelled,
              teardownTask == nil,
              !isWorkspaceReleased,
              let sourceFPS = recordingSourceFPS,
              sourceFPS > 0 else {
            if let audioLease {
                try? await audioSessionCoordinator.deactivate(audioLease)
            }
            return
        }
        do {
            try await recordingController.start(
                requestedFPS: sourceFPS,
                audioMode: audioPolicy.mode
            )
        } catch {
            if let audioLease {
                try? await audioSessionCoordinator.deactivate(audioLease)
            }
            publishRecordingAudioFailure(
                copy: .generatorErrorRecorder,
                recovery: nil,
                offerVideoOnly: audioPolicy.mode == .required
            )
            return
        }

        errorMessage = nil
        recordingPermissionRecovery = nil
        recordingVideoOnlyRecoveryAvailable = false
        recordingAudioLease = audioLease

        if let dimensions = recordingController.currentVideoDimensions {
            recordingResolutionLabel = "\(dimensions.width)×\(dimensions.height)"
        }

        guard !isWorkspaceReleased else {
            _ = await recordingController.stop(reason: .routeExit)
            await releaseRecordingAudioLease()
            return
        }
        prepareWorkspaceIfNeeded()
        isHintsEnabled = true
        isRecording = true
        recordingElapsedTime = 0
        recordingStartDate = Date()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let recordingStartDate = self.recordingStartDate else { return }
                self.recordingElapsedTime = Date().timeIntervalSince(recordingStartDate)
            }
        }
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
    }

    private func publishRecordingAudioFailure(
        copy: SETCopyKey,
        recovery: SceneRecordingPermissionRecovery?,
        offerVideoOnly: Bool
    ) {
        errorMessage = localizedCopy(copy)
        recordingPermissionRecovery = recovery
        recordingVideoOnlyRecoveryAvailable = offerVideoOnly
    }

    private func releaseRecordingAudioLease() async {
        guard let audioLease = recordingAudioLease else { return }
        recordingAudioLease = nil
        try? await audioSessionCoordinator.deactivate(audioLease)
    }

    /// The shell calls this before presenting a finalized take. The lease is
    /// stored in the ViewModel so route teardown can release it even if UIKit
    /// dismisses the player without a delegate callback.
    func acquireRecordingPlaybackLease(ownerID: UUID) async throws -> AudioSessionLease {
        guard !isWorkspaceReleased,
              teardownTask == nil,
              !isRecording,
              !isRecordingStarting,
              !isRecordingFinalizing,
              !isPlaying else {
            throw AudioSessionCoordinatorError.busy(
                ownerID: recordingAudioOwnerID,
                purpose: .recording
            )
        }

        let lease = try await audioSessionCoordinator.acquire(
            ownerID: ownerID,
            purpose: .playback
        )
        do {
            try await audioSessionCoordinator.activate(
                lease,
                configuration: .playback
            )
        } catch {
            // The coordinator clears failed activations; keep this method's
            // ownership projection equally empty on every failure path.
            throw error
        }
        recordingPlaybackLease = lease
        return lease
    }

    func releaseRecordingPlaybackLease(ownerID: UUID? = nil) async {
        guard let playbackLease = recordingPlaybackLease,
              ownerID == nil || playbackLease.ownerID == ownerID else { return }
        recordingPlaybackLease = nil
        try? await audioSessionCoordinator.deactivate(playbackLease)
    }

    func stopRecording() {
        requestStopRecording(reason: .user)
    }

    private func requestStopRecording(reason: RecordingStopReason) {
        guard isRecording || isRecordingStarting || isRecordingFinalizing else { return }
        guard recordingStopTask == nil else { return }
        let task: Task<RecordingStopResult?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performStopRecording(reason: reason)
        }
        recordingStopTask = task
    }

    /// Teardown and user stop share one awaited finalization identity. User
    /// stop persists only after the recorder has returned its terminal result;
    /// route exit leaves persistence to SceneWorkspaceTeardownCoordinator.
    private func stopRecordingAndWait(reason: RecordingStopReason) async -> RecordingStopResult? {
        if let recordingStopTask {
            return await recordingStopTask.value
        }

        let task: Task<RecordingStopResult?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performStopRecording(reason: reason)
        }
        recordingStopTask = task
        return await task.value
    }

    private func performStopRecording(reason: RecordingStopReason) async -> RecordingStopResult? {

        recordingStartTask?.cancel()
        if let recordingStartTask {
            await recordingStartTask.value
        }

        guard isRecording || isRecordingStarting || isRecordingFinalizing else {
            let result = await recordingController?.stop(reason: reason)
            acceptFinalizedRecording(from: result)
            await releaseRecordingAudioLease()
            recordingStopTask = nil
            return result
        }

        isRecording = false
        isRecordingFinalizing = true
        if let recordingStartDate {
            recordingElapsedTime = Date().timeIntervalSince(recordingStartDate)
        }
        recordingStartDate = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        refreshWorkspaceMode()
        refreshIdleStatusMessage()

        let result = await recordingController?.stop(reason: reason)
        acceptFinalizedRecording(from: result)
        await releaseRecordingAudioLease()
        if case .failed = result {
            errorMessage = localizedCopy(.generatorErrorRecorder)
            recordingPermissionRecovery = nil
        }
        isRecordingFinalizing = false
        refreshWorkspaceMode()
        if !isARSessionInterrupted && !isARSessionRecovering {
            refreshIdleStatusMessage()
        }

        if reason == .user, !suppressAutomaticPersistence {
            _ = await persistProjectSnapshot()
        }
        recordingStopTask = nil
        return result
    }

    /// Consumes only a recorder-attested finalized result. Promotion happens
    /// before the caller's persistence step, and the ID ledger prevents a
    /// coalesced/retried stop from publishing the same take twice.
    private func acceptFinalizedRecording(from result: RecordingStopResult?) {
        guard case let .finalized(artifact) = result else { return }
        queuePendingFinalizedRecording(artifact)
        _ = retryPendingFinalizedRecordings()
    }

    @discardableResult
    private func promoteFinalizedRecording(_ artifact: RecordingArtifact) -> Bool {
        let recordingID = artifact.id.rawValue
        guard !promotedRecordingIDs.contains(recordingID) else {
            removePendingFinalizedRecording(recordingID)
            return true
        }
        guard let recordingController else {
            queuePendingFinalizedRecording(artifact)
            errorMessage = localizedCopy(.generatorErrorRecorder)
            recordingPermissionRecovery = nil
            return false
        }

        do {
            let reference = try recordingController.promoteFinalizedArtifact(
                artifact,
                projectID: currentProject.id
            )
            guard let resolvedArtifact = recordingController.resolve(reference) else {
                queuePendingFinalizedRecording(artifact)
                errorMessage = localizedCopy(.generatorErrorRecorder)
                recordingPermissionRecovery = nil
                return false
            }
            promotedRecordingIDs.insert(recordingID)
            removePendingFinalizedRecording(recordingID)
            if !recordingReferences.contains(where: { $0.recordingID == recordingID }) {
                recordingReferences.append(reference)
            }
            latestAvailableRecordingArtifact = resolvedArtifact
            return true
        } catch {
            // Promotion never deletes a pending source on failure; keeping the
            // artifact here also gives a later recovery path its original URL.
            queuePendingFinalizedRecording(artifact)
            errorMessage = localizedCopy(.generatorErrorRecorder)
            recordingPermissionRecovery = nil
            return false
        }
    }

    private func queuePendingFinalizedRecording(_ artifact: RecordingArtifact) {
        let recordingID = artifact.id.rawValue
        if let index = pendingRecordingArtifacts.firstIndex(where: { $0.id.rawValue == recordingID }) {
            pendingRecordingArtifacts[index] = artifact
        } else {
            pendingRecordingArtifacts.append(artifact)
        }
    }

    private func removePendingFinalizedRecording(_ recordingID: UUID) {
        pendingRecordingArtifacts.removeAll { $0.id.rawValue == recordingID }
    }

    private func retryPendingFinalizedRecordings() -> Bool {
        while let artifact = pendingRecordingArtifacts.first {
            guard promoteFinalizedRecording(artifact) else {
                return false
            }
        }
        return true
    }

    private func processHintFrameIfNeeded(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        guard isHintsEnabled else {
            if liveHint != nil
                || hintPauseCritique != nil
                || !hintPreviewSuggestions.isEmpty
                || !coachingOverlayAnnotations.isEmpty
                || isHintPauseAnalysisActive
                || acceptedHintPauseSnapshot != nil
                || hintPausePresentationState != .idle {
                clearHintPresentation()
            }
            return
        }

        guard !isHintPauseAnalysisActive else { return }

        let context = makeHintContext(pixelBuffer: pixelBuffer, timestamp: timestamp)
        let budget = hintThermalGovernor.nextBudget()
        Telemetry.shared.setHeavyModelsEnabled(budget.heavyModelsEnabled)
        let highHintFrameInterval = hintFrameInterval(for: budget.highPriorityFrequency)
        let mediumHintFrameInterval = hintFrameInterval(for: budget.mediumPriorityFrequency)
        let lowHintFrameInterval = hintFrameInterval(for: budget.lowPriorityFrequency)

        let willRunHigh = timestamp - lastHighHintTimestamp >= highHintFrameInterval
        let willRunMedium = timestamp - lastMediumHintTimestamp >= mediumHintFrameInterval
        let thermalLowDue = budget.heavyModelsEnabled &&
            context.isStable &&
            timestamp - lastLowHintTimestamp >= lowHintFrameInterval
        let objectDemoLowDue = cameraDemoSceneMode == .object &&
            hintThermalGovernor.currentTier() != .critical &&
            context.isStable &&
            timestamp - lastLowHintTimestamp >= objectDemoDetrHintFrameInterval
        let willRunLow = thermalLowDue || objectDemoLowDue
        let lowRunReason: String
        if objectDemoLowDue {
            lowRunReason = "object_demo_detr"
        } else if thermalLowDue {
            lowRunReason = "thermal_budget"
        } else {
            lowRunReason = "none"
        }
        logHintFrameIfNeeded(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            context: context,
            willRunHigh: willRunHigh,
            willRunMedium: willRunMedium,
            willRunLow: willRunLow,
            lowRunReason: lowRunReason
        )

        if willRunHigh {
            lastHighHintTimestamp = timestamp
            analysisPipeline.ingestHigh(context: context)
        }

        if willRunMedium {
            lastMediumHintTimestamp = timestamp
            analysisPipeline.ingestMedium(context: context)
        }

        if willRunLow {
            lastLowHintTimestamp = timestamp
            analysisPipeline.ingestLow(context: context)
        }
    }

    private func applyPendingHintPauseAnalysisIfReady() {
        guard isHintPauseAnalysisActive,
              let acceptedSnapshot = acceptedHintPauseSnapshot,
              acceptedSnapshot.displayImage != nil,
              let pendingHintPauseAnalysis else { return }

        self.pendingHintPauseAnalysis = nil
        hintPreviewSuggestions = pendingHintPauseAnalysis.suggestions
        hintPauseCritique = pendingHintPauseAnalysis.critique

        switch pendingHintPauseAnalysis.result {
        case .success:
            guard let critique = pendingHintPauseAnalysis.critique else {
                hintPauseFailureReason = nil
                hintPausePresentationState = .empty(snapshotID: acceptedSnapshot.snapshotID)
                return
            }
            hintPauseFailureReason = nil
            hintPausePresentationState = .success(
                snapshotID: acceptedSnapshot.snapshotID,
                critique: critique
            )
        case .empty:
            hintPauseFailureReason = nil
            hintPausePresentationState = .empty(snapshotID: acceptedSnapshot.snapshotID)
        case .failure(let failure):
            hintPauseFailureReason = switch failure {
            case .noAcceptedEvidence: .noAcceptedEvidence
            case .pipelineUnavailable: .pipelineUnavailable
            case .timeout: .timeout
            }
            hintPausePresentationState = .failure(snapshotID: acceptedSnapshot.snapshotID)
        case .cancelled:
            break
        }
    }

    private func hintFrameInterval(for frequency: Double) -> TimeInterval {
        guard frequency > 0 else { return disabledHintFrameInterval }
        return 1.0 / frequency
    }

    private func makeHintContext(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> FrameContext {
        FrameContext(
            pixelBuffer: pixelBuffer,
            timestamp: CMTimeMakeWithSeconds(timestamp, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            orientation: arCameraAnalysisOrientation,
            isStable: !isMarkingMode,
            shakeLevel: isRecording ? 0.2 : 0.05,
            motionState: isMarkingMode ? .moving : .still
        )
    }

    private var arCameraAnalysisOrientation: CGImagePropertyOrientation {
        switch arInterfaceOrientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeRight:
            return .up
        case .landscapeLeft:
            return .down
        case .unknown:
            return .right
        @unknown default:
            return .right
        }
    }

    private func logHintFrameIfNeeded(pixelBuffer: CVPixelBuffer,
                                      timestamp: TimeInterval,
                                      context: FrameContext,
                                      willRunHigh: Bool,
                                      willRunMedium: Bool,
                                      willRunLow: Bool,
                                      lowRunReason: String) {
        hintFrameDebugCounter += 1
        guard timestamp - lastHintFrameDebugLogTimestamp >= 1.0 || willRunLow else { return }
        lastHintFrameDebugLogTimestamp = timestamp
        print(
            "[CA_DEBUG][HINT_FRAME] idx=\(hintFrameDebugCounter) ts=\(formatDebugDouble(timestamp)) " +
            "image=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) " +
            "uiOrientation=\(debugInterfaceOrientationDescription(arInterfaceOrientation)) " +
            "cgOrientation=\(debugCGOrientationDescription(context.orientation)) " +
            "stable=\(context.isStable) motion=\(String(describing: context.motionState)) shake=\(formatDebugDouble(context.shakeLevel)) " +
            "recording=\(isRecording) marking=\(isMarkingMode) pause=\(isHintPauseAnalysisActive) " +
            "runHigh=\(willRunHigh) runMedium=\(willRunMedium) runLow=\(willRunLow) lowReason=\(lowRunReason) " +
            "displayTransform=\(hintDisplayTransform.map(formatDebugTransform) ?? "nil")"
        )
    }

    private func debugInterfaceOrientationDescription(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait:
            return "portrait"
        case .portraitUpsideDown:
            return "portraitUpsideDown"
        case .landscapeLeft:
            return "landscapeLeft"
        case .landscapeRight:
            return "landscapeRight"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknownFuture"
        }
    }

    private func debugCGOrientationDescription(_ orientation: CGImagePropertyOrientation) -> String {
        switch orientation {
        case .up:
            return "up"
        case .upMirrored:
            return "upMirrored"
        case .down:
            return "down"
        case .downMirrored:
            return "downMirrored"
        case .left:
            return "left"
        case .leftMirrored:
            return "leftMirrored"
        case .right:
            return "right"
        case .rightMirrored:
            return "rightMirrored"
        }
    }

    private func formatDebugTransform(_ transform: CGAffineTransform) -> String {
        "[a=\(formatDebugDouble(transform.a)) b=\(formatDebugDouble(transform.b)) c=\(formatDebugDouble(transform.c)) d=\(formatDebugDouble(transform.d)) tx=\(formatDebugDouble(transform.tx)) ty=\(formatDebugDouble(transform.ty))]"
    }

    private func formatDebugRect(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return "[x=\(formatDebugDouble(rect.minX)) y=\(formatDebugDouble(rect.minY)) w=\(formatDebugDouble(rect.width)) h=\(formatDebugDouble(rect.height))]"
    }

    private func formatDebugDouble(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func formatDebugDouble(_ value: CGFloat) -> String {
        formatDebugDouble(Double(value))
    }

    private func makeHintDecisionDebugSignals() -> DecisionTraceDebugSignals {
        let debugData = analysisPipeline.currentDebugData
        return DecisionTraceDebugSignals.make(
            features: analysisPipeline.currentFeatures,
            detrDetections: debugData.detrDetections,
            visionSubjects: debugData.visionSubjects,
            saliencyCenter: debugData.saliencyCenter
        )
    }

    private func clearHintPresentation() {
        clearHintPauseProjection()
        analysisPipeline.clearLivePresentationState()
        analysisPipeline.clearPausePresentationState()
        coachingOverlayState = .init(primaryBoundingBox: nil,
                                     horizonAngle: 0,
                                     horizonConfidence: 0,
                                     saliencyBalance: 0)
        if hintDisplayTransform != nil {
            hintDisplayTransform = nil
        }
        liveHint = nil
        coachingOverlayAnnotations = []
    }

    /// Cancels every owner-side pause handoff before the pipeline clears its
    /// own publication fence. Late render/analysis completions must therefore
    /// fail both token and generation checks before touching the projection.
    private func clearHintPauseProjection() {
        hintPauseDisplayRenderTask?.cancel()
        hintPauseDisplayRenderTask = nil
        isHintPauseAnalysisActive = false
        hintPauseRequestToken = nil
        acceptedHintPauseRequestToken = nil
        hintPauseRequestGeneration = nil
        acceptedHintPauseSnapshot = nil
        pendingHintPauseAnalysis = nil
        hintPauseFailureReason = nil
        hintPausePresentationState = .idle
        hintPreviewSuggestions = []
        hintPauseCritique = nil
    }

    private func persistProjectMetadata() {
#if DEBUG
        guard debugFixtureID == nil else { return }
#endif
        guard !isWorkspaceReleased else { return }
        // A world-map snapshot owns the next complete write. Metadata changes
        // made while its AR callback is pending are folded into that write
        // after capture; an eager metadata save here would reintroduce the
        // stale-project race this owner is meant to close.
        guard projectSnapshotTask == nil else { return }
        // M1-015: the pre-bump updatedAt is the stored version this metadata
        // write is based on; a conflict means another writer moved the file and
        // the newer stored write must not be clobbered by this autosave.
        let expectedUpdatedAt = currentProject.updatedAt
        currentProject = buildCurrentProject()
        do {
            try projectStore.saveUnifiedSceneProject(
                currentProject,
                worldMap: initialWorldMap,
                expectedUpdatedAt: expectedUpdatedAt
            )
        } catch DBServiceError.staleSnapshot(let storedUpdatedAt) {
            print("Unified scene metadata save conflicted with stored updatedAt \(storedUpdatedAt); kept stored version")
        } catch {
            print("Error saving unified scene metadata: \(error)")
        }
    }

    private func persistProjectSnapshot() async -> Result<Void, SceneWorkspaceTeardownFailure> {
#if DEBUG
        guard debugFixtureID == nil else { return .success(()) }
#endif
        if let projectSnapshotTask {
            return await projectSnapshotTask.value
        }

        let task: Task<Result<Void, SceneWorkspaceTeardownFailure>, Never> = Task { @MainActor [weak self] in
            guard let self else {
                return .failure(.workspaceOwnerUnavailable)
            }
            return await self.performProjectSnapshotPersistence()
        }
        projectSnapshotTask = task
        let result = await task.value
        projectSnapshotTask = nil
        return result
    }

    private func performProjectSnapshotPersistence() async -> Result<Void, SceneWorkspaceTeardownFailure> {
        guard retryPendingFinalizedRecordings() else {
            return .failure(.persistenceFailed)
        }

        switch await captureCurrentWorldMap() {
        case .success(let capturedWorldMap):
            // Build only after capture. Scene edits can arrive while ARKit is
            // waiting, and the persisted envelope must contain those edits.
            guard retryPendingFinalizedRecordings() else {
                return .failure(.persistenceFailed)
            }
            let worldMap = capturedWorldMap ?? initialWorldMap
            let expectedUpdatedAt = currentProject.updatedAt
            currentProject = buildCurrentProject()
            if let worldMap {
                initialWorldMap = worldMap
            }
            return saveProjectSnapshot(currentProject, worldMap: worldMap, expectedUpdatedAt: expectedUpdatedAt)
        case .failure(let failure):
            // A timed-out/cancelled/failed AR snapshot still writes the latest
            // project metadata with an explicit nil map. The typed failure
            // keeps teardown blocked for a retry, while preserving user edits
            // and preventing an unbounded wait.
            guard retryPendingFinalizedRecordings() else {
                return .failure(.persistenceFailed)
            }
            let expectedUpdatedAt = currentProject.updatedAt
            currentProject = buildCurrentProject()
            let saveResult = saveProjectSnapshot(currentProject, worldMap: nil, expectedUpdatedAt: expectedUpdatedAt)
            switch saveResult {
            case .success:
                // The nil-map write is the durable source of truth. Clear the
                // in-memory fallback only after it succeeds, otherwise a
                // retry with no fresh map can resurrect the stale map.
                initialWorldMap = nil
                return .failure(failure)
            case .failure(let saveFailure):
                return .failure(saveFailure)
            }
        }
    }

    private func saveProjectSnapshot(
        _ project: UnifiedSceneProject,
        worldMap: ARWorldMap?,
        expectedUpdatedAt: Date? = nil
    ) -> Result<Void, SceneWorkspaceTeardownFailure> {
#if DEBUG
        testingProjectSnapshotSaveCount += 1
#endif

        do {
            try projectStore.saveUnifiedSceneProject(
                project,
                worldMap: worldMap,
                expectedUpdatedAt: expectedUpdatedAt
            )
            return .success(())
        } catch DBServiceError.staleSnapshot(let storedUpdatedAt) {
            // M1-015: a stale teardown snapshot must not overwrite a newer
            // stored write; persistenceFailed keeps teardown blocked and
            // recoverable (M1-009 retry semantics).
            print("Unified scene snapshot conflicted with stored updatedAt \(storedUpdatedAt)")
            return .failure(.persistenceFailed)
        } catch {
            print("Error saving unified scene snapshot: \(error)")
            return .failure(.persistenceFailed)
        }
    }

    private func captureCurrentWorldMap() async -> Result<ARWorldMap?, SceneWorkspaceTeardownFailure> {
#if DEBUG
        if let testingWorldMapCaptureOverride {
            return await testingWorldMapCaptureOverride()
        }
#endif
        guard let arView else { return .success(initialWorldMap) }
        // Unsupported AR configurations (notably the simulator) may never
        // invoke getCurrentWorldMap's completion. Preserve the persisted map
        // and let the owning teardown route complete without waiting forever.
        guard ARWorldTrackingConfiguration.isSupported else {
            return .success(initialWorldMap)
        }
        return await SETWorldMapCaptureResolver<ARWorldMap?>.resolve(
            timeoutNanoseconds: Self.worldMapCaptureTimeoutNanoseconds,
            request: { completion in
                arView.session.getCurrentWorldMap { worldMap, error in
                    if let error {
                        print("Error capturing current world map: \(error)")
                        completion(.failure(.worldMapSnapshotFailed))
                        return
                    }
                    completion(.success(worldMap))
                }
            }
        )
    }

    private func buildCurrentProject() -> UnifiedSceneProject {
        var project = currentProject
        project.name = sceneTitle
        project.updatedAt = Date()
        project.sceneDescription = sceneDescription
        project.markedObjects = markedObjects
        project.parsedScript = parsedScript
        project.plannedScene = plannedScene
        project.sceneChunkState = sceneChunkState
        project.visualOverlays = visualOverlays
        project.recordingReferences = recordingReferences
        return project
    }

    private func restorePersistedEntitiesIfNeeded() {
        guard arView != nil, !hasRestoredPersistedEntities else { return }

        hasRestoredPersistedEntities = true
        for marker in markedObjects where markerEntities[marker.id] == nil {
            placeMarkerEntity(for: marker)
        }

        if let plannedScene {
            Task {
                placeObjectsInAR(plannedScene)
                refreshStoryboardBeatItems()
                refreshWorkspaceMode()
                refreshIdleStatusMessage()
            }
        } else {
            refreshStoryboardBeatItems()
            refreshWorkspaceMode()
            refreshIdleStatusMessage()
        }
    }

    private func refreshWorkspaceMode() {
        if isARSessionInterrupted || isARSessionRecovering {
            workspaceMode = .editingScene
            return
        }

        if isPlaying {
            workspaceMode = .previewPlayback
            return
        }

        if isRecording {
            workspaceMode = .recording
            return
        }

        if isMarkingMode {
            workspaceMode = .marking
            return
        }

        if plannedScene != nil {
            workspaceMode = isHintsEnabled ? .shooting : .generatedReady
            return
        }

        workspaceMode = .editingScene
    }

    private func refreshIdleStatusMessage() {
        guard !isGenerating else { return }

        switch workspaceMode {
        case .editingScene:
            if isARSessionInterrupted {
                statusMessage = localizedCopy(.cameraInterrupted)
            } else if isARSessionRecovering {
                statusMessage = localizedCopy(.cameraResuming)
            } else if !isARSessionReady {
                statusMessage = localizedCopy(.generatorStatusIdleSurface)
            } else if sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                statusMessage = localizedCopy(.generatorStatusIdleDescription)
            } else {
                statusMessage = localizedCopy(.generatorStatusIdleReady)
            }
        case .marking:
            statusMessage = localizedCopy(.generatorStatusMarking)
        case .generatedReady:
            statusMessage = localizedCopy(.generatorStatusGeneratedReady)
        case .shooting:
            statusMessage = localizedCopy(.generatorStatusShooting)
        case .recording:
            statusMessage = localizedCopy(.generatorStatusRecording)
        case .previewPlayback:
            statusMessage = localizedCopy(.generatorStatusPreview)
        }
    }
}

#if DEBUG
extension SceneGeneratorViewModel {
    var testingStoryboardFixtureID: String? {
        debugFixtureID
    }

    private static func storyboardFixtureID(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: SETGalleryLaunchConfiguration.generatorStoryboardFixtureArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        let fixtureID = arguments[index + 1]
        return SETFixtureCatalog.generatorStoryboardFixtureIDs.contains(fixtureID) ? fixtureID : nil
    }

    /// Seeds the existing script/planner owners for simulator evidence. The
    /// payload is deterministic domain data, not an image or AR substitute,
    /// and the fixture flag keeps teardown/metadata persistence inert.
    private func loadDebugStoryboardFixture(_ fixtureID: String) {
        let isEnglish = presentationLocale.language.languageCode?.identifier == "en"
        let actorOneName = isEnglish ? "Mara" : "Мара"
        let actorTwoName = isEnglish ? "Noah" : "Ной"
        let tableName = isEnglish ? "table" : "стол"
        let description = isEnglish
            ? "A deterministic storyboard rehearsal in a quiet room."
            : "Детерминированная репетиция раскадровки в тихой комнате."

        let actorOne = SceneActor(id: "actor_1", type: .human, name: actorOneName)
        let actorTwo = SceneActor(id: "actor_2", type: .human, name: actorTwoName)
        let table = SceneObject(
            id: "object_table",
            type: .table,
            name: tableName,
            relativePosition: .center
        )
        let beats = [
            SceneBeat(
                id: "beat_1",
                actions: [
                    SceneAction(
                        id: "action_walk",
                        actorId: actorOne.id,
                        type: .walk,
                        target: table.id,
                        direction: .toTarget,
                        resultingPose: .standing,
                        sourceText: isEnglish ? "Mara steps toward the table." : "Мара подходит к столу."
                    )
                ],
                camera: CameraSetup(shotType: .medium, movement: .static, target: actorOne.id),
                minDuration: 1.2
            ),
            SceneBeat(
                id: "beat_2",
                actions: [
                    SceneAction(
                        id: "action_talk",
                        actorId: actorOne.id,
                        type: .talk,
                        resultingPose: .standing,
                        dialogue: isEnglish ? "The room settles." : "Комната затихает."
                    ),
                    SceneAction(
                        id: "action_look",
                        actorId: actorTwo.id,
                        type: .lookAt,
                        target: actorOne.id,
                        resultingPose: .standing,
                        sourceText: isEnglish ? "Noah looks toward Mara." : "Ной смотрит на Мару."
                    )
                ],
                camera: CameraSetup(shotType: .twoShot, movement: .static, target: actorOne.id),
                minDuration: 1.4
            ),
            SceneBeat(
                id: "beat_3",
                actions: [
                    SceneAction(
                        id: "action_give",
                        actorId: actorOne.id,
                        type: .give,
                        target: actorTwo.id,
                        resultingPose: .standing,
                        sourceText: isEnglish ? "Mara passes the note to Noah." : "Мара передаёт записку Ною."
                    )
                ],
                camera: CameraSetup(shotType: .closeUp, movement: .dollyIn, target: actorTwo.id),
                minDuration: 1.7
            )
        ]
        let script = SceneScript(
            sceneHeading: isEnglish ? "INT. QUIET ROOM - DAY" : "ИНТ. ТИХАЯ КОМНАТА — ДЕНЬ",
            locationName: isEnglish ? "QUIET ROOM" : "ТИХАЯ КОМНАТА",
            interiorExterior: "interior",
            timeOfDay: "day",
            actors: [actorOne, actorTwo],
            objects: [table],
            beats: beats,
            spatialRelations: [],
            originalDescription: description
        )

        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.6, 0, 1)
        currentCameraTransform = cameraTransform
        detectedPlanes = [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        isARSessionReady = true
        sceneDescription = description
        parsedScript = script
        parsingResult = ParsingResult(script: script, diagnostics: .empty)
        plannedScene = plannerService.planScene(
            script: script,
            cameraTransform: cameraTransform,
            detectedObjects: [],
            availablePlanes: detectedPlanes,
            markedObjects: []
        )
        beatTimelineItems = buildBeatTimelineItems(for: plannedScene!, script: script)
        refreshStoryboardBeatItems()
        statusMessage = localizedCopy(.generatorStatusGeneratedReady)

        switch fixtureID {
        case "storyboard.inspector", "storyboard.editor-medium", "storyboard.editor-large",
             "storyboard.saving", "storyboard.validation-failure", "storyboard.delete-confirmation":
            openStoryboardEditor(for: "beat_1")
        default:
            break
        }

        if fixtureID == "storyboard.validation-failure",
           var invalidDraft = activeStoryboardEditDraft,
           let actionIndex = invalidDraft.actions.indices.first {
            invalidDraft.actions[actionIndex].type = .give
            invalidDraft.actions[actionIndex].target = invalidDraft.actions[actionIndex].actorId
            activeStoryboardEditDraft = invalidDraft
        }
    }

    private func seedDebugDecisionTraceFixture() {
        let issueID = "fixture_generator_issue_background"
        let issueRegion = NormalizedRect(x: 0.56, y: 0.20, width: 0.28, height: 0.48)
        let observation = localizedCopy(.cameraCorrectiveObservation)
        let support = localizedCopy(.traceStrengthFocus)
        let action = localizedCopy(.traceActionSimplifyBackground)

        isHintsEnabled = true
        liveHint = LiveHintPresentation(
            id: "generator_fixture_live_hint",
            frameId: "generator_fixture_frame",
            text: observation,
            confidence: 0.82,
            actionType: .reduceBackgroundDistractions,
            actionId: "generator_fixture_action_simplify",
            linkedIssueIds: [issueID],
            summaryId: "generator_fixture_summary",
            traceRootIds: ["generator_fixture_trace_root"],
            targetRegion: issueRegion,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: observation,
                supportingText: support,
                actionText: action,
                fallbackUsed: false
            )
        )
        coachingOverlayAnnotations = [
            OverlayAnnotationPresentation(
                id: "generator_fixture_annotation",
                kind: .regionHighlight,
                direction: nil,
                targetRegion: issueRegion,
                emphasis: 0.82,
                tone: .warning,
                label: localizedCopy(.traceKindIssue)
            )
        ]
    }

    var testingARCameraAnalysisOrientation: CGImagePropertyOrientation {
        arCameraAnalysisOrientation
    }

    func testingSetARInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        arInterfaceOrientation = orientation
    }

    func testingSetPlanningContext(cameraTransform: simd_float4x4, planes: [ScenePlaneSnapshot]) {
        currentCameraTransform = cameraTransform
        detectedPlanes = planes
        isARSessionReady = true
    }

    /// UI-test support only: marks the AR session ready so the generator's
    /// loading overlay does not block the settings bar on simulators, where
    /// no ARKit session can start. Never called from production flows.
    func testingMarkARSessionReady() {
        isARSessionReady = true
    }

    /// Drains the existing high-priority frame path for deterministic tests.
    /// Production callers never use this helper; the accepted pause snapshot
    /// still comes from the same evidence store as the reachable AR route.
    func testingDrainHintAnalysis() async {
        await analysisPipeline.testingDrainHighQueue()
        await Task.yield()
    }

    func testingSetStoryboardMutationDelay(_ delay: TimeInterval) {
        storyboardDebugMutationDelay = max(0, delay)
    }

    func testingSetGenerationDelay(_ delay: TimeInterval) {
        generationDebugDelay = max(0, delay)
    }

    /// Test-only injection at the parser boundary. The production path still
    /// uses SceneParserService; tests can return a deterministic immutable
    /// parse result without publishing through the binding seam.
    func testingSetParserResultOverride(
        _ override: ((String, [MarkedObject]) async -> ParsingResult)?
    ) {
        testingParserResultOverride = override
    }

    func testingResetGenerationStateTrace() {
        testingGenerationStateTrace = [generationRequestState]
    }

    /// Test-only parser seam: drives the same request-owned clarification edge
    /// while an active request is fenced by its real ID/epoch.
    @discardableResult
    func testingPublishParserClarification(message: String) -> Bool {
        guard let requestID = generationRequestState.requestID,
              let epoch = generationRequestState.epoch,
              generationRequestState.phase == .generating else {
            return false
        }
        return publishGenerationState(
            .clarification(requestID: requestID, epoch: epoch, message: message),
            expectedRequestID: requestID,
            expectedEpoch: epoch,
            status: localizedCopy(.generatorClarification),
            error: message
        )
    }

    /// Test-only seam for the same unresolved-binding gate used by
    /// performGeneration. It enforces request identity before publication and
    /// deliberately does not perform any planning or commit work.
    @discardableResult
    func testingPublishObjectBindingResult(_ result: SceneObjectBindingResult) -> Bool {
        guard let requestID = generationRequestState.requestID,
              let epoch = generationRequestState.epoch,
              generationRequestState.phase == .generating,
              result.requestID == requestID,
              result.epoch == epoch else {
            return false
        }
        objectBindingResult = result
        return stopForUnresolvedObjectBindings(
            result,
            requestID: requestID,
            generationToken: epoch
        )
    }

}
#endif

extension SceneGeneratorViewModel {
    static func shouldPassTouchesThroughSwiftUIOverlay(
        isMarkingMode: Bool,
        hasActiveStoryboardEditor: Bool
    ) -> Bool {
        _ = hasActiveStoryboardEditor
        return isMarkingMode
    }
}

private extension SceneAction.ActionType {
    var storyboardDiagnosticTitle: String {
        switch self {
        case .walk:
            return "идёт"
        case .lookAt:
            return "смотрит"
        case .pickUp:
            return "берёт"
        case .give:
            return "передаёт"
        default:
            return rawValue
        }
    }
}
