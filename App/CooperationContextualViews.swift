import SwiftUI

@MainActor struct CoopFlowNewInvitationView: View {
    let reader: any CoopFlowReading
    let operationScope: String?
    @State private var kind: CoopFlowTargetKind = .merchant
    @State private var topics: [CoopFlowOwnedTopic] = []
    @State private var candidates: [CoopFlowTargetCandidate] = []
    @State private var topicID: Int?
    @State private var search = ""
    @State private var page = 1
    @State private var hasMore = true
    @State private var busy = false
    @State private var topicsFailed = false
    @State private var targetsFailed = false
    @State private var generation = 0
    @State private var loadedSession: CoopFlowSession?
    @State private var selected: Set<String> = []
    @State private var editing: [CoopFlowInvitationContext] = []
    @State private var showEditor = false
    private var topic: CoopFlowOwnedTopic? { topics.first { $0.id == topicID } }
    private var filtered: [CoopFlowTargetCandidate] { search.isEmpty ? candidates : candidates.filter { $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        Form {
            Picker("context.coop.kind", selection: $kind) {
                Text("context.coop.merchant").tag(CoopFlowTargetKind.merchant)
                Text("coopflow.invite.club").tag(CoopFlowTargetKind.club)
            }.disabled(busy)
            Section("context.coop.topic") {
                if topicsFailed { Button("action.retry") { Task { await load(reset: true) } } }
                Picker("context.coop.topic", selection: $topicID) {
                    Text("context.coop.chooseTopic").tag(Optional<Int>.none)
                    ForEach(topics) { row in
                        Text(verbatim: [row.name, row.startDate, row.address, "#\(row.id)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).tag(Optional(row.id))
                    }
                }
                if topic != nil, topic?.inviteWindowOpen != true { Text("context.coop.closed") }
                if hasMore, !topics.isEmpty { Button("context.picker.more") { Task { await load(reset: false) } }.disabled(busy) }
            }
            Section("context.coop.targets") {
                TextField("context.coop.search", text: $search).accessibilityIdentifier("context.coop.search")
                if busy { ProgressView("cooperation.loading") }
                if targetsFailed { Button("action.retry") { Task { await load(reset: true) } } }
                if !busy, !targetsFailed, filtered.isEmpty { Text("context.picker.empty") }
                ForEach(filtered) { candidate in
                    Button {
                        if selected.contains(candidate.id) { selected.remove(candidate.id) } else { selected.insert(candidate.id) }
                    } label: {
                        HStack { Text(verbatim: candidate.name); Spacer(); if selected.contains(candidate.id) { Image(systemName: "checkmark") } }
                    }.disabled(busy || loadedSession != reader.session)
                        .accessibilityAddTraits(selected.contains(candidate.id) ? .isSelected : [])
                        .accessibilityIdentifier("context.coop.target.\(candidate.id)")
                }
            }
            if !selected.isEmpty {
                LabeledContent("context.coop.selected", value: String(selected.count))
                Button("context.coop.continue") {
                    guard loadedSession == reader.session, let topic else { return }
                    let values = candidates.filter { selected.contains($0.id) }.compactMap {
                        CoopFlowInvitationContext(candidate: $0, topic: topic, scope: operationScope, session: loadedSession)
                    }
                    guard values.count == selected.count else { return }
                    editing = values; showEditor = true
                }.disabled(topic?.inviteWindowOpen != true || busy || loadedSession != reader.session)
            }
            CoopFlowSafetyNotice()
        }.navigationTitle("context.coop.new").scrollDismissesKeyboard(.interactively)
            .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0)") { await load(reset: true) }
            .onChange(of: kind) { _, _ in editing = []; showEditor = false; Task { await load(reset: true) } }
            .onChange(of: reader.session) { _, _ in generation += 1; topics = []; candidates = []; selected = []; topicID = nil; editing = []; showEditor = false; search = "" }
            .onDisappear { generation += 1; busy = false }
            .sheet(isPresented: $showEditor) { NavigationStack { CoopFlowBatchInviteEditor(reader: reader, contexts: editing) } }
    }
    private func load(reset: Bool) async {
        generation += 1; let request = generation, expected = reader.session, requestedKind = kind
        if reset { topics = []; candidates = []; selected = []; topicID = nil; page = 1; hasMore = true; loadedSession = nil }
        guard expected != nil else { return }
        busy = true; topicsFailed = false; targetsFailed = false
        defer { if request == generation { busy = false } }
        do {
            let value = try await reader.read(.ownedTopics(kind: requestedKind, scope: operationScope, page: page))
            guard request == generation, expected == reader.session, requestedKind == kind, !Task.isCancelled else { return }
            guard let rows = value["rows"].rows else { throw CoopFlowFailure.malformed }
            let parsed = rows.compactMap(CoopFlowOwnedTopic.init)
            guard parsed.count == rows.count else { throw CoopFlowFailure.malformed }
            var seen = Set(topics.map(\.id)); topics += parsed.filter { seen.insert($0.id).inserted }
            hasMore = rows.count == 20; page += 1
        } catch { if request == generation, expected == reader.session { topicsFailed = true } }
        guard reset else { return }
        do {
            let value = try await reader.read(requestedKind == .merchant ? .merchants(name: nil) : .clubs(name: nil))
            guard request == generation, expected == reader.session, requestedKind == kind, !Task.isCancelled else { return }
            guard let rows = value.rows else { throw CoopFlowFailure.malformed }
            let parsed = rows.compactMap { CoopFlowTargetCandidate(kind: requestedKind, row: $0) }
            guard parsed.count == rows.count, Set(parsed.map(\.id)).count == parsed.count else { throw CoopFlowFailure.malformed }
            candidates = parsed; loadedSession = expected
        } catch { if request == generation, expected == reader.session { targetsFailed = true } }
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
