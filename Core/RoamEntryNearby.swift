import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program pages/roam/index 开始漫游 tab: the 附近活动 peek reads `GET /api/roam/entry/nearby
/// {lat,lng,radius:3000}` (index.js `_loadEntryMap`). The server returns the same shape as the hangout
/// read (`data.items`, `data.radius`); hangout rows are retired and dropped like `kind !== 'hangout'`.
/// The centre is the manually chosen roam area, never device location.
public struct RoamEntryActivity: Decodable, Equatable, Identifiable {
    public let sourceID: Int
    public let kind: String
    public let title: String
    public let coverURL: String?
    public let topicID: Int?
    public let productType: Int?
    public let viewerHasTicket: Bool
    public let coordinate: RoamCoordinate?
    public let addressName: String?
    public let distance: Double?
    public let startDate: String?
    public let endDate: String?
    public var id: String { "\(kind)-\(sourceID)" }
    public var isSupported: Bool { sourceID > 0 && (kind == "activity" || kind == "topic") }
    /// A topic row is its own topic; an activity carries an optional linked topic.
    public var linkedTopicID: Int? { kind == "topic" ? sourceID : topicID.flatMap { $0 > 0 ? $0 : nil } }
    enum CodingKeys: String, CodingKey { case id, kind, name, title, picUrl, coverUrl, imgUrl, topicId, productType, viewerHasTicket, latitude, longitude, addressName, distance, startDate, endDate }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = c.roamInteger(.id) ?? 0
        kind = try c.roamText(.kind) ?? "hangout"
        title = try c.roamText(.name) ?? c.roamText(.title) ?? ""
        coverURL = try c.roamText(.picUrl) ?? c.roamText(.coverUrl) ?? c.roamText(.imgUrl)
        topicID = c.roamInteger(.topicId)
        productType = c.roamInteger(.productType)
        if let flag = try? c.decode(Bool.self, forKey: .viewerHasTicket) { viewerHasTicket = flag }
        else { viewerHasTicket = (c.roamInteger(.viewerHasTicket) ?? 0) > 0 }
        coordinate = c.roamCoordinate(latitude: .latitude, longitude: .longitude)
        addressName = try c.roamText(.addressName)
        distance = c.roamNumber(.distance).flatMap { $0 >= 0 ? $0 : nil }
        startDate = try c.roamText(.startDate); endDate = try c.roamText(.endDate)
    }
}

public enum RoamEntryNearbyRoute {
    public static let path = "api/roam/entry/nearby"
    /// Fixed by the source; the peek offers no radius control.
    public static let radius = 3000
    public static let maximumItems = 200
    public static func request(baseURL: URL, area: RoamSearchArea, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        guard var parts = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        parts.queryItems = [URLQueryItem(name: "lat", value: String(area.coordinate.latitude)),
                            URLQueryItem(name: "lng", value: String(area.coordinate.longitude)),
                            URLQueryItem(name: "radius", value: String(radius))]
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    /// Strict envelope: `code` 200, `data.items` a list of at most 200 rows, echoed radius, unique visible ids.
    public static func decode(_ data: Data, status: Int) throws -> [RoamEntryActivity] {
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        struct Status: Decodable { let code: Int }
        struct Payload: Decodable { let items: [RoamEntryActivity]; let radius: Int }
        struct Envelope: Decodable { let data: Payload }
        guard let envelope = try? JSONDecoder().decode(Status.self, from: data) else { throw APIError.malformedResponse }
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        guard let payload = try? JSONDecoder().decode(Envelope.self, from: data).data,
              payload.radius == radius, payload.items.count <= maximumItems else { throw APIError.malformedResponse }
        let visible = payload.items.filter(\.isSupported)
        guard Set(visible.map(\.id)).count == visible.count else { throw APIError.malformedResponse }
        return visible
    }
}

/// Mini-program `utils/roam-entry-map.js` `activityView`, minus remote faces and 现场动态 (the entry
/// payload carries no post images). Teams come from a separate `team/nearby` read at the same centre.
public struct RoamEntryActivityCard: Equatable, Identifiable {
    public struct Team: Equatable, Identifiable {
        public let teamID: NearbyTeamID
        public let title: String
        public let joinedCount: Int
        public let maxMembers: Int
        public let canApply: Bool
        public var id: NearbyTeamID { teamID }
    }
    public let activity: RoamEntryActivity
    public let ended: Bool
    public let registered: Bool
    public let participantCount: Int
    public let recruitingCount: Int
    public let teams: [Team]
    public var id: String { activity.id }
    public var isFreeExplore: Bool { activity.productType == 2 }
    public var tagKey: String { isFreeExplore ? "roam.w208.entry.tag.free" : "roam.w208.entry.tag.city" }
    public init(activity: RoamEntryActivity, teams: [NearbyTeam], now: Date = Date(), timeZone: TimeZone = TimeZone(secondsFromGMT: 8 * 3600)!) {
        self.activity = activity
        let start = Self.date(activity.startDate, timeZone: timeZone), end = Self.date(activity.endDate, timeZone: timeZone)
        // ActivityLifecycle.timeBucket: past its end and not before its start.
        ended = activity.kind == "activity" && end.map { now > $0 } == true && !(start.map { now < $0 } == true)
        let topic = activity.linkedTopicID
        let linked = teams.filter { team in
            (topic != nil && team.topicID == topic) || (activity.kind == "activity" && team.activityID == activity.sourceID)
        }
        participantCount = linked.reduce(0) { $0 + $1.joinedCount }
        registered = activity.viewerHasTicket || linked.contains { $0.viewerHasTicket }
        recruitingCount = linked.count
        self.teams = (ended ? [] : linked).prefix(2).map {
            Team(teamID: $0.teamID, title: $0.title, joinedCount: $0.joinedCount, maxMembers: $0.maxMembers, canApply: $0.viewerHasTicket)
        }
    }
    /// Kilometres with one decimal, as `H.fmtKm`; nil when the server gave no distance.
    public var distanceKilometers: Double? { activity.distance.map { ($0 / 100).rounded() / 10 } }
    /// Primary action: 去报名 until registered; 查看详情 once ended. Registered and open shows only 发起组队.
    public var primaryKey: String? {
        if ended { return "roam.w208.entry.viewDetail" }
        return registered ? nil : "roam.w208.entry.register"
    }
    public var destination: RoamEventDestination? {
        if let topic = activity.linkedTopicID { return .topic(topic) }
        return activity.kind == "activity" ? .activity(activity.sourceID) : nil
    }
    public var liveMomentFeedState: RoamLiveMomentFeedState { .hiddenWhenEmpty }
    static func date(_ text: String?, timeZone: TimeZone) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return NearbyServerTime.text(text).date(timeZone: timeZone)
    }
}

/// Presentation state for the 现场动态 section in `pages/roam/index`.
/// Filters valid `https` moment image URLs without credentials and collapses to `.hiddenWhenEmpty`
/// when the entry payload carries no moments.
public enum RoamLiveMomentFeedState: Equatable, Sendable {
    case hiddenWhenEmpty
    case moments([String])

    public init(_ rawURLs: [String?]? = nil) {
        self = Self.resolve(rawURLs)
    }

    public init(urls: [String]) {
        self = Self.resolve(urls)
    }

    public static func resolve(_ rawURLs: [String?]?) -> Self {
        guard let rawURLs else { return .hiddenWhenEmpty }
        return resolve(rawURLs.compactMap { $0 })
    }

    public static func resolve(_ rawURLs: [String]) -> Self {
        var valid: [String] = []
        for raw in rawURLs {
            guard let sanitized = sanitizeHTTPSMomentURL(raw), !valid.contains(sanitized) else { continue }
            valid.append(sanitized)
        }
        return valid.isEmpty ? .hiddenWhenEmpty : .moments(valid)
    }

    public var isHidden: Bool {
        if case .hiddenWhenEmpty = self { return true }
        return false
    }

    public var momentURLs: [String] {
        switch self {
        case .hiddenWhenEmpty: return []
        case .moments(let urls): return urls
        }
    }

    public static func sanitizeHTTPSMomentURL(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.url != nil else {
            return nil
        }
        return trimmed
    }
}

/// Distance prefix copy for nearby roam/team surfaces: manual area selection (`"距所选地点"`)
/// vs live device location (`"距当前位置"`).
public enum RoamNearbyDistanceCopy: Equatable, Sendable {
    public static let selectedAreaPrefix = "距所选地点"
    public static let currentLocationPrefix = "距当前位置"

    public static func prefix(usesManualArea: Bool = true) -> String {
        usesManualArea ? selectedAreaPrefix : currentLocationPrefix
    }

    public static func label(usesManualArea: Bool = true, distanceKilometers: Double? = nil) -> String {
        let base = prefix(usesManualArea: usesManualArea)
        guard let distanceKilometers, distanceKilometers >= 0 else { return base }
        return "\(base) \(String(format: "%.1f", distanceKilometers))km"
    }
}

/// Peek states in the source order: read access (login / denied) before error, cards, then empty.
public enum RoamEntryPeekState: Equatable {
    case unavailable, login, denied, loading, failed, empty, loaded([RoamEntryActivityCard])
    public init(error: Error) {
        switch error as? APIError {
        case .unauthorized?: self = .login
        case .httpStatus(403)?, .businessCode(403)?: self = .denied
        case .notConfigured?: self = .unavailable
        default: self = .failed
        }
    }
    public init(activities: [RoamEntryActivity], teams: [NearbyTeam], now: Date = Date()) {
        let cards = activities.map { RoamEntryActivityCard(activity: $0, teams: teams, now: now) }
        self = cards.isEmpty ? .empty : .loaded(cards)
    }
}

@MainActor public protocol RoamEntryNearbyReading: AnyObject {
    var isConfigured: Bool { get }
    var isSignedIn: Bool { get }
    var isOfflineExample: Bool { get }
    var searchArea: RoamSearchArea? { get }
    /// Changes whenever account, approval or area change; views key their reads on it.
    var readKey: String { get }
    func entryNearby() async throws -> [RoamEntryActivity]
}

/// Independent approval for the entry peek only. No membership, registration or write action.
@MainActor @Observable public final class RoamEntryNearbyReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              approval.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              approval.accountID == context.session.accountID,
              approval.paths == [RoamEntryNearbyRoute.path] else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

@MainActor public final class RoamEntryNearbyReader: RoamEntryNearbyReading {
    private let deployment: URL?
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let area: () -> ManualMapAreaSelection.Snapshot?
    private let selectAccess: (RuntimeDependencyContext) -> RoamEntryNearbyReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(configuration: APIConfiguration?, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, viewerRevision: @escaping () -> UInt64,
                area: @escaping () -> ManualMapAreaSelection.Snapshot?,
                access: @escaping (RuntimeDependencyContext) -> RoamEntryNearbyReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        deployment = configuration?.baseURL; self.transport = transport; self.current = current
        self.viewerRevision = viewerRevision; self.area = area; selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    private var currentAccess: RoamEntryNearbyReadAccess? {
        guard let context = current(), let access = selectAccess(context), access.matches(context),
              deployment?.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) == true else { return nil }
        return access
    }
    public var isConfigured: Bool { currentAccess != nil }
    public var isSignedIn: Bool { current() != nil }
    public var isOfflineExample: Bool { false }
    public var searchArea: RoamSearchArea? { area()?.area }
    public var readKey: String {
        let context = current()
        return "\(context?.session.accountID ?? 0):\(context?.session.epoch ?? 0):\(viewerRevision()):\(area()?.revision ?? 0):\(currentAccess?.revision.uuidString ?? "off")"
    }
    public func entryNearby() async throws -> [RoamEntryActivity] {
        try Task.checkCancellation()
        guard let context = current() else { throw APIError.unauthorized }
        guard let selected = currentAccess, let deployment else { throw APIError.notConfigured }
        guard let snapshot = area() else { throw RoamReadFailure.searchAreaRequired }
        let viewer = viewerRevision()
        func valid() -> Bool {
            guard !Task.isCancelled, let fresh = current(), ContentDraftContextFence.matches(context, fresh),
                  viewerRevision() == viewer, area() == snapshot else { return false }
            return currentAccess === selected
        }
        let request = try RoamEntryNearbyRoute.request(baseURL: deployment, area: snapshot.area, token: context.session.token)
        do {
            let (data, status) = try await transport.send(request)
            guard valid() else { throw CancellationError() }
            return try RoamEntryNearbyRoute.decode(data, status: status)
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(context) }
            throw error
        }
    }
}

/// Synthetic offline rows for previews and UI tests. Never a real place, price or reward.
@MainActor public final class RoamEntryNearbyFixtureReader: RoamEntryNearbyReading {
    public enum Scenario: String { case content, empty, failure, login, denied }
    public let scenario: Scenario
    public init(scenario: Scenario = .content) { self.scenario = scenario }
    public var isConfigured: Bool { true }
    public var isSignedIn: Bool { scenario != .login }
    public var isOfflineExample: Bool { true }
    public var searchArea: RoamSearchArea? { RoamCoordinate(latitude: 31.2304, longitude: 121.4737).map { RoamSearchArea(coordinate: $0, label: "Synthetic area") } }
    public var readKey: String { scenario.rawValue }
    public static let json = """
    {"code":200,"data":{"radius":3000,"items":[
      {"kind":"activity","id":901,"topicId":801,"productType":1,"name":"Synthetic city clues","picUrl":"","startDate":"2099-10-01 09:00:00","endDate":"2099-10-01 18:00:00","viewerHasTicket":0,"latitude":31.2304,"longitude":121.4737,"addressName":"Demo square","distance":1500},
      {"kind":"topic","id":802,"productType":2,"name":"Synthetic free explore","viewerHasTicket":1,"latitude":"31.2310","longitude":"121.4740","addressName":"Demo lane","distance":820},
      {"kind":"hangout","id":7,"title":"Retired hangout","latitude":31.23,"longitude":121.47}
    ]}}
    """
    public func entryNearby() async throws -> [RoamEntryActivity] {
        switch scenario {
        case .login: throw APIError.unauthorized
        case .denied: throw APIError.httpStatus(403)
        case .failure: throw APIError.httpStatus(503)
        case .empty: return []
        case .content: return try RoamEntryNearbyRoute.decode(Data(Self.json.utf8), status: 200)
        }
    }
}
