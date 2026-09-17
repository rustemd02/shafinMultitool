import Foundation
import Dispatch
import XCTest
@testable import shafinMultitool

/// Every URL in these ephemeral sessions is intercepted. These are URLSession
/// lifecycle/contract controls, not a live TLS server or redirect qualification.
private final class BoundedHTTPFixtureProtocol: URLProtocol, @unchecked Sendable {
    enum Delivery {
        case complete([Data])
        case holdOpen([Data])
        case trickle(TimeInterval)
    }

    final class Fixture: @unchecked Sendable {
        let status: Int?
        let headers: [String: String]
        let delivery: Delivery
        let started = XCTestExpectation(description: "owned request dispatched")
        let stopped = XCTestExpectation(description: "owned request stopped")
        let firstChunk = XCTestExpectation(description: "first body chunk delivered")
        private let lock = NSLock()
        private var starts = 0
        private var stops = 0
        private var chunks = 0
        private var capturedRequest: URLRequest?
        private var capturedBody: Data?

        init(status: Int? = 200, headers: [String: String] = ["Content-Type": "application/json"],
             delivery: Delivery) {
            self.status = status
            self.headers = headers
            self.delivery = delivery
        }

        func recordStart(_ request: URLRequest) {
            let body: Data?
            if let data = request.httpBody {
                body = data
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1_024)
                var result = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    result.append(bytes, count: count)
                }
                body = result
            } else {
                body = nil
            }
            lock.lock()
            starts += 1
            capturedRequest = request
            capturedBody = body
            let first = starts == 1
            lock.unlock()
            if first { started.fulfill() }
        }

        func recordStop() {
            lock.lock()
            stops += 1
            let first = stops == 1
            lock.unlock()
            if first { stopped.fulfill() }
        }

        func recordChunk() {
            lock.lock()
            chunks += 1
            let first = chunks == 1
            lock.unlock()
            if first { firstChunk.fulfill() }
        }

        var observation: (starts: Int, stops: Int, chunks: Int, request: URLRequest?, body: Data?) {
            lock.lock()
            defer { lock.unlock() }
            return (starts, stops, chunks, capturedRequest, capturedBody)
        }
    }

    private static let registryLock = NSLock()
    private static var fixtures: [String: Fixture] = [:]
    private let deliveryQueue = DispatchQueue(label: "BoundedHTTPFixtureProtocol.delivery")
    private var fixture: Fixture?
    private var timer: DispatchSourceTimer?
    private var didStop = false

    static func register(_ fixture: Fixture) -> URL {
        let host = UUID().uuidString.lowercased() + ".bounded-http.invalid"
        registryLock.lock()
        fixtures[host] = fixture
        registryLock.unlock()
        return URL(string: "https://" + host + "/proxy/v1/test")!
    }

    static func unregister(_ url: URL) {
        registryLock.lock()
        fixtures.removeValue(forKey: url.host ?? "")
        registryLock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        deliveryQueue.async { [self] in
            guard !didStop else { return }
            Self.registryLock.lock()
            let selected = Self.fixtures[request.url?.host ?? ""]
            Self.registryLock.unlock()
            guard let selected else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            fixture = selected
            selected.recordStart(request)
            // Nil status deliberately never produces headers. The task remains
            // owned by URLSession until its timeout/cancellation stops this owner.
            guard let status = selected.status else { return }
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status,
                                                 httpVersion: "HTTP/1.1", headerFields: selected.headers) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            switch selected.delivery {
            case .complete(let chunks):
                for chunk in chunks { emit(chunk) }
                client?.urlProtocolDidFinishLoading(self)
            case .holdOpen(let chunks):
                for chunk in chunks { emit(chunk) }
                // No completion or error callback: cancellation must stop this request.
            case .trickle(let interval):
                let source = DispatchSource.makeTimerSource(queue: deliveryQueue)
                source.schedule(deadline: .now(), repeating: interval)
                source.setEventHandler { [weak self] in self?.emit(Data([0x20])) }
                timer = source
                source.resume()
            }
        }
    }

    private func emit(_ data: Data) {
        guard !didStop else { return }
        client?.urlProtocol(self, didLoad: data)
        fixture?.recordChunk()
    }

    override func stopLoading() {
        deliveryQueue.async { [self] in
            guard !didStop else { return }
            didStop = true
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
            fixture?.recordStop()
        }
    }
}

final class BoundedServiceHTTPTransportTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedHTTPFixtureProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testExactDeclaredAndStreamedLimitPreservesCallerIdentityAndBody() async throws {
        let data = Data("{\"ok\":true}".utf8)
        for declared in [false, true] {
            var headers = ["Content-Type": "application/json; charset=utf-8"]
            if declared { headers["Content-Length"] = String(data.count) }
            let fixture = BoundedHTTPFixtureProtocol.Fixture(headers: headers,
                delivery: .complete([data.prefix(3), data.dropFirst(3)]))
            let url = BoundedHTTPFixtureProtocol.register(fixture)
            defer { BoundedHTTPFixtureProtocol.unregister(url) }
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 99)
            request.httpMethod = "POST"
            request.httpBody = Data("{\"fixture\":1}".utf8)
            request.setValue("Bearer synthetic-fixture-token", forHTTPHeaderField: "Authorization")
            request.setValue("synthetic-request-1", forHTTPHeaderField: "Idempotency-Key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (actual, response) = try await BoundedServiceHTTPTransport.send(
                request, session: session, maximumResponseBytes: data.count, timeoutSeconds: 1
            )
            XCTAssertEqual(actual, data)
            XCTAssertEqual(response.statusCode, 200)
            let seen = fixture.observation
            XCTAssertEqual(seen.starts, 1)
            XCTAssertEqual(seen.body, request.httpBody)
            XCTAssertEqual(seen.request?.url, url)
            XCTAssertEqual(seen.request?.httpMethod, "POST")
            XCTAssertEqual(seen.request?.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-fixture-token")
            XCTAssertEqual(seen.request?.value(forHTTPHeaderField: "Idempotency-Key"), "synthetic-request-1")
            XCTAssertEqual(seen.request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(seen.request?.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(seen.request?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertEqual(seen.request?.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(seen.request?.httpShouldHandleCookies, false)
            XCTAssertEqual(seen.request?.timeoutInterval, 1)
        }
    }

    func testDeclaredAndStreamedOverflowStopOpenTaskWithoutRetry() async {
        let cases: [BoundedHTTPFixtureProtocol.Fixture] = [
            .init(headers: ["Content-Type": "application/json", "Content-Length": "9"],
                  delivery: .holdOpen([])),
            .init(delivery: .holdOpen([Data(repeating: 32, count: 8), Data([32])]))
        ]
        for fixture in cases {
            let url = BoundedHTTPFixtureProtocol.register(fixture)
            defer { BoundedHTTPFixtureProtocol.unregister(url) }
            let outcome = await watchedAttempt(URLRequest(url: url), maximum: 8, timeout: 1)
            assertFailure(.malformedResponse, outcome)
            await assertStopped(fixture)
        }
    }

    func testInvalidURLAndLimitConfigurationFailsBeforeDispatch() async {
        let fixture = BoundedHTTPFixtureProtocol.Fixture(delivery: .holdOpen([]))
        let url = BoundedHTTPFixtureProtocol.register(fixture)
        defer { BoundedHTTPFixtureProtocol.unregister(url) }
        let invalidLimits: [(Int, TimeInterval)] = [
            (0, 1), (-1, 1), (8, 0), (8, -1), (8, .infinity), (8, .nan), (8, 301)
        ]
        for (maximum, timeout) in invalidLimits {
            let outcome = await watchedAttempt(URLRequest(url: url), maximum: maximum, timeout: timeout)
            assertFailure(.invalidRequest, outcome)
        }
        let host = url.host!
        let addresses = ["http://\(host)/v1", "https://user:pass@\(host)/v1",
                         "https://\(host)/v1?private=fixture", "https://\(host)/v1#fragment",
                         "https://\(host):0/v1", "https://\(host):65536/v1", "https:/relative"]
        for address in addresses {
            guard let invalid = URL(string: address) else {
                XCTFail("Invalid-request fixture must remain representable: \(address)")
                continue
            }
            let outcome = await watchedAttempt(URLRequest(url: invalid), maximum: 8, timeout: 1)
            assertFailure(.invalidRequest, outcome)
        }
        var noURL = URLRequest(url: url)
        noURL.url = nil
        let outcome = await watchedAttempt(noURL, maximum: 8, timeout: 1)
        assertFailure(.invalidRequest, outcome)
        XCTAssertEqual(fixture.observation.starts, 0)
        XCTAssertEqual(fixture.observation.stops, 0)
    }

    func testHTMLSuccessIsRejectedBeforeWaitingForItsBody() async {
        let fixture = BoundedHTTPFixtureProtocol.Fixture(headers: ["Content-Type": "text/html"],
                                                         delivery: .holdOpen([]))
        let url = BoundedHTTPFixtureProtocol.register(fixture)
        defer { BoundedHTTPFixtureProtocol.unregister(url) }
        let outcome = await watchedAttempt(URLRequest(url: url), maximum: 64, timeout: 1)
        assertFailure(.malformedResponse, outcome)
        await assertStopped(fixture)
    }

    func testJSONMediaTypeAndEmpty204And205AreAccepted() async throws {
        for status in [200, 204, 205] {
            let body = status == 200 ? Data("{}".utf8) : Data()
            let headers = status == 200 ? ["Content-Type": " Application/JSON ; charset=UTF-8"] : [:]
            let fixture = BoundedHTTPFixtureProtocol.Fixture(status: status, headers: headers,
                                                             delivery: .complete(body.isEmpty ? [] : [body]))
            let url = BoundedHTTPFixtureProtocol.register(fixture)
            defer { BoundedHTTPFixtureProtocol.unregister(url) }
            let (actual, response) = try await BoundedServiceHTTPTransport.send(
                URLRequest(url: url), session: session, maximumResponseBytes: 64, timeoutSeconds: 1
            )
            XCTAssertEqual(response.statusCode, status)
            XCTAssertEqual(actual, body)
            XCTAssertEqual(fixture.observation.starts, 1)
        }
    }

    func testTotalDeadlineStopsIdleBeforeHeadersIdleBodyAndContinuousTrickle() async {
        let cases: [(String, BoundedHTTPFixtureProtocol.Fixture)] = [
            ("before headers", .init(status: nil, delivery: .holdOpen([]))),
            ("idle body", .init(delivery: .holdOpen([]))),
            ("continuous trickle", .init(delivery: .trickle(0.05)))
        ]
        for (name, fixture) in cases {
            let url = BoundedHTTPFixtureProtocol.register(fixture)
            defer { BoundedHTTPFixtureProtocol.unregister(url) }
            let started = ProcessInfo.processInfo.systemUptime
            let outcome = await watchedAttempt(URLRequest(url: url), maximum: 4_096, timeout: 0.6)
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            assertFailure(.transport, outcome)
            XCTAssertGreaterThanOrEqual(elapsed, 0.25, name)
            XCTAssertLessThan(elapsed, 2, "Total deadline did not complete promptly: \(name)")
            await assertStopped(fixture)
            if name == "continuous trickle" {
                XCTAssertGreaterThanOrEqual(fixture.observation.chunks, 3,
                                             "Must exercise repeated delivery, not an idle stub")
            }
        }
    }

    func testCancellationBeforeHeadersAndDuringOpenBodyStopsOnlyOneAttempt() async {
        for beforeHeaders in [true, false] {
            let fixture = BoundedHTTPFixtureProtocol.Fixture(status: beforeHeaders ? nil : 200,
                                                             delivery: .holdOpen([Data([32])]))
            let url = BoundedHTTPFixtureProtocol.register(fixture)
            defer { BoundedHTTPFixtureProtocol.unregister(url) }
            let session = self.session!
            let task = Task {
                try await BoundedServiceHTTPTransport.send(URLRequest(url: url), session: session,
                                                          maximumResponseBytes: 64, timeoutSeconds: 5)
            }
            await fulfillment(of: [beforeHeaders ? fixture.started : fixture.firstChunk], timeout: 1)
            // Body emission establishes an open body fixture, not a private AsyncBytes
            // continuation position. Either cancellation handoff must release its task.
            let cancelledAt = ProcessInfo.processInfo.systemUptime
            task.cancel()
            switch await task.result {
            case .success: XCTFail("Cancelled request returned a successful response")
            case .failure(let error): XCTAssertTrue(error is CancellationError, "\(error)")
            }
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - cancelledAt, 2,
                              "Cancellation waited for the five-second request deadline")
            await assertStopped(fixture)
        }
    }

    func testCancelledAttemptDoesNotInvalidateSharedSession() async throws {
        let held = BoundedHTTPFixtureProtocol.Fixture(delivery: .holdOpen([Data([32])]))
        let heldURL = BoundedHTTPFixtureProtocol.register(held)
        let survivor = BoundedHTTPFixtureProtocol.Fixture(delivery: .complete([Data("{}".utf8)]))
        let survivorURL = BoundedHTTPFixtureProtocol.register(survivor)
        defer {
            BoundedHTTPFixtureProtocol.unregister(heldURL)
            BoundedHTTPFixtureProtocol.unregister(survivorURL)
        }
        let session = self.session!
        let heldTask = Task {
            try await BoundedServiceHTTPTransport.send(URLRequest(url: heldURL), session: session,
                                                      maximumResponseBytes: 64, timeoutSeconds: 5)
        }
        await fulfillment(of: [held.firstChunk], timeout: 1)
        heldTask.cancel()
        switch await heldTask.result {
        case .success: XCTFail("Cancelled request returned a response")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        await assertStopped(held)
        let (body, response) = try await BoundedServiceHTTPTransport.send(
            URLRequest(url: survivorURL), session: session, maximumResponseBytes: 64, timeoutSeconds: 1
        )
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(body, Data("{}".utf8))
        XCTAssertEqual(survivor.observation.starts, 1)
    }

    func testPrecancelledAttemptNeverDispatches() async {
        let fixture = BoundedHTTPFixtureProtocol.Fixture(delivery: .holdOpen([]))
        let url = BoundedHTTPFixtureProtocol.register(fixture)
        defer { BoundedHTTPFixtureProtocol.unregister(url) }
        let session = self.session!
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BoundedServiceHTTPTransport.send(URLRequest(url: url), session: session,
                                                             maximumResponseBytes: 64, timeoutSeconds: 1)
        }
        switch await task.result {
        case .success: XCTFail("Precancelled request returned a response")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(fixture.observation.starts, 0)
    }

    func testOriginal3xxStatusIsReturnedToCallerWithoutInternalRetry() async throws {
        // This fixture deliberately emits an original HTTP status only. It does NOT
        // call URLProtocol.wasRedirectedTo or claim to test Foundation's TLS redirects.
        let fixture = BoundedHTTPFixtureProtocol.Fixture(status: 302,
            headers: ["Content-Type": "text/html", "Location": "https://other.invalid/fixture"],
            delivery: .complete([Data("redirect fixture".utf8)]))
        let url = BoundedHTTPFixtureProtocol.register(fixture)
        defer { BoundedHTTPFixtureProtocol.unregister(url) }
        let (body, response) = try await BoundedServiceHTTPTransport.send(
            URLRequest(url: url), session: session, maximumResponseBytes: 64, timeoutSeconds: 1
        )
        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(response.url, url)
        XCTAssertEqual(body, Data("redirect fixture".utf8))
        XCTAssertEqual(fixture.observation.starts, 1)
    }

    private func watchedAttempt(_ request: URLRequest, maximum: Int, timeout: TimeInterval) async
        -> Result<(Data, HTTPURLResponse), Error> {
        let session = self.session!
        let task = Task {
            try await BoundedServiceHTTPTransport.send(request, session: session,
                                                      maximumResponseBytes: maximum, timeoutSeconds: timeout)
        }
        // A cleanup fallback for a broken deadline when URLSession cancellation works.
        // It is not an independent process timeout if cancellation itself is broken.
        // Watchdog cancellation is observably different from expected .transport.
        let watchdog = Task {
            do { try await Task.sleep(nanoseconds: 3_000_000_000) }
            catch { return }
            task.cancel()
        }
        defer { watchdog.cancel() }
        return await task.result
    }

    private func assertFailure(_ expected: BoundedServiceHTTPError,
                               _ outcome: Result<(Data, HTTPURLResponse), Error>,
                               file: StaticString = #filePath, line: UInt = #line) {
        switch outcome {
        case .success: XCTFail("Expected \(expected)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error as? BoundedServiceHTTPError, expected, file: file, line: line)
        }
    }

    private func assertStopped(_ fixture: BoundedHTTPFixtureProtocol.Fixture,
                               file: StaticString = #filePath, line: UInt = #line) async {
        await fulfillment(of: [fixture.stopped], timeout: 1)
        let seen = fixture.observation
        XCTAssertEqual(seen.starts, 1, file: file, line: line)
        XCTAssertEqual(seen.stops, 1, file: file, line: line)
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(tasks.contains { $0.state == .running || $0.state == .suspended },
                       "Owned URLSession task remains active", file: file, line: line)
    }
}
