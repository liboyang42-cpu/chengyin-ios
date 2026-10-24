import SwiftUI

/// A confirmed submission authorizes one existing own-case read, never a decision or another write.
@MainActor final class ClubCaseSubmissionReturn: ObservableObject {
    struct Source: Equatable {
        let context: ClubGovernanceReadContext
        let snapshot: ClubGovernanceSnapshot
        let generation: UInt64
        let namespace: String
        let realm: String
        @MainActor init?(context: ClubGovernanceReadContext, snapshot: ClubGovernanceSnapshot,
              generation: UInt64, access: any ClubGovernanceAccess) {
            guard context.operation == .cases, context.accepts(snapshot), snapshot.value.array != nil,
                  context.identity?.isSignedIn == true, context.identity == access.identity,
                  context.authorizationGeneration == access.authorizationGeneration,
                  context.accessIdentity == ObjectIdentifier(access), access.isConfigured,
                  (context.scope.clubID ?? 0) > 0,
                  snapshot.permissions?.allows(ClubGovernanceRead.cases.permission, scope: context.scope) == true else { return nil }
            self.context = context; self.snapshot = snapshot; self.generation = generation
            namespace = access.storageNamespace; realm = access.journalRealm
        }
    }
    struct Item: Identifiable {
        let route: ClubGovernanceFormRoute
        let source: Source
        var id: UUID { route.id }
    }
    struct Callbacks {
        let begin: (ClubGovernanceReview) -> Bool
        let acknowledged: (ClubGovernanceReview) -> Void
    }
    @Published private(set) var item: Item?
    @Published private(set) var isPresented = false
    @Published private(set) var readID: UUID?
    private var submitted: ClubGovernanceReview?
    private var acknowledged = false
    private var didDismiss = false

    func open(_ operation: ClubGovernanceMutation, source: Source?, visible: Bool, active: Bool) {
        guard [.report, .appeal].contains(operation), item == nil, readID == nil, visible, active, let source else { return }
        item = .init(route: .init(operation: operation, scope: source.context.scope), source: source)
        isPresented = true; submitted = nil; acknowledged = false; didDismiss = false
    }
    func current(_ expected: Item, source: Source?, active: Bool) -> Bool {
        active && item?.id == expected.id && expected.source == source
    }
    func binding(_ expected: Item, source: @escaping () -> Source?, active: @escaping () -> Bool) -> Binding<Bool> {
        Binding(get: { self.isPresented && self.current(expected, source: source(), active: active()) }, set: { shown in
            guard !shown, self.current(expected, source: source(), active: active()) else { return }
            self.isPresented = false
        })
    }
    func begin(_ review: ClubGovernanceReview, state: ClubGovernanceWriteState,
               item expected: Item, source: Source?, active: Bool) -> Bool {
        guard isPresented, current(expected, source: source, active: active), !acknowledged,
              state == .reviewing, review.command.operation == expected.route.operation,
              [.report, .appeal].contains(review.command.operation),
              review.command.scope == expected.source.context.scope,
              review.identity == expected.source.context.identity,
              review.authorizationGeneration == expected.source.context.authorizationGeneration,
              review.storageNamespace == expected.source.namespace, review.journalRealm == expected.source.realm,
              review.snapshot == expected.source.snapshot,
              let requestID = review.command.fields["requestId"]?.string,
              !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        submitted = review
        return true
    }
    func acknowledge(_ review: ClubGovernanceReview, state: ClubGovernanceWriteState,
                     item expected: Item, source: Source?, active: Bool) {
        guard isPresented, current(expected, source: source, active: active), !acknowledged,
              state == .acknowledged, submitted == review else { return }
        // The service owns acknowledgement validation; optional data is not a case verdict.
        acknowledged = true; isPresented = false
    }
    @discardableResult func dismissed(_ expected: Item, source: Source?, active: Bool) -> Bool {
        guard current(expected, source: source, active: active), !isPresented else { return false }
        if acknowledged { didDismiss = true } else { retire() }
        return true
    }
    func consume(source: Source?, visible: Bool, active: Bool) -> Source? {
        guard visible, active, !isPresented, didDismiss, acknowledged,
              let item, current(item, source: source, active: active) else { return nil }
        let result = item.source; retire(); readID = UUID(); return result
    }
    func finishRead(_ expected: UUID) {
        guard readID == expected else { return }; readID = nil
    }
    func invalidateUnlessCurrent(source: Source?, active: Bool) {
        if let item, !current(item, source: source, active: active) { retire() }
    }
    func retire() {
        item = nil; isPresented = false; submitted = nil; acknowledged = false; didDismiss = false; readID = nil
    }
}

/// The whole cases page retains the owner; lazy rows only request a concrete route.
@MainActor struct ClubCaseSubmissionPresentationOwner: View {
    let item: ClubCaseSubmissionReturn.Item
    @ObservedObject var owner: ClubCaseSubmissionReturn
    let source: () -> ClubCaseSubmissionReturn.Source?
    let active: () -> Bool
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    let didDismiss: () -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: owner.binding(item, source: source, active: active), onDismiss: {
                if owner.dismissed(item, source: source(), active: active()) { didDismiss() }
            }) {
                NavigationStack {
                    ClubGovernanceCommandForm(route: item.route, identity: item.source.context.identity,
                        access: access, coordinator: coordinator, validateTarget: {
                            guard owner.isPresented, owner.current(item, source: source(), active: active()) else {
                                throw ClubGovernanceFailure.staleReview
                            }
                        }, caseSubmissionReturn: .init(begin: { review in
                            owner.begin(review, state: coordinator.state, item: item, source: source(), active: active())
                        }, acknowledged: { review in
                            owner.acknowledge(review, state: coordinator.state, item: item, source: source(), active: active())
                        }))
                }
            }
    }
}
