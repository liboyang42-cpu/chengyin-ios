import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The mini-program self profile header (`cy-profile viewer=self`), mapped from
/// the signed-in `/api/user/info` branch. Missing counters are display zero, as
/// in the source; an unread balance stays nil so the UI never asserts 0.00.
public struct MemberIdentitySnapshot: Decodable, Equatable {
    public let id: Int?
    public let nickname: String
    public let avatar: String
    public let role: String
    public let levelID: Int?
    public let city: String
    public let friendCount: Int
    public let followCount: Int
    public let fansCount: Int
    /// All five source counters (follow, fans, topic, activity, like) were numeric.
    public let countersReady: Bool
    public let balanceText: String?
    public let joinDate: String?
    public let introduction: String
    public let interests: [String]
    public let casePictures: [String]

    enum CodingKeys: String, CodingKey {
        case id, nickname, nickName, avatar, role, levelId, city, friendNum, followNum, fansNum
        case topicNum, activityNum, likeNum, balance, createTime, introduction, sysCategoryList, casePics
    }
    private struct Category: Decodable { let categoryName: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.integer(c, .id)
        nickname = Self.text(c, .nickname) ?? Self.text(c, .nickName) ?? ""
        avatar = Self.text(c, .avatar) ?? ""
        role = Self.text(c, .role) ?? ""
        levelID = Self.integer(c, .levelId)
        city = Self.text(c, .city) ?? ""
        let follow = Self.metric(c, .followNum), fans = Self.metric(c, .fansNum), friend = Self.metric(c, .friendNum)
        friendCount = friend ?? 0; followCount = follow ?? 0; fansCount = fans ?? 0
        countersReady = [follow, fans, Self.metric(c, .topicNum), Self.metric(c, .activityNum), Self.metric(c, .likeNum)]
            .allSatisfy { $0 != nil }
        balanceText = Self.balance(c)
        joinDate = Self.text(c, .createTime).map(Self.joinDate)
        introduction = Self.text(c, .introduction) ?? ""
        interests = ((try? c.decodeIfPresent([Category].self, forKey: .sysCategoryList)) ?? nil)?
            .compactMap { $0.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        casePictures = (Self.text(c, .casePics) ?? "").split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Source `formatJoinDate`: first ten characters with `-` replaced by `.`.
    static func joinDate(_ raw: String) -> String {
        String(raw.prefix(10)).replacingOccurrences(of: "-", with: ".")
    }
    private static func text(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        guard let value = try? c.decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Decimal? {
        if let value = try? c.decodeIfPresent(Decimal.self, forKey: key) { return value }
        if let raw = text(c, key) { return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) }
        return nil
    }
    private static func integer(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
        return text(c, key).flatMap { Int($0) }
    }
    /// Source `metricNumber`: finite and non-negative, otherwise unknown.
    private static func metric(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        guard let value = number(c, key), value >= 0, value <= Decimal(Int32.max) else { return nil }
        return NSDecimalNumber(decimal: value).intValue
    }
    /// Source `formatBalance`: two fraction digits, or nil (rendered as "—").
    private static func balance(_ c: KeyedDecodingContainer<CodingKeys>) -> String? {
        guard var value = number(c, .balance) else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: rounded))
    }
}

/// `/api/role/info` (server `UserPermission`). Only explicit `true` unlocks a
/// capability; a null theme limit means unlimited, exactly as `buildBenefits`.
public struct MemberRoleInfo: Decodable, Equatable {
    public struct Permission: Decodable, Equatable {
        public let maxThemes: Int?
        public let canPublishCoupon: Bool?
        public let canRedeemCoupon: Bool?
        public let canBranch: Bool?
        public let canGameMechanic: Bool?
        public let canOpenAsNode: Bool?
        public let canDesignMedal: Bool?
        public let canCreateGroup: Bool?
        public let withdrawable: Bool?
        public init(maxThemes: Int? = nil, canPublishCoupon: Bool? = nil, canRedeemCoupon: Bool? = nil,
                    canBranch: Bool? = nil, canGameMechanic: Bool? = nil, canOpenAsNode: Bool? = nil,
                    canDesignMedal: Bool? = nil, canCreateGroup: Bool? = nil, withdrawable: Bool? = nil) {
            self.maxThemes = maxThemes; self.canPublishCoupon = canPublishCoupon; self.canRedeemCoupon = canRedeemCoupon
            self.canBranch = canBranch; self.canGameMechanic = canGameMechanic; self.canOpenAsNode = canOpenAsNode
            self.canDesignMedal = canDesignMedal; self.canCreateGroup = canCreateGroup; self.withdrawable = withdrawable
        }
        enum CodingKeys: String, CodingKey {
            case maxThemes, canPublishCoupon, canRedeemCoupon, canBranch, canGameMechanic, canOpenAsNode, canDesignMedal, canCreateGroup, withdrawable
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func flag(_ key: CodingKeys) -> Bool? { try? c.decodeIfPresent(Bool.self, forKey: key) }
            maxThemes = try? c.decodeIfPresent(Int.self, forKey: .maxThemes)
            canPublishCoupon = flag(.canPublishCoupon); canRedeemCoupon = flag(.canRedeemCoupon)
            canBranch = flag(.canBranch); canGameMechanic = flag(.canGameMechanic); canOpenAsNode = flag(.canOpenAsNode)
            canDesignMedal = flag(.canDesignMedal); canCreateGroup = flag(.canCreateGroup); withdrawable = flag(.withdrawable)
        }
    }
    public let role: String
    public let isClubLeader: Bool
    public let ownedClubCount: Int
    public let permission: Permission
    enum CodingKeys: String, CodingKey { case role, isClubLeader, ownedClubs, permission }
    private struct OwnedClub: Decodable {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let role = ((try? c.decodeIfPresent(String.self, forKey: .role)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // The source ignores a response without a role; so does this mapping.
        guard !role.isEmpty, role.utf8.count <= 32 else { throw APIError.malformedResponse }
        self.role = role
        isClubLeader = ((try? c.decodeIfPresent(Bool.self, forKey: .isClubLeader)) ?? nil) == true || role == "club"
        ownedClubCount = ((try? c.decodeIfPresent([OwnedClub].self, forKey: .ownedClubs)) ?? nil)?.count ?? 0
        permission = ((try? c.decodeIfPresent(Permission.self, forKey: .permission)) ?? nil) ?? Permission()
    }
    public var benefits: [MemberBenefit] { MemberBenefit.rows(for: permission) }
}

public struct MemberBenefit: Equatable, Identifiable {
    public enum Kind: String, CaseIterable, Equatable {
        case publishRoutes, publishCoupons, redeemCoupons, branching, gameMechanics, openAsNode, medalDesign, createGroup, earnings
    }
    public enum RouteLimit: Equatable { case unlimited, limited(Int) }
    public let kind: Kind
    public let unlocked: Bool
    /// Only the route-publishing row carries a limit.
    public let routeLimit: RouteLimit?
    /// Only 我的收益 navigates, and only when unlocked.
    public var opensEarnings: Bool { kind == .earnings && unlocked }
    public var id: String { kind.rawValue }

    public static func rows(for p: MemberRoleInfo.Permission) -> [MemberBenefit] {
        let limit: RouteLimit = p.maxThemes.map { .limited(max(0, $0)) } ?? .unlimited
        let routesUnlocked = p.maxThemes.map { $0 > 0 } ?? true
        func row(_ kind: Kind, _ flag: Bool?) -> MemberBenefit { .init(kind: kind, unlocked: flag == true, routeLimit: nil) }
        return [
            .init(kind: .publishRoutes, unlocked: routesUnlocked, routeLimit: limit),
            row(.publishCoupons, p.canPublishCoupon), row(.redeemCoupons, p.canRedeemCoupon),
            row(.branching, p.canBranch), row(.gameMechanics, p.canGameMechanic),
            row(.openAsNode, p.canOpenAsNode), row(.medalDesign, p.canDesignMedal),
            row(.createGroup, p.canCreateGroup), row(.earnings, p.withdrawable)
        ]
    }
}

public enum MemberRoleInfoReadRoute {
    public static let path = "api/role/info"
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(path).absoluteString.utf8),
              request.httpMethod == "POST", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Content-Type") == nil,
              let token = request.value(forHTTPHeaderField: "Authorization"),
              AuthRequestBuilder.isValidToken(token) else { return false }
        return true
    }
}

public enum MemberHomeReadFailure: Error, Equatable { case rejected(code: Int, message: String?) }

/// Read-only. The identity read is the same body-less `user/info` request the
/// session bootstrap already sends; `role/info` has its own approval route.
public struct MemberHomeService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func identity(token: String) async throws -> MemberIdentitySnapshot {
        try await read(AuthRequestBuilder(configuration: configuration).make(.userInfo, token: token))
    }
    public func roleInfo(token: String) async throws -> MemberRoleInfo {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        return try await read(AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent(MemberRoleInfoReadRoute.path),
            fields: [:], token: token, includesBody: false))
    }
    private struct Status: Decodable { let code: Int; let msg: String? }
    private struct Payload<T: Decodable>: Decodable { let data: T }
    private func read<T: Decodable>(_ request: URLRequest) async throws -> T {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 256 * 1024 else { throw APIError.malformedResponse }
        let envelope = try? JSONDecoder().decode(Status.self, from: data)
        // The source treats code 401 and code 2 as an expired login.
        if status == 401 || envelope?.code == 401 || envelope?.code == 2 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let envelope else { throw APIError.malformedResponse }
        guard envelope.code == 200 else { throw MemberHomeReadFailure.rejected(code: envelope.code, message: envelope.msg) }
        do { return try JSONDecoder().decode(Payload<T>.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
}

/// An in-memory identity fence; credentials are neither displayed nor persisted.
public struct MemberHomeSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    public let roleInfoApproval: UUID?
    let token: String
    public init(accountID: Int, epoch: UInt64, token: String, roleInfoApproval: UUID?) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token; self.roleInfoApproval = roleInfoApproval
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.epoch == rhs.epoch && lhs.roleInfoApproval == rhs.roleInfoApproval &&
            lhs.token.utf8.elementsEqual(rhs.token.utf8)
    }
}

@MainActor public protocol MemberHomeReading: AnyObject {
    /// Changes whenever the account, epoch or role-info approval changes.
    var scope: UUID { get }
    var isSignedIn: Bool { get }
    var isConfigured: Bool { get }
    var roleInfoAvailable: Bool { get }
    func identity() async throws -> MemberIdentitySnapshot
    func roleInfo() async throws -> MemberRoleInfo
}

@MainActor public final class MemberHomeSessionReader: MemberHomeReading {
    private let service: MemberHomeService?
    private let currentSession: () -> MemberHomeSession?
    private let onUnauthorized: (MemberHomeSession) -> Void
    private var snapshot: MemberHomeSession?
    private var stamp = UUID()
    public var scope: UUID {
        let current = currentSession()
        if snapshot != current { snapshot = current; stamp = UUID() }
        return stamp
    }
    public var isSignedIn: Bool { currentSession() != nil }
    public var isConfigured: Bool { service != nil }
    public var roleInfoAvailable: Bool { service != nil && currentSession()?.roleInfoApproval != nil }
    public init(service: MemberHomeService?, currentSession: @escaping () -> MemberHomeSession?,
                onUnauthorized: @escaping (MemberHomeSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func identity() async throws -> MemberIdentitySnapshot {
        try await read(requiresApproval: false) { try await $0.identity(token: $1) }
    }
    public func roleInfo() async throws -> MemberRoleInfo {
        try await read(requiresApproval: true) { try await $0.roleInfo(token: $1) }
    }
    private func read<T>(requiresApproval: Bool, _ operation: (MemberHomeService, String) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard let captured = currentSession() else { throw APIError.unauthorized }
        guard let service, !requiresApproval || captured.roleInfoApproval != nil else { throw APIError.notConfigured }
        do {
            let value = try await operation(service, captured.token)
            try Task.checkCancellation()
            guard currentSession() == captured else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentSession() == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(captured) }
            throw error
        }
    }
}
