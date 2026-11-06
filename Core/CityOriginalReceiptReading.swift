import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// r491 source domains. These are not the proposed CityGameServing operations.
public enum CityOriginalReceiptDomain: String, CaseIterable, Sendable {
    case participation = "team-participation"
    case actionBudget = "action-budget"
    case acquisition = "acquisition"
}
public enum CityOriginalReceiptReadFailure: Error, Equatable {
    case disabled, invalidReference, staleSession, unverified, unavailable(status: Int)
}

/// Ephemeral original actor/deployment. No token is exposed in the receipt projection.
public struct CityOriginalReceiptSession: Equatable {
    public let market: RegionalMarket
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public let epoch: UInt64
    private let credential: String
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int, epoch: UInt64, token: String) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard accountID > 0, !namespace.isEmpty, AuthRequestBuilder.isValidToken(token) else {
            throw CityOriginalReceiptReadFailure.invalidReference
        }
        self.market = market; self.baseURL = baseURL; self.namespace = namespace
        self.accountID = accountID; self.epoch = epoch; credential = token
    }
    fileprivate var token: String { credential }
}

/// Supplied by an original command owner, never minted from a displayed row or a new UUID.
/// This additive reader does not create command references or translate old CityActionIntent.
public struct CityOriginalReceiptReference: Equatable {
    public let session: CityOriginalReceiptSession
    public let domain: CityOriginalReceiptDomain
    public let requestID: String
    public init(session: CityOriginalReceiptSession, domain: CityOriginalReceiptDomain, requestID: String) throws {
        // CityBoardDraftDocument.isId, including its 96-byte ASCII ceiling.
        let bytes = Array(requestID.utf8)
        func alphaNumeric(_ value: UInt8) -> Bool { (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value) }
        guard let first = bytes.first, bytes.count <= 96, alphaNumeric(first),
              bytes.allSatisfy({ alphaNumeric($0) || $0 == 45 || $0 == 95 }) else {
            throw CityOriginalReceiptReadFailure.invalidReference
        }
        self.session = session; self.domain = domain; self.requestID = requestID
    }
}

/// Exact read-only issuance. No production issuer is installed by this change.
@MainActor public final class CityOriginalReceiptReadGrant {
    public let reference: CityOriginalReceiptReference
    public private(set) var isRevoked = false
    public init(reference: CityOriginalReceiptReference) { self.reference = reference }
    public func revoke() { isRevoked = true }
}

/// A source observation, NOT a gameplay receipt or permission to clear/replay an intent.
/// COMPLETE may be a terminal business rejection. Its domain payload is deliberately
/// not coerced into CityActionReceipt, points, ownership or payer success.
public struct CityOriginalReceiptObservation: Equatable {
    public enum State: Equatable { case unknown, complete(httpStatus: Int, businessCode: Int) }
    public let domain: CityOriginalReceiptDomain
    public let requestID: String
    public let state: State
}

@MainActor public final class CityOriginalReceiptReader {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentSession: () -> CityOriginalReceiptSession?
    private let grant: () -> CityOriginalReceiptReadGrant?
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                currentSession: @escaping () -> CityOriginalReceiptSession?,
                grant: @escaping () -> CityOriginalReceiptReadGrant? = { nil }) {
        self.configuration = configuration; self.transport = transport
        self.currentSession = currentSession; self.grant = grant
    }
    public func read(_ reference: CityOriginalReceiptReference) async throws -> CityOriginalReceiptObservation {
        guard let issued = grant(), !issued.isRevoked, issued.reference == reference else {
            throw CityOriginalReceiptReadFailure.disabled
        }
        func check() throws {
            try Task.checkCancellation()
            guard currentSession() == reference.session, configuration.baseURL == reference.session.baseURL else {
                throw CityOriginalReceiptReadFailure.staleSession
            }
            guard grant() === issued, !issued.isRevoked else { throw CityOriginalReceiptReadFailure.disabled }
        }
        try check()
        let path = "api/city-game/\(reference.domain.rawValue)/request/\(reference.requestID)"
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(reference.session.token, forHTTPHeaderField: "Authorization")
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch { try check(); throw CityOriginalReceiptReadFailure.unverified }
        try check()
        let (data, status) = response
        // A missing/private receipt never proves the original command was not executed.
        guard ![401, 403, 404].contains(status) else { throw CityOriginalReceiptReadFailure.unavailable(status: status) }
        guard data.count <= 1_048_576, let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw CityOriginalReceiptReadFailure.unverified
        }
        guard ![401, 403, 404].contains(envelope.code) else {
            throw CityOriginalReceiptReadFailure.unavailable(status: envelope.code)
        }
        guard envelope.data.requestId == reference.requestID else { throw CityOriginalReceiptReadFailure.unverified }
        let state: CityOriginalReceiptObservation.State
        if status == 202, envelope.code == 202, envelope.errorCode == "OUTCOME_UNKNOWN", envelope.data.requestStatus == "UNKNOWN" {
            state = .unknown
        } else if envelope.data.requestStatus == "COMPLETE",
                  (status == 200 && envelope.code == 200 || [400, 409].contains(status) && envelope.code == status) {
            state = .complete(httpStatus: status, businessCode: envelope.code)
        } else { throw CityOriginalReceiptReadFailure.unverified }
        try check()
        return .init(domain: reference.domain, requestID: reference.requestID, state: state)
    }
    private struct Envelope: Decodable {
        let code: Int
        let errorCode: String?
        let data: Receipt
    }
    private struct Receipt: Decodable { let requestId: String; let requestStatus: String }
}
