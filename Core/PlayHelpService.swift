import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Production writes stay behind explicit capabilities; the default is dormant.
public enum PlayHelpCapability: Hashable { case read, use, skip }

/// F01 adapter for `/api/play/help`, `/use` and `/skip` (and the advanced-session twins).
public struct PlayHelpService {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    public let enabled: Set<PlayHelpCapability>

    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Set<PlayHelpCapability> = []) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
    }

    public func view(scope: PlayHelpScope, token: String) async throws -> PlayHelpView {
        guard scope.isValid else { throw APIError.invalidRequest }
        let raw = try await send(makeRequest(scope.basePath,
            query: [scope.ownerField: String(scope.ownerID), "nodeId": String(scope.nodeID)], body: nil, token: token), capability: .read)
        return try PlayHelpView(raw)
    }

    public func use(scope: PlayHelpScope, level: Int, requestID: String, token: String) async throws -> PlayHelpUseReceipt {
        guard scope.isValid, level > 0, Self.validRequestID(requestID) else { throw APIError.invalidRequest }
        let body: [String: PlayWireValue] = [scope.ownerField: .int(scope.ownerID), "nodeId": .int(scope.nodeID),
                                             "level": .int(level), "action": .string("HELP"), "requestId": .string(requestID)]
        let raw = try await send(makeRequest(scope.basePath + "/use", query: [:], body: body, token: token), capability: .use)
        return try PlayHelpUseReceipt(raw, expectedLevel: level)
    }

    public func skip(scope: PlayHelpScope, requestID: String, token: String) async throws -> PlayHelpSkipReceipt {
        guard scope.isValid, Self.validRequestID(requestID) else { throw APIError.invalidRequest }
        let body: [String: PlayWireValue] = [scope.ownerField: .int(scope.ownerID), "nodeId": .int(scope.nodeID),
                                             "requestId": .string(requestID)]
        let raw = try await send(makeRequest(scope.basePath + "/skip", query: [:], body: body, token: token), capability: .skip)
        return try PlayHelpSkipReceipt(raw)
    }

    static func validRequestID(_ value: String) -> Bool {
        (16...64).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }

    func makeRequest(_ path: String, query: [String: String], body: [String: PlayWireValue]?, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !query.isEmpty, var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.url = components.url
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(body)
        } else {
            request.httpMethod = "GET"
        }
        return request
    }

    /// One request only: no retry, no fallback. A lost response is `unknownResult`
    /// and the caller retries with the same request id.
    private func send(_ request: URLRequest, capability: PlayHelpCapability) async throws -> PlayWireValue {
        guard enabled.contains(capability) else { throw PlayExperienceError.disabled }
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        let envelope = try? JSONDecoder().decode(PlayWireValue.self, from: data)
        let code = envelope?["code"].tolerantInteger
        if status == 401 || code == 401 { throw PlayExperienceError.unauthorized }
        guard (200..<300).contains(status) else { throw PlayExperienceError.unknownResult }
        guard let code else { throw PlayExperienceError.malformed }
        guard code == 200 else { throw PlayExperienceError.rejected(code, envelope?["msg"].text) }
        return envelope?["data"] ?? .null
    }
}

/// Panel state for one node. Content shown comes only from server receipts.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayHelpCoordinator {
    public private(set) var view: PlayHelpView?
    public private(set) var contents: [Int: String] = [:]
    /// Levels whose last outcome is unknown; tapping again reuses the request id.
    public private(set) var unknownLevels: Set<Int> = []
    public private(set) var skipUnknown = false
    public private(set) var skipped = false
    public private(set) var notice: String?
    public private(set) var busy = false
    let scope: PlayHelpScope
    let service: PlayHelpService
    let token: () -> String?
    private var ledger = PlayHelpRequestLedger()

    public init(scope: PlayHelpScope, service: PlayHelpService, token: @escaping () -> String?) {
        self.scope = scope; self.service = service; self.token = token
    }

    public var enabled: Bool { view?.enabled == true && !skipped }

    public func load() async {
        guard let token = token() else { return }
        do { view = try await service.view(scope: scope, token: token); notice = nil }
        catch { view = nil }
    }

    public func use(_ row: PlayHelpRow) async {
        guard !busy, row.canRequest || unknownLevels.contains(row.level), let token = token() else { return }
        busy = true; defer { busy = false }
        let requestID = ledger.requestID(scope, operation: "use", level: row.level)
        do {
            let receipt = try await service.use(scope: scope, level: row.level, requestID: requestID, token: token)
            ledger.settle(scope, operation: "use", level: row.level)
            unknownLevels.remove(row.level); contents[row.level] = receipt.content; notice = nil
            await load()
        } catch PlayExperienceError.rejected(_, let message) {
            ledger.settle(scope, operation: "use", level: row.level)
            unknownLevels.remove(row.level); notice = message
        } catch PlayExperienceError.unknownResult {
            unknownLevels.insert(row.level)
        } catch {
            unknownLevels.insert(row.level)
        }
    }

    public func skip() async -> PlayHelpSkipReceipt? {
        guard !busy, view?.skipLevel != nil || skipUnknown, let token = token() else { return nil }
        busy = true; defer { busy = false }
        let requestID = ledger.requestID(scope, operation: "skip", level: 0)
        do {
            let receipt = try await service.skip(scope: scope, requestID: requestID, token: token)
            ledger.settle(scope, operation: "skip", level: 0)
            skipUnknown = false; skipped = true; notice = nil
            return receipt
        } catch PlayExperienceError.rejected(_, let message) {
            ledger.settle(scope, operation: "skip", level: 0)
            skipUnknown = false; notice = message
        } catch {
            skipUnknown = true
        }
        return nil
    }
}
