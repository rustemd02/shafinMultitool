import Foundation

enum BoundedServiceHTTPError: Error, Equatable {
    case invalidRequest
    case malformedResponse
    case transport
}

/// One JSON service attempt. Authentication, idempotency and retries belong to
/// the caller; this owner bounds the response and the lifetime of the socket.
enum BoundedServiceHTTPTransport {
    private struct Response: Sendable {
        let data: Data
        let http: HTTPURLResponse
    }

    static func send(
        _ original: URLRequest,
        session: URLSession,
        maximumResponseBytes: Int,
        timeoutSeconds: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard maximumResponseBytes > 0,
              timeoutSeconds.isFinite, timeoutSeconds > 0, timeoutSeconds <= 300,
              let url = original.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.host?.isEmpty == false,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65_535).contains($0) }) ?? true else {
            throw BoundedServiceHTTPError.invalidRequest
        }
        var request = original
        request.timeoutInterval = timeoutSeconds
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let boundedRequest = request
        do {
            let result = try await withThrowingTaskGroup(of: Response.self) { group in
                group.addTask {
                    let (bytes, response) = try await session.bytes(
                        for: boundedRequest, delegate: ServiceHTTPRedirectGuard()
                    )
                    defer { bytes.task.cancel() }
                    guard let http = response as? HTTPURLResponse,
                          response.expectedContentLength >= -1,
                          response.expectedContentLength <= maximumResponseBytes else {
                        throw BoundedServiceHTTPError.malformedResponse
                    }
                    let bodyless = http.statusCode == 204 || http.statusCode == 205
                    if (200...299).contains(http.statusCode), !bodyless {
                        let contentType = http.value(forHTTPHeaderField: "Content-Type")?
                            .split(separator: ";", maxSplits: 1).first?
                            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        guard contentType == "application/json" else {
                            throw BoundedServiceHTTPError.malformedResponse
                        }
                    }
                    return try await withTaskCancellationHandler {
                        var data = Data()
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            guard !bodyless, data.count < maximumResponseBytes else {
                                throw BoundedServiceHTTPError.malformedResponse
                            }
                            data.append(byte)
                        }
                        try Task.checkCancellation()
                        return Response(data: data, http: http)
                    } onCancel: {
                        bytes.task.cancel()
                    }
                }
                group.addTask {
                    // A total deadline also terminates a response that keeps
                    // sending a few bytes before the idle timeout expires.
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw BoundedServiceHTTPError.transport
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw BoundedServiceHTTPError.transport
                }
                return result
            }
            try Task.checkCancellation()
            return (result.data, result.http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BoundedServiceHTTPError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw BoundedServiceHTTPError.transport
        }
    }
}

private final class ServiceHTTPRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Return the original 3xx response without forwarding a content body,
        // installation token, ownership proof or receipt capability elsewhere.
        completionHandler(nil)
    }
}
