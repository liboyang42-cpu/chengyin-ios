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
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]
    @State private var usesDeadline = false
    @State private var deadline = Date().addingTimeInterval(86400)
    @State private var selectedOption: Int?
    @State private var discard = false
    @FocusState private var focused: Bool
    init(owner: GroupPollCoordinator, creating: Bool = false) {
        _model = StateObject(wrappedValue: GroupPollViewModel(owner)); self.creating = creating
    }
    private var owner: GroupPollCoordinator { model.owner }
    private var validDraft: Bool { (try? GroupPollDraft(conversationID: owner.scope.conversationID, question: question, options: options, deadline: usesDeadline ? deadline : nil)) != nil }
    private var draftChanged: Bool { !question.isEmpty || options.contains { !$0.isEmpty } || usesDeadline }
    var body: some View {
        Form {
            Section { Text("poll.rules").font(.footnote).foregroundStyle(.secondary) }
            if !owner.isCurrent {
                Text("poll.stale").accessibilityIdentifier("poll.stale")
            } else if let poll = owner.visiblePoll {
                result(poll)
            } else if creating {
                draft
            }
            if !creating && !owner.canRead { Section { Text("poll.disabled").accessibilityIdentifier("poll.disabled") } }
            if creating && owner.canStartAnother { Section { Button("poll.createAnother") { question = ""; options = ["", ""]; usesDeadline = false; owner.startAnother() }.accessibilityIdentifier("poll.createAnother") } }
            status
        }
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
                    Button("messaging.refresh", systemImage: "arrow.clockwise") { selectedOption = nil; Task { await owner.refresh() } }
                        .disabled(!owner.canRead || busy).accessibilityIdentifier("poll.refresh")
                }
            }
        }
        .confirmationDialog("poll.discard", isPresented: $discard, titleVisibility: .visible) {
            Button("poll.discardConfirm", role: .destructive) { owner.cancelReview(); question = ""; options = ["", ""]; dismiss() }
            Button("action.cancel", role: .cancel) {}
        }
        .interactiveDismissDisabled(creating && draftChanged && owner.visiblePoll == nil)
        .onAppear { model.observe(); owner.resume() }
        .task { if !creating { await owner.refresh() } }
        .onDisappear { focused = false; question = ""; options = ["", ""]; selectedOption = nil; owner.suspend() }
        .onChange(of: owner.isCurrent) { _, current in
            if !current { focused = false; question = ""; options = ["", ""]; selectedOption = nil; discard = false }
        }
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
                    Task { await owner.reviewCreate(question: question, options: options, deadline: usesDeadline ? deadline : nil) }
                }.disabled(!validDraft || !owner.canCreate).accessibilityIdentifier("poll.reviewCreate")
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
                    }
                }.accessibilityIdentifier("poll.result.option.\(option.id)")
            }
            if let total = poll.totalVoters { LabeledContent("poll.total", value: String(total)).accessibilityIdentifier("poll.total") }
            else { Text("poll.awaitResults").accessibilityIdentifier("poll.awaitResults") }
        }
        if owner.canVote {
            Section {
                Button("poll.reviewVote") { if let selectedOption { owner.reviewVote(optionID: selectedOption) } }
                    .disabled(selectedOption == nil).accessibilityIdentifier("poll.reviewVote")
            }
        }
        if owner.canClose {
            Section { Button("poll.reviewClose", role: .destructive) { owner.reviewClose() }.accessibilityIdentifier("poll.reviewClose") }
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
                Button("poll.confirm") { focused = false; Task { await owner.confirm(); selectedOption = nil } }.accessibilityIdentifier("poll.confirm")
                Button("action.cancel", role: .cancel) { owner.cancelReview() }.accessibilityIdentifier("poll.cancelReview")
            case .loading, .submitting: ProgressView("poll.loading").accessibilityIdentifier("poll.loading")
            case .unknown:
                Text("poll.unknown").accessibilityIdentifier("poll.unknown")
                if owner.canRetryCreation { Button("poll.retryCreate") { Task { await owner.retryCreationUnchanged() } }.accessibilityIdentifier("poll.retryCreate") }
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
