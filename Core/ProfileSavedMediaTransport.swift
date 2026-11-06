import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public protocol ProfileSavedMediaDispatching: AnyObject {
    func send(_ request: URLRequest, authorization: ProfileSavedMediaReadAuthorization) async throws -> Data
}
/// Prepared exact anonymous request. A paused old read cannot begin after its source or view retires.
@MainActor public final class ProfileSavedMediaReadAuthorization {
    private let expected: URLRequest, current: () -> Bool
    private var invalidated = false
    private var cancellation: (() -> Void)?
    public private(set) var didForward = false
    init(expected: URLRequest, current: @escaping () -> Bool) { self.expected = expected; self.current = current }
    public var isCurrent: Bool { !invalidated && !Task.isCancelled && current() }
    public func accepts(_ request: URLRequest) -> Bool {
        request.url?.absoluteString.utf8.elementsEqual(expected.url!.absoluteString.utf8) == true
            && request.httpMethod == "GET" && request.httpBody == nil && request.httpBodyStream == nil
            && !request.httpShouldHandleCookies && request.cachePolicy == .reloadIgnoringLocalCacheData
            && request.allHTTPHeaderFields == expected.allHTTPHeaderFields
            && request.value(forHTTPHeaderField: "Authorization") == nil && request.value(forHTTPHeaderField: "Cookie") == nil
    }
    public func forward(_ request: URLRequest, cancel: @escaping () -> Void, dispatch: () throws -> Void) throws {
        guard !didForward, accepts(request), isCurrent else { throw RetainedImageFailure.disabled }
        didForward = true; cancellation = cancel
        try dispatch()
    }
    public func invalidate() {
        invalidated = true; let cancel = cancellation; cancellation = nil; cancel?()
    }
}

@MainActor public final class ProfileSavedMediaURLSessionTransport: ProfileSavedMediaDispatching {
    public init() {}
    nonisolated static func acceptsResponse(_ response: HTTPURLResponse, endpoint: URL) -> Bool {
        guard (200..<300).contains(response.statusCode), response.expectedContentLength >= -1,
              response.expectedContentLength <= Int64(RetainedSelectedImage.maximumInputBytes),
              response.mimeType?.lowercased().hasPrefix("image/") == true,
              response.url?.absoluteString.utf8.elementsEqual(endpoint.absoluteString.utf8) == true,
              response.allHeaderFields.count <= 128 else { return false }
        var headerBytes = 0
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { return false }
            headerBytes += name.utf8.count + value.utf8.count
            if headerBytes > 32_768 { return false }
        }
        return true
    }
    public func send(_ request: URLRequest, authorization: ProfileSavedMediaReadAuthorization) async throws -> Data {
        guard authorization.accepts(request), authorization.isCurrent else { throw RetainedImageFailure.disabled }
        let exchange = ProfileSavedMediaExchange(endpoint: request.url!)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                exchange.install(continuation)
                do {
                    try authorization.forward(request, cancel: { exchange.fail(CancellationError()) }) { exchange.start(request) }
                } catch { exchange.fail(error) }
            }
        }, onCancel: { exchange.fail(CancellationError()) })
    }
}
/// Fresh per-image transport. No signing, ambient credentials, redirects, cache, persistence or retry.
private final class ProfileSavedMediaExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let endpoint: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var finished = false
    private var failure: Error?
    private var bytes = Data()
    init(endpoint: URL) { self.endpoint = endpoint }
    func install(_ value: CheckedContinuation<Data, Error>) {
        lock.lock()
        if finished { let error = failure ?? RetainedImageFailure.disabled; lock.unlock(); value.resume(throwing: error); return }
        continuation = value; lock.unlock()
    }
    func start(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 20
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session; session.dataTask(with: request).resume()
    }
    func fail(_ error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock(); guard !finished else { lock.unlock(); return }
        finished = true; if case .failure(let error) = result { failure = error }
        let completion = continuation, session = session; continuation = nil; self.session = nil; bytes = Data()
        lock.unlock(); session?.invalidateAndCancel(); completion?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); fail(RetainedImageFailure.invalid)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // System TLS trust only. Never supply user/server/proxy credentials.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil); fail(RetainedImageFailure.invalid) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              ProfileSavedMediaURLSessionTransport.acceptsResponse(response, endpoint: endpoint) else {
            completionHandler(.cancel); fail(RetainedImageFailure.invalid); return
        }
        lock.lock(); let live = !finished; lock.unlock(); completionHandler(live ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); guard !finished else { lock.unlock(); return }
        guard data.count <= RetainedSelectedImage.maximumInputBytes - bytes.count else {
            lock.unlock(); fail(RetainedImageFailure.invalid); return
        }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let data = bytes; lock.unlock()
        if let error { fail(error) }
        else if data.isEmpty { fail(RetainedImageFailure.invalid) }
        else { finish(.success(data)) }
    }
}
