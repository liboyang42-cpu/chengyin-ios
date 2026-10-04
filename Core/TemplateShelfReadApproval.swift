import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently issued CN owned-template-read lease; no mutation or publishing authority.
/// Server owner scope remains authoritative. Default issuance is nil.
/// Revoke an old lease before removing/replacing it. Revocation cannot be reversed.
/// Authentication, display values, roles and other read grants cannot issue this lease.
@available(macOS 14.0, *)
@MainActor @Observable public final class TemplateShelfReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            // A queued MainActor task must not start the original duration again.
            // Wall-clock request checks remain authoritative throughout suspension.
            let remaining = Self.expiryDelay(until: expiresAt, now: Date())
            do {
                if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                try Task.checkCancellation()
            }
            catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    static func expiryDelay(until deadline: Date, now: Date) -> TimeInterval {
        max(0, min(deadline.timeIntervalSince(now), 86_400))
    }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
    /// Deterministic expiry seam for tests and foreground reconciliation. Never renews a lease.
    public func expireIfNeeded(now: Date = Date()) { if now >= expiresAt { revoke() } }
}

/// Canonical multipart bytes only. The fixed first100 write preflight is deliberately
/// not admitted by this read lease; page10 display is bounded to 100 pages / 1000 rows.
public enum TemplateShelfReadRoute: Equatable {
    case page(Int, keyword: String), detail(MemberPlayTemplateID)
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let body = request.httpBody, body.count <= 4096,
              let type = request.value(forHTTPHeaderField: "Content-Type"),
              type.hasPrefix("multipart/form-data; boundary="),
              let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard boundary.range(of: "^[A-Za-z0-9-]{1,70}$", options: .regularExpression) != nil else { return nil }
        // Parse only canonical framing, then rebuild with the actual request builder.
        // No generic form decoder, duplicate key collapse, file part or part-header variants.
        let ending = "--\(boundary)--\r\n"
        guard text.hasSuffix(ending) else { return nil }
        let chunks = String(text.dropLast(ending.count)).components(separatedBy: "--\(boundary)\r\n")
        guard chunks.first == "" else { return nil }
        var fields: [String: String] = [:]
        for chunk in chunks.dropFirst() {
            let header = "Content-Disposition: form-data; name=\""
            guard chunk.hasPrefix(header), chunk.hasSuffix("\r\n"),
                  let split = chunk.range(of: "\"\r\n\r\n") else { return nil }
            let keyStart = chunk.index(chunk.startIndex, offsetBy: header.count)
            guard split.lowerBound > keyStart else { return nil }
            let key = String(chunk[keyStart..<split.lowerBound])
            let value = String(chunk[split.upperBound...].dropLast(2))
            guard fields[key] == nil else { return nil }; fields[key] = value
        }
        let canonical: URLRequest
        if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/template/my-list").absoluteString.utf8) {
            guard Set(fields.keys) == ["is_quote", "keyword", "category_id", "pageNum", "pageSize"],
                  fields["is_quote"] == "", fields["category_id"] == "", fields["pageSize"] == "10",
                  let raw = fields["pageNum"], let page = Int(raw), raw == String(page),
                  (1...TemplateOwnShelfPage.maximumPages).contains(page), let keyword = fields["keyword"],
                  keyword.utf8.count <= 512, !keyword.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  let descriptor = try? TemplateOwnShelfPage.request(page: page, keyword: keyword),
                  let config = try? APIConfiguration(baseURL: baseURL),
                  let rebuilt = try? TemplateAuthoringWireRequestBuilder.make(descriptor, configuration: config,
                    token: "canonical-read", boundary: boundary) else { return nil }
            canonical = rebuilt; self = .page(page, keyword: keyword)
        } else if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/template/myinfo").absoluteString.utf8) {
            guard Set(fields.keys) == ["id"], let raw = fields["id"], let value = Int(raw), raw == String(value),
                  let id = MemberPlayTemplateID(rawValue: value),
                  let rebuilt = try? AuthRequestBuilder.makeFormRequest(url: url, fields: ["id": raw], token: nil, boundary: boundary) else { return nil }
            canonical = rebuilt; self = .detail(id)
        } else { return nil }
        guard canonical.httpBody == body else { return nil }
    }
}

/// Dedicated read transport, never conforming to the authoring mutation transport.
@available(macOS 14.0, *)
@MainActor public final class TemplateShelfReadTransport {
    private let configuration: APIConfiguration
    private let http: any HTTPTransport
    private let approval: TemplateShelfReadApproval
    private let current: () -> RuntimeDependencyContext?
    private let onUnauthorized: () -> Void
    public init(configuration: APIConfiguration, http: any HTTPTransport, approval: TemplateShelfReadApproval,
                current: @escaping () -> RuntimeDependencyContext?, onUnauthorized: @escaping () -> Void = {}) {
        self.configuration = configuration; self.http = http; self.approval = approval
        self.current = current; self.onUnauthorized = onUnauthorized
    }
    public var available: Bool { current().map { approval.matches($0) } == true }
    public var scope: UUID { approval.revision }
    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let context = current(), approval.matches(context),
              context.baseURL.absoluteString == configuration.baseURL.absoluteString,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              TemplateShelfReadRoute(request: request, baseURL: configuration.baseURL) != nil else { throw APIError.notConfigured }
        do {
            try Task.checkCancellation()
            let result = try await http.send(request)
            guard !Task.isCancelled, current().map({ ContentDraftContextFence.matches(context, $0) && approval.matches($0) }) == true else { throw CancellationError() }
            // Validate envelope while still inside the lifetime fence so current 401
            // expires only this captured account, and stale errors never do so.
            try TemplateAuthoringContract.requireSuccess(result.0, httpStatus: result.1)
            return result
        } catch {
            guard !Task.isCancelled, current().map({ ContentDraftContextFence.matches(context, $0) && approval.matches($0) }) == true else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized() }
            throw error
        }
    }
    public func page(_ descriptor: TemplateAuthoringRequest) async throws -> (Data, Int) {
        guard available, !descriptor.mutates, let context = current(),
              case .form(let fields) = descriptor.body, let raw = fields["pageNum"], let page = Int(raw),
              let keyword = fields["keyword"], descriptor == (try? TemplateOwnShelfPage.request(page: page, keyword: keyword)) else { throw APIError.notConfigured }
        let request = try TemplateAuthoringWireRequestBuilder.make(descriptor, configuration: configuration, token: context.session.token)
        guard case .page? = TemplateShelfReadRoute(request: request, baseURL: configuration.baseURL) else { throw APIError.invalidRequest }
        return try await send(request)
    }
    public func detail(_ id: MemberPlayTemplateID) async throws -> MemberTemplateDetail {
        guard available, let context = current() else { throw APIError.notConfigured }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/template/myinfo"), fields: ["id": String(id.rawValue)], token: context.session.token)
        let (data, _) = try await send(request)
        let wire = try JSONDecoder().decode(PlayWireValue.self, from: data)
        let value = try wire["data"].decoded(MemberTemplateDetail.self)
        // This destination is the owned shelf, not the broader public-eligible myinfo
        // projection used elsewhere. Missing owner does not prove current ownership.
        guard value.id == id, value.memberID == context.session.accountID else { throw APIError.malformedResponse }
        return value
    }
}

@available(macOS 14.0, *)
@MainActor public final class OwnedMemberTemplateReader: MemberTemplateReading {
    private let transport: TemplateShelfReadTransport?
    private let authenticated: () -> Bool
    private let identity = UUID()
    private let invalidatedIdentity = UUID()
    public var scope: UUID { isConfigured ? identity : invalidatedIdentity }
    public var isAuthenticated: Bool { authenticated() }
    public var isConfigured: Bool { transport?.available == true }
    public init(transport: TemplateShelfReadTransport?, authenticated: @escaping () -> Bool) {
        self.transport = transport; self.authenticated = authenticated
    }
    public func memberTemplate(id: MemberPlayTemplateID) async throws -> MemberTemplateDetail {
        guard let transport, isConfigured else { throw APIError.notConfigured }
        return try await transport.detail(id)
    }
}
