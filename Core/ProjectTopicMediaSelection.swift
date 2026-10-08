import Foundation

/// A pure local selection owner. It returns a one-use intent, never changes an
/// editor draft and never performs persistence, upload, moderation or publication.
/// Its future UI owner serializes state events; inspection chunk budgets are thread-safe.
public final class ProjectTopicMediaSelection {
    public struct Ticket: Equatable {
        public let id: UUID
        public let visit: UUID
        public let context: ProjectTopicMediaContext
        public let policy: ProjectTopicMediaPolicy
    }
    public struct Preview: Equatable {
        public let id: UUID
        public let ticket: Ticket
        public let items: [ProjectTopicMediaFacts]
    }
    public struct LocalSelectionIntent: Equatable {
        public let id: UUID
        public let context: ProjectTopicMediaContext
        public let policy: ProjectTopicMediaPolicy
        public let items: [ProjectTopicMediaFacts]
        public var localRecord: ProjectTopicMediaLocalRecord { .init(context: context, items: items) }
    }
    public enum State: Equatable {
        case unavailable(ProjectTopicMediaFailure), idle, needsReinspection
        case picking(Ticket), inspecting(Ticket), preview(Preview)
        case accepted(LocalSelectionIntent), failed(ProjectTopicMediaFailure), closed
    }
    public private(set) var state: State
    public private(set) var visit = UUID()
    public let context: ProjectTopicMediaContext?
    public let policy: ProjectTopicMediaPolicy?
    public private(set) var restoredRecord: ProjectTopicMediaLocalRecord?
    private var requests: [ProjectTopicMediaInspectionRequest] = []
    private var budget: ProjectTopicMediaInspectionBudget?

    public init(context: ProjectTopicMediaContext?, policy: ProjectTopicMediaPolicy?) {
        self.context = context; self.policy = policy
        state = context == nil ? .unavailable(.contextUnavailable) : (policy == nil ? .unavailable(.policyUnavailable) : .idle)
    }
    public static func restoring(_ record: ProjectTopicMediaLocalRecord, context: ProjectTopicMediaContext?,
                                 policy: ProjectTopicMediaPolicy?) throws -> Self {
        try record.validateShape()
        guard let context, record.matches(context) else { throw ProjectTopicMediaFailure.changedContext }
        let value = Self(context: context, policy: policy); value.restoredRecord = record
        if policy != nil { value.state = .needsReinspection }
        return value
    }

    /// Context/policy withdrawal retires this visit permanently. Reopening requires
    /// a new owner; changing away and back cannot revive an old picker or preview.
    public func synchronize(context current: ProjectTopicMediaContext?, policy currentPolicy: ProjectTopicMediaPolicy?) {
        guard state != .closed else { return }
        guard context != nil, current == context else { invalidate(.changedContext); return }
        guard policy != nil, currentPolicy == policy else { invalidate(currentPolicy == nil ? .policyUnavailable : .changedPolicy); return }
    }
    private func invalidate(_ failure: ProjectTopicMediaFailure) {
        budget?.invalidate(failure); budget = nil; requests = []; visit = UUID(); state = .unavailable(failure)
    }
    private func permits(_ originalVisit: UUID, context current: ProjectTopicMediaContext?,
                                  policy currentPolicy: ProjectTopicMediaPolicy?) -> Bool {
        synchronize(context: current, policy: currentPolicy)
        guard originalVisit == visit, context != nil, policy != nil else { return false }
        if case .unavailable = state { return false }
        return state != .closed
    }
    public func begin(visit originalVisit: UUID, context current: ProjectTopicMediaContext?,
                               policy currentPolicy: ProjectTopicMediaPolicy?) -> Ticket? {
        guard permits(originalVisit, context: current, policy: currentPolicy), let context, let policy else { return nil }
        switch state { case .idle, .needsReinspection, .failed: break; default: return nil }
        let ticket = Ticket(id: UUID(), visit: visit, context: context, policy: policy)
        state = .picking(ticket); return ticket
    }
    public func prepareInspection(_ references: [ProjectTopicMediaLocalReference], ticket: Ticket,
                                           context current: ProjectTopicMediaContext?, policy currentPolicy: ProjectTopicMediaPolicy?) -> [ProjectTopicMediaInspectionRequest]? {
        guard permits(ticket.visit, context: current, policy: currentPolicy), state == .picking(ticket) else { return nil }
        do {
            guard !references.isEmpty else { throw ProjectTopicMediaFailure.noSelection }
            guard UInt64(references.count) <= ticket.policy.maximumItems else { throw ProjectTopicMediaFailure.tooManyItems }
            guard Set(references.map(\.id)).count == references.count else { throw ProjectTopicMediaFailure.invalidReference }
            if let restoredRecord, references != restoredRecord.items.map(\.reference) { throw ProjectTopicMediaFailure.changedSource }
            let budget = ProjectTopicMediaInspectionBudget(maximum: ticket.policy.maximumTotalBytes)
            self.budget = budget
            requests = references.map { .init(id: UUID(), ticketID: ticket.id, context: ticket.context, reference: $0, policy: ticket.policy, budget: budget) }
            state = .inspecting(ticket); return requests
        } catch { state = .failed(error as? ProjectTopicMediaFailure ?? .invalidInspection); return nil }
    }
    public func finishInspection(_ evidence: [ProjectTopicMediaInspectionEvidence], ticket: Ticket,
                                          context current: ProjectTopicMediaContext?, policy currentPolicy: ProjectTopicMediaPolicy?) -> Preview? {
        guard permits(ticket.visit, context: current, policy: currentPolicy), state == .inspecting(ticket) else { return nil }
        do {
            guard evidence.count == requests.count, !requests.isEmpty else { throw ProjectTopicMediaFailure.invalidInspection }
            guard let budget else { throw ProjectTopicMediaFailure.invalidInspection }
            try budget.check()
            guard zip(evidence, requests).allSatisfy({ pair in pair.0.request == pair.1 }) else { throw ProjectTopicMediaFailure.invalidInspection }
            let items = evidence.map(\.facts)
            try ticket.policy.validate(items)
            if let restoredRecord, items != restoredRecord.items { throw ProjectTopicMediaFailure.changedSource }
            let preview = Preview(id: UUID(), ticket: ticket, items: items)
            state = .preview(preview); requests = []; self.budget = nil; return preview
        } catch {
            let failure = error as? ProjectTopicMediaFailure ?? .invalidInspection
            budget?.invalidate(failure); budget = nil; requests = []; state = .failed(failure); return nil
        }
    }
    public func inspectionFailed(_ failure: ProjectTopicMediaFailure, ticket: Ticket) {
        guard state == .inspecting(ticket), ticket.visit == visit else { return }
        budget?.invalidate(failure); budget = nil; requests = []; state = .failed(failure)
    }
    public func cancel(_ ticket: Ticket) {
        guard ticket.visit == visit else { return }
        let matches: Bool
        switch state {
        case .picking(let current), .inspecting(let current): matches = current == ticket
        case .preview(let current): matches = current.ticket == ticket
        default: matches = false
        }
        guard matches else { return }
        budget?.invalidate(.changedContext); budget = nil; requests = []
        state = restoredRecord == nil ? .idle : .needsReinspection
    }
    public func confirm(_ preview: Preview, context current: ProjectTopicMediaContext?,
                                 policy currentPolicy: ProjectTopicMediaPolicy?) -> LocalSelectionIntent? {
        guard permits(preview.ticket.visit, context: current, policy: currentPolicy), state == .preview(preview) else { return nil }
        let intent = LocalSelectionIntent(id: UUID(), context: preview.ticket.context, policy: preview.ticket.policy, items: preview.items)
        state = .accepted(intent); return intent
    }
    public func retire() {
        budget?.invalidate(.changedContext); budget = nil; requests = []; visit = UUID(); state = .closed
    }
}
