import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Dormant adapter: no default transport, shared session, automatic retries or telemetry.
public struct OfficialActionService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let enabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
    }
    static func request(_ command: OfficialActionCommand, configuration: APIConfiguration, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw OfficialActionFailure.invalid }
        let body = try command.payload()
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(command.path))
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    public func send(_ command: OfficialActionCommand, token: String) async throws -> OfficialActionReceipt {
        guard enabled else { throw OfficialActionFailure.disabled }
        let request = try Self.request(command, configuration: configuration, token: token)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        // Any throw after dispatch is conservatively unknown unless an exact business rejection was received.
        guard (200..<300).contains(status), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let codeNumber = object["code"] as? NSNumber, CFGetTypeID(codeNumber) != CFBooleanGetTypeID(), codeNumber.doubleValue == Double(codeNumber.intValue) else { throw OfficialActionFailure.unknown }
        let code = codeNumber.intValue
        guard code == 200 else { throw OfficialActionFailure.rejected(code, object["msg"] as? String) }
        func positiveID(_ value: Any?) throws -> Int {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue == Double(value.intValue), value.intValue > 0 else { throw OfficialActionFailure.unknown }; return value.intValue
        }
        switch command {
        case .publish: return .published(try positiveID(object["data"]))
        case .broadcast: return .broadcastSubmitted(try positiveID(object["data"]))
        case .inviteMerchants:
            guard let values = object["data"] as? [Any], !values.isEmpty else { throw OfficialActionFailure.unknown }
            let rows = try values.map { try positiveID($0) }
            guard Set(rows).count == rows.count else { throw OfficialActionFailure.unknown }
            return .invitesIssued(rows)
        case .arrival:
            struct Arrival: Decodable { let accepted: Bool; let completed: Bool; let reason: String? }
            struct ArrivalEnvelope: Decodable { let data: Arrival }
            guard let result = try? JSONDecoder().decode(ArrivalEnvelope.self, from: data).data else { throw OfficialActionFailure.unknown }
            return .arrival(accepted: result.accepted, completed: result.completed, reason: result.reason)
        default: return .acknowledged
        }
    }
}

/// The source's tracking endpoint returns schemaless objects. Preserve scalar facts only;
/// do not reinterpret notification IDs as delivery or participant state.
public struct OfficialInviteTrackingService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let enabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
    }
    public func invites(status: Int? = nil, token: String) async throws -> [[String: OfficialStatisticValue]] {
        guard enabled else { throw OfficialActionFailure.disabled }
        guard AuthRequestBuilder.isValidToken(token) else { throw OfficialActionFailure.invalid }
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/official/invites"), resolvingAgainstBaseURL: false)!
        if let status { components.queryItems = [URLQueryItem(name: "status", value: String(status))] }
        guard let url = components.url else { throw OfficialActionFailure.invalid }
        var request = URLRequest(url: url); request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, statusCode) = try await transport.send(request)
        guard (200..<300).contains(statusCode) else { throw OfficialActionFailure.unknown }
        struct Envelope: Decodable { let code: Int; let msg: String?; let data: [[String: OfficialStatisticValue]]? }
        let value = try JSONDecoder().decode(Envelope.self, from: data)
        guard value.code == 200 else { throw OfficialActionFailure.rejected(value.code, value.msg) }
        guard let rows = value.data else { throw OfficialActionFailure.unknown }; return rows
    }
    /// Optional instrumentation is separately opt-in and never prevents navigation.
    public func reportClick(id: Int, channel: String? = nil, token: String) async {
        guard enabled, id > 0, AuthRequestBuilder.isValidToken(token) else { return }
        var parts = URLComponents(url: configuration.baseURL.appendingPathComponent("api/official/broadcast/\(id)/click"), resolvingAgainstBaseURL: false)
        if let channel { parts?.queryItems = [URLQueryItem(name: "channel", value: channel)] }
        guard let url = parts?.url else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue(token, forHTTPHeaderField: "Authorization")
        _ = try? await transport.send(request)
    }
}
