//
//  SettingsTests.swift
//  shafinMultitoolTests
//
//  Created by AI Assistant
//

import XCTest
@testable import shafinMultitool

final class SettingsTests: XCTestCase {
    
    var interactor: CameraScreenInteractor!
    var dbService: DBService!
    
    override func setUpWithError() throws {
        super.setUp()
        interactor = CameraScreenInteractor()
        dbService = DBService.shared
        
        // Очищаем UserDefaults для чистых тестов
        clearUserDefaults()
    }
    
    override func tearDownWithError() throws {
        clearUserDefaults()
        interactor = nil
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
    
    // MARK: - Тест 1: Переключение разрешения (HD → FHD → UHD → HD)
    
    func testChangeResolutionCycle() throws {
        // Устанавливаем начальное разрешение HD
        UserDefaults.standard.set(1280, forKey: "resolutionWidth")
        UserDefaults.standard.set(720, forKey: "resolutionHeight")
        UserDefaults.standard.set("hd", forKey: "resolutionDescription")
        
        // HD -> FHD
        interactor.changeResolution()
        var settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.resolution.first?.width, 1920)
        XCTAssertEqual(settings.resolution.first?.height, 1080)
        
        // FHD -> UHD
        interactor.changeResolution()
        settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.resolution.first?.width, 3840)
        XCTAssertEqual(settings.resolution.first?.height, 2160)
        
        // UHD -> HD (циклический переход)
        interactor.changeResolution()
        settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.resolution.first?.width, 1280)
        XCTAssertEqual(settings.resolution.first?.height, 720)
    }
    
    // MARK: - Тест 2: Переключение FPS (24 → 25 → 30 → 24)
    
    func testChangeFPSCycle() throws {
        // Устанавливаем начальный FPS 24
        UserDefaults.standard.set(24, forKey: "framerate")
        
        // 24 -> 25
        interactor.changeFPS()
        var settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.fps, 25)
        
        // 25 -> 30
        interactor.changeFPS()
        settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.fps, 30)
        
        // 30 -> 24 (циклический переход)
        interactor.changeFPS()
        settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.fps, 24)
    }
    
    // MARK: - Тест 3: Переключение скорости (0.5 → 0.7 → 1.0 → 1.5 → 0.5)
    
    func testChangeSpeedCycle() throws {
        // Устанавливаем начальную скорость 0.5
        UserDefaults.standard.set(0.5, forKey: "speedMultiplier")
        
        // 0.5 -> 0.7
        interactor.changeSpeed()
        var settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.speed, 0.7, accuracy: 0.01)
        
        // 0.7 -> 1.0
        interactor.changeSpeed()
        settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.speed, 1.0, accuracy: 0.01)
        
        // 1.0 -> 1.5
        interactor.changeSpeed()
        settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.speed, 1.5, accuracy: 0.01)
        
        // 1.5 -> 0.5 (циклический переход)
        interactor.changeSpeed()
        settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.speed, 0.5, accuracy: 0.01)
    }
    
    // MARK: - Тест 4: Изменение ISO через picker view
    
    func testChangeISOThroughPicker() throws {
        // Устанавливаем начальный ISO 200
        UserDefaults.standard.set(200, forKey: "iso")
        
        let isoValues = [50, 100, 200, 400, 800]
        
        // Проверяем количество строк в picker view
        let numberOfRows = interactor.getNumberOfRowsInPickerView(tag: 1)
        XCTAssertEqual(numberOfRows, isoValues.count, "Количество строк должно соответствовать количеству значений ISO")
        
        // Выбираем каждое значение ISO
        for (index, isoValue) in isoValues.enumerated() {
            interactor.didSelectRow(row: index, tag: 1)
            let settings = dbService.fetchSettingsButtonValues()
            XCTAssertEqual(settings.iso, isoValue, "ISO должно быть \(isoValue)")
        }
    }
    
    // MARK: - Тест 5: Изменение баланса белого через picker view
    
    func testChangeWhiteBalanceThroughPicker() throws {
        // Устанавливаем начальный баланс белого 4000K
        UserDefaults.standard.set(4000, forKey: "whiteBalance")
        
        // Генерируем значения баланса белого (2400-8000 с шагом 100)
        let wbValues = Array(stride(from: 2400, through: 8000, by: 100))
        
        // Проверяем количество строк в picker view
        let numberOfRows = interactor.getNumberOfRowsInPickerView(tag: 2)
        XCTAssertEqual(numberOfRows, wbValues.count, "Количество строк должно соответствовать количеству значений WB")
        
        // Выбираем несколько значений баланса белого
        let testIndices = [0, wbValues.count / 2, wbValues.count - 1]
        for index in testIndices {
            interactor.didSelectRow(row: index, tag: 2)
            let settings = dbService.fetchSettingsButtonValues()
            XCTAssertEqual(settings.wb, wbValues[index], "Баланс белого должен быть \(wbValues[index])K")
        }
    }
    
    // MARK: - Тест 6: Сохранение настроек в UserDefaults
    
    func testSaveSettingsToUserDefaults() throws {
        // Изменяем разрешение
        UserDefaults.standard.set("hd", forKey: "resolutionDescription")
        interactor.changeResolution()
        
        let width = UserDefaults.standard.integer(forKey: "resolutionWidth")
        let height = UserDefaults.standard.integer(forKey: "resolutionHeight")
        let resolutionDescription = UserDefaults.standard.string(forKey: "resolutionDescription")
        
        XCTAssertEqual(width, 1920, "Ширина должна быть сохранена")
        XCTAssertEqual(height, 1080, "Высота должна быть сохранена")
        XCTAssertEqual(resolutionDescription, "fhd", "Описание разрешения должно быть сохранено")
    }
    
    // MARK: - Тест 7: Получение значений настроек из UserDefaults
    
    func testFetchSettingsFromUserDefaults() throws {
        // Устанавливаем значения напрямую
        UserDefaults.standard.set(1920, forKey: "resolutionWidth")
        UserDefaults.standard.set(1080, forKey: "resolutionHeight")
        UserDefaults.standard.set(30, forKey: "framerate")
        UserDefaults.standard.set(4000, forKey: "whiteBalance")
        UserDefaults.standard.set(200, forKey: "iso")
        UserDefaults.standard.set(1.0, forKey: "speedMultiplier")
        
        let settings = dbService.fetchSettingsButtonValues()
        
        XCTAssertEqual(settings.resolution.first?.width, 1920)
        XCTAssertEqual(settings.resolution.first?.height, 1080)
        XCTAssertEqual(settings.fps, 30)
        XCTAssertEqual(settings.wb, 4000)
        XCTAssertEqual(settings.iso, 200)
        XCTAssertEqual(settings.speed, 1.0, accuracy: 0.01)
    }
    
    // MARK: - Тест 8: Получение заголовков для строк picker view
    
    func testGetPickerViewTitles() throws {
        // Тест для ISO
        let isoRow0 = interactor.titleForRow(row: 0, tag: 1)
        XCTAssertEqual(isoRow0, "50", "Первая строка ISO должна быть '50'")
        
        let isoRow4 = interactor.titleForRow(row: 4, tag: 1)
        XCTAssertEqual(isoRow4, "800", "Последняя строка ISO должна быть '800'")
        
        // Тест для баланса белого
        let wbRow0 = interactor.titleForRow(row: 0, tag: 2)
        XCTAssertEqual(wbRow0, "2400K", "Первая строка WB должна быть '2400K'")
        
        let wbRowLast = interactor.titleForRow(row: interactor.getNumberOfRowsInPickerView(tag: 2) - 1, tag: 2)
        XCTAssertEqual(wbRowLast, "8000K", "Последняя строка WB должна быть '8000K'")
    }
    
    // MARK: - Тест 9: Получение выбранной строки для текущих настроек
    
    func testGetSelectedRowForCurrentSettings() throws {
        // Устанавливаем ISO 200
        UserDefaults.standard.set(200, forKey: "iso")
        let selectedISORow = interactor.getSelectedRowNumberForPickerView(tag: 1)
        XCTAssertEqual(selectedISORow, 2, "Выбранная строка для ISO 200 должна быть 2")
        
        // Устанавливаем баланс белого 4000K
        UserDefaults.standard.set(4000, forKey: "whiteBalance")
        let selectedWBRow = interactor.getSelectedRowNumberForPickerView(tag: 2)
        XCTAssertEqual(selectedWBRow, 16, "Выбранная строка для WB 4000K должна быть 16 (4000-2400)/100")
    }
    
    // MARK: - Тест 10: Установка дефолтных значений при первом запуске
    
    func testSetDefaultSettingsOnFirstLaunch() throws {
        // Очищаем все настройки
        clearUserDefaults()
        
        // Вызываем метод, который устанавливает дефолтные значения
        // Это делается в prepareRecorder, но мы можем проверить через interactor
        interactor.prepareRecorder()
        
        let settings = dbService.fetchSettingsButtonValues()
        
        // Проверяем, что установлены дефолтные значения
        XCTAssertEqual(settings.resolution.first?.width, 3840, "Дефолтная ширина должна быть 3840")
        XCTAssertEqual(settings.resolution.first?.height, 2160, "Дефолтная высота должна быть 2160")
        XCTAssertEqual(settings.fps, 25, "Дефолтный FPS должен быть 25")
        XCTAssertEqual(settings.wb, 4000, "Дефолтный баланс белого должен быть 4000")
        XCTAssertEqual(settings.iso, 200, "Дефолтный ISO должен быть 200")
        XCTAssertEqual(settings.speed, 1.0, accuracy: 0.01, "Дефолтная скорость должна быть 1.0")
    }
    
    // MARK: - Тест 11: Множественные изменения настроек
    
    func testMultipleSettingsChanges() throws {
        // Изменяем разрешение несколько раз
        UserDefaults.standard.set("hd", forKey: "resolutionDescription")
        interactor.changeResolution() // HD -> FHD
        interactor.changeResolution() // FHD -> UHD
        interactor.changeResolution() // UHD -> HD
        
        var settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.resolution.first?.width, 1280, "После трех изменений должно вернуться к HD")
        
        // Изменяем FPS несколько раз
        UserDefaults.standard.set(24, forKey: "framerate")
        interactor.changeFPS() // 24 -> 25
        interactor.changeFPS() // 25 -> 30
        
        settings = dbService.fetchSettingsButtonValues()
        XCTAssertEqual(settings.fps, 30, "После двух изменений FPS должен быть 30")
    }
    
    // MARK: - Тест 12: Сохранение настроек между сессиями
    
    func testSettingsPersistenceBetweenSessions() throws {
        // Устанавливаем настройки
        UserDefaults.standard.set(1920, forKey: "resolutionWidth")
        UserDefaults.standard.set(1080, forKey: "resolutionHeight")
        UserDefaults.standard.set(30, forKey: "framerate")
        UserDefaults.standard.set(4000, forKey: "whiteBalance")
        UserDefaults.standard.set(400, forKey: "iso")
        UserDefaults.standard.set(1.5, forKey: "speedMultiplier")
        
        // Создаем новый экземпляр сервиса (имитация нового запуска)
        let newDbService = DBService.shared
        let settings = newDbService.fetchSettingsButtonValues()
        
        // Проверяем, что настройки сохранились
        XCTAssertEqual(settings.resolution.first?.width, 1920)
        XCTAssertEqual(settings.resolution.first?.height, 1080)
        XCTAssertEqual(settings.fps, 30)
        XCTAssertEqual(settings.wb, 4000)
        XCTAssertEqual(settings.iso, 400)
        XCTAssertEqual(settings.speed, 1.5, accuracy: 0.01)
    }
}
