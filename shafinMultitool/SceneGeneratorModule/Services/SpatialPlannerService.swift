//
//  SpatialPlannerService.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import Foundation
import simd
import ARKit

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
    
    private init() {}
    
    // MARK: - Public API
    
    /// Планирует размещение всех элементов сцены
    /// - Parameters:
    ///   - script: Распознанный скрипт сцены
    ///   - cameraTransform: Текущая позиция и ориентация камеры
    ///   - detectedObjects: Обнаруженные объекты в кадре
    ///   - availablePlanes: Доступные горизонтальные плоскости
    ///   - markedObjects: Размеченные пользователем объекты (высший приоритет)
    /// - Returns: PlannedScene с готовыми координатами
    func planScene(
        script: SceneScript,
        cameraTransform: simd_float4x4,
        detectedObjects: [DetectedObject],
        availablePlanes: [ARPlaneAnchor],
        markedObjects: [MarkedObject] = []
    ) -> PlannedScene {
        print("🔍 [PLANNER] === НАЧАЛО ПЛАНИРОВАНИЯ ===")
        print("🔍 [PLANNER] Входные данные: actors=\(script.actors.count), objects=\(script.objects.count), actions=\(script.actions.count), detectedObjects=\(detectedObjects.count), markedObjects=\(markedObjects.count)")
        
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
        planes: [ARPlaneAnchor]
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
        if let lowestPlane = planes.filter({ $0.alignment == .horizontal }).min(by: { $0.transform.columns.3.y < $1.transform.columns.3.y }) {
            floorY = lowestPlane.transform.columns.3.y
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
        
        return scriptObjects.enumerated().map { index, scriptObject in
            print("🔍 [PLANNER] Обработка scriptObject[\(index)]: id='\(scriptObject.id)', type=\(scriptObject.type.rawValue), detectedPosition=\(scriptObject.detectedPosition != nil ? "YES" : "NO")")
            let position: Position3D
            let placementSource: PlannedScene.PlacedObject.PlacementSource
            var isDetected = false
            
            // 1. ВЫСШИЙ ПРИОРИТЕТ: Ручные метки пользователя
            if let markedObject = markedObjects.first(where: { $0.type == scriptObject.type }) {
                print("🔍 [PLANNER]   Найден markedObject для type=\(scriptObject.type.rawValue): id=\(markedObject.id.uuidString)")
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
            // 4. Создаём виртуальный объект
            else {
                print("🔍 [PLANNER]   Создаётся виртуальный объект для type=\(scriptObject.type.rawValue)")
                position = generateObjectPosition(
                    for: scriptObject,
                    index: index,
                    sceneSpace: sceneSpace
                )
                placementSource = .virtual
            }
            
            return PlannedScene.PlacedObject(
                id: "placed_\(scriptObject.id)",
                objectId: scriptObject.id,
                type: scriptObject.type,
                position: position,
                rotation: 0,
                isDetected: isDetected,
                placementSource: placementSource
            )
        }
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
        actions: [SceneAction],
        relations: [SpatialRelation],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> [PlannedScene.PlacedActor] {
        print("🔍 [PLANNER] planActors: scriptActors=\(scriptActors.count), actions=\(actions.count), relations=\(relations.count)")
        
        // Определяем начальные позиции
        var initialPositions = calculateInitialPositions(
            actors: scriptActors,
            actions: actions,
            placedObjects: placedObjects,
            sceneSpace: sceneSpace
        )
        print("🔍 [PLANNER] Вычислено начальных позиций: \(initialPositions.count)")
        
        // Строим траектории для каждого актёра
        return scriptActors.enumerated().map { index, actor in
            print("🔍 [PLANNER] Обработка scriptActor[\(index)]: id='\(actor.id)', type=\(actor.type.rawValue)")
            let initialPosition = initialPositions[index]
            let actorActions = actions.filter { $0.actorId == actor.id }
            
            // Вычисляем начальную ротацию (смотрим в центр сцены)
            let lookAtCenter = simd_float3(
                sceneSpace.center.x - initialPosition.x,
                0,
                sceneSpace.center.z - initialPosition.z
            )
            let initialRotation = atan2(lookAtCenter.x, lookAtCenter.z)
            
            // Строим траекторию
            let (path, durations) = buildPath(
                for: actor,
                startPosition: initialPosition,
                actions: actorActions,
                allActors: scriptActors,
                initialPositions: initialPositions,
                placedObjects: placedObjects,
                sceneSpace: sceneSpace
            )
            
            return PlannedScene.PlacedActor(
                id: "placed_\(actor.id)",
                actorId: actor.id,
                type: actor.type,
                name: actor.name,
                initialPosition: initialPosition,
                initialRotation: initialRotation,
                path: path,
                pathDurations: durations
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
        for i in 2..<actorCount {
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
    
    private func buildPath(
        for actor: SceneActor,
        startPosition: Position3D,
        actions: [SceneAction],
        allActors: [SceneActor],
        initialPositions: [Position3D],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> ([Position3D], [Double]) {
        
        var path: [Position3D] = [startPosition]
        var durations: [Double] = []
        var currentPosition = startPosition
        
        for action in actions {
            let (newPositions, newDurations) = processAction(
                action,
                currentPosition: currentPosition,
                allActors: allActors,
                initialPositions: initialPositions,
                placedObjects: placedObjects,
                sceneSpace: sceneSpace
            )
            
            path.append(contentsOf: newPositions)
            durations.append(contentsOf: newDurations)
            
            if let lastPosition = newPositions.last {
                currentPosition = lastPosition
            }
        }
        
        return (path, durations)
    }
    
    private func processAction(
        _ action: SceneAction,
        currentPosition: Position3D,
        allActors: [SceneActor],
        initialPositions: [Position3D],
        placedObjects: [PlannedScene.PlacedObject],
        sceneSpace: SceneSpace
    ) -> ([Position3D], [Double]) {
        
        var positions: [Position3D] = []
        var durations: [Double] = []
        
        // Helper: resolve target position from objects OR actors
        let resolvedTargetPosition: Position3D? = {
            guard let targetId = action.target else { return nil }
            // 1. Поиск среди объектов
            if let obj = placedObjects.first(where: { $0.objectId == targetId }) {
                return obj.position
            }
            // 2. Поиск среди актёров (например, pass_by с target: actor_1)
            if let actorIndex = allActors.firstIndex(where: { $0.id == targetId }),
               actorIndex < initialPositions.count {
                return initialPositions[actorIndex]
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
            }
            // Иначе используем направление
            else if let direction = action.direction {
                let (pos, dur) = handleDirectionalMovement(
                    direction: direction,
                    action: action,
                    currentPosition: currentPosition,
                    allActors: allActors,
                    initialPositions: initialPositions,
                    sceneSpace: sceneSpace
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
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
            }
            
        case .turn:
            // Поворот без перемещения — остаёмся на месте
            break
            
        case .stop:
            if let targetPos = resolvedTargetPosition {
                let (pos, dur) = handleApproach(
                    to: targetPos,
                    currentPosition: currentPosition,
                    speed: action.speed
                )
                positions.append(contentsOf: pos)
                durations.append(contentsOf: dur)
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
            }
            
        default:
            break
        }
        
        return (positions, durations)
    }
    
    private func handleDirectionalMovement(
        direction: SceneAction.Direction,
        action: SceneAction,
        currentPosition: Position3D,
        allActors: [SceneActor],
        initialPositions: [Position3D],
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
               let targetIndex = allActors.firstIndex(where: { $0.id == targetActorId }),
               targetIndex < initialPositions.count {
                let otherPos = initialPositions[targetIndex]
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
        let direction = simd_normalize(simd_float3(
            targetPosition.x - currentPosition.x,
            0,
            targetPosition.z - currentPosition.z
        ))
        
        let finalPosition = Position3D(
            x: targetPosition.x - direction.x * 0.5,
            y: currentPosition.y,
            z: targetPosition.z - direction.z * 0.5
        )
        
        let duration = calculateDuration(from: currentPosition, to: finalPosition, speed: speed)
        
        return ([finalPosition], [duration])
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
        return Double(distance / speed)
    }
}

