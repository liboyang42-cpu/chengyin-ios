import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public struct PrivateHomeService: PrivateHomeServing {
    public static let path = "api/native/home"
    private let api: APIConfiguration
    private let transport: any HTTPTransport
    private let owner: PlayExperienceSession
    private let current: () -> PlayExperienceSession?
    private let enabled: Bool
    public init(api: APIConfiguration, transport: any HTTPTransport, owner: PlayExperienceSession,
                enabled: Bool = false, current: @escaping () -> PlayExperienceSession?) {
        self.api = api; self.transport = transport; self.owner = owner; self.current = current; self.enabled = enabled
    }
    public func load() async throws -> PrivateHomeSnapshot {
        let value: PrivateHomeSnapshot = try await request(method: "GET", body: nil)
        try value.validate(); return value
    }
    public func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt {
        try mutation.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let value: PrivateHomeReceipt = try await request(method: mutation.method, body: encoder.encode(mutation))
        try value.validate(for: mutation); return value
    }
    /// Preserve the original BigDecimal scale/range contract before Foundation can
    /// round a long JSON number into a seemingly valid six-place private point.
    private static func validateSnapshotCoordinateTokens(_ root: ContentDraftJSON) throws {
        guard case .object(let envelope) = root,
              envelope[Data("code".utf8)] == .number(negative: false, digits: "2", exponent: 2),
              case .object(let snapshot)? = envelope[Data("data".utf8)],
              snapshot[Data("status".utf8)] == .string(Data("ACTIVE".utf8)) else { return }
        guard validSnapshotCoordinate(snapshot[Data("latitude".utf8)], limit: 90),
              validSnapshotCoordinate(snapshot[Data("longitude".utf8)], limit: 180) else { throw PrivateHomeIssue.invalid }
    }
    private static func validSnapshotCoordinate(_ token: ContentDraftJSON?, limit: Decimal) -> Bool {
        // The existing lossless parser removes insignificant zeros, retaining every
        // nonzero digit. A valid bounded point then has at most nine significant digits.
        guard case .number(let negative, let digits, let exponent)? = token,
              exponent >= -6, exponent <= 2, digits.count + exponent <= 3 else { return false }
        guard let value = Decimal(string: (negative ? "-" : "") + digits + "e" + String(exponent),
                                  locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { return false }
        return value >= -limit && value <= limit
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private func gate() throws {
        guard enabled else { throw PrivateHomeIssue.disabled }
        guard current() == owner else { throw PrivateHomeIssue.staleSession }
    }
    private func request<T: Decodable>(method: String, body: Data?) async throws -> T {
        try gate(); try Task.checkCancellation()
        var request = URLRequest(url: api.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = method; request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(owner.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, status) = try await transport.send(request)
        try gate(); try Task.checkCancellation()
        guard (200..<300).contains(status), data.count <= 32_768 else { throw PrivateHomeIssue.unavailable }
        // Reject ambiguous successful bodies before typed decoding can collapse duplicate keys.
        // Parse only within the existing size limit and decode the original bytes unchanged.
        guard let text = String(data: data, encoding: .utf8),
              let root = try? ContentDraftJSON.parse(text), case .object = root else { throw PrivateHomeIssue.invalid }
        if method == "GET" { try Self.validateSnapshotCoordinateTokens(root) }
        // Never surface server text/body or underlying transport error to UI/telemetry.
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.code == 200, let value = envelope.data else { throw PrivateHomeIssue.unavailable }
        return value
    }
}
