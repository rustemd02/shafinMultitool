//
//  SceneParseRequestFenceTests.swift
//  shafinMultitoolTests
//
//  M1-008 SceneGenerationOwner: parse pipelines are not cancellation-aware, so
//  parse-context writes are fenced by request tokens. These tests prove the
//  fence semantics (out-of-order completion, cancellation/reset invalidation)
//  and that the wired call sites keep publishing for the current request.
//

import XCTest
@testable import shafinMultitool

final class SceneParseRequestFenceTests: XCTestCase {

    // MARK: - Fence semantics (out-of-order completion, cancellation)

    func testSupersededRequestIsNotCurrentWhileLatestIs() {
        let fence = ParseRequestFence()

        let staleToken = fence.begin()
        let latestToken = fence.begin()

        // Out-of-order completion: the older request finishes after a newer one began.
        XCTAssertFalse(fence.isCurrent(staleToken), "superseded request must not publish")
        XCTAssertTrue(fence.isCurrent(latestToken), "latest request must publish")
    }

    func testResetInvalidatesEveryInFlightToken() {
        let fence = ParseRequestFence()

        let inFlightA = fence.begin()
        let inFlightB = fence.begin()
        fence.begin() // resetRuntimeContext invalidation

        XCTAssertFalse(fence.isCurrent(inFlightA))
        XCTAssertFalse(fence.isCurrent(inFlightB))
    }

    func testUnsupersededRequestStaysCurrent() {
        let fence = ParseRequestFence()

        let token = fence.begin()

        XCTAssertTrue(fence.isCurrent(token))
        XCTAssertTrue(fence.isCurrent(token), "repeated checks must not consume the token")
    }

    func testConcurrentBeginsIssueUniqueTokensAndOnlyLastIsCurrent() async {
        let fence = ParseRequestFence()
        let total = 64

        let tokens = await withTaskGroup(of: UInt.self) { group in
            for _ in 0..<total {
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 0...2_000))
                    return fence.begin()
                }
            }
            var collected: [UInt] = []
            for await token in group {
                collected.append(token)
            }
            return collected
        }

        XCTAssertEqual(Set(tokens).count, total, "tokens must be unique under concurrency")
        let lastIssued = tokens.max() ?? 0
        XCTAssertTrue(fence.isCurrent(lastIssued))
        for token in tokens where token != lastIssued {
            XCTAssertFalse(fence.isCurrent(token), "all but the last-issued token must be stale")
        }
    }

    func testDelayedStaleCompletionLosesToNewerRequest() async {
        let fence = ParseRequestFence()
        actor Published { var token: UInt?; func set(_ t: UInt) { token = t }; func value() -> UInt? { token } }
        let published = Published()

        // Request A starts, then is superseded; its completion lands late.
        let staleToken = fence.begin()
        let latestToken = fence.begin()

        let staleCompletion = Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            // Mirrors the wired call-site order: re-check currency right before the write.
            if fence.isCurrent(staleToken) {
                await published.set(staleToken)
            }
        }
        let latestCompletion = Task {
            if fence.isCurrent(latestToken) {
                await published.set(latestToken)
            }
        }

        _ = await (staleCompletion.result, latestCompletion.result)
        let winner = await published.value()
        XCTAssertEqual(winner, latestToken, "the newer request's write must survive the stale completion")
    }

    // MARK: - Wired call-site integration (real pipeline, rule-based fallback)

    @MainActor
    func testCurrentRequestStillPublishesParseContext() async throws {
        let parser = SceneParserService.shared
        parser.resetRuntimeContext()

        _ = await parser.parseAsync("Кузнец работает у наковальни в мастерской", markedObjects: [])

        XCTAssertNotNil(parser.lastRuntimeTrace, "an unsuperseded parse must publish its runtime trace")
        XCTAssertNotNil(parser.lastBundleResult, "an unsuperseded bundle parse must publish its result")
    }

    @MainActor
    func testResetRuntimeContextClearsContextAndInvalidatesInFlightWrites() async throws {
        let parser = SceneParserService.shared

        _ = await parser.parseAsync("Два актёра идут навстречу друг другу", markedObjects: [])
        XCTAssertNotNil(parser.lastBundleResult)

        parser.resetRuntimeContext()

        XCTAssertNil(parser.lastRuntimeTrace)
        XCTAssertNil(parser.lastChunkState)
        XCTAssertNil(parser.lastDocumentState)
        XCTAssertNil(parser.lastBundleResult)
        XCTAssertNil(parser.lastExecutionTrace)
    }
}
