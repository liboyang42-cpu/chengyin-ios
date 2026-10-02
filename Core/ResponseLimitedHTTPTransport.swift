import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A failed response never proves that a dispatched upload did not reach the server.
/// Callers must keep their pending-write record for every `outcomeUnknown` failure.
public enum ResponseLimitedHTTPTransportFailure: Error, Equatable {
    case disabled, invalidConfiguration, invalidRequest
    case outcomeUnknown(Reason)

    public enum Reason: Equatable {
        case cancelled, responseTooLarge, redirectDenied, invalidResponse, network
    }
}

/// Opt-in, one-request ephemeral transport. This does not authorize an endpoint or origin;
/// the calling client must still apply its existing scope, endpoint and origin gates.
/// Unlike `URLSession.data(for:)`, the delegate bounds bytes before accumulating them.
public final class ResponseLimitedHTTPTransport: HTTPTransport, @unchecked Sendable {
    public static let defaultMaximumResponseBytes = 1024 * 1024
    public let enabled: Bool
    public let maximumResponseBytes: Int
    private let makeTask: ResponseLimitedHTTPTaskFactory

    public init(enabled: Bool = false, maximumResponseBytes: Int = ResponseLimitedHTTPTransport.defaultMaximumResponseBytes) {
        self.enabled = enabled
        self.maximumResponseBytes = maximumResponseBytes
        self.makeTask = { request, delegate in
            ResponseLimitedURLSessionTask(request: request, delegate: delegate)
        }
    }

    /// Internal, inert-task injection for deterministic delegate/chunk tests. The factory
    /// must not send or deliver callbacks until `resume()` is called.
    init(enabled: Bool = false, maximumResponseBytes: Int = ResponseLimitedHTTPTransport.defaultMaximumResponseBytes,
         makeTask: @escaping ResponseLimitedHTTPTaskFactory) {
        self.enabled = enabled
        self.maximumResponseBytes = maximumResponseBytes
        self.makeTask = makeTask
    }

    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        return configuration
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard enabled else { throw ResponseLimitedHTTPTransportFailure.disabled }
        guard maximumResponseBytes > 0 else { throw ResponseLimitedHTTPTransportFailure.invalidConfiguration }
        guard let url = request.url, url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, request.httpBodyStream == nil else {
            throw ResponseLimitedHTTPTransportFailure.invalidRequest
        }
        var request = request
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        request.setValue(nil, forHTTPHeaderField: "Cookie2")

        let exchange = ResponseLimitedHTTPExchange(maximumResponseBytes: maximumResponseBytes)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            let result = try await exchange.send(request, makeTask: makeTask)
            // Completion and cancellation can race. Do not hand a cancelled caller a
            // receipt it could mistake for permission to clear its pending marker.
            guard !Task.isCancelled else {
                throw ResponseLimitedHTTPTransportFailure.outcomeUnknown(.cancelled)
            }
            return result
        }, onCancel: { exchange.cancel() })
    }
}

protocol ResponseLimitedHTTPTask: AnyObject {
    func resume()
    func invalidateAndCancel()
}
typealias ResponseLimitedHTTPTaskFactory = (URLRequest, ResponseLimitedHTTPExchange) -> any ResponseLimitedHTTPTask

/// Owns one session/task, with no cookie jar, credential store, disk cache or redirects.
private final class ResponseLimitedURLSessionTask: ResponseLimitedHTTPTask {
    private let session: URLSession
    private let task: URLSessionDataTask

    init(request: URLRequest, delegate: ResponseLimitedHTTPExchange) {
        let configuration = ResponseLimitedHTTPTransport.makeSessionConfiguration()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        self.session = session
        task = session.dataTask(with: request)
    }

    func resume() { task.resume() }
    func invalidateAndCancel() { task.cancel(); session.invalidateAndCancel() }
}

/// All terminal transitions, including cancellation before continuation installation,
/// are protected by the same lock. Delegate callbacks never resume a continuation twice.
final class ResponseLimitedHTTPExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumResponseBytes: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private var task: (any ResponseLimitedHTTPTask)?
    private var bytes = Data()
    private var status: Int?
    private var dispatched = false
    private var finished = false
    private var peak = 0

    init(maximumResponseBytes: Int) {
        self.maximumResponseBytes = maximumResponseBytes
        super.init()
    }

    // Internal diagnostics expose counts only, never request or response contents.
    var bufferedByteCount: Int { lock.lock(); defer { lock.unlock() }; return bytes.count }
    var peakBufferedByteCount: Int { lock.lock(); defer { lock.unlock() }; return peak }

    func send(_ request: URLRequest, makeTask: ResponseLimitedHTTPTaskFactory) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()

            // The factory creates a suspended task only. Cancellation may win while
            // it is being created; in that case it is invalidated without resuming.
            let task = makeTask(request, self)
            lock.lock()
            guard !finished else { lock.unlock(); task.invalidateAndCancel(); return }
            self.task = task
            // Once handed to the networking layer, even zero reported bytes cannot
            // establish that the server did not receive part or all of an upload.
            dispatched = true
            lock.unlock()
            task.resume()
        }
    }

    func cancel() {
        lock.lock()
        let error: Error = dispatched
            ? ResponseLimitedHTTPTransportFailure.outcomeUnknown(.cancelled)
            : CancellationError()
        let completion = finishLocked(.failure(error))
        lock.unlock()
        completion?.deliver()
    }

    /// Returns the delegate response disposition; rejects the advertised size early.
    func receive(_ response: URLResponse) -> Bool {
        lock.lock()
        guard !finished else { lock.unlock(); return false }
        let failure: ResponseLimitedHTTPTransportFailure.Reason?
        if let response = response as? HTTPURLResponse, status == nil {
            if (300..<400).contains(response.statusCode) { failure = .redirectDenied }
            else if response.expectedContentLength > Int64(maximumResponseBytes) { failure = .responseTooLarge }
            else { status = response.statusCode; failure = nil }
        } else { failure = .invalidResponse }
        let completion = failure.flatMap { finishLocked(.failure(ResponseLimitedHTTPTransportFailure.outcomeUnknown($0))) }
        lock.unlock()
        completion?.deliver()
        return failure == nil
    }

    func receive(_ chunk: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let failure: ResponseLimitedHTTPTransportFailure.Reason?
        if status == nil { failure = .invalidResponse }
        // Subtraction cannot overflow: accumulated bytes are always within the cap.
        // Never append an oversized chunk, even if Content-Length was absent or false.
        else if chunk.count > maximumResponseBytes - bytes.count { failure = .responseTooLarge }
        else {
            bytes.append(chunk)
            peak = max(peak, bytes.count)
            failure = nil
        }
        let completion = failure.flatMap { finishLocked(.failure(ResponseLimitedHTTPTransportFailure.outcomeUnknown($0))) }
        lock.unlock()
        completion?.deliver()
    }

    func denyRedirect() {
        lock.lock()
        let completion = finishLocked(.failure(ResponseLimitedHTTPTransportFailure.outcomeUnknown(.redirectDenied)))
        lock.unlock()
        completion?.deliver()
    }

    func complete(error: Error?) {
        lock.lock()
        let result: Result<(Data, Int), Error>
        if let error {
            let failure: ResponseLimitedHTTPTransportFailure.Reason =
                (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
                ? .cancelled : .network
            result = .failure(ResponseLimitedHTTPTransportFailure.outcomeUnknown(failure))
        } else if let status { result = .success((bytes, status)) }
        else { result = .failure(ResponseLimitedHTTPTransportFailure.outcomeUnknown(.invalidResponse)) }
        let completion = finishLocked(result)
        lock.unlock()
        completion?.deliver()
    }

    private struct Completion {
        let continuation: CheckedContinuation<(Data, Int), Error>?
        let task: (any ResponseLimitedHTTPTask)?
        let result: Result<(Data, Int), Error>
        func deliver() { task?.invalidateAndCancel(); continuation?.resume(with: result) }
    }

    /// Requires the lock. Release it before cancellation or continuation callbacks.
    private func finishLocked(_ result: Result<(Data, Int), Error>) -> Completion? {
        guard !finished else { return nil }
        finished = true
        let completion = Completion(continuation: continuation, task: task, result: result)
        continuation = nil
        task = nil
        bytes = Data()
        return completion
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(receive(response) ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { receive(data) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { complete(error: error) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not return even a same-origin replacement request: the upload cannot replay.
        completionHandler(nil)
        denyRedirect()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                    completionHandler: @escaping (CachedURLResponse?) -> Void) { completionHandler(nil) }
}
