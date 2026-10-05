import Foundation
import ImageIO
import SceneKit
import GLTFKit2

@MainActor protocol PlayKitGLBDataLoading {
    func load(_ url: URL, approvedHosts: Set<String>) async throws -> Data
}
@MainActor protocol PlayKitGLBSceneDecoding {
    func scene(from data: Data) async throws -> SCNScene
}

/// A separate ephemeral media session. Never shares API credentials, cookies,
/// cached bytes or account headers. Cross-origin and same-origin redirects are
/// both rejected: the exact approved asset must itself return the GLB.
@MainActor struct PlayKitGLBDownloader: PlayKitGLBDataLoading {
    func load(_ url: URL, approvedHosts: Set<String>) async throws -> Data {
        guard PlayKitGLBPolicy.approvedURL(url.absoluteString, hosts: approvedHosts) != nil else { throw PlayKitSpatialError.assetUnavailable }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.httpShouldSetCookies = false; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = PlayKitGLBPolicy.timeoutSeconds
        configuration.timeoutIntervalForResource = PlayKitGLBPolicy.timeoutSeconds
        let session = URLSession(configuration: configuration, delegate: PlayKitGLBNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler(operation: {
            var request = URLRequest(url: url)
            request.timeoutInterval = PlayKitGLBPolicy.timeoutSeconds
            request.setValue("model/gltf-binary, application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let (stream, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url == url, ["model/gltf-binary", "application/octet-stream"].contains(http.mimeType ?? ""),
                  http.expectedContentLength <= Int64(PlayKitGLBPolicy.maximumBytes) else { throw PlayKitSpatialError.assetUnavailable }
            var data = Data()
            let deadline = ContinuousClock.now.advanced(by: .seconds(PlayKitGLBPolicy.timeoutSeconds))
            for try await byte in stream {
                try Task.checkCancellation()
                guard data.count < PlayKitGLBPolicy.maximumBytes, ContinuousClock.now < deadline else { throw PlayKitSpatialError.assetUnavailable }
                data.append(byte)
            }
            try Task.checkCancellation()
            return data
        }, onCancel: { session.invalidateAndCancel() })
    }
}
private final class PlayKitGLBNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor struct PlayKitGLBDecoder: PlayKitGLBSceneDecoding {
    func scene(from data: Data) async throws -> SCNScene {
        try Task.checkCancellation()
        let operation = PlayKitGLBDecodeOperation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in operation.start(data: data, continuation: continuation) }
        }, onCancel: { operation.cancel() })
    }
}

/// Validated local bytes are passed directly to GLTFKit2. No temp files or asset
/// directory grants exist; every URI/extension is rejected before native loading.
/// Cancellation/timeout resumes exactly once and tells GLTFKit2 to stop at its
/// next progress callback. Late results never reach the screen.
private final class PlayKitGLBDecodeOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SCNScene, Error>?
    private var ended = false
    private var timeout: DispatchWorkItem?
    func start(data: Data, continuation: CheckedContinuation<SCNScene, Error>) {
        lock.lock()
        if ended { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(PlayKitSpatialError.assetUnavailable)) }
        timeout = timer; lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + PlayKitGLBPolicy.timeoutSeconds, execute: timer)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let data = try PlayKitGLBPolicy.sanitizedData(data)
                let manifest = try PlayKitGLBPolicy.validate(data)
                try Self.validateTextures(data: data, manifest: manifest)
                guard !isEnded else { return }
                GLTFAsset.load(with: data, options: [:]) { [self] _, status, asset, error, stop in
                    if isEnded { stop.pointee = true; return }
                    if let error { finish(.failure(error)); return }
                    if status == .error { finish(.failure(PlayKitSpatialError.unsupportedModel)); return }
                    if status == .complete {
                        guard let asset, let scene = GLTFSCNSceneSource(asset: asset).defaultScene,
                              !scene.rootNode.childNodes.isEmpty else { finish(.failure(PlayKitSpatialError.unsupportedModel)); return }
                        finish(.success(scene))
                    }
                }
            } catch { finish(.failure(error)) }
        }
    }
    private var isEnded: Bool { lock.lock(); defer { lock.unlock() }; return ended }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<SCNScene, Error>) {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        ended = true; let waiter = continuation; continuation = nil
        let timer = timeout; timeout = nil; lock.unlock()
        timer?.cancel(); waiter?.resume(with: result)
    }
    private static func validateTextures(data: Data, manifest: PlayKitGLBPolicy.Manifest) throws {
        var totalPixels = 0.0
        for range in manifest.imageRanges {
            guard let source = CGImageSourceCreateWithData(data.subdata(in: range) as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) == 1,
                  let type = CGImageSourceGetType(source) as String?, ["public.png", "public.jpeg"].contains(type),
                  let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = metadata[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = metadata[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0, width.doubleValue <= 4096, height.doubleValue <= 4096 else { throw PlayKitSpatialError.unsupportedModel }
            totalPixels += width.doubleValue * height.doubleValue
            guard totalPixels <= 16_777_216 else { throw PlayKitSpatialError.unsupportedModel }
        }
    }
}

@MainActor enum PlayKitGLBPreparation {
    static func load(_ url: URL, approvedHosts: Set<String>, downloader: (any PlayKitGLBDataLoading)? = nil,
                     decoder: (any PlayKitGLBSceneDecoding)? = nil) async throws -> SCNScene {
        try Task.checkCancellation()
        let downloader = downloader ?? PlayKitGLBDownloader()
        let decoder = decoder ?? PlayKitGLBDecoder()
        // Repeat the gate before invoking even an injected provider.
        guard PlayKitGLBPolicy.approvedURL(url.absoluteString, hosts: approvedHosts) != nil else { throw PlayKitSpatialError.assetUnavailable }
        let bytes = try await downloader.load(url, approvedHosts: approvedHosts)
        try Task.checkCancellation()
        _ = try PlayKitGLBPolicy.validate(bytes)
        let scene = try await decoder.scene(from: bytes)
        try Task.checkCancellation()
        return scene
    }
}
