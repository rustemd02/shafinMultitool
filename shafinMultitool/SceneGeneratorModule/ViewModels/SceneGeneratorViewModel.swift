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

struct StoryboardBeatInspectorPresentation: Equatable {
    let kindTitle: String
    let summary: String
    let durationText: String
    let actorLabels: [String]
    let targetLabels: [String]
    let warnings: [String]
    let dragHint: String
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

/// ViewModel для управления генерацией AR сцены из текстового описания
@MainActor
final class SceneGeneratorViewModel: ObservableObject {
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
    
    /// Статус генерации
    @Published var isGenerating: Bool = false
    
    /// Статус воспроизведения анимации
    @Published var isPlaying: Bool = false

    /// Активный режим unified workspace
    @Published private(set) var workspaceMode: SceneWorkspaceMode = .editingScene

    /// Идёт ли запись видео
    @Published var isRecording: Bool = false

    /// Включены ли live hints
    @Published var isHintsEnabled: Bool = false

    /// Длительность текущей записи
    @Published var recordingElapsedTime: TimeInterval = 0

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

    /// Короткая подсказка/ошибка ручного перемещения актёра для открытого такта.
    @Published var storyboardDragFeedback: String?

    private var generationLogCounter = 0
    private var playbackLogCounter = 0
    private var currentPlaybackLogID: String?
    private var lastLoggedPlaybackBeatIndex: Int?
    private var hintPauseRequestToken: UUID?
    
    /// Статус AR сессии
    @Published var isARSessionReady: Bool = false
    
    /// Текст ошибки
    @Published var errorMessage: String?
    
    /// Показать sheet ввода
    @Published var showInputSheet: Bool = false
    
    /// Показать popup для ввода имени маркера
    @Published var showMarkerNameInput: Bool = false
    
    /// Позиция для нового маркера (временная)
    @Published var pendingMarkerPosition: Position3D?
    
    /// Режим разметки объектов
    @Published var isMarkingMode: Bool = false
    
    /// Статус загрузки
    @Published var statusMessage: String = "Наведите камеру на поверхность"
    
    // MARK: - Services
    
    private let parserService = SceneParserService.shared
    private let plannerService = SpatialPlannerService.shared
    private let cameraService = CameraService.shared
    private let projectStore: DBService
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
    private var recorderPrepared = false
    private var hasRestoredPersistedEntities = false
    private var hasAutoPromptedDescription = false
    private var currentProject: UnifiedSceneProject
    private var lastHighHintTimestamp: TimeInterval = 0
    private var lastMediumHintTimestamp: TimeInterval = 0
    private var lastLowHintTimestamp: TimeInterval = 0
    private var arInterfaceOrientation: UIInterfaceOrientation = .portrait
    private var hintFrameDebugCounter = 0
    private var lastHintFrameDebugLogTimestamp: TimeInterval = 0
    private let objectDemoDetrHintFrameInterval: TimeInterval = 1.2
    private let lidarDepthMarkingEnabledDefaultsKey = "scene_generator_lidar_marking_enabled"
    
    // MARK: - Cancellables
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(projectName: String = "Новая сцена",
         isNewProject: Bool = true,
         projectStore: DBService = .shared) {
        self.projectStore = projectStore
        let loadedProject = isNewProject ? nil : projectStore.loadUnifiedSceneProject(named: projectName)
        if let loadedProject {
            self.currentProject = loadedProject.0
            self.initialWorldMap = loadedProject.1
        } else {
            self.currentProject = UnifiedSceneProject(name: projectName)
            self.initialWorldMap = nil
        }
        self.sceneTitle = currentProject.name
        self.sceneDescription = currentProject.sceneDescription
        self.markedObjects = currentProject.markedObjects
        self.parsedScript = currentProject.parsedScript
        self.plannedScene = currentProject.plannedScene
        self.sceneChunkState = currentProject.sceneChunkState
        self.visualOverlays = currentProject.visualOverlays
        setupBindings()
        refreshStoryboardBeatItems()
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
    }
    
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
            .sink { [weak self] _ in
                self?.sceneChunkState = nil
                self?.refreshIdleStatusMessage()
                self?.persistProjectMetadata()
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
                self?.liveHint = hint
            }
            .store(in: &cancellables)

        analysisPipeline.$currentOverlayAnnotations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] annotations in
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
    func updateARPresentationFrame(cameraTransform: simd_float4x4, timestamp: TimeInterval) {
        if timestamp < lastPresentationFrameTimestamp {
            guard lastPresentationFrameTimestamp - timestamp > 2 else { return }
        }
        lastPresentationFrameTimestamp = timestamp
        currentCameraTransform = cameraTransform
        updateBillboardEntities(cameraTransform: cameraTransform)
        if !isMarkerNameInputActive {
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
        displayTransform: CGAffineTransform? = nil
    ) {
        currentCameraTransform = cameraTransform
        if let interfaceOrientation, interfaceOrientation != .unknown {
            arInterfaceOrientation = interfaceOrientation
        }
        if let displayTransform {
            hintDisplayTransform = displayTransform
        }
        
        // Обновляем плоскости с ограничением частоты, чтобы не перегружать main thread.
        if timestamp - lastPlaneUpdateTimestamp >= planeRefreshInterval || detectedPlanes.isEmpty {
            detectedPlanes = planeSnapshots
            lastPlaneUpdateTimestamp = timestamp
        }
        
        // Проверяем готовность AR сессии
        if !isARSessionReady && !detectedPlanes.isEmpty {
            isARSessionReady = true
            refreshIdleStatusMessage()
        }
        
        if let capturedImage {
            if isRecording {
                cameraService.appendCapturedPixelBuffer(capturedImage, at: timestamp)
            }
            processHintFrameIfNeeded(pixelBuffer: capturedImage, timestamp: timestamp)
        }

        updateARPresentationFrame(cameraTransform: cameraTransform, timestamp: timestamp)
        
        // DETR детекция отключена - используем только ручную разметку и LiDAR
    }

    /// Backward-compatible обёртка для существующих call-sites.
    func processARFrame(_ frame: ARFrame) {
        processARFrameSnapshot(
            cameraTransform: frame.camera.transform,
            planeSnapshots: frame.anchors.compactMap { ($0 as? ARPlaneAnchor).map(ScenePlaneSnapshot.init(anchor:)) },
            timestamp: frame.timestamp,
            capturedImage: nil
        )
    }

    func prepareWorkspace() {
        prepareWorkspaceIfNeeded()
    }

    func persistWorkspaceState() {
        Task { await persistProjectSnapshot() }
    }

    func attachARView(_ arView: ARView) {
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

    func makeSessionConfiguration(depthEnabled: Bool) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .none

        if let initialWorldMap {
            configuration.initialWorldMap = initialWorldMap
        }

        if depthEnabled && UserDefaults.standard.bool(forKey: lidarDepthMarkingEnabledDefaultsKey) {
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
        }

        return configuration
    }

    /// Генерирует сцену из текстового описания
    func generateScene() async {
        guard !sceneDescription.isEmpty else {
            errorMessage = "Введите описание сцены"
            return
        }
        
        guard isARSessionReady else {
            errorMessage = "AR сессия не готова. Наведите камеру на поверхность."
            return
        }
        
        guard let cameraTransform = currentCameraTransform else {
            errorMessage = "Не удалось получить позицию камеры"
            return
        }

        generationLogCounter += 1
        let generationID = "generation_\(generationLogCounter)"
        
        isGenerating = true
        errorMessage = nil
        statusMessage = "Анализирую описание..."
        isPlaying = false
        activeStoryboardEditDraft = nil
        storyboardDragFeedback = nil
        cancelAllAnimations()
        resetPlaybackUIState(clearTimeline: true)
        removePlacedSceneEntities(reason: "generation_start \(generationID)")
        plannedScene = nil
        beatTimelineItems = []
        storyboardBeatItems = []
        
        // Логирование входных данных
        print("🔍 [VIEWMODEL][\(generationID)] === НАЧАЛО ГЕНЕРАЦИИ СЦЕНЫ ===")
        SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] start descriptionChars=\(sceneDescription.count), markedObjects=\(markedObjects.count)")
        print("🔍 [VIEWMODEL] Описание: '\(sceneDescription)'")
        print("🔍 [VIEWMODEL] Размеченных объектов: \(markedObjects.count)")
        for (index, marker) in markedObjects.enumerated() {
            print("🔍 [VIEWMODEL]   MarkedObject[\(index)]: name='\(marker.name)', type=\(marker.type.rawValue), id=\(marker.id.uuidString.prefix(8))")
        }
        
        // 1. Парсим описание с учётом markedObjects (async — поддержка LLM fallback)
        print("🔍 [VIEWMODEL] Вызов parserService.parseAsync()...")
        statusMessage = "Анализирую текст..."
        let result = await parserService.parseAsync(sceneDescription, markedObjects: markedObjects)
        parserService.releaseLocalModelResources(reason: "scene_generation_parse_complete")
        SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] parser finished and LLM resources requested for release")
        let script = result.script
        let runtimeTrace = parserService.lastRuntimeTrace
        
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
        
        parsedScript = script
        parsingResult = result
        sceneChunkState = parserService.lastChunkState
        visualOverlays = parserService.lastBundleResult?.visualOverlays ?? []
        if let runtimeTrace {
            print("🔍 [VIEWMODEL]   Runtime route: \(runtimeTrace.route.rawValue)")
            print("🔍 [VIEWMODEL]   Runtime reasons: \(runtimeTrace.reasons.joined(separator: ","))")
        }

        // Отображаем диагностику в статусе
        if runtimeTrace?.route == .needsClarification, let clarification = parserService.clarificationMessage(for: runtimeTrace) {
            statusMessage = "Нужно уточнение"
            errorMessage = clarification
        } else if runtimeTrace?.route == .offloadRemote {
            statusMessage = "Нужен более сильный парсер, использую fallback"
        } else if result.diagnostics.confidence < 0.6 {
            statusMessage = "Низкая уверенность парсинга (\(Int(result.diagnostics.confidence * 100))%)"
            if !result.diagnostics.notes.isEmpty {
                errorMessage = result.diagnostics.notes.joined(separator: "; ")
            }
        } else {
            statusMessage = "Парсинг выполнен (\(Int(result.diagnostics.confidence * 100))%)"
        }
        
        if script.isEmpty {
            errorMessage = "Не удалось распознать описание сцены"
            isGenerating = false
            SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] failed empty script")
            SceneGeneratorDiagnosticsLogger.shared.flush()
            return
        }
        
        statusMessage = "Планирую размещение..."
        
        // 2. Сопоставляем объекты с размеченными (приоритет) и детекциями
        // Объекты из markedObjects уже включены в script.objects с detectedPosition
        print("🔍 [VIEWMODEL] Сопоставление объектов с markedObjects и детекциями...")
        print("🔍 [VIEWMODEL]   До сопоставления: objects.count=\(script.objects.count)")
        let matchedObjects = matchObjectsWithMarkedAndDetected(script.objects)
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
            detectedObjects: detectedObjects,
            availablePlanes: detectedPlanes,
            markedObjects: markedObjects
        )
        
        print("🔍 [VIEWMODEL] Результат планирования:")
        print("🔍 [VIEWMODEL]   PlacedActors: \(planned.placedActors.count)")
        for (index, actor) in planned.placedActors.enumerated() {
            print("🔍 [VIEWMODEL]     PlacedActor[\(index)]: id='\(actor.id)', actorId='\(actor.actorId)', type=\(actor.type.rawValue), name='\(actor.name ?? "nil")', label='\(displayName(for: actor))', path.count=\(actor.path.count)")
        }
        print("🔍 [VIEWMODEL]   PlacedObjects: \(planned.placedObjects.count)")
        for (index, object) in planned.placedObjects.enumerated() {
            print("🔍 [VIEWMODEL]     PlacedObject[\(index)]: id='\(object.id)', objectId='\(object.objectId)', type=\(object.type.rawValue), isRealWorld=\(object.isRealWorld), placementSource=\(object.placementSource.rawValue)")
        }
        logPlannedSceneDetails(planned, script: updatedScript, generationID: generationID)
        
        parsedScript = updatedScript
        plannedScene = planned
        refreshStoryboardBeatItems()
        beatTimelineItems = buildBeatTimelineItems(for: planned, script: updatedScript)
        
        statusMessage = "Размещаю объекты..."
        
        // 4. Создаём 3D объекты в AR
        await placeObjectsInAR(planned)

        isGenerating = false
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
        persistProjectMetadata()
        SceneGeneratorDiagnosticsLogger.shared.log("[GENERATION][\(generationID)] complete actors=\(planned.placedActors.count), objects=\(planned.placedObjects.count)")
        SceneGeneratorDiagnosticsLogger.shared.flush()

        // Закрываем sheet
        showInputSheet = false
    }
    
    /// Запускает воспроизведение анимации
    func playScene() {
        guard let planned = plannedScene else {
            errorMessage = "Сначала создайте сцену"
            diagnosticsLog("🎬 [PLAYBACK] playScene rejected: plannedScene=nil")
            return
        }
        
        guard !isPlaying else {
            diagnosticsLog("🎬 [PLAYBACK] playScene ignored: already playing id=\(currentPlaybackLogID ?? "nil")")
            return
        }

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
        currentPlaybackLogID = playbackID
        lastLoggedPlaybackBeatIndex = nil
        
        beatTimelineItems = buildBeatTimelineItems(for: planned, script: parsedScript)
        logPlaybackPlan(planned, timeline: beatTimelineItems, playbackID: playbackID)
        SceneGeneratorDiagnosticsLogger.shared.flush()
        isPlaying = true
        resetPlaybackUIState(clearTimeline: false)
        refreshWorkspaceMode()
        statusMessage = "Воспроизведение..."
        
        // Инициализируем счётчики анимаций
        completedActorAnimations = 0
        totalActorAnimations = planned.placedActors.filter { $0.path.count > 1 }.count
        if totalActorAnimations == 0 {
            diagnosticsLog("🎬 [PLAYBACK][\(playbackID)] no animated actors: actors=\(planned.placedActors.count)")
            isPlaying = false
            statusMessage = "Нет анимируемых действий"
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
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
        Task { await persistProjectSnapshot() }
    }
    
    /// Показывает sheet ввода
    func showInput() {
        showInputSheet = true
    }
    
    // MARK: - Object Marking
    
    /// Включает/выключает режим разметки
    func toggleMarkingMode() {
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
            statusMessage = "Не удалось отметить объект. Наведите камеру на поверхность и попробуйте ещё раз."
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
            errorMessage = "Введите название объекта"
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
    
    private func placeObjectsInAR(_ planned: PlannedScene) async {
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
        let safeText = trimmed.isEmpty ? "Объект" : trimmed
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
        objectLabelItems = []
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
            objectLabelItems = []
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

        objectLabelItems = Self.layoutObjectLabels(rawLabels, canvasSize: arView.bounds.size)
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
        let dragHint = storyboardDragFeedback ?? "Удерживайте модель актёра в AR, чтобы переместить её в этом такте"

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

    func openStoryboardEditor(for beatID: String) {
        guard let draft = makeStoryboardEditDraft(for: beatID) else {
            errorMessage = "Не удалось открыть такт для редактирования"
            return
        }
        activeStoryboardEditDraft = draft
        storyboardDragFeedback = nil
        diagnosticsLog("[STORYBOARD_EDIT] open beat=\(beatID), actions=\(draft.actions.count)")
    }

    func cancelStoryboardEditor() {
        cancelActiveStoryboardActorDrag()
        activeStoryboardEditDraft = nil
        storyboardDragFeedback = nil
    }

    func applyStoryboardBeatEdit(_ draft: StoryboardBeatEditDraft) async -> Bool {
        guard let script = parsedScript,
              let beatIndex = script.beats.firstIndex(where: { $0.id == draft.beatID })
        else {
            errorMessage = "Такт больше не найден"
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
        guard let script = parsedScript,
              let index = script.beats.firstIndex(where: { $0.id == beatID })
        else {
            errorMessage = "Такт больше не найден"
            return false
        }
        guard script.beats.count > 1 else {
            errorMessage = "Нельзя удалить единственный такт"
            return false
        }

        var beats = script.beats
        beats.remove(at: index)
        diagnosticsLog("[STORYBOARD_EDIT] delete beat=\(beatID)")
        return await applyManualStoryboardScriptEdit(beats: beats, reason: "delete_beat")
    }

    func moveStoryboardBeat(beatID: String, offset: Int) async -> Bool {
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
        let targetOptions = [StoryboardEntityOption(id: "none", label: "Нет цели", kind: .none)] +
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
            title: "Такт \(script.beats.firstIndex(where: { $0.id == beat.id }).map { $0 + 1 } ?? 1)",
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
        return "Пустой такт"
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
                warnings.append("\(action.type.storyboardDiagnosticTitle): нет цели")
            }
            if (action.type == .talk || action.type == .describedAction),
               action.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append("\(actorLabelByID[action.actorId] ?? action.actorId): пустой текст")
            }
        }

        for actorID in Set(actions.map(\.actorId)).sorted()
        where !storyboardActorParticipatesInPlannedBeat(actorID: actorID, beatID: draft.beatID) {
            warnings.append("\(actorLabelByID[actorID] ?? actorID): нет точки в такте")
        }

        if let storyboardDragFeedback,
           !storyboardDragFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           storyboardDragFeedback.hasPrefix("Не") || storyboardDragFeedback.hasPrefix("Нельзя") {
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
            errorMessage = "Не удалось получить текущую AR-позицию для перепланирования"
            return false
        }

        if isPlaying {
            stopScene()
        } else {
            cancelAllAnimations()
            resetPlaybackUIState(clearTimeline: true)
        }

        let editedScript = SceneScript(
            sceneHeading: script.sceneHeading,
            locationName: script.locationName,
            interiorExterior: script.interiorExterior,
            timeOfDay: script.timeOfDay,
            actors: script.actors,
            objects: matchObjectsWithMarkedAndDetected(script.objects),
            beats: beats,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )
        let planned = plannerService.planScene(
            script: editedScript,
            cameraTransform: cameraTransform,
            detectedObjects: detectedObjects,
            availablePlanes: detectedPlanes,
            markedObjects: markedObjects
        )

        parsedScript = editedScript
        if let parsingResult {
            self.parsingResult = ParsingResult(script: editedScript, diagnostics: parsingResult.diagnostics)
        }
        plannedScene = planned
        await placeObjectsInAR(planned)
        beatTimelineItems = buildBeatTimelineItems(for: planned, script: editedScript)
        refreshStoryboardBeatItems()
        activeStoryboardEditDraft = nil
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
        persistProjectMetadata()
        diagnosticsLog("[STORYBOARD_EDIT] replan complete reason=\(reason), beats=\(editedScript.beats.count), visible=\(storyboardBeatItems.count), actors=\(planned.placedActors.count), objects=\(planned.placedObjects.count)")
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
            storyboardDragFeedback = "Нельзя переместить актёра: такт не открыт"
            diagnosticsLog("[STORYBOARD_EDIT] actor drag rejected: beat not active actor=\(actorID), beat=\(beatID)")
            return false
        }
        guard !isPlaying, !isGenerating, !isRecording else {
            storyboardDragFeedback = "Нельзя перемещать во время воспроизведения или записи"
            diagnosticsLog("[STORYBOARD_EDIT] actor drag rejected: busy actor=\(actorID), beat=\(beatID)")
            return false
        }
        guard let plannedScene,
              let actorIndex = plannedScene.placedActors.firstIndex(where: { $0.actorId == actorID || $0.id == actorID })
        else {
            storyboardDragFeedback = "Не найден актёр для перемещения"
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
            storyboardDragFeedback = "\(displayName(for: actor)) не участвует в этом такте"
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
        storyboardDragFeedback = "\(displayName(for: actor)) перемещён в \(activeStoryboardEditDraft?.title.lowercased() ?? "такте")"
        diagnosticsLog("[STORYBOARD_EDIT] actor drag committed actor=\(displayName(for: actor)), beat=\(beatID), points=\(changedPoints), position=\(formatPosition(position))")
        SceneGeneratorDiagnosticsLogger.shared.flush()
        return true
    }

    @discardableResult
    func commitStoryboardActorTrackDrag(actorID: String, from originalPosition: SIMD3<Float>, to position: Position3D) -> Bool {
        guard !isPlaying, !isGenerating, !isRecording else {
            storyboardDragFeedback = "Нельзя перемещать во время воспроизведения или записи"
            diagnosticsLog("[STORYBOARD_EDIT] actor track drag rejected: busy actor=\(actorID)")
            return false
        }
        guard let plannedScene,
              let actorIndex = plannedScene.placedActors.firstIndex(where: { $0.actorId == actorID || $0.id == actorID })
        else {
            storyboardDragFeedback = "Не найден актёр для перемещения"
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
        storyboardDragFeedback = "\(displayName(for: actor)) перемещён"
        diagnosticsLog("[STORYBOARD_EDIT] actor track drag committed actor=\(displayName(for: actor)), delta=(\(formatFloat(deltaX)), \(formatFloat(deltaZ))), position=\(formatPosition(position))")
        SceneGeneratorDiagnosticsLogger.shared.flush()
        return true
    }

    private func beginStoryboardActorDrag(at screenPoint: CGPoint) {
        diagnosticsLog("[STORYBOARD_EDIT] actor drag begin requested point=(\(formatFloat(Float(screenPoint.x))), \(formatFloat(Float(screenPoint.y))))")
        guard !isPlaying, !isGenerating, !isRecording else {
            storyboardDragFeedback = "Нельзя перемещать во время воспроизведения или записи"
            diagnosticsLog("[STORYBOARD_EDIT] actor drag begin rejected: busy")
            return
        }
        guard arView != nil else {
            storyboardDragFeedback = "AR-сцена ещё не готова"
            diagnosticsLog("[STORYBOARD_EDIT] actor drag begin rejected: no arView")
            return
        }
        let beatID = activeStoryboardEditDraft?.beatID
        guard let actor = storyboardActorHit(at: screenPoint, beatID: beatID)
        else {
            storyboardDragFeedback = "Удерживайте именно модель актёра"
            diagnosticsLog("[STORYBOARD_EDIT] actor drag begin rejected: actor hit missing beat=\(beatID ?? "global"), point=(\(formatFloat(Float(screenPoint.x))), \(formatFloat(Float(screenPoint.y))))")
            return
        }
        if let beatID {
            guard actor.pathBeatIDs.contains(beatID) else {
                storyboardDragFeedback = "\(displayName(for: actor)) не участвует в этом такте"
                diagnosticsLog("[STORYBOARD_EDIT] actor drag begin rejected: no beat point actor=\(displayName(for: actor)), beat=\(beatID)")
                return
            }
        }
        guard let entity = placedEntities[actor.id],
              let position = storyboardActorDragPosition(at: screenPoint, for: actor, beatID: beatID)
        else {
            storyboardDragFeedback = "Не удалось найти поверхность для перемещения"
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
            ? "Перемещаю \(displayName(for: actor))"
            : "Перемещаю \(displayName(for: actor)) в \(activeStoryboardEditDraft?.title.lowercased() ?? "такте")"
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
            storyboardDragFeedback = "Перемещение отменено"
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
            errorMessage = "У действия должен быть актёр"
            return false
        }
        if draft.type == .give {
            guard let target = draft.target, target != "none", !target.isEmpty else {
                errorMessage = "Для передачи нужна цель"
                return false
            }
            guard target != draft.actorId else {
                errorMessage = "Нельзя передать объект самому себе"
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
        return "Пустой такт"
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
            return "Актёр \(suffix)"
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
            return "Стол"
        case .phone:
            return "Телефон"
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
            return "Актёр \(suffix)"
        }
        return "Актёр"
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
    
    /// Сопоставляет объекты скрипта с размеченными и обнаруженными объектами
    /// Приоритет: 1) Размеченные объекты, 2) Детекции, 3) Виртуальные
    private func matchObjectsWithMarkedAndDetected(_ scriptObjects: [SceneObject]) -> [SceneObject] {
        var unusedMarkers = markedObjects
        
        return scriptObjects.map { scriptObject in
            var updatedObject = scriptObject
            
            // 1. Сначала ищем среди размеченных объектов (высший приоритет)
            if let markerIndex = indexOfMatchingMarker(for: scriptObject, in: unusedMarkers) {
                let marker = unusedMarkers.remove(at: markerIndex)
                updatedObject.detectedPosition = marker.worldPosition
                return updatedObject
            }
            
            // 2. Затем ищем в детекциях
            if let detection = detectionBridge?.findObject(ofType: scriptObject.type),
               let worldPosition = detection.worldPosition {
                updatedObject.detectedPosition = worldPosition
                return updatedObject
            }
            
            // 3. Если не найдено - остаётся виртуальным
            return updatedObject
        }
    }

    private func indexOfMatchingMarker(for scriptObject: SceneObject, in markers: [MarkedObject]) -> Int? {
        if let markedShortID = scriptObject.markedObjectShortID,
           let exactIndex = markers.firstIndex(where: { $0.id.uuidString.prefix(8).lowercased() == markedShortID.lowercased() }) {
            return exactIndex
        }

        let sameTypeIndices = markers.indices.filter { markers[$0].type == scriptObject.type }
        if sameTypeIndices.count == 1 {
            return sameTypeIndices.first
        }

        return nil
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
        guard !isHintPauseAnalysisActive else { return }

        isHintPauseAnalysisActive = true
        let requestToken = UUID()
        hintPauseRequestToken = requestToken
        hintPreviewSuggestions = []
        hintPauseCritique = nil
        print("[CA_DEBUG][PAUSE_START] token=\(requestToken.uuidString) liveHint=\(liveHint?.text ?? "nil") overlayBBox=\(formatDebugRect(coachingOverlayState.primaryBoundingBox))")
        analysisPipeline.clearLivePresentationState()

        analysisPipeline.runPauseAnalysis { [weak self] suggestions, critique in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.isHintPauseAnalysisActive,
                      self.hintPauseRequestToken == requestToken else { return }
                self.hintPreviewSuggestions = suggestions
                self.hintPauseCritique = critique
                let critiqueText = critique.map {
                    "verdict=\($0.verdict.rawValue) confidence=\(self.formatDebugDouble($0.verdictConfidence)) short=\($0.shortVerdict)"
                } ?? "nil"
                print("[CA_DEBUG][PAUSE_RESULT] token=\(requestToken.uuidString) suggestions=\(suggestions.count) critique=\(critiqueText)")
            }
        }
    }

    func resumeHintLiveAnalysis() {
        guard isHintPauseAnalysisActive else { return }

        isHintPauseAnalysisActive = false
        hintPauseRequestToken = nil
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
            debugSignals: makeHintDecisionDebugSignals()
        )
    }

    func startRecording() {
        guard plannedScene != nil else {
            errorMessage = "Сначала создайте сцену"
            return
        }

        guard !isRecording else { return }

        if !recorderPrepared {
            cameraService.prepareRecorder()
            recorderPrepared = cameraService.isRecorderPrepared
        }

        guard recorderPrepared else {
            errorMessage = "Не удалось подготовить запись"
            return
        }

        prepareWorkspaceIfNeeded()
        if isPlaying {
            stopScene()
        }

        isHintsEnabled = true
        cameraService.startRecording()
        isRecording = true
        recordingElapsedTime = 0
        recordingStartDate = Date()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let recordingStartDate = self.recordingStartDate else { return }
                self.recordingElapsedTime = Date().timeIntervalSince(recordingStartDate)
            }
        }
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
    }

    func stopRecording() {
        guard isRecording else { return }

        cameraService.stopRecording()
        recorderPrepared = cameraService.isRecorderPrepared
        isRecording = false
        if let recordingStartDate {
            recordingElapsedTime = Date().timeIntervalSince(recordingStartDate)
        }
        recordingStartDate = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        refreshWorkspaceMode()
        refreshIdleStatusMessage()
        Task { await persistProjectSnapshot() }
    }

    private func processHintFrameIfNeeded(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        guard isHintsEnabled else {
            if liveHint != nil || hintPauseCritique != nil || !hintPreviewSuggestions.isEmpty || !coachingOverlayAnnotations.isEmpty {
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
        isHintPauseAnalysisActive = false
        hintPauseRequestToken = nil
        hintPreviewSuggestions = []
        hintPauseCritique = nil
        analysisPipeline.clearLivePresentationState()
        analysisPipeline.clearPausePresentationState()
        coachingOverlayState = .init(primaryBoundingBox: nil,
                                     horizonAngle: 0,
                                     horizonConfidence: 0,
                                     saliencyBalance: 0)
        hintDisplayTransform = nil
        liveHint = nil
        coachingOverlayAnnotations = []
    }

    private func persistProjectMetadata() {
        currentProject = buildCurrentProject()
        do {
            try projectStore.saveUnifiedSceneProject(currentProject, worldMap: initialWorldMap)
        } catch {
            print("Error saving unified scene metadata: \(error)")
        }
    }

    private func persistProjectSnapshot() async {
        currentProject = buildCurrentProject()
        let worldMap = await captureCurrentWorldMap() ?? initialWorldMap
        if let worldMap {
            initialWorldMap = worldMap
        }

        do {
            try projectStore.saveUnifiedSceneProject(currentProject, worldMap: worldMap)
        } catch {
            print("Error saving unified scene snapshot: \(error)")
        }
    }

    private func captureCurrentWorldMap() async -> ARWorldMap? {
        guard let arView else { return initialWorldMap }
        return await withCheckedContinuation { continuation in
            arView.session.getCurrentWorldMap { worldMap, error in
                if let error {
                    print("Error capturing current world map: \(error)")
                }
                continuation.resume(returning: worldMap)
            }
        }
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
                await placeObjectsInAR(plannedScene)
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
            if !isARSessionReady {
                statusMessage = "Наведите камеру на поверхность"
            } else if sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                statusMessage = "Добавьте описание сцены"
            } else {
                statusMessage = "Можно разметить сцену или запустить генерацию"
            }
        case .marking:
            statusMessage = "Тапните по объекту, который хотите отметить"
        case .generatedReady:
            statusMessage = "Сцена готова. Можно открыть превью или начать запись"
        case .shooting:
            statusMessage = "AR-сцена готова к съёмке, подсказки включены"
        case .recording:
            statusMessage = "Идёт запись, подсказки включены автоматически"
        case .previewPlayback:
            statusMessage = "Предпросмотр сцены"
        }
    }
}

#if DEBUG
extension SceneGeneratorViewModel {
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
