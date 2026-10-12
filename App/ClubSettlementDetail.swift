import SwiftUI

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

/// Owns only the new Club row-to-detail route. Other finance sources are untouched.
@MainActor struct ClubSettlementRows: View {
    let presentation: ClubSettlementDetailPresentation
    let context: ClubGovernanceReadContext
    let snapshotGeneration: UInt64
    let namespace: String
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let sourceIsCurrent: () -> Bool
    let onReturn: () -> Void
    @State private var selected: ClubSettlementDetailTarget?
    var body: some View {
        Group {
            if presentation.records.isEmpty { Text("club.gov.empty") }
            ForEach(presentation.records) { row in
                if let target = presentation.target(recordID: row.id, context: context, snapshotGeneration: snapshotGeneration, namespace: namespace) {
                    Button {
                        guard selected == nil, current(target) else { return }; selected = target
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: row.name).font(.headline)
                            Text(LocalizedStringKey(row.status.localizationKey))
                            if let amount = row.amountText { Text(verbatim: amount) }
                            else { Text("club.settlementDetail.amountUnknown") }
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
        .sheet(item: $selected, onDismiss: { if sourceIsCurrent() { onReturn() } }) { target in
            NavigationStack {
                Group {
                    if current(target) {
                        ClubSettlementDetail(target: target, identity: identity, access: access, sourceIsCurrent: { current(target) })
                    } else { Color.clear }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { selected = nil } } }
                .onChange(of: current(target), initial: true) { _, valid in if !valid { selected = nil } }
            }
        }
        .onChange(of: context) { _, _ in selected = nil }
        .onChange(of: snapshotGeneration) { _, _ in selected = nil }
        .onChange(of: namespace) { _, _ in selected = nil }
        .onDisappear { selected = nil }
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
