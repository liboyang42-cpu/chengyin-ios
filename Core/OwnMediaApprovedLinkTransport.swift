import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public final class OwnMediaApprovedLinkTransport: OwnMediaApprovedLinkDispatching {
    public init() {}
    public func send(_ request: URLRequest, authorization: OwnMediaApprovedLinkAuthorization) async throws -> (Data, Int) {
        guard authorization.accepts(request), authorization.isCurrent else { throw OwnMediaApprovedLinkFailure.unavailable }
        let exchange = OwnMediaApprovedLinkExchange(endpoint: request.url!)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                exchange.install(continuation)
                do { try authorization.forward(request, cancel: { exchange.fail(CancellationError()) }) { exchange.start(request) } }
                catch { exchange.fail(error) }
            }
        }, onCancel: { exchange.fail(CancellationError()) })
    }
    nonisolated static func acceptsResponse(_ response: HTTPURLResponse, endpoint: URL) -> Bool {
        guard response.url?.absoluteString.utf8.elementsEqual(endpoint.absoluteString.utf8) == true,
              response.expectedContentLength >= -1, response.expectedContentLength <= 65_536,
              response.allHeaderFields.count <= 128 else { return false }
        var count = 0
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { return false }
            count += name.utf8.count + value.utf8.count; if count > 32_768 { return false }
        }
        return true // Classify original first-party status/errors in the metadata decoder.
    }
}
private final class OwnMediaApprovedLinkExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let endpoint: URL
    private let limit = 65_536
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private var session: URLSession?
    private var finished = false
    private var failure: Error?
    private var bytes = Data()
    private var status: Int?
    init(endpoint: URL) { self.endpoint = endpoint }
    func install(_ value: CheckedContinuation<(Data, Int), Error>) {
        lock.lock()
        if finished { let error = failure ?? OwnMediaApprovedLinkFailure.unavailable; lock.unlock(); value.resume(throwing: error); return }
        continuation = value; lock.unlock()
    }
    func start(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }; guard !finished else { return }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 20
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session; session.dataTask(with: request).resume()
    }
    func fail(_ error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<(Data, Int), Error>) {
        lock.lock(); guard !finished else { lock.unlock(); return }; finished = true
        if case .failure(let error) = result { failure = error }
        let completion = continuation, session = session; continuation = nil; self.session = nil; bytes = Data()
        lock.unlock(); session?.invalidateAndCancel(); completion?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); fail(OwnMediaApprovedLinkFailure.invalidResponse)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == "NSURLAuthenticationMethodServerTrust" { completionHandler(.performDefaultHandling, nil) }
        else { completionHandler(.cancelAuthenticationChallenge, nil); fail(OwnMediaApprovedLinkFailure.invalidResponse) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              OwnMediaApprovedLinkTransport.acceptsResponse(response, endpoint: endpoint) else {
            completionHandler(.cancel); fail(OwnMediaApprovedLinkFailure.invalidResponse); return
        }
        lock.lock(); status = response.statusCode; let live = !finished; lock.unlock(); completionHandler(live ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); guard !finished else { lock.unlock(); return }
        guard data.count <= limit - bytes.count else { lock.unlock(); fail(OwnMediaApprovedLinkFailure.invalidResponse); return }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let data = bytes, code = status; lock.unlock()
        if let error { fail(error) }
        else if let code { finish(.success((data, code))) }
        else { fail(OwnMediaApprovedLinkFailure.invalidResponse) }
    }
}
