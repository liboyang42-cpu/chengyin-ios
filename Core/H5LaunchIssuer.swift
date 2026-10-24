import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The platform issues the one-time shell description. An already held
/// API configuration whose base URL is https supplies the host: parentOrigin
/// and the shell URL are that host, scheme https, with no userinfo and no extra
/// domain. The nonce is minted here. License and author records do not carry
/// parentOrigin, nonce, or a shell URL, and this type does not read those fields
/// from them. The POST body is the nonce. A different host does not load. The
/// existing parent then opens the shell, and the install recovery entry reads
/// the owned install receipt for the same install request id. advanced/start and
/// a payment native-context are not the ticket. A missing or non-https
/// configuration closes only this launch. This type does not invent a
/// certificate, a zip, or an approval.
public struct H5LaunchIssuer {
    public enum Close: Equatable, Sendable {
        case missingConfiguration
        case notHTTPS
        case hostMismatch
        case advancedStartRefused
        case paymentNativeContextRefused
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

    private struct IssuedOrigin: Equatable {
        let parentOrigin: String
        let shellURL: URL
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

    /// One-time POST from the held configuration. Nil closes only this launch.
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
        let nonce = Self.mintNonce()
        guard let issued = Self.issuedOrigin(baseURL: baseURL),
              issued.shellURL.host == baseURL.host, issued.shellURL.port == baseURL.port,
              let launch = H5LaunchDescription(parentOrigin: issued.parentOrigin, nonce: nonce, mainToken: nil),
              let request = H5ShellParentFlow.loadRequest(shellURL: issued.shellURL, launch: launch),
              request.httpMethod == "POST",
              request.url?.scheme == "https", request.url?.user == nil, request.url?.password == nil,
              request.url?.host == issued.shellURL.host, request.url?.port == issued.shellURL.port,
              request.url?.query == nil, request.url?.fragment == nil,
              Self.sameHost(issued.parentOrigin, issued.shellURL),
              Self.bodyIsNonceOnly(request, nonce: nonce),
              !Self.mentionsAdvancedStart(issued.shellURL),
              !Self.mentionsPaymentNativeContext(issued.shellURL),
              request.url?.absoluteString.contains(nonce) != true else {
            return fail(.hostMismatch)
        }
        launchClosed = nil
        presentedLaunch = launch
        presentedShellURL = issued.shellURL
        parent = H5ShellParentFlow(requestID: owned.requestID, entry: entry)
        return request
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

    private static func mintNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Host already on the base URL. Scheme is https. Userinfo is not copied.
    /// No extra domain label and no invented shell path are added.
    private static func issuedOrigin(baseURL: URL) -> IssuedOrigin? {
        guard baseURL.scheme == "https",
              let parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.user == nil, parts.password == nil,
              let host = parts.host, !host.isEmpty,
              !host.contains("/"), !host.contains("@"), !host.contains("\\"), !host.contains(" ") else { return nil }
        let text = originText(host: host, port: parts.port)
        guard let shellURL = URL(string: text),
              shellURL.scheme == "https", shellURL.host == host, shellURL.port == parts.port,
              shellURL.user == nil, shellURL.password == nil,
              shellURL.query == nil, shellURL.fragment == nil else { return nil }
        let path = shellURL.path
        guard path.isEmpty || path == "/" else { return nil }
        guard URL(string: text)?.host == host, URL(string: text)?.port == parts.port else { return nil }
        return IssuedOrigin(parentOrigin: text, shellURL: shellURL)
    }

    private static func originText(host: String, port: Int?) -> String {
        let name = host.contains(":") && !host.contains("]") ? "[\(host)]" : host
        if let port { return "https://\(name):\(port)" }
        return "https://\(name)"
    }

    private static func sameHost(_ parentOrigin: String, _ shellURL: URL) -> Bool {
        guard let origin = URL(string: parentOrigin),
              origin.scheme == "https", origin.user == nil, origin.password == nil,
              origin.host == shellURL.host, origin.port == shellURL.port,
              shellURL.scheme == "https", shellURL.user == nil, shellURL.password == nil else { return false }
        return true
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
