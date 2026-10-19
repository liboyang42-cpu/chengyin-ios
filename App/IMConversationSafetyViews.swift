import SwiftUI

/// Sheet item for one retained safety owner. The owner, not the sheet, keeps a
/// pending/unknown action alive if the sheet is dismissed.
struct IMSafetyPresentation: Identifiable {
    let id = UUID()
    let owner: IMSafetyCoordinator
}

@MainActor final class IMSafetyModel: ObservableObject {
    let owner: IMSafetyCoordinator
    @Published private(set) var state: IMSafetyState
    init(owner: IMSafetyCoordinator) {
        self.owner = owner; state = owner.visibleState
        owner.onChange = { [weak self] in self?.state = self?.owner.visibleState ?? .idle }
    }
}

/// Mini-program cy-danger-confirm keys `im.conversation.delete` and `im.block`
/// (utils/danger-actions.js); report/unblock get the same explicit review on iOS.
struct IMSafetyCopy {
    let titleKey: String
    let contentKey: String?
    let consequenceKeys: [String]
    let confirmKey: String
    let doneKey: String
    let doneDetailKey: String?
    let failureKey: String
    init(_ action: IMSafetyAction) {
        switch action {
        case .hide:
            titleKey = "im.safety.hide.title"; contentKey = "im.safety.hide.content"
            consequenceKeys = ["im.safety.hide.consequence1", "im.safety.hide.consequence2"]
            confirmKey = "im.safety.hide.confirm"; doneKey = "im.safety.hide.done"; doneDetailKey = nil
            failureKey = "im.safety.hide.failed"
        case .block:
            titleKey = "im.safety.block.title"; contentKey = nil
            consequenceKeys = ["im.safety.block.consequence1", "im.safety.block.consequence2"]
            confirmKey = "im.safety.block.confirm"; doneKey = "im.safety.block.done"; doneDetailKey = "im.safety.block.doneDetail"
            failureKey = "im.safety.block.failed"
        case .unblock:
            titleKey = "im.safety.unblock.title"; contentKey = "im.safety.unblock.content"; consequenceKeys = []
            confirmKey = "im.safety.unblock.confirm"; doneKey = "im.safety.unblock.done"; doneDetailKey = nil
            failureKey = "im.safety.unblock.failed"
        case .report:
            titleKey = "im.safety.report.title"; contentKey = "im.safety.report.content"; consequenceKeys = []
            confirmKey = "im.safety.report.confirm"; doneKey = "im.safety.report.done"; doneDetailKey = nil
            failureKey = "im.safety.report.failed"
        }
    }
}

@MainActor struct IMSafetyReviewView: View {
    @StateObject private var model: IMSafetyModel
    let onSettled: (IMSafetyAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var task: Task<Void, Never>?
    init(owner: IMSafetyCoordinator, onSettled: @escaping (IMSafetyAction) -> Void) {
        _model = StateObject(wrappedValue: IMSafetyModel(owner: owner)); self.onSettled = onSettled
    }
    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(Text("im.safety.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { close() }.disabled(isInFlight).accessibilityIdentifier("im.safety.close")
                    }
                }
        }
        .accessibilityIdentifier("im.safety.sheet")
        .interactiveDismissDisabled(isInFlight)
        // A dispatched request is never cancelled by dismissal; its owner keeps the
        // unknown/acknowledged state. Only an acknowledged action refreshes the host.
        .onDisappear {
            if case .acknowledged(let action) = model.state { onSettled(action) }
            model.owner.cancelReview()
        }
    }
    private var isInFlight: Bool {
        switch model.state { case .submitting, .verifying, .resolving: return true; default: return false }
    }
    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle:
            Text("im.safety.idle").accessibilityIdentifier("im.safety.idle")
        case .resolving:
            ProgressView("im.safety.resolving").accessibilityIdentifier("im.safety.resolving")
        case .unavailable(let message):
            Section {
                Label("im.safety.unavailable", systemImage: "exclamationmark.circle").accessibilityIdentifier("im.safety.unavailable")
                if let message, !message.isEmpty { Text(verbatim: message) }
            }
        case .reviewing(let action):
            let copy = IMSafetyCopy(action)
            Section {
                Text(LocalizedStringKey(copy.titleKey)).font(.headline).accessibilityIdentifier("im.safety.reviewTitle")
                if let key = copy.contentKey { Text(LocalizedStringKey(key)) }
                ForEach(copy.consequenceKeys, id: \.self) { key in
                    Label(LocalizedStringKey(key), systemImage: "info.circle").font(.subheadline)
                }
            }
            Section {
                Button(role: .destructive) { run { await model.owner.confirm() } } label: { Text(LocalizedStringKey(copy.confirmKey)) }
                    .accessibilityIdentifier("im.safety.confirm")
                Button("action.cancel", role: .cancel) { close() }.accessibilityIdentifier("im.safety.cancel")
            }
        case .submitting:
            ProgressView("im.safety.submitting").accessibilityIdentifier("im.safety.submitting")
        case .verifying:
            ProgressView("im.safety.verifying").accessibilityIdentifier("im.safety.verifying")
        case .acknowledged(let action):
            let copy = IMSafetyCopy(action)
            Section {
                Label(LocalizedStringKey(copy.doneKey), systemImage: "checkmark.circle").accessibilityIdentifier("im.safety.done")
                if let key = copy.doneDetailKey { Text(LocalizedStringKey(key)) }
            }
            Button("action.close") { close() }.accessibilityIdentifier("im.safety.doneClose")
        case .rejected(let action, let message):
            Section {
                Label(LocalizedStringKey(IMSafetyCopy(action).failureKey), systemImage: "xmark.octagon").accessibilityIdentifier("im.safety.rejected")
                if let message, !message.isEmpty { Text(verbatim: message) }
                Button("im.safety.retrySame") { run { await model.owner.retryUnchanged() } }.accessibilityIdentifier("im.safety.retry")
            }
        case .outcomeUnknown(let action):
            Section {
                Label("im.safety.unknown", systemImage: "questionmark.circle").accessibilityIdentifier("im.safety.unknown")
                if case .report = action {
                    Text("im.safety.unknownReport")
                } else {
                    Text("im.safety.unknownHint")
                    Button("im.safety.verify") { run { await model.owner.verify() } }.accessibilityIdentifier("im.safety.verify")
                }
                Button("im.safety.retrySame") { run { await model.owner.retryUnchanged() } }.accessibilityIdentifier("im.safety.retry")
            }
        case .notApplied:
            Section {
                Label("im.safety.notApplied", systemImage: "arrow.uturn.backward.circle").accessibilityIdentifier("im.safety.notApplied")
                Text("im.safety.notAppliedHint")
                Button("im.safety.retrySame") { run { await model.owner.retryUnchanged() } }.accessibilityIdentifier("im.safety.retry")
            }
        }
    }
    private func run(_ body: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        task = Task { @MainActor in await body(); task = nil }
    }
    private func close() { dismiss() }
}
