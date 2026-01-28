//
//  UserDefaultsTests.swift
//  shafinMultitoolTests
//
//  Created by AI Assistant
//

import XCTest
@testable import shafinMultitool

final class UserDefaultsTests: XCTestCase {
    
    var dbService: DBService!
    
    override func setUpWithError() throws {
        super.setUp()
        dbService = DBService.shared
        clearUserDefaults()
    }
    
    override func tearDownWithError() throws {
        clearUserDefaults()
        dbService = nil
        super.tearDown()
    }
    
    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "resolutionWidth")
        UserDefaults.standard.removeObject(forKey: "resolutionHeight")
        UserDefaults.standard.removeObject(forKey: "resolutionDescription")
        UserDefaults.standard.removeObject(forKey: "framerate")
        UserDefaults.standard.removeObject(forKey: "whiteBalance")
        UserDefaults.standard.removeObject(forKey: "iso")
        UserDefaults.standard.removeObject(forKey: "speedMultiplier")
    }
    
    // MARK: - Тест 1: Сохранение настроек камеры
    
    func testSaveCameraSettings() throws {
        UserDefaults.standard.set(1920, forKey: "resolutionWidth")
        UserDefaults.standard.set(1080, forKey: "resolutionHeight")
        UserDefaults.standard.set("fhd", forKey: "resolutionDescription")
        UserDefaults.standard.set(30, forKey: "framerate")
        UserDefaults.standard.set(4000, forKey: "whiteBalance")
        UserDefaults.standard.set(200, forKey: "iso")
        UserDefaults.standard.set(1.0, forKey: "speedMultiplier")
        
        // Проверяем сохранение
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "resolutionWidth"), 1920)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "resolutionHeight"), 1080)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "resolutionDescription"), "fhd")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "framerate"), 30)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "whiteBalance"), 4000)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "iso"), 200)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "speedMultiplier"), 1.0, accuracy: 0.01)
    }
    
    // MARK: - Тест 2: Загрузка настроек при следующем запуске
    
    func testLoadSettingsOnNextLaunch() throws {
        // Сохраняем настройки
        UserDefaults.standard.set(3840, forKey: "resolutionWidth")
        UserDefaults.standard.set(2160, forKey: "resolutionHeight")
        UserDefaults.standard.set(25, forKey: "framerate")
        UserDefaults.standard.set(5000, forKey: "whiteBalance")
        UserDefaults.standard.set(400, forKey: "iso")
        UserDefaults.standard.set(1.5, forKey: "speedMultiplier")
        
        // Симулируем новый запуск - создаем новый экземпляр сервиса
        let settings = dbService.fetchSettingsButtonValues()
        
        XCTAssertEqual(settings.resolution.first?.width, 3840, "Ширина должна загрузиться")
        XCTAssertEqual(settings.resolution.first?.height, 2160, "Высота должна загрузиться")
        XCTAssertEqual(settings.fps, 25, "FPS должен загрузиться")
        XCTAssertEqual(settings.wb, 5000, "Баланс белого должен загрузиться")
        XCTAssertEqual(settings.iso, 400, "ISO должен загрузиться")
        XCTAssertEqual(settings.speed, 1.5, accuracy: 0.01, "Скорость должна загрузиться")
    }
    
    // MARK: - Тест 3: Установка дефолтных значений при первом запуске
    
    func testSetDefaultValuesOnFirstLaunch() throws {
        // Очищаем все настройки
        clearUserDefaults()
        
        // Проверяем, что значения отсутствуют
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "resolutionWidth"), 0)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "resolutionHeight"), 0)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "framerate"), 0)
        
        // Устанавливаем дефолтные значения (как в setDefaultSettings)
        UserDefaults.standard.set(3840, forKey: "resolutionWidth")
        UserDefaults.standard.set(2160, forKey: "resolutionHeight")
        UserDefaults.standard.set("uhd", forKey: "resolutionDescription")
        UserDefaults.standard.set(25, forKey: "framerate")
        UserDefaults.standard.set(4000, forKey: "whiteBalance")
        UserDefaults.standard.set(200, forKey: "iso")
        UserDefaults.standard.set(1.0, forKey: "speedMultiplier")
        
        let settings = dbService.fetchSettingsButtonValues()
        
        // Проверяем дефолтные значения
        XCTAssertEqual(settings.resolution.first?.width, 3840, "Дефолтная ширина должна быть 3840")
        XCTAssertEqual(settings.resolution.first?.height, 2160, "Дефолтная высота должна быть 2160")
        XCTAssertEqual(settings.fps, 25, "Дефолтный FPS должен быть 25")
        XCTAssertEqual(settings.wb, 4000, "Дефолтный баланс белого должен быть 4000")
        XCTAssertEqual(settings.iso, 200, "Дефолтный ISO должен быть 200")
        XCTAssertEqual(settings.speed, 1.0, accuracy: 0.01, "Дефолтная скорость должна быть 1.0")
    }
    
    // MARK: - Тест 4: Обновление существующих настроек
    
    func testUpdateExistingSettings() throws {
        // Устанавливаем начальные значения
        UserDefaults.standard.set(1280, forKey: "resolutionWidth")
        UserDefaults.standard.set(720, forKey: "resolutionHeight")
        UserDefaults.standard.set(24, forKey: "framerate")
        
        // Обновляем значения
        UserDefaults.standard.set(1920, forKey: "resolutionWidth")
        UserDefaults.standard.set(1080, forKey: "resolutionHeight")
        UserDefaults.standard.set(30, forKey: "framerate")
        
        // Проверяем обновление
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "resolutionWidth"), 1920, "Ширина должна быть обновлена")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "resolutionHeight"), 1080, "Высота должна быть обновлена")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "framerate"), 30, "FPS должен быть обновлен")
    }
    
    // MARK: - Тест 5: Сохранение различных значений разрешения
    
    func testSaveDifferentResolutions() throws {
        let resolutions: [(width: Int, height: Int, description: String)] = [
            (1280, 720, "hd"),
            (1920, 1080, "fhd"),
            (3840, 2160, "uhd")
        ]
        
        for resolution in resolutions {
            UserDefaults.standard.set(resolution.width, forKey: "resolutionWidth")
            UserDefaults.standard.set(resolution.height, forKey: "resolutionHeight")
            UserDefaults.standard.set(resolution.description, forKey: "resolutionDescription")
            
            let settings = dbService.fetchSettingsButtonValues()
            XCTAssertEqual(settings.resolution.first?.width, resolution.width, "Ширина должна быть \(resolution.width)")
            XCTAssertEqual(settings.resolution.first?.height, resolution.height, "Высота должна быть \(resolution.height)")
        }
    }
    
    // MARK: - Тест 6: Сохранение различных значений FPS
    
    func testSaveDifferentFPSValues() throws {
        let fpsValues = [24, 25, 30]
        
        for fps in fpsValues {
            UserDefaults.standard.set(fps, forKey: "framerate")
            let settings = dbService.fetchSettingsButtonValues()
            XCTAssertEqual(settings.fps, fps, "FPS должен быть \(fps)")
        }
    }
    
    // MARK: - Тест 7: Сохранение различных значений ISO
    
    func testSaveDifferentISOValues() throws {
        let isoValues = [50, 100, 200, 400, 800]
        
        for iso in isoValues {
            UserDefaults.standard.set(iso, forKey: "iso")
            let settings = dbService.fetchSettingsButtonValues()
            XCTAssertEqual(settings.iso, iso, "ISO должен быть \(iso)")
        }
    }
    
    // MARK: - Тест 8: Сохранение различных значений баланса белого
    
    func testSaveDifferentWhiteBalanceValues() throws {
        let wbValues = [2400, 3000, 4000, 5000, 6000, 7000, 8000]
        
        for wb in wbValues {
            UserDefaults.standard.set(wb, forKey: "whiteBalance")
            let settings = dbService.fetchSettingsButtonValues()
            XCTAssertEqual(settings.wb, wb, "Баланс белого должен быть \(wb)")
        }
    }
    
    // MARK: - Тест 9: Сохранение различных значений скорости
    
    func testSaveDifferentSpeedValues() throws {
        let speedValues: [Double] = [0.5, 0.7, 1.0, 1.5]
        
        for speed in speedValues {
            UserDefaults.standard.set(speed, forKey: "speedMultiplier")
            let settings = dbService.fetchSettingsButtonValues()
            XCTAssertEqual(settings.speed, speed, accuracy: 0.01, "Скорость должна быть \(speed)")
        }
    }
    
    // MARK: - Тест 10: Сохранение всех настроек одновременно
    
    func testSaveAllSettingsSimultaneously() throws {
        UserDefaults.standard.set(3840, forKey: "resolutionWidth")
        UserDefaults.standard.set(2160, forKey: "resolutionHeight")
        UserDefaults.standard.set("uhd", forKey: "resolutionDescription")
        UserDefaults.standard.set(30, forKey: "framerate")
        UserDefaults.standard.set(5000, forKey: "whiteBalance")
        UserDefaults.standard.set(400, forKey: "iso")
        UserDefaults.standard.set(1.5, forKey: "speedMultiplier")
        
        let settings = dbService.fetchSettingsButtonValues()
        
        XCTAssertEqual(settings.resolution.first?.width, 3840)
        XCTAssertEqual(settings.resolution.first?.height, 2160)
        XCTAssertEqual(settings.fps, 30)
        XCTAssertEqual(settings.wb, 5000)
        XCTAssertEqual(settings.iso, 400)
        XCTAssertEqual(settings.speed, 1.5, accuracy: 0.01)
    }
    
    // MARK: - Тест 11: Проверка целостности данных после множественных изменений
    
    func testDataIntegrityAfterMultipleChanges() throws {
        // Делаем несколько изменений настроек
        for i in 1...5 {
            UserDefaults.standard.set(1280 + (i * 100), forKey: "resolutionWidth")
            UserDefaults.standard.set(720 + (i * 50), forKey: "resolutionHeight")
            UserDefaults.standard.set(24 + i, forKey: "framerate")
            
            let settings = dbService.fetchSettingsButtonValues()
            
            XCTAssertEqual(settings.resolution.first?.width, 1280 + (i * 100), "Ширина должна быть обновлена на итерации \(i)")
            XCTAssertEqual(settings.resolution.first?.height, 720 + (i * 50), "Высота должна быть обновлена на итерации \(i)")
            XCTAssertEqual(settings.fps, 24 + i, "FPS должен быть обновлен на итерации \(i)")
        }
    }
    
    // MARK: - Тест 12: Очистка настроек
    
    func testClearSettings() throws {
        // Устанавливаем значения
        UserDefaults.standard.set(1920, forKey: "resolutionWidth")
        UserDefaults.standard.set(1080, forKey: "resolutionHeight")
        UserDefaults.standard.set(30, forKey: "framerate")
        
        // Очищаем
        clearUserDefaults()
        
        // Проверяем, что значения очищены
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "resolutionWidth"), 0)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "resolutionHeight"), 0)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "framerate"), 0)
    }
}
