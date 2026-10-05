import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Source image messages use msgType=2 and content=the media URL. No media upload,
/// messaging mutation, additional card action, or invented message-info endpoint.
public struct SocialMessageMedia: Equatable {
    public let messageID: Int
    public let conversationID: Int
    public let url: URL
    public init(message: MessagingMessage) throws {
        guard message.isPayloadVisible, message.type == 2, let raw = SocialText.nonempty(message.content),
              let url = URL(string: raw), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              !host.contains(":"), !host.lowercased().hasSuffix(".local"), host.lowercased() != "localhost",
              !host.split(separator: ".").allSatisfy({ Int($0) != nil }) else { throw SocialMediaFailure.invalidURL }
        self.messageID = message.id; self.conversationID = message.conversationID; self.url = url
    }
}
public enum SocialMediaFailure: Error, Equatable { case invalidURL, originNotApproved, tooLarge, notImage, unavailable }
/// Media requests must use the app's no-redirect transport, with no credentials/cookies.
/// Approved origins are explicit deployment configuration; no wildcard storage hosts.
public struct SocialMessageMediaService {
    public static let maximumBytes = 12 * 1024 * 1024
    private let approvedOrigins: Set<String>
    private let transport: any HTTPTransport
    private let authorize: (@MainActor (SocialMessageMedia) async throws -> Void)?
    public init(approvedOrigins: Set<String>, transport: any HTTPTransport,
                authorize: (@MainActor (SocialMessageMedia) async throws -> Void)? = nil) {
        self.approvedOrigins = approvedOrigins; self.transport = transport; self.authorize = authorize
    }
    public static func origin(_ url: URL) -> String? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme?.lowercased() == "https", let host = c.host, c.user == nil, c.password == nil else { return nil }
        return "https://\(host.lowercased())" + (c.port.map { $0 == 443 ? "" : ":\($0)" } ?? "")
    }
    public func image(_ media: SocialMessageMedia) async throws -> Data {
        guard let origin = Self.origin(media.url), approvedOrigins.contains(origin) else { throw SocialMediaFailure.originNotApproved }
        try Task.checkCancellation()
        try await authorize?(media)
        try Task.checkCancellation()
        var request = URLRequest(url: media.url)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(status) else { throw SocialMediaFailure.unavailable }
        guard data.count <= Self.maximumBytes else { throw SocialMediaFailure.tooLarge }
        // Signature gate before UI decoding. Size-limited transport remains an enablement
        // prerequisite because HTTPTransport returns a fully buffered Data value.
        let prefix = Array(data.prefix(12))
        let jpeg = prefix.starts(with: [0xff, 0xd8, 0xff])
        let png = prefix.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        let gif = prefix.starts(with: Array("GIF87a".utf8)) || prefix.starts(with: Array("GIF89a".utf8))
        let webp = prefix.count >= 12 && Array(prefix[0..<4]) == Array("RIFF".utf8) && Array(prefix[8..<12]) == Array("WEBP".utf8)
        guard jpeg || png || gif || webp else { throw SocialMediaFailure.notImage }
        // The production factory rechecks current conversation access and exact URL.
        // Bytes never reach the view if a message is removed or permission is lost.
        try await authorize?(media)
        try Task.checkCancellation()
        return data
    }
}
@MainActor public protocol SocialMessageMediaReading: AnyObject {
    var identity: MessagingReadIdentity? { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    func image(_ media: SocialMessageMedia, expectedIdentity: MessagingReadIdentity) async throws -> Data
}
@MainActor public final class SocialMessageMediaReader: SocialMessageMediaReading {
    private let serviceProvider: () -> SocialMessageMediaService?
    private let currentIdentity: () -> MessagingReadIdentity?
    private let currentContext: () -> RuntimeDependencyContext?
    private let requiresContext: Bool
    private let onUnauthorized: (MessagingReadIdentity) -> Void
    public var identity: MessagingReadIdentity? { currentIdentity() }
    public var isConfigured: Bool { (!requiresContext || currentContext() != nil) && serviceProvider() != nil }
    public var isOfflineExample: Bool { false }
    public init(service: SocialMessageMediaService?, currentIdentity: @escaping () -> MessagingReadIdentity?,
                onUnauthorized: @escaping (MessagingReadIdentity) -> Void = { _ in }) {
        self.serviceProvider = { service }; self.currentIdentity = currentIdentity; self.onUnauthorized = onUnauthorized
        self.currentContext = { nil }; self.requiresContext = false
    }
    public init(serviceProvider: @escaping () -> SocialMessageMediaService?, currentIdentity: @escaping () -> MessagingReadIdentity?,
                currentContext: @escaping () -> RuntimeDependencyContext?,
                onUnauthorized: @escaping (MessagingReadIdentity) -> Void = { _ in }) {
        self.serviceProvider = serviceProvider; self.currentIdentity = currentIdentity; self.onUnauthorized = onUnauthorized
        self.currentContext = currentContext; self.requiresContext = true
    }
    public func image(_ media: SocialMessageMedia, expectedIdentity: MessagingReadIdentity) async throws -> Data {
        try Task.checkCancellation()
        guard identity == expectedIdentity else { throw APIError.unauthorized }
        let context = currentContext()
        guard !requiresContext || context != nil else { throw APIError.notConfigured }
        guard let service = serviceProvider() else { throw APIError.notConfigured }
        do {
            let data = try await service.image(media)
            // Final MainActor check covers the window after the service's last
            // transport/readback check, including unchanged account/epoch identities.
            try Task.checkCancellation()
            guard currentContext() == context, identity == expectedIdentity else { throw CancellationError() }
            return data
        } catch {
            guard !Task.isCancelled, currentContext() == context, identity == expectedIdentity else { throw CancellationError() }
            if error as? APIError == .unauthorized || (error as? MessagingReadFailure)?.isUnauthorized == true {
                onUnauthorized(expectedIdentity)
                throw APIError.unauthorized
            }
            throw error
        }
    }
}
