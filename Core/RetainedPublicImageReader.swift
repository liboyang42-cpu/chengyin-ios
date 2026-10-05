import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Anonymous media bytes only; callers supply URLs from the current public-review snapshot.
/// No URL text-entry UI, cookies, Authorization header or cross-domain IM identity.
@MainActor public protocol RetainedPublicImageReading {
    var enabled: Bool { get }
    func image(url: URL) async throws -> Data
}
@MainActor public struct RetainedPublicImageReader: RetainedPublicImageReading {
    public let enabled: Bool
    private let origins: Set<String>
    public init(enabled: Bool = false, origins: Set<String> = []) { self.enabled = enabled; self.origins = origins }
    public func image(url: URL) async throws -> Data {
        guard enabled, RetainedImageOrigin.accepts(url, origins: origins) else { throw RetainedImageFailure.disabled }
        let loader = RetainedBoundedImageDownload()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await loader.load(url)
        }, onCancel: { loader.cancel() })
    }
}
/// A fresh ephemeral no-redirect download, rejecting headers/chunks over the selected-image bound.
/// Serial delegate callbacks and a lock protect cancellation before continuation installation.
private final class RetainedBoundedImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var bytes = Data()
    private var finished = false
    func load(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if finished { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForResource = 20
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            self.session = session
            var request = URLRequest(url: url); request.httpShouldHandleCookies = false
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let task = session.dataTask(with: request); self.task = task
            lock.unlock(); task.resume()
        }
    }
    func cancel() { complete(.failure(CancellationError())) }
    private func complete(_ result: Result<Data, Error>) {
        lock.lock(); guard !finished else { lock.unlock(); return }
        finished = true; let continuation = continuation; self.continuation = nil
        let session = session; self.session = nil; task = nil; bytes = Data(); lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); complete(.failure(RetainedImageFailure.invalid))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.expectedContentLength <= Int64(RetainedSelectedImage.maximumInputBytes),
              response.mimeType?.hasPrefix("image/") == true else {
            completionHandler(.cancel); complete(.failure(RetainedImageFailure.invalid)); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= RetainedSelectedImage.maximumInputBytes - bytes.count else {
            lock.unlock(); complete(.failure(RetainedImageFailure.invalid)); return
        }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let data = bytes; lock.unlock()
        if let error { complete(.failure(error)) }
        else if data.isEmpty { complete(.failure(RetainedImageFailure.invalid)) }
        else { complete(.success(data)) }
    }
}
