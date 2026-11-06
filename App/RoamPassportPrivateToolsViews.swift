import SwiftUI

/// Mini-program subpackageTools/capsule, exploration-goals and exploration-export.
/// Owner-only private records: every write is explicitly reviewed, keeps its request ID for readback
/// or exact retry, and is refused unless a reviewed write approval exists (none in production today).

/// 探索目标 / 时光胶囊 passport tiles (pages/roam `passport.tiles`, NEW since 2026-10-14).
@MainActor struct RoamPassportPrivateLinks: View {
    let tools: (any RoamPrivateToolsServing)?
    var body: some View {
        NavigationLink { RoamExplorationGoalsView(tools: tools) } label: {
            RoamPassportTileLabel(title: "roam.goals.title", subtitle: "roam.goals.tile", systemImage: "flag")
        }.accessibilityIdentifier("roam.goals.open")
        NavigationLink { RoamCapsuleView(tools: tools) } label: {
            RoamPassportTileLabel(title: "roam.capsule.title", subtitle: "roam.capsule.tile", systemImage: "clock")
        }.accessibilityIdentifier("roam.capsule.open")
    }
}

private struct RoamPassportTileLabel: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    Text("roam.private.new").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: systemImage) }
    }
}

struct RoamPrivateIssueView: View {
    let issue: RoamPrivateToolIssue
    var retry: (() -> Void)? = nil
    var dismiss: (() -> Void)? = nil
    private var text: Text {
        switch issue {
        case .signInRequired: return Text("roam.signInRequired")
        case .notConfigured: return Text("roam.notConfigured")
        case .readFailed: return Text("roam.private.readFailed")
        case .changedContext: return Text("roam.private.changedContext")
        case .writesDisabled: return Text("roam.private.writesDisabled")
        case .outcomeUnknown: return Text("roam.private.outcomeUnknown")
        case .rejected(let message): return message.map { Text(verbatim: $0) } ?? Text("roam.private.rejected")
        case .invalidDraft: return Text("roam.private.invalidDraft")
        case .pendingFirst: return Text("roam.private.pendingFirst")
        case .expired: return Text("roam.export.expired")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { text } icon: { Image(systemName: "exclamationmark.circle") }
            HStack {
                if let retry, issue != .signInRequired, issue != .notConfigured {
                    Button("action.retry", action: retry).buttonStyle(.borderless).accessibilityIdentifier("roam.private.retry")
                }
                if let dismiss { Button("roam.private.dismiss", action: dismiss).buttonStyle(.borderless).accessibilityIdentifier("roam.private.dismiss") }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("roam.private.issue")
    }
}

/// Shanghai calendar-day bridge for DatePicker values.
enum RoamShanghaiPicker {
    static let timeZone = TimeZone(secondsFromGMT: RoamShanghaiCalendar.offsetSeconds)!
    static func date(_ text: String) -> Date {
        let day = RoamShanghaiCalendar.parseDate(text) ?? 0
        return Date(timeIntervalSince1970: TimeInterval(day * RoamShanghaiCalendar.dayMilliseconds / 1000 + 4 * 3600))
    }
    static func text(_ date: Date) -> String { RoamShanghaiCalendar.dateText(dayNumber: RoamShanghaiCalendar.dayNumber(now: date)) }
}

/// A page instance is tied to the actual reader and exact local scope, not just an account number.
struct RoamPrivatePageScope: Hashable {
    let reader: ObjectIdentifier
    let storageKey: String?
    let epoch: UInt64?
    let readScope: UUID?
    @MainActor init(_ tools: any RoamPrivateToolsServing) {
        reader = ObjectIdentifier(tools)
        let identity = tools.identity
        storageKey = identity?.scope.storageKey; epoch = identity?.epoch
        readScope = (tools as? RoamPrivateToolsSessionReader)?.readScope
    }
}

/// UI lifetime only. Pending payloads and durable request IDs remain in the original reader.
/// Issued writer/receipt work is never stored in the cancellable ordinary-read task.
@MainActor final class RoamPrivatePageOwner: ObservableObject {
    private let tools: any RoamPrivateToolsServing
    private let scope: RoamPrivatePageScope
    @Published private(set) var active = false
    @Published private(set) var foreground = false
    @Published private(set) var settlementInFlight = false
    @Published private(set) var readInFlight = false
    private var mounted = false
    private var ticket = UUID()
    private var actionRevision = UUID()
    private var readTask: Task<Void, Never>?
    private var currentReadID: UUID?
    init(tools: any RoamPrivateToolsServing) { self.tools = tools; scope = .init(tools) }
    var isPresented: Bool { active && scope == RoamPrivatePageScope(tools) && tools.identity != nil && tools.isConfigured }
    var acceptsInput: Bool { isPresented && foreground }
    func appear(foreground: Bool) -> Bool { mounted = true; return activate(foreground: foreground) }
    func activate(foreground: Bool) -> Bool {
        self.foreground = foreground
        guard mounted, foreground, !active, tools.identity != nil,
              scope == RoamPrivatePageScope(tools), tools.isConfigured else { return false }
        active = true; ticket = UUID(); return true
    }
    // A system interruption is not departure, but a previously queued action cannot start afterward.
    func inactive() { foreground = false; actionRevision = UUID() }
    func retire(leaving: Bool = false) {
        if leaving { mounted = false }
        active = false; foreground = false; ticket = UUID(); actionRevision = UUID()
        readTask?.cancel(); readTask = nil; currentReadID = nil; readInFlight = false
        // Only the original operation may finish settlementInFlight. Never cancel/retry it here.
    }
    private func accepts(_ offered: UUID) -> Bool { acceptsInput && ticket == offered }
    func read(_ work: @escaping @MainActor () async -> Void) {
        let offered = ticket, action = actionRevision
        readTask = Task { [self] in
            guard accepts(offered), action == actionRevision else { return }
            await readNow(work)
        }
    }
    func readNow(_ work: @MainActor () async -> Void) async {
        let offered = ticket
        guard accepts(offered), !settlementInFlight, !readInFlight, !Task.isCancelled else { return }
        let readID = UUID(); currentReadID = readID
        readInFlight = true; await work()
        // Inactive retires queued actions without cancelling an already-issued ordinary read.
        // Only this same read can release its busy state, never a replacement read.
        guard currentReadID == readID else { return }
        currentReadID = nil; readInFlight = false
    }
    func settle<Value>(write: Bool, _ work: @escaping @MainActor () async -> Value,
                       refresh: @escaping @MainActor () async -> Void,
                       finished: @escaping @MainActor (Value) -> Void = { _ in }) {
        let offered = ticket, action = actionRevision
        Task { [self] in
            guard accepts(offered), action == actionRevision, !settlementInFlight, !readInFlight, !Task.isCancelled,
                  !write || tools.allowsWrites else { return }
            settlementInFlight = true
            let result = await work()
            settlementInFlight = false
            if isPresented && ticket == offered { finished(result) }
            // Foreground return during settlement waits for it, then reads metadata only.
            else if acceptsInput { read(refresh) }
        }
    }
}

// MARK: 时光胶囊

@MainActor struct RoamCapsuleView: View {
    let tools: (any RoamPrivateToolsServing)?
    var body: some View {
        Group {
            if let tools { RoamCapsuleContent(tools: tools).id(RoamPrivatePageScope(tools)) }
            else { List { RoamPrivateIssueView(issue: .notConfigured) }.accessibilityIdentifier("roam.capsule.screen") }
        }.appNavigationTitle("roam.capsule.title")
    }
}

@MainActor private struct RoamCapsuleContent: View {
    let tools: any RoamPrivateToolsServing
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var page: RoamPrivatePageOwner
    @State private var model: RoamCapsuleCoordinator
    @State private var composing = false
    @State private var text = ""
    @State private var unlockDate = ""
    @State private var custom = false
    @State private var lockedTip = false
    init(tools: any RoamPrivateToolsServing) {
        self.tools = tools; _page = StateObject(wrappedValue: RoamPrivatePageOwner(tools: tools))
        _model = State(initialValue: RoamCapsuleCoordinator(tools: tools))
    }
    private var options: [RoamCapsuleUnlockOption] { RoamCapsuleUnlockOption.options(now: tools.now) }
    private func presetKey(_ preset: RoamCapsuleUnlockOption.Preset) -> LocalizedStringKey {
        switch preset { case .month: return "roam.capsule.unlock.month"; case .halfYear: return "roam.capsule.unlock.halfYear"; case .year: return "roam.capsule.unlock.year" }
    }
    private var showsList: Bool { model.opened == nil && !model.deleted }
    var body: some View {
        List {
            if page.isPresented {
            if tools.isOfflineExample { Section { RoamExperienceNotice(offline: true) } }
            if let issue = model.issue {
                Section { RoamPrivateIssueView(issue: issue, retry: issue == .outcomeUnknown ? nil : { page.read { await model.load() } }) }
            }
            if model.pending != nil || model.pendingRequestID != nil {
                Section {
                    Text("roam.capsule.pending").accessibilityIdentifier("roam.capsule.pending")
                    Button("roam.capsule.verify") { page.settle(write: false, { await model.verifyPending() }, refresh: { await model.load() }) }
                        .disabled(model.isBusy).accessibilityIdentifier("roam.capsule.verify")
                    // A restored lock has only the original request ID. Checking that
                    // receipt is the only action; the body is never rebuilt in order to resend.
                    if model.pending != nil {
                        Button("roam.capsule.retryOriginal") { page.settle(write: true, { await model.retryPending() }, refresh: { await model.load() }) }
                            .disabled(model.isBusy || !model.canWrite).accessibilityIdentifier("roam.capsule.retryOriginal")
                    }
                }
            }
            if let opened = model.opened {
                Section {
                    Text("roam.capsule.openedMeta \(opened.unlockDateText ?? "—") \(opened.createdDateText ?? "—")").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: opened.body ?? "").font(.body).textSelection(.enabled).accessibilityIdentifier("roam.capsule.body")
                    if let photo = opened.photoURL, let url = URL(string: photo), url.scheme == "https" {
                        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .accessibilityLabel(Text("roam.capsule.photo"))
                    }
                    Button("roam.capsule.keep") { page.read { await model.closeOpened() } }.accessibilityIdentifier("roam.capsule.keep")
                    if model.canWrite {
                        Button("roam.capsule.delete", role: .destructive) { guard page.acceptsInput, !page.settlementInFlight else { return }; model.prepareDelete() }.accessibilityIdentifier("roam.capsule.delete")
                    }
                }.accessibilityIdentifier("roam.capsule.opened")
            }
            if model.deleted {
                Section {
                    Text("roam.capsule.deleted").accessibilityIdentifier("roam.capsule.deleted")
                    Button("roam.capsule.backToList") { page.read { await model.closeOpened() } }.accessibilityIdentifier("roam.capsule.backToList")
                }
            }
            if composing { composer }
            if showsList { list }
            } else if scenePhase == .active && (tools.identity == nil || !tools.isConfigured) {
                Section { RoamPrivateIssueView(issue: tools.identity == nil ? .signInRequired : .notConfigured) }
            }
        }
        .disabled(!page.acceptsInput || page.settlementInFlight)
        .privacySensitive()
        .toolbar {
            // Writing is only offered when it can be saved.
            if page.acceptsInput && !composing && tools.allowsWrites {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startComposing() } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("roam.capsule.write")).accessibilityIdentifier("roam.capsule.write")
                }
            }
        }
        .onAppear { activate(appearing: true) }
        .refreshable { await page.readNow { await model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { retire() }
            else if phase == .active { activate() }
            else { page.inactive() }
        }
        .onChange(of: tools.isConfigured) { _, configured in
            if configured { activate() } else { retire() }
        }
        .onDisappear { retire(leaving: true) }
        .alert("roam.capsule.lockedTip", isPresented: $lockedTip) { Button("roam.private.ok", role: .cancel) {} }
        .confirmationDialog("roam.capsule.confirmTitle", isPresented: Binding(get: { model.review != nil }, set: { if !$0 { model.cancelReview() } }), titleVisibility: .visible) {
            Button("roam.capsule.seal") { page.settle(write: true, { await model.confirmCreate() }, refresh: { await model.load() }) { saved in if saved { composing = false; text = "" } } }
                .accessibilityIdentifier("roam.capsule.confirmSeal")
            Button("roam.private.notNow", role: .cancel) { model.cancelReview() }
        } message: { Text("roam.capsule.confirmMessage \(model.review?.unlockDate ?? "")") }
        .confirmationDialog("roam.capsule.deleteTitle", isPresented: Binding(get: { model.deleteReview != nil }, set: { if !$0 { model.cancelDelete() } }), titleVisibility: .visible) {
            Button("roam.capsule.delete", role: .destructive) { page.settle(write: true, { await model.confirmDelete() }, refresh: { await model.load() }) }
                .accessibilityIdentifier("roam.capsule.confirmDelete")
            Button("roam.private.notNow", role: .cancel) { model.cancelDelete() }
        } message: { Text("roam.capsule.deleteMessage") }
        .accessibilityIdentifier("roam.capsule.screen")
    }
    private func activate(appearing: Bool = false) {
        let started = appearing ? page.appear(foreground: scenePhase == .active) : page.activate(foreground: scenePhase == .active)
        if started { model.resume(); page.read { await model.load() } }
    }
    private func retire(leaving: Bool = false) {
        page.retire(leaving: leaving); model.suspend()
        text = ""; composing = false; lockedTip = false
    }
    private func startComposing() {
        guard page.acceptsInput, !page.settlementInFlight, !model.isBusy else { return }
        if unlockDate.isEmpty { unlockDate = options[2].date }
        composing = true
    }
    @ViewBuilder private var composer: some View {
        Section {
            TextField("roam.capsule.placeholder", text: $text, axis: .vertical)
                .lineLimit(4...12).disabled(model.isBusy || model.pending != nil)
                .onChange(of: text) { _, value in if value.utf16.count > RoamCapsuleDraft.bodyLimit { text = String(value.utf16.prefix(RoamCapsuleDraft.bodyLimit)) ?? value } }
                .accessibilityIdentifier("roam.capsule.text")
            Text("roam.capsule.count \(text.utf16.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        } header: { Text("roam.capsule.bodyLabel") }
        Section {
            LabeledContent("roam.capsule.unlockLabel") { Text(verbatim: unlockDate).monospacedDigit() }
                .accessibilityIdentifier("roam.capsule.unlockDate")
            HStack {
                ForEach(options) { option in
                    Button { unlockDate = option.date; custom = false } label: { Text(presetKey(option.preset)) }
                        .buttonStyle(.bordered).tint(!custom && unlockDate == option.date ? Color.accentColor : Color.secondary)
                        .accessibilityIdentifier("roam.capsule.unlock.\(option.preset.rawValue)")
                }
            }.disabled(model.isBusy)
            DatePicker("roam.capsule.unlockCustom", selection: Binding(get: { RoamShanghaiPicker.date(unlockDate.isEmpty ? options[2].date : unlockDate) },
                                                                      set: { unlockDate = RoamShanghaiPicker.text($0); custom = true }),
                       in: RoamShanghaiPicker.date(RoamCapsuleUnlockOption.minimumDate(now: tools.now))..., displayedComponents: .date)
                .environment(\.timeZone, RoamShanghaiPicker.timeZone).disabled(model.isBusy)
                .accessibilityIdentifier("roam.capsule.unlockCustom")
        }
        Section {
            Button("roam.capsule.seal") { guard page.acceptsInput, !page.settlementInFlight else { return }; model.prepareCreate(body: text, unlockDate: unlockDate) }
                .buttonStyle(.questifyPrimary)
                .disabled(model.isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unlockDate.isEmpty || model.pending != nil || !model.canWrite)
                .accessibilityIdentifier("roam.capsule.seal")
            Button("roam.capsule.later") { composing = false }.disabled(model.isBusy).accessibilityIdentifier("roam.capsule.later")
        }
    }
    @ViewBuilder private var list: some View {
        Section {
            if model.isBusy && model.items.isEmpty { ProgressView("roam.private.loading") }
            ForEach(model.items) { item in
                if item.state == .open {
                    Button { page.read { await model.open(item) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("roam.capsule.openReady \(item.createdDateText ?? "—")").font(.caption).foregroundStyle(.tint)
                            Text("roam.capsule.openIt").font(.headline)
                        }
                    }.accessibilityIdentifier("roam.capsule.row.open")
                } else {
                    Button { lockedTip = true } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("roam.capsule.writtenOn \(item.createdDateText ?? "—")").font(.caption).foregroundStyle(.secondary)
                            Text("roam.capsule.daysLeft \(item.daysLeft(now: tools.now))").font(.title2.bold()).monospacedDigit()
                            Text("roam.capsule.unlocksOn \(item.unlockDateText ?? "—")").font(.caption).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }.buttonStyle(.plain).accessibilityIdentifier("roam.capsule.row.locked")
                }
            }
            if !model.isBusy && model.items.isEmpty && model.phase == .ready {
                Text("roam.capsule.empty").foregroundStyle(.secondary).accessibilityIdentifier("roam.capsule.empty")
            }
            if model.hasMore && !model.isBusy {
                Button("roam.tools.loadMore") { page.read { await model.load(more: true) } }.accessibilityIdentifier("roam.capsule.more")
            }
        } header: {
            HStack { Text("roam.capsule.mine"); Spacer(); if !model.items.isEmpty { Text("roam.capsule.count.items \(model.items.count)") } }
        }
    }
}

// MARK: 探索目标

@MainActor struct RoamExplorationGoalsView: View {
    let tools: (any RoamPrivateToolsServing)?
    var body: some View {
        Group {
            if let tools { RoamGoalsContent(tools: tools).id(RoamPrivatePageScope(tools)) }
            else { List { RoamPrivateIssueView(issue: .notConfigured) }.accessibilityIdentifier("roam.goals.screen") }
        }.appNavigationTitle("roam.goals.title")
    }
}

extension RoamGoalMetric {
    var titleKey: LocalizedStringKey { self == .distinctRoutes ? "roam.goals.metric.routes" : "roam.goals.metric.days" }
}
extension RoamGoalState {
    var titleKey: LocalizedStringKey {
        switch self {
        case .active: return "roam.goals.state.active"; case .scheduled: return "roam.goals.state.scheduled"
        case .achieved: return "roam.goals.state.achieved"; case .ended: return "roam.goals.state.ended"; case .cancelled: return "roam.goals.state.cancelled"
        }
    }
}

@MainActor private struct RoamGoalsContent: View {
    let tools: any RoamPrivateToolsServing
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var page: RoamPrivatePageOwner
    @State private var model: RoamGoalsCoordinator
    @State private var creating = false
    @State private var metric: RoamGoalMetric = .distinctRoutes
    @State private var target = 5
    @State private var period: RoamGoalPeriod.Kind = .month
    @State private var startDate = ""
    @State private var endDate = ""
    init(tools: any RoamPrivateToolsServing) {
        self.tools = tools; _page = StateObject(wrappedValue: RoamPrivatePageOwner(tools: tools))
        _model = State(initialValue: RoamGoalsCoordinator(tools: tools))
    }
    private func periodKey(_ kind: RoamGoalPeriod.Kind) -> LocalizedStringKey {
        switch kind { case .week: return "roam.goals.period.week"; case .month: return "roam.goals.period.month"; case .thirtyDays: return "roam.goals.period.thirty" }
    }
    private func amountText(_ metric: RoamGoalMetric, _ value: Int) -> Text {
        metric == .distinctRoutes ? Text("roam.goals.unit.routes \(value)") : Text("roam.goals.unit.days \(value)")
    }
    var body: some View {
        List {
            if page.isPresented {
            if tools.isOfflineExample { Section { RoamExperienceNotice(offline: true) } }
            if let issue = model.issue, !(creating && (issue == .invalidDraft || isRejection(issue))) {
                Section { RoamPrivateIssueView(issue: issue, retry: issue == .outcomeUnknown ? nil : { page.read { await model.load() } }) }
            }
            if model.pending != nil || model.pendingRequestID != nil {
                Section {
                    Text("roam.goals.pending").accessibilityIdentifier("roam.goals.pending")
                    Button("roam.goals.verify") { page.settle(write: false, { await model.verifyPending() }, refresh: { await model.load() }) }
                        .disabled(model.isBusy).accessibilityIdentifier("roam.goals.verify")
                    // Restored lock: receipt check only. No draft means no resend.
                    if model.pending != nil {
                        Button("roam.goals.retryOriginal") { page.settle(write: true, { await model.retryPending() }, refresh: { await model.load() }) }
                            .disabled(model.isBusy || !model.canWrite).accessibilityIdentifier("roam.goals.retryOriginal")
                    }
                }
            }
            if let detail = model.detail { detailSection(detail) }
            if creating { form }
            Section {
                if model.isBusy && model.rows.isEmpty { ProgressView("roam.private.loading") }
                ForEach(model.rows) { row in
                    Button { page.read { await model.open(row.id) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                (Text(verbatim: "\(row.progress) / ") + amountText(row.metric, row.target)).font(.headline).monospacedDigit()
                                Spacer()
                                Text(row.state.titleKey).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(row.state == .achieved ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
                            }
                            ProgressView(value: Double(row.percent), total: 100)
                            (Text(verbatim: "\(row.startDate) – \(row.endDateExclusive) · ") + Text(row.metric.titleKey)).font(.caption).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }.buttonStyle(.plain).accessibilityIdentifier("roam.goals.row")
                }
                if !model.isBusy && model.rows.isEmpty && model.phase == .ready {
                    Text("roam.goals.empty").foregroundStyle(.secondary).accessibilityIdentifier("roam.goals.empty")
                }
                if model.hasMore && !model.isBusy {
                    Button("roam.tools.loadMore") { page.read { await model.load(more: true) } }.accessibilityIdentifier("roam.goals.more")
                }
            } header: {
                HStack { Text("roam.goals.mine"); Spacer(); if !model.rows.isEmpty { Text("roam.goals.count \(model.rows.count)") } }
            }
            } else if scenePhase == .active && (tools.identity == nil || !tools.isConfigured) {
                Section { RoamPrivateIssueView(issue: tools.identity == nil ? .signInRequired : .notConfigured) }
            }
        }
        .disabled(!page.acceptsInput || page.settlementInFlight)
        .privacySensitive()
        .toolbar {
            if page.acceptsInput && !creating && tools.allowsWrites {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startCreating() } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("roam.goals.new")).accessibilityIdentifier("roam.goals.new")
                }
            }
        }
        .onAppear { activate(appearing: true) }
        .refreshable { await page.readNow { await model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { retire() }
            else if phase == .active { activate() }
            else { page.inactive() }
        }
        .onChange(of: tools.isConfigured) { _, configured in
            if configured { activate() } else { retire() }
        }
        .onDisappear { retire(leaving: true) }
        .confirmationDialog("roam.goals.confirmTitle", isPresented: Binding(get: { model.review != nil }, set: { if !$0 { model.cancelCreateReview() } }), titleVisibility: .visible) {
            Button("roam.goals.create") { page.settle(write: true, { await model.confirmCreate() }, refresh: { await model.load() }) { saved in if saved { creating = false } } }.accessibilityIdentifier("roam.goals.confirmCreate")
            Button("roam.private.notNow", role: .cancel) { model.cancelCreateReview() }
        } message: {
            if let review = model.review { amountText(review.metric, review.target) + Text(verbatim: " · \(review.startDate) – \(review.endDateExclusive)") }
        }
        .confirmationDialog("roam.goals.cancelTitle", isPresented: Binding(get: { model.cancelReview != nil }, set: { if !$0 { model.keepGoal() } }), titleVisibility: .visible) {
            Button("roam.goals.cancelGoal", role: .destructive) { page.settle(write: true, { await model.confirmCancel() }, refresh: { await model.load() }) }.accessibilityIdentifier("roam.goals.confirmCancel")
            Button("roam.goals.keep", role: .cancel) { model.keepGoal() }
        } message: { Text("roam.goals.cancelMessage") }
        .accessibilityIdentifier("roam.goals.screen")
    }
    private func activate(appearing: Bool = false) {
        let started = appearing ? page.appear(foreground: scenePhase == .active) : page.activate(foreground: scenePhase == .active)
        if started { model.resume(); page.read { await model.load() } }
    }
    private func retire(leaving: Bool = false) {
        page.retire(leaving: leaving); model.suspend()
        if leaving { creating = false; startDate = ""; endDate = "" }
    }
    private func isRejection(_ issue: RoamPrivateToolIssue) -> Bool { if case .rejected = issue { return true }; return false }
    private func usePeriod(_ kind: RoamGoalPeriod.Kind) {
        guard let value = model.periods.first(where: { $0.kind == kind }) else { return }
        period = kind; startDate = value.startDate; endDate = value.endDateExclusive
    }
    private func startCreating() { guard page.acceptsInput, !page.settlementInFlight, !model.isBusy else { return }; usePeriod(period); model.dismissIssue(); creating = true }
    @ViewBuilder private func detailSection(_ detail: RoamExplorationGoal) -> some View {
        Section {
            (Text(detail.metric.titleKey) + Text(verbatim: " · ") + Text(detail.state.titleKey)).font(.caption).foregroundStyle(.secondary)
            (Text(verbatim: "\(detail.progress)").font(Theme.Font.dataXL) + Text(verbatim: " / \(detail.target)").font(.title2))
                .monospacedDigit().accessibilityIdentifier("roam.goals.detail.progress")
            ProgressView(value: Double(detail.percent), total: 100)
            Text("roam.goals.range \(detail.startDate) \(detail.endDateExclusive)").font(.caption).foregroundStyle(.secondary)
            Button("roam.goals.collapse") { model.closeDetail() }.accessibilityIdentifier("roam.goals.collapse")
            if detail.state.isCancellable && model.canWrite {
                Button("roam.goals.cancelThis", role: .destructive) { guard page.acceptsInput, !page.settlementInFlight else { return }; model.prepareCancel() }.accessibilityIdentifier("roam.goals.cancelThis")
            }
        }.accessibilityIdentifier("roam.goals.detail")
    }
    @ViewBuilder private var form: some View {
        Section {
            Picker("roam.goals.metric", selection: $metric) {
                ForEach(RoamGoalMetric.allCases) { Text($0.titleKey).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("roam.goals.metricPicker")
            Stepper(value: $target, in: 1...100) { amountText(metric, target).monospacedDigit() }
                .accessibilityIdentifier("roam.goals.target")
        }.disabled(model.isBusy || model.pending != nil)
        Section {
            Picker("roam.goals.period", selection: Binding(get: { period }, set: { usePeriod($0) })) {
                ForEach(RoamGoalPeriod.Kind.allCases, id: \.self) { Text(periodKey($0)).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("roam.goals.periodPicker")
            DatePicker("roam.goals.start", selection: Binding(get: { RoamShanghaiPicker.date(startDate) }, set: { startDate = RoamShanghaiPicker.text($0) }),
                       in: RoamShanghaiPicker.date(model.today)..., displayedComponents: .date)
                .environment(\.timeZone, RoamShanghaiPicker.timeZone).accessibilityIdentifier("roam.goals.startDate")
            DatePicker("roam.goals.end", selection: Binding(get: { RoamShanghaiPicker.date(endDate) }, set: { endDate = RoamShanghaiPicker.text($0) }),
                       in: RoamShanghaiPicker.date(startDate)..., displayedComponents: .date)
                .environment(\.timeZone, RoamShanghaiPicker.timeZone).accessibilityIdentifier("roam.goals.endDate")
        } header: { Text("roam.goals.period") }
            .disabled(model.isBusy || model.pending != nil)
        if let issue = model.issue, issue == .invalidDraft || isRejection(issue) {
            // Refusals stay on the form: adjust and create again; the same payload is never resent.
            Section { RoamPrivateIssueView(issue: issue, dismiss: { model.dismissIssue() }) }
        }
        Section {
            Button("roam.goals.create") { guard page.acceptsInput, !page.settlementInFlight else { return }; model.prepareCreate(metric: metric, target: target, startDate: startDate, endDateExclusive: endDate) }
                .disabled(model.isBusy || model.pending != nil || !model.canWrite).accessibilityIdentifier("roam.goals.create")
            Button("roam.goals.later") { creating = false; model.dismissIssue() }.disabled(model.isBusy).accessibilityIdentifier("roam.goals.later")
        }
    }
}
