import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Legacy launch facade. An API configuration and an installed license cannot
/// issue a server ticket or establish an isolated hosting origin. Until the
/// frozen backend provides that contract, launch fails closed. Reading the
/// original owned installation receipt remains available; it is not an H5
/// completion receipt. No client nonce is minted or sent to the API origin.
public struct H5LaunchIssuer {
    public enum Close: Equatable, Sendable {
        case missingConfiguration
        case notHTTPS
        case hostMismatch
        case advancedStartRefused
        case paymentNativeContextRefused
        case serverIssuedLaunchUnavailable
    }

    /// ACTIVE license row: licenseId, moduleId, purchasedVersionId, contentHash,
    /// termsHash. purchasedVersionId is the install release id. The platform
    /// issues the shell description; this record does not.
    public struct LicenseInstall: Equatable, Sendable {
        public let requestID: String
        public let status: String
        public let identity: WorkshopInstallIdentity
        public var licenseId: String { identity.licenseId }
        public var moduleId: String { identity.moduleId }
        public var purchasedVersionId: String { identity.releaseId }
        public var contentHash: String { identity.contentHash }
        public var termsHash: String { identity.termsHash }

        public init?(requestID: String, licenseId: String, moduleId: String, purchasedVersionId: String,
                     contentHash: String, termsHash: String, status: String) {
            guard status == "ACTIVE",
                  WorkshopOriginalInstallConsumer.canonicalRequestID(requestID) != nil,
                  let identity = WorkshopInstallIdentity(licenseId: licenseId, moduleId: moduleId,
                                                        releaseId: purchasedVersionId, contentHash: contentHash,
                                                        termsHash: termsHash) else { return nil }
            self.requestID = requestID
            self.status = status
            self.identity = identity
        }
    }

    /// Author qmod submission id. It is not the install receipt id. The platform
    /// issues the shell description; this record does not.
    public struct AuthorSubmission: Equatable, Sendable {
        public let requestID: String
        public init?(requestID: String) {
            guard WorkshopOriginalInstallConsumer.canonicalRequestID(requestID) != nil else { return nil }
            self.requestID = requestID
        }
    }

    public let owned: LicenseInstall
    public let author: AuthorSubmission
    public let configuration: APIConfiguration?
    public private(set) var entry: WorkshopInstallRecoverEntry
    public private(set) var parent: H5ShellParentFlow
    public private(set) var launchClosed: Close?
    public private(set) var presentedLaunch: H5LaunchDescription?
    public private(set) var presentedShellURL: URL?
    public private(set) var receipt: WorkshopOriginalInstallFact?
    public var opensZip: Bool { entry.opensZip }
    public var clientResultIsServerPass: Bool { entry.clientResultIsServerPass }

    public init?(owned: LicenseInstall, author: AuthorSubmission, configuration: APIConfiguration?,
                 entry: WorkshopInstallRecoverEntry = WorkshopInstallRecoverEntry()) {
        guard owned.requestID != author.requestID else { return nil }
        self.owned = owned
        self.author = author
        self.configuration = configuration
        self.entry = entry
        self.parent = H5ShellParentFlow(requestID: owned.requestID, entry: entry)
    }

    /// No launch without a server-issued one-use ticket and isolated origin.
    @discardableResult
    public mutating func issue() -> URLRequest? {
        issue(baseURL: configuration?.baseURL)
    }

    /// advanced/start is not the shell ticket. The receipt read stays available.
    @discardableResult
    public mutating func refuseAdvancedStart(_ start: H5LaunchProducer.PlayerAdvancedStart) -> URLRequest? {
        _ = (start.activityID, start.topicID, start.nodeID)
        return fail(.advancedStartRefused)
    }

    /// A payment native-context is not the shell ticket. The receipt read stays available.
    @discardableResult
    public mutating func refusePaymentNativeContext(_ context: H5LaunchProducer.PaymentNativeContext) -> URLRequest? {
        _ = context.values
        return fail(.paymentNativeContextRefused)
    }

    /// Opens the existing parent when the POST exists, then reads the owned
    /// install receipt for the same install request id. A closed launch still reads.
    @discardableResult
    public mutating func readOwnedInstallReceipt(identity: WorkshopInstallIdentity,
                                                 source: any WorkshopOriginalInstallReading) async throws -> WorkshopOriginalInstallFact {
        guard identity == owned.identity else { throw WorkshopOriginalInstallError.invalidRequest }
        if presentedLaunch == nil && launchClosed == nil {
            _ = issue()
        }
        if launchClosed == nil, let launch = presentedLaunch, let shellURL = presentedShellURL {
            parent = H5ShellParentFlow(requestID: owned.requestID, entry: entry)
            guard let opened = parent.open(shellURL: shellURL, launch: launch),
                  opened.httpMethod == "POST",
                  opened.url?.host == shellURL.host,
                  opened.url?.port == shellURL.port,
                  Self.bodyIsNonceOnly(opened, nonce: launch.nonce) else {
                _ = fail(.hostMismatch)
                return try await readClosed(identity: identity, source: source)
            }
            let fact = try await parent.readOriginalReceipt(identity: identity, source: source)
            guard fact.requestID == owned.requestID, fact.requestID != author.requestID else {
                throw WorkshopOriginalInstallError.unknown
            }
            entry = parent.entry
            receipt = fact
            return fact
        }
        return try await readClosed(identity: identity, source: source)
    }

    public mutating func rejectSelfReportClear() throws {
        let installed = entry.release.journey.machine.installCount
        let kept = entry.receipt
        var failure: Error?
        do {
            try entry.rejectPageClear(requestID: owned.requestID)
        } catch {
            failure = error
        }
        do {
            try entry.rejectJavaScriptClear(requestID: owned.requestID)
        } catch {
            if failure == nil { failure = error }
        }
        guard entry.release.journey.machine.installCount == installed, entry.receipt == kept else {
            throw WorkshopOriginalInstallError.unknown
        }
        throw failure ?? WorkshopOriginalInstallError.unknown
    }

    public func clientResultInstalled(_ payload: [String: String]) -> Bool {
        entry.recordClientResult(payload)
    }

    @discardableResult
    mutating func issue(baseURL: URL?) -> URLRequest? {
        presentedLaunch = nil
        presentedShellURL = nil
        guard let baseURL else { return fail(.missingConfiguration) }
        guard baseURL.scheme == "https" else { return fail(.notHTTPS) }
        if Self.mentionsAdvancedStart(baseURL) { return fail(.advancedStartRefused) }
        if Self.mentionsPaymentNativeContext(baseURL) { return fail(.paymentNativeContextRefused) }
        guard baseURL.user == nil, baseURL.password == nil, baseURL.host != nil else { return fail(.hostMismatch) }
        return fail(.serverIssuedLaunchUnavailable)
    }

    private mutating func readClosed(identity: WorkshopInstallIdentity,
                                    source: any WorkshopOriginalInstallReading) async throws -> WorkshopOriginalInstallFact {
        let fact = try await entry.recover(requestID: owned.requestID, identity: identity, source: source)
        guard fact.requestID == owned.requestID, fact.requestID != author.requestID else {
            throw WorkshopOriginalInstallError.unknown
        }
        receipt = fact
        parent = H5ShellParentFlow(requestID: owned.requestID, entry: entry)
        return fact
    }

    private mutating func fail(_ reason: Close) -> URLRequest? {
        launchClosed = reason
        presentedLaunch = nil
        presentedShellURL = nil
        parent = H5ShellParentFlow(requestID: owned.requestID, entry: entry)
        return nil
    }

    private static func bodyIsNonceOnly(_ request: URLRequest, nonce: String) -> Bool {
        guard let encoded = nonce.addingPercentEncoding(withAllowedCharacters: .alphanumerics), !encoded.isEmpty,
              request.httpBody == Data("nonce=\(encoded)".utf8) else { return false }
        return true
    }

    private static func mentionsAdvancedStart(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return lower.contains("advanced/start") || lower.contains("/play/advanced")
    }

    private static func mentionsPaymentNativeContext(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return lower.contains("native-context") || lower.contains("nativecontext")
            || lower.contains("native-dispatch") || lower.contains("nativedispatch")
    }
}
