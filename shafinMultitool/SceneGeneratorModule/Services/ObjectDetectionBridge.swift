//
//  ObjectDetectionBridge.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import Foundation
import CoreVideo
import ARKit
import RealityKit

/// Мост между DETRDetector и SceneGenerator модулем
/// Обеспечивает распознавание объектов в кадре и их привязку к 3D координатам
final class ObjectDetectionBridge {
    
    static let shared = ObjectDetectionBridge()
    
    // MARK: - Properties
    
    private var detector: DETRDetector?
    private let processingQueue = DispatchQueue(label: "ObjectDetectionBridge.processing", qos: .userInitiated)
    
    /// Кэш последних обнаруженных объектов
    private(set) var lastDetections: [DetectedObject] = []
    
    /// Время последнего обновления детекций
    private var lastDetectionTime: Date = .distantPast
    
    /// Минимальный интервал между детекциями (в секундах)
    private let detectionInterval: TimeInterval = 0.5
    
    /// Минимальная уверенность для принятия детекции
    private let minimumConfidence: Float = 0.3
    
    // MARK: - Initialization
    
    private init() {
        initializeDetector()
    }
    
    private func initializeDetector() {
        processingQueue.async { [weak self] in
            do {
                self?.detector = try DETRDetector()
                print("✅ ObjectDetectionBridge: DETRDetector initialized successfully")
            } catch {
                print("⚠️ ObjectDetectionBridge: Failed to initialize DETRDetector: \(error.localizedDescription)")
                // Продолжаем работу без детектора - будем использовать placeholder позиции
            }
        }
    }
    
    // MARK: - Public API
    
    /// Проверяет, готов ли детектор к работе
    var isReady: Bool {
        detector != nil
    }
    
    /// Выполняет детекцию объектов на кадре
    /// - Parameters:
    ///   - pixelBuffer: Буфер с изображением
    ///   - arFrame: AR кадр для получения 3D координат
    ///   - completion: Callback с обнаруженными объектами
    func detectObjects(
        in pixelBuffer: CVPixelBuffer,
        arFrame: ARFrame?,
        completion: @escaping ([DetectedObject]) -> Void
    ) {
        // Проверяем интервал между детекциями
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= detectionInterval else {
            completion(lastDetections)
            return
        }
        
        guard let detector = detector else {
            print("⚠️ ObjectDetectionBridge: Detector not initialized")
            completion([])
            return
        }
        
        lastDetectionTime = now
        
        detector.detect(pixelBuffer: pixelBuffer, orientation: .right) { [weak self] detections in
            guard let self = self else { return }
            
            let filteredDetections = detections
                .filter { $0.confidence >= self.minimumConfidence }
                .compactMap { detection -> DetectedObject? in
                    self.convertToDetectedObject(detection, arFrame: arFrame)
                }
            
            DispatchQueue.main.async {
                self.lastDetections = filteredDetections
                completion(filteredDetections)
            }
        }
    }
    
    /// Находит объект определённого типа среди обнаруженных
    /// - Parameter type: Тип объекта для поиска
    /// - Returns: Обнаруженный объект или nil
    func findObject(ofType type: SceneObject.ObjectType) -> DetectedObject? {
        return lastDetections.first { detection in
            type.cocoLabels.contains { $0.lowercased() == detection.label.lowercased() }
        }
    }
    
    /// Находит все объекты определённого типа
    func findAllObjects(ofType type: SceneObject.ObjectType) -> [DetectedObject] {
        return lastDetections.filter { detection in
            type.cocoLabels.contains { $0.lowercased() == detection.label.lowercased() }
        }
    }
    
    /// Сопоставляет объекты из SceneScript с обнаруженными объектами
    /// - Parameters:
    ///   - sceneObjects: Объекты из распознанного скрипта
    ///   - arFrame: AR кадр для получения 3D координат
    /// - Returns: Обновлённые объекты с позициями из детекций
    func matchObjectsWithDetections(
        _ sceneObjects: [SceneObject],
        arFrame: ARFrame?
    ) -> [SceneObject] {
        return sceneObjects.map { sceneObject in
            var updatedObject = sceneObject
            
            // Ищем соответствующую детекцию
            if let detection = findObject(ofType: sceneObject.type) {
                updatedObject.detectedPosition = detection.worldPosition
            }
            
            return updatedObject
        }
    }
    
    /// Получает 3D позицию объекта через raycast
    /// - Parameters:
    ///   - boundingBox: Нормализованный bounding box (0...1)
    ///   - arView: AR View для raycast
    /// - Returns: 3D позиция или nil
    func getWorldPosition(
        for boundingBox: CGRect,
        in arView: ARView
    ) -> Position3D? {
        // Вычисляем центр bounding box
        let centerX = boundingBox.midX
        let centerY = 1.0 - boundingBox.midY  // Инвертируем Y для координат экрана
        
        // Конвертируем в координаты экрана
        let screenPoint = CGPoint(
            x: centerX * arView.bounds.width,
            y: centerY * arView.bounds.height
        )
        
        // Выполняем raycast
        let results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .horizontal)
        
        if let firstResult = results.first {
            let position = firstResult.worldTransform.columns.3
            return Position3D(x: position.x, y: position.y, z: position.z)
        }
        
        return nil
    }
    
    /// Очищает кэш детекций
    func clearCache() {
        lastDetections = []
        lastDetectionTime = .distantPast
    }
    
    // MARK: - Private Methods
    
    private func convertToDetectedObject(_ detection: DETRDetection, arFrame: ARFrame?) -> DetectedObject? {
        // Фильтруем нерелевантные классы
        let relevantLabels = Set(SceneObject.ObjectType.allCases.flatMap { $0.cocoLabels })
        guard relevantLabels.contains(where: { $0.lowercased() == detection.label.lowercased() }) else {
            return nil
        }
        
        // Создаём DetectedObject
        var detectedObject = DetectedObject(
            id: detection.id,
            label: detection.label,
            confidence: detection.confidence,
            boundingBox: detection.boundingBox,
            worldPosition: nil
        )
        
        // Пытаемся получить 3D позицию через ARFrame
        if let arFrame = arFrame {
            detectedObject.worldPosition = estimateWorldPosition(
                boundingBox: detection.boundingBox,
                arFrame: arFrame
            )
        }
        
        return detectedObject
    }
    
    private func estimateWorldPosition(boundingBox: CGRect, arFrame: ARFrame) -> Position3D? {
        // Вычисляем центр bounding box
        let centerX = boundingBox.midX
        let centerY = boundingBox.midY
        
        // Получаем размер изображения
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(arFrame.capturedImage),
            height: CVPixelBufferGetHeight(arFrame.capturedImage)
        )
        
        // Конвертируем в нормализованные координаты камеры (0...1)
        let normalizedPoint = CGPoint(x: centerX, y: centerY)
        
        // Используем ARFrame для получения примерной глубины
        // Это упрощённая оценка - для точности нужен LiDAR или depth estimation
        
        // Получаем матрицу проекции камеры
        let intrinsics = arFrame.camera.intrinsics
        let viewMatrix = arFrame.camera.viewMatrix(for: .landscapeRight)
        
        // Оцениваем расстояние на основе размера bounding box
        // Чем больше bbox, тем ближе объект
        let estimatedDistance = estimateDistance(boundingBoxSize: boundingBox.size)
        
        // Вычисляем 3D позицию
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]
        
        // Координаты в пикселях
        let pixelX = Float(normalizedPoint.x * imageSize.width)
        let pixelY = Float(normalizedPoint.y * imageSize.height)
        
        // Обратная проекция
        let x = (pixelX - cx) * estimatedDistance / fx
        let y = (pixelY - cy) * estimatedDistance / fy
        let z = -estimatedDistance  // Отрицательный Z в координатах камеры
        
        // Конвертируем из координат камеры в мировые координаты
        let cameraPosition = simd_float4(x, y, z, 1.0)
        let worldPosition = simd_mul(simd_inverse(viewMatrix), cameraPosition)
        
        return Position3D(x: worldPosition.x, y: 0, z: worldPosition.z)  // Y = 0 для горизонтальной плоскости
    }
    
    private func estimateDistance(boundingBoxSize: CGSize) -> Float {
        // Эвристика: чем больше bbox, тем ближе объект
        // Это очень грубая оценка
        let averageSize = Float((boundingBoxSize.width + boundingBoxSize.height) / 2)
        
        // Примерная зависимость: bbox 0.5 = 1м, bbox 0.25 = 2м, bbox 0.125 = 4м
        let baseDistance: Float = 1.0
        let baseSize: Float = 0.5
        
        if averageSize > 0.01 {
            return baseDistance * (baseSize / averageSize)
        }
        
        return 3.0  // Значение по умолчанию - 3 метра
    }
}

// MARK: - Russian Label Mapping Extension

extension ObjectDetectionBridge {
    
    /// Возвращает русское название для COCO label
    func russianLabel(for cocoLabel: String) -> String {
        return KeywordsMapping.cocoToRussian[cocoLabel.lowercased()] ?? cocoLabel
    }
    
    /// Возвращает все обнаруженные объекты с русскими названиями
    func detectedObjectsWithRussianLabels() -> [(object: DetectedObject, russianLabel: String)] {
        return lastDetections.map { detection in
            (detection, russianLabel(for: detection.label))
        }
    }
}

// MARK: - Scene Object Matching

extension ObjectDetectionBridge {
    
    /// Создаёт SceneObject из обнаруженного объекта
    func createSceneObject(from detection: DetectedObject, id: String) -> SceneObject? {
        guard let objectType = detection.objectType else { return nil }
        
        let relativePosition = determineRelativePosition(from: detection.boundingBox)
        
        return SceneObject(
            id: id,
            type: objectType,
            detectedPosition: detection.worldPosition,
            relativePosition: relativePosition
        )
    }
    
    private func determineRelativePosition(from boundingBox: CGRect) -> SceneObject.RelativePosition {
        let centerX = boundingBox.midX
        
        if centerX < 0.33 {
            return .left
        } else if centerX > 0.66 {
            return .right
        } else {
            return .center
        }
    }
}

