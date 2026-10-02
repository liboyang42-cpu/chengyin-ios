import SwiftUI

@MainActor struct ContextualReviewComposer: View {
    @Environment(\.dismiss) private var dismiss
    let target: ContextualReviewTarget
    let owner: ContextualReviewCoordinator?
    let onAcknowledged: () -> Void
    @State private var draft = ContextualReviewDraft()
    @State private var review: ContextualReviewDraft?
    @State private var captured: ContextualReviewSession?
    @State private var busy = false
    @State private var revision = 0
    @State private var confirmDiscard = false
    @FocusState private var typing: Bool
    private var state: ContextualReviewState { let _ = revision; return owner?.state ?? .idle }
    var body: some View {
        Form {
            Section("context.review.rating") {
                Picker("context.review.rating", selection: $draft.rating) {
                    Text("context.review.chooseRating").tag(0)
                    ForEach(1...5, id: \.self) { Text(verbatim: String($0)).tag($0) }
                }.accessibilityIdentifier("context.review.rating")
                TextField("context.review.contents", text: $draft.contents, axis: .vertical)
                    .lineLimit(4...10).focused($typing).accessibilityIdentifier("context.review.contents")
                Text(verbatim: "\(draft.contents.utf16.count)/500").font(.caption)
            }.disabled(busy || state == .unknown || state == .acknowledged)
            if owner?.writer.isConfigured != true { Section { Text("context.review.disabled") } }
            Section {
                switch state {
                case .submitting: ProgressView("context.review.submitting")
                case .acknowledged: Text("context.review.acknowledged")
                case .unknown: Text("context.review.unknown")
                case .rejected: Text("context.review.rejected")
                case .notSent: Text("context.review.notSent")
                case .idle: EmptyView()
                }
                Button("context.review.preview") { typing = false; captured = owner?.writer.session; review = draft }
                    .disabled(!draft.isValid || busy || state == .unknown || state == .acknowledged)
                    .accessibilityIdentifier("context.review.preview")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("context.review.title").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("action.cancel") {
                if draft != ContextualReviewDraft(), state != .acknowledged { confirmDiscard = true } else { dismiss() }
            }.disabled(busy) }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("action.done") { typing = false } }
        }
        .interactiveDismissDisabled(busy || draft != ContextualReviewDraft())
        .confirmationDialog("context.review.discard", isPresented: $confirmDiscard) {
            Button("context.review.discard", role: .destructive) { draft = .init(); dismiss() }
            Button("action.cancel", role: .cancel) { }
        }
        .sheet(isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil; captured = nil } })) {
            NavigationStack {
                Form {
                    if let review {
                        LabeledContent("context.review.rating", value: String(review.rating))
                        Text(verbatim: review.contents)
                        if owner?.writer.isConfigured != true { Text("context.review.disabled") }
                        Button("context.review.submit") { Task { await submit(review) } }
                            .disabled(owner?.canSubmit != true || captured == nil || busy)
                            .accessibilityIdentifier("context.review.submit")
                    }
                }.navigationTitle("context.review.preview")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { review = nil; captured = nil }.disabled(busy) } }
            }.interactiveDismissDisabled(busy)
        }
        .onChange(of: owner?.writer.session) { _, _ in draft = .init(); review = nil; captured = nil; busy = false; revision += 1 }
    }
    private func submit(_ value: ContextualReviewDraft) async {
        guard let owner, let captured, owner.target == target, owner.writer.session == captured else { return }
        busy = true
        await owner.submit(value, expected: captured)
        busy = false; review = nil; revision += 1
        guard owner.writer.session == captured else { draft = .init(); return }
        if owner.state == .acknowledged { draft = .init(); onAcknowledged(); dismiss() }
    }
}
