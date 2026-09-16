import XCTest
@testable import shafinMultitool

final class SceneScriptsMarkdownSmokeTests: XCTestCase {
    private let liveModelOverrideKey = "scene_generator_llm_model_path"
    private let v9RuntimeModeKey = "scene_generator_v9_runtime_mode"
    /// Derived from this file's location, not from one machine's absolute path:
    /// the hardcoded paths this used to carry made the smoke test unusable from any
    /// other checkout while still looking configured.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    private let scriptsPath = SceneScriptsMarkdownSmokeTests.repositoryRoot + "/scripts/scripts.md"
    private let modelPath = SceneScriptsMarkdownSmokeTests.repositoryRoot
        + "/shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf"
    private let outputPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("scene_scripts_md_results.json").path
    private let maxChunkCharacters = 5_000
    private let minMeaningfulUnitCharacters = 250

    private struct ScriptCase {
        let index: Int
        let originalText: String
        let text: String

        var preview: String {
            let compact = text.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(compact.prefix(160))
        }
    }

    private struct CaseOutput: Codable {
        struct ChunkOutput: Codable {
            let chunkIndex: Int
            let preview: String
            let characterCount: Int
            let elapsedSeconds: Double
            let route: String?
            let actorCount: Int
            let objectCount: Int
            let beatCount: Int
            let actionCount: Int
            let diagnosticsConfidence: Float
            let diagnosticsCoverage: Float
            let chunkReasonCodes: [String]
            let usedFallbackPlanner: Bool
            let hasActiveScene: Bool
            let notes: [String]
            let script: SceneScript?
        }

        let index: Int
        let preview: String
        let characterCount: Int
        let preprocessedCharacterCount: Int
        let chunkCount: Int
        let elapsedSecondsTotal: Double
        let chunks: [ChunkOutput]
    }

    func testRunLocalModelOnScriptsMarkdownCases() async throws {
        guard ProcessInfo.processInfo.environment["SG_RUN_SCRIPTS_MD_SMOKE"] == "1" else {
            throw XCTSkip("Set SG_RUN_SCRIPTS_MD_SMOKE=1 to run the live scripts.md local-model smoke test.")
        }

        let scriptCases = try loadScriptCases()
        XCTAssertEqual(scriptCases.count, 3, "Expected exactly 3 non-empty script cases in scripts.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelPath), "Expected local V9 GGUF model")

        let defaults = UserDefaults.standard
        let previousModelOverride = defaults.string(forKey: liveModelOverrideKey)
        let previousRuntimeMode = defaults.string(forKey: v9RuntimeModeKey)
        defaults.set(modelPath, forKey: liveModelOverrideKey)
        defaults.set("v9_full", forKey: v9RuntimeModeKey)
        defer {
            if let previousModelOverride {
                defaults.set(previousModelOverride, forKey: liveModelOverrideKey)
            } else {
                defaults.removeObject(forKey: liveModelOverrideKey)
            }
            if let previousRuntimeMode {
                defaults.set(previousRuntimeMode, forKey: v9RuntimeModeKey)
            } else {
                defaults.removeObject(forKey: v9RuntimeModeKey)
            }
        }

        let parser = SceneParserService.shared
        let llm = LLMParserService.shared
        parser.resetRuntimeContext()
        await llm.loadModelIfNeeded()
        XCTAssertTrue(llm.isAvailable, "Expected local LLM to be available")

        var outputs: [CaseOutput] = []
        var summaryLines: [String] = []

        for scriptCase in scriptCases {
            let chunkTexts = splitIntoChunks(scriptCase.text, maxCharacters: maxChunkCharacters)
            var chunkOutputs: [CaseOutput.ChunkOutput] = []
            var elapsedTotal: Double = 0

            for (chunkOffset, chunkText) in chunkTexts.enumerated() {
                parser.resetRuntimeContext()
                let start = Date()
                let result = await parser.parseBundle(chunkText, markedObjects: [])
                let elapsedSeconds = Date().timeIntervalSince(start)
                elapsedTotal += elapsedSeconds
                let activeScene = result.activeSceneScript
                let trace = parser.lastRuntimeTrace

                let chunkOutput = CaseOutput.ChunkOutput(
                    chunkIndex: chunkOffset + 1,
                    preview: makePreview(from: chunkText),
                    characterCount: chunkText.count,
                    elapsedSeconds: elapsedSeconds,
                    route: trace?.route.rawValue,
                    actorCount: activeScene?.actors.count ?? 0,
                    objectCount: activeScene?.objects.count ?? 0,
                    beatCount: activeScene?.beats.count ?? 0,
                    actionCount: activeScene?.actions.count ?? 0,
                    diagnosticsConfidence: result.diagnostics.confidence,
                    diagnosticsCoverage: result.diagnostics.coverage,
                    chunkReasonCodes: result.chunkDiagnostics.flatMap(\.reasonCodes),
                    usedFallbackPlanner: result.chunkDiagnostics.contains(where: \.usedFallbackPlanner),
                    hasActiveScene: activeScene != nil,
                    notes: result.diagnostics.notes,
                    script: activeScene
                )
                chunkOutputs.append(chunkOutput)

                let partialOutput = CaseOutput(
                    index: scriptCase.index,
                    preview: scriptCase.preview,
                    characterCount: scriptCase.originalText.count,
                    preprocessedCharacterCount: scriptCase.text.count,
                    chunkCount: chunkOutputs.count,
                    elapsedSecondsTotal: elapsedTotal,
                    chunks: chunkOutputs
                )
                persistOutputs(outputs + [partialOutput])
            }

            let output = CaseOutput(
                index: scriptCase.index,
                preview: scriptCase.preview,
                characterCount: scriptCase.originalText.count,
                preprocessedCharacterCount: scriptCase.text.count,
                chunkCount: chunkOutputs.count,
                elapsedSecondsTotal: elapsedTotal,
                chunks: chunkOutputs
            )
            outputs.append(output)

            summaryLines.append(
                """
                case=\(output.index) chars=\(output.characterCount) preprocessed=\(output.preprocessedCharacterCount) chunks=\(output.chunkCount) elapsed_total=\(String(format: "%.1f", output.elapsedSecondsTotal))s preview=\(output.preview)
                """
            )
            summaryLines.append(contentsOf: output.chunks.map { chunk in
                """
                  chunk=\(chunk.chunkIndex) chars=\(chunk.characterCount) elapsed=\(String(format: "%.1f", chunk.elapsedSeconds))s route=\(chunk.route ?? "nil") active=\(chunk.hasActiveScene) actors=\(chunk.actorCount) objects=\(chunk.objectCount) beats=\(chunk.beatCount) actions=\(chunk.actionCount) fallback=\(chunk.usedFallbackPlanner) confidence=\(String(format: "%.2f", chunk.diagnosticsConfidence)) preview=\(chunk.preview)
                """
            })
        }

        persistOutputs(outputs)

        let summary = summaryLines.joined(separator: "\n")
        await MainActor.run {
            XCTContext.runActivity(named: "scripts.md live smoke summary") { activity in
                let attachment = XCTAttachment(string: summary)
                attachment.name = "scripts-md-live-summary.txt"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }

        XCTAssertEqual(outputs.count, 3)
    }

    private func loadScriptCases() throws -> [ScriptCase] {
        let contents = try String(contentsOfFile: scriptsPath, encoding: .utf8)
        return contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { offset, text in
                ScriptCase(
                    index: offset + 1,
                    originalText: text,
                    text: preprocessScript(text)
                )
            }
    }

    private func splitIntoChunks(_ text: String, maxCharacters: Int) -> [String] {
        let sceneUnits = mergeTinyUnits(
            splitIntoSceneUnits(text),
            minCharacters: minMeaningfulUnitCharacters
        )
        guard !sceneUnits.isEmpty else { return [text] }

        var chunks: [String] = []
        var currentUnits: [String] = []
        var currentLength = 0

        func flushCurrentUnits() {
            guard !currentUnits.isEmpty else { return }
            chunks.append(currentUnits.joined(separator: "\n"))
            currentUnits.removeAll()
            currentLength = 0
        }

        for unit in sceneUnits {
            let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUnit.isEmpty else { continue }

            if trimmedUnit.count > maxCharacters {
                flushCurrentUnits()
                chunks.append(contentsOf: splitOversizedUnit(trimmedUnit, maxCharacters: maxCharacters))
                continue
            }

            let separatorLength = currentUnits.isEmpty ? 0 : 1
            if currentLength + separatorLength + trimmedUnit.count > maxCharacters {
                flushCurrentUnits()
            }

            currentUnits.append(trimmedUnit)
            currentLength += separatorLength + trimmedUnit.count
        }

        flushCurrentUnits()
        return chunks.isEmpty ? [text] : chunks
    }

    private func splitIntoSceneUnits(_ text: String) -> [String] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        var units: [String] = []
        var currentLines: [String] = []

        func flushCurrentLines() {
            guard !currentLines.isEmpty else { return }
            units.append(currentLines.joined(separator: "\n"))
            currentLines.removeAll()
        }

        for line in lines {
            if isSceneBoundary(line), !currentLines.isEmpty {
                flushCurrentLines()
            }
            currentLines.append(line)
        }

        flushCurrentLines()
        return units
    }

    private func splitOversizedUnit(_ unit: String, maxCharacters: Int) -> [String] {
        let lines = unit
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [unit] }

        var chunks: [String] = []
        var currentLines: [String] = []
        var currentLength = 0

        func flushCurrentLines() {
            guard !currentLines.isEmpty else { return }
            chunks.append(currentLines.joined(separator: "\n"))
            currentLines.removeAll()
            currentLength = 0
        }

        for line in lines {
            if line.count > maxCharacters {
                flushCurrentLines()
                var startIndex = line.startIndex
                while startIndex < line.endIndex {
                    let endIndex = line.index(startIndex, offsetBy: maxCharacters, limitedBy: line.endIndex) ?? line.endIndex
                    chunks.append(String(line[startIndex..<endIndex]))
                    startIndex = endIndex
                }
                continue
            }

            let separatorLength = currentLines.isEmpty ? 0 : 1
            if currentLength + separatorLength + line.count > maxCharacters {
                flushCurrentLines()
            }

            currentLines.append(line)
            currentLength += separatorLength + line.count
        }

        flushCurrentLines()
        return chunks.isEmpty ? [unit] : chunks
    }

    private func mergeTinyUnits(_ units: [String], minCharacters: Int) -> [String] {
        guard !units.isEmpty else { return [] }

        var merged: [String] = []
        var index = 0

        while index < units.count {
            var current = units[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !current.isEmpty else {
                index += 1
                continue
            }

            while current.count < minCharacters, index + 1 < units.count {
                index += 1
                let next = units[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !next.isEmpty {
                    current += "\n" + next
                }
            }

            if current.count < minCharacters, let last = merged.popLast() {
                merged.append(last + "\n" + current)
            } else {
                merged.append(current)
            }

            index += 1
        }

        return merged
    }

    private func isSceneBoundary(_ line: String) -> Bool {
        let uppercased = line.uppercased()
        return uppercased.hasPrefix("ИНТ.")
            || uppercased.hasPrefix("ЭКСТ.")
            || uppercased.hasPrefix("INT.")
            || uppercased.hasPrefix("EXT.")
            || uppercased.hasPrefix("ПЛАН НА:")
            || uppercased.hasPrefix("ВЫХОД ИЗ ЗАТЕМНЕНИЯ:")
            || uppercased.hasPrefix("ЧЕРНЫЙ ЭКРАН")
            || uppercased.hasPrefix("КОНЕЦ ТИЗЕРА")
            || uppercased.hasPrefix("ПЕРВЫЙ АКТ")
            || uppercased.hasPrefix("ВТОРОЙ АКТ")
            || uppercased.hasPrefix("ТРЕТИЙ АКТ")
    }

    private func preprocessScript(_ text: String) -> String {
        var output = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let markers = [
            "ПЛАН НА:",
            "ВЫХОД ИЗ ЗАТЕМНЕНИЯ:",
            "ЧЕРНЫЙ ЭКРАН",
            "КОНЕЦ ТИЗЕРА",
            "ПЕРВЫЙ АКТ",
            "ВТОРОЙ АКТ",
            "ТРЕТИЙ АКТ",
            "ИНТ.",
            "ЭКСТ.",
            "INT.",
            "EXT."
        ]

        for marker in markers {
            output = output.replacingOccurrences(
                of: marker,
                with: "\n\(marker)"
            )
        }

        output = output.replacingOccurrences(
            of: #"(?<=[.!?…])\s+(?=[A-ZА-ЯЁ0-9"«])"#,
            with: "\n",
            options: .regularExpression
        )

        output = output.replacingOccurrences(
            of: #"\n+"#,
            with: "\n",
            options: .regularExpression
        )

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makePreview(from text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(compact.prefix(160))
    }

    private func persistOutputs(_ outputs: [CaseOutput]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(outputs) else { return }
        try? data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }
}
