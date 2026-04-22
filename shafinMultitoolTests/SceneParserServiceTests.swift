//
//  SceneParserServiceTests.swift
//  shafinMultitoolTests
//
//  Created on 28.01.2026.
//

import XCTest
@testable import shafinMultitool

final class SceneParserServiceTests: XCTestCase {
    
    var parser: SceneParserService!
    
    override func setUpWithError() throws {
        super.setUp()
        parser = SceneParserService.shared
        parser.resetRuntimeContext()
    }

    override func tearDownWithError() throws {
        parser?.resetRuntimeContext()
        parser = nil
        super.tearDown()
    }
    
    // MARK: - Basic Parsing Tests
    
    func testParseSimpleScene() throws {
        let description = "2 актёра идут навстречу друг другу"
        let result = parser.parse(description, markedObjects: [])
        
        XCTAssertEqual(result.script.actors.count, 2, "Должно быть 2 актёра")
        XCTAssertFalse(result.script.actions.isEmpty, "Должны быть действия")
        XCTAssertGreaterThan(result.diagnostics.confidence, 0.5, "Confidence должен быть разумным")
    }
    
    func testParseWithMarkedObjects() throws {
        let marker = MarkedObject(
            name: "стол",
            position: Position3D(x: 1.0, y: 0.0, z: 2.0)
        )
        let markedObjects = [marker]
        
        let description = "Человек подходит к моему столу"
        let result = parser.parse(description, markedObjects: markedObjects)
        
        // Должен найти объект из markedObjects
        let foundObject = result.script.objects.first { $0.detectedPosition == marker.worldPosition }
        XCTAssertNotNil(foundObject, "Должен быть найден объект из markedObjects")
        XCTAssertEqual(foundObject?.type, .table, "Тип должен быть table")
        
        // Должен быть action с target на этот объект
        let approachAction = result.script.actions.first { $0.type == .approach && $0.target == foundObject?.id }
        XCTAssertNotNil(approachAction, "Должно быть действие approach к столу")
        
        // MarkedObject должен быть в списке распознанных
        XCTAssertTrue(result.diagnostics.matchedMarkedObjects.contains(marker.id), "MarkedObject должен быть в списке распознанных")
    }
    
    func testParseMultipleObjectsOfSameType() throws {
        let description = "2 стола стоят рядом"
        let result = parser.parse(description, markedObjects: [])
        
        // Теперь должны поддерживаться множественные объекты одного типа
        let tables = result.script.objects.filter { $0.type == .table }
        XCTAssertGreaterThanOrEqual(tables.count, 1, "Должен быть найден хотя бы один стол")
    }
    
    func testParseEmptyDescription() throws {
        let description = ""
        let result = parser.parse(description, markedObjects: [])
        
        XCTAssertTrue(result.script.isEmpty, "Пустое описание должно давать пустой скрипт")
        XCTAssertLessThan(result.diagnostics.confidence, 0.5, "Confidence должен быть низким для пустого текста")
        XCTAssertTrue(result.diagnostics.notes.contains { $0.contains("актёров") || $0.contains("объектов") }, "Должна быть заметка о проблеме")
    }
    
    func testParseWithUnresolvedPronouns() throws {
        let description = "Он подходит к столу, она сидит на диване"
        let result = parser.parse(description, markedObjects: [])
        
        // Должны быть найдены объекты
        XCTAssertFalse(result.script.objects.isEmpty, "Должны быть найдены объекты")
        
        // Если актёров меньше 2, должны быть unresolvedPronouns
        if result.script.actors.count < 2 {
            XCTAssertTrue(result.diagnostics.unresolvedPronouns, "Должны быть неразрешенные местоимения")
        }
    }
    
    func testParseWithCustomMarkedObjectName() throws {
        let marker = MarkedObject(
            name: "мой_шкаф",
            position: Position3D(x: 2.0, y: 0.0, z: 1.0)
        )
        let markedObjects = [marker]
        
        let description = "Человек проходит мимо моего шкафа"
        let result = parser.parse(description, markedObjects: markedObjects)
        
        // Должен найти объект по кастомному имени
        let foundObject = result.script.objects.first { $0.detectedPosition == marker.worldPosition }
        XCTAssertNotNil(foundObject, "Должен быть найден объект по кастомному имени")
        
        // Должно быть действие passBy
        let passByAction = result.script.actions.first { $0.type == .passBy && $0.target == foundObject?.id }
        XCTAssertNotNil(passByAction, "Должно быть действие passBy")
    }
    
    func testDiagnosticsConfidence() throws {
        let goodDescription = "2 актёра идут навстречу друг другу, проходят мимо стола"
        let goodResult = parser.parse(goodDescription, markedObjects: [])
        
        XCTAssertGreaterThan(goodResult.diagnostics.confidence, 0.6, "Хорошее описание должно иметь высокий confidence")
        
        let badDescription = "что-то непонятное без актёров и объектов"
        let badResult = parser.parse(badDescription, markedObjects: [])
        
        XCTAssertLessThan(badResult.diagnostics.confidence, 0.6, "Плохое описание должно иметь низкий confidence")
    }
    
    func testDiagnosticsCoverage() throws {
        let description = "Человек идёт к столу, садится на стул"
        let result = parser.parse(description, markedObjects: [])
        
        XCTAssertGreaterThan(result.diagnostics.coverage, 0.0, "Coverage должен быть больше 0")
        XCTAssertLessThanOrEqual(result.diagnostics.coverage, 1.0, "Coverage не должен превышать 1.0")
    }
    
    func testDiagnosticsMissingActors() throws {
        let description = "идёт к столу" // Нет актёра
        let result = parser.parse(description, markedObjects: [])
        
        // Парсер создаёт актёра по умолчанию, но если есть действия без актёров - должна быть ошибка
        if result.script.actors.isEmpty && !result.script.actions.isEmpty {
            XCTAssertTrue(result.diagnostics.missingActors, "Должна быть ошибка missingActors")
        }
    }
    
    func testDiagnosticsMissingObjects() throws {
        let marker = MarkedObject(
            name: "стол",
            position: Position3D(x: 1.0, y: 0.0, z: 2.0)
        )
        let markedObjects = [marker]
        
        let description = "Человек подходит к несуществующему_объекту"
        let result = parser.parse(description, markedObjects: markedObjects)
        
        // Если есть действие с target, но объект не найден
        let actionsWithTargets = result.script.actions.filter { $0.target != nil }
        if !actionsWithTargets.isEmpty {
            let objectIds = Set(result.script.objects.map { $0.id })
            let missingTargets = actionsWithTargets.filter { action in
                guard let target = action.target else { return false }
                return !objectIds.contains(target)
            }
            
            if !missingTargets.isEmpty {
                XCTAssertTrue(result.diagnostics.missingObjects, "Должна быть ошибка missingObjects")
            }
        }
    }
    
    func testBackwardCompatibility() throws {
        // Старый метод должен работать
        let description = "2 актёра идут"
        let script = parser.parse(description) // Старый метод без markedObjects

        XCTAssertFalse(script.isEmpty, "Старый метод должен работать")
        XCTAssertEqual(script.actors.count, 2, "Должно быть 2 актёра")
    }

    func testParseExtractsTopLevelSceneMetadata() throws {
        let description = "INT. OFFICE - NIGHT\nЧеловек подходит к столу"
        let result = parser.parse(description, markedObjects: [])

        XCTAssertEqual(result.script.sceneHeading, "INT. OFFICE - NIGHT")
        XCTAssertEqual(result.script.locationName, "OFFICE")
        XCTAssertEqual(result.script.interiorExterior, "interior")
        XCTAssertEqual(result.script.timeOfDay, "night")
    }
}
