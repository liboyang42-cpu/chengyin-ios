import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RegistrationWaitlistScope: Codable, Hashable {
    public let activityID: Int
    public let ticketID: Int
    public init(activityID: Int, ticketID: Int) throws {
        guard activityID > 0, ticketID > 0 else { throw APIError.invalidRequest }
        self.activityID = activityID; self.ticketID = ticketID
    }
    enum CodingKeys: String, CodingKey { case activityID = "activityId", ticketID = "ticketId" }
}
public enum RegistrationWaitlistState: String, Decodable { case none = "NONE", waiting = "WAITING", offered = "OFFERED", claimed = "CLAIMED", converted = "CONVERTED", cancelled = "CANCELLED", expired = "EXPIRED" }
public enum RegistrationWaitlistEligibility: String, Decodable { case noSeries = "NO_SERIES", closed = "WAITLIST_CLOSED", notMember = "NOT_MEMBER", registered = "ALREADY_REGISTERED", eligible = "ELIGIBLE", blocked = "BLOCKED" }

/// Exact current-member status. No queue position, capacity, renewal, or quantity is inferred.
public struct RegistrationWaitlistStatus: Decodable, Equatable {
    public let id: Int?
    public let activityID: Int
    public let ticketID: Int
    public let memberID: Int
    public let state: RegistrationWaitlistState
    public let eligibility: RegistrationWaitlistEligibility
    public let joinAllowed: Bool
    public let registrationID: Int?
    public let expiresAt: Date?
    private let offerToken: String?
    enum CodingKeys: String, CodingKey { case id, activityID = "activityId", ticketID = "ticketId", memberID = "memberId", state, eligibility = "eligibilityState", joinAllowed = "waitlistJoinAllowed", registrationID = "registrationId", expiresAt = "offerExpiresAt", offerToken }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        activityID = try c.decode(Int.self, forKey: .activityID)
        ticketID = try c.decode(Int.self, forKey: .ticketID)
        memberID = try c.decode(Int.self, forKey: .memberID)
        state = try c.decode(RegistrationWaitlistState.self, forKey: .state)
        eligibility = try c.decode(RegistrationWaitlistEligibility.self, forKey: .eligibility)
        joinAllowed = try c.decode(Bool.self, forKey: .joinAllowed)
        registrationID = try c.decodeIfPresent(Int.self, forKey: .registrationID)
        offerToken = try c.decodeIfPresent(String.self, forKey: .offerToken)
        let rawDate = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        expiresAt = rawDate.flatMap(Self.parseDeadline)
        guard activityID > 0, ticketID > 0, memberID > 0,
              id.map({ $0 > 0 }) ?? (state == .none),
              registrationID.map({ $0 > 0 }) ?? ![.claimed, .converted].contains(state),
              joinAllowed == (eligibility == .eligible),
              state != .offered || eligibility != .eligible || (id != nil && expiresAt != nil && offerToken.map({ !$0.isEmpty && $0.utf8.count <= 256 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }) == true) else { throw APIError.malformedResponse }
    }
    public func matches(_ scope: RegistrationWaitlistScope, accountID: Int) -> Bool {
        activityID == scope.activityID && ticketID == scope.ticketID && memberID == accountID
    }
    public var canJoin: Bool { eligibility == .eligible && joinAllowed && [.none, .cancelled, .expired].contains(state) }
    public var canCancel: Bool { [.waiting, .offered].contains(state) }
    public func offer(at now: Date) -> RegistrationWaitlistOffer? {
        guard state == .offered, eligibility == .eligible, let id, let offerToken, let expiresAt,
              expiresAt > now else { return nil }
        return try? .init(id: id, token: offerToken)
    }
    /// Backend uses Asia/Shanghai for timezone-free date strings. Never use device timezone.
    /// Offset-bearing ISO dates remain absolute. No stale client-side two-hour maximum.
    static func parseDeadline(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        guard text.range(of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\z"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"; formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
}

@MainActor public protocol RegistrationWaitlistServing {
    func status(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus
    func join(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus
    func cancel(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus
}

/// Dormant wire adapter. Production composition uses the independently scoped guarded service.
public struct RegistrationWaitlistService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) { self.configuration = configuration; self.transport = transport }
    public func status(_ scope: RegistrationWaitlistScope, accountID: Int, token: String) async throws -> RegistrationWaitlistStatus {
        let result: RegistrationWaitlistStatus = try await post("status", scope: scope, token: token)
        guard result.matches(scope, accountID: accountID) else { throw APIError.malformedResponse }
        return result
    }
    public func join(_ scope: RegistrationWaitlistScope, accountID: Int, token: String) async throws -> Int {
        let receipt: JoinReceipt = try await post("join", scope: scope, token: token)
        guard receipt.id > 0, receipt.activityId == scope.activityID, receipt.ticketId == scope.ticketID,
              receipt.memberId == accountID, receipt.state == "WAITING" else { throw APIError.malformedResponse }
        return receipt.id
    }
    public func cancel(_ scope: RegistrationWaitlistScope, token: String) async throws {
        let _: Bool = try await post("cancel", scope: scope, token: token)
    }
    private struct JoinReceipt: Decodable { let id: Int; let activityId: Int; let ticketId: Int; let memberId: Int; let state: String }
    private func post<T: Decodable>(_ operation: String, scope: RegistrationWaitlistScope, token: String) async throws -> T {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let request = try OperationAdapterHTTP.json(configuration: configuration,
            path: "api/club/event-ops/waitlist/\(operation)", body: JSONEncoder().encode(scope), token: token)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        return try JSONDecoder().decode(RegistrationResponse<T>.self, from: data).data
    }
}
