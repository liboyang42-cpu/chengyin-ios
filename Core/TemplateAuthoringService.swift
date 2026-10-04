import Foundation

public enum TemplateAuthoringAuthority: Equatable { case disabled, synthetic, injectedHTTP }
@MainActor public protocol TemplateAuthoringTransport: AnyObject {
    var authority: TemplateAuthoringAuthority { get }
    func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int)
}
public enum TemplateAuthoringOutcome: Equatable {
    case simulated, acknowledged, notSent, unauthorized, rejected(TemplateAuthoringRejection), uncertain
}
/// Exact audited adapter. Default remains disabled; HTTP requires explicit transport injection.
@MainActor public final class TemplateAuthoringAdapter {
    private let transport: (any TemplateAuthoringTransport)?
    private let shelfReadTransport: TemplateShelfReadTransport?
    public init(transport: (any TemplateAuthoringTransport)? = nil, shelfReadTransport: TemplateShelfReadTransport? = nil) {
        self.transport = transport; self.shelfReadTransport = shelfReadTransport
    }
    public var canRead: Bool { shelfReadTransport?.available == true || canSubmit }
    public var canSimulate: Bool {
        #if DEBUG
        return transport?.authority == .synthetic
        #else
        return false
        #endif
    }
    public var canSubmit: Bool { canSimulate || transport?.authority == .injectedHTTP }
    public func listMine() async throws -> [DiscoveryPlayTemplate] {
        guard canSubmit, let transport else { throw TemplateAuthoringError.unavailable }
        let (data, status) = try await transport.send(TemplateAuthoringContract.listMine())
        return try TemplateAuthoringContract.decodeList(data, httpStatus: status)
    }
    /// Read-only continuation, separate from the conservative write/readback snapshot.
    public func listMinePage(page: Int, keyword: String) async throws -> TemplateOwnShelfPage {
        let request = try TemplateOwnShelfPage.request(page: page, keyword: keyword)
        let result: (Data, Int)
        if let shelfReadTransport { result = try await shelfReadTransport.page(request) }
        else {
            guard canSubmit, let transport else { throw TemplateAuthoringError.unavailable }
            result = try await transport.send(request)
        }
        let (data, status) = result
        return try TemplateOwnShelfPage.decode(data, httpStatus: status)
    }
    public func submit(_ request: TemplateAuthoringRequest) async -> TemplateAuthoringOutcome {
        guard canSubmit, let transport, request.mutates else { return .notSent }
        do {
            let (data, status) = try await transport.send(request)
            // A 5xx or unreadable response cannot prove that a mutation did not happen.
            guard status < 500 else { return .uncertain }
            try TemplateAuthoringContract.requireSuccess(data, httpStatus: status)
            return canSimulate ? .simulated : .acknowledged
        } catch APIError.unauthorized { return .unauthorized }
        catch let failure as TemplateAuthoringRejection { return .rejected(failure) }
        catch { return .uncertain }
    }
}
