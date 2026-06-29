//
//  SpatialPlannerService.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import Foundation
import simd
import ARKit

struct ScenePlaneSnapshot: Equatable {
    enum Alignment: Equatable {
        case horizontal
        case vertical
        case unknown
    }

    var alignment: Alignment
    var y: Float

    init(alignment: Alignment, y: Float) {
        self.alignment = alignment
        self.y = y
    }

    init(anchor: ARPlaneAnchor) {
        let alignment: Alignment
        switch anchor.alignment {
        case .horizontal:
            alignment = .horizontal
        case .vertical:
            alignment = .vertical
        @unknown default:
            alignment = .unknown
        }
        self.init(alignment: alignment, y: anchor.transform.columns.3.y)
    }
}

/// Сервис для планирования размещения объектов и построения траекторий в 3D пространстве
final class SpatialPlannerService {

    static let shared = SpatialPlannerService()

    // MARK: - Configuration

    /// Расстояние между актёрами при начальном размещении
    private let actorSpacing: Float = 2.0

    /// Расстояние от камеры для размещения объектов
    private let defaultDistanceFromCamera: Float = 3.0

    /// Минимальное расстояние между объектами
    private let minimumObjectDistance: Float = 0.5

    /// Высота размещения актёров (Y координата)
    private let actorHeight: Float = 0.0

    /// Скорость ходьбы по умолчанию (м/с)
    private let defaultWalkSpeed: Float = 0.8

    /// Сценическая минимальная длительность заметного перемещения: короткие шаги не должны выглядеть как телепорт.
    private let minimumVisibleMovementDuration: Double = 1.2

    /// Длительности действий без физического перемещения, ближе к реальному отыгрышу актёрами.
    private let lookActionDuration: Double = 1.4
    private let propActionDuration: Double = 1.7

    /// LLM иногда отдаёт слишком большие minDuration; для live-demo это выглядит как зависший playback.
    private let maxModelBeatMinDuration: Double = 4.0

    private init() {}

    private struct ActorPathPlan {
        var path: [Position3D]
        var durations: [Double]
        var annotations: [PlaybackPathAnnotation?]
        var beatIDs: [String?]
    }

    // MARK: - Public API

    /// Планирует размещение всех элементов сцены
    /// - Parameters:
    ///   - script: Распознанный скрипт сцены
    ///   - cameraTransform: Текущая позиция и ориентация камеры
    ///   - detectedObjects: Обнаруженные объекты в кадре
    ///   - availablePlanes: Лёгкие snapshot'ы доступных плоскостей
    ///   - markedObjects: Размеченные пользователем объекты (высший приоритет)
    /// - Returns: PlannedScene с готовыми координатами
    func planScene(
        script: SceneScript,
        cameraTransform: simd_float4x4,
        detectedObjects: [DetectedObject],
        availablePlanes: [ScenePlaneSnapshot],
        markedObjects: [MarkedObject] = []
    ) -> PlannedScene {
        print("🔍 [PLANNER] === НАЧАЛО ПЛАНИРОВАНИЯ ===")
        print("🔍 [PLANNER] Входные данные: actors=\(script.actors.count), objects=\(script.objects.count), beats=\(script.beats.count), actions=\(script.actions.count), detectedObjects=\(detectedObjects.count), markedObjects=\(markedObjects.count)")

        // 1. Определяем доступное пространство
        let sceneSpace = calculateSceneSpace(
            cameraTransform: cameraTransform,
            planes: availablePlanes
        )

        // 2. Размещаем объекты (приоритет: marked -> detected -> virtual)
        print("🔍 [PLANNER] Планирование объектов...")
        let placedObjects = planObjects(
            scriptObjects: script.objects,
            detectedObjects: detectedObjects,
            markedObjects: markedObjects,
            sceneSpace: sceneSpace
        )
        print("🔍 [PLANNER] Размещено объектов: \(placedObjects.count)")
        for (index, object) in placedObjects.enumerated() {
            print("🔍 [PLANNER]   PlacedObject[\(index)]: id='\(object.id)', objectId='\(object.objectId)', type=\(object.type.rawValue), isRealWorld=\(object.isRealWorld ? 1 : 0), source=\(object.placementSource.rawValue)")
        }

        // 3. Размещаем актёров
        print("🔍 [PLANNER] Планирование актёров...")
        let placedActors = planActors(
            scriptActors: script.actors,
            beats: script.beats,
            actions: script.actions,
            relations: script.spatialRelations,
            placedObjects: placedObjects,
            sceneSpace: sceneSpace
        )
        print("🔍 [PLANNER] Размещено актёров: \(placedActors.count)")
        for (index, actor) in placedActors.enumerated() {
            print("🔍 [PLANNER]   PlacedActor[\(index)]: id='\(actor.id)', actorId='\(actor.actorId)', type=\(actor.type.rawValue), path.count=\(actor.path.count)")
        }

        print("🔍 [PLANNER] === ПЛАНИРОВАНИЕ ЗАВЕРШЕНО ===")

        return PlannedScene(
            placedActors: placedActors,
            placedObjects: placedObjects
        )
    }

    // MARK: - Scene Space Calculation

    private struct SceneSpace {
        let center: Position3D           // Центр доступного пространства
        let forward: simd_float3         // Направление "вперёд" от камеры
        let right: simd_float3           // Направление "вправо" от камеры
        let bounds: (min: Position3D, max: Position3D)  // Границы пространства
        let floorY: Float                // Y координата пола
    }

    private func calculateSceneSpace(
        cameraTransform: simd_float4x4,
        planes: [ScenePlaneSnapshot]
    ) -> SceneSpace {
        // Позиция камеры
        let cameraPosition = simd_float3(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        // Направление "вперёд" камеры (отрицательный Z)
        let forward = -simd_normalize(simd_float3(
            cameraTransform.columns.2.x,
            0,  // Проецируем на горизонтальную плоскость
            cameraTransform.columns.2.z
        ))

        // Направление "вправо"
        let right = simd_normalize(simd_cross(simd_float3(0, 1, 0), forward))

        // Определяем Y координату пола
        let floorY: Float
        if let lowestPlane = planes.filter({ $0.alignment == .horizontal }).min(by: { $0.y < $1.y }) {
            floorY = lowestPlane.y
        } else {
            floorY = cameraPosition.y - 1.5  // Предполагаем высоту камеры ~1.5м
        }

        // Центр сцены - перед камерой на defaultDistanceFromCamera
        let center = Position3D(
            x: cameraPosition.x + forward.x * defaultDistanceFromCamera,
            y: floorY,
            z: cameraPosition.z + forward.z * defaultDistanceFromCamera
        )

        // Границы сцены
        let halfWidth: Float = 3.0
        let halfDepth: Float = 4.0

        let minBounds = Position3D(
            x: center.x - halfWidth,
            y: floorY,
            z: center.z - halfDepth
        )

        let maxBounds = Position3D(
            x: center.x + halfWidth,
            y: floorY + 3.0,
            z: center.z + halfDepth
        )

        return SceneSpace(
            center: center,
            forward: forward,
            right: right,
            bounds: (min: minBounds, max: maxBounds),
            floorY: floorY
        )
    }

    // MARK: - Object Planning

    private func planObjects(
        scriptObjects: [SceneObject],
        detectedObjects: [DetectedObject],
        markedObjects: [MarkedObject],
        sceneSpace: SceneSpace
    ) -> [PlannedScene.PlacedObject] {
        print("🔍 [PLANNER] planObjects: scriptObjects=\(scriptObjects.count), detectedObjects=\(detectedObjects.count), markedObjects=\(markedObjects.count)")

        var placedObjects: [PlannedScene.PlacedObject] = []

        for (index, scriptObject) in scriptObjects.enumerated() {
            print("🔍 [PLANNER] Обработка scriptObject[\(index)]: id='\(scriptObject.id)', type=\(scriptObject.type.rawValue), detectedPosition=\(scriptObject.detectedPosition != nil ? "YES" : "NO")")
            let position: Position3D
            let placementSource: PlannedScene.PlacedObject.PlacementSource
            var isDetected = false

            // 1. ВЫСШИЙ ПРИОРИТЕТ: Ручные метки пользователя
            if let markedObject = findMarkedObject(for: scriptObject, in: markedObjects) {
                print("🔍 [PLANNER]   Найден markedObject для scriptObject.id='\(scriptObject.id)': id=\(markedObject.id.uuidString)")
                position = markedObject.worldPosition
                placementSource = .marked
                isDetected = true
            }
            // 2. Используем уже сопоставленную позицию (например, через ViewModel)
            else if let detectedPosition = scriptObject.detectedPosition {
                print("🔍 [PLANNER]   Используется detectedPosition из scriptObject")
                position = detectedPosition
                placementSource = .detected
                isDetected = true
            }
            // 3. Используем автоматическую детекцию
            else if let detection = detectedObjects.first(where: { $0.objectType == scriptObject.type }),
                    let worldPosition = detection.worldPosition {
                print("🔍 [PLANNER]   Найден detectedObject для type=\(scriptObject.type.rawValue)")
                position = worldPosition
                placementSource = .detected
                isDetected = true
            }
            // 4. Для связанных виртуальных объектов используем уже размещённый контекст сцены.
            else if let relatedPosition = generateRelatedVirtualObjectPosition(
                for: scriptObject,
                placedObjects: placedObjects
            ) {
                print("🔍 [PLANNER]   Виртуальный объект связан с уже размещённым объектом")
                position = relatedPosition
                placementSource = .virtual
            }
            // 5. Создаём виртуальный объект
            else {
                print("🔍 [PLANNER]   Создаётся виртуальный объект для type=\(scriptObject.type.rawValue)")
                position = generateObjectPosition(
                    for: scriptObject,
                    index: index,
                    sceneSpace: sceneSpace
                )
                placementSource = .virtual
            }

            let placedObject = PlannedScene.PlacedObject(
                id: "placed_\(scriptObject.id)",
                objectId: scriptObject.id,
                type: scriptObject.type,
                position: position,
                rotation: 0,
                isDetected: isDetected,
                placementSource: placementSource
            )
            placedObjects.append(placedObject)
        }

        return placedObjects
    }

    private func findMarkedObject(for scriptObject: SceneObject, in markedObjects: [MarkedObject]) -> MarkedObject? {
        if let markedShortID = scriptObject.markedObjectShortID,
           let exactMarker = markedObjects.first(where: { $0.id.uuidString.prefix(8).lowercased() == markedShortID.lowercased() }) {
            return exactMarker
        }

        let sameTypeMarkers = markedObjects.filter { $0.type == scriptObject.type }
        if sameTypeMarkers.count == 1 {
            return sameTypeMarkers.first
        }

        return nil
    }

    private func generateRelatedVirtualObjectPosition(
        for object: SceneObject,
        placedObjects: [PlannedScene.PlacedObject]
    ) -> Position3D? {
        guard object.type == .phone,
              let table = placedObjects.first(where: { $0.type == .table })
        else {
            return nil
        }

        let tableTopY: Float
        if table.placementSource == .marked {
            tableTopY = table.position.y
        } else {
            tableTopY = table.position.y + table.size.y / 2
        }
        let phoneCenterY = tableTopY + object.type.placeholderSize.y / 2 + 0.03
        let tableOffset = supportSurfaceOffset(for: object, on: table)
        return Position3D(
            x: table.position.x + tableOffset.x,
            y: phoneCenterY,
            z: table.position.z + tableOffset.y
        )
    }

    private func supportSurfaceOffset(
        for object: SceneObject,
        on supportObject: PlannedScene.PlacedObject
    ) -> SIMD2<Float> {
        guard object.type == .phone, supportObject.type == .table else {
            return SIMD2<Float>(0, 0)
        }

        let localOffset = SIMD2<Float>(
            min(max(supportObject.size.x * 0.04, 0.04), 0.07),
            -min(max(supportObject.size.z * 0.035, 0.025), 0.05)
        )
        let cosRotation = cos(supportObject.rotation)
        let sinRotation = sin(supportObject.rotation)

        return SIMD2<Float>(
            localOffset.x * cosRotation + localOffset.y * sinRotation,
            -localOffset.x * sinRotation + localOffset.y * cosRotation
        )
    }

    private func generateObjectPosition(
        for object: SceneObject,
        index: Int,
        sceneSpace: SceneSpace
    ) -> Position3D {
        let offsetX: Float
        let offsetZ: Float

        switch object.relativePosition {
        case .left:
            offsetX = -2.0
            offsetZ = 0
        case .right:
            offsetX = 2.0
            offsetZ = 0
        case .center:
            offsetX = 0
            offsetZ = 0
        case .background:
            offsetX = Float(index) * 1.5 - 1.5
            offsetZ = 2.0
        case .foreground:
            offsetX = Float(index) * 1.5 - 1.5
            offsetZ = -1.0
        case .unknown:
            // Размещаем справа от центра
            offsetX = 1.5 + Float(index) * 1.0
            offsetZ = 0
        }

        return Position3D(
            x: sceneSpace.center.x + sceneSpace.right.x * offsetX + sceneSpace.forward.x * offsetZ,
            y: sceneSpace.floorY,
            z: sceneSpace.center.z + sceneSpace.right.z * offsetX + sceneSpace.forward.z * offsetZ
        )
    }

    // MARK: - Actor Planning

    private func planActors(
        scriptActors: [SceneActor],
        beats: [SceneBeat],
        actions: [SceneAction],
        relations: [SpatialRelation],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> [PlannedScene.PlacedActor] {
        print("🔍 [PLANNER] planActors: scriptActors=\(scriptActors.count), actions=\(actions.count), relations=\(relations.count)")

        // Определяем начальные позиции
        let initialPositions = calculateInitialPositions(
            actors: scriptActors,
            actions: actions,
            placedObjects: placedObjects,
            sceneSpace: sceneSpace
        )
        print("🔍 [PLANNER] Вычислено начальных позиций: \(initialPositions.count)")

        let actorPathPlans = buildSynchronizedActorPaths(
            actors: scriptActors,
            beats: beats,
            initialPositions: initialPositions,
            placedObjects: placedObjects,
            sceneSpace: sceneSpace
        )

        // Строим траектории для каждого актёра
        return scriptActors.enumerated().map { index, actor in
            print("🔍 [PLANNER] Обработка scriptActor[\(index)]: id='\(actor.id)', type=\(actor.type.rawValue)")
            let initialPosition = initialPositions[index]

            // Вычисляем начальную ротацию (смотрим в центр сцены)
            let lookAtCenter = simd_float3(
                sceneSpace.center.x - initialPosition.x,
                0,
                sceneSpace.center.z - initialPosition.z
            )
            let initialRotation = atan2(lookAtCenter.x, lookAtCenter.z)
            let pathPlan = actorPathPlans[actor.id] ?? ActorPathPlan(path: [initialPosition], durations: [], annotations: [nil], beatIDs: [nil])

            return PlannedScene.PlacedActor(
                id: "placed_\(actor.id)",
                actorId: actor.id,
                type: actor.type,
                name: actor.name,
                initialPosition: initialPosition,
                initialRotation: initialRotation,
                path: pathPlan.path,
                pathDurations: pathPlan.durations,
                pathPoses: Array(repeating: .standing, count: pathPlan.path.count),
                pathCameras: Array(repeating: nil, count: pathPlan.path.count),
                pathAnnotations: pathPlan.annotations,
                pathBeatIDs: pathPlan.beatIDs
            )
        }
    }

    private func calculateInitialPositions(
        actors: [SceneActor],
        actions: [SceneAction],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> [Position3D] {

        let actorCount = actors.count

        // Проверяем есть ли действие "навстречу друг другу"
        let hasTowardEachOther = actions.contains { $0.direction == .towardEachOther }

        if hasTowardEachOther && actorCount >= 2 {
            // Размещаем на противоположных сторонах
            return calculateOppositePositions(
                actorCount: actorCount,
                sceneSpace: sceneSpace
            )
        }

        // Проверяем есть ли действие "подойти к объекту"
        let approachActions = actions.filter { $0.type == .approach && $0.target != nil }
        if !approachActions.isEmpty {
            return calculateApproachPositions(
                actors: actors,
                approachActions: approachActions,
                placedObjects: placedObjects,
                sceneSpace: sceneSpace
            )
        }

        // По умолчанию - в ряд
        return calculateRowPositions(actorCount: actorCount, sceneSpace: sceneSpace)
    }

    private func calculateOppositePositions(
        actorCount: Int,
        sceneSpace: SceneSpace
    ) -> [Position3D] {
        var positions: [Position3D] = []

        // Первый актёр слева
        positions.append(Position3D(
            x: sceneSpace.center.x - sceneSpace.right.x * actorSpacing,
            y: sceneSpace.floorY,
            z: sceneSpace.center.z - sceneSpace.right.z * actorSpacing
        ))

        // Второй актёр справа
        if actorCount >= 2 {
            positions.append(Position3D(
                x: sceneSpace.center.x + sceneSpace.right.x * actorSpacing,
                y: sceneSpace.floorY,
                z: sceneSpace.center.z + sceneSpace.right.z * actorSpacing
            ))
        }

        // Дополнительные актёры - случайные позиции
        for _ in 2..<actorCount {
            let offsetX = Float.random(in: -1.5...1.5)
            let offsetZ = Float.random(in: -1.0...1.0)
            positions.append(Position3D(
                x: sceneSpace.center.x + offsetX,
                y: sceneSpace.floorY,
                z: sceneSpace.center.z + offsetZ
            ))
        }

        return positions
    }

    private func calculateApproachPositions(
        actors: [SceneActor],
        approachActions: [SceneAction],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> [Position3D] {
        var positions: [Position3D] = []

        // Группируем актёров по целевому объекту
        var actorsByTarget: [String: [SceneActor]] = [:]
        for actor in actors {
            if let action = approachActions.first(where: { $0.actorId == actor.id }),
               let targetId = action.target {
                if actorsByTarget[targetId] == nil {
                    actorsByTarget[targetId] = []
                }
                actorsByTarget[targetId]?.append(actor)
            }
        }

        print("🔍 [PLANNER] calculateApproachPositions: actors=\(actors.count), actorsByTarget=\(actorsByTarget.count) групп")

        for actor in actors {
            // Ищем действие approach для этого актёра
            if let action = approachActions.first(where: { $0.actorId == actor.id }),
               let targetId = action.target,
               let targetObject = placedObjects.first(where: { $0.objectId == targetId }) {

                // Определяем индекс актёра среди тех, кто идёт к этому же объекту
                let actorsToSameTarget = actorsByTarget[targetId] ?? []
                let actorIndexInGroup = actorsToSameTarget.firstIndex(where: { $0.id == actor.id }) ?? 0
                let totalActorsToTarget = actorsToSameTarget.count

                print("🔍 [PLANNER]   Актёр '\(actor.id)' идёт к объекту '\(targetId)', индекс в группе: \(actorIndexInGroup)/\(totalActorsToTarget)")

                // Размещаем в 2 метрах от объекта
                let direction = simd_normalize(simd_float3(
                    sceneSpace.center.x - targetObject.position.x,
                    0,
                    sceneSpace.center.z - targetObject.position.z
                ))

                // Если несколько актёров идут к одному объекту, размещаем их в ряд перпендикулярно направлению
                let baseDistance: Float = 2.0
                let basePosition = Position3D(
                    x: targetObject.position.x + direction.x * baseDistance,
                    y: sceneSpace.floorY,
                    z: targetObject.position.z + direction.z * baseDistance
                )

                if totalActorsToTarget > 1 {
                    // Вычисляем перпендикулярное направление для размещения в ряд
                    let perpendicular = simd_float3(-direction.z, 0, direction.x)

                    // Размещаем актёров в ряд с интервалом actorSpacing
                    let totalWidth = Float(totalActorsToTarget - 1) * actorSpacing
                    let startOffset = -totalWidth / 2
                    let offset = startOffset + Float(actorIndexInGroup) * actorSpacing

                    positions.append(Position3D(
                        x: basePosition.x + perpendicular.x * offset,
                        y: sceneSpace.floorY,
                        z: basePosition.z + perpendicular.z * offset
                    ))
                    print("🔍 [PLANNER]     Позиция с смещением: x=\(basePosition.x + perpendicular.x * offset), z=\(basePosition.z + perpendicular.z * offset)")
                } else {
                    // Один актёр - размещаем в базовой позиции
                    positions.append(basePosition)
                    print("🔍 [PLANNER]     Позиция без смещения: x=\(basePosition.x), z=\(basePosition.z)")
                }
            } else {
                // Позиция по умолчанию
                let offsetX = Float(positions.count) * actorSpacing - Float(actors.count - 1) * actorSpacing / 2
                positions.append(Position3D(
                    x: sceneSpace.center.x + sceneSpace.right.x * offsetX,
                    y: sceneSpace.floorY,
                    z: sceneSpace.center.z + sceneSpace.forward.z * 2.0
                ))
            }
        }

        return positions
    }

    private func calculateRowPositions(
        actorCount: Int,
        sceneSpace: SceneSpace
    ) -> [Position3D] {
        var positions: [Position3D] = []

        let totalWidth = Float(actorCount - 1) * actorSpacing
        let startX = -totalWidth / 2

        for i in 0..<actorCount {
            let offsetX = startX + Float(i) * actorSpacing
            positions.append(Position3D(
                x: sceneSpace.center.x + sceneSpace.right.x * offsetX,
                y: sceneSpace.floorY,
                z: sceneSpace.center.z
            ))
        }

        return positions
    }

    // MARK: - Path Building

    private func buildSynchronizedActorPaths(
        actors: [SceneActor],
        beats: [SceneBeat],
        initialPositions: [Position3D],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> [String: ActorPathPlan] {
        var timelines: [String: ActorPathPlan] = [:]
        var currentPositions: [String: Position3D] = [:]

        for (index, actor) in actors.enumerated() {
            let initialPosition = initialPositions.indices.contains(index) ? initialPositions[index] : sceneSpace.center
            timelines[actor.id] = ActorPathPlan(path: [initialPosition], durations: [], annotations: [nil], beatIDs: [nil])
            currentPositions[actor.id] = initialPosition
        }

        for beat in beats {
            if shouldSerializeBeatActions(beat) {
                let serialized = buildSerializedBeatAdditions(
                    beat: beat,
                    actors: actors,
                    currentPositions: currentPositions,
                    placedObjects: placedObjects,
                    sceneSpace: sceneSpace
                )
                guard serialized.hasOutput, serialized.duration > 0 else { continue }

                for actor in actors {
                    guard var timeline = timelines[actor.id],
                          let addition = serialized.additions[actor.id]
                    else { continue }
                    timeline.path.append(contentsOf: addition.path)
                    timeline.durations.append(contentsOf: addition.durations)
                    timeline.annotations.append(contentsOf: addition.annotations)
                    timeline.beatIDs.append(contentsOf: addition.beatIDs)
                    timelines[actor.id] = timeline
                    currentPositions[actor.id] = serialized.finalPositions[actor.id] ?? currentPositions[actor.id]
                }
                continue
            }

            let beatStartPositions = currentPositions
            var additionsByActor: [String: ActorPathPlan] = [:]
            var beatDuration = min(max(beat.minDuration ?? 0, 0), maxModelBeatMinDuration)
            var hasAnyActorOutput = false

            for actor in actors {
                var actorPositions: [Position3D] = []
                var actorDurations: [Double] = []
                var actorAnnotations: [PlaybackPathAnnotation?] = []
                var actorBeatIDs: [String?] = []
                var actorCurrentPosition = currentPositions[actor.id] ?? sceneSpace.center
                let actorActions = beat.actions.filter { $0.actorId == actor.id }

                for action in actorActions {
                    let (newPositions, newDurations, newAnnotations) = processAction(
                        action,
                        currentPosition: actorCurrentPosition,
                        allActors: actors,
                        actorPositions: beatStartPositions,
                        placedObjects: placedObjects,
                        sceneSpace: sceneSpace
                    )

                    actorPositions.append(contentsOf: newPositions)
                    actorDurations.append(contentsOf: newDurations)
                    actorAnnotations.append(contentsOf: newAnnotations)
                    actorBeatIDs.append(contentsOf: Array(repeating: beat.id, count: newPositions.count))

                    if let lastPosition = newPositions.last {
                        actorCurrentPosition = lastPosition
                    }
                }

                additionsByActor[actor.id] = ActorPathPlan(
                    path: actorPositions,
                    durations: actorDurations,
                    annotations: actorAnnotations,
                    beatIDs: actorBeatIDs
                )
                hasAnyActorOutput = hasAnyActorOutput || !actorPositions.isEmpty
                beatDuration = max(beatDuration, actorDurations.reduce(0, +))
            }

            guard hasAnyActorOutput else { continue }
            guard beatDuration > 0 else { continue }

            for actor in actors {
                guard var timeline = timelines[actor.id] else { continue }
                var addition = additionsByActor[actor.id] ?? ActorPathPlan(path: [], durations: [], annotations: [], beatIDs: [])
                let actorBeatDuration = addition.durations.reduce(0, +)
                let finalPosition = addition.path.last ?? currentPositions[actor.id] ?? sceneSpace.center
                let remainingDuration = beatDuration - actorBeatDuration

                if remainingDuration > 0.001 {
                    addition.path.append(finalPosition)
                    addition.durations.append(remainingDuration)
                    addition.annotations.append(nil)
                    addition.beatIDs.append(beat.id)
                }

                timeline.path.append(contentsOf: addition.path)
                timeline.durations.append(contentsOf: addition.durations)
                timeline.annotations.append(contentsOf: addition.annotations)
                timeline.beatIDs.append(contentsOf: addition.beatIDs)
                timelines[actor.id] = timeline
                currentPositions[actor.id] = finalPosition
            }
        }

        return timelines
    }

    private func shouldSerializeBeatActions(_ beat: SceneBeat) -> Bool {
        guard beat.actions.count > 1 else { return false }
        return beat.actions.allSatisfy { action in
            action.type == .talk || action.type == .describedAction
        }
    }

    private func buildSerializedBeatAdditions(
        beat: SceneBeat,
        actors: [SceneActor],
        currentPositions: [String: Position3D],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> (additions: [String: ActorPathPlan], finalPositions: [String: Position3D], duration: Double, hasOutput: Bool) {
        var additions = Dictionary(
            uniqueKeysWithValues: actors.map { actor in
                (actor.id, ActorPathPlan(path: [], durations: [], annotations: [], beatIDs: []))
            }
        )
        var runningPositions = currentPositions
        var totalDuration: Double = 0
        var hasOutput = false

        for action in beat.actions {
            guard actors.contains(where: { $0.id == action.actorId }) else { continue }
            let currentPosition = runningPositions[action.actorId] ?? sceneSpace.center
            let (newPositions, newDurations, newAnnotations) = processAction(
                action,
                currentPosition: currentPosition,
                allActors: actors,
                actorPositions: runningPositions,
                placedObjects: placedObjects,
                sceneSpace: sceneSpace
            )
            let actionDuration = newDurations.reduce(0, +)
            guard !newPositions.isEmpty, actionDuration > 0 else { continue }
            hasOutput = true
            totalDuration += actionDuration

            for actor in actors {
                var addition = additions[actor.id] ?? ActorPathPlan(path: [], durations: [], annotations: [], beatIDs: [])
                if actor.id == action.actorId {
                    addition.path.append(contentsOf: newPositions)
                    addition.durations.append(contentsOf: newDurations)
                    addition.annotations.append(contentsOf: newAnnotations)
                    addition.beatIDs.append(contentsOf: Array(repeating: beat.id, count: newPositions.count))
                    runningPositions[actor.id] = newPositions.last ?? currentPosition
                } else {
                    let waitPosition = runningPositions[actor.id] ?? sceneSpace.center
                    addition.path.append(waitPosition)
                    addition.durations.append(actionDuration)
                    addition.annotations.append(nil)
                    addition.beatIDs.append(beat.id)
                }
                additions[actor.id] = addition
            }
        }

        return (additions, runningPositions, totalDuration, hasOutput)
    }

    private func buildPath(
        for actor: SceneActor,
        startPosition: Position3D,
        actions: [SceneAction],
        allActors: [SceneActor],
        initialPositions: [Position3D],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> ([Position3D], [Double], [PlaybackPathAnnotation?]) {

        var path: [Position3D] = [startPosition]
        var durations: [Double] = []
        var annotations: [PlaybackPathAnnotation?] = [nil]
        var currentPosition = startPosition
        let actorPositions = Dictionary(uniqueKeysWithValues: zip(allActors.map(\.id), initialPositions))

        for action in actions {
            let (newPositions, newDurations, newAnnotations) = processAction(
                action,
                currentPosition: currentPosition,
                allActors: allActors,
                actorPositions: actorPositions,
                placedObjects: placedObjects,
                sceneSpace: sceneSpace
            )

            path.append(contentsOf: newPositions)
            durations.append(contentsOf: newDurations)
            annotations.append(contentsOf: newAnnotations)

            if let lastPosition = newPositions.last {
                currentPosition = lastPosition
            }
        }

        return (path, durations, annotations)
    }

    private func processAction(
        _ action: SceneAction,
        currentPosition: Position3D,
        allActors: [SceneActor],
        actorPositions: [String: Position3D],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> ([Position3D], [Double], [PlaybackPathAnnotation?]) {

        var positions: [Position3D] = []
        var durations: [Double] = []
        var annotations: [PlaybackPathAnnotation?] = []

        let resolvedTargetObject: PlannedScene.PlacedObject? = {
            guard let targetId = action.target else { return nil }
            return placedObjects.first(where: { $0.objectId == targetId })
        }()

        // Helper: resolve target position from objects OR actors
        let resolvedTargetPosition: Position3D? = {
            guard let targetId = action.target else { return nil }
            // 1. Поиск среди объектов
            if let obj = resolvedTargetObject {
                return obj.position
            }
            // 2. Поиск среди актёров (например, pass_by с target: actor_1)
            if let actorPosition = actorPositions[targetId] {
                return actorPosition
            }
            return nil
        }()

        switch action.type {
        case .walk, .run:
            // Если есть направление к цели и есть target — идём к объекту/актёру
            if action.direction == .toTarget,
               let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleApproach(
                    to: targetPos,
                    currentPosition: currentPosition,
                    speed: action.speed
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            }
            // Иначе используем направление
            else if let direction = action.direction {
                let (pos, dur) = handleDirectionalMovement(
                    direction: direction,
                    action: action,
                    currentPosition: currentPosition,
                    allActors: allActors,
                    actorPositions: actorPositions,
                    sceneSpace: sceneSpace
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            }
            // Если нет направления, но есть target — идём к нему
            else if let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleApproach(
                    to: targetPos,
                    currentPosition: currentPosition,
                    speed: action.speed
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            }

        case .enter:
            if action.direction == .toTarget,
               let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleApproach(
                    to: targetPos,
                    currentPosition: currentPosition,
                    speed: max(action.speed, 0.8)
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            } else if let direction = action.direction {
                let (pos, dur) = handleDirectionalMovement(
                    direction: direction,
                    action: action,
                    currentPosition: currentPosition,
                    allActors: allActors,
                    actorPositions: actorPositions,
                    sceneSpace: sceneSpace
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            } else if let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleApproach(
                    to: targetPos,
                    currentPosition: currentPosition,
                    speed: max(action.speed, 0.8)
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            } else {
                let (pos, dur) = handleEnter(
                    currentPosition: currentPosition,
                    sceneSpace: sceneSpace,
                    speed: max(action.speed, 0.8)
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            }

        case .approach:
            if let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleApproach(
                    to: targetPos,
                    currentPosition: currentPosition,
                    speed: action.speed
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            } else {
                print("⚠️ [PLANNER] approach без resolvable target для action '\(action.id)', остаёмся на месте")
                positions.append(currentPosition)
                durations.append(0.2)
                annotations.append(playbackAnnotation(kind: .action, text: action.sourceText ?? action.fallbackText ?? "approach(target unresolved)"))
            }

        case .passBy:
            if let targetPos = resolvedTargetPosition {
                let (pos, dur) = handlePassBy(
                    object: targetPos,
                    currentPosition: currentPosition,
                    sceneSpace: sceneSpace,
                    speed: action.speed
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            } else {
                print("⚠️ [PLANNER] pass_by без resolvable target для action '\(action.id)', остаёмся на месте")
                positions.append(currentPosition)
                durations.append(0.2)
                annotations.append(playbackAnnotation(kind: .action, text: action.sourceText ?? action.fallbackText ?? "pass_by(target unresolved)"))
            }

        case .turn:
            // Поворот без перемещения — остаёмся на месте
            break

        case .stop:
            if let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleApproach(
                    to: targetPos,
                    currentPosition: currentPosition,
                    speed: max(action.speed, 0.8)
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            } else {
                positions.append(currentPosition)
                durations.append(0.2)
                annotations.append(playbackAnnotation(kind: .action, text: action.sourceText ?? action.fallbackText))
            }

        case .stand:
            if let targetPos = resolvedTargetPosition {
                let (pos, _) = handleApproach(
                    to: targetPos,
                    currentPosition: currentPosition,
                    speed: 100 // Мгновенное перемещение
                )
                positions.append(contentsOf: pos)
                durations.append(0.1)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
            } else {
                if let annotation = playbackAnnotation(kind: .action, text: action.sourceText ?? action.fallbackText) {
                    positions.append(currentPosition)
                    durations.append(0.5)
                    annotations.append(annotation)
                }
            }

        case .lookAt:
            var actionPosition = currentPosition
            if sourceTextIndicatesApproach(action.sourceText),
               let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleContextualApproach(
                    action: action,
                    to: targetPos,
                    targetObject: resolvedTargetObject,
                    currentPosition: currentPosition,
                    placedObjects: placedObjects,
                    speed: max(action.speed, 0.8)
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
                actionPosition = pos.last ?? currentPosition
            }
            positions.append(actionPosition)
            durations.append(lookActionDuration)
            annotations.append(playbackAnnotation(kind: .action, text: actionCaption(for: action)))

        case .pickUp, .putDown, .give, .open, .close:
            var actionPosition = currentPosition
            if let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleContextualApproach(
                    action: action,
                    to: targetPos,
                    targetObject: resolvedTargetObject,
                    currentPosition: currentPosition,
                    placedObjects: placedObjects,
                    speed: max(action.speed, 0.8)
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
                annotations.append(contentsOf: Array(repeating: nil, count: pos.count))
                actionPosition = pos.last ?? currentPosition
            }
            positions.append(actionPosition)
            durations.append(propActionDuration)
            annotations.append(playbackAnnotation(kind: .action, text: actionCaption(for: action)))

        case .talk:
            let text = action.dialogue ?? action.sourceText ?? action.fallbackText
            positions.append(currentPosition)
            durations.append(stageTextDuration(for: text, minimum: 1.7, maximum: 3.6))
            annotations.append(playbackAnnotation(kind: .dialogue, text: text))

        case .describedAction:
            let text = action.fallbackText ?? action.sourceText
            guard let annotation = playbackAnnotation(kind: .action, text: text) else { break }
            // Не перемещаемся физически, но резервируем время под описанное действие.
            positions.append(currentPosition)
            durations.append(stageTextDuration(for: annotation.text, minimum: 1.8, maximum: 3.2))
            annotations.append(annotation)

        default:
            break
        }

        return (positions, durations, annotations)
    }

    private func actionCaption(for action: SceneAction) -> String {
        if let text = action.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return semanticActionCaption(for: action, sourceText: text)
        }
        if let text = action.fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return semanticActionCaption(for: action, sourceText: text)
        }
        switch action.type {
        case .lookAt:
            return "смотрит на объект"
        case .pickUp:
            return "берёт объект"
        case .putDown:
            return "кладёт объект"
        case .give:
            return "передаёт объект"
        case .open:
            return "открывает объект"
        case .close:
            return "закрывает объект"
        case .describedAction:
            return "описанное действие"
        default:
            return action.type.rawValue
        }
    }

    private func semanticActionCaption(for action: SceneAction, sourceText: String) -> String {
        switch action.type {
        case .pickUp:
            guard let giveRange = firstRange(
                ofAny: ["передаёт", "передает", "передал", "передала", "даёт", "дает"],
                in: sourceText
            ) else { return sourceText }
            return cleanedActionFragment(String(sourceText[..<giveRange.lowerBound]))
        case .give:
            guard let giveRange = firstRange(
                ofAny: ["передаёт", "передает", "передал", "передала", "даёт", "дает"],
                in: sourceText
            ) else { return sourceText }
            let actorPrefix = actorPrefixBeforeFirstActionVerb(in: sourceText)
            let giveClause = cleanedActionFragment(String(sourceText[giveRange.lowerBound...]))
            guard !actorPrefix.isEmpty else { return giveClause }
            return cleanedActionFragment("\(actorPrefix) \(giveClause)")
        default:
            return sourceText
        }
    }

    private func actorPrefixBeforeFirstActionVerb(in text: String) -> String {
        guard let verbRange = firstRange(
            ofAny: ["берёт", "берет", "поднимает", "взял", "взяла", "кладёт", "кладет", "передаёт", "передает", "даёт", "дает"],
            in: text
        ) else { return "" }
        return cleanedActionFragment(String(text[..<verbRange.lowerBound]))
    }

    private func firstRange(ofAny needles: [String], in text: String) -> Range<String.Index>? {
        needles
            .compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private func cleanedActionFragment(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix(" и") {
            cleaned = String(cleaned.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
    }

    private func playbackAnnotation(kind: PlaybackPathAnnotation.Kind, text: String?) -> PlaybackPathAnnotation? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        guard let caption = humanReadablePlaybackCaption(text) else { return nil }
        return PlaybackPathAnnotation(kind: kind, text: caption)
    }

    private func humanReadablePlaybackCaption(_ text: String) -> String? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "described_action":
            return nil
        case "look_at":
            return "Смотрит на цель"
        case "pick_up":
            return "Берёт объект"
        case "give":
            return "Передаёт объект"
        default:
            return text
        }
    }

    private func stageTextDuration(for text: String?, minimum: Double, maximum: Double) -> Double {
        let normalized = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty } ?? []
        guard !normalized.isEmpty else { return minimum }
        let spokenDuration = 0.45 + Double(normalized.count) * 0.34
        return min(max(spokenDuration, minimum), maximum)
    }

    private func handleDirectionalMovement(
        direction: SceneAction.Direction,
        action: SceneAction,
        currentPosition: Position3D,
        allActors: [SceneActor],
        actorPositions: [String: Position3D],
        sceneSpace: SceneSpace
    ) -> ([Position3D], [Double]) {

        var positions: [Position3D] = []
        var durations: [Double] = []
        let moveDistance: Float = 2.0

        switch direction {
        case .towardEachOther:
            // Вычисляем точку встречи между двумя актёрами (с оффсетом, чтобы не наложились)
            // Находим оппонента по target или используем центр
            var meetingPoint = sceneSpace.center
            if let targetActorId = action.target,
               let otherPos = actorPositions[targetActorId] {
                // Точка встречи — середина между двумя актёрами
                let midPoint = Position3D(
                    x: (currentPosition.x + otherPos.x) / 2,
                    y: currentPosition.y,
                    z: (currentPosition.z + otherPos.z) / 2
                )
                // Перпендикулярный оффсет чтобы не стоять в одной точке
                let toOther = simd_normalize(simd_float3(
                    otherPos.x - currentPosition.x, 0, otherPos.z - currentPosition.z
                ))
                // Останавливаемся в 0.5м от середины (1м между актёрами)
                meetingPoint = Position3D(
                    x: midPoint.x - toOther.x * 0.5,
                    y: currentPosition.y,
                    z: midPoint.z - toOther.z * 0.5
                )
            }
            positions.append(meetingPoint)
            durations.append(calculateDuration(from: currentPosition, to: meetingPoint, speed: action.speed))

        case .awayFromEachOther:
            // Движемся от центра
            let directionFromCenter = simd_normalize(simd_float3(
                currentPosition.x - sceneSpace.center.x,
                0,
                currentPosition.z - sceneSpace.center.z
            ))
            let targetPosition = Position3D(
                x: currentPosition.x + directionFromCenter.x * moveDistance,
                y: currentPosition.y,
                z: currentPosition.z + directionFromCenter.z * moveDistance
            )
            positions.append(targetPosition)
            durations.append(calculateDuration(from: currentPosition, to: targetPosition, speed: action.speed))

        case .left:
            let targetPosition = Position3D(
                x: currentPosition.x - sceneSpace.right.x * moveDistance,
                y: currentPosition.y,
                z: currentPosition.z - sceneSpace.right.z * moveDistance
            )
            positions.append(targetPosition)
            durations.append(calculateDuration(from: currentPosition, to: targetPosition, speed: action.speed))

        case .right:
            let targetPosition = Position3D(
                x: currentPosition.x + sceneSpace.right.x * moveDistance,
                y: currentPosition.y,
                z: currentPosition.z + sceneSpace.right.z * moveDistance
            )
            positions.append(targetPosition)
            durations.append(calculateDuration(from: currentPosition, to: targetPosition, speed: action.speed))

        case .forward:
            let targetPosition = Position3D(
                x: currentPosition.x + sceneSpace.forward.x * moveDistance,
                y: currentPosition.y,
                z: currentPosition.z + sceneSpace.forward.z * moveDistance
            )
            positions.append(targetPosition)
            durations.append(calculateDuration(from: currentPosition, to: targetPosition, speed: action.speed))

        case .backward:
            let targetPosition = Position3D(
                x: currentPosition.x - sceneSpace.forward.x * moveDistance,
                y: currentPosition.y,
                z: currentPosition.z - sceneSpace.forward.z * moveDistance
            )
            positions.append(targetPosition)
            durations.append(calculateDuration(from: currentPosition, to: targetPosition, speed: action.speed))

        case .toTarget:
            // Handled in approach
            break
        }

        return (positions, durations)
    }

    private func handleApproach(
        to targetPosition: Position3D,
        currentPosition: Position3D,
        speed: Float
    ) -> ([Position3D], [Double]) {
        // Подходим к объекту на расстояние 0.5м
        let delta = simd_float3(
            targetPosition.x - currentPosition.x,
            0,
            targetPosition.z - currentPosition.z
        )
        let distance = simd_length(delta)
        guard distance.isFinite, distance > 0.01 else {
            return ([currentPosition], [0.2])
        }

        let direction = delta / distance

        let finalPosition = Position3D(
            x: targetPosition.x - direction.x * 0.5,
            y: currentPosition.y,
            z: targetPosition.z - direction.z * 0.5
        )

        let duration = calculateDuration(from: currentPosition, to: finalPosition, speed: speed)

        return ([finalPosition], [duration])
    }

    private func handleContextualApproach(
        action: SceneAction,
        to targetPosition: Position3D,
        targetObject: PlannedScene.PlacedObject?,
        currentPosition: Position3D,
        placedObjects: [PlannedScene.PlacedObject],
        speed: Float
    ) -> ([Position3D], [Double]) {
        if sourceTextIndicatesOppositeSide(action.sourceText),
           let finalPosition = oppositeSideApproachPosition(
            for: targetPosition,
            targetObject: targetObject,
            currentPosition: currentPosition,
            placedObjects: placedObjects
           ) {
            return handleMove(to: finalPosition, currentPosition: currentPosition, speed: speed)
        }

        return handleApproach(to: targetPosition, currentPosition: currentPosition, speed: speed)
    }

    private func handleMove(
        to finalPosition: Position3D,
        currentPosition: Position3D,
        speed: Float
    ) -> ([Position3D], [Double]) {
        let duration = calculateDuration(from: currentPosition, to: finalPosition, speed: speed)
        return ([finalPosition], [duration])
    }

    private func handleEnter(
        currentPosition: Position3D,
        sceneSpace: SceneSpace,
        speed: Float
    ) -> ([Position3D], [Double]) {
        let towardCenter = simd_float3(
            sceneSpace.center.x - currentPosition.x,
            0,
            sceneSpace.center.z - currentPosition.z
        )
        let distanceToCenter = simd_length(towardCenter)
        let direction: simd_float3
        if distanceToCenter.isFinite, distanceToCenter > 0.05 {
            direction = towardCenter / distanceToCenter
        } else {
            direction = simd_float3(sceneSpace.forward.x, 0, sceneSpace.forward.z)
        }

        let moveDistance = min(max(distanceToCenter * 0.35, 0.45), 0.85)
        let targetPosition = Position3D(
            x: currentPosition.x + direction.x * moveDistance,
            y: currentPosition.y,
            z: currentPosition.z + direction.z * moveDistance
        )
        return handleMove(to: targetPosition, currentPosition: currentPosition, speed: speed)
    }

    private func oppositeSideApproachPosition(
        for targetPosition: Position3D,
        targetObject: PlannedScene.PlacedObject?,
        currentPosition: Position3D,
        placedObjects: [PlannedScene.PlacedObject]
    ) -> Position3D? {
        let supportObject = supportObject(for: targetObject, near: targetPosition, placedObjects: placedObjects)
        let anchor = supportObject?.position ?? targetPosition
        let fromAnchor = simd_float3(currentPosition.x - anchor.x, 0, currentPosition.z - anchor.z)
        let distance = simd_length(fromAnchor)
        guard distance.isFinite, distance > 0.05 else { return nil }

        let awayFromCurrent = -(fromAnchor / distance)
        let clearance = max(max(supportObject?.size.x ?? 0.4, supportObject?.size.z ?? 0.4) / 2 + 0.55, 0.85)
        return Position3D(
            x: anchor.x + awayFromCurrent.x * clearance,
            y: currentPosition.y,
            z: anchor.z + awayFromCurrent.z * clearance
        )
    }

    private func supportObject(
        for targetObject: PlannedScene.PlacedObject?,
        near targetPosition: Position3D,
        placedObjects: [PlannedScene.PlacedObject]
    ) -> PlannedScene.PlacedObject? {
        if targetObject?.type == .table {
            return targetObject
        }
        return placedObjects
            .filter { $0.type == .table && horizontalDistance($0.position, targetPosition) < 0.85 }
            .min { horizontalDistance($0.position, targetPosition) < horizontalDistance($1.position, targetPosition) }
    }

    private func horizontalDistance(_ lhs: Position3D, _ rhs: Position3D) -> Float {
        let dx = lhs.x - rhs.x
        let dz = lhs.z - rhs.z
        return sqrt(dx * dx + dz * dz)
    }

    private func sourceTextIndicatesApproach(_ text: String?) -> Bool {
        let lowercased = text?.lowercased() ?? ""
        return [
            "подходит",
            "подош",
            "приближается",
            "идёт к",
            "идет к",
            "входит",
            "обходит",
        ].contains { lowercased.contains($0) }
    }

    private func sourceTextIndicatesOppositeSide(_ text: String?) -> Bool {
        let lowercased = text?.lowercased() ?? ""
        return [
            "с другой стороны",
            "с противоположной стороны",
            "по другую сторону",
            "обходит",
        ].contains { lowercased.contains($0) }
    }

    private func handlePassBy(
        object objectPosition: Position3D,
        currentPosition: Position3D,
        sceneSpace: SceneSpace,
        speed: Float
    ) -> ([Position3D], [Double]) {

        var positions: [Position3D] = []
        var durations: [Double] = []

        // Точка "мимо объекта" - проходим сбоку
        let passByOffset: Float = 0.8

        // Определяем направление обхода (справа от объекта)
        let toObject = simd_normalize(simd_float3(
            objectPosition.x - currentPosition.x,
            0,
            objectPosition.z - currentPosition.z
        ))
        let perpendicular = simd_float3(-toObject.z, 0, toObject.x)

        // Точка рядом с объектом
        let nearObjectPosition = Position3D(
            x: objectPosition.x + perpendicular.x * passByOffset,
            y: currentPosition.y,
            z: objectPosition.z + perpendicular.z * passByOffset
        )
        positions.append(nearObjectPosition)
        durations.append(calculateDuration(from: currentPosition, to: nearObjectPosition, speed: speed))

        // Точка за объектом
        let pastObjectPosition = Position3D(
            x: objectPosition.x + toObject.x * 1.5 + perpendicular.x * passByOffset,
            y: currentPosition.y,
            z: objectPosition.z + toObject.z * 1.5 + perpendicular.z * passByOffset
        )
        positions.append(pastObjectPosition)
        durations.append(calculateDuration(from: nearObjectPosition, to: pastObjectPosition, speed: speed))

        return (positions, durations)
    }

    private func calculateDuration(from: Position3D, to: Position3D, speed: Float) -> Double {
        let distance = from.distance(to: to)
        guard distance.isFinite else { return 0.1 }
        if distance < 0.01 { return 0.1 }

        let safeSpeed = max(speed.isFinite ? speed : 0, 0.05)
        let duration = Double(distance / safeSpeed)

        if !duration.isFinite || duration.isNaN {
            return 0.1
        }

        return max(duration, minimumVisibleMovementDuration)
    }
}
