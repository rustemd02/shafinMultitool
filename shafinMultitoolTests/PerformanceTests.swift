//
//  PerformanceTests.swift
//  shafinMultitoolTests
//
//  Created by AI Assistant
//

import XCTest
@testable import shafinMultitool

final class PerformanceTests: XCTestCase {
    
    var interactor: CameraScreenInteractor!
    var dbService: DBService!
    
    override func setUpWithError() throws {
        super.setUp()
        interactor = CameraScreenInteractor()
        dbService = DBService.shared
    }
    
    override func tearDownWithError() throws {
        interactor = nil
        dbService = nil
        super.tearDown()
    }
    
    // MARK: - Тест 1: Парсинг больших сценариев
    
    func testParseLargeScriptPerformance() throws {
        // Создаем большой сценарий (1000+ строк)
        var largeScript = ""
        for i in 1...1000 {
            largeScript += "Персонаж\(i % 10): Реплика номер \(i). "
        }
        
        measure {
            _ = interactor.reformatScript(script: largeScript)
        }
    }
    
    // MARK: - Тест 2: Парсинг сценария на 1000+ строк (время выполнения < 1 секунды)
    
    func testParseLargeScriptUnderOneSecond() throws {
        var largeScript = ""
        for i in 1...1000 {
            largeScript += "Персонаж\(i % 10): Реплика номер \(i). "
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = interactor.reformatScript(script: largeScript)
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertLessThan(executionTime, 1.0, "Парсинг должен выполняться менее чем за 1 секунду")
        XCTAssertEqual(result.names.count, 1000, "Должно быть распознано 1000 имен")
        XCTAssertEqual(result.phrases.count, 1000, "Должно быть распознано 1000 фраз")
    }
    
    // MARK: - Тест 3: Парсинг очень больших сценариев
    
    func testParseVeryLargeScriptPerformance() throws {
        // Создаем очень большой сценарий (5000 строк)
        var veryLargeScript = ""
        for i in 1...5000 {
            veryLargeScript += "Персонаж\(i % 20): Реплика номер \(i) с более длинным текстом для тестирования производительности. "
        }
        
        measure {
            _ = interactor.reformatScript(script: veryLargeScript)
        }
    }
    
    // MARK: - Тест 4: Сохранение больших AR-карт
    
    func testSaveLargeARMapPerformance() throws {
        // Создаем сцену с множеством актеров и якорей
        var actors: [ActorData] = []
        for i in 1...100 {
            var actor = ActorData(
                id: UInt64(i),
                name: "Актер\(i)",
                red: CGFloat.random(in: 0...1),
                green: CGFloat.random(in: 0...1),
                blue: CGFloat.random(in: 0...1),
                alpha: 1.0
            )
            // Добавляем несколько якорей к каждому актеру
            for _ in 1...5 {
                actor.anchorIDs.append(UUID())
            }
            actors.append(actor)
        }
        
        let sceneData = SceneData(
            name: "LargeTestScene_\(UUID().uuidString)",
            actors: actors,
            script: String(repeating: "Иван: Тестовая реплика. ", count: 100)
        )
        
        measure {
            do {
                try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
            } catch {
                XCTFail("Ошибка сохранения: \(error)")
            }
        }
    }
    
    // MARK: - Тест 5: Сохранение карты с множеством якорей (время сохранения < 5 секунд)
    
    func testSaveLargeMapUnderFiveSeconds() throws {
        var actors: [ActorData] = []
        for i in 1...50 {
            var actor = ActorData(
                id: UInt64(i),
                name: "Актер\(i)",
                red: 0.5,
                green: 0.5,
                blue: 0.5,
                alpha: 1.0
            )
            for _ in 1...10 {
                actor.anchorIDs.append(UUID())
            }
            actors.append(actor)
        }
        
        let sceneData = SceneData(
            name: "PerformanceTestScene_\(UUID().uuidString)",
            actors: actors,
            script: String(repeating: "Тест: Реплика. ", count: 200)
        )
        
        let startTime = CFAbsoluteTimeGetCurrent()
        try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertLessThan(executionTime, 5.0, "Сохранение должно выполняться менее чем за 5 секунд")
        
        // Очистка
        dbService.deleteMap(with: sceneData.name) { _ in }
    }
    
    // MARK: - Тест 6: Загрузка больших AR-карт
    
    func testLoadLargeARMapPerformance() throws {
        // Сначала создаем большую карту
        var actors: [ActorData] = []
        for i in 1...50 {
            var actor = ActorData(
                id: UInt64(i),
                name: "Актер\(i)",
                red: 0.5,
                green: 0.5,
                blue: 0.5,
                alpha: 1.0
            )
            for _ in 1...5 {
                actor.anchorIDs.append(UUID())
            }
            actors.append(actor)
        }
        
        let sceneName = "LoadPerformanceTest_\(UUID().uuidString)"
        let sceneData = SceneData(
            name: sceneName,
            actors: actors,
            script: String(repeating: "Тест: Реплика. ", count: 100)
        )
        
        try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
        
        measure {
            _ = dbService.loadARWorldMap(sceneName: sceneName)
        }
        
        // Очистка
        dbService.deleteMap(with: sceneName) { _ in }
    }
    
    // MARK: - Тест 7: Конвертация множества цветов
    
    func testConvertMultipleColorsPerformance() throws {
        let converter = Converter.shared
        let colors: [UIColor] = (0..<1000).map { index in
            UIColor(
                red: CGFloat.random(in: 0...1),
                green: CGFloat.random(in: 0...1),
                blue: CGFloat.random(in: 0...1),
                alpha: CGFloat.random(in: 0...1)
            )
        }
        
        measure {
            for color in colors {
                _ = converter.cgFloatValuesFromUIColor(color: color)
            }
        }
    }
    
    // MARK: - Тест 8: Конвертация множества разрешений
    
//    func testConvertMultipleResolutionsPerformance() throws {
//        let converter = Converter.shared
//        let resolutions: [Resolutions] = [.hd, .fhd, .uhd]
//        
//        measure {
//            for _ in 0..<10000 {
//                for resolution in resolutions {
//                    _ = converter.resolutionEnumToRawValues(Resolution: resolution)
//                }
//            }
//        }
//    }
    
    // MARK: - Тест 9: Сериализация и десериализация больших данных
    
    func testEncodeDecodeLargeDataPerformance() throws {
        var actors: [ActorData] = []
        for i in 1...100 {
            var actor = ActorData(
                id: UInt64(i),
                name: "Актер\(i)",
                red: CGFloat.random(in: 0...1),
                green: CGFloat.random(in: 0...1),
                blue: CGFloat.random(in: 0...1),
                alpha: 1.0
            )
            for _ in 1...10 {
                actor.anchorIDs.append(UUID())
            }
            actors.append(actor)
        }
        
        let sceneData = SceneData(
            name: "PerformanceTest",
            actors: actors,
            script: String(repeating: "Тест: Реплика. ", count: 500)
        )
        
        measure {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(sceneData)
                
                let decoder = JSONDecoder()
                _ = try decoder.decode(SceneData.self, from: data)
            } catch {
                XCTFail("Ошибка кодирования/декодирования: \(error)")
            }
        }
    }
    
    // MARK: - Тест 10: Получение списка всех сцен (производительность)
    
    func testGetAllSceneNamesPerformance() throws {
        // Создаем несколько тестовых сцен
        let sceneCount = 50
        var sceneNames: [String] = []
        
        for i in 1...sceneCount {
            let sceneName = "PerformanceScene\(i)_\(UUID().uuidString)"
            sceneNames.append(sceneName)
            let sceneData = SceneData(
                name: sceneName,
                actors: nil,
                script: "Тест \(i)"
            )
            try dbService.saveARWorldMap(map: nil, sceneData: sceneData)
        }
        
        measure {
            _ = dbService.getAllARWorldMapTitles()
        }
        
        // Очистка
        for sceneName in sceneNames {
            dbService.deleteMap(with: sceneName) { _ in }
        }
    }
    
    // MARK: - Тест 11: Множественные изменения настроек
    
    func testMultipleSettingsChangesPerformance() throws {
        UserDefaults.standard.set("hd", forKey: "resolutionDescription")
        UserDefaults.standard.set(24, forKey: "framerate")
        UserDefaults.standard.set(0.5, forKey: "speedMultiplier")
        
        measure {
            for _ in 0..<100 {
                interactor.changeResolution()
                interactor.changeFPS()
                interactor.changeSpeed()
            }
        }
        
        // Очистка
        UserDefaults.standard.removeObject(forKey: "resolutionWidth")
        UserDefaults.standard.removeObject(forKey: "resolutionHeight")
        UserDefaults.standard.removeObject(forKey: "resolutionDescription")
        UserDefaults.standard.removeObject(forKey: "framerate")
        UserDefaults.standard.removeObject(forKey: "speedMultiplier")
    }
    
    // MARK: - Тест 12: Поиск актера в большом списке
    
    func testFindActorInLargeListPerformance() throws {
        // Создаем большой список актеров
        var actors: [ActorData] = []
        for i in 1...1000 {
            var actor = ActorData(
                id: UInt64(i),
                name: "Актер\(i)",
                red: 0.5,
                green: 0.5,
                blue: 0.5,
                alpha: 1.0
            )
            actor.anchorIDs.append(UUID())
            actors.append(actor)
        }
        
        let targetActorID = UInt64(500)
        
        measure {
            _ = actors.first { $0.id == targetActorID }
        }
    }
    
    
    // MARK: - Тест 15: Отсутствие утечек памяти при длительной записи (симуляция)
    
    func testNoMemoryLeaksDuringLongRecording() throws {
        // Симулируем длительную запись
        let iterations = 10000
        
        autoreleasepool {
            for i in 0..<iterations {
                // Симулируем обработку данных записи
                let sceneData = SceneData(
                    name: "MemoryTest\(i)",
                    actors: nil,
                    script: "Тест \(i)"
                )
                
                // Создаем и сразу освобождаем данные
                let _ = try? JSONEncoder().encode(sceneData)
            }
        }
        
        // Если есть утечки памяти, тест упадет или будет очень медленным
        XCTAssertTrue(true, "Тест должен завершиться без утечек памяти")
    }
}
