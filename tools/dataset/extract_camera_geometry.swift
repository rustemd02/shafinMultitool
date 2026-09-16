// Offline, research-only geometry extraction for already verified Camera
// source inventories. Raw media and generated outputs stay outside Git.

import CoreFoundation
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import Vision

private let schemaID = "camera-silver-geometry-v1"
private let schemaVersion = "1.0.0"
private let receiptSchemaID = "camera-silver-geometry-receipt-v1"
private let toolRelativePath = "tools/dataset/extract_camera_geometry.swift"
private let selectionConfidenceFloor = 0.5
private let selectionTieMargin = 0.15
private let saliencyConfidenceFloor = 0.5

private enum GeometryError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let value): return value
        }
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func isLowercaseSHA256(_ value: String) -> Bool {
    guard value.utf8.count == 64 else { return false }
    return value.utf8.allSatisfy { byte in
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
    }
}

private func canonicalJSON(_ value: Any) throws -> Data {
    guard JSONSerialization.isValidJSONObject(value) else {
        throw GeometryError.message("value cannot be serialized as JSON")
    }
    do {
        return try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    } catch {
        throw GeometryError.message("cannot serialize JSON")
    }
}

private func jsonLine(_ value: Any) throws -> Data {
    var data = try canonicalJSON(value)
    data.append(0x0a)
    return data
}

private func expandedURL(_ value: String) -> URL {
    URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
}

private func fileMode(_ url: URL) -> mode_t? {
    var info = Darwin.stat()
    let result = url.path.withCString { Darwin.lstat($0, &info) }
    return result == 0 ? info.st_mode : nil
}

private func isSymlink(_ url: URL) -> Bool {
    guard let mode = fileMode(url) else { return false }
    return (mode & 0o170000) == 0o120000
}

private func isRegularFile(_ url: URL) -> Bool {
    guard let mode = fileMode(url) else { return false }
    return (mode & 0o170000) == 0o100000
}

private func isDirectory(_ url: URL) -> Bool {
    guard let mode = fileMode(url) else { return false }
    return (mode & 0o170000) == 0o040000
}

private func assertNoSymlinkComponents(_ url: URL) throws {
    // Inspect the lexical path before any symlink resolution (or dot-segment
    // normalization). `relativePath` preserves the caller's spelling even
    // when URL.path has already normalized it.
    let rawPath = url.relativePath
    let absolutePath = rawPath.hasPrefix("/")
        ? rawPath
        : FileManager.default.currentDirectoryPath + "/" + rawPath
    var current = URL(fileURLWithPath: "/")
    for component in absolutePath.split(separator: "/") {
        let value = String(component)
        if value == "." { continue }
        if value == ".." {
            current.deleteLastPathComponent()
            continue
        }
        current.appendPathComponent(value)
        // macOS exposes temporary locations through harmless /var and /tmp
        // aliases; reject every other lexical symlink so corpus paths cannot
        // redirect outside the root.
        if current.path != "/var", current.path != "/tmp", isSymlink(current) {
            throw GeometryError.message("path uses a symlink: \(current.path)")
        }
    }
}

private func isWithin(_ child: URL, _ parent: URL) -> Bool {
    let childPath = child.standardizedFileURL.path
    let parentPath = parent.standardizedFileURL.path
    return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL
}

private func validateExternalDirectory(
    _ input: URL,
    repository: URL,
    label: String,
    mustExist: Bool
) throws -> (url: URL, existed: Bool) {
    try assertNoSymlinkComponents(input)
    let lexical = input.standardizedFileURL
    guard !isSymlink(lexical) else {
        throw GeometryError.message("\(label) must not be a symlink")
    }
    let standardized = lexical.resolvingSymlinksInPath().standardizedFileURL
    try assertNoSymlinkComponents(standardized)
    let existed = fileMode(standardized) != nil
    if existed {
        guard !isSymlink(standardized), isDirectory(standardized) else {
            throw GeometryError.message("\(label) must be a regular directory")
        }
    } else if mustExist {
        throw GeometryError.message("\(label) must be an existing directory")
    }

    let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
    if isWithin(resolved, repository) || isWithin(repository, resolved) {
        throw GeometryError.message("\(label) must be outside the repository")
    }
    return (resolved, existed)
}

private func safeRelativePath(_ value: String, root: URL) throws -> (url: URL, relative: String) {
    guard !value.isEmpty, !value.contains("\0") else {
        throw GeometryError.message("relative_path must be a non-empty relative path")
    }
    let normalized = value.replacingOccurrences(of: "\\", with: "/")
    let parts = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !normalized.hasPrefix("/"), !parts.isEmpty,
          !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
          !parts[0].contains(":") else {
        throw GeometryError.message("relative_path is not safely relative")
    }

    var candidate = root
    for part in parts {
        candidate.appendPathComponent(part, isDirectory: false)
        if isSymlink(candidate) {
            throw GeometryError.message("relative_path uses a symlink: \(normalized)")
        }
    }
    let standardized = candidate.standardizedFileURL
    guard isWithin(standardized, root) else {
        throw GeometryError.message("relative_path escapes source-root")
    }
    return (standardized, normalized)
}

private func readRegularFile(_ url: URL, label: String) throws -> Data {
    try assertNoSymlinkComponents(url)
    let lexical = url.standardizedFileURL
    guard !isSymlink(lexical) else {
        throw GeometryError.message("\(label) is not a regular file")
    }
    let canonical = lexical.resolvingSymlinksInPath().standardizedFileURL
    try assertNoSymlinkComponents(canonical)
    guard !isSymlink(canonical), isRegularFile(canonical) else {
        throw GeometryError.message("\(label) is not a regular file")
    }
    do {
        let data = try Data(contentsOf: canonical, options: [.mappedIfSafe])
        guard !isSymlink(canonical), isRegularFile(canonical) else {
            throw GeometryError.message("\(label) changed to a non-regular file")
        }
        return data
    } catch let error as GeometryError {
        throw error
    } catch {
        throw GeometryError.message("cannot read \(label)")
    }
}

private func writeAndSync(_ data: Data, to url: URL) throws {
    do {
        try data.write(to: url, options: [.atomic])
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
    } catch {
        throw GeometryError.message("cannot write staged output: \(url.lastPathComponent)")
    }
}

private func syncDirectory(_ url: URL) {
    let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY) }
    if descriptor >= 0 {
        _ = Darwin.fsync(descriptor)
        _ = Darwin.close(descriptor)
    }
}

private func jsonString(_ value: Any?, field: String) throws -> String {
    guard let value = value as? String, !value.isEmpty, !value.contains("\0") else {
        throw GeometryError.message("\(field) must be a non-empty string")
    }
    return value
}

private func jsonInt(_ value: Any?, field: String) throws -> Int64 {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else {
        throw GeometryError.message("\(field) must be an integer")
    }
    let doubleValue = number.doubleValue
    guard doubleValue.isFinite,
          doubleValue.rounded() == doubleValue,
          doubleValue >= Double(Int64.min),
          doubleValue <= Double(Int64.max) else {
        throw GeometryError.message("\(field) must be a finite integer")
    }
    return number.int64Value
}

private func jsonBool(_ value: Any?, field: String) throws -> Bool {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else {
        throw GeometryError.message("\(field) must be a boolean")
    }
    return number.boolValue
}

private func validateMetadata(_ value: Any, path: String) throws {
    if let dictionary = value as? [String: Any] {
        let policyTokens = ["rights", "license", "consent", "release", "gold", "admission", "approved"]
        for (key, child) in dictionary {
            if policyTokens.contains(where: { key.lowercased().contains($0) }) {
                throw GeometryError.message("policy-bearing metadata is not accepted: \(path).\(key)")
            }
            try validateMetadata(child, path: "\(path).\(key)")
        }
    } else if let array = value as? [Any] {
        for (index, child) in array.enumerated() {
            try validateMetadata(child, path: "\(path)[\(index)]")
        }
    } else if let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !number.doubleValue.isFinite {
        throw GeometryError.message("metadata contains a non-finite number: \(path)")
    } else if value is String || value is NSNumber || value is NSNull {
        return
    } else {
        throw GeometryError.message("unsupported inventory metadata: \(path)")
    }
}

private struct InventoryEntry {
    let sourceID: String
    let sourceRecordID: String
    let relativePath: String
    let mediaURL: URL
    let sha256: String
    let byteCount: Int64
    let width: Int
    let height: Int
    let format: String
}

private func inventoryIdentifier(_ value: String, field: String, allowSlash: Bool) throws -> String {
    guard !value.isEmpty,
          !value.contains(where: { $0.isWhitespace || $0.isNewline }),
          !value.unicodeScalars.contains(where: { $0.value < 0x20 }),
          !value.contains("\0") else {
        throw GeometryError.message("\(field) is not a safe identifier")
    }
    if !allowSlash && (value.contains("/") || value.contains("\\")) {
        throw GeometryError.message("\(field) must not contain a path separator")
    }
    return value
}

private func parseInventory(_ data: Data, sourceRoot: URL) throws -> [InventoryEntry] {
    guard let text = String(data: data, encoding: .utf8) else {
        throw GeometryError.message("inventory is not valid UTF-8")
    }
    let rawLines = text.components(separatedBy: .newlines)
    let allowed: Set<String> = [
        "byte_count", "format", "height", "human_gold", "intake_tier",
        "relative_path", "release_admissible", "sha256", "source_id",
        "source_record_id", "width", "upstream_metadata"
    ]
    let required: Set<String> = [
        "byte_count", "format", "height", "human_gold", "intake_tier",
        "relative_path", "release_admissible", "sha256", "source_id",
        "source_record_id", "width"
    ]
    var entries: [InventoryEntry] = []
    var seenPairs = Set<String>()
    var seenPaths = Set<String>()
    for (lineIndex, rawLine) in rawLines.enumerated() {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            if lineIndex == rawLines.count - 1 { continue }
            throw GeometryError.message("inventory has a blank line at \(lineIndex + 1)")
        }
        guard let object = try? JSONSerialization.jsonObject(
            with: Data(line.utf8), options: [.fragmentsAllowed]
        ) as? [String: Any] else {
            throw GeometryError.message("inventory line \(lineIndex + 1) is malformed JSON")
        }
        let keys = Set(object.keys)
        let unknown = keys.subtracting(allowed)
        if !unknown.isEmpty {
            throw GeometryError.message(
                "inventory line \(lineIndex + 1) has unknown fields: \(unknown.sorted().joined(separator: ","))"
            )
        }
        let missing = required.subtracting(keys)
        if !missing.isEmpty {
            throw GeometryError.message(
                "inventory line \(lineIndex + 1) is missing fields: \(missing.sorted().joined(separator: ","))"
            )
        }

        let sourceID = try inventoryIdentifier(
            jsonString(object["source_id"], field: "source_id"), field: "source_id", allowSlash: true
        )
        let sourceRecordID = try inventoryIdentifier(
            jsonString(object["source_record_id"], field: "source_record_id"), field: "source_record_id", allowSlash: false
        )
        let relativeValue = try jsonString(object["relative_path"], field: "relative_path")
        let (mediaURL, relativePath) = try safeRelativePath(relativeValue, root: sourceRoot)
        let pair = sourceID + "\u{1f}" + sourceRecordID
        guard seenPairs.insert(pair).inserted else {
            throw GeometryError.message("duplicate source_id/source_record_id: \(sourceID)/\(sourceRecordID)")
        }
        guard seenPaths.insert(relativePath).inserted else {
            throw GeometryError.message("duplicate relative_path: \(relativePath)")
        }
        let digest = try jsonString(object["sha256"], field: "sha256")
        guard isLowercaseSHA256(digest) else {
            throw GeometryError.message("sha256 must be a lowercase SHA-256 digest")
        }
        let byteCount = try jsonInt(object["byte_count"], field: "byte_count")
        guard byteCount > 0 else {
            throw GeometryError.message("byte_count must be positive")
        }
        let width = try jsonInt(object["width"], field: "width")
        let height = try jsonInt(object["height"], field: "height")
        guard width > 0, height > 0,
              width <= Int64(Int.max), height <= Int64(Int.max) else {
            throw GeometryError.message("inventory dimensions must be positive")
        }
        let format = try jsonString(object["format"], field: "format").lowercased()
        guard format.utf8.allSatisfy({
            ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 46 || $0 == 43 || $0 == 45
        }) else {
            throw GeometryError.message("format is not a recognized inventory value")
        }
        guard try jsonString(object["intake_tier"], field: "intake_tier") == "research_only",
              try jsonBool(object["human_gold"], field: "human_gold") == false,
              try jsonBool(object["release_admissible"], field: "release_admissible") == false else {
            throw GeometryError.message("inventory row is not immutable research_only metadata")
        }
        if let upstream = object["upstream_metadata"] {
            try validateMetadata(upstream, path: "upstream_metadata")
        }
        entries.append(InventoryEntry(
            sourceID: sourceID,
            sourceRecordID: sourceRecordID,
            relativePath: relativePath,
            mediaURL: mediaURL,
            sha256: digest,
            byteCount: byteCount,
            width: Int(width),
            height: Int(height),
            format: format
        ))
    }
    guard !entries.isEmpty else {
        throw GeometryError.message("inventory contains no rows")
    }
    return entries.sorted {
        if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
        if $0.sourceRecordID != $1.sourceRecordID { return $0.sourceRecordID < $1.sourceRecordID }
        return $0.relativePath < $1.relativePath
    }
}

private struct OrientationInfo {
    let tag: Int
    let name: String
    let cgOrientation: CGImagePropertyOrientation
    let exifPresent: Bool

    init(tag: Int?, propertiesPresent: Bool) throws {
        let value = tag ?? 1
        guard (1...8).contains(value),
              let orientation = CGImagePropertyOrientation(rawValue: UInt32(value)) else {
            throw GeometryError.message("image EXIF orientation is not one of 1..8")
        }
        self.tag = value
        self.cgOrientation = orientation
        self.exifPresent = propertiesPresent
        switch value {
        case 1: self.name = "up"
        case 2: self.name = "up_mirrored"
        case 3: self.name = "down"
        case 4: self.name = "down_mirrored"
        case 5: self.name = "left_mirrored"
        case 6: self.name = "right"
        case 7: self.name = "right_mirrored"
        case 8: self.name = "left"
        default: self.name = "up"
        }
    }

    var swapsDimensions: Bool {
        (5...8).contains(tag)
    }
}

private func clamp01(_ value: Double) -> Double {
    Swift.min(1.0, Swift.max(0.0, value))
}

private func comesBefore(_ lhs: [Double], _ rhs: [Double]) -> Bool {
    for (left, right) in zip(lhs, rhs) where left != right {
        return left < right
    }
    return false
}

private struct DecodedImage {
    let image: CGImage
    let format: String
    let orientation: OrientationInfo

    var decodedWidth: Int { image.width }
    var decodedHeight: Int { image.height }
    var orientedWidth: Int { orientation.swapsDimensions ? decodedHeight : decodedWidth }
    var orientedHeight: Int { orientation.swapsDimensions ? decodedWidth : decodedHeight }
}

private func canonicalImageFormat(uti: String) -> String? {
    let value = uti.lowercased()
    if value.contains("jpeg") || value == "public.jpg" { return "jpeg" }
    if value.contains("png") { return "png" }
    if value.contains("webp") { return "webp" }
    if value.contains("heic") { return "heic" }
    if value.contains("heif") { return "heif" }
    if value.contains("tiff") { return "tiff" }
    if value.contains("gif") { return "gif" }
    if value.contains("bmp") { return "bmp" }
    if value.contains("jp2") || value.contains("jpeg-2000") { return "jp2" }
    if value.contains("avif") { return "avif" }
    return nil
}

private func formatMatches(_ declared: String, uti: String) -> Bool {
    let normalized = declared.lowercased()
    guard let actual = canonicalImageFormat(uti: uti) else { return false }
    if normalized == "jpg" { return actual == "jpeg" }
    return normalized == actual
}

private func decodeImage(_ data: Data, entry: InventoryEntry) throws -> DecodedImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(source) > 0,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw GeometryError.message("image is not decodable: \(entry.relativePath)")
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
    let orientationNumber = properties?.object(forKey: kCGImagePropertyOrientation) as? NSNumber
    let orientation = try OrientationInfo(
        tag: orientationNumber?.intValue,
        propertiesPresent: orientationNumber != nil
    )
    let uti = CGImageSourceGetType(source).map { String(describing: $0) } ?? ""
    guard formatMatches(entry.format, uti: uti) else {
        throw GeometryError.message("inventory format does not match decoded image: \(entry.relativePath)")
    }
    guard image.width == entry.width, image.height == entry.height else {
        throw GeometryError.message("inventory dimensions do not match decoded image: \(entry.relativePath)")
    }
    guard image.width > 0, image.height > 0 else {
        throw GeometryError.message("decoded image dimensions must be positive: \(entry.relativePath)")
    }
    guard let format = canonicalImageFormat(uti: uti) else {
        throw GeometryError.message("image format is not supported by this extractor: \(entry.relativePath)")
    }
    return DecodedImage(image: image, format: format, orientation: orientation)
}

private struct RawCandidate {
    let kind: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Double
    let index: Int

    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    func contains(x pointX: Double, y pointY: Double) -> Bool {
        pointX >= x && pointX <= x + width && pointY >= y && pointY <= y + height
    }
}

private struct Saliency {
    let region: (x: Double, y: Double, width: Double, height: Double)
    let centerX: Double
    let centerY: Double
    let confidence: Double
}

private struct Horizon {
    let observedAngleDegrees: Double
    let confidence: Double
}

private struct VisionResult {
    let candidates: [RawCandidate]
    let saliency: Saliency?
    let horizon: Horizon?
    let analysisStatus: String
}

private func normalizedRect(_ rect: CGRect, kind: String, confidence: Double, index: Int) throws -> RawCandidate {
    let values = [Double(rect.origin.x), Double(rect.origin.y), Double(rect.width), Double(rect.height), confidence]
    guard values.allSatisfy({ $0.isFinite }), confidence >= 0, confidence <= 1 else {
        throw GeometryError.message("Vision returned non-finite or out-of-range geometry")
    }
    let minX = clamp01(values[0])
    let minY = clamp01(values[1])
    let maxX = clamp01(values[0] + values[2])
    let maxY = clamp01(values[1] + values[3])
    guard maxX > minX, maxY > minY else {
        throw GeometryError.message("Vision returned a degenerate geometry region")
    }
    return RawCandidate(
        kind: kind,
        x: minX,
        y: minY,
        width: maxX - minX,
        height: maxY - minY,
        confidence: confidence,
        index: index
    )
}

private final class VisionGeometryExtractor {
    private let humanRequest = VNDetectHumanRectanglesRequest()
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
    private let horizonRequest = VNDetectHorizonRequest()

    func extract(image: CGImage, orientation: CGImagePropertyOrientation) throws -> VisionResult {
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([humanRequest, faceRequest, saliencyRequest, horizonRequest])
        } catch {
            // A valid image can be unsupported by one OS Vision revision. The
            // honest result is unavailable geometry, never invented geometry.
            return VisionResult(candidates: [], saliency: nil, horizon: nil, analysisStatus: "vision_unavailable")
        }

        var candidates: [RawCandidate] = []
        if let faces = faceRequest.results {
            for (index, observation) in faces.enumerated() {
                candidates.append(try normalizedRect(
                    observation.boundingBox,
                    kind: "face",
                    confidence: Double(observation.confidence),
                    index: index
                ))
            }
        }
        if let humans = humanRequest.results {
            for (index, observation) in humans.enumerated() {
                candidates.append(try normalizedRect(
                    observation.boundingBox,
                    kind: "person",
                    confidence: Double(observation.confidence),
                    index: index
                ))
            }
        }
        candidates = candidates.sorted {
            let kindRank: (String) -> Int = { $0 == "face" ? 0 : 1 }
            let lhs = [Double(kindRank($0.kind)), $0.x, $0.y, $0.width, $0.height, $0.confidence]
            let rhs = [Double(kindRank($1.kind)), $1.x, $1.y, $1.width, $1.height, $1.confidence]
            return comesBefore(lhs, rhs)
        }.enumerated().map { offset, candidate in
            RawCandidate(
                kind: candidate.kind,
                x: candidate.x,
                y: candidate.y,
                width: candidate.width,
                height: candidate.height,
                confidence: candidate.confidence,
                index: offset
            )
        }

        var saliency: Saliency?
        if let observation = saliencyRequest.results?.first as? VNSaliencyImageObservation,
           let objects = observation.salientObjects,
           let top = objects.max(by: { lhs, rhs in
               if lhs.confidence != rhs.confidence { return lhs.confidence < rhs.confidence }
               let left = lhs.boundingBox
               let right = rhs.boundingBox
               return comesBefore(
                   [Double(left.origin.x), Double(left.origin.y), Double(left.width), Double(left.height)],
                   [Double(right.origin.x), Double(right.origin.y), Double(right.width), Double(right.height)]
               )
           }) {
            let rect = top.boundingBox
            let confidence = Double(top.confidence)
            let values = [Double(rect.origin.x), Double(rect.origin.y), Double(rect.width), Double(rect.height), confidence]
            let minX = clamp01(values[0])
            let minY = clamp01(values[1])
            let maxX = clamp01(values[0] + values[2])
            let maxY = clamp01(values[1] + values[3])
            guard values.allSatisfy({ $0.isFinite }), confidence >= 0, confidence <= 1, maxX > minX, maxY > minY else {
                throw GeometryError.message("Vision returned invalid saliency geometry")
            }
            saliency = Saliency(
                region: (minX, minY, maxX - minX, maxY - minY),
                centerX: (minX + maxX) / 2,
                centerY: (minY + maxY) / 2,
                confidence: confidence
            )
        } else {
            saliency = nil
        }

        var horizon: Horizon?
        if let observation = horizonRequest.results?.first as? VNHorizonObservation {
            // Vision's angle is the observed tilt, not the correction. In the
            // oriented display (x-right, y-down), positive means the horizon
            // falls toward +x (clockwise). Pillow's positive Image.rotate
            // direction is visual counter-clockwise, so the same numeric
            // value is the uprighting rotation after EXIF transposition.
            let observedAngle = Double(observation.angle) * 180 / .pi
            let confidence = Double(observation.confidence)
            guard observedAngle.isFinite, observedAngle >= -180, observedAngle <= 180,
                  confidence.isFinite, confidence >= 0, confidence <= 1 else {
                throw GeometryError.message("Vision returned invalid horizon evidence")
            }
            horizon = Horizon(observedAngleDegrees: observedAngle, confidence: confidence)
        } else {
            horizon = nil
        }
        return VisionResult(candidates: candidates, saliency: saliency, horizon: horizon, analysisStatus: "complete")
    }
}

private struct ProposalCandidate {
    let kind: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Double
    let sourceIndices: [Int]

    func contains(x pointX: Double, y pointY: Double) -> Bool {
        pointX >= x && pointX <= x + width && pointY >= y && pointY <= y + height
    }
}

private func proposalCandidates(from raw: [RawCandidate]) -> [ProposalCandidate] {
    let persons = raw.filter { $0.kind == "person" }
    let faces = raw.filter { $0.kind == "face" }
    var mergedFaces = Set<Int>()
    var proposals: [ProposalCandidate] = []
    for person in persons {
        let containing = faces.filter { face in
            person.contains(x: face.midX, y: face.midY)
                && persons.filter { candidate in
                    candidate.contains(x: face.midX, y: face.midY)
                }.count == 1
        }
        if containing.count == 1, let face = containing.first {
            mergedFaces.insert(face.index)
            proposals.append(ProposalCandidate(
                kind: "person",
                x: person.x,
                y: person.y,
                width: person.width,
                height: person.height,
                confidence: max(person.confidence, face.confidence),
                sourceIndices: [person.index, face.index].sorted()
            ))
        } else {
            proposals.append(ProposalCandidate(
                kind: person.kind,
                x: person.x,
                y: person.y,
                width: person.width,
                height: person.height,
                confidence: person.confidence,
                sourceIndices: [person.index]
            ))
        }
    }
    for face in faces where !mergedFaces.contains(face.index) {
        proposals.append(ProposalCandidate(
            kind: face.kind,
            x: face.x,
            y: face.y,
            width: face.width,
            height: face.height,
            confidence: face.confidence,
            sourceIndices: [face.index]
        ))
    }
    return proposals.sorted {
        let lhs = [Double($0.kind == "face" ? 0 : 1), $0.x, $0.y, $0.width, $0.height, $0.confidence]
        let rhs = [Double($1.kind == "face" ? 0 : 1), $1.x, $1.y, $1.width, $1.height, $1.confidence]
        return comesBefore(lhs, rhs)
    }
}

private struct Selection {
    let status: String
    let rule: String
    let selected: ProposalCandidate?
}

private func selectProposal(_ raw: [RawCandidate], saliency: Saliency?) -> Selection {
    let proposals = proposalCandidates(from: raw)
    guard !proposals.isEmpty else {
        return Selection(status: "none", rule: "no_candidates", selected: nil)
    }
    if proposals.count == 1 {
        let only = proposals[0]
        guard only.confidence >= selectionConfidenceFloor else {
            return Selection(status: "ambiguous", rule: "single_candidate_low_confidence", selected: nil)
        }
        return Selection(
            status: "selected",
            rule: only.sourceIndices.count > 1 ? "merged_person_face" : "single_candidate",
            selected: only
        )
    }

    if let saliency,
       saliency.confidence >= saliencyConfidenceFloor {
        let endorsed = proposals.filter {
            $0.contains(x: saliency.centerX, y: saliency.centerY)
        }
        if endorsed.count == 1 {
            let winner = endorsed[0]
            guard winner.confidence >= selectionConfidenceFloor else {
                return Selection(status: "ambiguous", rule: "saliency_low_detection_confidence", selected: nil)
            }
            return Selection(status: "selected", rule: "unique_saliency_endorsement", selected: winner)
        }
    }

    let sorted: [ProposalCandidate] = proposals.sorted { (lhs: ProposalCandidate, rhs: ProposalCandidate) in
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        let leftValues = [Double(lhs.kind == "face" ? 0 : 1), lhs.x, lhs.y, lhs.width, lhs.height]
        let rightValues = [Double(rhs.kind == "face" ? 0 : 1), rhs.x, rhs.y, rhs.width, rhs.height]
        return comesBefore(leftValues, rightValues)
    }
    let top = sorted[0]
    let second = sorted[1]
    guard top.confidence >= selectionConfidenceFloor else {
        return Selection(status: "ambiguous", rule: "low_detection_confidence", selected: nil)
    }
    if top.confidence - second.confidence > selectionTieMargin {
        return Selection(status: "selected", rule: "clear_confidence_winner", selected: top)
    }
    return Selection(status: "ambiguous", rule: "confidence_tie_or_conflict", selected: nil)
}

private func candidateJSON(_ candidate: RawCandidate) -> [String: Any] {
    [
        "confidence": candidate.confidence,
        "height": candidate.height,
        "kind": candidate.kind,
        "width": candidate.width,
        "x": candidate.x,
        "y": candidate.y
    ]
}

private func proposalJSON(_ candidate: ProposalCandidate) -> [String: Any] {
    [
        "confidence": candidate.confidence,
        "height": candidate.height,
        "kind": candidate.kind,
        "source_candidate_indices": candidate.sourceIndices,
        "width": candidate.width,
        "x": candidate.x,
        "y": candidate.y
    ]
}

private func geometryRecord(
    entry: InventoryEntry,
    digest: String,
    image: DecodedImage,
    vision: VisionResult
) -> [String: Any] {
    let selection = selectProposal(vision.candidates, saliency: vision.saliency)
    let saliencyValue: Any
    if let saliency = vision.saliency {
        saliencyValue = [
            "confidence": saliency.confidence,
            "center": ["x": saliency.centerX, "y": saliency.centerY],
            "region": [
                "height": saliency.region.height,
                "width": saliency.region.width,
                "x": saliency.region.x,
                "y": saliency.region.y
            ]
        ]
    } else {
        saliencyValue = NSNull()
    }
    let horizonValue: Any
    if let horizon = vision.horizon {
        horizonValue = [
            "confidence": horizon.confidence,
            "observed_angle_degrees": horizon.observedAngleDegrees,
            "pillow_uprighting_rotation_degrees": horizon.observedAngleDegrees
        ]
    } else {
        horizonValue = NSNull()
    }
    let selectedValue: Any = selection.selected.map(proposalJSON) ?? NSNull()
    return [
        "analysis_status": vision.analysisStatus,
        "coordinate_space": [
            "axes": "x_right_y_up",
            "box_format": "normalized_xywh",
            "dimensions": "oriented_image",
            "id": "vision_oriented_normalized",
            "origin": "bottom_left",
            "horizon_angle_contract": "observed Vision tilt, not an uprighting correction; positive means the horizon falls toward +x in the oriented display (clockwise in x-right/y-down), equivalently a negative line angle in x-right/y-up",
            "horizon_pillow_rotation": "after ImageOps.exif_transpose exactly once, call PIL Image.rotate(angle=pillow_uprighting_rotation_degrees); Pillow positive angles are counter-clockwise visually, and this levels the observed tilt",
            "pillow_transform": "after ImageOps.exif_transpose exactly once: x'=x; y'=1-y-height; width'=width; height'=height; no second EXIF transform",
            "raw_pixel_preprocessing": "ImageIO/CGImage remains in encoded storage orientation; raw Pillow pixels require ImageOps.exif_transpose exactly once before geometry transforms"
        ],
        "exif_orientation": [
            "applied_by_decoder": false,
            "exif_present": image.orientation.exifPresent,
            "name": image.orientation.name,
            "passed_to_vision": true,
            "passed_to_vision_exactly_once": true,
            "tag": image.orientation.tag,
            "source": image.orientation.exifPresent ? "kCGImagePropertyOrientation" : "default_when_EXIF_missing"
        ],
        "geometry_authority": "silver_apple_vision",
        "horizon": horizonValue,
        "human_gold": false,
        "image": [
            "decoded_dimensions": ["height": image.decodedHeight, "width": image.decodedWidth],
            "format": image.format,
            "oriented_dimensions": ["height": image.orientedHeight, "width": image.orientedWidth]
        ],
        "research_only": true,
        "release_admissible": false,
        "schema_id": schemaID,
        "schema_version": schemaVersion,
        "selection_rule": selection.rule,
        "selection_status": selection.status,
        "selected_subject": selectedValue,
        "source": [
            "relative_path": entry.relativePath,
            "sha256": digest,
            "source_id": entry.sourceID,
            "source_record_id": entry.sourceRecordID
        ],
        "subject_candidates": vision.candidates.map(candidateJSON),
        "saliency": saliencyValue
    ]
}

private struct BuildResult {
    let geometryData: Data
    let geometryDigest: String
    let recordCount: Int
    let selectionCounts: [String: Int]
    let horizonAvailable: Int
    let saliencyAvailable: Int
    let analysisCounts: [String: Int]
}

private func publish(
    geometryData: Data,
    receiptData: Data,
    outputRoot: URL
) throws {
    let parent = outputRoot.deletingLastPathComponent()
    guard isDirectory(parent), !isSymlink(parent) else {
        throw GeometryError.message("output-root parent is not a safe directory")
    }
    let staging = parent.appendingPathComponent(
        ".\(outputRoot.lastPathComponent).staging-\(UUID().uuidString)",
        isDirectory: true
    )
    do {
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let stagedGeometry = staging.appendingPathComponent("geometry.jsonl")
        let stagedReceipt = staging.appendingPathComponent("receipt.json")
        try writeAndSync(geometryData, to: stagedGeometry)
        try writeAndSync(receiptData, to: stagedReceipt)
        syncDirectory(staging)

        guard fileMode(outputRoot) == nil else {
            throw GeometryError.message("output-root appeared during extraction")
        }
        try FileManager.default.moveItem(at: staging, to: outputRoot)
        syncDirectory(parent)
    } catch let error as GeometryError {
        if fileMode(staging) != nil { try? FileManager.default.removeItem(at: staging) }
        throw error
    } catch {
        if fileMode(staging) != nil { try? FileManager.default.removeItem(at: staging) }
        throw GeometryError.message("cannot atomically publish geometry outputs")
    }
}

private func environmentJSON() -> [String: Any] {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let visionVersion = Bundle(identifier: "com.apple.Vision")?.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "unavailable"
    return [
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "os_version_components": ["major": os.majorVersion, "minor": os.minorVersion, "patch": os.patchVersion],
        "platform": "macOS",
        "vision_framework": [
            "bundle_identifier": "com.apple.Vision",
            "name": "Vision",
            "version": visionVersion
        ],
        "vision_request_family": [
            "VNDetectHumanRectanglesRequest",
            "VNDetectFaceRectanglesRequest",
            "VNGenerateAttentionBasedSaliencyImageRequest",
            "VNDetectHorizonRequest"
        ],
        "vision_request_revisions": [
            "VNDetectHumanRectanglesRequest": VNDetectHumanRectanglesRequest().revision,
            "VNDetectFaceRectanglesRequest": VNDetectFaceRectanglesRequest().revision,
            "VNGenerateAttentionBasedSaliencyImageRequest": VNGenerateAttentionBasedSaliencyImageRequest().revision,
            "VNDetectHorizonRequest": VNDetectHorizonRequest().revision
        ]
    ]
}

private func build(
    inventoryURL: URL,
    sourceRootInput: URL,
    outputRootInput: URL,
    maxRecords: Int?
) throws -> (result: BuildResult, outputRoot: URL) {
    let repository = repositoryRoot()
    let source = try validateExternalDirectory(
        sourceRootInput, repository: repository, label: "source-root", mustExist: true
    ).url
    let outputPlan = try validateExternalDirectory(
        outputRootInput, repository: repository, label: "output-root", mustExist: false
    )
    let output = outputPlan.url
    guard !outputPlan.existed else {
        throw GeometryError.message("output-root must not already exist; provide a new path")
    }
    guard !isWithin(source, output), !isWithin(output, source) else {
        throw GeometryError.message("source-root and output-root must be separate")
    }
    let parent = output.deletingLastPathComponent()
    try assertNoSymlinkComponents(parent.resolvingSymlinksInPath().standardizedFileURL)
    guard isDirectory(parent), !isSymlink(parent) else {
        throw GeometryError.message("output-root parent is not a regular directory")
    }
    let inventoryData = try readRegularFile(inventoryURL, label: "inventory")
    let inventoryDigest = sha256(inventoryData)
    let entries = try parseInventory(inventoryData, sourceRoot: source)
    let count = min(maxRecords ?? entries.count, entries.count)
    let selectedEntries = Array(entries.prefix(count))
    guard !selectedEntries.isEmpty else {
        throw GeometryError.message("max-records selected no rows")
    }

    let toolURL = URL(fileURLWithPath: #filePath).standardizedFileURL
    let toolData = try readRegularFile(toolURL, label: "tool source")
    let toolDigest = sha256(toolData)
    let extractor = VisionGeometryExtractor()
    var rows: [[String: Any]] = []
    var fingerprints: [(url: URL, digest: String)] = []
    var selectionCounts = ["selected": 0, "ambiguous": 0, "none": 0]
    var horizonAvailable = 0
    var saliencyAvailable = 0
    var analysisCounts = ["complete": 0, "vision_unavailable": 0]

    for entry in selectedEntries {
        let data = try readRegularFile(entry.mediaURL, label: entry.relativePath)
        guard Int64(data.count) == entry.byteCount else {
            throw GeometryError.message("byte_count mismatch: \(entry.relativePath)")
        }
        let digest = sha256(data)
        guard digest == entry.sha256 else {
            throw GeometryError.message("sha256 mismatch: \(entry.relativePath)")
        }
        let decoded = try decodeImage(data, entry: entry)
        let vision = try extractor.extract(image: decoded.image, orientation: decoded.orientation.cgOrientation)
        let record = geometryRecord(entry: entry, digest: digest, image: decoded, vision: vision)
        rows.append(record)
        let status = record["selection_status"] as? String ?? "none"
        selectionCounts[status, default: 0] += 1
        if vision.horizon != nil { horizonAvailable += 1 }
        if vision.saliency != nil { saliencyAvailable += 1 }
        analysisCounts[vision.analysisStatus, default: 0] += 1
        fingerprints.append((entry.mediaURL, digest))
    }

    let finalInventoryData = try readRegularFile(inventoryURL, label: "inventory")
    guard sha256(finalInventoryData) == inventoryDigest else {
        throw GeometryError.message("inventory changed during extraction")
    }
    let finalToolData = try readRegularFile(toolURL, label: "tool source")
    guard sha256(finalToolData) == toolDigest else {
        throw GeometryError.message("tool source changed during extraction")
    }
    for fingerprint in fingerprints {
        let current = try readRegularFile(fingerprint.url, label: fingerprint.url.lastPathComponent)
        guard sha256(current) == fingerprint.digest else {
            throw GeometryError.message("source image changed during extraction: \(fingerprint.url.lastPathComponent)")
        }
    }

    var geometryData = Data()
    for row in rows {
        geometryData.append(try jsonLine(row))
    }
    let geometryDigest = sha256(geometryData)
    let receipt: [String: Any] = [
        "counts": [
            "analysis_status": analysisCounts,
            "horizon": ["available": horizonAvailable, "unavailable": selectedEntries.count - horizonAvailable],
            "records": selectedEntries.count,
            "saliency": ["available": saliencyAvailable, "unavailable": selectedEntries.count - saliencyAvailable],
            "selection_status": selectionCounts
        ],
        "determinism": "conditional_on_captured_apple_os_vision_runtime",
        "environment": environmentJSON(),
        "geometry_authority": "silver_apple_vision",
        "human_gold": false,
        "input_inventory": ["records": entries.count, "sha256": inventoryDigest],
        "limits": ["max_records": maxRecords as Any? ?? NSNull(), "processed_records": selectedEntries.count],
        "output_geometry": ["path": "geometry.jsonl", "records": selectedEntries.count, "sha256": geometryDigest],
        "receipt_schema_id": receiptSchemaID,
        "release_admissible": false,
        "research_only": true,
        "schema_version": schemaVersion,
        "tool_source": ["path": toolRelativePath, "sha256": toolDigest]
    ]
    let receiptData = try jsonLine(receipt)
    try publish(
        geometryData: geometryData,
        receiptData: receiptData,
        outputRoot: output
    )
    return (
        BuildResult(
            geometryData: geometryData,
            geometryDigest: geometryDigest,
            recordCount: selectedEntries.count,
            selectionCounts: selectionCounts,
            horizonAvailable: horizonAvailable,
            saliencyAvailable: saliencyAvailable,
            analysisCounts: analysisCounts
        ),
        output
    )
}

private func validFixtureInventory(imageData: Data) throws -> Data {
    let digest = sha256(imageData)
    let row: [String: Any] = [
        "byte_count": imageData.count,
        "format": "png",
        "height": 1,
        "human_gold": false,
        "intake_tier": "research_only",
        "relative_path": "images/fixture.png",
        "release_admissible": false,
        "sha256": digest,
        "source_id": "fixture",
        "source_record_id": "one",
        "width": 1
    ]
    return try jsonLine(row)
}

private func expectFailure(_ operation: () throws -> Void, label: String) throws {
    do {
        try operation()
    } catch {
        return
    }
    throw GeometryError.message("self-test accepted invalid case: \(label)")
}

private func selfTest() throws {
    let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    guard let imageData = Data(base64Encoded: pngBase64) else {
        throw GeometryError.message("self-test fixture is malformed")
    }
    let base = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("set-os-geometry-self-test-\(UUID().uuidString)", isDirectory: true)
        .standardizedFileURL
    defer { try? FileManager.default.removeItem(at: base) }
    let sourceRoot = base.appendingPathComponent("source", isDirectory: true)
    let images = sourceRoot.appendingPathComponent("images", isDirectory: true)
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let fixtureURL = images.appendingPathComponent("fixture.png")
    try imageData.write(to: fixtureURL)
    let inventoryURL = base.appendingPathComponent("inventory.jsonl")
    try validFixtureInventory(imageData: imageData).write(to: inventoryURL)

    let outputRoot = base.appendingPathComponent("output", isDirectory: true)
    let buildResult = try build(
        inventoryURL: inventoryURL,
        sourceRootInput: sourceRoot,
        outputRootInput: outputRoot,
        maxRecords: nil
    )
    let geometryURL = buildResult.outputRoot.appendingPathComponent("geometry.jsonl")
    let receiptURL = buildResult.outputRoot.appendingPathComponent("receipt.json")
    guard isRegularFile(geometryURL), isRegularFile(receiptURL),
          try FileManager.default.contentsOfDirectory(at: buildResult.outputRoot, includingPropertiesForKeys: nil).count == 2 else {
        throw GeometryError.message("self-test did not publish exactly two outputs")
    }
    let outputGeometry = try readRegularFile(geometryURL, label: "self-test geometry")
    guard sha256(outputGeometry) == buildResult.result.geometryDigest,
          String(data: outputGeometry, encoding: .utf8)?.contains("\"human_gold\":false") == true else {
        throw GeometryError.message("self-test geometry receipt binding failed")
    }
    let receiptData = try readRegularFile(receiptURL, label: "self-test receipt")
    guard let receipt = try JSONSerialization.jsonObject(with: receiptData, options: []) as? [String: Any],
          let output = receipt["output_geometry"] as? [String: Any],
          output["sha256"] as? String == buildResult.result.geometryDigest else {
        throw GeometryError.message("self-test receipt is not bound to geometry")
    }

    let invalidHashInventory = base.appendingPathComponent("invalid-hash.jsonl")
    let invalidHashRow = [
        "byte_count": imageData.count,
        "format": "png",
        "height": 1,
        "human_gold": false,
        "intake_tier": "research_only",
        "relative_path": "images/fixture.png",
        "release_admissible": false,
        "sha256": String(repeating: "0", count: 64),
        "source_id": "fixture",
        "source_record_id": "one",
        "width": 1
    ] as [String: Any]
    try jsonLine(invalidHashRow).write(to: invalidHashInventory)
    try expectFailure({
        _ = try build(
            inventoryURL: invalidHashInventory,
            sourceRootInput: sourceRoot,
            outputRootInput: base.appendingPathComponent("invalid-hash-output"),
            maxRecords: nil
        )
    }, label: "hash mismatch")

    let unknownInventory = base.appendingPathComponent("unknown.jsonl")
    var unknownRow = try JSONSerialization.jsonObject(with: validFixtureInventory(imageData: imageData), options: []) as! [String: Any]
    unknownRow["human_truth"] = true
    try jsonLine(unknownRow).write(to: unknownInventory)
    try expectFailure({
        _ = try build(
            inventoryURL: unknownInventory,
            sourceRootInput: sourceRoot,
            outputRootInput: base.appendingPathComponent("unknown-output"),
            maxRecords: nil
        )
    }, label: "unknown inventory semantics")

    let escapingInventory = base.appendingPathComponent("escaping.jsonl")
    var escapingRow = try JSONSerialization.jsonObject(with: validFixtureInventory(imageData: imageData), options: []) as! [String: Any]
    escapingRow["relative_path"] = "../outside.png"
    try jsonLine(escapingRow).write(to: escapingInventory)
    try expectFailure({
        _ = try build(
            inventoryURL: escapingInventory,
            sourceRootInput: sourceRoot,
            outputRootInput: base.appendingPathComponent("escaping-output"),
            maxRecords: nil
        )
    }, label: "escaping path")

    let linkedURL = images.appendingPathComponent("linked.png")
    try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: fixtureURL)
    let symlinkInventory = base.appendingPathComponent("symlink.jsonl")
    var symlinkRow = try JSONSerialization.jsonObject(with: validFixtureInventory(imageData: imageData), options: []) as! [String: Any]
    symlinkRow["relative_path"] = "images/linked.png"
    try jsonLine(symlinkRow).write(to: symlinkInventory)
    try expectFailure({
        _ = try build(
            inventoryURL: symlinkInventory,
            sourceRootInput: sourceRoot,
            outputRootInput: base.appendingPathComponent("symlink-output"),
            maxRecords: nil
        )
    }, label: "symlink path")

    let linkedBase = base.appendingPathComponent("linked-base", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linkedBase, withDestinationURL: base)
    let intermediateSourceOutput = base.appendingPathComponent("intermediate-source-output")
    try expectFailure({
        _ = try build(
            inventoryURL: inventoryURL,
            sourceRootInput: linkedBase.appendingPathComponent("source", isDirectory: true),
            outputRootInput: intermediateSourceOutput,
            maxRecords: nil
        )
    }, label: "intermediate source-root symlink")
    guard fileMode(intermediateSourceOutput) == nil else {
        throw GeometryError.message("self-test created output for intermediate source symlink")
    }
    let intermediateOutput = linkedBase.appendingPathComponent("intermediate-output", isDirectory: true)
    try expectFailure({
        _ = try build(
            inventoryURL: inventoryURL,
            sourceRootInput: sourceRoot,
            outputRootInput: intermediateOutput,
            maxRecords: nil
        )
    }, label: "intermediate output-root symlink")
    guard fileMode(intermediateOutput) == nil else {
        throw GeometryError.message("self-test created output for intermediate output symlink")
    }
    let intermediateInventoryOutput = base.appendingPathComponent("intermediate-inventory-output")
    try expectFailure({
        _ = try build(
            inventoryURL: linkedBase.appendingPathComponent("inventory.jsonl"),
            sourceRootInput: sourceRoot,
            outputRootInput: intermediateInventoryOutput,
            maxRecords: nil
        )
    }, label: "intermediate inventory symlink")
    guard fileMode(intermediateInventoryOutput) == nil else {
        throw GeometryError.message("self-test created output for intermediate inventory symlink")
    }

    let existingEmptyOutput = base.appendingPathComponent("existing-empty-output", isDirectory: true)
    try FileManager.default.createDirectory(at: existingEmptyOutput, withIntermediateDirectories: true)
    try expectFailure({
        _ = try build(
            inventoryURL: inventoryURL,
            sourceRootInput: sourceRoot,
            outputRootInput: existingEmptyOutput,
            maxRecords: nil
        )
    }, label: "pre-existing empty output")
    guard (try FileManager.default.contentsOfDirectory(at: existingEmptyOutput, includingPropertiesForKeys: nil)).isEmpty else {
        throw GeometryError.message("self-test changed pre-existing empty output")
    }

    let nonEmptyOutput = base.appendingPathComponent("non-empty-output", isDirectory: true)
    try FileManager.default.createDirectory(at: nonEmptyOutput, withIntermediateDirectories: true)
    let sentinel = nonEmptyOutput.appendingPathComponent("sentinel")
    try Data("untouched".utf8).write(to: sentinel)
    try expectFailure({
        _ = try build(
            inventoryURL: inventoryURL,
            sourceRootInput: sourceRoot,
            outputRootInput: nonEmptyOutput,
            maxRecords: nil
        )
    }, label: "non-empty output")
    guard try Data(contentsOf: sentinel) == Data("untouched".utf8) else {
        throw GeometryError.message("self-test changed non-empty output")
    }
    print("PASS extract_camera_geometry self-test inventory_schema hash_path_symlink_guards atomic_outputs receipt_binding research_only_boundary")
}

private struct CLIOptions {
    var inventory: URL?
    var sourceRoot: URL?
    var outputRoot: URL?
    var maxRecords: Int?
    var selfTest = false
}

private func usage() {
    print("Usage: extract_camera_geometry --inventory <inventory.jsonl> --source-root <root> --output-root <new-external-dir> [--max-records N] [--self-test]")
}

private func parseCLI(_ arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--self-test":
            options.selfTest = true
        case "--inventory", "--source-root", "--output-root", "--max-records":
            index += 1
            guard index < arguments.count else {
                throw GeometryError.message("missing value for \(arguments[index - 1])")
            }
            switch arguments[index - 1] {
            case "--inventory": options.inventory = expandedURL(arguments[index])
            case "--source-root": options.sourceRoot = expandedURL(arguments[index])
            case "--output-root": options.outputRoot = expandedURL(arguments[index])
            case "--max-records":
                guard let value = Int(arguments[index]), value > 0 else {
                    throw GeometryError.message("--max-records must be a positive integer")
                }
                options.maxRecords = value
            default: break
            }
        case "--help", "-h":
            usage()
            exit(0)
        default:
            throw GeometryError.message("unknown argument: \(arguments[index])")
        }
        index += 1
    }
    if options.selfTest {
        guard options.inventory == nil, options.sourceRoot == nil, options.outputRoot == nil, options.maxRecords == nil else {
            throw GeometryError.message("--self-test cannot be combined with extraction arguments")
        }
        return options
    }
    guard let inventory = options.inventory, let sourceRoot = options.sourceRoot, let outputRoot = options.outputRoot else {
        throw GeometryError.message("--inventory, --source-root, and --output-root are required")
    }
    guard !isSymlink(inventory), isRegularFile(inventory) else {
        throw GeometryError.message("inventory must be a regular file")
    }
    _ = inventory
    _ = sourceRoot
    _ = outputRoot
    return options
}

private func main() -> Int32 {
    do {
        let options = try parseCLI(CommandLine.arguments)
        if options.selfTest {
            try selfTest()
            return 0
        }
        guard let inventory = options.inventory, let sourceRoot = options.sourceRoot, let outputRoot = options.outputRoot else {
            usage()
            return 2
        }
        let run = try build(
            inventoryURL: inventory,
            sourceRootInput: sourceRoot,
            outputRootInput: outputRoot,
            maxRecords: options.maxRecords
        )
        print("PASS extract_camera_geometry records=\(run.result.recordCount) geometry_sha256=\(run.result.geometryDigest) output=\(run.outputRoot.path)")
        return 0
    } catch let error as GeometryError {
        FileHandle.standardError.write(Data("FAIL \(error.description)\n".utf8))
        return 1
    } catch {
        FileHandle.standardError.write(Data("FAIL extraction failed\n".utf8))
        return 1
    }
}

exit(main())
