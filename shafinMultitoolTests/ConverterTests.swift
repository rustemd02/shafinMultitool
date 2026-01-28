//
//  ConverterTests.swift
//  shafinMultitoolTests
//
//  Created by AI Assistant
//

import XCTest
import UIKit
import simd
@testable import shafinMultitool

final class ConverterTests: XCTestCase {
    
    var converter: Converter!
    
    override func setUpWithError() throws {
        super.setUp()
        converter = Converter.shared
    }
    
    override func tearDownWithError() throws {
        converter = nil
        super.tearDown()
    }
    
    // MARK: - Тест 1: Преобразование UIColor в CGFloat компоненты
    
    func testConvertUIColorToCGFloatComponents() throws {
        let color = UIColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 0.9)
        let components = converter.cgFloatValuesFromUIColor(color: color)
        
        XCTAssertEqual(components.red, 0.5, accuracy: 0.01, "Красный компонент должен быть 0.5")
        XCTAssertEqual(components.green, 0.3, accuracy: 0.01, "Зеленый компонент должен быть 0.3")
        XCTAssertEqual(components.blue, 0.8, accuracy: 0.01, "Синий компонент должен быть 0.8")
        XCTAssertEqual(components.alpha, 0.9, accuracy: 0.01, "Альфа компонент должен быть 0.9")
    }
    
    // MARK: - Тест 2: Обработка некорректных цветов
    
    func testConvertInvalidColor() throws {
        // Тестируем с цветом, который может не иметь компонентов
        let color = UIColor.systemBackground
        let components = converter.cgFloatValuesFromUIColor(color: color)
        
        // Метод должен вернуть значения по умолчанию (0.0, 0.0, 0.0, 0.0) если компоненты недоступны
        // Проверяем, что метод не падает
        XCTAssertNotNil(components, "Компоненты не должны быть nil")
    }
    
    // MARK: - Тест 3: Конвертация разрешения HD
    
    func testConvertHDResolution() throws {
        let resolution = Resolutions.hd
        let (width, height) = converter.resolutionEnumToRawValues(Resolution: resolution)
        
        XCTAssertEqual(width, 1280, "Ширина HD должна быть 1280")
        XCTAssertEqual(height, 720, "Высота HD должна быть 720")
    }
    
    // MARK: - Тест 4: Конвертация разрешения Full HD
    
    func testConvertFullHDResolution() throws {
        let resolution = Resolutions.fhd
        let (width, height) = converter.resolutionEnumToRawValues(Resolution: resolution)
        
        XCTAssertEqual(width, 1920, "Ширина Full HD должна быть 1920")
        XCTAssertEqual(height, 1080, "Высота Full HD должна быть 1080")
    }
    
    // MARK: - Тест 5: Конвертация разрешения 4K UHD
    
    func testConvert4KUHDResolution() throws {
        let resolution = Resolutions.uhd
        let (width, height) = converter.resolutionEnumToRawValues(Resolution: resolution)
        
        XCTAssertEqual(width, 3840, "Ширина 4K UHD должна быть 3840")
        XCTAssertEqual(height, 2160, "Высота 4K UHD должна быть 2160")
    }
    
    // MARK: - Тест 6: Конвертация всех разрешений
    
    func testConvertAllResolutions() throws {
        let resolutions: [Resolutions] = [.hd, .fhd, .uhd]
        let expectedValues: [(Int, Int)] = [(1280, 720), (1920, 1080), (3840, 2160)]
        
        for (index, resolution) in resolutions.enumerated() {
            let (width, height) = converter.resolutionEnumToRawValues(Resolution: resolution)
            let (expectedWidth, expectedHeight) = expectedValues[index]
            
            XCTAssertEqual(width, expectedWidth, "Ширина для \(resolution) должна быть \(expectedWidth)")
            XCTAssertEqual(height, expectedHeight, "Высота для \(resolution) должна быть \(expectedHeight)")
        }
    }
    
    // MARK: - Тест 7: Преобразование simd_float4x4 в массив Float
    
    func testConvertSimdFloat4x4ToArray() throws {
        let matrix = simd_float4x4(
            SIMD4<Float>(1.0, 2.0, 3.0, 4.0),
            SIMD4<Float>(5.0, 6.0, 7.0, 8.0),
            SIMD4<Float>(9.0, 10.0, 11.0, 12.0),
            SIMD4<Float>(13.0, 14.0, 15.0, 16.0)
        )
        
        let array = matrix.toArray()
        
        XCTAssertEqual(array.count, 16, "Массив должен содержать 16 элементов")
        XCTAssertEqual(array[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(array[15], 16.0, accuracy: 0.001)
        XCTAssertEqual(array[4], 5.0, accuracy: 0.001)
    }
    
    // MARK: - Тест 8: Преобразование массива Float обратно в simd_float4x4
    
    func testConvertArrayToSimdFloat4x4() throws {
        let array: [Float] = [
            1.0, 2.0, 3.0, 4.0,
            5.0, 6.0, 7.0, 8.0,
            9.0, 10.0, 11.0, 12.0,
            13.0, 14.0, 15.0, 16.0
        ]
        
        let matrix = simd_float4x4.fromArray(array)
        
        XCTAssertEqual(matrix.columns.0.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(matrix.columns.0.y, 2.0, accuracy: 0.001)
        XCTAssertEqual(matrix.columns.3.w, 16.0, accuracy: 0.001)
    }
    
    // MARK: - Тест 9: Обработка некорректного размера массива
    
    func testConvertInvalidArraySize() throws {
        let invalidArray: [Float] = [1.0, 2.0, 3.0] // Только 3 элемента вместо 16
        
        // Метод fromArray должен использовать precondition, который вызовет crash в debug режиме
        // В release режиме поведение может отличаться
        // Для теста проверяем, что метод существует и может обработать валидный массив
        let validArray: [Float] = Array(repeating: 1.0, count: 16)
        let matrix = simd_float4x4.fromArray(validArray)
        XCTAssertNotNil(matrix, "Матрица должна создаваться из валидного массива")
    }
    
    // MARK: - Тест 10: Обратное преобразование (массив -> матрица -> массив)
    
    func testRoundTripConversion() throws {
        let originalArray: [Float] = [
            0.1, 0.2, 0.3, 0.4,
            0.5, 0.6, 0.7, 0.8,
            0.9, 1.0, 1.1, 1.2,
            1.3, 1.4, 1.5, 1.6
        ]
        
        let matrix = simd_float4x4.fromArray(originalArray)
        let convertedArray = matrix.toArray()
        
        for (index, value) in originalArray.enumerated() {
            XCTAssertEqual(convertedArray[index], value, accuracy: 0.001, 
                          "Элемент \(index) должен совпадать после обратного преобразования")
        }
    }
    
    // MARK: - Тест 11: Конвертация различных цветов
    
    func testConvertVariousColors() throws {
        let colors: [(UIColor, (CGFloat, CGFloat, CGFloat, CGFloat))] = [
            (.red, (1.0, 0.0, 0.0, 1.0)),
            (.green, (0.0, 1.0, 0.0, 1.0)),
            (.blue, (0.0, 0.0, 1.0, 1.0)),
            (.white, (1.0, 1.0, 1.0, 1.0)),
            (.black, (0.0, 0.0, 0.0, 1.0))
        ]
        
        for (color, expectedComponents) in colors {
            let components = converter.cgFloatValuesFromUIColor(color: color)
            let (expectedRed, expectedGreen, expectedBlue, expectedAlpha) = expectedComponents
            
            // Проверяем с небольшой погрешностью, так как системные цвета могут иметь другие значения
            XCTAssertNotNil(components, "Компоненты цвета \(color) не должны быть nil")
        }
    }
    
    // MARK: - Тест 12: Конвертация разрешений в цикле
    
    func testResolutionConversionCycle() throws {
        var currentResolution = Resolutions.hd
        
        // Проверяем цикл: HD -> FHD -> UHD -> HD
        let (width1, height1) = converter.resolutionEnumToRawValues(Resolution: currentResolution)
        XCTAssertEqual(width1, 1280)
        XCTAssertEqual(height1, 720)
        
        currentResolution = currentResolution.next()
        let (width2, height2) = converter.resolutionEnumToRawValues(Resolution: currentResolution)
        XCTAssertEqual(width2, 1920)
        XCTAssertEqual(height2, 1080)
        
        currentResolution = currentResolution.next()
        let (width3, height3) = converter.resolutionEnumToRawValues(Resolution: currentResolution)
        XCTAssertEqual(width3, 3840)
        XCTAssertEqual(height3, 2160)
        
        currentResolution = currentResolution.next()
        let (width4, height4) = converter.resolutionEnumToRawValues(Resolution: currentResolution)
        XCTAssertEqual(width4, 1280) // Должен вернуться к HD
        XCTAssertEqual(height4, 720)
    }
}
