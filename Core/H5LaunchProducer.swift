import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Builds the one-time shell POST from the card's owned license install or the
/// author qmod submission, then the existing parent opens the shell and reads
/// the original install receipt. The body is the nonce. The shell URL and the
/// parent origin must already be on that one entry and share one HTTPS host.
/// The card's entries do not carry parentOrigin, nonce, or a shell URL, so that
/// launch stays closed and the original receipt read stays available. Player
/// advanced/start and a payment native-context are not the ticket. This type
/// does not invent a domain, a certificate, a zip, or an approval.
public struct H5LaunchProducer: Equatable {
    public struct EntryLaunch: Equatable, Sendable {
        public let parentOrigin: String?
        public let nonce: String?
        public let shellURL: URL?
        public let mainToken: String?
        public init(parentOrigin: String? = nil, nonce: String? = nil, shellURL: URL? = nil, mainToken: String? = nil) {
            self.parentOrigin = parentOrigin
            self.nonce = nonce
            self.shellURL = shellURL
            self.mainToken = mainToken
        }
        public static let absent = EntryLaunch()
    }

    /// ACTIVE license row named by the card: licenseId, moduleId, purchasedVersionId,
    /// contentHash, termsHash. purchasedVersionId is the install release id.
    /// The author submission request id is not this install identity.
    public struct OwnedLicenseInstall: Equatable, Sendable {
        public let requestID: String
        public let status: String
        public let identity: WorkshopInstallIdentity
        public let launch: EntryLaunch
        public var licenseId: String { identity.licenseId }
        public var moduleId: String { identity.moduleId }
        public var purchasedVersionId: String { identity.releaseId }
        public var contentHash: String { identity.contentHash }
        public var termsHash: String { identity.termsHash }

        public init?(requestID: String, licenseId: String, moduleId: String, purchasedVersionId: String,
                     contentHash: String, termsHash: String, status: String, launch: EntryLaunch = .absent) {
            guard status == "ACTIVE",
                  WorkshopOriginalInstallConsumer.canonicalRequestID(requestID) != nil,
                  let identity = WorkshopInstallIdentity(licenseId: licenseId, moduleId: moduleId,
                                                        releaseId: purchasedVersionId, contentHash: contentHash,
                                                        termsHash: termsHash) else { return nil }
            self.requestID = requestID
            self.status = status
            self.identity = identity
            self.launch = launch
        }
    }

    /// Author qmod source submission. It is not the player challenge identity
    /// and it is not the install receipt id.
    public struct AuthorSubmission: Equatable, Sendable {
        public let requestID: String
        public let launch: EntryLaunch
        public init?(requestID: String, launch: EntryLaunch = .absent) {
            guard WorkshopOriginalInstallConsumer.canonicalRequestID(requestID) != nil else { return nil }
            self.requestID = requestID
            self.launch = launch
        }
    }

    /// Player advanced entry named by the card. It is not an H5 ticket.
    public struct PlayerAdvancedStart: Equatable, Sendable {
        public let activityID: Int
        public let topicID: Int
        public let nodeID: Int
        public init(activityID: Int, topicID: Int, nodeID: Int) {
            self.activityID = activityID
            self.topicID = topicID
            self.nodeID = nodeID
        }
    }

    /// Payment native-context. It is not an H5 ticket.
    public struct PaymentNativeContext: Equatable, Sendable {
        public let values: [String: String]
        public init(values: [String: String]) { self.values = values }
    }

    public enum Close: Equatable, Sendable {
        case missingLaunchFields
        case conflictingLaunchFields
        case hostMismatch
        case advancedStartRefused
        case paymentNativeContextRefused
    }

    public let owned: OwnedLicenseInstall
    public let author: AuthorSubmission
    public private(set) var entry: WorkshopInstallRecoverEntry
    public private(set) var parent: H5ShellParentFlow
    public private(set) var launchClosed: Close?
    public private(set) var presentedLaunch: H5LaunchDescription?
    public private(set) var presentedShellURL: URL?
    public private(set) var receipt: WorkshopOriginalInstallFact?
    public var opensZip: Bool { entry.opensZip }
    public var clientResultIsServerPass: Bool { entry.clientResultIsServerPass }

    public init?(owned: OwnedLicenseInstall, author: AuthorSubmission,
                 entry: WorkshopInstallRecoverEntry = WorkshopInstallRecoverEntry()) {
        guard owned.requestID != author.requestID else { return nil }
        self.owned = owned
        self.author = author
        self.entry = entry
        self.parent = H5ShellParentFlow(requestID: owned.requestID, entry: entry)
    }

    /// One-time POST. Nil closes only the launch. The receipt read stays available.
    @discardableResult
    public mutating func produce() -> URLRequest? {
        presentedLaunch = nil
        presentedShellURL = nil
        switch chooseTicket() {
        case .missing:
            launchClosed = .missingLaunchFields
            return nil
        case .conflict:
            launchClosed = .conflictingLaunchFields
            return nil
        case .ready(let ticket):
            return post(ticket)
        }
    }

    private mutating func post(_ ticket: Ticket) -> URLRequest? {
        if Self.mentionsAdvancedStart(ticket.origin) || Self.mentionsAdvancedStart(ticket.shell) {
            launchClosed = .advancedStartRefused
            return nil
        }
        if Self.mentionsPaymentNativeContext(ticket.origin) || Self.mentionsPaymentNativeContext(ticket.shell) {
            launchClosed = .paymentNativeContextRefused
            return nil
        }
        guard let launch = H5LaunchDescription(parentOrigin: ticket.origin, nonce: ticket.nonce, mainToken: ticket.mainToken) else {
            launchClosed = .missingLaunchFields
            return nil
        }
        guard let request = H5ShellParentFlow.loadRequest(shellURL: ticket.shell, launch: launch),
              request.httpMethod == "POST",
              Self.bodyIsNonceOnly(request, nonce: launch.nonce) else {
            launchClosed = .hostMismatch
            return nil
        }
        launchClosed = nil
        presentedLaunch = launch
        presentedShellURL = ticket.shell
        return request
    }

    /// advanced/start is not the shell ticket. The receipt read stays available.
    @discardableResult
    public mutating func refuseAdvancedStart(_ start: PlayerAdvancedStart) -> URLRequest? {
        _ = (start.activityID, start.topicID, start.nodeID)
        presentedLaunch = nil
        presentedShellURL = nil
        launchClosed = .advancedStartRefused
        return nil
    }

    /// A payment native-context is not the shell ticket. The receipt read stays available.
    @discardableResult
    public mutating func refusePaymentNativeContext(_ context: PaymentNativeContext) -> URLRequest? {
        _ = context.values
        presentedLaunch = nil
        presentedShellURL = nil
        launchClosed = .paymentNativeContextRefused
        return nil
    }

    /// Opens the existing parent when the POST exists, then reads the original
    /// install receipt for the owned request id. A closed launch still reads.
    @discardableResult
    public mutating func readOriginalReceipt(identity: WorkshopInstallIdentity,
                                            source: any WorkshopOriginalInstallReading) async throws -> WorkshopOriginalInstallFact {
        guard identity == owned.identity else { throw WorkshopOriginalInstallError.invalidRequest }
        if presentedLaunch == nil && launchClosed == nil {
            _ = produce()
        }
        if launchClosed == nil, let launch = presentedLaunch, let shellURL = presentedShellURL {
            parent = H5ShellParentFlow(requestID: owned.requestID, entry: entry)
            guard parent.open(shellURL: shellURL, launch: launch) != nil else {
                launchClosed = .hostMismatch
                presentedLaunch = nil
                presentedShellURL = nil
                return try await readClosed(identity: identity, source: source)
            }
            let fact = try await parent.readOriginalReceipt(identity: identity, source: source)
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

    private struct Ticket: Equatable {
        let origin: String
        let nonce: String
        let shell: URL
        let mainToken: String?
    }

    private enum TicketChoice {
        case ready(Ticket)
        case missing
        case conflict
    }

    private func chooseTicket() -> TicketChoice {
        if Self.isPartial(owned.launch) || Self.isPartial(author.launch) { return .missing }
        switch (Self.ticket(owned.launch), Self.ticket(author.launch)) {
        case let (left?, right?) where left != right:
            return .conflict
        case let (left?, _?):
            return .ready(left)
        case let (left?, nil):
            return .ready(left)
        case let (nil, right?):
            return .ready(right)
        case (nil, nil):
            return .missing
        }
    }

    private static func isPartial(_ launch: EntryLaunch) -> Bool {
        let count = [launch.parentOrigin != nil, launch.nonce != nil, launch.shellURL != nil].filter { $0 }.count
        return count != 0 && count != 3
    }

    private static func ticket(_ launch: EntryLaunch) -> Ticket? {
        guard !isPartial(launch),
              let origin = launch.parentOrigin, !origin.isEmpty,
              let nonce = launch.nonce, !nonce.isEmpty,
              let shell = launch.shellURL else { return nil }
        return Ticket(origin: origin, nonce: nonce, shell: shell, mainToken: launch.mainToken)
    }

    private static func bodyIsNonceOnly(_ request: URLRequest, nonce: String) -> Bool {
        guard let encoded = nonce.addingPercentEncoding(withAllowedCharacters: .alphanumerics), !encoded.isEmpty,
              request.httpBody == Data("nonce=\(encoded)".utf8) else { return false }
        return true
    }

    private static func mentionsAdvancedStart(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("advanced/start") || lower.contains("/play/advanced")
    }

    private static func mentionsAdvancedStart(_ url: URL) -> Bool {
        mentionsAdvancedStart(url.absoluteString)
    }

    private static func mentionsPaymentNativeContext(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("native-context") || lower.contains("nativecontext")
            || lower.contains("native-dispatch") || lower.contains("nativedispatch")
    }

    private static func mentionsPaymentNativeContext(_ url: URL) -> Bool {
        mentionsPaymentNativeContext(url.absoluteString)
    }
}
