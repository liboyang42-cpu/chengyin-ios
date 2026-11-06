import Foundation

/// One session-owned pair of adapters and one original coordinator. Binding retirement
/// scrubs projections/confirmations but never replaces the UNKNOWN account lock, with a PII-free durable marker.
@MainActor final class ProfileParticipantHost {
    typealias TransportFactory = @MainActor (RuntimeDependencyContext, ProfileParticipantAccess, @escaping () -> Bool) -> ProfileParticipantTransport?
    private struct Binding {
        let context: RuntimeDependencyContext
        let viewer: UInt64
        let access: ProfileParticipantAccess?
        let revision: UUID
        var identity: ProfileReadIdentity {
            .init(accountID: context.session.accountID, epoch: context.session.epoch,
                  viewerRevision: viewer, approvalRevision: revision)
        }
    }
    private let pendingJournal: any OperationPendingJournal
    private let current: () -> RuntimeDependencyContext?
    private let viewer: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> ProfileParticipantAccess?
    private let makeTransport: TransportFactory
    private let changed: () -> Void
    private let unauthorized: (RuntimeDependencyContext, UInt64) -> Void
    private var binding: Binding?
    private var observer: UUID?
    lazy var reader: any ProfileReading = Reader(owner: self)
    lazy var writer: any ParticipantWriting = Writer(owner: self)
    lazy var coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader,
        pendingJournal: pendingJournal, pendingOwner: { [weak self] in
            self?.current().map(Self.pendingOwner)
        }, onParticipantsChanged: { [weak self] in self?.changed() })

    init(current: @escaping () -> RuntimeDependencyContext?, viewer: @escaping () -> UInt64,
         access: @escaping (RuntimeDependencyContext) -> ProfileParticipantAccess?,
         makeTransport: @escaping TransportFactory, pendingJournal: (any OperationPendingJournal)? = nil, changed: @escaping () -> Void = {},
         unauthorized: @escaping (RuntimeDependencyContext, UInt64) -> Void = { _, _ in }) {
        self.pendingJournal = pendingJournal ?? ParticipantFileJournal.applicationSupport(legacy: OperationDefaultsJournal(defaults: .standard))
        self.current = current; self.viewer = viewer; selectAccess = access; self.makeTransport = makeTransport
        self.changed = changed; self.unauthorized = unauthorized
    }
    /// Stable, byte-exact deployment/owner scope. Credentials, roles, epochs and PII
    /// are not persisted. Role changes cannot bypass an unresolved owner operation.
    private static func pendingOwner(_ context: RuntimeDependencyContext) -> String {
        let fields = [context.market.rawValue, context.baseURL.absoluteString,
                      context.session.namespace, String(context.session.accountID)]
        let bytes = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return "profile.participant.v1." + Data(bytes.utf8).base64EncodedString()
    }
    /// Also invoked when the selector itself is replaced, including A -> nil -> A.
    /// This local generation is not a new server operation/request UUID.
    func invalidateAccess() {
        detachObserver(); binding = nil
        coordinator.synchronizeSession()
        changed()
    }
    private func detachObserver() {
        if let observer { binding?.access?.removeObserver(observer) }
        observer = nil
    }
    private func refresh() -> Binding? {
        guard let context = current() else { detachObserver(); binding = nil; return nil }
        let revision = viewer()
        let issued = selectAccess(context).flatMap { $0.matches(context) ? $0 : nil }
        if let held = binding, ContentDraftContextFence.matches(context, held.context),
           held.context.session.role.utf8.elementsEqual(context.session.role.utf8), held.viewer == revision,
           held.access === issued { return held }
        detachObserver()
        let next = Binding(context: context, viewer: revision, access: issued, revision: UUID())
        binding = next
        if let issued {
            observer = issued.observeRevocation { [weak self] in self?.invalidateAccess() }
        }
        return next
    }
    private func matches(_ captured: Binding) -> Bool { refresh()?.identity == captured.identity }
    private var identity: ProfileReadIdentity? { refresh()?.identity }
    private func capture(write: Bool) -> Binding? {
        guard let held = refresh(), let access = held.access, access.matches(held.context),
              !write || access.permitsWrites else { return nil }
        return held
    }
    private func transport(_ captured: Binding) -> ProfileParticipantTransport? {
        guard let access = captured.access, matches(captured) else { return nil }
        return makeTransport(captured.context, access, { [weak self] in self?.matches(captured) == true })
    }
    private func read<Value>(_ operation: (ProfileService, String) async throws -> Value) async throws -> Value {
        guard let captured = capture(write: false), let wire = transport(captured) else { throw APIError.notConfigured }
        try Task.checkCancellation()
        let service = ProfileService(configuration: try APIConfiguration(baseURL: captured.context.baseURL), transport: wire)
        do {
            let result = try await operation(service, captured.context.session.token)
            guard matches(captured), !Task.isCancelled else { throw CancellationError() }
            return result
        } catch {
            guard matches(captured), !Task.isCancelled else { throw CancellationError() }
            if let failure = error as? ProfileReadFailure, failure.isUnauthorized {
                unauthorized(captured.context, captured.viewer); throw APIError.unauthorized
            }
            throw error
        }
    }
    private func perform(_ mutation: ParticipantMutation, requestID: UUID,
                         expectedIdentity: ProfileReadIdentity) async throws -> ProfileParticipant? {
        guard let captured = capture(write: true) else { throw ParticipantWriteError.notSent(.notConfigured) }
        guard captured.identity == expectedIdentity else { throw ParticipantWriteError.notSent(.unauthorized) }
        if case .setDefault = mutation { throw ParticipantWriteError.notSent(.invalidRequest) }
        guard !Task.isCancelled else { throw ParticipantWriteError.cancelledBeforeDispatch }
        guard let wire = transport(captured) else { throw ParticipantWriteError.notSent(.notConfigured) }
        let service: ParticipantService
        do { service = ParticipantService(configuration: try APIConfiguration(baseURL: captured.context.baseURL), transport: wire) }
        catch { throw ParticipantWriteError.notSent(.notConfigured) }
        do {
            let row = try await service.performReturningParticipant(mutation, requestID: requestID, token: captured.context.session.token)
            guard matches(captured) else { throw ParticipantWriteError.outcomeUnknown(.accountChanged) }
            guard !Task.isCancelled else { throw ParticipantWriteError.outcomeUnknown(.cancelled) }
            return row
        } catch {
            if !wire.hasForwardedRequest {
                if let original = error as? ParticipantWriteError, case .notSent = original { throw original }
                if Task.isCancelled { throw ParticipantWriteError.cancelledBeforeDispatch }
                throw ParticipantWriteError.notSent(.notConfigured)
            }
            guard matches(captured) else { throw ParticipantWriteError.outcomeUnknown(.accountChanged) }
            if let failure = error as? ParticipantWriteError, case .rejected(let response) = failure, response.isUnauthorized {
                unauthorized(captured.context, captured.viewer)
            }
            throw error
        }
    }
    @MainActor private final class Reader: ProfileReading {
        weak var owner: ProfileParticipantHost?
        init(owner: ProfileParticipantHost) { self.owner = owner }
        var identity: ProfileReadIdentity? { owner?.identity }
        var isConfigured: Bool { owner?.capture(write: false) != nil }
        func profileParticipants() async throws -> [ProfileParticipant] {
            guard let owner else { throw APIError.notConfigured }
            return try await owner.read { try await $0.participants(token: $1) }
        }
        func profileParticipant(id: Int) async throws -> ProfileParticipant {
            guard let owner else { throw APIError.notConfigured }
            return try await owner.read { try await $0.participant(id: id, token: $1) }
        }
        func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
        func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
        func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
    }
    @MainActor private final class Writer: ParticipantWriting {
        weak var owner: ProfileParticipantHost?
        init(owner: ProfileParticipantHost) { self.owner = owner }
        var identity: ProfileReadIdentity? { owner?.identity }
        var isConfigured: Bool { owner?.capture(write: true) != nil }
        func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws {
            // Creation must have the original coordinator's confirmation ID, never a fresh fallback UUID.
            if case .save(let draft) = mutation, draft.id == nil { throw ParticipantWriteError.notSent(.invalidRequest) }
            _ = try await performReturningParticipant(mutation, requestID: UUID(), expectedIdentity: expectedIdentity)
        }
        func performReturningParticipant(_ mutation: ParticipantMutation, requestID: UUID,
                                         expectedIdentity: ProfileReadIdentity) async throws -> ProfileParticipant? {
            guard let owner else { throw ParticipantWriteError.notSent(.notConfigured) }
            return try await owner.perform(mutation, requestID: requestID, expectedIdentity: expectedIdentity)
        }
    }
}
