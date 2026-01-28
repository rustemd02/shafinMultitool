//
//  SceneSaveLoadTests.swift
//  shafinMultitoolTests
//
//  Created by AI Assistant
//

import XCTest
import ARKit
@testable import shafinMultitool

final class SceneSaveLoadTests: XCTestCase {
    
    var dbService: DBService!
    var testSceneName: String!
    
    override func setUpWithError() throws {
        super.setUp()
        dbService = DBService.shared
        testSceneName = "TestScene_\(UUID().uuidString)"
        
        // Очистка тестовых данных перед каждым тестом
        cleanupTestScene()
    }
    
    override func tearDownWithError() throws {
        cleanupTestScene()
        testSceneName = nil
        dbService = nil
        super.tearDown()
    }
    
    private func cleanupTestScene() {
        if let sceneName = testSceneName {
            dbService.deleteMap(with: sceneName) { _ in }
        }
    }
    
    // MARK: - Тест 1: Сохранение AR World Map с корректными данными
    
    func testSaveARWorldMapWithValidData() throws {
        // Создаем тестовые данные
        let sceneData = SceneData(
            name: testSceneName,
            actors: [
                ActorData(id: 1, name: "Актер1", red: 0.5, green: 0.3, blue: 0.8, alpha: 1.0),
                ActorData(id: 2, name: "Актер2", red: 0.2, green: 0.9, blue: 0.1, alpha: 1.0)
            ],
            script: "Иван: Привет. Мария: Как дела?"
        )
        
        // Создаем минимальный ARWorldMap (в реальности это требует AR сессии)
        // Для теста используем nil, так как создание реального ARWorldMap требует AR сессии
        let arWorldMap: ARWorldMap? = nil
        
        // Проверяем, что метод не падает с nil
        XCTAssertNoThrow(
            try dbService.saveARWorldMap(map: arWorldMap, sceneData: sceneData),
            "Сохранение не должно вызывать ошибку даже с nil map"
        )
        
        // Проверяем, что SceneData сохранилась
        if let loaded = dbService.loadARWorldMap(sceneName: testSceneName) {
            XCTAssertEqual(loaded.1.name, sceneData.name, "Имя сцены должно совпадать")
            XCTAssertEqual(loaded.1.script, sceneData.script, "Сценарий должен совпадать")
            XCTAssertEqual(loaded.1.actors?.count, sceneData.actors?.count, "Количество актеров должно совпадать")
        }
    }
    
    // MARK: - Тест 2: Загрузка существующей карты
    
    func testLoadExistingMap() throws {
        let sceneData = SceneData(
            name: testSceneName,
            actors: [ActorData(id: 1, name: "Тестовый актер", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)],
            script: "Тестовый сценарий"
        )
        
        // Сохраняем
        try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
        
        // Загружаем
        let loaded = dbService.loadARWorldMap(sceneName: testSceneName)
        
        XCTAssertNotNil(loaded, "Загруженные данные не должны быть nil")
        XCTAssertEqual(loaded?.1.name, sceneData.name, "Имя должно совпадать")
        XCTAssertEqual(loaded?.1.script, sceneData.script, "Сценарий должен совпадать")
        XCTAssertEqual(loaded?.1.actors?.first?.name, sceneData.actors?.first?.name, "Имя актера должно совпадать")
    }
    
    // MARK: - Тест 3: Загрузка несуществующей карты
    
    func testLoadNonExistentMap() throws {
        let nonExistentName = "NonExistentScene_\(UUID().uuidString)"
        let loaded = dbService.loadARWorldMap(sceneName: nonExistentName)
        
        XCTAssertNil(loaded, "Загрузка несуществующей карты должна возвращать nil")
    }
    
    // MARK: - Тест 4: Сохранение SceneData вместе с картой
    
    func testSaveSceneDataWithMap() throws {
        let actors = [
            ActorData(id: 1, name: "Актер1", red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
            ActorData(id: 2, name: "Актер2", red: 0.8, green: 0.2, blue: 0.3, alpha: 1.0)
        ]
        
        let sceneData = SceneData(
            name: testSceneName,
            actors: actors,
            script: "Длинный сценарий с множеством реплик. Иван: Привет. Мария: Как дела?"
        )
        
        try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
        
        if let loaded = dbService.loadARWorldMap(sceneName: testSceneName) {
            let loadedSceneData = loaded.1
            
            XCTAssertEqual(loadedSceneData.name, sceneData.name)
            XCTAssertEqual(loadedSceneData.script, sceneData.script)
            XCTAssertEqual(loadedSceneData.actors?.count, actors.count)
            
            if let loadedActors = loadedSceneData.actors {
                XCTAssertEqual(loadedActors[0].name, actors[0].name)
                XCTAssertEqual(loadedActors[0].id, actors[0].id)
                XCTAssertEqual(loadedActors[1].name, actors[1].name)
                XCTAssertEqual(loadedActors[1].id, actors[1].id)
            }
        } else {
            XCTFail("Не удалось загрузить сохраненные данные")
        }
    }
    
    // MARK: - Тест 5: Получение списка всех названий сцен
    
    func testGetAllSceneNames() throws {
        // Создаем несколько тестовых сцен
        let scene1Name = "TestScene1_\(UUID().uuidString)"
        let scene2Name = "TestScene2_\(UUID().uuidString)"
        
        let scene1 = SceneData(name: scene1Name, actors: nil, script: "Сценарий 1")
        let scene2 = SceneData(name: scene2Name, actors: nil, script: "Сценарий 2")
        
        try dbService.saveARWorldMap(map: nil, sceneData: scene1)
        try dbService.saveARWorldMap(map: nil, sceneData: scene2)
        
        let sceneNames = dbService.getAllARWorldMapTitles()
        
        XCTAssertNotNil(sceneNames, "Список сцен не должен быть nil")
        XCTAssertTrue(sceneNames?.contains(scene1Name) ?? false, "Должна содержаться сцена 1")
        XCTAssertTrue(sceneNames?.contains(scene2Name) ?? false, "Должна содержаться сцена 2")
        
        // Очистка
        dbService.deleteMap(with: scene1Name) { _ in }
        dbService.deleteMap(with: scene2Name) { _ in }
    }
    
    // MARK: - Тест 6: Удаление существующей сцены
    
    func testDeleteExistingScene() throws {
        let sceneData = SceneData(
            name: testSceneName,
            actors: nil,
            script: "Тестовый сценарий"
        )
        
        // Сохраняем
        try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
        
        // Проверяем, что сцена существует
        let beforeDelete = dbService.loadARWorldMap(sceneName: testSceneName)
        XCTAssertNotNil(beforeDelete, "Сцена должна существовать перед удалением")
        
        // Удаляем
        let expectation = XCTestExpectation(description: "Удаление сцены")
        dbService.deleteMap(with: testSceneName) { deleted in
            XCTAssertTrue(deleted, "Удаление должно быть успешным")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Проверяем, что сцена удалена
        let afterDelete = dbService.loadARWorldMap(sceneName: testSceneName)
        XCTAssertNil(afterDelete, "Сцена должна быть удалена")
    }
    
    // MARK: - Тест 7: Удаление несуществующей сцены
    
    func testDeleteNonExistentScene() throws {
        let nonExistentName = "NonExistentScene_\(UUID().uuidString)"
        
        let expectation = XCTestExpectation(description: "Удаление несуществующей сцены")
        dbService.deleteMap(with: nonExistentName) { deleted in
            // Удаление несуществующей сцены не должно вызывать ошибку
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Тест 8: Создание директории для сцен
    
    func testCreateScenesDirectory() throws {
        // Метод createARMapsDirectory вызывается внутри других методов
        // Проверяем, что он работает корректно, пытаясь сохранить сцену
        let sceneData = SceneData(name: testSceneName, actors: nil, script: "Тест")
        
        XCTAssertNoThrow(
            try dbService.saveARWorldMap(map: nil, sceneData: sceneData),
            "Директория должна создаваться автоматически"
        )
    }
    
    // MARK: - Тест 9: Сохранение сцены без актеров
    
    func testSaveSceneWithoutActors() throws {
        let sceneData = SceneData(
            name: testSceneName,
            actors: nil,
            script: "Сценарий без актеров"
        )
        
        try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
        
        if let loaded = dbService.loadARWorldMap(sceneName: testSceneName) {
            XCTAssertNil(loaded.1.actors, "Актеры должны быть nil")
            XCTAssertEqual(loaded.1.script, sceneData.script)
        } else {
            XCTFail("Не удалось загрузить сцену")
        }
    }
    
//    // MARK: - Тест 10: Сохранение сцены без сценария
//    
//    func testSaveSceneWithoutScript() throws {
//        let sceneData = SceneData(
//            name: testSceneName,
//            actors: [ActorData(id: 1, name: "Актер", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)],
//            script: nil
//        )
//        
//        try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
//        
//        if let loaded = dbService.loadARWorldMap(sceneName: testSceneName) {
//            XCTAssertNil(loaded.1.script, "Сценарий должен быть nil")
//            XCTAssertNotNil(loaded.1.actors, "Актеры должны существовать")
//        } else {
//            XCTFail("Не удалось загрузить сцену")
//        }
//    }
    
    // MARK: - Тест 11: Сохранение актеров с якорями
    
    func testSaveActorsWithAnchors() throws {
        let anchorID1 = UUID()
        let anchorID2 = UUID()
        
        var actor1 = ActorData(id: 1, name: "Актер1", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        actor1.anchorIDs = [anchorID1, anchorID2]
        
        let sceneData = SceneData(
            name: testSceneName,
            actors: [actor1],
            script: "Тест"
        )
        
        try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
        
        if let loaded = dbService.loadARWorldMap(sceneName: testSceneName),
           let loadedActor = loaded.1.actors?.first {
            XCTAssertEqual(loadedActor.anchorIDs.count, 2, "Должно быть 2 якоря")
            XCTAssertEqual(loadedActor.anchorIDs[0], anchorID1)
            XCTAssertEqual(loadedActor.anchorIDs[1], anchorID2)
        } else {
            XCTFail("Не удалось загрузить актера с якорями")
        }
    }
    
    // MARK: - Тест 12: Целостность данных при множественных сохранениях
    
    func testDataIntegrityOnMultipleSaves() throws {
        let initialSceneData = SceneData(
            name: testSceneName,
            actors: [ActorData(id: 1, name: "Актер1", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)],
            script: "Первый сценарий"
        )
        
        try dbService.saveARWorldMap(map: nil, sceneData: initialSceneData)
        
        // Обновляем сцену
        let updatedSceneData = SceneData(
            name: testSceneName,
            actors: [
                ActorData(id: 1, name: "Актер1", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
                ActorData(id: 2, name: "Актер2", red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
            ],
            script: "Обновленный сценарий"
        )
        
        try dbService.saveARWorldMap(map: nil, sceneData: updatedSceneData)
        
        if let loaded = dbService.loadARWorldMap(sceneName: testSceneName) {
            XCTAssertEqual(loaded.1.actors?.count, 2, "Должно быть 2 актера после обновления")
            XCTAssertEqual(loaded.1.script, "Обновленный сценарий", "Сценарий должен быть обновлен")
        } else {
            XCTFail("Не удалось загрузить обновленную сцену")
        }
    }
}
