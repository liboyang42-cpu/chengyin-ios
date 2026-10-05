import Foundation

/// A viewfinder aid only. It never enters the uploaded image or proves a task result.
public struct PlayKitPhotoFrame: Equatable {
    public let imageURL: URL
    public let opacity: Double
    public init?(source: String?, opacityPercent: Double?, approvedHosts: Set<String>) {
        guard let url = PlayKitCameraAssets.approvedURL(source, hosts: approvedHosts) else { return nil }
        imageURL = url
        let value = opacityPercent.flatMap { $0.isFinite ? $0 : nil } ?? 40
        opacity = min(100, max(0, value)) / 100
    }
}
/// The coordinator uses this optional extension when a configured native provider
/// supports framing. Other providers retain ordinary photo capture as the fallback.
@MainActor public protocol PlayKitFramedPhotoProviding: PlayDeviceProviding {
    func capturePhoto(frame: PlayKitPhotoFrame, context: PlayDeviceContext) async throws -> PlayDeviceOutput
}
@MainActor public protocol PlayKitPhotoLibraryProviding: PlayDeviceProviding {
    func captureLibraryPhoto(context: PlayDeviceContext) async throws -> PlayDeviceOutput
}
@MainActor public protocol PlayDevicePermissionStateProviding: AnyObject {
    var authorizationInFlight: Bool { get }
}
public enum PlayKitCameraAssets {
    public static func approvedURL(_ source: String?, hosts: Set<String>) -> URL? {
        guard let source, let parts = URLComponents(string: source), parts.scheme == "https",
              let host = parts.host?.lowercased(), hosts.map({ $0.lowercased() }).contains(host),
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              let url = parts.url else { return nil }
        return url
    }
}
public struct PlayKitScanOverlay: Equatable {
    public let imageURL: URL
    public let widthFraction: Double
    public let reply: String
    public let mode: String
    public init?(segment: PlayWireValue, approvedHosts: Set<String>) {
        // AR or camera visualization is downstream of authoritative QR validation.
        guard segment["scanned"].bool == true,
              let url = PlayKitCameraAssets.approvedURL(segment["overlayUrl"].text, hosts: approvedHosts) else { return nil }
        imageURL = url; reply = segment["reply"].text ?? ""; mode = segment["arMode"].text ?? "NONE"
        let scale = segment["overlayScale"].double ?? 60
        widthFraction = (scale.isFinite && scale > 0 ? min(100, max(20, scale)) : 60) / 100
    }
}
