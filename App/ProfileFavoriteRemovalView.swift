import SwiftUI

/// No nil/disabled production button. A reviewed factory must supply the exact capability.
@MainActor struct ProfileFavoriteRemovalEntry: View {
    let post: SquarePost
    let scope: UUID
    let controller: ProfileFavoriteRemovalController
    let isCurrent: () -> Bool
    let onRemoved: () async -> Void
    private struct Presentation: Identifiable { let id: UUID }
    @State private var presentation: Presentation?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if isCurrent(), controller.isAvailable(post: post, collectionScope: scope) {
                Button("profile.favoriteRemoval.open", role: .destructive) {
                    guard scenePhase == .active, isCurrent(), let id = controller.begin(post: post, collectionScope: scope) else { return }
                    presentation = .init(id: id)
                }.disabled(controller.isBusy)
                    .accessibilityIdentifier("profile.favoriteRemoval.open.\(post.id)")
            }
        }
        .sheet(item: $presentation) { value in
            ProfileFavoriteRemovalSheet(id: value.id, post: post, scope: scope, controller: controller,
                isCurrent: isCurrent, onRemoved: onRemoved)
        }
        .onChange(of: scope) { _, _ in close() }
        .onChange(of: scenePhase) { _, value in if value != .active { close() } }
        .onDisappear { close() }
    }
    private func close() {
        if let id = presentation?.id { controller.retire(id) }
        presentation = nil
    }
}

@MainActor private struct ProfileFavoriteRemovalSheet: View {
    let id: UUID
    let post: SquarePost
    let scope: UUID
    let controller: ProfileFavoriteRemovalController
    let isCurrent: () -> Bool
    let onRemoved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var delivered = false
    private var current: Bool {
        isCurrent() && controller.presentationID == id && controller.isAvailable(post: post, collectionScope: scope)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let text = post.contents { Text(verbatim: text).lineLimit(6) }
                    LabeledContent("profile.favoriteRemoval.postID", value: String(post.id))
                    Text("profile.favoriteRemoval.explanation")
                }
                if !current { Section { Text("profile.favoriteRemoval.changed") } }
                else {
                    Section {
                        switch controller.phase {
                        case .idle: Text("profile.favoriteRemoval.changed")
                        case .loading, .working: ProgressView("profile.favoriteRemoval.working")
                        case .reviewed:
                            if let review = controller.review {
                                Button("profile.favoriteRemoval.confirm", role: .destructive) { Task { await controller.confirm(review) } }
                                    .accessibilityIdentifier("profile.favoriteRemoval.confirm")
                            }
                        case .failed:
                            Text("profile.favoriteRemoval.failed")
                            Button("action.retry") { Task { await controller.retryPreparation(id) } }
                                .accessibilityIdentifier("profile.favoriteRemoval.retry")
                        case .unknown:
                            Text("profile.favoriteRemoval.unknown")
                            Button("profile.favoriteRemoval.check") { Task { await controller.reconcile(id) } }
                                .accessibilityIdentifier("profile.favoriteRemoval.check")
                        case .removed:
                            Text("profile.favoriteRemoval.removed")
                            Button("action.done") { complete() }.accessibilityIdentifier("profile.favoriteRemoval.done")
                        }
                    }
                }
            }
            .appNavigationTitle("profile.favoriteRemoval.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("action.close") { controller.retire(id); dismiss() }.accessibilityIdentifier("profile.favoriteRemoval.close")
            } }
            .task(id: id) { await controller.prepare(id) }
            .onDisappear { controller.retire(id) }
        }
    }
    private func complete() {
        guard !delivered, current, controller.phase == .removed else { return }
        delivered = true; controller.retire(id); dismiss()
        Task { if isCurrent() { await onRemoved() } }
    }
}
