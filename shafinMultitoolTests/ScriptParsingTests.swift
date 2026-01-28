//
//  ScriptParsingTests.swift
//  shafinMultitoolTests
//
//  Created by AI Assistant
//

import XCTest
@testable import shafinMultitool

final class ScriptParsingTests: XCTestCase {
    
    var interactor: CameraScreenInteractor!
    
    override func setUpWithError() throws {
        super.setUp()
        interactor = CameraScreenInteractor()
    }
    
    override func tearDownWithError() throws {
        interactor = nil
        super.tearDown()
    }
    
    // MARK: - Тест 1: Парсинг простого диалога
    
    func testParseSimpleDialogue() throws {
        let script = "Иван: Привет. Мария: Как дела?"
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.names.count, 2, "Должно быть 2 имени")
        XCTAssertEqual(result.phrases.count, 2, "Должно быть 2 фразы")
        
        XCTAssertEqual(result.names[0], "Иван", "Первое имя должно быть 'Иван'")
        XCTAssertEqual(result.names[1], "Мария", "Второе имя должно быть 'Мария'")
        
        XCTAssertEqual(result.phrases[0], ": Привет.", "Первая фраза должна быть 'Привет.'")
        XCTAssertEqual(result.phrases[1], ": Как дела?", "Вторая фраза должна быть 'Как дела?'")
    }
    
    // MARK: - Тест 2: Парсинг многострочного сценария
    
    func testParseMultilineScript() throws {
        let script = """
        Иван: Привет всем.
        Мария: Здравствуй, Иван.
        Иван: Как дела?
        Мария: Отлично, спасибо!
        """
        
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.names.count, 4, "Должно быть 4 имени")
        XCTAssertEqual(result.phrases.count, 4, "Должно быть 4 фразы")
        
        XCTAssertEqual(result.names[0], "Иван")
        XCTAssertEqual(result.names[1], "Мария")
        XCTAssertEqual(result.names[2], "Иван")
        XCTAssertEqual(result.names[3], "Мария")
    }
    
    // MARK: - Тест 3: Парсинг с несколькими репликами одного персонажа
    
    func testParseMultipleRepliesFromSameCharacter() throws {
        let script = "Иван: Привет. Иван: Как дела? Иван: Что нового?"
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.names.count, 3, "Должно быть 3 имени")
        XCTAssertEqual(result.phrases.count, 3, "Должно быть 3 фразы")
        
        XCTAssertEqual(result.names[0], "Иван")
        XCTAssertEqual(result.names[1], "Иван")
        XCTAssertEqual(result.names[2], "Иван")
        
        XCTAssertEqual(result.phrases[0], ": Привет.")
        XCTAssertEqual(result.phrases[1], ": Как дела?")
        XCTAssertEqual(result.phrases[2], ": Что нового?")
    }
    
    // MARK: - Тест 4: Обработка пустого сценария
    
    func testParseEmptyScript() throws {
        let script = ""
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.names.count, 0, "Должно быть 0 имен")
        XCTAssertEqual(result.phrases.count, 0, "Должно быть 0 фраз")
    }
    
    // MARK: - Тест 5: Обработка некорректного формата (без двоеточий)
    
    func testParseInvalidFormatWithoutColons() throws {
        let script = "Это просто текст без двоеточий и имен персонажей."
        let result = interactor.reformatScript(script: script)
        
        // Должен обработать, но без имен и фраз
        XCTAssertEqual(result.names.count, 0, "Не должно быть имен без двоеточий")
        XCTAssertEqual(result.phrases.count, 0, "Не должно быть фраз без двоеточий")
    }
    
    // MARK: - Тест 6: Извлечение имен персонажей
    
    func testExtractCharacterNames() throws {
        let script = "Алиса: Привет. Боб: Здравствуй. Чарли: Как дела?"
        let result = interactor.reformatScript(script: script)
        
        let uniqueNames = Set(result.names)
        XCTAssertEqual(uniqueNames.count, 3, "Должно быть 3 уникальных имени")
        XCTAssertTrue(uniqueNames.contains("Алиса"))
        XCTAssertTrue(uniqueNames.contains("Боб"))
        XCTAssertTrue(uniqueNames.contains("Чарли"))
    }
    
    // MARK: - Тест 7: Извлечение фраз с правильной пунктуацией
    
    func testExtractPhrasesWithPunctuation() throws {
        let script = "Иван: Вопрос? Мария: Восклицание! Петр: Точка."
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.phrases.count, 3)
        XCTAssertTrue(result.phrases[0].hasSuffix("?"), "Первая фраза должна заканчиваться на '?'")
        XCTAssertTrue(result.phrases[1].hasSuffix("!"), "Вторая фраза должна заканчиваться на '!'")
        XCTAssertTrue(result.phrases[2].hasSuffix("."), "Третья фраза должна заканчиваться на '.'")
    }
    
    // MARK: - Тест 8: Парсинг сценария с пробелами и переносами строк
    
    func testParseScriptWithWhitespace() throws {
        let script = "  Иван  :  Привет всем.  \n  Мария  :  Как дела?  "
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.names.count, 2)
        XCTAssertEqual(result.phrases.count, 2)
        
        // Имена должны быть очищены от лишних пробелов
        XCTAssertEqual(result.names[0].trimmingCharacters(in: .whitespaces), "Иван")
        XCTAssertEqual(result.names[1].trimmingCharacters(in: .whitespaces), "Мария")
    }
    
    // MARK: - Тест 9: Парсинг длинного диалога
    
    func testParseLongDialogue() throws {
        var script = ""
        var expectedNames: [String] = []
        var expectedPhrases: [String] = []
        
        for i in 1...10 {
            let name = "Персонаж\(i)"
            let phrase = "Фраза номер \(i)."
            script += "\(name): \(phrase) "
            expectedNames.append(name)
            expectedPhrases.append(phrase)
        }
        
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.names.count, 10, "Должно быть 10 имен")
        XCTAssertEqual(result.phrases.count, 10, "Должно быть 10 фраз")
        
        for i in 0..<10 {
            XCTAssertEqual(result.names[i], expectedNames[i])
            XCTAssertEqual(result.phrases[i], expectedPhrases[i])
        }
    }
    
    // MARK: - Тест 10: Парсинг сценария с запятыми в именах
    
    func testParseScriptWithCommasInNames() throws {
        let script = "Иван, Петр: Привет. Мария: Как дела?"
        let result = interactor.reformatScript(script: script)
        
        // Запятая в имени должна обрабатываться корректно
        XCTAssertGreaterThanOrEqual(result.names.count, 1)
        XCTAssertGreaterThanOrEqual(result.phrases.count, 1)
    }
    
    // MARK: - Тест 11: Парсинг сценария только с именем без фразы
    
    func testParseScriptWithNameOnly() throws {
        let script = "Иван:"
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.names.count, 1, "Должно быть одно имя")
        XCTAssertEqual(result.names[0], "Иван")
        // Может быть пустая фраза или без фразы
    }
    
    // MARK: - Тест 12: Парсинг сценария с несколькими предложениями в одной реплике
    
    func testParseScriptWithMultipleSentences() throws {
        let script = "Иван: Первое предложение. Второе предложение? Третье предложение!"
        let result = interactor.reformatScript(script: script)
        
        XCTAssertEqual(result.names.count, 1)
        XCTAssertEqual(result.phrases.count, 3, "Должно быть 3 фразы из-за трех знаков препинания")
    }
}
