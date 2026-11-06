import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Evidence-only GET grant; it cannot authorize either existing consent mutation chain.
public struct UsageConsentReadApproval: Equatable {
    public let market: RegionalMarket
    public let revision: UUID
    public let endpoint: OperationEndpointApproval
    public init(market: RegionalMarket, endpoint: OperationEndpointApproval, revision: UUID = UUID()) throws {
        guard !endpoint.paths.isEmpty, endpoint.paths.isSubset(of: Set(UsageConsentReadRoute.paths)) else { throw APIError.invalidConfiguration }
        self.market = market; self.endpoint = endpoint; self.revision = revision
    }
    public func allows(_ context: RuntimeDependencyContext, path: String) -> Bool {
        market == context.market && endpoint.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8)
            && endpoint.namespace.utf8.elementsEqual(context.session.namespace.utf8)
            && endpoint.accountID == context.session.accountID && endpoint.paths.contains(path)
    }
}
extension UsageConsentReadApproval {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision && lhs.market == rhs.market &&
            lhs.endpoint.baseURL.absoluteString.utf8.elementsEqual(rhs.endpoint.baseURL.absoluteString.utf8) &&
            lhs.endpoint.namespace.utf8.elementsEqual(rhs.endpoint.namespace.utf8) &&
            lhs.endpoint.accountID == rhs.endpoint.accountID && lhs.endpoint.paths == rhs.endpoint.paths
    }
}
public enum UsageConsentReadScope {
    public static func matches(_ current: RuntimeDependencyContext?, _ captured: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(current, captured) &&
            current?.session.role.utf8.elementsEqual(captured.session.role.utf8) == true &&
            captured.role.utf8.elementsEqual(captured.session.role.utf8)
    }
}
public struct UsageConsentReadRoute: Equatable {
    public static let history = "api/compliance/usage-records"
    public static let original = history + "/request"
    public static let paths = [history, original]
    public let path: String
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
        let items = parts.queryItems ?? []; parts.query = nil
        guard let path = Self.paths.first(where: { baseURL.appendingPathComponent($0) == parts.url }),
              Set(items.map(\.name)).count == items.count else { return nil }
        if path == Self.history {
            guard items.isEmpty || (items.count == 1 && items[0].name == "beforeId"
                && items[0].value.flatMap(Int.init).map({ $0 > 0 && String($0) == items[0].value }) == true) else { return nil }
        } else {
            guard items.count == 1, items[0].name == "requestId", Self.validKey(items[0].value) else { return nil }
        }
        self.path = path
    }
    public static func validKey(_ key: String?) -> Bool {
        guard let key else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && key.utf16.count <= 64
            && key.rangeOfCharacter(from: .controlCharacters) == nil
    }
}
public enum UsageConsentReadFailure: Error, Equatable { case unavailable, missing, failed, malformed, stale }
public struct UsageConsentEvidence: Decodable, Equatable, Identifiable {
    public let id: Int
    public let docType: String
    public let docVersion: String
    public let eventType: String
    public let requestId: String
    public let occurredAt: Int?
    /// Preserve raw milliseconds. An unsupported display range is not clamped into a false date.
    public var displayDate: Date? {
        guard let occurredAt, occurredAt >= 0, occurredAt < 1_000_000_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: Double(occurredAt) / 1000)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.occurredAt == rhs.occurredAt &&
            lhs.docType.utf8.elementsEqual(rhs.docType.utf8) && lhs.docVersion.utf8.elementsEqual(rhs.docVersion.utf8) &&
            lhs.eventType.utf8.elementsEqual(rhs.eventType.utf8) && lhs.requestId.utf8.elementsEqual(rhs.requestId.utf8)
    }
    func validate() throws {
        guard id > 0, ["privacy_policy", "user_service_agreement", "privacy", "user_agreement"].contains(docType),
              !docVersion.isEmpty, docVersion.utf16.count <= 32, ["AGREE", "REVOKE"].contains(eventType),
              UsageConsentReadRoute.validKey(requestId), occurredAt == nil || occurredAt! >= 0 else { throw UsageConsentReadFailure.malformed }
    }
}
public struct UsageConsentSourceDocument: Decodable, Equatable {
    public let docType: String
    public let version: String
    public let availability: String
    public let title: String?
    public let content: String?
    public let publishedAt: Int?
    func validate(record: UsageConsentEvidence) throws {
        guard docType.utf8.elementsEqual(record.docType.utf8), version.utf8.elementsEqual(record.docVersion.utf8),
              ["MISSING", "MISMATCH", "UNPUBLISHED", "INCOMPLETE", "SOURCE_AVAILABLE"].contains(availability) else { throw UsageConsentReadFailure.malformed }
        if availability == "SOURCE_AVAILABLE" {
            guard title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  let publishedAt, publishedAt >= 0 else { throw UsageConsentReadFailure.malformed }
        } else if title != nil || content != nil || publishedAt != nil { throw UsageConsentReadFailure.malformed }
    }
}
public struct UsageConsentEvidencePage: Decodable, Equatable {
    public let accountId: Int
    public let scene: String
    public let readOnly: Bool
    public let nativeMarketBinding: String
    public let items: [UsageConsentEvidence]
    public let nextBeforeId: Int?
    func validate(account: Int, before: Int?) throws {
        guard accountId == account, scene == "app_launch", readOnly, nativeMarketBinding == "UNPROVEN", items.count <= 50,
              Set(items.map(\.id)).count == items.count, Set(items.map { Data($0.requestId.utf8) }).count == items.count,
              zip(items, items.dropFirst()).allSatisfy({ $0.0.id > $0.1.id }),
              items.allSatisfy({ before == nil || $0.id < before! }),
              nextBeforeId == nil || (items.count == 50 && nextBeforeId == items.last?.id) else { throw UsageConsentReadFailure.malformed }
        try items.forEach { try $0.validate() }
    }
}
public struct UsageConsentOriginalEvidence: Decodable, Equatable {
    public let accountId: Int
    public let scene: String
    public let readOnly: Bool
    public let nativeMarketBinding: String
    public let record: UsageConsentEvidence
    public let latestRecordId: Int?
    public let document: UsageConsentSourceDocument
    func validate(account: Int, requestId: String) throws {
        guard accountId == account, scene == "app_launch", readOnly, nativeMarketBinding == "UNPROVEN",
              record.requestId.utf8.elementsEqual(requestId.utf8), latestRecordId == nil || latestRecordId! > 0 else { throw UsageConsentReadFailure.malformed }
        try record.validate(); try document.validate(record: record)
    }
}
@MainActor public protocol UsageConsentEvidenceReading {
    var isCurrent: Bool { get }
    func history(before: Int?) async throws -> UsageConsentEvidencePage
    func original(requestId: String) async throws -> UsageConsentOriginalEvidence
}
@MainActor public final class UsageConsentReadService: UsageConsentEvidenceReading {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let captured: RuntimeDependencyContext
    private let approval: UsageConsentReadApproval?
    private let current: () -> RuntimeDependencyContext?
    private let stillApproved: () -> Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, captured: RuntimeDependencyContext,
                approval: UsageConsentReadApproval?, current: @escaping () -> RuntimeDependencyContext?,
                stillApproved: @escaping () -> Bool = { true }) {
        self.configuration = configuration; self.transport = transport; self.captured = captured; self.approval = approval; self.current = current; self.stillApproved = stillApproved
    }
    public var isCurrent: Bool { UsageConsentReadScope.matches(current(), captured) && stillApproved() }
    public func history(before: Int? = nil) async throws -> UsageConsentEvidencePage {
        let value: UsageConsentEvidencePage = try await read(path: UsageConsentReadRoute.history,
            query: before.map { [URLQueryItem(name: "beforeId", value: String($0))] } ?? [])
        try value.validate(account: captured.session.accountID, before: before); return value
    }
    public func original(requestId: String) async throws -> UsageConsentOriginalEvidence {
        let value: UsageConsentOriginalEvidence = try await read(path: UsageConsentReadRoute.original,
            query: [URLQueryItem(name: "requestId", value: requestId)])
        try value.validate(account: captured.session.accountID, requestId: requestId); return value
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private func read<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        try Task.checkCancellation()
        guard isCurrent else { throw UsageConsentReadFailure.stale }
        guard configuration.baseURL.absoluteString.utf8.elementsEqual(captured.baseURL.absoluteString.utf8), approval?.allows(captured, path: path) == true else { throw UsageConsentReadFailure.unavailable }
        guard var parts = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw UsageConsentReadFailure.malformed }
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw UsageConsentReadFailure.malformed }
        var request = try AuthRequestBuilder.makeFormRequest(url: url, fields: [:], token: captured.session.token, includesBody: false)
        request.httpMethod = "GET"; request.httpBody = nil; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard UsageConsentReadRoute(request: request, baseURL: configuration.baseURL)?.path == path else { throw UsageConsentReadFailure.malformed }
        let result: (Data, Int)
        do { result = try await transport.send(request) }
        catch { guard isCurrent else { throw UsageConsentReadFailure.stale }; throw error }
        try Task.checkCancellation()
        guard isCurrent else { throw UsageConsentReadFailure.stale }
        guard (200..<300).contains(result.1) else { throw UsageConsentReadFailure.failed }
        guard result.0.count <= 8_388_608, let raw = String(data: result.0, encoding: .utf8),
              (try? ContentDraftJSON.parse(raw)) != nil else { throw UsageConsentReadFailure.malformed }
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: result.0)
        guard envelope.code != 404 else { throw UsageConsentReadFailure.missing }
        guard envelope.code == 200, let value = envelope.data else { throw UsageConsentReadFailure.failed }
        return value
    }
}

public struct UsageConsentReadPresentation: Equatable { fileprivate let id: UUID }
public struct UsageConsentReadIntent: Equatable {
    fileprivate let presentation: UsageConsentReadPresentation
    fileprivate let epoch: UInt64
}
@MainActor @Observable public final class UsageConsentReadCoordinator {
    private var storedItems: [UsageConsentEvidence] = []
    private var storedDetail: UsageConsentOriginalEvidence?
    private var storedNextBeforeId: Int?
    public private(set) var failure: UsageConsentReadFailure?
    public private(set) var busy = false
    private var storedLoaded = false
    /// An old controller cannot expose another account's cached evidence while the host retires its view.
    public var items: [UsageConsentEvidence] { active && service.isCurrent ? storedItems : [] }
    public var detail: UsageConsentOriginalEvidence? { active && service.isCurrent ? storedDetail : nil }
    public var nextBeforeId: Int? { active && service.isCurrent ? storedNextBeforeId : nil }
    public var loaded: Bool { active && service.isCurrent && storedLoaded }
    private let service: any UsageConsentEvidenceReading
    private var epoch: UInt64 = 0
    // Preserve direct API callers; the normal host installs and captures its own explicit presentation.
    private var presentation: UsageConsentReadPresentation? = .init(id: UUID())
    private var active = true
    public init(service: any UsageConsentEvidenceReading) { self.service = service }
    public func clear() { epoch &+= 1; storedItems = []; storedDetail = nil; storedNextBeforeId = nil; failure = nil; busy = false; storedLoaded = false }
    public func beginPresentation() -> UsageConsentReadPresentation {
        clear(); let value = UsageConsentReadPresentation(id: UUID()); presentation = value; active = true; return value
    }
    public func captureRead(_ value: UsageConsentReadPresentation) -> UsageConsentReadIntent? {
        guard !Task.isCancelled, active, presentation == value, service.isCurrent else { return nil }
        return .init(presentation: value, epoch: epoch)
    }
    public func isCurrent(_ value: UsageConsentReadIntent) -> Bool {
        !Task.isCancelled && active && presentation == value.presentation && epoch == value.epoch && service.isCurrent
    }
    public func suspend(_ value: UsageConsentReadPresentation) {
        guard presentation == value else { return }; active = false; clear()
    }
    public func resume(_ value: UsageConsentReadPresentation) -> Bool {
        guard presentation == value, service.isCurrent else { return false }; active = true; return true
    }
    public func endPresentation(_ value: UsageConsentReadPresentation) {
        guard presentation == value else { return }; retire()
    }
    public func retire() { presentation = nil; active = false; clear() }
    private func admitted(_ intent: UsageConsentReadIntent?) -> Bool {
        guard !Task.isCancelled, active, presentation != nil else { return false }
        if let intent { return isCurrent(intent) }
        return true
    }
    public func reload(more: Bool = false, intent: UsageConsentReadIntent? = nil) async {
        guard admitted(intent), !busy, !more || storedNextBeforeId != nil else { return }
        let before = more ? storedNextBeforeId : nil
        if !more { clear() } else { epoch &+= 1 }
        let stamp = epoch; busy = true; failure = nil
        do {
            let page = try await service.history(before: before)
            guard stamp == epoch, active, service.isCurrent, !Task.isCancelled else {
                if stamp == epoch { clear(); failure = .stale }; return
            }
            guard !more || (Set(storedItems.map(\.id)).isDisjoint(with: page.items.map(\.id)) &&
                Set(storedItems.map { Data($0.requestId.utf8) }).isDisjoint(with: page.items.map { Data($0.requestId.utf8) })) else {
                throw UsageConsentReadFailure.malformed
            }
            storedItems = more ? storedItems + page.items : page.items; storedNextBeforeId = page.nextBeforeId; storedLoaded = true
        } catch { if stamp == epoch { report(error) } }
        if stamp == epoch { busy = false }
    }
    public func read(_ requestId: String, intent: UsageConsentReadIntent? = nil) async {
        guard admitted(intent), !busy else { return }
        epoch &+= 1
        let stamp = epoch; busy = true; storedDetail = nil; failure = nil
        do {
            let value = try await service.original(requestId: requestId)
            guard stamp == epoch, active, service.isCurrent, !Task.isCancelled else {
                if stamp == epoch { clear(); failure = .stale }; return
            }
            if let original = storedItems.first(where: { $0.requestId.utf8.elementsEqual(requestId.utf8) }), original != value.record {
                throw UsageConsentReadFailure.malformed
            }
            storedDetail = value
        } catch { if stamp == epoch { report(error) } }
        if stamp == epoch { busy = false }
    }
    private func report(_ error: Error) {
        if !service.isCurrent || Task.isCancelled { clear(); failure = .stale }
        else { failure = error as? UsageConsentReadFailure ?? .failed }
    }
}
