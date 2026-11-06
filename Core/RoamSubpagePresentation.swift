import Foundation

/// Mini-program subpackageRoam presentation rules (history RunCard, session route name,
/// POI node card, city voucher copy, city stamp slip). Pure projections of already-read facts:
/// nothing here reads location, writes, or invents a value the record does not contain.

/// `scene-roam-history` RunCard. Unknown values stay unknown ("—"), except the source's
/// documented distance fallback (UI-04: an unread distance renders 0 on the card).
public struct RoamRunCardPresentation: Equatable {
    public enum Title: Equatable { case zone(String), city }
    public let title: Title
    /// `M/D/YY` in the device calendar, or nil when the timestamp is unusable (日期不可用).
    public let dateShort: String?
    public let distanceText: String
    public let shopsText: String
    public let timeText: String
    public let stamps: Int
    public let medals: [String]
    public init(_ record: RoamHistoryRecord, calendar: Calendar = .current) {
        title = record.meaningfulZone.map(Title.zone) ?? .city
        if let date = record.recordedAt {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            if let year = parts.year, let month = parts.month, let day = parts.day {
                dateShort = "\(month)/\(day)/" + String(String(year).suffix(2))
            } else { dateShort = nil }
        } else { dateShort = nil }
        distanceText = record.distance.map(Self.number) ?? "0"
        shopsText = record.shops.map(String.init) ?? "—"
        timeText = record.durationText ?? "—"
        stamps = record.photos.count
        medals = [record.medal, record.shopMedalName].compactMap { $0 }.filter { !$0.isEmpty }
    }
    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// `scene-roam-history` summary strip: `{n}次漫游 · {km}公里 · 探{n}家`. A single unknown
/// distance or shop count makes that total unknown ("—"), never a partial sum.
public struct RoamHistoryStripSummary: Equatable {
    public let trips: Int
    public let kilometersText: String
    public let shopsText: String
    public init(_ records: [RoamHistoryRecord]) {
        trips = records.count
        if records.allSatisfy({ $0.distance != nil }) {
            kilometersText = String(format: "%.1f", records.compactMap(\.distance).reduce(0, +))
        } else { kilometersText = "—" }
        shopsText = records.allSatisfy({ $0.shops != nil }) ? String(records.compactMap(\.shops).reduce(0, +)) : "—"
    }
}

/// `subpackageRoam/session` `routeName` (index.js `_setSessionView`). The placeholder zone
/// 这片街区 is never presented as a real route name.
public enum RoamSessionRouteName: Equatable {
    case zone(String)
    case places(first: String, count: Int)
    case place(String)
    case date(month: Int, day: Int)
    case generic
    public init(_ record: RoamHistoryRecord, calendar: Calendar = .current) {
        if let zone = record.meaningfulZone { self = .zone(zone); return }
        let names = record.pois.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if names.count > 1 { self = .places(first: names[0], count: names.count); return }
        if let only = names.first { self = .place(only); return }
        if let date = record.recordedAt {
            let parts = calendar.dateComponents([.month, .day], from: date)
            if let month = parts.month, let day = parts.day { self = .date(month: month, day: day); return }
        }
        self = .generic
    }
}

/// Anonymous receiver read of a friend's shared footprint (`GET api/roam/share/snapshot?token=`).
/// The token is a random 32-hex capability; anything else is "gone" without a request.
public struct RoamShareToken: Equatable {
    public let value: String
    public init?(_ raw: String) {
        guard raw.utf8.count == 32, raw.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        value = raw
    }
    /// Exact source request: GET, single `token` query item, no credential or cookie.
    public func request(baseURL: URL) throws -> URLRequest {
        guard var parts = URLComponents(url: baseURL.appendingPathComponent(RoamShareSnapshot.path), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        parts.queryItems = [URLQueryItem(name: "token", value: value)]
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// Validates a 32-hex `shareToken` query parameter for `subpackageRoam/session`,
/// normalizing valid hex tokens to lowercase `NormalizedToken` or returning `.invalidToken`
/// with copy `"分享链接无效或已过期"`.
public enum RoamShareTokenValidator: Equatable, Sendable {
    public static let invalidTokenMessage = "分享链接无效或已过期"

    public struct NormalizedToken: Equatable, Sendable {
        public let rawValue: String
        public var value: String { rawValue }
        public var shareToken: RoamShareToken? { RoamShareToken(rawValue) }

        public init?(_ raw: String?) {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  let token = RoamShareToken(trimmed) else {
                return nil
            }
            self.rawValue = token.value
        }
    }

    case normalized(NormalizedToken)
    case invalidToken

    public init(_ raw: String?) {
        self = Self.validate(raw)
    }

    public init(url: URL) {
        self = Self.validate(url: url)
    }

    public static func validate(_ raw: String?) -> Self {
        guard let token = NormalizedToken(raw) else { return .invalidToken }
        return .normalized(token)
    }

    public static func validate(url: URL) -> Self {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            return .invalidToken
        }
        return validate(queryItems: items)
    }

    public static func validate(queryItems: [URLQueryItem]) -> Self {
        let matching = queryItems.filter { $0.name == "shareToken" || $0.name == "token" }
        guard matching.count == 1 else { return .invalidToken }
        return validate(matching[0].value)
    }

    public var normalizedToken: NormalizedToken? {
        if case .normalized(let token) = self { return token }
        return nil
    }

    public var errorMessage: String? {
        if case .invalidToken = self { return Self.invalidTokenMessage }
        return nil
    }
}

/// Server-normalized snapshot (ApiRoamShareController/RoamSharePrivacyService): time to the hour,
/// coordinates already coarse. Optional numbers stay optional; a malformed shape is "gone".
public struct RoamShareSnapshot: Decodable, Equatable {
    public static let path = "api/roam/share/snapshot"
    public struct Point: Decodable, Equatable { public let lat: Double; public let lng: Double }
    public struct Place: Decodable, Equatable {
        public let name: String
        public let cat: String
        public let catLabel: String
        public let lat: Double?
        public let lng: Double?
    }
    public let ts: Int64
    public let routeName: String
    public let time: String
    public let distance: Double?
    public let explorePct: Double?
    public let shops: Int?
    public let medal: String
    public let shopMedalName: String
    public let track: [Point]
    public let pois: [Place]
    enum CodingKeys: String, CodingKey { case ts, routeName, time, distance, explorePct, shops, medal, shopMedalName, track, pois }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decode(Int64.self, forKey: .ts)
        let name = try c.decodeIfPresent(String.self, forKey: .routeName) ?? ""
        routeName = name.isEmpty ? "城市漫游足迹" : name
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? "—"
        distance = try c.decodeIfPresent(Double.self, forKey: .distance)
        explorePct = try c.decodeIfPresent(Double.self, forKey: .explorePct)
        shops = try c.decodeIfPresent(Int.self, forKey: .shops)
        medal = try c.decodeIfPresent(String.self, forKey: .medal) ?? ""
        shopMedalName = try c.decodeIfPresent(String.self, forKey: .shopMedalName) ?? ""
        track = try c.decodeIfPresent([Point].self, forKey: .track) ?? []
        pois = try c.decodeIfPresent([Place].self, forKey: .pois) ?? []
        guard ts > 0, track.count <= 500, pois.count <= 50, (distance ?? 0) >= 0, (shops ?? 0) >= 0,
              (0...100).contains(explorePct ?? 0),
              track.allSatisfy({ abs($0.lat) <= 90 && abs($0.lng) <= 180 }) else { throw APIError.malformedResponse }
    }
}

public enum RoamShareSnapshotOutcome: Equatable {
    case ready(RoamShareSnapshot)
    /// The server explicitly said no (revoked, cleared, unknown token) or the body is unusable.
    case gone
    /// Not read (transport/gateway). Retry is meaningful.
    case error
    /// No reviewed reader exists for this market/session.
    case unavailable
    /// Mirrors `readShareSnapshot`: non-2xx is retryable, any non-200 envelope is gone.
    public static func resolve(data: Data, status: Int) -> Self {
        guard (200..<300).contains(status) else { return .error }
        struct Status: Decodable { let code: Int }
        struct Envelope: Decodable { let data: RoamShareSnapshot }
        guard let code = try? JSONDecoder().decode(Status.self, from: data).code, code == 200,
              let value = try? JSONDecoder().decode(Envelope.self, from: data).data else { return .gone }
        return .ready(value)
    }
}

@MainActor public protocol RoamShareSnapshotReading: AnyObject {
    func snapshot(_ token: RoamShareToken) async -> RoamShareSnapshotOutcome
}

/// Offline DEBUG reader. Production composition supplies no reader until the anonymous route is reviewed.
@MainActor public final class RoamShareSnapshotFixtureReader: RoamShareSnapshotReading {
    public static let readyToken = String(repeating: "0a", count: 16)
    public static let goneToken = String(repeating: "f1", count: 16)
    public static let readyBody = #"{"code":200,"data":{"ts":1760857200000,"routeName":"Demo lane footprints","time":"42:10","distance":2.4,"explorePct":18,"shops":3,"medal":"","shopMedalName":"","track":[{"lat":37.781,"lng":-122.421},{"lat":37.784,"lng":-122.418}],"pois":[{"name":"Demo cafe","cat":"merchant","catLabel":"Cafe"}]}}"#
    public init() {}
    public func snapshot(_ token: RoamShareToken) async -> RoamShareSnapshotOutcome {
        switch token.value {
        case Self.readyToken: return .resolve(data: Data(Self.readyBody.utf8), status: 200)
        case Self.goneToken: return .resolve(data: Data(#"{"code":500,"msg":"gone"}"#.utf8), status: 200)
        default: return .error
        }
    }
}

/// `scene-roam-poi-detail` node card. Labels follow `utils/validation-method-labels.js`.
public struct RoamPOINodePresentation: Equatable {
    public enum PrimaryAction: String, Equatable { case completed, showVoucher, unavailable, interact }
    /// Validation methods the mini-program can actually play (VALIDATION_METHODS).
    public static let playableMethods: Set<Int> = [1, 2, 3, 4, 5]
    public let validationKey: String
    public let grantsCoupon: Bool
    public let offline: Bool
    public let offlineKeepsVoucher: Bool
    public let primary: PrimaryAction
    public init(_ node: RoamNodeDetail) {
        if let method = node.validationMethod, (0...7).contains(method) {
            validationKey = "roamSub.w208.poi.method.\(method)"
        } else { validationKey = "roamSub.w208.poi.method.unknown" }
        grantsCoupon = (node.couponId ?? 0) > 0
        offline = node.status == 0
        offlineKeepsVoucher = offline && node.needRedeem
        let canInteract = node.canInteract ?? (node.status == 1 && node.validationMethod.map(Self.playableMethods.contains) == true)
        if node.completed { primary = .completed }
        else if node.needRedeem { primary = .showVoucher }
        else if !canInteract { primary = .unavailable }
        else { primary = .interact }
    }
    public var primaryKey: String { "roamSub.w208.poi.primary.\(primary.rawValue)" }
    /// 收费承接 / 免费承接 / 收费方式待确认.
    public static func chargeKey(_ chargeType: Int?) -> String {
        switch chargeType { case 1: return "roamSub.w208.poi.charge.paid"; case 0: return "roamSub.w208.poi.charge.free"; default: return "roamSub.w208.poi.charge.unknown" }
    }
}

/// `citynode-code` copy for the city voucher. Missing parameters are not a failed issue:
/// there is no retry for them.
public enum RoamCityVoucherCopy {
    public static func phaseKey(_ phase: VerificationCodeCoordinator.Phase) -> String? {
        switch phase {
        case .failed, .invalid: return "roamSub.w208.voucher.issueFailed"
        case .unavailable: return "roamSub.w208.voucher.unavailable"
        default: return nil
        }
    }
    public static func displayName(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// `citystamp` print slip. The serial and bar pattern are deterministic for one stamp id,
/// so the barcode is the serial's shape, not decoration.
public struct RoamStampSlip: Equatable {
    public struct Bar: Equatable { public let width: Int; public let gap: Int }
    public static let captionLimit = 30
    public let got: Bool
    public let reason: String?
    public let serial: String
    public let bars: [Bar]
    public let caption: String?
    public let pictureURL: String?
    public let leftAt: String?
    public init(_ receipt: RoamStampExchangeReceipt) {
        let stamp = receipt.exchanged ? receipt.stamp : nil
        got = stamp != nil
        let reasonText = receipt.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        reason = reasonText?.isEmpty == false ? reasonText : nil
        let number = stamp?.id ?? 0
        serial = Self.serial(number)
        bars = Self.bars(number)
        caption = stamp?.caption.flatMap { $0.isEmpty ? nil : $0 }
        pictureURL = stamp?.picUrl
        leftAt = stamp?.createTime.map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") }
    }
    public static func serial(_ id: Int) -> String { String(format: "NO. %04d", ((id % 10000) + 10000) % 10000) }
    /// Port of `barcodeOf`: 31-bit LCG seeded by the serial, 46 bars.
    public static func bars(_ id: Int) -> [Bar] {
        var state = Int64(77) &+ Int64(id) &* 31
        func next() -> Double {
            state = (state &* 1103515245 &+ 12345) & 0x7fffffff
            return Double(state) / Double(0x7fffffff)
        }
        let widths = [1, 1, 1, 2, 2, 3]
        return (0..<46).map { _ in
            let width = widths[min(5, Int(next() * 6))]
            return Bar(width: width, gap: 1 + min(1, Int(next() * 2)))
        }
    }
    /// 今日城市签 (sign, default) or 城市贴纸 (sticker).
    public static func titleKey(kind: String?) -> String { kind == "sticker" ? "roamSub.w208.stamp.title.sticker" : "roamSub.w208.stamp.title.sign" }
    /// `{M.DD}` date label used before the place name.
    public static func dateLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)." + String(format: "%02d", parts.day ?? 0)
    }
}
