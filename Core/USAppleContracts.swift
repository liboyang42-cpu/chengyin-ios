import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Release admission remains closed even when a deployment URL has been approved.
/// Backend realm enforcement and protected-session verification are separate release gates.
public enum USAppleProductionGate {
    public static let enabled = false
}

/// A monotonic clock that includes device sleep. Values have no persisted/cross-process meaning.
public enum USAppleMonotonicClock {
    private static let clock = ContinuousClock()
    private static let origin = clock.now
    public static func now() -> TimeInterval {
        let elapsed = origin.duration(to: clock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
    }
}

/// Exactly approved US origin + host-owned realm, never inferred from locale or Apple audience.
public struct USAppleDeployment: Equatable {
    public let origin: URL
    public let realm: String
    public init(market: RegionalMarket, origin: URL, realm: String, approvedUSOrigins: Set<String>) throws {
        guard market == .unitedStates,
              let parts = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              approvedUSOrigins.contains(origin.absoluteString),
              !realm.isEmpty, realm.utf8.count <= 128,
              realm.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw USAppleError.unavailable
        }
        self.origin = origin; self.realm = realm
    }
}

/// Only these pairs are the backend's stable handled protocol errors. Never parse `msg`.
public enum USAppleError: String, Error, CaseIterable {
    case invalidRequest = "US_APPLE_INVALID_REQUEST"
    case invalidChallenge = "US_APPLE_INVALID_CHALLENGE"
    case invalidIdentity = "US_APPLE_INVALID_IDENTITY"
    case rateLimited = "US_APPLE_RATE_LIMITED"
    case unavailable = "US_APPLE_UNAVAILABLE"
    public var httpStatus: Int {
        switch self {
        case .invalidRequest: return 400
        case .invalidChallenge, .invalidIdentity: return 401
        case .rateLimited: return 429
        case .unavailable: return 503
        }
    }
}

public enum USAppleClientError: Error, Equatable {
    case invalidResponse, authorizationFailed, sessionChanged, storage
}

public enum USAppleValidation {
    /// Exact canonical unpadded base64url encoding of 256 bits.
    public static func isRandomValue(_ value: String) -> Bool {
        guard value.utf8.count == 43,
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              let bytes = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="),
              bytes.count == 32 else { return false }
        return bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value
    }
    /// Transport validation only. Apple JWT verification belongs to the backend.
    public static func isToken(_ value: String) -> Bool {
        (1...16_384).contains(value.utf8.count) && value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
    }
    public static func nonceDigest(_ rawNonce: String) throws -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        // No alternate algorithm, plaintext nonce or silent authentication fallback.
        throw USAppleError.unavailable
        #endif
    }
}

/// Attempt-only memory. Never persist, print, send to telemetry, or add to a URL.
public struct USAppleChallenge: Decodable {
    public let challengeId: String
    public let rawNonce: String
    public let state: String
    public let expiresIn: Int
    public let market: String
    public let provider: String
    public func validate() throws {
        guard USAppleValidation.isRandomValue(challengeId), USAppleValidation.isRandomValue(rawNonce),
              USAppleValidation.isRandomValue(state), Set([challengeId, rawNonce, state]).count == 3,
              (1...300).contains(expiresIn), market == "US", provider == "apple" else {
            throw USAppleClientError.invalidResponse
        }
    }
}

public struct USAppleAuthorizationRequest {
    public let nonce: String // SHA-256(rawNonce), lowercase hex; never rawNonce.
    public let state: String
    public init(nonce: String, state: String) { self.nonce = nonce; self.state = state }
}
public struct USAppleCredential {
    public let identityToken: String
    public let state: String?
    public init(identityToken: String, state: String?) { self.identityToken = identityToken; self.state = state }
}

@MainActor
public protocol USAppleAuthorizing: AnyObject {
    func authorize(_ request: USAppleAuthorizationRequest) async throws -> USAppleCredential
    func cancel()
}
@MainActor
public protocol USAppleServing {
    func challenge() async throws -> USAppleChallenge
    func exchange(challengeId: String, state: String, identityToken: String) async throws -> LoginResult
}

public struct USAppleSessionSnapshot: Equatable {
    public let epoch: UInt64
    public let market: RegionalMarket
    public let realm: String
    public let accountID: Int?
    public let isBusy: Bool
    public init(epoch: UInt64, market: RegionalMarket, realm: String, accountID: Int?, isBusy: Bool = false) {
        self.epoch = epoch; self.market = market; self.realm = realm; self.accountID = accountID; self.isBusy = isBusy
    }
}

/// Evidence produced by the future US protected-session adapter, NOT by reading JWT claims
/// or echoing the exchange's `market` field. No current-account URL is invented here.
public struct USAppleVerifiedCurrentAccount {
    public let account: Account
    public let market: RegionalMarket
    public let realm: String
    public init(account: Account, market: RegionalMarket, realm: String) {
        self.account = account; self.market = market; self.realm = realm
    }
}

public enum USAppleWork: Equatable { case requestingChallenge, authorizing, exchanging, verifyingAccount }
public enum USAppleIssue: Equatable {
    case invalidRequest, invalidChallenge, invalidIdentity, rateLimited, unavailable
    case invalidResponse, authorizationFailed, network, sessionChanged, storage
    public var localizationKey: String {
        switch self {
        case .invalidRequest: return "usApple.invalidRequest"
        case .invalidChallenge: return "usApple.invalidChallenge"
        case .invalidIdentity: return "usApple.invalidIdentity"
        case .rateLimited: return "usApple.rateLimited"
        case .unavailable: return "usApple.unavailable"
        case .invalidResponse: return "usApple.invalidResponse"
        case .authorizationFailed: return "usApple.authorizationFailed"
        case .network: return "usApple.network"
        case .sessionChanged: return "usApple.sessionChanged"
        case .storage: return "usApple.storage"
        }
    }
}
public struct USAppleState: Equatable {
    public internal(set) var work: USAppleWork?
    public internal(set) var issue: USAppleIssue?
    public internal(set) var signedIn = false
    public var isWorking: Bool { work != nil }
}
