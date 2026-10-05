import Foundation

public enum PlayKitSpatialMode: String, Hashable { case plane = "PLANE", marker = "MARKER" }
public enum PlayKitSpatialError: String, Error, Equatable {
    case disabled, unvalidatedScan, unsupportedMode, unsupportedModel, assetUnavailable, markerCalibrationRequired, permissionDenied, deviceUnavailable, interrupted
}
/// Operator-supplied acceptance, separate from server task data. No runtime
/// section can grant camera access, approve an origin or invent marker dimensions.
public struct PlayKitSpatialApproval: Equatable {
    public let modes: Set<PlayKitSpatialMode>
    public let artworkHosts: Set<String>
    public let modelHosts: Set<String>
    public let markerWidthsMeters: [String: Double]
    public init(modes: Set<PlayKitSpatialMode> = [], artworkHosts: Set<String> = [], modelHosts: Set<String> = [], markerWidthsMeters: [String: Double] = [:]) {
        self.modes = modes; self.artworkHosts = artworkHosts; self.modelHosts = modelHosts; self.markerWidthsMeters = markerWidthsMeters
    }
}
public struct PlayKitSpatialRequest: Equatable {
    public let mode: PlayKitSpatialMode
    public let imageURL: URL
    public let modelURL: URL?
    public let markerURL: URL?
    public let markerWidthMeters: Double?
    public let reply: String
    public init(segment: PlayWireValue, approval: PlayKitSpatialApproval) throws {
        guard segment["scanned"].bool == true, segment["kind"].text == "OVERLAY" else { throw PlayKitSpatialError.unvalidatedScan }
        guard let mode = PlayKitSpatialMode(rawValue: segment["arMode"].text ?? "NONE") else { throw PlayKitSpatialError.unsupportedMode }
        guard approval.modes.contains(mode) else { throw PlayKitSpatialError.disabled }
        let model = segment["modelUrl"].text ?? ""
        if model.isEmpty { modelURL = nil }
        else {
            guard let url = PlayKitGLBPolicy.approvedURL(model, hosts: approval.modelHosts) else { throw PlayKitSpatialError.unsupportedModel }
            modelURL = url
        }
        guard let image = PlayKitCameraAssets.approvedURL(segment["overlayUrl"].text, hosts: approval.artworkHosts) else { throw PlayKitSpatialError.assetUnavailable }
        self.mode = mode; imageURL = image; reply = segment["reply"].text ?? ""
        if mode == .marker {
            guard let marker = PlayKitCameraAssets.approvedURL(segment["markerUrl"].text, hosts: approval.artworkHosts) else { throw PlayKitSpatialError.assetUnavailable }
            guard let width = approval.markerWidthsMeters[marker.absoluteString], width.isFinite, width > 0, width <= 10 else { throw PlayKitSpatialError.markerCalibrationRequired }
            markerURL = marker; markerWidthMeters = width
        } else { markerURL = nil; markerWidthMeters = nil }
    }
    /// Source plane cards are 0.4 m wide. Marker cards use the accepted marker size.
    public var modelLongestSideMeters: Double { mode == .plane ? 0.4 : 0.8 * (markerWidthMeters ?? 0) }
    public var cardWidthMeters: Double { mode == .plane ? 0.4 : (markerWidthMeters ?? 0) }
    public func cardHeightMeters(imageWidth: Double, imageHeight: Double) throws -> Double {
        guard imageWidth.isFinite, imageHeight.isFinite, imageWidth > 0, imageHeight > 0 else { throw PlayKitSpatialError.assetUnavailable }
        return cardWidthMeters * imageHeight / imageWidth
    }
}
/// Pure display lifecycle, never evidence for arrival/completion. A marker locks
/// once in world space; losing image tracking cannot move or delete that placement.
public struct PlayKitSpatialPlacement: Equatable {
    public enum Phase: String { case searching, surfaceFound, placed, fallback }
    public private(set) var phase = Phase.searching
    public private(set) var placementCount = 0
    public init() {}
    public mutating func foundPlane() { if phase == .searching { phase = .surfaceFound } }
    public mutating func placeOnPlane(hasActualRaycast: Bool) -> Bool {
        guard hasActualRaycast, phase != .fallback else { return false }
        placementCount += 1; phase = .placed; return true
    }
    public mutating func lockMarker(hasActualAnchor: Bool) -> Bool {
        guard hasActualAnchor, placementCount == 0, phase != .fallback else { return false }
        placementCount = 1; phase = .placed; return true
    }
    public mutating func fail() { phase = .fallback }
}
