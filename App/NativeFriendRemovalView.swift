import SwiftUI

@MainActor final class NativeFriendRemovalViewModel: ObservableObject {
    let flow: NativeFriendRemovalFlow
    init(_ flow: NativeFriendRemovalFlow, onResolved: @escaping () -> Void) {
        self.flow = flow; flow.onChange = { [weak self] in self?.objectWillChange.send() }; flow.onResolved = onResolved
    }
}

/// The original real-row identity remains visible. No numeric peer input, block action or conversation creation.
@MainActor struct NativeFriendRemovalView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: NativeFriendRemovalViewModel
    @State private var confirmingRetry = false
    @State private var confirmingRemoval = false
    @State private var retryCommand: NativeFriendRemovalCommand?
    @State private var operationTask: Task<Void, Never>?
    init(flow: NativeFriendRemovalFlow, onResolved: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: NativeFriendRemovalViewModel(flow, onResolved: onResolved))
    }
    private var flow: NativeFriendRemovalFlow { model.flow }
    var body: some View {
        Form {
            if let item = flow.presentationItem {
                Section {
                    HStack(spacing: Theme.Space.s3) {
                        Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(verbatim: item.displayName.isEmpty ? "—" : item.displayName).font(Theme.Font.sectionTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("friendRemoval.target")
                    }
                }
            }
            if flow.busy { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("friendRemoval.loading") }
            if flow.phase == .closed { text("friendRemoval.closed") }
            if let issue = flow.issue {
                Label { text(issue) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                    .accessibilityIdentifier("friendRemoval.issue")
            }
            if flow.pending != nil {
                Section {
                    text("friendRemoval.unknown")
                    Button { perform { await flow.recover() } } label: { text("friendRemoval.recover") }
                        .disabled(!flow.canRecover).accessibilityIdentifier("friendRemoval.recover")
                    Button { retryCommand = flow.pendingCommand; confirmingRetry = true } label: { text("friendRemoval.retryOriginal") }
                        .disabled(!flow.canRetryOriginal).accessibilityIdentifier("friendRemoval.retryOriginal")
                }
            } else if flow.item == nil && flow.result == nil && flow.phase == .ready {
                ContentUnavailableView { Label { text("friendRemoval.noPending") } icon: { Image(systemName: "checkmark.circle") } }
            }
            if let result = flow.result {
                Section {
                    text(result.outcome == "APPLIED" ? "friendRemoval.applied" : "friendRemoval.rejected")
                        .accessibilityIdentifier("friendRemoval.outcome")
                }
            }
            if let current = flow.currentRelationship {
                Section {
                    LabeledContent {
                        text(current.state == .friend ? "friendRemoval.currentFriend" : "friendRemoval.currentNotFriend")
                            .accessibilityIdentifier("friendRemoval.current")
                    } label: { text("friendRemoval.currentTitle") }
                }
            }
            if flow.review != nil || (flow.item != nil && flow.result == nil && flow.pending == nil) {
                Section {
                    Button(role: .destructive) {
                        if flow.review == nil { flow.reviewRemoval() }
                        confirmingRemoval = flow.review != nil
                    } label: { text("friendRemoval.review").frame(maxWidth: .infinity) }
                        .disabled(!(flow.canReview || flow.canConfirm)).accessibilityIdentifier("friendRemoval.review")
                }
            }
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .navigationTitle(localized("friendRemoval.title"))
        .accessibilityIdentifier("friendRemoval.home")
        .task { await flow.load() }
        .onDisappear { suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { perform { await flow.load() } }
            else { suspend() }
        }
        .onChange(of: flow.isCurrent) { _, current in
            if !current { cancelOperation() }
        }
        // The dialog only presents the flow's own review; dismissing it without a choice keeps that review open.
        .confirmationDialog(localized("d7.friendRemoval.confirmTitle"), isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button(role: .destructive) {
                guard let confirmed = flow.review else { return }
                perform { await flow.confirm(confirmed: confirmed) }
            } label: { text("friendRemoval.confirm") }
                .disabled(!flow.canConfirm).accessibilityIdentifier("friendRemoval.confirm")
            Button(role: .cancel) { flow.cancelReview() } label: { text("friendRemoval.cancel") }
                .accessibilityIdentifier("friendRemoval.cancel")
        } message: {
            text("friendRemoval.impact")
        }
        .confirmationDialog(localized("friendRemoval.retryTitle"), isPresented: $confirmingRetry, titleVisibility: .visible) {
            Button(localized("friendRemoval.retryConfirm"), role: .destructive) {
                guard let confirmed = retryCommand else { return }
                retryCommand = nil
                perform { await flow.retryOriginal(confirmed: confirmed) }
            }
            Button(localized("friendRemoval.keepPending"), role: .cancel) { retryCommand = nil }
        } message: {
            text("friendRemoval.retryImpact")
        }
        .tint(Theme.Color.accent(in: domain))
    }
    private func perform(_ operation: @escaping @MainActor () async -> Void) {
        // A repeated tap must not cancel an already-dispatched original command.
        guard !flow.busy else { return }
        operationTask?.cancel()
        operationTask = Task {
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
    private func cancelOperation() {
        operationTask?.cancel(); operationTask = nil
        confirmingRetry = false; retryCommand = nil; confirmingRemoval = false
    }
    private func suspend() {
        cancelOperation(); flow.invalidate()
    }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeFriendRemoval") }
    private func localized(_ key: String) -> String { String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "NativeFriendRemoval", locale: locale)) }
}

#if DEBUG
/// UI-only synthetic transport. It hosts the same ordinary friend list, confirmation and recovery screens.
@MainActor final class NativeFriendRemovalFixtureState: ObservableObject, NativeFriendServing, NativeFriendRemovalServing {
    final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { rows.removeAll { $0 == record } }
    }
    let journal = Journal()
    var viewerID: Int64 = 2
    var isCurrent = true
    var canWrite = true
    var canSettle = true
    @Published var removeCount = 0
    @Published var receiptCount = 0
    @Published var settleCount = 0
    var currentFriend = true
    var terminal: [UUID: NativeFriendRemovalReceipt] = [:]
    let loseResponse: Bool
    let item = NativeFriendItem(peerID: 9, nickname: "Synthetic friend", state: .friend, version: 3, message: "", expiresAtMS: 0)
    lazy var home = NativeFriendFlow(service: self, journal: journal, ownerKey: "removal-fixture-friend")
    init(loseResponse: Bool = ProcessInfo.processInfo.arguments.contains("--friend-removal-unknown")) { self.loseResponse = loseResponse }
    func makeRemoval(item: NativeFriendItem?) -> NativeFriendRemovalFlow { .init(item: item, service: self, journal: journal, ownerKey: "removal-fixture-owner-2") }
    func relationship(peerID: Int64) async throws -> NativeFriendRelationship {
        .init(viewerID: viewerID, peerID: peerID, state: currentFriend ? .friend : .none, version: currentFriend ? 3 : 4, conversationID: 80)
    }
    func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage {
        .init(viewerID: viewerID, incoming: [], outgoing: [], friends: !requests && currentFriend ? [item] : [], hasMore: false, nextCursor: nil)
    }
    func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt { throw NativeFriendFailure.notSent }
    func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt { throw NativeFriendFailure.notSent }
    func remove(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
        removeCount += 1
        if let previous = terminal[command.requestID] { return previous }
        currentFriend = false
        let result = NativeFriendRemovalReceipt(viewerID: viewerID, command: command, outcome: "APPLIED", reason: "REMOVED", removedVersion: command.expectedVersion + 1, currentRelationship: try await relationship(peerID: command.peerID))
        terminal[command.requestID] = result
        if loseResponse { throw NativeFriendFailure.unknown }; return result
    }
    func receipt(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
        receiptCount += 1
        if let previous = terminal[command.requestID] { return previous }
        return .init(viewerID: viewerID, command: command, outcome: "UNKNOWN", currentRelationship: try await relationship(peerID: command.peerID))
    }
    func settle(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
        settleCount += 1
        if let previous = terminal[command.requestID] { return previous }
        let result = NativeFriendRemovalReceipt(viewerID: viewerID, command: command, outcome: "REJECTED", reason: "FINALIZED_WITHOUT_REMOVAL", currentRelationship: try await relationship(peerID: command.peerID))
        terminal[command.requestID] = result; return result
    }
}
@MainActor struct NativeFriendRemovalFixtureHost: View {
    @StateObject private var state = NativeFriendRemovalFixtureState()
    var body: some View {
        VStack {
            NavigationStack {
                NativeFriendHomeView(flow: state.home, removalFactory: { state.makeRemoval(item: $0) }, conversation: { _ in AnyView(Text(verbatim: "Existing synthetic chat")) })
            }
            Text(verbatim: "\(state.removeCount)/\(state.receiptCount)/\(state.settleCount)").accessibilityIdentifier("friendRemoval.fixture.counts")
        }
    }
}
#endif
