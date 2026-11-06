import SwiftUI

@MainActor struct CityAcquisitionEntry: View {
    private let table = "CityAcquisition"
    let factory: (@MainActor () -> CityAcquisitionController)?
    var open: (@MainActor () -> Void)? = nil
    var body: some View {
        Group {
            if let open { Button(action: open) { entryLabel } }
            else { NavigationLink { CityAcquisitionView(controller: factory?() ?? .init(service: nil, journal: nil)) } label: { entryLabel } }
        }.accessibilityIdentifier("city.acquisition.entry")
    }
    private var entryLabel: some View {
        Label { Text("cityAcquire.entry", tableName: table) } icon: { Image(systemName: "building.2.crop.circle") }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
/// Authoritative current title read for this exact selected board/point, never a POI tag.
@MainActor struct CityAcquisitionPointStatus: View {
    @Environment(\.scenePhase) private var scenePhase
    private let table = "CityAcquisition"
    let board: CityReadBoard
    let pointID: String
    let factory: (@MainActor () -> CityAcquisitionController)?
    var open: (@MainActor () -> Void)? = nil
    @State private var controller: CityAcquisitionController?
    @State private var visible = false
    @State private var readID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = controller?.snapshot, snapshot.binding?.boardId == board.boardId, snapshot.binding?.seasonId == board.seasonId, snapshot.binding?.regionId == board.regionId, snapshot.binding?.contentHash == board.rulesHash, snapshot.binding?.rulesReleaseId == board.rulesReleaseId {
                if let title = snapshot.ownership.first(where: { $0.pointId == pointID }) {
                    if title.contentHash == board.rulesHash {
                        Text("cityAcquire.map.owned", tableName: table); Text(verbatim: title.ownerTeamId).font(.caption)
                        Text(CityAcquisitionView.status(title.status), tableName: table)
                    } else { Text("cityAcquire.map.releaseReview", tableName: table) }
                } else { Text("cityAcquire.map.noRecordedTitle", tableName: table) }
            } else { Text("cityAcquire.map.unavailable", tableName: table) }
            CityAcquisitionEntry(factory: factory, open: open)
        }
        .task(id: readID) {
            guard visible, scenePhase == .active, !Task.isCancelled else { return }
            let reader = factory?(); controller = reader; await reader?.load()
        }
        .onAppear { visible = true; readID = UUID() }
        .onDisappear { visible = false; controller?.suspend(); controller = nil }
        .onChange(of: scenePhase) { _, phase in
            controller?.suspend(); controller = nil
            if visible, phase == .active { readID = UUID() }
        }
        .onChange(of: controller?.current) { _, current in if current != true { controller?.invalidate() } }
    }
}
@MainActor struct CityAcquisitionView: View {
    private let table = "CityAcquisition"
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: CityAcquisitionController
    @State private var visible = false
    @State private var readID = UUID()
    private var interactive: Bool { visible && scenePhase == .active && controller.current }
    init(controller: CityAcquisitionController) { _controller = State(initialValue: controller) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text("cityAcquire.boundary", tableName: table).font(.footnote)
                Text(LocalizedStringKey(controller.messageKey), tableName: table).font(Theme.Font.cardTitle).fixedSize(horizontal: false, vertical: true)
                if controller.busy { ProgressView() }
                Button { guard interactive else { return }; readID = UUID() } label: { Text("cityAcquire.refresh", tableName: table) }.disabled(controller.busy || !interactive)
                if controller.current, controller.originalRequestID != nil {
                    Label { Text(controller.pendingRequestID == nil ? "cityAcquire.original.hint" : "cityAcquire.pending.hint", tableName: table) } icon: { Image(systemName: "clock.arrow.circlepath") }.font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Button { recoverOriginal() } label: { Text("cityAcquire.recover", tableName: table) }.disabled(controller.busy || !interactive)
                }
                if let quote = controller.selectedQuote {
                    CityAcquisitionCard { quoteContent(quote) }
                    Button { guard interactive else { return }; controller.prepareConfirmation() } label: { Text("cityAcquire.reviewConfirmation", tableName: table) }.modifier(CityAcquisitionPrimaryAction()).disabled(!interactive || !controller.canWrite || !quote.writeApproved || !quote.unexpired)
                }
                if let receipt = controller.receipt {
                    Text(receipt.succeeded ? "cityAcquire.receipt.success" : "cityAcquire.receipt.rejected", tableName: table)
                    if let code = receipt.errorCode { Text(Self.failure(code), tableName: table).font(.footnote) }
                    Text(verbatim: receipt.requestId).font(.footnote.monospaced()).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let title = receipt.title { Text("cityAcquire.receipt.historical", tableName: table).font(.footnote); titleContent(title) }
                }
                if let snapshot = controller.snapshot {
                    Text("cityAcquire.tasks.title", tableName: table).font(.headline)
                    if snapshot.candidates.isEmpty { Text("cityAcquire.tasks.none", tableName: table) }
                    ForEach(snapshot.candidates) { candidate in
                        CityAcquisitionCard {
                            Text(verbatim: candidate.pointId + " · " + candidate.taskId)
                            Text(candidate.eligibility == "QUOTE_AVAILABLE" ? "cityAcquire.task.eligible" : "cityAcquire.task.unavailable", tableName: table)
                            Button { requestQuote(candidate) } label: { Text("cityAcquire.quote", tableName: table) }.modifier(CityAcquisitionPrimaryAction()).disabled(!interactive || !controller.allows(candidate))
                        }
                    }
                }
                Text("cityAcquire.titles.title", tableName: table).font(.headline)
                ForEach(controller.titles) { title in titleContent(title) }
                Text("cityAcquire.lifecycleBoundary", tableName: table).font(.footnote)
            }.padding(.horizontal, Theme.Space.pageX).padding(.vertical, Theme.Space.s4)
        }.modifier(CityAcquisitionPageStyle()).navigationTitle(Text("cityAcquire.title", tableName: table))
        .accessibilityIdentifier("city.acquisition.screen")
        .sheet(item: Binding(get: { controller.confirmation }, set: { if $0 == nil { controller.cancelConfirmation() } })) { captured in
            NavigationStack {
                Form {
                    quoteContent(captured)
                    Text("cityAcquire.confirm.hint", tableName: table)
                    Button(role: .destructive) { confirm(captured) } label: { Text("cityAcquire.confirm.pay", tableName: table) }.modifier(CityAcquisitionPrimaryAction(destructive: true)).disabled(!interactive || !controller.canWrite || !captured.unexpired)
                    Button { controller.cancelConfirmation() } label: { Text("cityAcquire.confirm.cancel", tableName: table) }
                }.modifier(CityAcquisitionPageStyle()).navigationTitle(Text("cityAcquire.confirm.title", tableName: table))
            }
        }
        .task(id: readID) { guard visible, scenePhase == .active, !Task.isCancelled else { return }; await controller.open(activity: controller.activityID) }
        .onAppear { visible = true; controller.activate(); readID = UUID() }
        .onChange(of: scenePhase) { _, phase in
            controller.suspend()
            if visible, phase == .active { controller.activate(); readID = UUID() }
        }
        .onChange(of: controller.current) { _, current in if !current { controller.invalidate() } }
        .onDisappear { visible = false; controller.suspend() }
    }
    private func requestQuote(_ candidate: CityAcquisitionCandidate) {
        guard interactive else { return }; let activity = controller.activityID
        Task { await controller.requestQuote(candidate, activity: activity) }
    }
    private func confirm(_ quote: CityAcquisitionQuote) {
        guard interactive else { return }; let activity = controller.activityID
        Task { await controller.confirm(quote, activity: activity) }
    }
    private func recoverOriginal() {
        guard interactive else { return }; let activity = controller.activityID
        Task { await controller.recover(activity: activity) }
    }
    @ViewBuilder private func quoteContent(_ q: CityAcquisitionQuote) -> some View {
        Text("cityAcquire.quote.title", tableName: table).font(.headline)
        row("cityAcquire.quote.points", String(q.pointCost))
        row("cityAcquire.quote.actions", String(q.actionCost))
        row("cityAcquire.quote.payer", String(q.payerMemberId))
        row("cityAcquire.quote.team", q.beneficiaryTeamId)
        row("cityAcquire.quote.point", q.pointId)
        row("cityAcquire.quote.balance", String(q.pointsBalanceAtQuote))
        row("cityAcquire.quote.remainingActions", String(q.actionsRemainingAtQuote))
        row("cityAcquire.quote.limit", String(q.maxHoldingsPerTeam))
        row("cityAcquire.quote.term", String(q.termSeconds))
        row("cityAcquire.quote.expiry", q.expiresAt)
        row("cityAcquire.quote.release", String(q.releaseId))
        row("cityAcquire.quote.pointVersion", String(q.pointVersion))
        row("cityAcquire.quote.budgetVersion", String(q.budgetVersion))
        Text("cityAcquire.quote.currentRelease", tableName: table).font(.footnote)
        Text("cityAcquire.quote.assurance", tableName: table).font(.footnote)
        Text(verbatim: q.evidenceAcceptanceReason).font(.footnote)
        Text(verbatim: q.quoteHash).font(.footnote.monospaced()).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        if !q.unexpired { Text("cityAcquire.quote.expired", tableName: table) }
    }
    @ViewBuilder private func titleContent(_ t: CityAcquisitionTitle) -> some View {
        CityAcquisitionCard {
            Text(verbatim: t.pointId).font(Theme.Font.cardTitle).fixedSize(horizontal: false, vertical: true)
            Text(Self.status(t.status), tableName: table)
            row("cityAcquire.quote.team", t.ownerTeamId)
            if let points = t.pointCost { row("cityAcquire.title.debit", String(points)) }
            if let after = t.pointsAfter { row("cityAcquire.title.after", String(after)) }
            if let actions = t.actionCost { row("cityAcquire.quote.actions", String(actions)) }
            Text(verbatim: t.titleId).font(.caption).textSelection(.enabled)
        }
    }
    @ViewBuilder private func row(_ key: String, _ value: String) -> some View {
        if key == "cityAcquire.quote.points" || key == "cityAcquire.quote.actions" {
            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                Text(LocalizedStringKey(key), tableName: table).font(Theme.Font.label).foregroundStyle(.secondary)
                Text(verbatim: value).font(.title3.weight(.semibold)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }.accessibilityElement(children: .combine)
        } else {
            CityAcquisitionMetadataRow(label: Text(LocalizedStringKey(key), tableName: table), value: value)
        }
    }
    static func failure(_ code: String) -> LocalizedStringKey {
        switch code {
        case "POINT_ALREADY_OWNED", "TASK_EFFECT_ALREADY_COMMITTED": return "cityAcquire.failure.owned"
        case "INSUFFICIENT_POINTS": return "cityAcquire.failure.points"
        case "ACTION_BUDGET_EXHAUSTED", "ACTION_VERSION_CHANGED": return "cityAcquire.failure.actions"
        case "HOLDING_LIMIT_REACHED": return "cityAcquire.failure.limit"
        case "QUOTE_EXPIRED", "EVIDENCE_EXPIRED": return "cityAcquire.failure.expired"
        case "ORIGINAL_OUTCOME_UNRESOLVED", "ORIGINAL_CONFIRM_KEY_REQUIRED": return "cityAcquire.failure.original"
        default: return "cityAcquire.failure.changed"
        }
    }
    static func status(_ value: String) -> LocalizedStringKey {
        switch value {
        case "ACTIVE_TERM": return "cityAcquire.title.active"
        case "PAUSED_TERM_FROZEN": return "cityAcquire.title.paused"
        case "TERM_REVIEW_REQUIRED": return "cityAcquire.title.review"
        default: return "cityAcquire.title.sourceUnavailable"
        }
    }
}
