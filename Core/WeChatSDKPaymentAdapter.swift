import Foundation

/// Provider identities and callback routes are independently verified deployment facts.
/// No AppID, merchant, endpoint, SDK or storefront permission is installed by default.
public struct WeChatSDKPaymentConfiguration: Equatable {
    public let sdk: WeChatSDKConfiguration
    public let merchantIDs: Set<String>
    public init(sdk: WeChatSDKConfiguration, merchantIDs: Set<String>) throws {
        guard !merchantIDs.isEmpty, merchantIDs.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { throw APIError.invalidConfiguration }
        self.sdk = sdk; self.merchantIDs = merchantIDs
    }
}
/// Transient signed provider fields. Never Codable, persisted, logged, or shown in UI.
public struct WeChatSDKPaymentRequest {
    public let partnerID: String
    public let prepayID: String
    public let nonce: String
    public let timestamp: UInt32
    public let package: String
    public let signature: String
    public init(parameters: [String: String], configuration: WeChatSDKPaymentConfiguration) throws {
        guard parameters["appId"] == configuration.sdk.appID,
              let partner = parameters["partnerId"], configuration.merchantIDs.contains(partner),
              let prepay = parameters["prepayId"], let nonce = parameters["nonceStr"],
              let rawTime = parameters["timeStamp"], let time = UInt32(rawTime), time > 0,
              let package = parameters["packageValue"], let sign = parameters["sign"],
              [partner, prepay, nonce, package, sign].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 && $0.utf8.allSatisfy { $0 > 0x20 && $0 < 0x7f } }) else { throw APIError.invalidRequest }
        partnerID = partner; prepayID = prepay; self.nonce = nonce; timestamp = time; self.package = package; signature = sign
    }
}
@MainActor public protocol WeChatSDKPaymentDriving: AnyObject {
    var isLinked: Bool { get }
    var isInstalledAndSupported: Bool { get }
    func register(_ configuration: WeChatSDKConfiguration) -> Bool
    func send(_ request: WeChatSDKPaymentRequest, launched: @escaping (Bool) -> Void, response: @escaping (Int32) -> Void)
    func detach()
}
/// PayResp has no orderID or OAuth state. At most one local order is pending. A callback
/// only ends the provider wait; the caller always reconciles its own order on the server.
@MainActor public final class WeChatSDKPaymentAdapter: TopicSelfPlayPaymentProviding {
    private struct Pending {
        let id: UUID
        let registrationID: Int
        let context: RuntimeDependencyContext
        let callback: (TopicSelfPlayProviderReturn) -> Void
    }
    private let driver: (any WeChatSDKPaymentDriving)?
    private let configuration: WeChatSDKPaymentConfiguration?
    private let allowed: () -> Bool
    private let context: () -> RuntimeDependencyContext?
    private let timeoutNanoseconds: UInt64
    private var pending: Pending?
    private var timeout: Task<Void, Never>?
    private var registered = false
    public init(driver: (any WeChatSDKPaymentDriving)? = nil, configuration: WeChatSDKPaymentConfiguration? = nil,
                allowed: @escaping () -> Bool = { false }, context: @escaping () -> RuntimeDependencyContext?,
                timeoutNanoseconds: UInt64 = 120_000_000_000) {
        self.driver = driver; self.configuration = configuration; self.allowed = allowed; self.context = context
        self.timeoutNanoseconds = max(1, timeoutNanoseconds)
    }
    public var isConfigured: Bool {
        guard allowed(), let context = context(), context.market == .china,
              ["player", "club"].contains(context.role), configuration != nil, driver?.isLinked == true else { return false }
        return true
    }
    public var pendingRegistrationID: Int? { pending?.registrationID }
    public func pay(registrationID: Int, parameters: [String: String]) async -> TopicSelfPlayProviderReturn {
        guard pending == nil, registrationID > 0, isConfigured, !Task.isCancelled,
              let captured = context(), let configuration, let driver,
              let request = try? WeChatSDKPaymentRequest(parameters: parameters, configuration: configuration) else { return .unknown }
        let attempt = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: .unknown); return }
                pending = Pending(id: attempt, registrationID: registrationID, context: captured, callback: { continuation.resume(returning: $0) })
                if !registered { registered = driver.register(configuration.sdk) }
                guard registered, driver.isInstalledAndSupported, current(attempt) else { finish(.unknown, id: attempt); return }
                timeout = Task { [weak self] in
                    guard let self else { return }
                    do { try await Task.sleep(nanoseconds: self.timeoutNanoseconds) } catch { return }
                    self.finish(.unknown, id: attempt)
                }
                driver.send(request, launched: { [weak self] launched in
                    guard let self, self.current(attempt) else { return }
                    if !launched { self.finish(.failed, id: attempt) }
                }, response: { [weak self] code in
                    guard let self, self.current(attempt) else { return }
                    // Zero is a provider return, never proof of payment settlement.
                    let outcome: TopicSelfPlayProviderReturn = code == 0 ? .returned : code == -2 ? .cancelled : .failed
                    self.finish(outcome, id: attempt)
                })
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(.unknown, id: attempt) } }
    }
    public func acceptsURL(_ url: URL) -> Bool {
        guard let id = pending?.id, current(id) else { return false }
        return configuration?.sdk.acceptsURL(url) == true
    }
    public func acceptsUniversalLink(_ url: URL) -> Bool {
        guard let id = pending?.id, current(id) else { return false }
        return configuration?.sdk.acceptsUniversalLink(url) == true
    }
    public func cancelPending() { if let pending { finish(.unknown, id: pending.id) } }
    private func current(_ id: UUID) -> Bool {
        guard let pending, pending.id == id else { return false }
        guard isConfigured, context() == pending.context else { finish(.unknown, id: id); return false }
        return true
    }
    private func finish(_ outcome: TopicSelfPlayProviderReturn, id: UUID) {
        guard let pending, pending.id == id else { return }
        self.pending = nil; timeout?.cancel(); timeout = nil; driver?.detach(); pending.callback(outcome)
    }
}
