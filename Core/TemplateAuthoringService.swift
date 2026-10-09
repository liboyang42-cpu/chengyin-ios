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
        await submitWithReceipt(request).outcome
    }
    public func submitWithReceipt(_ request: TemplateAuthoringRequest) async -> TemplateAuthoringSubmission {
        guard TemplateAuthoringContract.permitsRemoteConfiguration(request), canSubmit, let transport, request.mutates else { return .init(outcome: .notSent, savedMemberTemplateID: nil) }
        do {
            let (data, status) = try await transport.send(request)
            guard status < 500 else { return .init(outcome: .uncertain, savedMemberTemplateID: nil) }
            try TemplateAuthoringContract.requireSuccess(data, httpStatus: status)
            let outcome: TemplateAuthoringOutcome = canSimulate ? .simulated : .acknowledged
            // Preserve legacy acknowledged semantics. Missing/invalid IDs cannot become a handoff.
            let id = outcome == .acknowledged ? try? TemplateAuthoringSavedDraft.responseID(data, request: request) : nil
            return .init(outcome: outcome, savedMemberTemplateID: id)
        } catch APIError.unauthorized { return .init(outcome: .unauthorized, savedMemberTemplateID: nil) }
        catch let failure as TemplateAuthoringRejection { return .init(outcome: .rejected(failure), savedMemberTemplateID: nil) }
        catch { return .init(outcome: .uncertain, savedMemberTemplateID: nil) }
    }
}
