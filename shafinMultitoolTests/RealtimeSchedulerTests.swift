import CoreMedia
import CoreVideo
import ImageIO
import XCTest
@testable import shafinMultitool

final class RealtimeSchedulerTests: XCTestCase {

    func testLowPriorityConsumerIsSkippedWhenHeavyModelsAreDisabled() {
        let scheduler = RealtimeScheduler()
        let lowConsumer = CountingFrameConsumer()
        scheduler.register(consumer: lowConsumer, priority: .low, targetFrequency: 60)

        scheduler.dispatchSynchronouslyForTesting(
            context: makeFrameContext(isStable: true),
            budget: ThermalGovernor.Budget(
                highPriorityFrequency: 60,
                mediumPriorityFrequency: 60,
                lowPriorityFrequency: 60,
                heavyModelsEnabled: false
            )
        )

        XCTAssertEqual(lowConsumer.count, 0)
    }

    func testStableConsumerIsSkippedForUnstableFrames() {
        let scheduler = RealtimeScheduler()
        let stableConsumer = CountingFrameConsumer()
        scheduler.register(consumer: stableConsumer, priority: .high, targetFrequency: 60, requiresStability: true)

        scheduler.dispatchSynchronouslyForTesting(
            context: makeFrameContext(isStable: false),
            budget: ThermalGovernor.Budget(
                highPriorityFrequency: 60,
                mediumPriorityFrequency: 60,
                lowPriorityFrequency: 60,
                heavyModelsEnabled: true
            )
        )

        XCTAssertEqual(stableConsumer.count, 0)
    }

    func testZeroHighPriorityBudgetDoesNotDispatchHighConsumer() {
        let scheduler = RealtimeScheduler()
        let highConsumer = CountingFrameConsumer()
        scheduler.register(consumer: highConsumer, priority: .high, targetFrequency: 60)

        scheduler.dispatchSynchronouslyForTesting(
            context: makeFrameContext(isStable: true),
            budget: ThermalGovernor.Budget(
                highPriorityFrequency: 0,
                mediumPriorityFrequency: 60,
                lowPriorityFrequency: 60,
                heavyModelsEnabled: true
            )
        )

        XCTAssertEqual(highConsumer.count, 0)
    }

    func testZeroMediumPriorityBudgetDoesNotDispatchMediumConsumer() {
        let scheduler = RealtimeScheduler()
        let mediumConsumer = CountingFrameConsumer()
        scheduler.register(consumer: mediumConsumer, priority: .medium, targetFrequency: 60)

        scheduler.dispatchSynchronouslyForTesting(
            context: makeFrameContext(isStable: true),
            budget: ThermalGovernor.Budget(
                highPriorityFrequency: 60,
                mediumPriorityFrequency: 0,
                lowPriorityFrequency: 60,
                heavyModelsEnabled: true
            )
        )

        XCTAssertEqual(mediumConsumer.count, 0)
    }

    func testZeroLowPriorityBudgetDoesNotDispatchLowConsumer() {
        let scheduler = RealtimeScheduler()
        let lowConsumer = CountingFrameConsumer()
        scheduler.register(consumer: lowConsumer, priority: .low, targetFrequency: 60)

        scheduler.dispatchSynchronouslyForTesting(
            context: makeFrameContext(isStable: true),
            budget: ThermalGovernor.Budget(
                highPriorityFrequency: 60,
                mediumPriorityFrequency: 60,
                lowPriorityFrequency: 0,
                heavyModelsEnabled: true
            )
        )

        XCTAssertEqual(lowConsumer.count, 0)
    }

    private func makeFrameContext(isStable: Bool) -> FrameContext {
        FrameContext(
            pixelBuffer: makePixelBuffer(),
            timestamp: CMTimeMakeWithSeconds(1, preferredTimescale: 600),
            orientation: .up,
            isStable: isStable,
            shakeLevel: isStable ? 0.05 : 0.6,
            motionState: isStable ? .still : .moving
        )
    }

    private func makePixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: 4,
            kCVPixelBufferHeightKey as String: 4,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            4,
            4,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return pixelBuffer!
    }
}

private final class CountingFrameConsumer: FrameConsumer {
    private(set) var count = 0

    func consumeFrame(_ context: FrameContext) {
        count += 1
    }
}
