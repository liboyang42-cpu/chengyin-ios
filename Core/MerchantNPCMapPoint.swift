import Foundation

/// The source `wx.chooseLocation` flow writes GCJ-02. This is a store display point,
/// never a device fix, arrival proof, or an approved MapKit rendering/conversion contract.
public struct MerchantNPCMapPoint: Decodable, Equatable {
    public let merchantID: Int
    public private(set) var latitude: String
    public private(set) var longitude: String
    public private(set) var address: String
    public let datum: WalkingCoordinateDatum
    private enum CodingKeys: String, CodingKey { case id, locationLat, locationLng, address }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), id > 0 else { throw APIError.malformedResponse }
        merchantID = id
        latitude = try Self.coordinateText(c, .locationLat)
        longitude = try Self.coordinateText(c, .locationLng)
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        // This declaration is specific to the source endpoint. It does not relabel
        // coordinates delivered by a native map, sensor, or an arbitrary provider.
        datum = .gcj02
    }
    private static func coordinateText(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String {
        if !c.contains(key) { return "" }
        if try c.decodeNil(forKey: key) { return "" }
        if let text = try? c.decode(String.self, forKey: key) { return text }
        return String(try c.decode(Double.self, forKey: key))
    }
    public var coordinate: RoamCoordinate? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lng = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return RoamCoordinate(latitude: lat, longitude: lng)
    }
    public var statusKey: String { coordinate == nil ? "merchantMapPoint.unset" : "merchantMapPoint.selected" }
    public var blocker: String? {
        if coordinate == nil { return "merchantMapPoint.invalidCoordinate" }
        if address.utf16.count > 255 { return "merchantMapPoint.addressLimit" }
        return nil
    }
    /// A human explicitly enters source-format coordinates. No GPS or provider output is
    /// converted or relabeled, and missing coordinates never receive a substitute.
    public func replacing(latitude: String, longitude: String, address: String,
                          confirmedDatum: WalkingCoordinateDatum?) throws -> Self {
        guard confirmedDatum == .gcj02 else { throw APIError.invalidRequest }
        var result = self
        result.latitude = latitude.trimmingCharacters(in: .whitespacesAndNewlines)
        result.longitude = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        result.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.blocker == nil, let point = result.coordinate else { throw APIError.invalidRequest }
        // Normalize only numeric representation so unchanged input does not become dirty.
        result.latitude = String(point.latitude); result.longitude = String(point.longitude)
        return result
    }
    public var fields: [String: Any] {
        get throws {
            guard blocker == nil, let coordinate else { throw APIError.invalidRequest }
            return ["locationLat": coordinate.latitude, "locationLng": coordinate.longitude, "address": address]
        }
    }
}

/// A read-only projection for the NPC entry/details screen. It owns no editable draft,
/// confirmation, journal mutation or save path. The ordinary editor remains separate.
@MainActor public final class MerchantNPCMapPointReadOnlyCoordinator {
    public let reader: any MerchantOperationsReading
    public private(set) var issue: MerchantOperationsIssue?
    public private(set) var isBusy = false
    public private(set) var loadedScope: UUID?
    private var savedPoint: MerchantNPCMapPoint?
    private var access: MerchantOperationsAccess?
    private var generation = 0
    public init(reader: any MerchantOperationsReading) { self.reader = reader }
    public var isCurrent: Bool { loadedScope == reader.scope && reader.isAuthenticated }
    public var point: MerchantNPCMapPoint? { isCurrent ? savedPoint : nil }
    public var hasPendingWrite: Bool { isCurrent && reader.hasPending(.npcMapPoint) }
    public var canOpenEditor: Bool {
        isCurrent && !isBusy && savedPoint != nil && access?.allows(.npcMapPoint) == true && !hasPendingWrite
    }
    public func invalidate() {
        generation += 1; savedPoint = nil; access = nil; issue = nil; loadedScope = nil; isBusy = false
    }
    public func load() async {
        guard !isBusy else { return }
        invalidate(); let operation = generation, scope = reader.scope
        guard reader.isConfigured else { loadedScope = scope; issue = .key("auth.notConfigured"); return }
        guard reader.isAuthenticated else { loadedScope = scope; issue = .key("merchant.operations.signedOut"); return }
        isBusy = true
        defer { if operation == generation { isBusy = false } }
        do {
            let initial = try await reader.access()
            guard accepts(operation, scope) else { return }
            guard initial.cooperationManage else { throw MerchantOperationsFailure.accessDenied }
            let document = try await reader.document(.npcMapPoint)
            guard accepts(operation, scope) else { return }
            guard case .draft(.npcMapPoint(let value)) = document,
                  value.merchantID == initial.identity.merchantID else { throw APIError.malformedResponse }
            // Recheck after the read so a same-session role downgrade never exposes an
            // editor based only on the permission snapshot from before the request.
            let latest = try await reader.access()
            guard accepts(operation, scope) else { return }
            guard latest.cooperationManage else { throw MerchantOperationsFailure.accessDenied }
            guard value.merchantID == latest.identity.merchantID else { throw APIError.malformedResponse }
            savedPoint = value; access = latest; loadedScope = scope
        } catch {
            guard accepts(operation, scope), !(error is CancellationError) else { return }
            loadedScope = scope; issue = .init(error)
        }
    }
    private func accepts(_ operation: Int, _ scope: UUID) -> Bool {
        !Task.isCancelled && operation == generation && scope == reader.scope && reader.isAuthenticated
    }
}
