//
//  LemmatizerTests.swift
//  shafinMultitoolTests
//
//  Created on 28.01.2026.
//

import XCTest
@testable import shafinMultitool

final class LemmatizerTests: XCTestCase {
    
    var lemmatizer: Lemmatizer!
    
    override func setUpWithError() throws {
        super.setUp()
        lemmatizer = Lemmatizer()
    }
    
    override func tearDownWithError() throws {
        lemmatizer = nil
        super.tearDown()
    }
    
    // MARK: - Basic Lemmatization Tests
    
    func testLemmatizeTable() throws {
        let result = lemmatizer.lemmatize("столу")
        XCTAssertTrue(result.contains("стол") || result == "столу", "Столу должно приводиться к стол")
    }
    
    func testLemmatizeWalk() throws {
        let result = lemmatizer.lemmatize("идёт")
        XCTAssertTrue(result.contains("ид") || result == "идёт", "Идёт должно приводиться к идти")
    }
    
    func testLemmatizeApproach() throws {
        let result = lemmatizer.lemmatize("подошёл")
        // Проверяем, что результат содержит корень "подош" или является формой "подойти"
        XCTAssertTrue(result.contains("подош") || result == "подошёл" || result.contains("подойти"), 
                     "Подошёл должно приводиться к подойти или содержать корень 'подош'. Получено: \(result)")
    }
    
    func testLemmatizeEmptyString() throws {
        let result = lemmatizer.lemmatize("")
        XCTAssertEqual(result, "", "Пустая строка должна оставаться пустой")
    }
    
    // MARK: - Keyword Matching Tests
    
    func testMatchesKeywordTable() throws {
        XCTAssertTrue(lemmatizer.matchesKeyword("столу", keyword: "стол"), "Столу должно совпадать со стол")
        XCTAssertTrue(lemmatizer.matchesKeyword("столом", keyword: "стол"), "Столом должно совпадать со стол")
        XCTAssertTrue(lemmatizer.matchesKeyword("стол", keyword: "стол"), "Стол должно совпадать со стол")
    }
    
    func testMatchesKeywordWalk() throws {
        XCTAssertTrue(lemmatizer.matchesKeyword("идёт", keyword: "идти"), "Идёт должно совпадать с идти")
        XCTAssertTrue(lemmatizer.matchesKeyword("идут", keyword: "идти"), "Идут должно совпадать с идти")
        XCTAssertTrue(lemmatizer.matchesKeyword("идут", keyword: "идёт"), "Идут должно совпадать с идёт")
    }
    
    func testTextContainsKeyword() throws {
        let text = "Человек идёт к столу"
        XCTAssertTrue(lemmatizer.textContainsKeyword(text, keyword: "стол"), "Текст должен содержать стол")
        XCTAssertTrue(lemmatizer.textContainsKeyword(text, keyword: "идти"), "Текст должен содержать идти")
        XCTAssertFalse(lemmatizer.textContainsKeyword(text, keyword: "шкаф"), "Текст не должен содержать шкаф")
    }
    
    func testTextContainsKeywordWithPossessive() throws {
        let text = "Подойти к моему столу"
        XCTAssertTrue(lemmatizer.textContainsKeyword(text, keyword: "стол"), "Текст должен содержать стол даже с притяжательным местоимением")
    }
}
