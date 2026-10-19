import SwiftUI

/// Opening chapter 出发 (mini-program `continueChapterStory`). Shown only while the
/// server reports a pending opening; the write needs explicit confirmation and an
/// unknown result is settled by re-reading the route, never by resubmitting.
@MainActor struct PlayOpeningCompletionSection: View {
    @Bindable var model: PlayOpeningCompletionCoordinator

    var body: some View {
        if PlayOpeningGate.suppressesCompletion(model.route) || model.phase != .idle {
            Section("playx.opening.title") {
                content
            }
            .accessibilityIdentifier("playx.opening")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .disabled:
            Text("playx.opening.disabled").accessibilityIdentifier("playx.opening.disabled")
        case .loading, .submitting:
            ProgressView("playx.loading")
        case .finishPlayFirst:
            Text("playx.opening.finishFirst").accessibilityIdentifier("playx.opening.finishFirst")
            departButton
        case .reviewing:
            Text("playx.opening.review").accessibilityIdentifier("playx.opening.review")
            Button("playx.opening.confirm") { Task { await model.confirm() } }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("playx.opening.confirm")
            Button("playx.opening.cancel", role: .cancel) { model.cancelReview() }
                .accessibilityIdentifier("playx.opening.cancel")
        case .departed:
            Text("playx.opening.departed").accessibilityIdentifier("playx.opening.departed")
        case .rejected(let message, _):
            if let message, !message.isEmpty { Text(verbatim: message).accessibilityIdentifier("playx.opening.rejected") }
            else { Text("playx.opening.saveFailed").accessibilityIdentifier("playx.opening.rejected") }
            departButton
        case .unknown:
            Text("playx.opening.unknown").accessibilityIdentifier("playx.opening.unknown")
            Button("playx.opening.readBack") { Task { await model.readBack() } }
                .accessibilityIdentifier("playx.opening.readBack")
        case .failed:
            Text("playx.opening.loadFailed")
            Button("playx.refresh") { Task { await model.load() } }
        case .idle:
            departButton
        }
    }

    private var departButton: some View {
        Button("playx.opening.depart") { model.depart(chapterIsOpening: true) }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("playx.opening.depart")
    }
}
