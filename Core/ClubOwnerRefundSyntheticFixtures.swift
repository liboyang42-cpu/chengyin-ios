import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline examples only. No URLSession, credentials from accounts or provider calls.
public struct ClubOwnerRefundFixtureTransport: ClubOwnerRefundOfflineTransport {
    public let status: Int
    public let body: String
    public init(status: Int = 200, body: String) { self.status = status; self.body = body }
    public func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(body.utf8), status) }
}
@MainActor public final class ClubOwnerRefundMemoryLocks: ClubOwnerRefundLocking {
    public var values: Set<String> = []
    public var failWrites = false
    public var failAfterAcquisitions: Int?
    public var onAcquire: (() -> Void)?
    public init() {}
    public func contains(_ key: String) throws -> Bool { values.contains(key) }
    public func acquire(_ key: String) throws {
        guard !failWrites, !values.contains(key), failAfterAcquisitions.map({ values.count < $0 }) ?? true else { throw ClubOwnerRefundFailure.storage }; values.insert(key); onAcquire?()
    }
}
@MainActor public final class ClubOwnerRefundFixtureAccess: ClubOwnerRefundAccess {
    public enum Scenario { case accepted, unknown, manual, httpFailure, httpTimeout, businessTimeout, malformed, disabled }
    public let governance = ClubGovernanceFixtureAccess()
    public var identity: ClubReadIdentity? { get { governance.identity } set { governance.identity = newValue } }
    public var namespace = "synthetic-owner-refund"
    public var canDispatchOffline: Bool { scenario != .disabled }
    public let scenario: Scenario
    public private(set) var sent = 0
    public var onEvidence: (() -> Void)?
    public var beforeEvidence: (() async -> Void)?
    public var onSend: (() -> Void)?
    public init(_ scenario: Scenario = .accepted) {
        self.scenario = scenario
        governance.overrideValue[.checkin] = ClubGovernanceFixtures.json(#"{"registrationId":121,"displayName":"Fixture attendee","topicName":"Fixture topic","ticketText":"Fixture ticket","orderNo":"SAMPLE-121","paidAmountText":"Source amount","statusCode":"PENDING","railStep":0,"canRefund":true}"#)
    }
    public func markRefundRecorded() {
        var object = governance.overrideValue[.checkin]?.object ?? [:]
        object["statusCode"] = .string("REFUNDED"); object["canRefund"] = .bool(false); object["railStep"] = .integer(-1)
        governance.overrideValue[.checkin] = .object(object)
    }
    public func evidence(_ target: ClubOwnerRefundTarget) async throws -> ClubOwnerRefundEvidence {
        onEvidence?(); await beforeEvidence?()
        let snapshot = try await governance.read(.checkin, scope: target.scope, options: [:])
        return try ClubOwnerRefundEvidence(snapshot: snapshot, target: target)
    }
    public func send(_ review: ClubOwnerRefundReview) async throws -> ClubOwnerRefundReceipt {
        guard canDispatchOffline else { throw ClubOwnerRefundFailure.disabled }
        sent += 1; onSend?()
        let body: String, status: Int
        switch scenario {
        case .unknown: body = "{}"; status = 503
        case .httpFailure: body = #"{"code":403,"msg":"Fixture rejected"}"#; status = 403
        case .httpTimeout: body = #"{"code":408,"msg":"Fixture timeout"}"#; status = 408
        case .businessTimeout: body = #"{"code":408,"msg":"Fixture business timeout"}"#; status = 200
        case .malformed: body = #"{"code":200,"msg":"Fixture incomplete feedback","data":{}}"#; status = 200
        case .manual: body = #"{"code":200,"msg":"Fixture manual review","data":{"registrationId":121,"cancellationStatus":"MANUAL_REVIEW","cashRefundStatus":"MANUAL_REVIEW","cashRefundAmount":null}}"#; status = 200
        default: body = #"{"code":200,"msg":"Fixture accepted; payout processing","data":{"registrationId":121,"scope":"REGISTRATION","cancellationStatus":"CANCELLED","cashRefundStatus":"PROCESSING","pointsRefundStatus":"NOT_NEEDED"}}"#; status = 200
        }
        let service = ClubOwnerRefundService(offlineConfiguration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!), offlineTransport: ClubOwnerRefundFixtureTransport(status: status, body: body))
        return try await service.cancel(registrationID: review.evidence.target.registrationID, token: "synthetic-offline-token") {
            guard self.identity == review.identity, self.namespace == review.namespace else { throw ClubOwnerRefundFailure.stale }
        }
    }
}
