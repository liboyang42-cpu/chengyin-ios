import SwiftUI

@MainActor final class CoopInvitationReadModel: ObservableObject {
    struct Permit: Equatable { let id: UUID; let session: CoopFlowSession?; let kind: CoopFlowTargetKind }
    let reader: any CoopFlowReading
    let operationScope: String?
    @Published private(set) var kind: CoopFlowTargetKind = .merchant
    @Published private(set) var topics: [CoopFlowOwnedTopic] = []
    @Published private(set) var candidates: [CoopFlowTargetCandidate] = []
    @Published private(set) var topicID: Int?
    @Published private(set) var selected: Set<String> = []
    @Published private(set) var topicsFailed = false
    @Published private(set) var targetsFailed = false
    @Published private(set) var topicsBusy = false
    @Published private(set) var targetsBusy = false
    @Published private(set) var hasMore = true
    private var topicsReady = false, targetsReady = false
    private var page = 1, failedPage: Int?
    @Published private var visible = false
    @Published private var active = false
    private var generation = UUID(), topicRun: UUID?, targetRun: UUID?
    private var session: CoopFlowSession?
    init(reader: any CoopFlowReading, operationScope: String?) { self.reader = reader; self.operationScope = operationScope; session = reader.session }
    var permit: Permit { .init(id: generation, session: session, kind: kind) }
    var isCurrent: Bool { visible && active && session != nil && session == reader.session }
    var busy: Bool { topicsBusy || targetsBusy }
    var topic: CoopFlowOwnedTopic? { isCurrent ? topics.first { $0.id == topicID } : nil }
    private func accepts(_ value: Permit) -> Bool { isCurrent && value == permit && !Task.isCancelled }
    func appear(active: Bool) -> Permit {
        if session != reader.session { reset() }
        visible = true; self.active = active; return permit
    }
    func disappear() { visible = false; invalidateRuns() }
    func sceneChanged(active: Bool) { self.active = active; if !active { invalidateRuns() } }
    func identityChanged() { reset() }
    private func invalidateRuns() { generation = UUID(); topicRun = nil; targetRun = nil; topicsBusy = false; targetsBusy = false }
    private func reset() {
        invalidateRuns(); session = reader.session; topics = []; candidates = []; topicID = nil; selected = []
        topicsReady = false; targetsReady = false; topicsFailed = false; targetsFailed = false; page = 1; failedPage = nil; hasMore = true
    }
    func changeKind(_ value: CoopFlowTargetKind, permit old: Permit) -> Permit? {
        guard accepts(old), !busy, value != kind else { return nil }
        kind = value; reset(); return permit
    }
    func chooseTopic(_ id: Int?, permit value: Permit) {
        guard accepts(value), !topicsBusy, id == nil || topics.contains(where: { $0.id == id }) else { return }
        topicID = id
    }
    func toggle(_ id: String, permit value: Permit) {
        guard accepts(value), targetsReady, !targetsBusy, candidates.contains(where: { $0.id == id }) else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    func contexts(permit value: Permit) -> [CoopFlowInvitationContext]? {
        guard accepts(value), topicsReady, targetsReady, !busy, let topic, topic.inviteWindowOpen == true, !selected.isEmpty else { return nil }
        let result = candidates.filter { selected.contains($0.id) }.compactMap {
            CoopFlowInvitationContext(candidate: $0, topic: topic, scope: operationScope, session: session)
        }
        return result.count == selected.count ? result : nil
    }
    func loadInitial(_ value: Permit) async {
        guard accepts(value) else { return }
        if !topicsReady { await readTopics(value, requested: 1, append: false) }
        guard accepts(value) else { return }
        if !targetsReady { await retryTargets(value) }
    }
    func retryTopics(_ value: Permit) async {
        let requested = failedPage ?? 1
        await readTopics(value, requested: requested, append: requested > 1)
    }
    func more(_ value: Permit) async {
        guard topicsReady, hasMore, !topicsFailed else { return }
        await readTopics(value, requested: page, append: true)
    }
    private func refuses(_ error: Error) -> Bool {
        if let e = error as? CoopFlowFailure {
            switch e { case .permission, .disabled, .stale: return true; case .server(let code, _): return code == 401 || code == 403; default: break }
        }
        if let e = error as? APIError {
            switch e { case .unauthorized, .notConfigured: return true; case .httpStatus(let code): return code == 401 || code == 403; default: break }
        }
        return false
    }
    private func readTopics(_ value: Permit, requested: Int, append: Bool) async {
        guard accepts(value), !topicsBusy, requested > 0 else { return }
        let run = UUID(); topicRun = run; topicsBusy = true; topicsFailed = false
        defer { if topicRun == run { topicRun = nil; topicsBusy = false } }
        do {
            let result = try await reader.read(.ownedTopics(kind: value.kind, scope: operationScope, page: requested), isCurrent: { [weak self] in
                guard let self else { return false }; return self.accepts(value) && self.topicRun == run
            })
            guard accepts(value), topicRun == run else { return }
            guard let rows = result["rows"].rows else { throw CoopFlowFailure.malformed }
            let parsed = rows.compactMap(CoopFlowOwnedTopic.init)
            guard parsed.count == rows.count, Set(parsed.map(\.id)).count == parsed.count else { throw CoopFlowFailure.malformed }
            var seen = Set((append ? topics : []).map(\.id))
            topics = (append ? topics : []) + parsed.filter { seen.insert($0.id).inserted }
            if let id = topicID, !topics.contains(where: { $0.id == id }) { topicID = nil }
            topicsReady = true; failedPage = nil; hasMore = rows.count == 20; page = requested + 1
        } catch {
            guard accepts(value), topicRun == run else { return }
            topicsFailed = true; failedPage = requested
            if refuses(error) { topics = []; topicID = nil; topicsReady = false; hasMore = true; page = 1; failedPage = 1 }
        }
    }
    func retryTargets(_ value: Permit) async {
        guard accepts(value), !targetsBusy else { return }
        let run = UUID(); targetRun = run; targetsBusy = true; targetsFailed = false
        defer { if targetRun == run { targetRun = nil; targetsBusy = false } }
        do {
            let result = try await reader.read(value.kind == .merchant ? .merchants(name: nil) : .clubs(name: nil), isCurrent: { [weak self] in
                guard let self else { return false }; return self.accepts(value) && self.targetRun == run
            })
            guard accepts(value), targetRun == run else { return }
            guard let rows = result.rows else { throw CoopFlowFailure.malformed }
            let parsed = rows.compactMap { CoopFlowTargetCandidate(kind: value.kind, row: $0) }
            guard parsed.count == rows.count, Set(parsed.map(\.id)).count == parsed.count else { throw CoopFlowFailure.malformed }
            candidates = parsed; selected.formIntersection(Set(parsed.map(\.id))); targetsReady = true
        } catch {
            guard accepts(value), targetRun == run else { return }
            targetsFailed = true
            if refuses(error) { candidates = []; selected = []; targetsReady = false }
        }
    }
}

@MainActor struct CoopFlowNewInvitationView: View {
    let reader: any CoopFlowReading
    let operationScope: String?
    private struct Identity: Hashable { let reader: ObjectIdentifier; let scope: String? }
    var body: some View {
        CoopInvitationReadContent(reader: reader, operationScope: operationScope)
            .id(Identity(reader: ObjectIdentifier(reader), scope: operationScope))
    }
}
@MainActor private struct CoopInvitationReadContent: View {
    let reader: any CoopFlowReading
    let operationScope: String?
    @StateObject private var model: CoopInvitationReadModel
    @State private var search = ""
    @State private var editing: [CoopFlowInvitationContext] = []
    @State private var showEditor = false
    @Environment(\.scenePhase) private var scenePhase
    init(reader: any CoopFlowReading, operationScope: String?) {
        self.reader = reader; self.operationScope = operationScope
        _model = StateObject(wrappedValue: .init(reader: reader, operationScope: operationScope))
    }
    private var filtered: [CoopFlowTargetCandidate] {
        guard model.isCurrent else { return [] }
        return search.isEmpty ? model.candidates : model.candidates.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        let permit = model.permit
        Form {
            Picker("context.coop.kind", selection: Binding(get: { model.kind }, set: { value in
                guard let next = model.changeKind(value, permit: permit) else { return }
                editing = []; showEditor = false; search = ""
                Task { await model.loadInitial(next) }
            })) {
                Text("context.coop.merchant").tag(CoopFlowTargetKind.merchant)
                Text("coopflow.invite.club").tag(CoopFlowTargetKind.club)
            }.disabled(model.busy)
            Section("context.coop.topic") {
                if model.topicsFailed { Button("action.retry") { Task { await model.retryTopics(permit) } }.disabled(model.topicsBusy) }
                Picker("context.coop.topic", selection: Binding(get: { model.isCurrent ? model.topicID : nil }, set: { model.chooseTopic($0, permit: permit) })) {
                    Text("context.coop.chooseTopic").tag(Optional<Int>.none)
                    ForEach(model.isCurrent ? model.topics : []) { row in
                        Text(verbatim: [row.name, row.startDate, row.address, "#\(row.id)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).tag(Optional(row.id))
                    }
                }.disabled(model.topicsBusy)
                if model.topic != nil, model.topic?.inviteWindowOpen != true { Text("context.coop.closed") }
                if model.hasMore, !model.topics.isEmpty { Button("context.picker.more") { Task { await model.more(permit) } }.disabled(model.topicsBusy || model.topicsFailed) }
            }
            Section("context.coop.targets") {
                TextField("context.coop.search", text: $search).accessibilityIdentifier("context.coop.search")
                if model.busy { ProgressView("cooperation.loading") }
                if model.targetsFailed { Button("action.retry") { Task { await model.retryTargets(permit) } }.disabled(model.targetsBusy) }
                if !model.busy, !model.targetsFailed, filtered.isEmpty { Text("context.picker.empty") }
                ForEach(filtered) { candidate in
                    Button { model.toggle(candidate.id, permit: permit) } label: {
                        HStack { Text(verbatim: candidate.name); Spacer(); if model.selected.contains(candidate.id) { Image(systemName: "checkmark") } }
                    }.disabled(model.targetsBusy || !model.isCurrent)
                        .accessibilityAddTraits(model.selected.contains(candidate.id) ? .isSelected : [])
                        .accessibilityIdentifier("context.coop.target.\(candidate.id)")
                }
            }
            if !model.selected.isEmpty, model.isCurrent {
                LabeledContent("context.coop.selected", value: String(model.selected.count))
                Button("context.coop.continue") {
                    guard let contexts = model.contexts(permit: permit) else { return }
                    editing = contexts; showEditor = true
                }.disabled(model.contexts(permit: permit) == nil)
            }
            CoopFlowSafetyNotice()
        }.navigationTitle("context.coop.new").scrollDismissesKeyboard(.interactively)
            .onAppear {
                let value = model.appear(active: scenePhase == .active)
                Task { await model.loadInitial(value) }
            }
            .onChange(of: reader.session) { _, _ in
                model.identityChanged(); editing = []; showEditor = false; search = ""
                let value = model.permit; Task { await model.loadInitial(value) }
            }
            .onChange(of: scenePhase) { _, phase in
                model.sceneChanged(active: phase == .active)
                if phase == .active { let value = model.permit; Task { await model.loadInitial(value) } }
            }
            .onDisappear { model.disappear() }
            .sheet(isPresented: $showEditor) { NavigationStack { CoopFlowBatchInviteEditor(reader: reader, contexts: editing) } }
    }
}

@MainActor struct CoopPeerCreditView: View {
    let reader: any CoopFlowReading
    let peer: CoopPeerMember
    @State private var credit: CoopFlowJSON?
    @State private var summary: CoopFlowJSON?
    @State private var creditFailed = false
    @State private var summaryFailed = false
    @State private var busy = false
    @State private var generation = 0
    var body: some View {
        List {
            if busy { ProgressView("cooperation.loading") }
            Section("coopflow.credit") {
                if creditFailed { Text("coopflow.read.failed"); Button("action.retry") { Task { await load() } } }
                else if let credit {
                    if credit == .null || credit == .object([:]) { Text("context.coop.noReputation") }
                    else { CoopFlowFields(value: credit, keys: ["fulfillmentRate", "violationCount"]) }
                }
            }
            Section("coopflow.reviews") {
                if summaryFailed { Text("coopflow.read.failed"); Button("action.retry") { Task { await load() } } }
                else if let summary {
                    if summary == .null || summary == .object([:]) { Text("context.coop.noReputation") }
                    if let count = summary["count"].integer { LabeledContent("context.coop.reviewCount", value: String(count)) }
                    if let avg = summary["avg"].text { LabeledContent("context.coop.reviewAverage", value: avg) }
                    if summary["count"].integer == 0 { Text("coopflow.reviews.empty") }
                }
            }
        }.navigationTitle("context.coop.peerCredit")
            .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0)") { await load() }
            .onChange(of: reader.session) { _, _ in generation += 1; credit = nil; summary = nil; busy = false }
            .onDisappear { generation += 1; busy = false }
    }
    private func load() async {
        generation += 1; let request = generation, session = reader.session
        credit = nil; summary = nil; creditFailed = false; summaryFailed = false; busy = true
        guard session != nil else { busy = false; return }
        async let a: Void = readCredit(request: request, session: session)
        async let b: Void = readSummary(request: request, session: session)
        _ = await (a, b)
        if request == generation { busy = false }
    }
    private func readCredit(request: Int, session: CoopFlowSession?) async {
        do {
            let value = try await reader.read(.credit(memberID: peer.memberID))
            guard request == generation, session == reader.session, !Task.isCancelled else { return }
            credit = value["credit"] == .null ? value : value["credit"]
        } catch { if request == generation, session == reader.session { creditFailed = true } }
    }
    private func readSummary(request: Int, session: CoopFlowSession?) async {
        do {
            let value = try await reader.read(.reviewSummary(memberID: peer.memberID))
            guard request == generation, session == reader.session, !Task.isCancelled else { return }
            summary = value["summary"]
        } catch { if request == generation, session == reader.session { summaryFailed = true } }
    }
}

@MainActor struct CoopFlowBatchInviteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let reader: any CoopFlowReading
    let contexts: [CoopFlowInvitationContext]
    @State private var message = ""
    @State private var fixed = false
    @State private var fee = ""
    @State private var discard = false
    @FocusState private var typing: Bool
    private var drafts: [CoopFlowInvitation]? {
        guard !contexts.isEmpty, contexts.allSatisfy({ $0.session == reader.session }) else { return nil }
        let compensation: CoopFlowCompensation
        if fixed {
            guard let value = Decimal(string: fee, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
            compensation = .fixed(value)
        } else { compensation = .traffic }
        return try? contexts.map { try $0.invitation(message: message, compensation: compensation, currentSession: reader.session) }
    }
    private var dirty: Bool { !message.isEmpty || fixed || !fee.isEmpty }
    var body: some View {
        Form {
            Section("context.coop.targets") { ForEach(contexts) { Text(verbatim: $0.recipientName) } }
            TextField("coopflow.field.message", text: $message, axis: .vertical).lineLimit(3...8).focused($typing)
            Toggle("coopflow.fixed", isOn: $fixed)
            if fixed { TextField("coopflow.field.fixedFee", text: $fee).keyboardType(.decimalPad).focused($typing); Text("coopflow.currency") }
            if let drafts {
                NavigationLink("coopflow.reviewAction") {
                    List {
                        Text("context.coop.individualReviews")
                        ForEach(Array(drafts.enumerated()), id: \.offset) { index, draft in
                            NavigationLink(contexts[index].recipientName) { CoopFlowRequestPreview(operation: .invite(draft)) }
                        }
                        CoopFlowSafetyNotice()
                    }.navigationTitle("coopflow.reviewAction")
                }
            }
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.invite.title").scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { if dirty { discard = true } else { dismiss() } } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("action.done") { typing = false } }
            }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("coopflow.invite.discardPrompt", isPresented: $discard) {
                Button("coopflow.invite.discard", role: .destructive) { dismiss() }
                Button("action.cancel", role: .cancel) { }
            }
            .onChange(of: reader.session) { _, _ in message = ""; fee = ""; fixed = false; dismiss() }
    }
}
