import SwiftUI

/// One completion token is shared by the entry and sheet. Done, Close, swipe,
/// background and parent disappearance cannot deliver twice or retire a successor.
@MainActor final class ProfileFavoriteRemovalPresentation: Identifiable {
    let id: UUID
    let postID: Int
    let scope: UUID
    private(set) var isFinished = false
    init(id: UUID, postID: Int, scope: UUID) { self.id = id; self.postID = postID; self.scope = scope }
    func finish(controller: ProfileFavoriteRemovalController, isCurrent: @escaping () -> Bool,
                onRemoved: @escaping () async -> Void) {
        guard !isFinished else { return }
        isFinished = true
        let removed = controller.presentationID == id && controller.phase == .removed &&
            controller.isAvailable(postID: postID, collectionScope: scope) && isCurrent()
        controller.retire(id)
        if removed { Task { if isCurrent() { await onRemoved() } } }
    }
}

/// No nil/disabled production button. A reviewed factory must supply the exact capability.
@MainActor struct ProfileFavoriteRemovalEntry: View {
    let post: SquarePost
    let scope: UUID
    let controller: ProfileFavoriteRemovalController
    let isCurrent: () -> Bool
    let onRemoved: () async -> Void
    @State private var presentation: ProfileFavoriteRemovalPresentation?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if isCurrent(), controller.isAvailable(post: post, collectionScope: scope) {
                Button("profile.favoriteRemoval.open", role: .destructive) {
                    guard scenePhase == .active, isCurrent(), let id = controller.begin(post: post, collectionScope: scope) else { return }
                    presentation = .init(id: id, postID: post.id, scope: scope)
                }.disabled(controller.isBusy)
                    .accessibilityIdentifier("profile.favoriteRemoval.open.\(post.id)")
            }
        }
        .sheet(item: $presentation) { value in
            ProfileFavoriteRemovalSheet(presentation: value, contents: post.contents, controller: controller,
                isCurrent: isCurrent, onRemoved: onRemoved)
        }
        .onChange(of: scope) { _, _ in close() }
        .onChange(of: scenePhase) { _, value in if value != .active { close() } }
        .onDisappear { close() }
    }
    private func close() {
        presentation?.finish(controller: controller, isCurrent: isCurrent, onRemoved: onRemoved)
        presentation = nil
    }
}

/// This owner stays mounted when an unresolved post disappears from the saved list
/// or successful reconciliation clears its journal row. It never creates a write review.
@MainActor struct ProfileFavoriteRecoverySection: View {
    let scope: UUID
    let controller: ProfileFavoriteRemovalController
    let isCurrent: () -> Bool
    let onRemoved: () async -> Void
    @State private var presentation: ProfileFavoriteRemovalPresentation?
    @State private var readRevision = 0
    @Environment(\.scenePhase) private var scenePhase
    private var availability: ProfileFavoriteRemovalController.RecoveryAvailability {
        _ = readRevision
        return isCurrent() ? controller.recoveryAvailability(collectionScope: scope) : .unavailable
    }
    var body: some View {
        Group {
            switch availability {
            case .unavailable: EmptyView()
            case .unreadable:
                Section {
                    Text("profile.favoriteRecovery.unreadable", tableName: "ProfileSettingsFavorites")
                    Button("action.retry") { readRevision &+= 1 }
                        .accessibilityIdentifier("profile.favoriteRecovery.retry")
                }
            case .pending(let ids):
                // Keep a rendered section while its result sheet is open, even
                // after the successful readback removes the last pending row.
                if !ids.isEmpty || presentation != nil {
                    Section {
                        Text("profile.favoriteRecovery.explanation", tableName: "ProfileSettingsFavorites")
                        ForEach(ids, id: \.self) { postID in
                            Button {
                                guard scenePhase == .active, isCurrent(),
                                      let id = controller.beginRecovery(postID: postID, collectionScope: scope) else { return }
                                presentation = .init(id: id, postID: postID, scope: scope)
                            } label: {
                                HStack {
                                    Text("profile.favoriteRecovery.check", tableName: "ProfileSettingsFavorites")
                                    Text(verbatim: String(postID))
                                }
                            }.disabled(controller.isBusy)
                                .accessibilityIdentifier("profile.favoriteRecovery.open.\(postID)")
                        }
                    } header: { Text("profile.favoriteRecovery.title", tableName: "ProfileSettingsFavorites") }
                }
            }
        }
        .sheet(item: $presentation) { value in
            ProfileFavoriteRemovalSheet(presentation: value, controller: controller,
                isCurrent: isCurrent, onRemoved: onRemoved)
        }
        .onChange(of: scope) { _, _ in close() }
        .onChange(of: scenePhase) { _, value in if value != .active { close() } }
        .onDisappear { close() }
    }
    private func close() {
        presentation?.finish(controller: controller, isCurrent: isCurrent, onRemoved: onRemoved)
        presentation = nil
    }
}

@MainActor private struct ProfileFavoriteRemovalSheet: View {
    let presentation: ProfileFavoriteRemovalPresentation
    var contents: String? = nil
    let controller: ProfileFavoriteRemovalController
    let isCurrent: () -> Bool
    let onRemoved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private var current: Bool {
        !presentation.isFinished && isCurrent() && controller.presentationID == presentation.id &&
            controller.isAvailable(postID: presentation.postID, collectionScope: presentation.scope)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let contents { Text(verbatim: contents).lineLimit(6) }
                    LabeledContent("profile.favoriteRemoval.postID", value: String(presentation.postID))
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
                                Button("profile.favoriteRemoval.confirm", role: .destructive) {
                                    Task { guard scenePhase == .active, current else { return }; await controller.confirm(review) }
                                }.accessibilityIdentifier("profile.favoriteRemoval.confirm")
                            }
                        case .failed:
                            Text("profile.favoriteRemoval.failed")
                            Button("action.retry") {
                                Task { guard scenePhase == .active, current else { return }; await controller.retryPreparation(presentation.id) }
                            }.accessibilityIdentifier("profile.favoriteRemoval.retry")
                        case .unknown:
                            Text("profile.favoriteRemoval.unknown")
                            Button("profile.favoriteRemoval.check") {
                                Task { guard scenePhase == .active, current else { return }; await controller.reconcile(presentation.id) }
                            }.accessibilityIdentifier("profile.favoriteRemoval.check")
                        case .removed:
                            Text("profile.favoriteRecovery.removed", tableName: "ProfileSettingsFavorites")
                            Button("action.done") { close() }.accessibilityIdentifier("profile.favoriteRemoval.done")
                        }
                    }
                }
            }
            .appNavigationTitle("profile.favoriteRemoval.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("action.close") { close() }.accessibilityIdentifier("profile.favoriteRemoval.close")
            } }
            .task(id: presentation.id) {
                guard scenePhase == .active, current else { return }
                await controller.prepare(presentation.id)
            }
            .onDisappear { finish() }
        }
    }
    private func finish() {
        presentation.finish(controller: controller, isCurrent: isCurrent, onRemoved: onRemoved)
    }
    private func close() { finish(); dismiss() }
}
