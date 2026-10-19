import SwiftUI
import UIKit

@MainActor final class ClubSettlementDetailReadModel: ObservableObject {
    struct Context: Hashable { let read: ClubGovernanceReadContext; let namespace: String; let targetID: UUID }
    struct Permit: Equatable { let context: Context; let visibility: UUID }
    @Published private(set) var record: ClubSettlementDetailRecord?
    @Published private(set) var missing = false
    @Published private(set) var loading = false
    @Published private(set) var failure: ClubGovernanceFailure?
    private var bound: Context?
    private var loaded: Context?
    private var visibility: UUID?
    private var generation = UUID()
    static func context(target: ClubSettlementDetailTarget, identity: ClubReadIdentity?, access: any ClubGovernanceAccess) -> Context {
        .init(read: .init(operation: .settlement, scope: target.readScope, identity: identity, viewerRevision: 0,
                          authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access)),
              namespace: access.storageNamespace, targetID: target.id)
    }
    func bind(_ context: Context) {
        guard bound != context else { return }
        bound = context; visibility = nil; generation = UUID()
    }
    func activate(_ context: Context) -> Permit? {
        guard bound == context, !Task.isCancelled else { return nil }
        if visibility == nil {
            visibility = UUID(); generation = UUID()
            loaded = nil; record = nil; loading = false; failure = nil; missing = false
        }
        return permit(in: context)
    }
    func permit(in context: Context) -> Permit? {
        guard bound == context, let visibility else { return nil }
        return .init(context: context, visibility: visibility)
    }
    private func accepts(_ permit: Permit) -> Bool { bound == permit.context && visibility == permit.visibility }
    private func live(_ context: Context, access: any ClubGovernanceAccess) -> Bool {
        let read = context.read
        return read.operation == .settlement && (read.scope.clubID ?? 0) > 0 &&
            read.identity?.isSignedIn == true && access.isConfigured && read.identity == access.identity &&
            read.authorizationGeneration == access.authorizationGeneration && read.accessIdentity == ObjectIdentifier(access) &&
            context.namespace == access.storageNamespace
    }
    func accepted(_ context: Context, access: any ClubGovernanceAccess) -> ClubSettlementDetailRecord? {
        guard permit(in: context) != nil, loaded == context, !loading, live(context, access: access) else { return nil }
        return record
    }
    func acceptedMissing(_ context: Context, access: any ClubGovernanceAccess) -> Bool {
        permit(in: context) != nil && loaded == context && !loading && live(context, access: access) && missing
    }
    func leave(_ context: Context) {
        guard bound == context else { return }
        visibility = nil; generation = UUID(); loaded = nil
        record = nil; loading = false; failure = nil; missing = false
    }
    func load(_ permit: Permit, target: ClubSettlementDetailTarget, access: any ClubGovernanceAccess, current: @escaping () -> Bool) async {
        guard accepts(permit), permit.context.targetID == target.id, target.acceptsRead(context: permit.context.read, namespace: permit.context.namespace), current(), !Task.isCancelled else { return }
        guard live(permit.context, access: access) else {
            loaded = nil; record = nil; loading = false
            failure = access.identity?.isSignedIn == true ? .notConfigured : .signedOut; return
        }
        generation = UUID(); let request = generation
        loaded = nil; record = nil; failure = nil; missing = false; loading = true
        defer { if generation == request && accepts(permit) { loading = false } }
        func check() throws {
            guard accepts(permit), generation == request, live(permit.context, access: access), current(), !Task.isCancelled else { throw CancellationError() }
        }
        do {
            try check()
            let snapshot = try await access.read(.settlement, scope: permit.context.read.scope, options: [:], check: check)
            try check()
            let projected = try ClubSettlementDetailPresentation(snapshot: snapshot, context: permit.context.read)
            let match = try projected.record(for: target)
            loaded = permit.context; record = match; missing = match == nil
        } catch {
            guard accepts(permit), generation == request, live(permit.context, access: access), current(), !Task.isCancelled else { return }
            failure = error as? ClubGovernanceFailure ?? .malformed
        }
    }
}

/// Whole-page owner for the existing read-only settlement record journey.
@MainActor final class ClubSettlementReturnOwner: ObservableObject {
    struct Source: Equatable {
        let presentation: ClubSettlementDetailPresentation
        let context: ClubGovernanceReadContext
        let generation: UInt64
        let namespace: String
    }
    struct Item: Identifiable, Equatable {
        var id: UUID { target.id }
        let attachment: UUID
        let source: Source
        let target: ClubSettlementDetailTarget
    }
    @Published private(set) var item: Item?
    @Published private(set) var isPresented = false
    @Published private(set) var attachment: UUID?
    private(set) var context: ClubGovernanceReadContext?
    private(set) var namespace: String?
    private(set) var visible = false
    private(set) var needsRefresh = true
    var retainsChild: Bool { item != nil }
    @discardableResult func synchronize(_ context: ClubGovernanceReadContext, namespace: String) -> Bool {
        guard self.context != context || self.namespace != namespace else { return false }
        self.context = context; self.namespace = namespace; attachment = UUID(); item = nil; isPresented = false; needsRefresh = true
        return true
    }
    func appear(_ context: ClubGovernanceReadContext, namespace: String) {
        synchronize(context, namespace: namespace)
        if attachment == nil { attachment = UUID() }
        visible = true
    }
    func hide() { visible = false }
    @discardableResult func depart(_ expected: UUID) -> Bool {
        guard attachment == expected else { return false }
        item = nil; isPresented = false; attachment = nil; context = nil; namespace = nil; visible = false; needsRefresh = true
        return true
    }
    func background() { item = nil; isPresented = false; needsRefresh = true }
    func open(_ target: ClubSettlementDetailTarget, source: Source, current: Source?, active: Bool) {
        guard visible, active, let attachment, item == nil, source == current, context == source.context, namespace == source.namespace,
              target.isCurrent(presentation: source.presentation, context: source.context,
                               snapshotGeneration: source.generation, namespace: source.namespace) else { return }
        item = Item(attachment: attachment, source: source, target: target); isPresented = true
    }
    private func matches(_ expected: Item, source: Source?, active: Bool) -> Bool {
        active && item == expected && attachment == expected.attachment && expected.source == source && context == expected.source.context && namespace == expected.source.namespace
    }
    func current(_ expected: Item, source: Source?, active: Bool) -> Bool {
        isPresented && matches(expected, source: source, active: active)
    }
    func binding(_ expected: Item, source: @escaping () -> Source?, active: @escaping () -> Bool) -> Binding<Bool> {
        Binding(get: { self.isPresented && self.current(expected, source: source(), active: active()) }, set: { presented in
            guard !presented, self.current(expected, source: source(), active: active()) else { return }
            self.isPresented = false
        })
    }
    @discardableResult func dismissed(_ expected: Item, source: Source?, active: Bool) -> Bool {
        guard !isPresented, matches(expected, source: source, active: active) else { return false }
        item = nil; needsRefresh = true; return true
    }
    func invalidate(source: Source?, active: Bool) {
        if let item, !matches(item, source: source, active: active) { background() }
    }
    func acceptsRead(_ expected: UUID?, context: ClubGovernanceReadContext, namespace: String, active: Bool) -> Bool {
        expected != nil && attachment == expected && self.context == context && self.namespace == namespace && visible && active && item == nil
    }
    func finishedRead(_ expected: UUID, context: ClubGovernanceReadContext, namespace: String, active: Bool, succeeded: Bool) {
        guard acceptsRead(expected, context: context, namespace: namespace, active: active) else { return }
        needsRefresh = !succeeded
    }
}

@MainActor struct ClubSettlementPresentationOwner: View {
    let item: ClubSettlementReturnOwner.Item
    @ObservedObject var owner: ClubSettlementReturnOwner
    let source: () -> ClubSettlementReturnOwner.Source?
    let active: () -> Bool
    let access: any ClubGovernanceAccess
    let returned: () -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: owner.binding(item, source: source, active: active), onDismiss: {
                if owner.dismissed(item, source: source(), active: active()) { returned() }
            }) {
                NavigationStack {
                    Group {
                        if owner.current(item, source: source(), active: active()) {
                            ClubSettlementDetail(target: item.target, identity: item.source.context.identity, access: access,
                                sourceIsCurrent: { owner.current(item, source: source(), active: active()) })
                        } else { Color.clear }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("club.gov.close") { owner.binding(item, source: source, active: active).wrappedValue = false }
                    } }
                }
            }
    }
}

@MainActor struct ClubSettlementParentLifetime: UIViewControllerRepresentable {
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
            while let value = current {
                if value.isBeingDismissed || value.isMovingFromParent { leave(); return }
                current = value.parent
            }
        }
    }
}

/// Owns only the new Club row-to-detail route. Other finance sources are untouched.
@MainActor struct ClubSettlementRows: View {
    let presentation: ClubSettlementDetailPresentation
    let context: ClubGovernanceReadContext
    let snapshotGeneration: UInt64
    let namespace: String
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let sourceIsCurrent: () -> Bool
    let source: ClubSettlementReturnOwner.Source
    @ObservedObject var owner: ClubSettlementReturnOwner
    let currentSource: () -> ClubSettlementReturnOwner.Source?
    let active: () -> Bool
    var body: some View {
        Group {
            if presentation.records.isEmpty { Text("clubOps.settlement.empty", tableName: "ClubOpsCustomer").accessibilityIdentifier("clubOps.settlement.empty") }
            ForEach(presentation.records) { row in
                if let target = presentation.target(recordID: row.id, context: context, snapshotGeneration: snapshotGeneration, namespace: namespace) {
                    Button {
                        guard current(target) else { return }
                        owner.open(target, source: source, current: currentSource(), active: active())
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: row.name).font(.headline)
                                Spacer()
                                if let amount = row.amountText { Text(verbatim: amount).font(.headline) }
                                else { Text("clubOps.settlement.rowUnverified", tableName: "ClubOpsCustomer").font(.headline) }
                            }
                            Text(LocalizedStringKey(row.status.localizationKey)).font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(row.status == .credited ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15)))
                            LabeledContent("club.settlementDetail.original") { Text(verbatim: row.originalAmountText) }
                            LabeledContent("club.settlementDetail.adjustment") { Text(verbatim: row.executedAdjustmentText) }
                            LabeledContent("club.settlementDetail.net") { Text(verbatim: row.netAmountText) }
                            Text(verbatim: row.arrivedText)
                            if row.status == .void || row.status == .unverified { Text(verbatim: row.paidText) }
                            Label("club.settlementDetail.open", systemImage: "chevron.right.circle")
                        }
                    }.buttonStyle(.borderless).accessibilityIdentifier("club.settlementDetail.open.\(row.id)")
                }
            }
        }
    }
    private func current(_ target: ClubSettlementDetailTarget) -> Bool {
        sourceIsCurrent() && identity == access.identity && access.isConfigured &&
        context.authorizationGeneration == access.authorizationGeneration && context.accessIdentity == ObjectIdentifier(access) &&
        namespace == access.storageNamespace && target.isCurrent(presentation: presentation, context: context,
            snapshotGeneration: snapshotGeneration, namespace: namespace)
    }
}

@MainActor struct ClubSettlementDetail: View {
    let target: ClubSettlementDetailTarget
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let sourceIsCurrent: () -> Bool
    @StateObject private var model = ClubSettlementDetailReadModel()
    private var context: ClubSettlementDetailReadModel.Context { ClubSettlementDetailReadModel.context(target: target, identity: identity, access: access) }
    var body: some View {
        let expected = context
        let _ = model.bind(expected)
        List {
            if model.loading { ProgressView("club.loading").accessibilityIdentifier("club.settlementDetail.loading") }
            if let failure = model.failure { Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.settlementDetail.failure") }
            if sourceIsCurrent(), let row = model.accepted(expected, access: access) {
                Section {
                    Text(verbatim: row.name).font(.title2)
                    Text("club.settlementDetail.perspective").font(.subheadline)
                    Text(LocalizedStringKey(row.status.localizationKey))
                    LabeledContent(LocalizedStringKey(row.amountLabelKey)) {
                        if let amount = row.amountText { Text(verbatim: amount) }
                        else { Text("club.settlementDetail.amountUnknown") }
                    }
                }
                Section("club.settlementDetail.breakdown") {
                    LabeledContent("club.settlementDetail.original") { Text(verbatim: row.originalAmountText) }
                    LabeledContent("club.settlementDetail.adjustment") { Text(verbatim: row.executedAdjustmentText) }
                    LabeledContent("club.settlementDetail.net") { Text(verbatim: row.netAmountText) }
                }
                Section("club.settlementDetail.paymentState") {
                    LabeledContent("club.settlementDetail.arrival") { Text(verbatim: row.arrivedText) }
                    LabeledContent("club.settlementDetail.paid") { Text(verbatim: row.paidText) }
                }
                Section {
                    LabeledContent("club.settlementDetail.recordID", value: String(row.id))
                    LabeledContent("club.gov.field.topicId", value: String(row.topicID))
                    Text("club.settlementDetail.disclaimer").font(.footnote)
                }
            } else if sourceIsCurrent(), model.acceptedMissing(expected, access: access) {
                Text("club.settlementDetail.missing").accessibilityIdentifier("club.settlementDetail.missing")
            }
            if model.failure != .forbidden {
                Button(LocalizedStringKey(model.failure == nil ? "club.gov.refresh" : "action.retry")) {
                    guard sourceIsCurrent(), let permit = model.permit(in: expected) else { return }
                    Task { await model.load(permit, target: target, access: access, current: sourceIsCurrent) }
                }.disabled(model.loading || model.permit(in: expected) == nil).accessibilityIdentifier("club.settlementDetail.reload")
            }
        }
        .navigationTitle("club.settlementDetail.title")
        .task(id: expected) {
            guard sourceIsCurrent(), let permit = model.activate(expected) else { return }
            await model.load(permit, target: target, access: access, current: sourceIsCurrent)
        }
        .onDisappear { model.leave(expected) }
    }
}
