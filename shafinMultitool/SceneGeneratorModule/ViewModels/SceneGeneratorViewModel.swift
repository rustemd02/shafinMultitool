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

/// ViewModel для управления генерацией AR сцены из текстового описания
@MainActor
final class SceneGeneratorViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Текущее описание сцены
    @Published var sceneDescription: String = ""
    
    /// Распознанный скрипт сцены
    @Published var parsedScript: SceneScript?
    
    /// Результат парсинга с диагностикой
    @Published var parsingResult: ParsingResult?
    
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
    private let detectionBridge = ObjectDetectionBridge.shared
    private let plannerService = SpatialPlannerService.shared
    
    // MARK: - AR Properties
    
    /// Ссылка на ARView (устанавливается из ARSceneContainer)
    weak var arView: ARView?
    
    /// Текущая трансформация камеры
    private var currentCameraTransform: simd_float4x4?
    
    /// Текущий AR frame (для доступа к depth data)
    private var currentARFrame: ARFrame?
    
    /// Обнаруженные плоскости
    private var detectedPlanes: [ARPlaneAnchor] = []
    
    /// Размещённые entity
    private var placedEntities: [String: ModelEntity] = [:]
    
    /// Anchor для всей сцены
    private var sceneAnchor: AnchorEntity?
    
    /// Entity для маркеров объектов
    private var markerEntities: [UUID: ModelEntity] = [:]
    
    /// Anchor для маркеров (сохраняется отдельно от сцены)
    private var markersAnchor: AnchorEntity?
    
    /// Work items для анимаций (для отмены)
    private var animationWorkItems: [DispatchWorkItem] = []
    
    // MARK: - Cancellables
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        // Автоматическое обновление статуса при изменении размеченных объектов
        $markedObjects
            .map { markers in
                if markers.isEmpty {
                    return "Нажмите 📍 чтобы разметить объекты"
                } else {
                    let names = markers.prefix(3).map { $0.name.capitalized }
                    return "Размечено: \(names.joined(separator: ", "))"
                }
            }
            .assign(to: &$statusMessage)
    }
    
    // MARK: - Public API
    
    /// Обрабатывает AR frame
    func processARFrame(_ frame: ARFrame) {
        currentCameraTransform = frame.camera.transform
        currentARFrame = frame
        
        // Обновляем плоскости
        detectedPlanes = frame.anchors.compactMap { $0 as? ARPlaneAnchor }
        
        // Проверяем готовность AR сессии
        if !isARSessionReady && !detectedPlanes.isEmpty {
            isARSessionReady = true
            statusMessage = "AR готов. Нажмите + для ввода описания"
        }
        
        // DETR детекция отключена - используем только ручную разметку и LiDAR
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
        
        isGenerating = true
        errorMessage = nil
        statusMessage = "Анализирую описание..."
        
        // Логирование входных данных
        print("🔍 [VIEWMODEL] === НАЧАЛО ГЕНЕРАЦИИ СЦЕНЫ ===")
        print("🔍 [VIEWMODEL] Описание: '\(sceneDescription)'")
        print("🔍 [VIEWMODEL] Размеченных объектов: \(markedObjects.count)")
        for (index, marker) in markedObjects.enumerated() {
            print("🔍 [VIEWMODEL]   MarkedObject[\(index)]: name='\(marker.name)', type=\(marker.type.rawValue), id=\(marker.id.uuidString.prefix(8))")
        }
        
        // 1. Парсим описание с учётом markedObjects (async — поддержка LLM fallback)
        print("🔍 [VIEWMODEL] Вызов parserService.parseAsync()...")
        statusMessage = "Анализирую текст..."
        let result = await parserService.parseAsync(sceneDescription, markedObjects: markedObjects)
        let script = result.script
        
        print("🔍 [VIEWMODEL] Результат парсинга:")
        print("🔍 [VIEWMODEL]   Actors: \(script.actors.count)")
        for (index, actor) in script.actors.enumerated() {
            print("🔍 [VIEWMODEL]     Actor[\(index)]: id='\(actor.id)', type=\(actor.type.rawValue)")
        }
        print("🔍 [VIEWMODEL]   Objects: \(script.objects.count)")
        for (index, object) in script.objects.enumerated() {
            print("🔍 [VIEWMODEL]     Object[\(index)]: id='\(object.id)', type=\(object.type.rawValue), detectedPosition=\(object.detectedPosition != nil ? "YES" : "NO")")
        }
        print("🔍 [VIEWMODEL]   Actions: \(script.actions.count)")
        for (index, action) in script.actions.enumerated() {
            print("🔍 [VIEWMODEL]     Action[\(index)]: id='\(action.id)', actorId='\(action.actorId)', type=\(action.type.rawValue), target=\(action.target ?? "nil")")
        }
        print("🔍 [VIEWMODEL]   Confidence: \(result.diagnostics.confidence)")
        print("🔍 [VIEWMODEL]   Matched markedObjects: \(result.diagnostics.matchedMarkedObjects.count)")
        
        parsedScript = script
        parsingResult = result
        
        // Отображаем диагностику в статусе
        if result.diagnostics.confidence < 0.6 {
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
            actors: script.actors,
            objects: matchedObjects,
            actions: script.actions,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )
        
        // 3. Планируем размещение с учётом размеченных объектов
        print("🔍 [VIEWMODEL] Планирование размещения...")
        print("🔍 [VIEWMODEL]   Script для планирования: actors=\(updatedScript.actors.count), objects=\(updatedScript.objects.count), actions=\(updatedScript.actions.count)")
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
            print("🔍 [VIEWMODEL]     PlacedActor[\(index)]: id='\(actor.id)', actorId='\(actor.actorId)', type=\(actor.type.rawValue), path.count=\(actor.path.count)")
        }
        print("🔍 [VIEWMODEL]   PlacedObjects: \(planned.placedObjects.count)")
        for (index, object) in planned.placedObjects.enumerated() {
            print("🔍 [VIEWMODEL]     PlacedObject[\(index)]: id='\(object.id)', objectId='\(object.objectId)', type=\(object.type.rawValue), isRealWorld=\(object.isRealWorld), placementSource=\(object.placementSource.rawValue)")
        }
        
        plannedScene = planned
        
        statusMessage = "Размещаю объекты..."
        
        // 4. Создаём 3D объекты в AR
        await placeObjectsInAR(planned)
        
        isGenerating = false
        statusMessage = "Сцена создана! Нажмите ▶️ для воспроизведения"
        
        // Закрываем sheet
        showInputSheet = false
    }
    
    /// Запускает воспроизведение анимации
    func playScene() {
        guard let planned = plannedScene else {
            errorMessage = "Сначала создайте сцену"
            return
        }
        
        guard !isPlaying else { return }
        
        // Отменяем все предыдущие анимации
        cancelAllAnimations()
        
        isPlaying = true
        statusMessage = "Воспроизведение..."
        
        // Инициализируем счётчики анимаций
        completedActorAnimations = 0
        totalActorAnimations = planned.placedActors.filter { $0.path.count > 1 }.count
        
        // Мгновенно устанавливаем актёров на начальные позиции (без анимации)
        setActorsToInitialPositionsInstantly()
        
        // Небольшая задержка чтобы позиции успели примениться
        let startWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPlaying else { return }
            
            // Анимируем каждого актёра по его траектории
            for actor in planned.placedActors {
                self.animateActor(actor)
            }
        }
        animationWorkItems.append(startWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: startWorkItem)
    }
    
    /// Останавливает воспроизведение
    func stopScene() {
        // Отменяем все запланированные анимации
        cancelAllAnimations()
        
        isPlaying = false
        statusMessage = "Остановлено"
        
        // Мгновенно возвращаем актёров на начальные позиции
        setActorsToInitialPositionsInstantly()
    }
    
    /// Отменяет все запланированные анимации
    private func cancelAllAnimations() {
        // Отменяем все DispatchWorkItems
        for workItem in animationWorkItems {
            workItem.cancel()
        }
        animationWorkItems.removeAll()
        
        // Сбрасываем счётчики
        completedActorAnimations = 0
        totalActorAnimations = 0
        
        // Останавливаем все текущие RealityKit анимации
        stopAllEntityAnimations()
    }
    
    /// Останавливает все RealityKit анимации, фиксируя текущие позиции
    private func stopAllEntityAnimations() {
        for (_, entity) in placedEntities {
            // Устанавливаем текущую трансформацию как конечную (останавливает анимацию)
            entity.stopAllAnimations()
        }
    }
    
    /// Сбрасывает сцену
    func resetScene() {
        // Отменяем все анимации
        cancelAllAnimations()
        
        // Удаляем все размещённые объекты
        sceneAnchor?.removeFromParent()
        sceneAnchor = nil
        placedEntities.removeAll()
        
        plannedScene = nil
        parsedScript = nil
        sceneDescription = ""
        isPlaying = false
        
        statusMessage = "Сцена очищена"
    }
    
    /// Показывает sheet ввода
    func showInput() {
        showInputSheet = true
    }
    
    // MARK: - Object Marking
    
    /// Включает/выключает режим разметки
    func toggleMarkingMode() {
        isMarkingMode.toggle()
        if isMarkingMode {
            statusMessage = "Режим разметки: тапните на объект"
        } else {
            statusMessage = "Режим разметки выключен"
        }
    }
    
    /// Обрабатывает tap для размещения маркера
    func handleTapForMarker(at screenPoint: CGPoint) {
        guard isMarkingMode, let arView = arView else { return }
        
        // Приоритет 1: Используем LiDAR depth для максимально точного определения позиции
        if let worldPosition = getWorldPositionFromLiDAR(screenPoint: screenPoint, arView: arView) {
            print("🔍 [MARKER] Позиция определена через LiDAR: x=\(worldPosition.x), y=\(worldPosition.y), z=\(worldPosition.z)")
            pendingMarkerPosition = worldPosition
            showMarkerNameInput = true
            return
        }
        
        // Приоритет 2: Используем raycast с более точными настройками
        // Пробуем сначала точные плоскости, затем оценённые
        var results = arView.raycast(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any)
        if results.isEmpty {
            results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        }
        
        guard let firstResult = results.first else {
            statusMessage = "Не удалось определить позицию. Попробуйте ещё раз."
            return
        }
        
        // Используем точную позицию из raycast результата
        let transform = firstResult.worldTransform
        let position = transform.columns.3
        let worldPosition = Position3D(x: position.x, y: position.y, z: position.z)
        
        print("🔍 [MARKER] Позиция определена через raycast: x=\(worldPosition.x), y=\(worldPosition.y), z=\(worldPosition.z)")
        pendingMarkerPosition = worldPosition
        showMarkerNameInput = true
    }
    
    /// Получает 3D позицию в мировых координатах используя LiDAR depth
    private func getWorldPositionFromLiDAR(screenPoint: CGPoint, arView: ARView) -> Position3D? {
        guard let frame = currentARFrame else { return nil }
        
        // Пробуем smoothedSceneDepth (более стабильный) или sceneDepth
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        
        let depthMap = depthData.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Конвертируем screen point в normalized координаты depth map
        let viewSize = arView.bounds.size
        let normalizedX = screenPoint.x / viewSize.width
        let normalizedY = screenPoint.y / viewSize.height
        
        // Учитываем ориентацию устройства для правильного маппинга
        let depthX = Int(normalizedX * CGFloat(width))
        let depthY = Int(normalizedY * CGFloat(height))
        
        guard depthX >= 0, depthX < width, depthY >= 0, depthY < height else { return nil }
        
        // Читаем значение глубины
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let offset = depthY * bytesPerRow + depthX * MemoryLayout<Float32>.size
        let depthPointer = baseAddress.advanced(by: offset).assumingMemoryBound(to: Float32.self)
        let depthValue = depthPointer.pointee
        
        // Проверяем валидность глубины
        guard depthValue > 0 && depthValue < 10.0 else { return nil } // Глубина в разумных пределах
        
        // Конвертируем 2D + depth в 3D мировые координаты
        let camera = frame.camera
        let intrinsics = camera.intrinsics
        let imageResolution = camera.imageResolution
        
        // Конвертируем screen point в image coordinates
        let imageX = Float(normalizedX * imageResolution.width)
        let imageY = Float(normalizedY * imageResolution.height)
        
        // Unproject из image coordinates в camera space
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        
        let cameraX = (imageX - cx) * depthValue / fx
        let cameraY = (imageY - cy) * depthValue / fy
        let cameraZ = -depthValue // Negative because camera looks along -Z
        
        // Transform from camera space to world space
        let cameraPoint = simd_float4(cameraX, cameraY, cameraZ, 1)
        let worldPoint = camera.transform * cameraPoint
        
        return Position3D(x: worldPoint.x, y: worldPoint.y, z: worldPoint.z)
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
        
        statusMessage = "Объект '\(marker.name)' отмечен"
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
        
        cleanupMarkersAnchorIfNeeded()
        statusMessage = "Маркер удалён"
    }
    
    /// Удаляет все маркеры
    func clearAllMarkers() {
        markedObjects.removeAll()
        
        // Удаляем все визуальные маркеры
        for (_, entity) in markerEntities {
            entity.removeFromParent()
        }
        markerEntities.removeAll()
        
        cleanupMarkersAnchorIfNeeded()
        statusMessage = "Все маркеры удалены"
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
        
        // Используем ТОЧНУЮ позицию из marker.worldPosition (без смещений)
        markerEntity.position = marker.worldPosition.simdVector
        
        print("🔍 [MARKER] Размещение маркера '\(marker.name)' в позиции: x=\(marker.worldPosition.x), y=\(marker.worldPosition.y), z=\(marker.worldPosition.z)")
        
        markersAnchor?.addChild(markerEntity)
        markerEntities[marker.id] = markerEntity
    }

    private func cleanupMarkersAnchorIfNeeded() {
        if markerEntities.isEmpty {
            markersAnchor?.removeFromParent()
            markersAnchor = nil
        }
    }
    
    /// Создаёт entity для маркера (отличается от виртуальных объектов)
    private func createMarkerEntity(for marker: MarkedObject) -> ModelEntity {
        // Создаём сферу вместо куба - более отличимый маркер
        let mesh = MeshResource.generateSphere(radius: 0.06)
        
        // Используем яркий цвет с полупрозрачностью для отличия от виртуальных объектов
        let markerColor = marker.markerColor.withAlphaComponent(0.8)
        let material = SimpleMaterial(
            color: markerColor,
            roughness: 0.2,
            isMetallic: true // Металлический блеск для отличия
        )
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.generateCollisionShapes(recursive: true)
        
        // Добавляем подпись сверху (меньше и выше)
        let textMesh = MeshResource.generateText(
            marker.name.capitalized,
            extrusionDepth: 0.003,
            font: .boldSystemFont(ofSize: 0.04)
        )
        let textMaterial = SimpleMaterial(color: .white, roughness: 0.5, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position = simd_float3(-0.04, 0.10, 0)
        
        entity.addChild(textEntity)
        
        // Маркер визуально отличается от виртуальных объектов:
        // - Сфера вместо куба
        // - Металлический блеск
        // - Полупрозрачность
        // - Яркий цвет
        
        return entity
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
        sceneAnchor?.removeFromParent()
        placedEntities.removeAll()
        
        // Создаём anchor для сцены
        let anchor = AnchorEntity(world: .zero)
        sceneAnchor = anchor
        arView.scene.addAnchor(anchor)
        
        var virtualObjectsPlaced = 0
        // Размещаем только виртуальные объекты (реальные не дублируем)
        for object in planned.placedObjects where !object.isRealWorld {
            print("🔍 [VIEWMODEL] Размещаю виртуальный объект: id='\(object.id)', type=\(object.type.rawValue)")
            let entity = createPlaceholderEntity(
                size: object.size,
                color: object.color,
                label: object.type.rawValue
            )
            
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
            print("🔍 [VIEWMODEL] Обработка актёра[\(index)]: id='\(actor.id)', actorId='\(actor.actorId)', type=\(actor.type.rawValue), initialPosition=(\(actor.initialPosition.x), \(actor.initialPosition.y), \(actor.initialPosition.z))")
            let entity = createActorEntity(
                size: actor.size,
                color: actor.color,
                label: actor.name ?? actor.type.rawValue
            )
            
            entity.position = actor.initialPosition.simdVector
            entity.orientation = simd_quatf(angle: actor.initialRotation, axis: [0, 1, 0])
            
            print("🔍 [VIEWMODEL] Создан entity для актёра[\(index)], добавляю в anchor...")
            anchor.addChild(entity)
            placedEntities[actor.id] = entity
            print("🔍 [VIEWMODEL] Актёр[\(index)] добавлен в placedEntities с ключом '\(actor.id)', теперь placedEntities.count=\(placedEntities.count)")
            actorsPlaced += 1
        }
        print("🔍 [VIEWMODEL] Размещено актёров: \(actorsPlaced) из \(planned.placedActors.count)")
        print("🔍 [VIEWMODEL] Всего entities в placedEntities: \(placedEntities.count)")
        print("🔍 [VIEWMODEL] Ключи в placedEntities: \(placedEntities.keys.sorted().joined(separator: ", "))")
        print("🔍 [VIEWMODEL] === РАЗМЕЩЕНИЕ ЗАВЕРШЕНО ===")
    }
    
    private func createPlaceholderEntity(
        size: simd_float3,
        color: (r: Float, g: Float, b: Float),
        label: String
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
        
        // Добавляем подпись
        let textMesh = MeshResource.generateText(
            label,
            extrusionDepth: 0.01,
            font: .boldSystemFont(ofSize: 0.1)
        )
        let textMaterial = SimpleMaterial(color: .white, roughness: 0.5, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position = simd_float3(0, size.y / 2 + 0.15, 0)
        
        entity.addChild(textEntity)
        
        return entity
    }
    
    private func createActorEntity(
        size: simd_float3,
        color: (r: Float, g: Float, b: Float),
        label: String
    ) -> ModelEntity {
        // Для актёров используем капсулу вместо куба
        let mesh = MeshResource.generateBox(
            width: size.x,
            height: size.y,
            depth: size.z,
            cornerRadius: min(size.x, size.z) / 4
        )
        
        let material = SimpleMaterial(
            color: UIColor(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1.0),
            roughness: 0.3,
            isMetallic: false
        )
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.generateCollisionShapes(recursive: true)
        
        // Добавляем подпись
        let textMesh = MeshResource.generateText(
            label,
            extrusionDepth: 0.01,
            font: .boldSystemFont(ofSize: 0.08)
        )
        let textMaterial = SimpleMaterial(color: .white, roughness: 0.5, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position = simd_float3(-0.1, size.y / 2 + 0.1, 0)
        
        entity.addChild(textEntity)
        
        return entity
    }
    
    // MARK: - Animation
    
    private func animateActor(_ actor: PlannedScene.PlacedActor) {
        guard let entity = placedEntities[actor.id] else { return }
        guard actor.path.count > 1 else { return }
        
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
            }
            checkIfAllAnimationsComplete()
            return
        }
        
        guard isPlaying else { return }
        
        let startPosition = actor.path[segmentIndex].simdVector
        let targetPosition = actor.path[segmentIndex + 1].simdVector
        let duration = max(actor.pathDurations[segmentIndex], 0.1) // Минимум 0.1 сек
        
        // Сначала устанавливаем точную начальную позицию сегмента
        entity.stopAllAnimations()
        entity.position = startPosition
        
        // Вычисляем угол поворота в направлении движения
        let delta = targetPosition - startPosition
        let distance = simd_length(delta)
        
        // Если расстояние слишком маленькое, пропускаем этот сегмент
        guard distance > 0.01 else {
            animateActorSegment(entity: entity, actor: actor, segmentIndex: segmentIndex + 1)
            return
        }
        
        let angle = atan2(delta.x, delta.z)
        
        // Сначала устанавливаем ориентацию
        entity.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        
        // Создаём целевую трансформацию
        var targetTransform = Transform()
        targetTransform.translation = targetPosition
        targetTransform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
        
        // Запускаем анимацию
        entity.move(to: targetTransform, relativeTo: entity.parent, duration: duration, timingFunction: .linear)
        
        // Планируем следующий сегмент после завершения текущего
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPlaying else { return }
            // Устанавливаем точную конечную позицию перед следующим сегментом
            entity.position = targetPosition
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
        
        // Все актёры завершили анимацию
        if completedActorAnimations >= totalActorAnimations && isPlaying {
            isPlaying = false
            statusMessage = "Воспроизведение завершено"
        }
    }
    
    /// Мгновенно устанавливает актёров на начальные позиции (без анимации)
    private func setActorsToInitialPositionsInstantly() {
        guard let planned = plannedScene else { return }
        
        for actor in planned.placedActors {
            guard let entity = placedEntities[actor.id] else { continue }
            
            // Останавливаем любые текущие анимации этого entity
            entity.stopAllAnimations()
            
            // Мгновенно устанавливаем позицию
            entity.position = actor.initialPosition.simdVector
            entity.orientation = simd_quatf(angle: actor.initialRotation, axis: [0, 1, 0])
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
            if let markerIndex = unusedMarkers.firstIndex(where: { $0.type == scriptObject.type }) {
                let marker = unusedMarkers.remove(at: markerIndex)
                updatedObject.detectedPosition = marker.worldPosition
                return updatedObject
            }
            
            // 2. Затем ищем в детекциях
            if let detection = detectionBridge.findObject(ofType: scriptObject.type),
               let worldPosition = detection.worldPosition {
                updatedObject.detectedPosition = worldPosition
                return updatedObject
            }
            
            // 3. Если не найдено - остаётся виртуальным
            return updatedObject
        }
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
}

// MARK: - Example Descriptions

extension SceneGeneratorViewModel {
    
    /// Примеры описаний для UI
    static let exampleDescriptions: [(title: String, description: String)] = [
        ("Встреча", "2 актёра идут навстречу друг другу"),
        ("У стола", "Человек подходит к столу"),
        ("Расхождение", "2 человека идут навстречу, проходят мимо друг друга, один поворачивает направо, другой продолжает идти прямо"),
        ("Мимо шкафа", "Актёр проходит мимо шкафа"),
        ("Быстрый бег", "Человек быстро бежит вперёд")
    ]
}

