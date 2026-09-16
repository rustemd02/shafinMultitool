//
//  extract_video_frames.swift
//  Cinematic frame harvest for the Camera Coach corpus.
//
//  Extracts candidate frames from a video file at a fixed interval, drops
//  frames that cannot carry composition information (near-black, blown out,
//  or flat/low-texture), and writes JPEGs plus a manifest line per frame.
//
//  Build/run (macOS, no external dependencies):
//    swiftc -O tools/dataset/extract_video_frames.swift -o /tmp/extract_frames
//    /tmp/extract_frames --input film.mov --out frames/ --interval 4 --max 200
//
//  Frame provenance (film title, licence, timestamp) is added by the Python
//  orchestrator; this tool records only what it can see.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Options {
    var input: URL
    var out: URL
    var interval: Double = 4.0
    var maxFrames: Int = 200
    var longSide: Int = 1280
    var minStdDev: Double = 0.055     // rejects flat/black/blank frames
    var minMeanLuma: Double = 0.12
    var maxMeanLuma: Double = 0.93
    var jpegQuality: Double = 0.92
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func parseOptions() -> Options {
    var args = CommandLine.arguments.dropFirst()
    var values: [String: String] = [:]
    while let key = args.first {
        args = args.dropFirst()
        guard key.hasPrefix("--"), let value = args.first else { fail("bad arguments near \(key)") }
        args = args.dropFirst()
        values[String(key.dropFirst(2))] = value
    }
    guard let input = values["input"], let out = values["out"] else {
        fail("--input and --out are required")
    }
    var options = Options(input: URL(fileURLWithPath: input), out: URL(fileURLWithPath: out))
    if let value = values["interval"], let parsed = Double(value) { options.interval = parsed }
    if let value = values["max"], let parsed = Int(value) { options.maxFrames = parsed }
    if let value = values["long-side"], let parsed = Int(value) { options.longSide = parsed }
    if let value = values["min-stddev"], let parsed = Double(value) { options.minStdDev = parsed }
    return options
}

/// Mean luma and its standard deviation over a small grayscale grid. Frames
/// below either bound carry no usable composition evidence.
func luminanceStats(of image: CGImage) -> (mean: Double, stdDev: Double) {
    let width = 32
    let height = 32
    var pixels = [UInt8](repeating: 0, count: width * height)
    guard let space = CGColorSpace(name: CGColorSpace.linearGray),
          let context = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        return (0, 0)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let values = pixels.map { Double($0) / 255.0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    return (mean, variance.squareRoot())
}

let options = parseOptions()
try? FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)

let asset = AVURLAsset(url: options.input)
let duration = CMTimeGetSeconds(asset.duration)
guard duration.isFinite, duration > 0 else { fail("cannot read video duration") }
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let scale = CGFloat(options.longSide)
generator.maximumSize = CGSize(width: scale, height: scale)

var written = 0
var scanned = 0
var timestamp = 0.0
var manifestLines: [String] = []

while timestamp < duration && written < options.maxFrames {
    defer { timestamp += options.interval }
    let time = CMTime(seconds: timestamp, preferredTimescale: 600)
    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
    scanned += 1
    let stats = luminanceStats(of: image)
    guard stats.mean >= options.minMeanLuma,
          stats.mean <= options.maxMeanLuma,
          stats.stdDev >= options.minStdDev else { continue }

    let name = "frame_" + String(format: "%07.2f", timestamp).replacingOccurrences(of: ".", with: "_") + ".jpg"
    let url = options.out.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { continue }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: options.jpegQuality
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { continue }

    written += 1
    let record: [String: Any] = [
        "frame": name,
        "timestamp_s": (timestamp * 100).rounded() / 100,
        "mean_luma": (stats.mean * 10000).rounded() / 10000,
        "stddev": (stats.stdDev * 10000).rounded() / 10000,
        "width": image.width,
        "height": image.height,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        manifestLines.append(text)
    }
}

let manifest = options.out.appendingPathComponent("frames.jsonl")
try manifestLines.joined(separator: "\n").appending("\n").write(to: manifest, atomically: true, encoding: .utf8)
print("{\"written\": \(written), \"scanned\": \(scanned), \"duration_s\": \(Int(duration)), \"manifest\": \"\(manifest.path)\"}")
