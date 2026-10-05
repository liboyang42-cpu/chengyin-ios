import Foundation

/// Presentation scope only. Neither the selected view nor a locality grants merchant access.
/// The access revision fences an owner/operator merchant switch even within one login epoch.
public struct ClubDiscoveryScope: Hashable {
    public let identity: ClubReadIdentity
    public let role: String?
    public let viewerRevision: UInt64
    public let merchantID: Int?
    public let merchantRevision: UInt64
    public init(identity: ClubReadIdentity, role: String? = nil, viewerRevision: UInt64 = 0,
                merchantID: Int? = nil, merchantRevision: UInt64 = 0) {
        self.identity = identity; self.role = role; self.viewerRevision = viewerRevision
        self.merchantID = merchantID; self.merchantRevision = merchantRevision
    }
    public var isMerchantViewer: Bool { identity.isSignedIn && role == "merchant" }
}

/// Narrow projection of the existing token-scoped merchant/info response. Unknown or
/// malformed locality stays unknown; it is never inferred from coordinates or geocoding.
public struct MerchantClubLocality: Decodable, Equatable {
    public let merchantID: Int
    public let value: String?
    enum CodingKeys: String, CodingKey { case id, city, address }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), id > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Invalid merchant identity")
        }
        merchantID = id
        let city = (try? c.decode(String.self, forKey: .city))?.trimmingCharacters(in: Self.sourceWhitespace)
        let address = (try? c.decode(String.self, forKey: .address))?.trimmingCharacters(in: Self.sourceWhitespace)
        value = city.flatMap { $0.isEmpty ? nil : $0 } ?? address.flatMap { $0.isEmpty ? nil : $0 }
    }
    // ECMAScript trim's whitespace/line terminators, including BOM but excluding NEL.
    // Locale-aware normalization would change the mini client's literal matching contract.
    private static let sourceWhitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000B}\u{000C}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}\u{FEFF}\u{000A}\u{000D}\u{2028}\u{2029}")
    /// Match the source's case-sensitive city-or-address substring exactly for decoded strings.
    /// A nonempty club city wins over its address, even if that city contains only whitespace.
    public func matches(_ club: ClubRecord) -> Bool {
        guard let value else { return true }
        let city = club.city.flatMap { $0.isEmpty ? nil : $0 }
        let location = city ?? club.address ?? ""
        return !location.isEmpty && (location.range(of: value, options: .literal) != nil || city.map { value.range(of: $0, options: .literal) != nil } == true)
    }
}

/// A per-view value state machine. Every retry starts a new generation; disappearing
/// invalidates pending completions without destroying already-visible source navigation.
public struct MerchantClubDiscoveryState {
    public enum Phase: Equatable { case idle, loading, ready, unavailable }
    public struct Request: Equatable {
        fileprivate let generation: UInt64
        fileprivate let scope: ClubDiscoveryScope
    }
    private var generation: UInt64 = 0
    private var scope: ClubDiscoveryScope?
    private var phase: Phase = .idle
    private var locality: MerchantClubLocality?
    public init() {}
    public func phase(in current: ClubDiscoveryScope) -> Phase { scope == current ? phase : .idle }
    public func nearby(_ rows: [ClubRecord], in current: ClubDiscoveryScope) -> [ClubRecord] {
        guard current.isMerchantViewer, scope == current, phase == .ready, let locality else { return rows }
        return rows.filter(locality.matches)
    }
    public mutating func begin(in current: ClubDiscoveryScope) -> Request? {
        generation &+= 1; scope = current; locality = nil
        guard current.isMerchantViewer else { phase = .idle; return nil }
        phase = .loading
        return Request(generation: generation, scope: current)
    }
    @discardableResult
    public mutating func receive(_ result: MerchantClubLocality, for request: Request, current: ClubDiscoveryScope) -> Bool {
        guard accepts(request, current: current) else { return false }
        guard result.value != nil, current.merchantID == nil || current.merchantID == result.merchantID else {
            locality = nil; phase = .unavailable; return true
        }
        locality = result; phase = .ready; return true
    }
    @discardableResult
    public mutating func fail(_ request: Request, current: ClubDiscoveryScope) -> Bool {
        guard accepts(request, current: current) else { return false }
        locality = nil; phase = .unavailable; return true
    }
    public mutating func leaveScreen() {
        generation &+= 1
        if phase == .loading { locality = nil; phase = .idle }
    }
    private func accepts(_ request: Request, current: ClubDiscoveryScope) -> Bool {
        request.generation == generation && request.scope == scope && scope == current && current.isMerchantViewer
    }
}
