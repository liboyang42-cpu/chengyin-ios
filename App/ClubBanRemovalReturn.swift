import SwiftUI
import UIKit

/// Owns one existing ban removal and its exact scoped return read. It cannot authorize a write.
@MainActor final class ClubBanRemovalReturn: ObservableObject {
    struct Source: Equatable {
        let context: ClubGovernanceReadContext
        let snapshot: ClubGovernanceSnapshot
        let generation: UInt64
        let namespace: String
        let realm: String
        @MainActor init?(context: ClubGovernanceReadContext, snapshot: ClubGovernanceSnapshot,
                         generation: UInt64, access: any ClubGovernanceAccess) {
            guard context.operation == .bans, context.accepts(snapshot),
                  context.identity?.isSignedIn == true, context.identity == access.identity,
                  context.authorizationGeneration == access.authorizationGeneration,
                  context.accessIdentity == ObjectIdentifier(access), access.isConfigured,
                  snapshot.permissions?.allows(ClubGovernanceRead.bans.permission, scope: context.scope) == true,
                  (try? ClubGovernanceValidation.validate(snapshot.value, operation: .bans, scope: context.scope)) == snapshot.value else { return nil }
            self.context = context; self.snapshot = snapshot; self.generation = generation
            namespace = access.storageNamespace; realm = access.journalRealm
        }
    }
    struct Item: Identifiable {
        let route: ClubGovernanceFormRoute
        let source: Source
        let attachment: UUID
        var id: UUID { route.id }
    }
    struct ReadTicket: Equatable {
        let id = UUID()
        let attachment: UUID
        let source: Source
    }
    struct Callbacks {
        let begin: (ClubGovernanceReview) -> Bool
        let acknowledged: (ClubGovernanceReview, ClubGovernanceValue) -> Void
    }
    @Published private(set) var item: Item?
    @Published private(set) var isPresented = false
    @Published private(set) var visible = false
    @Published private(set) var attachment: UUID?
    @Published private(set) var readTicket: ReadTicket?
    private var submitted: ClubGovernanceReview?
    private var acknowledged = false
    private var didDismiss = false
    var retainsReturn: Bool { item != nil || readTicket != nil }
    func appear() { visible = true; if attachment == nil { attachment = UUID() } }
    func hide() { visible = false }
    func depart(_ expected: UUID) {
        guard attachment == expected else { return }
        visible = false; attachment = nil; retire()
    }
    func depart(_ expected: UUID, reads: ClubBanListRead, resetParentRead: () -> Void) {
        guard attachment == expected else { return }
        depart(expected); reads.retire(); resetParentRead()
    }
    func open(seed: [String: ClubGovernanceValue], source: Source?, active: Bool) {
        guard visible, active, let attachment, item == nil, readTicket == nil, let source,
              Set(seed.keys) == Set(["banId", "version"]), let id = seed["banId"]?.int, id > 0,
              let version = seed["version"]?.int, version >= 0,
              source.snapshot.value.array?.filter({ $0["id"].int == id && $0["version"].int == version &&
                  $0["sourceType"] == .string("CLUB") && $0["status"] == .string("ACTIVE") }).count == 1 else { return }
        let route = ClubGovernanceFormRoute(operation: .unban, scope: source.context.scope, seed: seed)
        item = .init(route: route, source: source, attachment: attachment)
        isPresented = true; submitted = nil; acknowledged = false; didDismiss = false
    }
    func current(_ expected: Item, source: Source?, active: Bool) -> Bool {
        active && item?.id == expected.id && attachment == expected.attachment && expected.source == source
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
              review.command.operation == .unban,
              review.command.scope == expected.route.scope,
              review.identity == expected.source.context.identity,
              review.authorizationGeneration == expected.source.context.authorizationGeneration,
              review.storageNamespace == expected.source.namespace, review.journalRealm == expected.source.realm,
              review.snapshot.operation == .bans, review.snapshot.scope == review.command.scope,
              let requestID = review.command.fields["requestId"]?.string,
              !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard Set(review.command.fields.keys) == Set(["clubId", "banId", "version", "reason", "requestId"]),
              review.command.fields["banId"] == expected.route.seed["banId"],
              review.command.fields["version"] == expected.route.seed["version"],
              let row = expected.source.snapshot.value.array?.first(where: { $0["id"] == expected.route.seed["banId"] }),
              review.snapshot.value.array?.filter({ $0["id"] == expected.route.seed["banId"] }).count == 1,
              review.snapshot.value.array?.contains(row) == true else { return false }
        submitted = review
        return true
    }
    func acknowledge(_ review: ClubGovernanceReview, receipt _: ClubGovernanceValue, state: ClubGovernanceWriteState,
                     item expected: Item, source: Source?, active: Bool) {
        guard isPresented, current(expected, source: source, active: active), !acknowledged,
              state == .acknowledged, submitted == review else { return }
        acknowledged = true; isPresented = false
    }
    @discardableResult func dismissed(_ expected: Item, source: Source?, active: Bool) -> Bool {
        guard current(expected, source: source, active: active), !isPresented else { return false }
        if acknowledged { didDismiss = true } else { retire() }
        return true
    }
    func consume(source: Source?, active: Bool) -> ReadTicket? {
        guard visible, active, !isPresented, didDismiss, acknowledged, let item,
              current(item, source: source, active: active) else { return nil }
        let ticket = ReadTicket(attachment: item.attachment, source: item.source)
        retire(); readTicket = ticket
        return ticket
    }
    func isReading(_ expected: ReadTicket, context: ClubGovernanceReadContext, active: Bool) -> Bool {
        visible && active && attachment == expected.attachment && readTicket == expected && expected.source.context == context
    }
    func finishRead(_ expected: ReadTicket) { if readTicket == expected { readTicket = nil } }
    func invalidateUnlessCurrent(source: Source?, active: Bool) {
        if let item, !current(item, source: source, active: active) { retire() }
        if !active { retire() }
    }
    func retire() { item = nil; isPresented = false; submitted = nil; acknowledged = false; didDismiss = false; readTicket = nil }
}

/// Non-nil presentation identity is retained by the whole bans page, not a lazy row.
@MainActor struct ClubBanRemovalPresentationOwner: View {
    let item: ClubBanRemovalReturn.Item
    @ObservedObject var owner: ClubBanRemovalReturn
    let source: () -> ClubBanRemovalReturn.Source?
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
                        }, banRemovalReturn: .init(begin: { review in
                            owner.begin(review, state: coordinator.state, item: item, source: source(), active: active())
                        }, acknowledged: { review, receipt in
                            owner.acknowledge(review, receipt: receipt, state: coordinator.state,
                                              item: item, source: source(), active: active())
                        }))
                }
            }
    }
}

@MainActor struct ClubBanRemovalLifetime: UIViewControllerRepresentable {
    let leave: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(leave: leave) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.leave = leave }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.leave() }
    @MainActor final class Controller: UIViewController {
        var leave: () -> Void
        private var wasAttached = false
        init(leave: @escaping () -> Void) { self.leave = leave; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { wasAttached = true } else if wasAttached { leave() }
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            var current: UIViewController? = self
            while let controller = current {
                if controller.isBeingDismissed || controller.isMovingFromParent { leave(); return }
                current = controller.parent
            }
        }
    }
}

/// The normal bans page uses this loading owner across account/context changes.
@MainActor final class ClubBanListRead: ObservableObject {
    @Published private(set) var loading = false
    private(set) var context: ClubGovernanceReadContext?
    private var runID: UUID?
    @discardableResult func synchronize(_ next: ClubGovernanceReadContext) -> Bool {
        guard context != next else { return false }
        retire(); context = next
        return true
    }
    func retire() { runID = nil; loading = false }
    func load(context expected: ClubGovernanceReadContext, access: any ClubGovernanceAccess,
              check: @escaping @MainActor () throws -> Void) async throws -> ClubGovernanceSnapshot {
        synchronize(expected)
        try check()
        guard expected.operation == .bans, !loading,
              expected.identity == access.identity,
              expected.authorizationGeneration == access.authorizationGeneration,
              expected.accessIdentity == ObjectIdentifier(access) else { throw ClubGovernanceFailure.staleReview }
        let run = UUID(); runID = run; loading = true
        defer { if runID == run { runID = nil; loading = false } }
        func current() throws {
            guard runID == run, context == expected, !Task.isCancelled else { throw CancellationError() }
            try check()
        }
        let result = try await access.read(.bans, scope: expected.scope, options: [:], check: current)
        try current()
        guard expected.accepts(result) else { throw ClubGovernanceFailure.targetChanged }
        return result
    }
}
