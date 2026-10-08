import SwiftUI

struct IMConversationReadAllButtonToken: Equatable {
    let id: UUID
    let appearance: UUID
}

@MainActor final class IMConversationReadAllReviewModel: ObservableObject {
    let batch: IMConversationReadAll
    @Published private(set) var appearance: UUID?
    @Published private(set) var phase: IMConversationReadAllPhase
    @Published private(set) var items: [IMConversationReadAllItem]
    @Published private(set) var isActionPending = false
    @Published private(set) var stopRequested = false
    private var queued: IMConversationReadAllButtonToken?
    private var executing: IMConversationReadAllButtonToken?
    private let invalidateList: () -> Void

    init(batch: IMConversationReadAll, invalidateList: @escaping () -> Void) {
        self.batch = batch; self.invalidateList = invalidateList
        phase = batch.phase; items = batch.items
    }
    func observe() {
        let lifetime = UUID()
        appearance = lifetime; queued = nil; executing = nil; isActionPending = false
        batch.onChange = { [weak self] in
            guard let self, self.appearance == lifetime else { return }
            self.copySnapshot()
        }
        copySnapshot()
    }
    func prepare(appearance expected: UUID?) -> IMConversationReadAllButtonToken? {
        guard let expected, appearance == expected, queued == nil, executing == nil,
              batch.canConfirm else { return nil }
        let token = IMConversationReadAllButtonToken(id: UUID(), appearance: expected)
        queued = token; isActionPending = true
        return token
    }
    func perform(_ token: IMConversationReadAllButtonToken) async {
        guard queued == token, appearance == token.appearance else { return }
        queued = nil
        guard batch.canConfirm, !Task.isCancelled else {
            batch.stop(); isActionPending = false; copySnapshot(); return
        }
        executing = token
        await batch.confirm()
        // List/cache ownership outlives a closed review. This also runs for unknown
        // or partial results: those writes may have reached the server. Invalidation
        // creates no network task; the current list appearance owns the actual read.
        if batch.attemptedCount > 0, batch.isCurrent { invalidateList() }
        guard appearance == token.appearance, executing == token else { return }
        executing = nil; isActionPending = false; copySnapshot()
    }
    func stop() { batch.stop(); copySnapshot() }
    func dismiss() {
        appearance = nil; queued = nil; executing = nil; isActionPending = false
        batch.stop()
        phase = .cancelled
        // Never cancel/reset the session coordinator or resend an uncertain item.
    }
    private func copySnapshot() {
        phase = batch.phase; items = batch.items; stopRequested = batch.stopRequested
    }
}

@MainActor struct IMConversationReadAllView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: IMConversationReadAllReviewModel
    init(batch: IMConversationReadAll, invalidateList: @escaping () -> Void) {
        _model = StateObject(wrappedValue: IMConversationReadAllReviewModel(batch: batch,
            invalidateList: invalidateList))
    }
    var body: some View {
        let appearance = model.appearance
        NavigationStack {
            List {
                if model.batch.isCurrent {
                    Section {
                        Text("im.readAll.scopeHint")
                        LabeledContent("im.readAll.frozenCount") { Text(verbatim: String(model.items.count)) }
                        Text("im.readAll.cancelHint").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        switch model.phase {
                        case .reviewing:
                            Button("im.readAll.confirm") {
                                guard let token = model.prepare(appearance: appearance) else { return }
                                Task { await model.perform(token) }
                            }
                            .disabled(model.isActionPending || !model.batch.canConfirm)
                            .accessibilityIdentifier("im.readAll.confirmButton")
                            if !model.batch.canConfirm { Text("im.readAll.unavailable") }
                        case .running:
                            ProgressView("im.readAll.running")
                            Button("im.readAll.stop") { model.stop() }
                                .disabled(model.stopRequested)
                                .accessibilityIdentifier("im.readAll.stopButton")
                            if model.stopRequested { Text("im.readAll.stopping") }
                        case .finished:
                            Text("im.readAll.finished")
                            summary
                            Text("im.readAll.readbackHint").font(.footnote)
                            if model.batch.unknownCount > 0 { Text("im.readAll.unknownHint").font(.footnote) }
                        case .cancelled:
                            Text("im.readAll.cancelled")
                        }
                    }
                    Section("im.readAll.conversations") {
                        ForEach(model.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                MessagingConversationName(conversation: item.conversation)
                                Text(LocalizedStringKey(outcomeKey(item.outcome)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityIdentifier("im.readAll.item.\(item.id)")
                        }
                    }
                } else { Text("messaging.signInHint") }
            }
            .navigationTitle(Text("im.readAll.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { model.dismiss(); dismiss() }
                        .accessibilityIdentifier("im.readAll.closeButton")
                }
            }
        }
        .privacySensitive()
        .accessibilityIdentifier("im.readAll.reviewSheet")
        .onAppear { model.observe() }
        .onDisappear { model.dismiss() }
    }
    private var summary: some View {
        Group {
            LabeledContent("im.readAll.acknowledged") { Text(verbatim: String(model.batch.acknowledgedCount)) }
            LabeledContent("im.readAll.unknown") { Text(verbatim: String(model.batch.unknownCount)) }
            LabeledContent("im.readAll.rejected") { Text(verbatim: String(model.batch.rejectedCount)) }
            LabeledContent("im.readAll.remaining") { Text(verbatim: String(model.batch.remainingCount)) }
        }
    }
    private func outcomeKey(_ outcome: IMConversationReadAllOutcome) -> String {
        switch outcome {
        case .notAttempted: return "im.readAll.remaining"
        case .submitting: return "im.readAll.running"
        case .acknowledged: return "im.readAll.acknowledged"
        case .rejected: return "im.readAll.rejected"
        case .outcomeUnknown: return "im.readAll.unknown"
        case .protectedIntent: return "im.readAll.protected"
        case .unavailable: return "im.readAll.unavailable"
        }
    }
}

@MainActor struct IMConversationReadAllPresentation: Identifiable {
    let id = UUID()
    let batch: IMConversationReadAll
}
