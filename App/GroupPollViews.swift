import SwiftUI

@MainActor private final class GroupPollViewModel: ObservableObject {
    @Published var revision = 0
    let owner: GroupPollCoordinator
    init(_ owner: GroupPollCoordinator) { self.owner = owner }
    func observe() { owner.onChange = { [weak self] in self?.revision &+= 1 }; revision &+= 1 }
}
@MainActor struct GroupPollView: View {
    @StateObject private var model: GroupPollViewModel
    let creating: Bool
    // Normal creation and message-detail callers supply their original source fence.
    // A result grant is not a writer grant; the existing coordinator owns every mutation.
    private let sourceIsCurrent: (() -> Bool)?
    @State private var sourceActive = false
    @State private var presentationGeneration: UInt64 = 0
    @State private var operationTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]
    @State private var usesDeadline = false
    @State private var deadline = Date().addingTimeInterval(86400)
    @State private var selectedOption: Int?
    @State private var discard = false
    @State private var confirmOriginalRetry = false
    @FocusState private var focused: Bool
    init(owner: GroupPollCoordinator, creating: Bool = false, current: (() -> Bool)? = nil) {
        _model = StateObject(wrappedValue: GroupPollViewModel(owner)); self.creating = creating
        sourceIsCurrent = current
    }
    private var owner: GroupPollCoordinator { model.owner }
    private var entryCurrent: Bool {
        sourceActive && scenePhase == .active && (sourceIsCurrent?() ?? true)
    }
    private var validDraft: Bool { (try? GroupPollDraft(conversationID: owner.scope.conversationID, question: question, options: options, deadline: usesDeadline ? deadline : nil)) != nil }
    private var draftChanged: Bool { !question.isEmpty || options.contains { !$0.isEmpty } || usesDeadline }
    var body: some View {
        Form {
            Section { Text("poll.rules").font(.footnote).foregroundStyle(.secondary) }
            if entryCurrent && owner.recoveredCreationWithoutDraft {
                Text("已按旧记录的原创建编号找到本人投票；旧记录没有保存原草稿，未补造草稿或重新发送。")
            }
            if !entryCurrent || !owner.isCurrent {
                Text("poll.stale").accessibilityIdentifier("poll.stale")
            } else if let poll = owner.visiblePoll {
                result(poll)
            } else if creating {
                draft
            }
            if !creating && !owner.canRead { Section { Text("poll.disabled").accessibilityIdentifier("poll.disabled") } }
            if entryCurrent && creating && owner.canStartAnother { Section { Button("poll.createAnother") { question = ""; options = ["", ""]; usesDeadline = false; owner.startAnother() }.accessibilityIdentifier("poll.createAnother") } }
            if entryCurrent { status }
        }
        .nativeChannelScreen()
        .navigationTitle(Text(creating ? "poll.create" : "poll.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("poll.screen")
        .privacySensitive()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("poll.keyboardDone") { focused = false } }
            if creating {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { focused = false; if draftChanged && owner.visiblePoll == nil { discard = true } else { dismiss() } }
                        .accessibilityIdentifier("poll.cancel")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if owner.reference != nil {
                    Button("messaging.refresh", systemImage: "arrow.clockwise") { selectedOption = nil; run(.refresh) }
                        .disabled(!entryCurrent || !owner.canRead || busy).accessibilityIdentifier("poll.refresh")
                }
            }
        }
        .confirmationDialog("poll.discard", isPresented: $discard, titleVisibility: .visible) {
            Button("poll.discardConfirm", role: .destructive) { owner.cancelReview(); question = ""; options = ["", ""]; dismiss() }
            Button("action.cancel", role: .cancel) {}
        }
        .interactiveDismissDisabled(creating && draftChanged && owner.visiblePoll == nil)
        .onAppear { model.observe(); sourceActive = true; owner.resume() }
        .confirmationDialog("仅重试已保存的原投票草稿与相同 clientPollKey，不根据 NOT_FOUND 新建投票或变更截止时间。",isPresented:$confirmOriginalRetry) {
            Button("确认重试原投票创建") { run(.retry) }
            Button("取消",role:.cancel) {}
        }
        .task(id: entryCurrent) {
            guard entryCurrent else { return }
            owner.resume()
            // Only the original creation owner can recover its same-key intent.
            // Existing message details continue to use their original result reader.
            if creating {
                if owner.canRecoverCreationReceipt { run(.recover) }
            } else { run(.refresh) }
        }
        .onDisappear { sourceActive = false; invalidatePresentation(); question = ""; options = ["", ""] }
        .onChange(of: entryCurrent) { _, current in
            if !current { invalidatePresentation() }
        }
        .onChange(of: owner.isCurrent) { _, current in
            if !current { invalidatePresentation(); question = ""; options = ["", ""]; discard = false }
        }
    }
    private enum Work {
        case reviewCreate(question: String, options: [String], deadline: Date?)
        case confirm, refresh, recover, retry
    }
    /// The view owns only its presentation lifetime, never a second poll/journal.
    /// Capture inputs at the tap and fence every await against this exact appearance.
    private func run(_ work: Work) {
        guard entryCurrent, !busy else { return }
        let ticket = presentationGeneration
        operationTask?.cancel()
        operationTask = Task {
            let current = { entryCurrent && presentationGeneration == ticket && !Task.isCancelled }
            guard current() else { return }
            switch work {
            case .reviewCreate(let question, let options, let deadline):
                await owner.reviewCreate(question: question, options: options, deadline: deadline, sourceIsCurrent: current)
            case .confirm: await owner.confirm(sourceIsCurrent: current)
            case .refresh: await owner.refresh(sourceIsCurrent: current)
            case .recover: await owner.recoverCreationReceipt(sourceIsCurrent: current)
            case .retry: await owner.retryCreationUnchanged(sourceIsCurrent: current)
            }
            if current() { selectedOption = nil }
        }
    }
    private func invalidatePresentation() {
        presentationGeneration &+= 1
        operationTask?.cancel(); operationTask = nil
        focused = false; selectedOption = nil; confirmOriginalRetry = false
        owner.suspend() // Keep any dispatched UNKNOWN UUID and original payload intact.
    }
    private var busy: Bool { owner.visiblePhase == .submitting || owner.visiblePhase == .loading }
    private var reviewing: Bool { if case .reviewing = owner.visiblePhase { return true }; return false }
    private var draft: some View {
        Group {
            Section("poll.question") {
                TextField("poll.questionPrompt", text: $question, axis: .vertical).lineLimit(2...5)
                    .focused($focused).accessibilityIdentifier("poll.question")
                Text(verbatim: "\(question.utf16.count) / 200").font(.caption).foregroundStyle(.secondary)
            }
            Section("poll.options") {
                ForEach(options.indices, id: \.self) { index in
                    HStack(alignment: .top) {
                        TextField("poll.optionPrompt", text: $options[index], axis: .vertical).focused($focused)
                            .accessibilityIdentifier("poll.option.\(index)")
                        if options.count > 2 {
                            Button { options.remove(at: index) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).accessibilityLabel(Text("poll.removeOption"))
                                .accessibilityIdentifier("poll.remove.\(index)")
                        }
                    }
                }
                if options.count < 10 {
                    Button("poll.addOption", systemImage: "plus.circle") { options.append("") }.accessibilityIdentifier("poll.addOption")
                }
                Text("poll.optionLimit").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("poll.useDeadline", isOn: $usesDeadline).accessibilityIdentifier("poll.useDeadline")
                if usesDeadline {
                    DatePicker("poll.deadline", selection: $deadline, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("poll.deadline")
                }
                Button("poll.reviewCreate") {
                    focused = false
                    run(.reviewCreate(question: question, options: options, deadline: usesDeadline ? deadline : nil))
                }.nativeChannelPrimaryAction().disabled(!validDraft || !owner.canCreate).accessibilityIdentifier("poll.reviewCreate")
            }
            if !owner.client.permits("api/im/poll/create") || !owner.canRead { Text("poll.disabled").accessibilityIdentifier("poll.disabled") }
        }.disabled(busy || reviewing || owner.visiblePhase == .unknown || !owner.isCurrent)
    }
    @ViewBuilder private func result(_ poll: GroupPoll) -> some View {
        Section {
            Text(verbatim: poll.question).font(.title3.weight(.semibold)).accessibilityIdentifier("poll.result.question")
            Label(LocalizedStringKey(poll.status == "CLOSED" ? "poll.closed" : (poll.isOpen() ? "poll.open" : "poll.deadlinePassed")), systemImage: poll.isOpen() ? "chart.bar.xaxis" : "checkmark.seal")
            if let deadline = poll.deadlineAt?.value { LabeledContent("poll.deadline") { Text(deadline, format: .dateTime) } }
        }
        Section("poll.options") {
            ForEach(poll.options) { option in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: option.content).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("poll.result.option.\(option.id)")
                        if poll.myOptionId == option.id { Label("poll.yourVote", systemImage: "checkmark.circle.fill").font(.caption) }
                        if poll.hasResults, let count = option.voteCount { Text(verbatim: String(count)).monospacedDigit() }
                    }
                    if poll.hasResults, let count = option.voteCount, let total = poll.totalVoters {
                        ProgressView(value: Double(count), total: Double(max(total, 1))).accessibilityLabel(Text(verbatim: option.content))
                            .accessibilityValue(Text(verbatim: "\(count) / \(total)"))
                    }
                    if owner.canVote {
                        Button { selectedOption = option.id } label: {
                            Label(LocalizedStringKey(selectedOption == option.id ? "poll.selected" : "poll.choose"), systemImage: selectedOption == option.id ? "largecircle.fill.circle" : "circle")
                        }.accessibilityIdentifier("poll.choose.\(option.id)")
                        .frame(minHeight: 44)
                        .accessibilityAddTraits(selectedOption == option.id ? .isSelected : [])
                    }
                }
            }
            if let total = poll.totalVoters { LabeledContent("poll.total", value: String(total)).accessibilityIdentifier("poll.total") }
            else { Text("poll.awaitResults").accessibilityIdentifier("poll.awaitResults") }
        }
        if owner.canVote {
            Section {
                Button("poll.reviewVote") { if let selectedOption { owner.reviewVote(optionID: selectedOption, sourceIsCurrent: { entryCurrent }) } }
                    .disabled(selectedOption == nil).accessibilityIdentifier("poll.reviewVote")
            }
        }
        if owner.canClose {
            Section { Button("poll.reviewClose", role: .destructive) { owner.reviewClose(sourceIsCurrent: { entryCurrent }) }.accessibilityIdentifier("poll.reviewClose") }
        }
        if !owner.isMember, poll.hasResults { Section { Text("poll.historical").font(.footnote) } }
        if !owner.canRead { Section { Text("poll.disabled") } }
    }
    @ViewBuilder private var status: some View {
        Section {
            switch owner.visiblePhase {
            case .reviewing(let mutation):
                switch mutation {
                case .create(let draft):
                    Text("poll.confirmCreateTitle").font(.headline)
                    Text(verbatim: draft.question)
                    ForEach(Array(draft.options.enumerated()), id: \.offset) { _, option in Text(verbatim: option) }
                    if let date = draft.deadline { Text(date, format: .dateTime) }
                case .vote(_, let option):
                    Text("poll.confirmVoteTitle").font(.headline)
                    if let text = owner.visiblePoll?.options.first(where: { $0.id == option })?.content { Text(verbatim: text) }
                    Text("poll.noRevote")
                case .close: Text("poll.confirmCloseTitle").font(.headline); Text("poll.closeWarning")
                }
                Button("poll.confirm") { focused = false; run(.confirm) }.nativeChannelPrimaryAction().accessibilityIdentifier("poll.confirm")
                Button("action.cancel", role: .cancel) { owner.cancelReview() }.accessibilityIdentifier("poll.cancelReview")
            case .loading, .submitting: ProgressView("poll.loading").accessibilityIdentifier("poll.loading")
            case .unknown:
                Text("poll.unknown").nativeChannelNotice(systemImage: "clock").accessibilityIdentifier("poll.unknown")
                if creating, let draft = owner.originalCreationDraft {
                    Text("原已确认投票 · 内容与截止时间不会重新生成").font(.headline)
                    Text(verbatim: draft.question)
                    ForEach(Array(draft.options.enumerated()), id: \.offset) { _, option in Text(verbatim: option) }
                    if let deadline = draft.deadline { Text(deadline, format: .dateTime) }
                }
                if creating && owner.canRecoverCreationReceipt { Button("只回读原投票创建请求") { run(.recover) } }
                if creating && owner.canRetryCreation { Button("poll.retryCreate") { confirmOriginalRetry=true }.accessibilityIdentifier("poll.retryCreate") }
            case .failed: Text("poll.failed").accessibilityIdentifier("poll.failed")
            case .rejected: Text("poll.rejected").accessibilityIdentifier("poll.rejected")
            case .blocked: Text("poll.blocked").accessibilityIdentifier("poll.blocked")
            case .acknowledged: Text("poll.acknowledged").accessibilityIdentifier("poll.acknowledged")
            case .idle: EmptyView()
            }
        }
    }
}
struct GroupPollUnavailableView: View {
    var body: some View { ContentUnavailableView("poll.title", systemImage: "chart.bar.xaxis", description: Text("poll.disabled")).navigationTitle(Text("poll.title")) }
}
