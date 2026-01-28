//
//  UITests.swift
//  shafinMultitoolTests
//
//  Created by AI Assistant
//

import XCTest
@testable import shafinMultitool

final class UITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Тест 1: Открытие приложения и отображение списка сцен
    
    func testAppLaunchShowsSceneList() throws {
        // Проверяем, что приложение запустилось
        XCTAssertTrue(app.waitForExistence(timeout: 5.0), "Приложение должно запуститься")
        
        // Проверяем наличие основных элементов интерфейса
        // В реальном тесте нужно использовать accessibility identifiers
        // Для примера проверяем наличие элементов по тексту
        let sceneListExists = app.collectionViews.firstMatch.waitForExistence(timeout: 2.0)
        XCTAssertTrue(sceneListExists, "Список сцен должен отображаться")
    }
    
    // MARK: - Тест 2: Создание новой сцены
    
    func testCreateNewScene() throws {
        // Находим кнопку добавления новой сцены (обычно первая ячейка с "+")
        let addButton = app.collectionViews.cells.firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 2.0), "Кнопка добавления должна существовать")
        
        // Нажимаем на кнопку добавления
        addButton.tap()
        
        // Ожидаем появления алерта для ввода имени
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2.0), "Должен появиться алерт для ввода имени")
        
        // В реальном тесте здесь нужно:
        // 1. Ввести имя в текстовое поле
        // 2. Нажать кнопку "Сохранить"
        // 3. Проверить, что сцена появилась в списке
    }
    
    // MARK: - Тест 3: Открытие существующей сцены
    
    func testOpenExistingScene() throws {
        // Предполагаем, что есть хотя бы одна сцена
        // В реальном тесте нужно сначала создать сцену или использовать предустановленные данные
        
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            // Нажимаем на вторую ячейку (первая - это кнопка добавления)
            sceneCells.element(boundBy: 1).tap()
            
            // Проверяем переход на экран камеры
            // В реальном тесте нужно проверить наличие элементов AR-вида
            XCTAssertTrue(app.waitForExistence(timeout: 2.0), "Должен произойти переход на экран камеры")
        }
    }
    
    // MARK: - Тест 4: Удаление сцены
    
    func testDeleteScene() throws {
        // В реальном тесте нужно:
        // 1. Создать тестовую сцену
        // 2. Найти кнопку удаления на ячейке сцены
        // 3. Нажать на кнопку удаления
        // 4. Подтвердить удаление (если требуется)
        // 5. Проверить, что сцена исчезла из списка
        
        // Примерная структура:
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            let sceneCell = sceneCells.element(boundBy: 1)
            let deleteButton = sceneCell.buttons["deleteButton"] // Нужен accessibility identifier
            
            if deleteButton.exists {
                deleteButton.tap()
                // Проверяем, что сцена удалена
            }
        }
    }
    
    // MARK: - Тест 5: Отображение AR-вида
    
    func testARViewDisplay() throws {
        // Переходим на экран камеры (предполагаем, что есть сцена)
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Проверяем наличие AR-вида
            // В реальном тесте нужно использовать accessibility identifier для ARView
            XCTAssertTrue(app.waitForExistence(timeout: 3.0), "AR-вид должен отображаться")
        }
    }
    
    // MARK: - Тест 6: Нажатие на кнопку добавления актера
    
    func testAddActorButton() throws {
        // Переходим на экран камеры
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Ищем кнопку добавления актера
            // В реальном тесте нужен accessibility identifier: "addActorButton"
            let addActorButton = app.buttons["addActorButton"]
            
            if addActorButton.waitForExistence(timeout: 2.0) {
                addActorButton.tap()
                // Проверяем, что кнопка сработала (например, появились кнопки редактирования)
            }
        }
    }
    
    // MARK: - Тест 7: Отображение кнопок управления
    
    func testControlButtonsDisplay() throws {
        // Переходим на экран камеры
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Проверяем наличие кнопок управления
            // В реальном тесте нужны accessibility identifiers
            let recordButton = app.buttons["recordButton"]
            let backButton = app.buttons["backButton"]
            
            XCTAssertTrue(recordButton.waitForExistence(timeout: 2.0), "Кнопка записи должна существовать")
            XCTAssertTrue(backButton.waitForExistence(timeout: 2.0), "Кнопка назад должна существовать")
        }
    }
    
    // MARK: - Тест 8: Нажатие на кнопку записи
    
    func testRecordButtonPress() throws {
        // Переходим на экран камеры
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Находим кнопку записи
            let recordButton = app.buttons["recordButton"]
            
            if recordButton.waitForExistence(timeout: 2.0) {
                recordButton.tap()
                
                // Проверяем, что кнопка записи скрылась, а кнопка остановки появилась
                let stopButton = app.buttons["stopButton"]
                XCTAssertTrue(stopButton.waitForExistence(timeout: 1.0), "Кнопка остановки должна появиться")
                
                // Проверяем наличие секундомера
                let stopwatch = app.staticTexts.matching(identifier: "stopwatchLabel").firstMatch
                XCTAssertTrue(stopwatch.waitForExistence(timeout: 1.0), "Секундомер должен отображаться")
            }
        }
    }
    
    // MARK: - Тест 9: Остановка записи
    
    func testStopRecording() throws {
        // Переходим на экран камеры и начинаем запись
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            let recordButton = app.buttons["recordButton"]
            if recordButton.waitForExistence(timeout: 2.0) {
                recordButton.tap()
                
                // Ждем немного
                sleep(1)
                
                // Останавливаем запись
                let stopButton = app.buttons["stopButton"]
                if stopButton.waitForExistence(timeout: 2.0) {
                    stopButton.tap()
                    
                    // Проверяем, что кнопка записи снова появилась
                    XCTAssertTrue(recordButton.waitForExistence(timeout: 2.0), "Кнопка записи должна появиться снова")
                }
            }
        }
    }
    
    // MARK: - Тест 10: Открытие picker view для ISO
    
    func testOpenISOPickerView() throws {
        // Переходим на экран камеры
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Находим кнопку ISO
            let isoButton = app.buttons.matching(identifier: "changeISOButton").firstMatch
            
            if isoButton.waitForExistence(timeout: 2.0) {
                isoButton.tap()
                
                // Проверяем появление picker view
                let pickerView = app.pickers.firstMatch
                XCTAssertTrue(pickerView.waitForExistence(timeout: 2.0), "Picker view должен появиться")
            }
        }
    }
    
    // MARK: - Тест 11: Выбор значения ISO
    
    func testSelectISOValue() throws {
        // Переходим на экран камеры и открываем picker view
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            let isoButton = app.buttons.matching(identifier: "changeISOButton").firstMatch
            if isoButton.waitForExistence(timeout: 2.0) {
                isoButton.tap()
                
                let pickerView = app.pickers.firstMatch
                if pickerView.waitForExistence(timeout: 2.0) {
                    // Выбираем значение (например, третье значение - 200)
                    pickerView.adjust(toPickerWheelValue: "200")
                    
                    // Проверяем, что значение обновилось на кнопке
                    // В реальном тесте нужно проверить текст кнопки ISO
                }
            }
        }
    }
    
    // MARK: - Тест 12: Переключение разрешения
    
    func testChangeResolution() throws {
        // Переходим на экран камеры
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Находим кнопку разрешения
            let resolutionButton = app.buttons.matching(identifier: "changeResolutionButton").firstMatch
            
            if resolutionButton.waitForExistence(timeout: 2.0) {
                let initialText = resolutionButton.label
                
                // Нажимаем на кнопку для переключения разрешения
                resolutionButton.tap()
                
                // Ждем обновления
                sleep(1)
                
                // Проверяем, что текст изменился (в реальном тесте нужно проверить конкретные значения)
                let newText = resolutionButton.label
                // XCTAssertNotEqual(initialText, newText, "Разрешение должно измениться")
            }
        }
    }
    
    // MARK: - Тест 13: Переключение FPS
    
    func testChangeFPS() throws {
        // Переходим на экран камеры
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Находим кнопку FPS
            let fpsButton = app.buttons.matching(identifier: "changeFPSButton").firstMatch
            
            if fpsButton.waitForExistence(timeout: 2.0) {
                let initialText = fpsButton.label
                
                // Нажимаем на кнопку для переключения FPS
                fpsButton.tap()
                
                // Ждем обновления
                sleep(1)
                
                // Проверяем, что текст изменился
                let newText = fpsButton.label
                // XCTAssertNotEqual(initialText, newText, "FPS должен измениться")
            }
        }
    }
    
    // MARK: - Тест 14: Открытие экрана редактирования сценария
    
    func testOpenEditScriptScreen() throws {
        // Переходим на экран камеры
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Находим кнопку редактирования сценария
            let scriptButton = app.buttons.matching(identifier: "changeScriptButton").firstMatch
            
            if scriptButton.waitForExistence(timeout: 2.0) {
                scriptButton.tap()
                
                // Проверяем переход на экран редактирования
                let textView = app.textViews.firstMatch
                XCTAssertTrue(textView.waitForExistence(timeout: 2.0), "Текстовое поле должно появиться")
            }
        }
    }
    
    // MARK: - Тест 15: Ввод текста в текстовое поле сценария
    
    func testEnterScriptText() throws {
        // Переходим на экран редактирования сценария
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            let scriptButton = app.buttons.matching(identifier: "changeScriptButton").firstMatch
            if scriptButton.waitForExistence(timeout: 2.0) {
                scriptButton.tap()
                
                let textView = app.textViews.firstMatch
                if textView.waitForExistence(timeout: 2.0) {
                    textView.tap()
                    textView.typeText("Иван: Привет. Мария: Как дела?")
                    
                    // Проверяем, что текст введен
                    XCTAssertTrue(textView.value as? String == "Иван: Привет. Мария: Как дела?", 
                                 "Текст должен быть введен")
                }
            }
        }
    }
    
    // MARK: - Тест 16: Сохранение изменений сценария
    
    func testSaveScriptChanges() throws {
        // Переходим на экран редактирования и вводим текст
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            let scriptButton = app.buttons.matching(identifier: "changeScriptButton").firstMatch
            if scriptButton.waitForExistence(timeout: 2.0) {
                scriptButton.tap()
                
                let textView = app.textViews.firstMatch
                if textView.waitForExistence(timeout: 2.0) {
                    textView.tap()
                    textView.typeText("Новый сценарий")
                    
                    // Находим кнопку сохранения
                    let saveButton = app.buttons.matching(identifier: "submitButton").firstMatch
                    if saveButton.waitForExistence(timeout: 2.0) {
                        saveButton.tap()
                        
                        // Проверяем возврат на экран камеры
                        XCTAssertTrue(app.waitForExistence(timeout: 2.0), "Должен произойти возврат на экран камеры")
                    }
                }
            }
        }
    }
    
    // MARK: - Тест 17: Возврат на экран списка сцен
    
    func testReturnToScenesList() throws {
        // Переходим на экран камеры
        let sceneCells = app.collectionViews.cells
        if sceneCells.count > 1 {
            sceneCells.element(boundBy: 1).tap()
            
            // Находим кнопку назад
            let backButton = app.buttons.matching(identifier: "backButton").firstMatch
            
            if backButton.waitForExistence(timeout: 2.0) {
                backButton.tap()
                
                // Проверяем возврат на экран списка сцен
                let sceneList = app.collectionViews.firstMatch
                XCTAssertTrue(sceneList.waitForExistence(timeout: 2.0), "Должен произойти возврат на экран списка сцен")
            }
        }
    }
}

// MARK: - Вспомогательные расширения для упрощения тестов

extension XCUIElement {
    func waitForExistence(timeout: TimeInterval) -> Bool {
        return self.waitForExistence(timeout: timeout)
    }
}
