import Foundation
import Observation

public struct PlatformMapDestination: Equatable, Sendable {
    public let name: String
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public init(name: String, address: String? = nil, latitude: Double?, longitude: Double?) {
        self.name = name; self.address = address; self.latitude = latitude; self.longitude = longitude
    }
    public var hasCoordinates: Bool {
        guard let latitude, let longitude else { return false }
        // Preserve source's zero sentinel (either axis); additionally reject out-of-range values.
        return latitude.isFinite && longitude.isFinite && latitude != 0 && longitude != 0 && abs(latitude) <= 90 && abs(longitude) <= 180
    }
    public var copyText: String {
        let address = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name + " " + (address.isEmpty ? "\(latitude.map { String($0) } ?? "") , \(longitude.map { String($0) } ?? "")" : address)
    }
}
public enum PlatformMapState: Equatable { case gated, idle, opening, opened, noCoordinates, copied, launchFailed, copyFailed }
@MainActor public protocol PlatformMapOpening { func open(_ destination: PlatformMapDestination) async -> Bool }
@MainActor public protocol PlatformAddressCopying { func copy(_ text: String) throws }
@MainActor @Observable public final class PlatformExternalMaps {
    public private(set) var state: PlatformMapState = .gated
    public private(set) var selected: PlatformMapDestination?
    private let opener: any PlatformMapOpening
    private let copier: any PlatformAddressCopying
    private let enabled: Bool
    private var generation = 0
    public init(opener: any PlatformMapOpening, copier: any PlatformAddressCopying, enabled: Bool = false) {
        self.opener = opener; self.copier = copier; self.enabled = enabled
    }
    public func select(_ destination: PlatformMapDestination?) { generation += 1; selected = destination; state = enabled ? .idle : .gated }
    /// Only call after the user confirms this selected destination will be sent to Apple Maps.
    public func openReviewedDestination(_ destination: PlatformMapDestination) async {
        guard enabled, selected == destination, state != .opening else { return }
        guard destination.hasCoordinates else { state = .noCoordinates; return }
        generation += 1; let token = generation; state = .opening
        let opened = await opener.open(destination)
        guard token == generation, selected == destination else { return }
        state = opened ? .opened : .launchFailed
        // Copy is a separate explicit action: no silent clipboard mutation.
    }
    public func copySelectedAddress() {
        guard enabled, let selected else { return }
        do { try copier.copy(selected.copyText); state = .copied } catch { state = .copyFailed }
    }
    public func invalidate() { generation += 1; selected = nil; state = enabled ? .idle : .gated }
}
@MainActor public final class SyntheticPlatformMapAdapter: PlatformMapOpening, PlatformAddressCopying {
    public var result = false
    public var failCopy = false
    public private(set) var opened: [PlatformMapDestination] = []
    public private(set) var copied: [String] = []
    public init() {}
    public func open(_ destination: PlatformMapDestination) async -> Bool { opened.append(destination); return result }
    public func copy(_ text: String) throws { if failCopy { throw CocoaError(.fileWriteUnknown) }; copied.append(text) }
}
