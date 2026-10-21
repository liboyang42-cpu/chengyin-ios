import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only CITY fairness. A missing grant, 401, 403, 503, empty body, or unknown
/// status is a distinct failure. None of those become a ratio.
public enum CityFairnessFailure: String, Equatable, Error, Sendable {
    case unauthorized, forbidden, unavailable, malformed, unknown
}

public struct CityFairnessOuting: Decodable, Equatable, Identifiable, Sendable {
    public let outingId, title: String
    public var id: String { outingId }
}

public struct CityFairnessPage: Equatable, Sendable {
    public let numerator, denominator, sampleCount: Int
    public let asOf: Int64
    public let metricVersion: String
    public let outings: [CityFairnessOuting]
    public let nextCursor: String?
    public var ratioText: String { "\(numerator)/\(denominator)" }
}

public struct CityFairnessGap: Equatable, Sendable {
    public let reason: String
    public let sampleCount: Int?
    public let asOf: Int64?
    public let metricVersion: String?
}

public struct CityFairnessEvidence: Equatable, Sendable {
    public let outingId, text, metricVersion: String
    public let asOf: Int64
}

public enum CityFairnessScreen: Equatable, Sendable {
    case blocked, loading
    case missingConfig(String)
    case noMatureSample(CityFairnessGap)
    case unknown(String?)
    case mature(CityFairnessPage)
    case failed(CityFairnessFailure)
}

/// Revocable read lease. It is not issued by login, and it does not authorize a write.
@available(macOS 14.0, *)
@MainActor @Observable public final class CityFairnessReadApproval {
    public let context: RuntimeDependencyContext
    public let regionID: String
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, regionID: String, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role), context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token), CityFairnessRoute.validID(regionID),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.regionID = regionID; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            let remaining = max(0, min(expiresAt.timeIntervalSinceNow, 86_400))
            do { if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }; try Task.checkCancellation() } catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
}

public struct CityFairnessRoute: Equatable {
    public enum Kind: String { case page = "fairness", outing = "fairness/outing" }
    public let kind: Kind
    public let regionID: String
    public let cursor: String?
    public let outingID: String?
    public init(page regionID: String, cursor: String? = nil) throws {
        guard Self.validID(regionID), cursor.map(Self.validCursor) != false else { throw APIError.invalidRequest }
        kind = .page; self.regionID = regionID; self.cursor = cursor; outingID = nil
    }
    public init(outing regionID: String, outingID: String) throws {
        guard Self.validID(regionID), Self.validID(outingID) else { throw APIError.invalidRequest }
        kind = .outing; self.regionID = regionID; cursor = nil; self.outingID = outingID
    }
    public func request(baseURL: URL, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let configuration = try APIConfiguration(baseURL: baseURL)
        guard var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/city-game/" + kind.rawValue), resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        var fields = ["regionId": regionID]
        if let cursor { fields["cursor"] = cursor }
        if let outingID { fields["outingId"] = outingID }
        components.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json", let url = request.url, url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems,
              items.count == Set(items.map(\.name)).count else { return nil }
        var values: [String: String] = [:]
        for item in items { guard let value = item.value else { return nil }; values[item.name] = value }
        let path = url.path
        let page = baseURL.appendingPathComponent("api/city-game/fairness").path
        let outing = baseURL.appendingPathComponent("api/city-game/fairness/outing").path
        guard let region = values["regionId"], Self.validID(region) else { return nil }
        if path == outing {
            guard Set(values.keys) == ["regionId", "outingId"], Self.validID(values["outingId"] ?? "") else { return nil }
            kind = .outing; regionID = region; cursor = nil; outingID = values["outingId"]
        } else if path == page {
            let keys = Set(values.keys)
            guard keys == ["regionId"] || keys == ["regionId", "cursor"], values["cursor"].map(Self.validCursor) != false else { return nil }
            kind = .page; regionID = region; cursor = values["cursor"]; outingID = nil
        } else { return nil }
        guard let canonical = try? self.request(baseURL: baseURL, token: "synthetic-token"),
              canonical.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true else { return nil }
    }
    static func validID(_ value: String) -> Bool { value.range(of: "\\A[A-Za-z0-9][A-Za-z0-9_-]{0,95}\\z", options: .regularExpression) != nil }
    static func validCursor(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 2048 && value.range(of: "\\A[A-Za-z0-9._~-]{1,2048}\\z", options: .regularExpression) != nil }
    static func validText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= limit && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

public enum CityFairnessWire {
    public static func page(data: Data, status: Int, regionID: String) throws -> CityFairnessScreen {
        try screen(decode(data, status: status), regionID: regionID)
    }
    public static func evidence(data: Data, status: Int, regionID: String, outingID: String) throws -> CityFairnessEvidence {
        let payload = try decode(data, status: status)
        guard payload.contract == contract, payload.scope == "CITY", payload.regionId == regionID, payload.status == "EVIDENCE",
              let row = payload.evidence, row.outingId == outingID, CityFairnessRoute.validText(row.text, limit: 2_000),
              let asOf = stamp(row.asOf), let version = version(row.metricVersion) else { throw CityFairnessFailure.malformed }
        return CityFairnessEvidence(outingId: outingID, text: row.text, metricVersion: version, asOf: asOf)
    }

    private static let contract = "CITY_FAIRNESS_READ_V1"
    private static func decode(_ data: Data, status: Int) throws -> Payload {
        if status == 401 { throw CityFairnessFailure.unauthorized }
        if status == 403 { throw CityFairnessFailure.forbidden }
        if status == 503 { throw CityFairnessFailure.unavailable }
        guard (200..<300).contains(status), !data.isEmpty else { throw CityFairnessFailure.malformed }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw CityFairnessFailure.malformed }
        if envelope.code == 401 { throw CityFairnessFailure.unauthorized }
        if envelope.code == 403 { throw CityFairnessFailure.forbidden }
        if envelope.code == 503 { throw CityFairnessFailure.unavailable }
        guard envelope.code == 200, let payload = envelope.data else { throw CityFairnessFailure.malformed }
        return payload
    }
    private static func screen(_ payload: Payload, regionID: String) throws -> CityFairnessScreen {
        guard payload.contract == contract, payload.scope == "CITY", payload.regionId == regionID else { throw CityFairnessFailure.malformed }
        switch payload.status {
        case "MISSING_CONFIG":
            guard let reason = reason(payload.missingReason), payload.numerator == nil, payload.denominator == nil else { throw CityFairnessFailure.malformed }
            return .missingConfig(reason)
        case "NO_MATURE_SAMPLE":
            guard let reason = reason(payload.missingReason), payload.numerator == nil, payload.denominator == nil else { throw CityFairnessFailure.malformed }
            return .noMatureSample(CityFairnessGap(reason: reason, sampleCount: try count(payload.sampleCount, required: false), asOf: try optionalStamp(payload.asOf), metricVersion: try optionalVersion(payload.metricVersion)))
        case "UNKNOWN":
            guard payload.numerator == nil, payload.denominator == nil else { throw CityFairnessFailure.malformed }
            guard let raw = payload.missingReason else { return .unknown(nil) }
            guard let text = reason(raw) else { throw CityFairnessFailure.malformed }
            return .unknown(text)
        case "MATURE":
            guard let numerator = payload.numerator, let denominator = payload.denominator, denominator > 0, numerator >= 0,
                  numerator <= 1_000_000, denominator <= 1_000_000,
                  let sampleCount = try count(payload.sampleCount, required: true),
                  let asOf = stamp(payload.asOf), let version = version(payload.metricVersion),
                  let outings = payload.outings, outings.count <= 50, Set(outings.map(\.outingId)).count == outings.count,
                  outings.allSatisfy({ CityFairnessRoute.validID($0.outingId) && CityFairnessRoute.validText($0.title, limit: 160) }) else { throw CityFairnessFailure.malformed }
            let cursor = try cursor(payload.nextCursor)
            return .mature(CityFairnessPage(numerator: numerator, denominator: denominator, sampleCount: sampleCount, asOf: asOf, metricVersion: version, outings: outings, nextCursor: cursor))
        default:
            throw CityFairnessFailure.unknown
        }
    }
    private static func reason(_ value: String?) -> String? { value.flatMap { CityFairnessRoute.validText($0, limit: 160) ? $0 : nil } }
    private static func version(_ value: String?) -> String? { value.flatMap { $0.range(of: "\\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\\z", options: .regularExpression) != nil ? $0 : nil } }
    private static func stamp(_ value: Int64?) -> Int64? { value.flatMap { (0...253_402_300_799_000).contains($0) ? $0 : nil } }
    private static func optionalStamp(_ value: Int64?) throws -> Int64? {
        guard let value else { return nil }
        guard let stamped = stamp(value) else { throw CityFairnessFailure.malformed }
        return stamped
    }
    private static func optionalVersion(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard let parsed = version(value) else { throw CityFairnessFailure.malformed }
        return parsed
    }
    private static func count(_ value: Int?, required: Bool) throws -> Int? {
        if value == nil { if required { throw CityFairnessFailure.malformed }; return nil }
        guard let value, (0...1_000_000).contains(value) else { throw CityFairnessFailure.malformed }
        return value
    }
    private static func cursor(_ value: String?) throws -> String? {
        if value == nil { return nil }
        guard let value, CityFairnessRoute.validCursor(value) else { throw CityFairnessFailure.malformed }
        return value
    }

    private struct Envelope: Decodable { let code: Int; let data: Payload? }
    private struct EvidenceRow: Decodable { let outingId, text, metricVersion: String; let asOf: Int64 }
    private struct Payload: Decodable {
        let contract, scope, status: String
        let regionId: String?
        let numerator, denominator, sampleCount: Int?
        let asOf: Int64?
        let metricVersion, missingReason, nextCursor: String?
        let outings: [CityFairnessOuting]?
        let evidence: EvidenceRow?
    }
}

@available(macOS 14.0, *)
@MainActor @Observable public final class CityFairnessReader {
    public private(set) var screen: CityFairnessScreen = .blocked
    public private(set) var refreshing = false
    public private(set) var evidence: CityFairnessEvidence?
    public private(set) var evidenceFailure: CityFairnessFailure?
    public private(set) var refreshFailure: CityFairnessFailure?
    private let approval: CityFairnessReadApproval?
    private let transport: any HTTPTransport
    private let isCurrent: () -> Bool
    private let onUnauthorized: () -> Void
    private var generation = UUID()
    private var evidenceGeneration = UUID()
    private var page: CityFairnessPage?
    @ObservationIgnored private var task: Task<Void, Never>?
    public var isConfigured: Bool {
        guard let approval else { return false }
        return approval.matches(approval.context) && isCurrent()
    }
    public init(approval: CityFairnessReadApproval?, transport: any HTTPTransport, isCurrent: @escaping () -> Bool, onUnauthorized: @escaping () -> Void = {}) {
        self.approval = approval; self.transport = transport; self.isCurrent = isCurrent; self.onUnauthorized = onUnauthorized
    }
    deinit { task?.cancel() }
    public func restoreSameQuery() async { await reload(cursor: nil, preserve: true) }
    public func refresh() async { await reload(cursor: nil, preserve: true) }
    public func nextPage() async {
        guard let page, let cursor = page.nextCursor else { return }
        await reload(cursor: cursor, preserve: true)
    }
    public func loadEvidence(_ outingID: String) async {
        guard CityFairnessRoute.validID(outingID) else { evidence = nil; evidenceFailure = .malformed; return }
        let stamp = UUID(); evidenceGeneration = stamp
        evidence = nil; evidenceFailure = nil
        guard let approval, approval.matches(approval.context), isCurrent() else { evidenceFailure = .malformed; return }
        do {
            let route = try CityFairnessRoute(outing: approval.regionID, outingID: outingID)
            let request = try route.request(baseURL: approval.context.baseURL, token: approval.context.session.token)
            let (data, status) = try await transport.send(request)
            guard evidenceGeneration == stamp, approval.matches(approval.context), isCurrent() else { return }
            evidence = try CityFairnessWire.evidence(data: data, status: status, regionID: approval.regionID, outingID: outingID)
        } catch {
            guard evidenceGeneration == stamp else { return }
            evidenceFailure = Self.failure(error)
            if evidenceFailure == .unauthorized, isCurrent() { onUnauthorized() }
        }
    }
    public func clearEvidence() { evidenceGeneration = UUID(); evidence = nil; evidenceFailure = nil }

    private func reload(cursor: String?, preserve: Bool) async {
        guard !Task.isCancelled else { return }
        let stamp = UUID(); generation = stamp; task?.cancel()
        guard let approval, approval.matches(approval.context), isCurrent() else {
            page = nil; screen = .blocked; refreshing = false; refreshFailure = nil; return
        }
        refreshFailure = nil
        if page == nil || !preserve { screen = .loading }
        refreshing = page != nil
        let job = Task { @MainActor in await self.fetch(stamp: stamp, cursor: cursor) }
        task = job
        await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
        if generation == stamp { task = nil }
    }
    private func fetch(stamp: UUID, cursor: String?) async {
        guard let approval else { return }
        do {
            let route = try CityFairnessRoute(page: approval.regionID, cursor: cursor)
            let request = try route.request(baseURL: approval.context.baseURL, token: approval.context.session.token)
            let (data, status) = try await transport.send(request)
            guard generation == stamp, approval.matches(approval.context), isCurrent(), !Task.isCancelled else { return }
            let decoded = try CityFairnessWire.page(data: data, status: status, regionID: approval.regionID)
            if let cursor {
                guard case .mature(let incoming) = decoded, let current = page,
                      incoming.numerator == current.numerator, incoming.denominator == current.denominator,
                      incoming.sampleCount == current.sampleCount, incoming.metricVersion == current.metricVersion else { throw CityFairnessFailure.malformed }
                var seen = Set(current.outings.map(\.outingId))
                let added = incoming.outings.filter { seen.insert($0.outingId).inserted }
                let merged = CityFairnessPage(numerator: current.numerator, denominator: current.denominator, sampleCount: current.sampleCount, asOf: incoming.asOf, metricVersion: current.metricVersion, outings: current.outings + added, nextCursor: incoming.nextCursor)
                page = merged
                screen = .mature(merged)
            } else {
                if case .mature(let incoming) = decoded { page = incoming } else { page = nil }
                screen = decoded
            }
            refreshing = false
        } catch {
            guard generation == stamp else { return }
            let failure = Self.failure(error)
            if failure == .unauthorized { page = nil; refreshFailure = nil; screen = .failed(.unauthorized); if isCurrent(), !Task.isCancelled { onUnauthorized() } }
            else if page == nil { screen = .failed(failure) }
            else { refreshFailure = failure }
            refreshing = false
        }
    }
    private static func failure(_ error: Error) -> CityFairnessFailure {
        if let failure = error as? CityFairnessFailure { return failure }
        if let api = error as? APIError {
            if api == .unauthorized || api == .httpStatus(401) { return .unauthorized }
            if api == .httpStatus(403) { return .forbidden }
            if api == .httpStatus(503) { return .unavailable }
        }
        return .malformed
    }
}
