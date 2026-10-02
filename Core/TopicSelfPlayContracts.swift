import Foundation

/// A topic identity cannot be passed to the activity registration request by accident.
public struct SelfPlayTopicID: RawRepresentable, Codable, Hashable {
    public let rawValue: Int
    public init?(rawValue: Int) { guard rawValue > 0 else { return nil }; self.rawValue = rawValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer(); let raw = try c.decode(Int.self)
        guard let id = Self(rawValue: raw) else { throw APIError.malformedResponse }; self = id
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
public struct TopicSelfPlayIntent: Encodable, Equatable {
    public let topic: SelfPlayTopicID
    public let realName: String
    public let phone: String
    public let requestID: String
    public init(topic: SelfPlayTopicID, realName: String, phone: String, requestID: String) throws {
        let name = realName.trimmingCharacters(in: .whitespacesAndNewlines), phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, phone.range(of: "^1[0-9]{10}$", options: .regularExpression) != nil,
              !requestID.isEmpty, requestID.utf16.count <= 64 else { throw APIError.invalidRequest }
        self.topic = topic; self.realName = name; self.phone = phone; self.requestID = requestID
    }
    enum CodingKeys: String, CodingKey { case ownerType, ownerId, realName, phone, isUsePoint, payChannel, requestId }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .ownerType); try c.encode(topic.rawValue, forKey: .ownerId)
        try c.encode(realName, forKey: .realName); try c.encode(phone, forKey: .phone)
        try c.encode(0, forKey: .isUsePoint); try c.encode("APP", forKey: .payChannel); try c.encode(requestID, forKey: .requestId)
    }
}
public struct TopicSelfPlayDocument: Equatable {
    public let version: String
    public let officialURL: URL
    public init(version: String, officialURL: URL) throws {
        guard !version.isEmpty, let parts = URLComponents(url: officialURL, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else { throw APIError.invalidConfiguration }
        self.version = version; self.officialURL = officialURL
    }
}
@MainActor public protocol TopicSelfPlayDocumentProviding {
    /// Independently approved current signup-sharing notice for this exact deployment.
    /// No document endpoint/version is invented by the client.
    func currentDocument(context: RuntimeDependencyContext) async throws -> TopicSelfPlayDocument
}
public enum TopicSelfPlayProviderReturn: Equatable { case returned, cancelled, failed, unknown }
@MainActor public protocol TopicSelfPlayPaymentProviding {
    var isConfigured: Bool { get }
    func pay(registrationID: Int, parameters: [String: String]) async -> TopicSelfPlayProviderReturn
}
public struct TopicSelfPlayPending: Codable, Equatable {
    public let owner: String
    public let topic: SelfPlayTopicID
    public let requestID: String
    public var registrationID: Int?
    public var paymentAttempted: Bool?
    public init(owner: String, topic: SelfPlayTopicID, requestID: String, registrationID: Int? = nil) {
        self.owner = owner; self.topic = topic; self.requestID = requestID; self.registrationID = registrationID; paymentAttempted = false
    }
}
@MainActor public protocol TopicSelfPlayJournaling: AnyObject {
    func pending(owner: String, topic: SelfPlayTopicID) throws -> TopicSelfPlayPending?
    func write(_ pending: TopicSelfPlayPending) throws
    func resolve(_ pending: TopicSelfPlayPending, authoritativeOrder: OrderLifecycleDetail) throws
}
/// Stores only opaque intent/order IDs. Unknown create remains locked across dismiss/relaunch.
@MainActor public final class TopicSelfPlayDefaultsJournal: TopicSelfPlayJournaling {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    private func key(_ owner: String, _ topic: SelfPlayTopicID) -> String { "selfplay.pending.v1." + Data("\(owner)|\(topic.rawValue)".utf8).base64EncodedString() }
    public func pending(owner: String, topic: SelfPlayTopicID) throws -> TopicSelfPlayPending? {
        guard let raw = defaults.object(forKey: key(owner, topic)) else { return nil }
        guard let data = raw as? Data, let value = try? JSONDecoder().decode(TopicSelfPlayPending.self, from: data),
              value.owner == owner, value.topic == topic, !value.requestID.isEmpty,
              value.registrationID.map({ $0 > 0 }) ?? true else { throw APIError.malformedResponse }
        return value
    }
    public func resolve(_ pending: TopicSelfPlayPending, authoritativeOrder: OrderLifecycleDetail) throws {
        guard try self.pending(owner: pending.owner, topic: pending.topic) == pending,
              pending.registrationID == authoritativeOrder.id, authoritativeOrder.ownerType == 1,
              authoritativeOrder.ownerID == pending.topic.rawValue,
              [3, 4].contains(authoritativeOrder.registrationStatus ?? 0) else { throw APIError.invalidRequest }
        let key = key(pending.owner, pending.topic); defaults.removeObject(forKey: key)
        guard defaults.object(forKey: key) == nil else { throw APIError.malformedResponse }
    }
    public func write(_ pending: TopicSelfPlayPending) throws {
        let prior = try self.pending(owner: pending.owner, topic: pending.topic)
        guard prior == nil || prior?.requestID == pending.requestID,
              prior?.registrationID == nil || prior?.registrationID == pending.registrationID,
              prior?.paymentAttempted != true || pending.paymentAttempted == true else { throw APIError.invalidRequest }
        let data = try JSONEncoder().encode(pending), key = key(pending.owner, pending.topic)
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else { throw APIError.malformedResponse }
    }
}
public struct TopicSelfPlayReview: Equatable, Identifiable {
    public let id: UUID
    public let session: PublishingSession
    public let intent: TopicSelfPlayIntent
    public let price: Decimal
    public let document: TopicSelfPlayDocument
}
public enum TopicSelfPlayFailure: Error, Equatable { case unavailable, changed, invalid, consent, priceChanged, unknown }

public struct TopicSelfPlayPaymentReview: Identifiable, Equatable {
    public let id: UUID
    public let session: PublishingSession
    public let registrationID: Int
    public let price: Decimal
    public let document: TopicSelfPlayDocument
}
@MainActor public final class TopicSelfPlayOperationGate {
    private var busy = false
    public init() {}
    public func acquire() -> Bool { guard !busy else { return false }; busy = true; return true }
    public func release() { busy = false }
}
