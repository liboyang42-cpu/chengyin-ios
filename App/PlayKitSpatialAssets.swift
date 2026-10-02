import Foundation
import UIKit
import ImageIO

/// Approved media only: no account headers, cookies, credentials, persistent cache
/// or arbitrary redirects. Streaming limits bytes before buffering the entire asset.
@MainActor enum PlayKitSpatialAssets {
    static func loadImage(_ url: URL, approvedHosts: Set<String>) async throws -> UIImage {
        guard PlayKitCameraAssets.approvedURL(url.absoluteString, hosts: approvedHosts) != nil else { throw PlayKitSpatialError.assetUnavailable }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.httpShouldSetCookies = false; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let redirects = PlayKitSpatialRedirectGuard(hosts: approvedHosts)
        let session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.timeoutInterval = 20; request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (stream, response) = try await session.bytes(for: request)
        let maximum = 10 * 1024 * 1024
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, PlayKitCameraAssets.approvedURL(finalURL.absoluteString, hosts: approvedHosts) != nil,
              ["image/png", "image/jpeg", "image/webp"].contains(http.mimeType ?? ""),
              http.expectedContentLength <= Int64(maximum) else { throw PlayKitSpatialError.assetUnavailable }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < maximum else { throw PlayKitSpatialError.assetUnavailable }
            data.append(byte)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = metadata[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0, width.doubleValue <= 12_000, height.doubleValue <= 12_000,
              width.doubleValue * height.doubleValue <= 24_000_000 else { throw PlayKitSpatialError.assetUnavailable }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096]
        guard let normalized = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw PlayKitSpatialError.assetUnavailable }
        return UIImage(cgImage: normalized) // EXIF orientation applied; bounded texture, original aspect ratio.
    }
}
private final class PlayKitSpatialRedirectGuard: NSObject, URLSessionTaskDelegate {
    let hosts: Set<String>
    init(hosts: Set<String>) { self.hosts = hosts }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, PlayKitCameraAssets.approvedURL(url.absoluteString, hosts: hosts) != nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}
