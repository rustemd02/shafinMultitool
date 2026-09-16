import AudioToolbox
import CoreMedia
import Foundation
import XCTest
@testable import shafinMultitool

final class CameraAudioMeterMeasurementTests: XCTestCase {
    func testSignedInt16StereoUsesAllSamplesWithoutPresentationGain() throws {
        let sample = try makeSample(
            format: pcmFormat(channels: 2, bits: 16),
            frames: 2,
            bytes: bytes(of: [Int16(0), Int16.max, Int16.min, 16_384])
        )
        let positiveFullScale = Double(Int16.max) / 32_768.0
        let expected = sqrt((positiveFullScale * positiveFullScale + 1 + 0.25) / 4)
        XCTAssertEqual(try level(sample), Float(expected), accuracy: 0.000001)
    }

    func testSignedInt16SilenceAndNegativeFullScale() throws {
        let silence = try makeSample(
            format: pcmFormat(channels: 2, bits: 16),
            frames: 4,
            bytes: bytes(of: [Int16](repeating: 0, count: 8))
        )
        let fullScale = try makeSample(
            format: pcmFormat(channels: 1, bits: 16),
            frames: 2,
            bytes: bytes(of: [Int16.min, Int16.min])
        )
        XCTAssertEqual(try level(silence), 0)
        XCTAssertEqual(try level(fullScale), 1)
    }

    func testInterleavedFloat32KeepsHalfScaleAtHalfScale() throws {
        let sample = try makeSample(
            format: pcmFormat(channels: 2, bits: 32, isFloat: true),
            frames: 2,
            bytes: bytes(of: [Float32(0.5), -0.5, 0.5, -0.5])
        )
        XCTAssertEqual(try level(sample), 0.5, accuracy: 0.000001)
    }

    func testPlanarFloat32IncludesQuietChannelInRMS() throws {
        // Two frames of the left plane, then two of the right plane.
        let sample = try makeSample(
            format: pcmFormat(channels: 2, bits: 32, isFloat: true, planar: true),
            frames: 2,
            bytes: bytes(of: [Float32(0.5), -0.5, 0, 0])
        )
        XCTAssertEqual(try level(sample), Float(sqrt(0.125)), accuracy: 0.000001)
    }

    func testSegmentedBlockBufferIsMeasuredAcrossItsStorageBoundary() throws {
        let sample = try makeSample(
            format: pcmFormat(channels: 1, bits: 16),
            frames: 4,
            bytes: bytes(of: [Int16(16_384), -16_384, 16_384, -16_384]),
            segmented: true
        )
        XCTAssertEqual(try level(sample), 0.5, accuracy: 0.000001)
    }

    func testFiniteFloatOverflowSaturatesOnlyFinalMeterLevel() throws {
        let sample = try makeSample(
            format: pcmFormat(channels: 1, bits: 32, isFloat: true),
            frames: 2,
            bytes: bytes(of: [Float32(2), -2])
        )
        XCTAssertEqual(try level(sample), 1)
    }

    func testAnyNonfiniteFloatSampleMakesMeasurementUnavailable() throws {
        for invalid: Float32 in [.nan, .infinity, -.infinity] {
            let sample = try makeSample(
                format: pcmFormat(channels: 2, bits: 32, isFloat: true, planar: true),
                frames: 2,
                bytes: bytes(of: [Float32(0.5), 0.5, 0.5, invalid])
            )
            XCTAssertNil(CameraAudioMeterMeasurement.normalizedRMS(from: sample))
        }
    }

    func testUnsupportedValidAudioFormatsAreNotReinterpretedAsInt16() throws {
        var unsigned = pcmFormat(channels: 1, bits: 16)
        unsigned.mFormatFlags = kAudioFormatFlagIsPacked
        var bigEndian = pcmFormat(channels: 1, bits: 16)
        bigEndian.mFormatFlags |= kAudioFormatFlagIsBigEndian
        let integer32 = pcmFormat(channels: 1, bits: 32)
        let float64 = pcmFormat(channels: 1, bits: 64, isFloat: true)
        var compressed = pcmFormat(channels: 1, bits: 8)
        compressed.mFormatID = kAudioFormatULaw
        compressed.mFormatFlags = 0

        for format in [unsigned, bigEndian, integer32, float64, compressed] {
            let sample = try makeSample(
                format: format,
                frames: 2,
                bytes: Data(repeating: 0x7f, count: Int(format.mBytesPerFrame) * 2)
            )
            XCTAssertNil(CameraAudioMeterMeasurement.normalizedRMS(from: sample),
                         "Unsupported format \(format.mFormatID), flags \(format.mFormatFlags), bits \(format.mBitsPerChannel)")
        }
    }

    func testTruncatedInterleavedAndPlanarDataCannotBeMeasured() throws {
        for format in [
            pcmFormat(channels: 2, bits: 16),
            pcmFormat(channels: 2, bits: 32, isFloat: true, planar: true)
        ] {
            let sample = try makeSample(
                format: format,
                frames: 4,
                bytes: Data(repeating: 0, count: 4)
            )
            XCTAssertNil(CameraAudioMeterMeasurement.normalizedRMS(from: sample),
                         "Declared four stereo frames require more than four bytes")
        }
    }

    func testUnreadableAndInvalidatedBuffersAreUnavailable() throws {
        let notReady = try makeSample(
            format: pcmFormat(channels: 1, bits: 16),
            frames: 2,
            bytes: bytes(of: [Int16(16_384), -16_384]),
            dataReady: false
        )
        XCTAssertFalse(CMSampleBufferDataIsReady(notReady))
        XCTAssertNil(CameraAudioMeterMeasurement.normalizedRMS(from: notReady))

        let invalidated = try makeSample(
            format: pcmFormat(channels: 1, bits: 16),
            frames: 2,
            bytes: bytes(of: [Int16(16_384), -16_384])
        )
        XCTAssertEqual(CMSampleBufferInvalidate(invalidated), noErr)
        XCTAssertNil(CameraAudioMeterMeasurement.normalizedRMS(from: invalidated))
    }

    private func level(_ sample: CMSampleBuffer) throws -> Float {
        try XCTUnwrap(CameraAudioMeterMeasurement.normalizedRMS(from: sample))
    }

    private func bytes<Value>(of values: [Value]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }

    private func pcmFormat(
        channels: UInt32,
        bits: UInt32,
        isFloat: Bool = false,
        planar: Bool = false
    ) -> AudioStreamBasicDescription {
        let flags = (isFloat ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger)
            | kAudioFormatFlagIsPacked
            | (planar ? kAudioFormatFlagIsNonInterleaved : 0)
        let frameBytes = bits / 8 * (planar ? 1 : channels)
        return AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags,
            mBytesPerPacket: frameBytes,
            mFramesPerPacket: 1,
            mBytesPerFrame: frameBytes,
            mChannelsPerFrame: channels,
            mBitsPerChannel: bits,
            mReserved: 0
        )
    }

    private func makeSample(
        format: AudioStreamBasicDescription,
        frames: Int,
        bytes: Data,
        segmented: Bool = false,
        dataReady: Bool = true
    ) throws -> CMSampleBuffer {
        var description = format
        var audioFormat: CMAudioFormatDescription?
        try requireSuccess(CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &audioFormat
        ))
        let resolvedFormat = try XCTUnwrap(audioFormat)
        let segments = segmented
            ? [Data(bytes.prefix(bytes.count / 2)), Data(bytes.suffix(bytes.count - bytes.count / 2))]
            : [bytes]
        var block: CMBlockBuffer?
        try requireSuccess(CMBlockBufferCreateEmpty(
            allocator: kCFAllocatorDefault,
            capacity: UInt32(segments.count),
            flags: 0,
            blockBufferOut: &block
        ))
        let resolvedBlock = try XCTUnwrap(block)
        var offset = 0
        for segment in segments {
            try requireSuccess(CMBlockBufferAppendMemoryBlock(
                resolvedBlock,
                memoryBlock: nil,
                length: segment.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: segment.count,
                flags: 0
            ))
            let copyStatus = segment.withUnsafeBytes { source in
                CMBlockBufferReplaceDataBytes(
                    with: source.baseAddress!,
                    blockBuffer: resolvedBlock,
                    offsetIntoDestination: offset,
                    dataLength: segment.count
                )
            }
            try requireSuccess(copyStatus)
            offset += segment.count
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleSize = Int(format.mBytesPerFrame)
        let isPlanar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        var sample: CMSampleBuffer?
        let status = withUnsafePointer(to: &sampleSize) { sampleSizePointer in
            CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: resolvedBlock,
                dataReady: dataReady,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: resolvedFormat,
                sampleCount: frames,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: isPlanar ? 0 : 1,
                sampleSizeArray: isPlanar ? nil : sampleSizePointer,
                sampleBufferOut: &sample
            )
        }
        try requireSuccess(status)
        return try XCTUnwrap(sample)
    }

    private func requireSuccess(_ status: OSStatus) throws {
        guard status == noErr else {
            throw NSError(domain: "CameraAudioMeterMeasurementTests", code: Int(status))
        }
    }
}
