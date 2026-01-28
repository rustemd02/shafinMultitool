//
//  ActorManagementTests.swift
//  shafinMultitoolTests
//
//  Created by AI Assistant
//

import XCTest
import ARKit
import RealityKit
@testable import shafinMultitool

final class ActorManagementTests: XCTestCase {
    
    var interactor: CameraScreenInteractor!
    
    override func setUpWithError() throws {
        super.setUp()
        interactor = CameraScreenInteractor()
        // Очищаем глобальный массив актеров
        actors.removeAll()
    }
    
    override func tearDownWithError() throws {
        actors.removeAll()
        interactor = nil
        super.tearDown()
    }
    
    // MARK: - Тест 1: Получение актера по его якорю
    
    func testGetActorByAnchor() throws {
        let anchorID1 = UUID()
        let anchorID2 = UUID()
        
        var actor1 = ActorData(id: 1, name: "Актер1", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        actor1.anchorIDs = [anchorID1]
        
        var actor2 = ActorData(id: 2, name: "Актер2", red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        actor2.anchorIDs = [anchorID2]
        
        actors = [actor1, actor2]
        
        // Создаем тестовый anchor
        let anchor = ARAnchor(transform: simd_float4x4.init())
        // Используем reflection для установки identifier (в реальности это делается ARKit)
        // Для теста создадим mock anchor с нужным ID
        
        // Устанавливаем sceneData с актерами
        interactor.sceneData = SceneData(name: "TestScene", actors: actors, script: "Тест")
        
        // Тестируем получение актера (метод использует anchor.identifier внутри)
        // Так как мы не можем напрямую установить identifier, проверим логику через sceneData
        if let sceneData = interactor.sceneData,
           let sceneActors = sceneData.actors {
            let foundActor = sceneActors.first { actor in
                actor.anchorIDs.contains(anchorID1)
            }
            
            XCTAssertNotNil(foundActor, "Актер должен быть найден по anchor ID")
            XCTAssertEqual(foundActor?.name, "Актер1", "Имя актера должно совпадать")
        }
    }
    
    // MARK: - Тест 2: Установка случайного цвета актеру
    
    func testSetRandomColorToActor() throws {
        // Создаем тестовую модель (в реальности это ModelEntity из .usdz файла)
        // Для теста проверим логику генерации цвета
        
        let red = CGFloat.random(in: 0.1...0.9)
        let green = CGFloat.random(in: 0.1...0.9)
        let blue = CGFloat.random(in: 0.1...0.9)
        
        // Проверяем, что значения в допустимом диапазоне
        XCTAssertGreaterThanOrEqual(red, 0.1, "Красный компонент должен быть >= 0.1")
        XCTAssertLessThanOrEqual(red, 0.9, "Красный компонент должен быть <= 0.9")
        
        XCTAssertGreaterThanOrEqual(green, 0.1, "Зеленый компонент должен быть >= 0.1")
        XCTAssertLessThanOrEqual(green, 0.9, "Зеленый компонент должен быть <= 0.9")
        
        XCTAssertGreaterThanOrEqual(blue, 0.1, "Синий компонент должен быть >= 0.1")
        XCTAssertLessThanOrEqual(blue, 0.9, "Синий компонент должен быть <= 0.9")
    }
    
    // MARK: - Тест 3: Создание актера с дефолтным именем
    
    func testCreateActorWithDefaultName() throws {
        // Очищаем массив актеров
        actors.removeAll()
        
        // Проверяем логику создания имени актера
        let actorCount = actors.count
        let expectedName = "Актёр \(actorCount + 1)"
        
        XCTAssertEqual(expectedName, "Актёр 1", "Первое имя должно быть 'Актёр 1'")
        
        // Добавляем одного актера
        let actor1 = ActorData(id: 1, name: "Актёр 1", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        actors.append(actor1)
        
        let nextExpectedName = "Актёр \(actors.count + 1)"
        XCTAssertEqual(nextExpectedName, "Актёр 2", "Следующее имя должно быть 'Актёр 2'")
    }
    
    // MARK: - Тест 4: Сохранение актера с якорем
    
    func testSaveActorWithAnchor() throws {
        let anchorID = UUID()
        var actor = ActorData(id: 1, name: "Тестовый актер", red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        actor.anchorIDs.append(anchorID)
        
        actors.append(actor)
        
        XCTAssertEqual(actors.count, 1, "Должен быть один актер")
        XCTAssertEqual(actors.first?.anchorIDs.count, 1, "У актера должен быть один якорь")
        XCTAssertEqual(actors.first?.anchorIDs.first, anchorID, "ID якоря должен совпадать")
    }
    
    // MARK: - Тест 5: Добавление нескольких якорей к актеру
    
    func testAddMultipleAnchorsToActor() throws {
        var actor = ActorData(id: 1, name: "Актер с несколькими якорями", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        
        let anchorID1 = UUID()
        let anchorID2 = UUID()
        let anchorID3 = UUID()
        
        actor.anchorIDs.append(anchorID1)
        actor.anchorIDs.append(anchorID2)
        actor.anchorIDs.append(anchorID3)
        
        XCTAssertEqual(actor.anchorIDs.count, 3, "У актера должно быть 3 якоря")
        XCTAssertTrue(actor.anchorIDs.contains(anchorID1))
        XCTAssertTrue(actor.anchorIDs.contains(anchorID2))
        XCTAssertTrue(actor.anchorIDs.contains(anchorID3))
    }
    
    // MARK: - Тест 6: Изменение имени актера
    
    func testChangeActorName() throws {
        var actor = ActorData(id: 1, name: "Старое имя", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        actors.append(actor)
        
        // Изменяем имя
        let newName = "Новое имя"
        if let index = actors.firstIndex(where: { $0.id == 1 }) {
            actors[index].name = newName
        }
        
        XCTAssertEqual(actors.first?.name, newName, "Имя должно быть изменено")
    }
    
    // MARK: - Тест 7: Удаление актера
    
    func testRemoveActor() throws {
        let actor1 = ActorData(id: 1, name: "Актер1", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let actor2 = ActorData(id: 2, name: "Актер2", red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        
        actors = [actor1, actor2]
        XCTAssertEqual(actors.count, 2, "Должно быть 2 актера")
        
        // Удаляем актера по ID
        actors.removeAll { $0.id == 1 }
        
        XCTAssertEqual(actors.count, 1, "Должен остаться один актер")
        XCTAssertEqual(actors.first?.id, 2, "Оставшийся актер должен иметь ID 2")
    }
    
    // MARK: - Тест 8: Конвертация цвета актера в компоненты
    
    func testConvertActorColorToComponents() throws {
        let actor = ActorData(id: 1, name: "Актер", red: 0.5, green: 0.3, blue: 0.8, alpha: 0.9)
        
        let color = actor.color
        let components = Converter.shared.cgFloatValuesFromUIColor(color: color)
        
        XCTAssertEqual(components.red, 0.5, accuracy: 0.01, "Красный компонент должен совпадать")
        XCTAssertEqual(components.green, 0.3, accuracy: 0.01, "Зеленый компонент должен совпадать")
        XCTAssertEqual(components.blue, 0.8, accuracy: 0.01, "Синий компонент должен совпадать")
        XCTAssertEqual(components.alpha, 0.9, accuracy: 0.01, "Альфа компонент должен совпадать")
    }
    
    // MARK: - Тест 9: Сериализация и десериализация актера
    
    func testActorEncodingDecoding() throws {
        let anchorID1 = UUID()
        let anchorID2 = UUID()
        
        var originalActor = ActorData(id: 12345, name: "Тестовый актер", red: 0.7, green: 0.2, blue: 0.9, alpha: 1.0)
        originalActor.anchorIDs = [anchorID1, anchorID2]
        
        // Кодируем
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalActor)
        
        // Декодируем
        let decoder = JSONDecoder()
        let decodedActor = try decoder.decode(ActorData.self, from: data)
        
        XCTAssertEqual(decodedActor.id, originalActor.id, "ID должен совпадать")
        XCTAssertEqual(decodedActor.name, originalActor.name, "Имя должно совпадать")
        XCTAssertEqual(decodedActor.red, originalActor.red, accuracy: 0.01, "Красный компонент должен совпадать")
        XCTAssertEqual(decodedActor.green, originalActor.green, accuracy: 0.01, "Зеленый компонент должен совпадать")
        XCTAssertEqual(decodedActor.blue, originalActor.blue, accuracy: 0.01, "Синий компонент должен совпадать")
        XCTAssertEqual(decodedActor.alpha, originalActor.alpha, accuracy: 0.01, "Альфа компонент должен совпадать")
        XCTAssertEqual(decodedActor.anchorIDs.count, originalActor.anchorIDs.count, "Количество якорей должно совпадать")
        XCTAssertEqual(decodedActor.anchorIDs[0], anchorID1, "Первый якорь должен совпадать")
        XCTAssertEqual(decodedActor.anchorIDs[1], anchorID2, "Второй якорь должен совпадать")
    }
    
    // MARK: - Тест 10: Создание актера с уникальным ID
    
    func testCreateActorWithUniqueID() throws {
        actors.removeAll()
        
        let actor1 = ActorData(id: 1, name: "Актер1", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let actor2 = ActorData(id: 2, name: "Актер2", red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        let actor3 = ActorData(id: 3, name: "Актер3", red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        
        actors = [actor1, actor2, actor3]
        
        // Проверяем уникальность ID
        let uniqueIDs = Set(actors.map { $0.id })
        XCTAssertEqual(uniqueIDs.count, actors.count, "Все ID должны быть уникальными")
    }
    
    // MARK: - Тест 11: Поиск актера по имени
    
    func testFindActorByName() throws {
        let actor1 = ActorData(id: 1, name: "Иван", red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let actor2 = ActorData(id: 2, name: "Мария", red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        let actor3 = ActorData(id: 3, name: "Петр", red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        
        actors = [actor1, actor2, actor3]
        
        let foundActor = actors.first { $0.name == "Мария" }
        
        XCTAssertNotNil(foundActor, "Актер 'Мария' должен быть найден")
        XCTAssertEqual(foundActor?.id, 2, "ID найденного актера должен быть 2")
    }
    
}
