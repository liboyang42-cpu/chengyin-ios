import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum StoreCharacterFailure: Error, Equatable {
    case notConfigured, unauthorized, accessDenied, malformed, writesDisabled, staleScope
    /// The server answered with a definite business rejection (message shown as-is).
    case rejected(code: Int, message: String?)
    /// Timeout, network loss, 5xx or an unreadable reply after dispatch: never re-send blindly.
    case outcomeUnknown
}

/// Exact JSON POST contracts for the store character page. Holds no credential itself.
public struct StoreCharacterService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    private struct Code: Decodable {
        let value: Int
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let number = try? c.decode(Int.self) { value = number }
            else if let text = try? c.decode(String.self), let number = Int(text) { value = number }
            else { throw APIError.malformedResponse }
        }
    }
    private struct Envelope<Value: Decodable>: Decodable {
        let code: Code; let msg: String?; let data: Value?
    }
    private struct TopLevelVoice: Decodable {
        let code: Code; let msg: String?; let voiceStatus: Code?; let voiceSample: String?
    }
    private struct Ignored: Decodable { init(from decoder: Decoder) throws {} }

    public func request(_ path: String, body: Data, token: String) throws -> URLRequest {
        guard StoreCharacterEndpoint.reads.contains(path) || StoreCharacterEndpoint.writes.contains(path) else { throw APIError.invalidRequest }
        return try OperationAdapterHTTP.json(configuration: configuration, path: path, body: body, token: token)
    }
    /// Reads surface transport errors as-is; a business `code` other than 200 is a rejection.
    private func read(_ path: String, body: Data = Data("{}".utf8), token: String) async throws -> Data {
        let request = try self.request(path, body: body, token: token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw StoreCharacterFailure.unauthorized }
        if status == 403 { throw StoreCharacterFailure.accessDenied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        try Self.checkCode(data)
        return data
    }
    /// Writes classify every post-dispatch ambiguity as `.outcomeUnknown`.
    private func write(_ path: String, body: Data, token: String) async throws -> Data {
        let request = try self.request(path, body: body, token: token)
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) } catch { throw StoreCharacterFailure.outcomeUnknown }
        if status == 401 { throw StoreCharacterFailure.unauthorized }
        if status == 403 { throw StoreCharacterFailure.accessDenied }
        if status >= 500 || !(200..<300).contains(status) && status < 400 { throw StoreCharacterFailure.outcomeUnknown }
        guard (200..<300).contains(status) else { throw StoreCharacterFailure.rejected(code: status, message: nil) }
        do { try Self.checkCode(data) }
        catch let failure as StoreCharacterFailure where failure != .malformed { throw failure }
        catch { throw StoreCharacterFailure.outcomeUnknown }
        return data
    }
    static func checkCode(_ data: Data) throws {
        guard let envelope = try? JSONDecoder().decode(Envelope<Ignored>.self, from: data) else { throw StoreCharacterFailure.malformed }
        if envelope.code.value == 401 { throw StoreCharacterFailure.unauthorized }
        guard envelope.code.value == 200 else { throw StoreCharacterFailure.rejected(code: envelope.code.value, message: envelope.msg) }
    }
    static func decodeVoice(_ data: Data) throws -> StoreCharacterVoiceState {
        guard let value = try? JSONDecoder().decode(TopLevelVoice.self, from: data), let raw = value.voiceStatus?.value,
              let status = StoreCharacterVoiceState.Status(rawValue: raw) else { throw StoreCharacterFailure.malformed }
        let sample = value.voiceSample.flatMap { $0.isEmpty ? nil : $0 }
        return .init(status: status, sample: sample)
    }

    public func access(token: String) async throws -> MerchantOperationsAccess {
        let data = try await read(StoreCharacterEndpoint.access, token: token)
        guard let value = try? JSONDecoder().decode(Envelope<MerchantOperationsAccess>.self, from: data).data else { throw StoreCharacterFailure.malformed }
        return value
    }
    /// `data: null` is an empty profile (the merchant has not created a character yet).
    public func profile(token: String) async throws -> StoreCharacterProfile {
        let data = try await read(StoreCharacterEndpoint.profile, token: token)
        guard let envelope = try? JSONDecoder().decode(Envelope<StoreCharacterProfile>.self, from: data) else { throw StoreCharacterFailure.malformed }
        return envelope.data ?? .empty
    }
    public func voiceStatus(token: String) async throws -> StoreCharacterVoiceState {
        try Self.decodeVoice(try await read(StoreCharacterEndpoint.voiceStatus, token: token))
    }
    public func mapPoint(token: String) async throws -> StoreCharacterMapPointState {
        let data = try await read(StoreCharacterEndpoint.mapPointRead, token: token)
        guard let value = try? JSONDecoder().decode(Envelope<StoreCharacterMapPointState>.self, from: data).data else { throw StoreCharacterFailure.malformed }
        return value
    }
    /// Acknowledgement is `msg` only; the caller shows the source's local post-save state.
    public func save(_ payload: StoreCharacterSavePayload, token: String) async throws {
        _ = try await write(StoreCharacterEndpoint.save, body: try payload.jsonBody(), token: token)
    }
    public func recordConsent(_ record: StoreCharacterVoiceConsentRecord, token: String) async throws {
        let data = try await write(StoreCharacterEndpoint.consent, body: try record.jsonBody(), token: token)
        let row = (try? JSONDecoder().decode(Envelope<StoreCharacterConsentRow>.self, from: data))?.data
        guard record.accepts(row) else { throw StoreCharacterFailure.outcomeUnknown }
    }
    public func enroll(_ enrollment: StoreCharacterVoiceEnrollment, token: String) async throws -> StoreCharacterVoiceState.Status {
        let data = try await write(StoreCharacterEndpoint.voiceEnroll, body: try enrollment.jsonBody(), token: token)
        do { return try Self.decodeVoice(data).status } catch { throw StoreCharacterFailure.outcomeUnknown }
    }
    public func saveMapPoint(_ point: StoreCharacterMapPointWrite, token: String) async throws {
        _ = try await write(StoreCharacterEndpoint.mapPointSave, body: try point.jsonBody(), token: token)
    }
}

/// Reads used by the page. `scope` rotates on account/session changes; stale completions are dropped.
@MainActor public protocol StoreCharacterReading: AnyObject {
    var scope: UUID { get }
    var isAuthenticated: Bool { get }
    func access() async throws -> MerchantOperationsAccess
    func profile() async throws -> StoreCharacterProfile
    func voiceStatus() async throws -> StoreCharacterVoiceState
    func mapPoint() async throws -> StoreCharacterMapPointState
}

/// Writes. The `requestID` is the prepared action's identity: a local lock key, never a server field.
@MainActor public protocol StoreCharacterWriting: AnyObject {
    func save(_ payload: StoreCharacterSavePayload, requestID: UUID) async throws
    func recordVoiceConsent(_ record: StoreCharacterVoiceConsentRecord) async throws
    func enroll(_ enrollment: StoreCharacterVoiceEnrollment, requestID: UUID) async throws -> StoreCharacterVoiceState.Status
    func saveMapPoint(_ point: StoreCharacterMapPointWrite, requestID: UUID) async throws
}

/// Token-scoped reader over the exact service. Writes exist only when a gate flag is on AND the
/// path is either in the reviewed per-market allowlist or the transport is an injected offline harness.
@MainActor public final class StoreCharacterServiceBackend: StoreCharacterReading, StoreCharacterWriting {
    public enum Execution: Equatable { case disabled, injectedOfflineHarness }
    private let service: StoreCharacterService
    private let token: () -> String?
    private let currentScope: () -> UUID?
    private let gates: MerchantCityNPCParityGates
    private let market: RegionalMarket
    private let execution: Execution
    public init(service: StoreCharacterService, market: RegionalMarket, gates: MerchantCityNPCParityGates = .disabled,
                execution: Execution = .disabled, token: @escaping () -> String?, currentScope: @escaping () -> UUID?) {
        self.service = service; self.market = market; self.gates = gates; self.execution = execution
        self.token = token; self.currentScope = currentScope
    }
    public var scope: UUID { currentScope() ?? Self.signedOut }
    private static let signedOut = UUID()
    public var isAuthenticated: Bool { currentScope() != nil && token().map(AuthRequestBuilder.isValidToken) == true }
    public func permits(_ path: String) -> Bool {
        let flag: Bool
        switch path {
        case StoreCharacterEndpoint.save, StoreCharacterEndpoint.mapPointSave: flag = gates.storeCharacterSaves
        case StoreCharacterEndpoint.consent, StoreCharacterEndpoint.voiceEnroll: flag = gates.storeVoiceEnrollment
        default: return false
        }
        return flag && (execution == .injectedOfflineHarness || gates.allows(path, market: market))
    }
    private func credential() throws -> (String, UUID) {
        guard let token = token(), AuthRequestBuilder.isValidToken(token), let scope = currentScope() else { throw StoreCharacterFailure.unauthorized }
        return (token, scope)
    }
    private func run<Value>(_ operation: (StoreCharacterService, String) async throws -> Value) async throws -> Value {
        let (token, captured) = try credential()
        let value = try await operation(service, token)
        guard currentScope() == captured else { throw StoreCharacterFailure.staleScope }
        return value
    }
    private func runWrite<Value>(_ path: String, _ operation: (StoreCharacterService, String) async throws -> Value) async throws -> Value {
        guard permits(path) else { throw StoreCharacterFailure.writesDisabled }
        let (token, captured) = try credential()
        let value = try await operation(service, token)
        // The write may have landed; a changed scope only means this screen can no longer show it.
        guard currentScope() == captured else { throw StoreCharacterFailure.outcomeUnknown }
        return value
    }
    public func access() async throws -> MerchantOperationsAccess { try await run { try await $0.access(token: $1) } }
    public func profile() async throws -> StoreCharacterProfile { try await run { try await $0.profile(token: $1) } }
    public func voiceStatus() async throws -> StoreCharacterVoiceState { try await run { try await $0.voiceStatus(token: $1) } }
    public func mapPoint() async throws -> StoreCharacterMapPointState { try await run { try await $0.mapPoint(token: $1) } }
    public func save(_ payload: StoreCharacterSavePayload, requestID: UUID) async throws {
        try await runWrite(StoreCharacterEndpoint.save) { try await $0.save(payload, token: $1) }
    }
    public func recordVoiceConsent(_ record: StoreCharacterVoiceConsentRecord) async throws {
        try await runWrite(StoreCharacterEndpoint.consent) { try await $0.recordConsent(record, token: $1) }
    }
    public func enroll(_ enrollment: StoreCharacterVoiceEnrollment, requestID: UUID) async throws -> StoreCharacterVoiceState.Status {
        try await runWrite(StoreCharacterEndpoint.voiceEnroll) { try await $0.enroll(enrollment, token: $1) }
    }
    public func saveMapPoint(_ point: StoreCharacterMapPointWrite, requestID: UUID) async throws {
        try await runWrite(StoreCharacterEndpoint.mapPointSave) { try await $0.saveMapPoint(point, token: $1) }
    }
}

/// Production read adapter over the existing merchant operations reader (no credential access).
/// `npc/profile` and `coop-profile` come through its token-scoped reads; voice status has no
/// top-level-safe read there, so it is reported unconfirmed rather than guessed.
@MainActor public final class StoreCharacterOperationsReader: StoreCharacterReading {
    private let reader: any MerchantOperationsReading
    public init(reader: any MerchantOperationsReading) { self.reader = reader }
    public var scope: UUID { reader.scope }
    public var isAuthenticated: Bool { reader.isAuthenticated }
    public func access() async throws -> MerchantOperationsAccess { try await reader.access() }
    public func profile() async throws -> StoreCharacterProfile {
        guard case .draft(.character(let value)) = try await reader.document(.character) else { throw StoreCharacterFailure.malformed }
        var profile = StoreCharacterProfile()
        profile.name = value.name; profile.avatar = value.avatar; profile.greeting = value.greeting
        profile.persona = value.persona; profile.knowledge = value.knowledge
        profile.auditStatus = value.auditStatus; profile.auditReason = value.auditReason ?? ""; profile.voiceStatus = nil
        return profile
    }
    public func voiceStatus() async throws -> StoreCharacterVoiceState { throw StoreCharacterFailure.notConfigured }
    public func mapPoint() async throws -> StoreCharacterMapPointState {
        guard case .draft(.npcMapPoint(let value)) = try await reader.document(.npcMapPoint) else { throw StoreCharacterFailure.malformed }
        return .init(hasPoint: value.coordinate != nil, address: value.address)
    }
}
