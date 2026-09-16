import AudioToolbox
import CoreMedia
import Foundation

/// A level in full-scale PCM units, with no presentation gain. Unknown audio
/// layouts remain unavailable instead of being reinterpreted as Int16 samples.
enum CameraAudioMeterMeasurement {
    static func normalizedRMS(from sampleBuffer: CMSampleBuffer) -> Float? {
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer),
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaType(format) == kCMMediaType_Audio,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM,
              description.mSampleRate.isFinite, description.mSampleRate > 0,
              (1...32).contains(description.mChannelsPerFrame),
              description.mFramesPerPacket == 1 else {
            return nil
        }

        // Non-mixable does not change sample representation. Every other flag
        // must describe one of these explicitly supported packed layouts.
        let flags = description.mFormatFlags & ~kAudioFormatFlagIsNonMixable
        let integerFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        let floatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        let isFloat: Bool
        let isPlanar: Bool
        let sampleByteCount: Int
        switch flags {
        case integerFlags where description.mBitsPerChannel == 16:
            isFloat = false
            isPlanar = false
            sampleByteCount = MemoryLayout<Int16>.size
        case floatFlags where description.mBitsPerChannel == 32:
            isFloat = true
            isPlanar = false
            sampleByteCount = MemoryLayout<Float32>.size
        case floatFlags | kAudioFormatFlagIsNonInterleaved where description.mBitsPerChannel == 32:
            isFloat = true
            isPlanar = true
            sampleByteCount = MemoryLayout<Float32>.size
        default:
            // Big-endian, unsigned, padded, compressed, and other bit depths
            // are not the capture PCM contract implemented by this meter.
            return nil
        }

        let channels = Int(description.mChannelsPerFrame)
        let channelsPerBuffer = isPlanar ? 1 : channels
        let bytesPerFrame = sampleByteCount * channelsPerBuffer
        guard Int(description.mBytesPerFrame) == bytesPerFrame,
              Int(description.mBytesPerPacket) == bytesPerFrame else {
            return nil
        }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }
        let (requiredBytes, byteOverflow) = frameCount.multipliedReportingOverflow(by: bytesPerFrame)
        let (totalSampleCount, sampleOverflow) = frameCount.multipliedReportingOverflow(by: channels)
        guard !byteOverflow, !sampleOverflow else { return nil }
        let (totalBytes, totalByteOverflow) = totalSampleCount.multipliedReportingOverflow(by: sampleByteCount)
        guard !totalByteOverflow,
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              CMBlockBufferGetDataLength(dataBuffer) >= totalBytes else {
            return nil
        }

        // CoreMedia supplies one contiguous region per AudioBuffer, including
        // separate Float32 planes and originally segmented CMBlockBuffer data.
        let bufferCount = isPlanar ? channels : 1
        let listByteCount = MemoryLayout<AudioBufferList>.size
            + (bufferCount - 1) * MemoryLayout<AudioBuffer>.stride
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: listByteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlock: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: listByteCount,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &retainedBlock
        )
        guard status == noErr, let retainedBlock,
              list.pointee.mNumberBuffers == UInt32(bufferCount) else {
            return nil
        }

        return withExtendedLifetime(retainedBlock) {
            var sumSquares = 0.0
            for buffer in UnsafeMutableAudioBufferListPointer(list) {
                guard buffer.mNumberChannels == UInt32(channelsPerBuffer),
                      Int(buffer.mDataByteSize) >= requiredBytes,
                      let data = buffer.mData else {
                    return nil
                }
                let samplesInBuffer = requiredBytes / sampleByteCount
                for index in 0..<samplesInBuffer {
                    let samplePointer = UnsafeRawPointer(data).advanced(by: index * sampleByteCount)
                    let value: Double
                    if isFloat {
                        let sample = samplePointer.loadUnaligned(as: Float32.self)
                        guard sample.isFinite else { return nil }
                        value = Double(sample)
                    } else {
                        value = Double(samplePointer.loadUnaligned(as: Int16.self)) / 32_768.0
                    }
                    sumSquares += value * value
                }
            }
            guard sumSquares.isFinite else { return nil }
            // Float PCM may exceed nominal full scale. Saturation belongs at
            // the final meter boundary, after measuring every declared sample.
            return Float(min(1, sqrt(sumSquares / Double(totalSampleCount))))
        }
    }
}
