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
        // Never surface server text/body or underlying transport error to UI/telemetry.
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.code == 200, let value = envelope.data else { throw PrivateHomeIssue.unavailable }
        return value
    }
}
