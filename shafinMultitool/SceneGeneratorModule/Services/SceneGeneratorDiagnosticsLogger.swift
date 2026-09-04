//
//  SceneGeneratorDiagnosticsLogger.swift
//  shafinMultitool
//
//  Created by Codex on 23.06.2026.
//

import Foundation

#if !DEBUG
@inline(__always) func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

final class SceneGeneratorDiagnosticsLogger {
    static let shared = SceneGeneratorDiagnosticsLogger()

    private init() {}

    func log(_ message: @autoclosure () -> String) {
#if DEBUG
        let entry = "[\(Self.timestampFormatter.string(from: Date()))] \(message())"
        print(entry)
#endif
    }

    func flush() {
        // Console-only diagnostics; Xcode console is the source of truth for this path.
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
