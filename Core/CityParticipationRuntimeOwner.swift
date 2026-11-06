import Foundation
import Observation

/// One full runtime-context/revision owner. No transport allowlist or authority issuer is installed.
/// Providers must return independently issued, stable grant objects and revoke them on permission loss.
/// The original durable namespace remains role-independent: switching roles cannot escape an UNKNOWN lock.
@MainActor @Observable public final class CityParticipationRuntimeOwner {
    public let id = UUID()
    public let captured: RuntimeDependencyContext
    public let capturedRevision: UInt64
    public private(set) var isRetired = false
    public private(set) var form: CityParticipationFormModel?
    private let commandScope: CityParticipationCommandScope
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentRevision: () -> UInt64

    public init(context: RuntimeDependencyContext, revision: UInt64, regionID: String,
                directory: URL, transport: any HTTPTransport,
                currentContext: @escaping () -> RuntimeDependencyContext?, currentRevision: @escaping () -> UInt64,
                stateGrant: @escaping (CityParticipationReadScope) -> CityParticipationReadGrant? = { _ in nil },
                invitationGrant: @escaping (CityParticipationCommandScope, String, String) -> CityParticipationInvitationGrant? = { _, _, _ in nil },
                commandGrant: @escaping (CityParticipationCommandScope) -> CityParticipationCommandGrant? = { _ in nil },
                receiptGrant: @escaping (CityOriginalReceiptReference) -> CityOriginalReceiptReadGrant? = { _ in nil },
                approve: (@MainActor (RuntimeDependencyContext, UInt64, CityParticipationCommand) async -> Bool)? = nil) throws {
        let api = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.role == context.session.role, !context.role.isEmpty,
              CityParticipationCommand.id(regionID), api.baseURL == context.baseURL,
              let current = currentContext(), Self.same(context, current), currentRevision() == revision else {
            throw CityParticipationCommandFailure.staleSession
        }
        captured = context; capturedRevision = revision
        self.currentContext = currentContext; self.currentRevision = currentRevision
        commandScope = try .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token)
        let scope = commandScope
        let readScope = try CityParticipationReadScope(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token, regionID: regionID)
        let journal = try CityParticipationCommandJournal(directory: directory)
        let stateReader = CityParticipationStateReader(configuration: api, transport: transport,
            currentScope: { [weak self] in self?.liveScope() == scope ? readScope : nil },
            grant: { [weak self] in guard self?.liveScope() == scope else { return nil }; return stateGrant(readScope) })
        let invitationReader = CityParticipationInvitationReader(configuration: api, transport: transport,
            currentScope: { [weak self] in self?.liveScope() },
            grantForRequest: { [weak self] requestedScope, region, code in
                guard self?.liveScope() == requestedScope, requestedScope == scope, region == regionID else { return nil }
                return invitationGrant(requestedScope, region, code)
            })
        let receiptReader = CityOriginalReceiptReader(configuration: api, transport: transport,
            currentSession: { [weak self] in self?.liveScope()?.session },
            grant: { [weak self] in
                guard self?.liveScope() == scope, let record = try? journal.load(scope),
                      let original = try? record.command,
                      let reference = try? CityOriginalReceiptReference(session: scope.session, domain: .participation, requestID: original.requestId) else { return nil }
                // Original persisted request only; provider decides authority. No new UUID, grant, or journal change.
                return receiptGrant(reference)
            })
        let recovery = CityParticipationCommandRecovery(configuration: api, transport: transport, journal: journal,
            currentScope: { [weak self] in self?.liveScope() },
            grant: { [weak self] in guard self?.liveScope() == scope else { return nil }; return commandGrant(scope) }, receiptReader: receiptReader)
        let approval: (@MainActor (CityParticipationCommand) async -> Bool)?
        if let approve {
            approval = { [weak self] command in
                guard self?.liveScope() == scope else { return false }
                let accepted = await approve(context, revision, command)
                return accepted && self?.liveScope() == scope
            }
        } else { approval = nil }
        form = CityParticipationFormModel(regionID: regionID, recovery: recovery,
            currentScope: { [weak self] in self?.liveScope() }, stateReader: stateReader,
            invitationReader: invitationReader, approve: approval)
    }
    public var isCurrent: Bool { matches(currentContext(), revision: currentRevision()) }
    public func matches(_ context: RuntimeDependencyContext?, revision: UInt64) -> Bool {
        guard !isRetired, let context else { return false }
        return capturedRevision == revision && Self.same(captured, context)
    }
    private static func same(_ first: RuntimeDependencyContext, _ second: RuntimeDependencyContext) -> Bool {
        first.role == first.session.role && second.role == second.session.role
            && ContentDraftContextFence.matches(first, second) && first.session == second.session
    }
    private func liveScope() -> CityParticipationCommandScope? {
        guard isCurrent else { retire(); return nil }; return commandScope
    }
    public func synchronize() { if !isCurrent { retire() } }
    public func retire() {
        guard !isRetired else { return }; isRetired = true; form?.close()
    }
}
