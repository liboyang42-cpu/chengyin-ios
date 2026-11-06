import SwiftUI

/// A result-only presentation over the existing poll client. It does not call the
/// mutation coordinator's refresh/recovery methods or touch any pending journal.
@MainActor private final class GroupPollOriginalResultModel: ObservableObject {
    @Published private(set) var poll: GroupPoll?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private let owner: GroupPollCoordinator
    private let reference: GroupPollReference
    private let sourceCurrent: () -> Bool
    private var generation: UInt64 = 0
    private var active = false
    init(owner: GroupPollCoordinator, reference: GroupPollReference, current: @escaping () -> Bool) {
        self.owner = owner; self.reference = reference; sourceCurrent = current
    }
    var isCurrent: Bool {
        active && sourceCurrent() && owner.isCurrent && owner.reference == reference
            && owner.scope.conversationID == reference.conversationID && owner.canRead
    }
    func activate() async {
        guard !Task.isCancelled else { return }
        active = true
        await reload()
    }
    func reload() async {
        guard isCurrent, !Task.isCancelled else { retire(); return }
        generation &+= 1; let run = generation
        poll = nil; failed = false; loading = true
        defer { if generation == run { loading = false } }
        do {
            // This is the exact existing original result route and captured session.
            // Historical-audience authorization stays server-owned; no membership grant.
            let value = try await owner.client.result(reference, expectedIdentity: owner.scope.identity)
            guard generation == run, isCurrent, !Task.isCancelled else { return }
            try value.validate(reference: reference, conversationID: owner.scope.conversationID, results: true)
            poll = value
        } catch {
            guard generation == run else { return }
            poll = nil
            if !isCurrent || Task.isCancelled { retire() } else { failed = true }
        }
    }
    func retire() {
        active = false; generation &+= 1; poll = nil; loading = false; failed = false
    }
}

/// Original type4 cards and server-owned type9 results share this passive destination.
/// No create, vote, close, resend, receipt settlement or ACK action is exposed here.
@MainActor struct GroupPollOriginalResultView: View {
    @StateObject private var model: GroupPollOriginalResultModel
    @State private var readTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase
    init(owner: GroupPollCoordinator, reference: GroupPollReference, current: @escaping () -> Bool) {
        _model = StateObject(wrappedValue: GroupPollOriginalResultModel(owner: owner, reference: reference, current: current))
    }
    var body: some View {
        List {
            Section { Text("原投票结果 · 只读").font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true); Text("结果读取不代表仍可参与；本页不创建、投票、关闭或重试任何原操作。").fixedSize(horizontal: false, vertical: true) .font(Theme.Font.label) }
            if !model.isCurrent { Text("poll.disabled").fixedSize(horizontal: false, vertical: true) }
            else if let poll = model.poll {
                Section {
                    Text(verbatim: poll.question).fixedSize(horizontal: false, vertical: true).font(Theme.Font.sectionTitle)
                    Text(LocalizedStringKey(poll.status == "CLOSED" ? "poll.closed" : (poll.isOpen() ? "poll.open" : "poll.deadlinePassed"))).fixedSize(horizontal: false, vertical: true)
                    if let date = poll.deadlineAt?.value { LabeledContent("poll.deadline") { Text(date, format: .dateTime).fixedSize(horizontal: false, vertical: true) } }
                }
                Section("poll.options") {
                    ForEach(poll.options) { option in
                        VStack(alignment: .leading, spacing: Theme.Space.s1) {
                            Text(verbatim: option.content).fixedSize(horizontal: false, vertical: true)
                            if let count = option.voteCount, let total = poll.totalVoters {
                                Text(verbatim: "\(count) / \(total)").fixedSize(horizontal: false, vertical: true).monospacedDigit()
                                ProgressView(value: Double(count), total: Double(max(total, 1)))
                            }
                            if poll.myOptionId == option.id { Label("poll.yourVote", systemImage: "checkmark.circle.fill") }
                        }
                    }
                    if let total = poll.totalVoters { LabeledContent("poll.total", value: String(total)) }
                }
            } else if model.failed {
                Text("poll.failed").fixedSize(horizontal: false, vertical: true)
                Button("重新读取原投票结果") { reload() }.font(Theme.Font.button).frame(minHeight: 44)
            }
            if model.loading { ProgressView("poll.loading") }
        }
        .font(Theme.Font.body)
        .nativeChannelScreen()
        .navigationTitle(Text("poll.title"))
        .privacySensitive().accessibilityIdentifier("poll.originalResult.readOnly")
        .toolbar { Button("messaging.refresh", systemImage: "arrow.clockwise") { reload() }.disabled(!model.isCurrent || model.loading) }
        .task(id: phase) {
            guard phase == .active else { retire(); return }
            await model.activate()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                guard model.isCurrent else { retire(); return }
                if !model.loading { await model.reload() }
            }
        }
        .onDisappear { retire() }
        .onChange(of: model.isCurrent) { _, current in if !current { retire() } }
    }
    private func reload() {
        guard phase == .active, model.isCurrent else { retire(); return }
        readTask?.cancel(); readTask = Task { await model.reload() }
    }
    private func retire() { readTask?.cancel(); readTask = nil; model.retire() }
}
