import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ObjectCardMediaFailure: Error { case disabled, invalidURL, unapprovedOrigin, invalidResponse, tooLarge, unsupportedImage }
/// Exact approved origins only. No credentials, cookies, caches, redirects or model downloads.
public struct ObjectCardMediaPolicy {
    public let approvedOrigins: Set<String>
    public static let maximumBytes = 12 * 1024 * 1024
    public init(approvedOrigins: Set<String>) { self.approvedOrigins = approvedOrigins }
    public static func origin(_ raw: String) -> String? {
        guard let c = URLComponents(string: raw), c.scheme?.lowercased() == "https",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.fragment == nil, !host.contains(":"), host.lowercased() != "localhost",
              !host.lowercased().hasSuffix(".local"), !host.split(separator: ".").allSatisfy({ Int($0) != nil }) else { return nil }
        return "https://\(host.lowercased())" + (c.port.map { $0 == 443 ? "" : ":\($0)" } ?? "")
    }
    public func validate(_ raw: String) throws -> URL {
        guard let origin = Self.origin(raw), let url = URL(string: raw) else { throw ObjectCardMediaFailure.invalidURL }
        guard approvedOrigins.contains(origin) else { throw ObjectCardMediaFailure.unapprovedOrigin }
        return url
    }
}
public protocol ObjectCardImageLoading {
    func image(url: String) async throws -> Data
}
public struct ObjectCardBoundedImageLoader: ObjectCardImageLoading {
    public let policy: ObjectCardMediaPolicy
    public init(policy: ObjectCardMediaPolicy) { self.policy = policy }
    public func image(url raw: String) async throws -> Data {
        let url = try policy.validate(raw)
        let operation = ObjectCardImageTransfer(url: url)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { operation.start($0) }
        }, onCancel: { operation.cancel() })
    }
}
private final class ObjectCardImageTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var bytes = Data()
    private var finished = false
    init(url: URL) { self.url = url }
    func start(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCache = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/png,image/jpeg,image/gif,image/webp", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)
        lock.unlock(); task.resume()
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation; self.continuation = nil
        let session = self.session; self.session = nil; bytes.removeAll()
        lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(ObjectCardMediaFailure.invalidResponse))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Permit platform TLS validation only. Never answer HTTP/proxy authentication.
        if challenge.protectionSpace.authenticationMethod == "NSURLAuthenticationMethodServerTrust" { completionHandler(.performDefaultHandling, nil) }
        else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.url == url,
              ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(response.mimeType?.lowercased() ?? "") else {
            completionHandler(.cancel); finish(.failure(ObjectCardMediaFailure.invalidResponse)); return
        }
        guard response.expectedContentLength <= Int64(ObjectCardMediaPolicy.maximumBytes) else {
            completionHandler(.cancel); finish(.failure(ObjectCardMediaFailure.tooLarge)); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= ObjectCardMediaPolicy.maximumBytes - bytes.count else {
            lock.unlock(); finish(.failure(ObjectCardMediaFailure.tooLarge)); return
        }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock(); let data = bytes; lock.unlock()
        let p = Array(data.prefix(12))
        let valid = p.starts(with: [137,80,78,71,13,10,26,10]) || p.starts(with: [255,216,255]) ||
            p.starts(with: Array("GIF87a".utf8)) || p.starts(with: Array("GIF89a".utf8)) ||
            (p.count == 12 && Array(p[0..<4]) == Array("RIFF".utf8) && Array(p[8..<12]) == Array("WEBP".utf8))
        finish(valid ? .success(data) : .failure(ObjectCardMediaFailure.unsupportedImage))
    }
}
