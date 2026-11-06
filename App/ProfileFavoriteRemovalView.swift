import SwiftUI
import Observation

/// Opt-in, payload-free UI-test evidence. No UUIDs, account data, or server values are emitted.
@MainActor @Observable final class ProfileFavoriteRemovalLifecycleDiagnostics {
    let enabled: Bool
    private(set) var events: [String] = []
    init() {
        #if DEBUG
        enabled = ProcessInfo.processInfo.arguments.contains("--uitesting-profile-favorite-removal-lifecycle")
        #else
        enabled = false
        #endif
    }
    func record(_ event: String, scene: ScenePhase, presentation: ProfileFavoriteRemovalPresentation?,
                controller: ProfileFavoriteRemovalController) {
        guard enabled else { return }
        let identity = presentation.map { controller.presentationID == $0.id ? "same" : "different" } ?? "none"
        let finished = presentation?.isFinished == true
        events.append("\(event):scene=\(scene);identity=\(identity);finished=\(finished);phase=\(controller.phase)")
        // Keep evidence even if SwiftUI retires the row and its state during presentation.
        if let latest = events.last { print("PROFILE_FAVORITE_LIFECYCLE \(latest)") }
        if events.count > 16 { events.removeFirst(events.count - 16) }
    }
    var value: String { events.joined(separator: " | ") }
}

private struct ProfileFavoriteRemovalLifecycleEvidence: ViewModifier {
    let diagnostics: ProfileFavoriteRemovalLifecycleDiagnostics?
    func body(content: Content) -> some View {
        if let diagnostics, diagnostics.enabled {
            content.accessibilityValue(Text(verbatim: diagnostics.value))
        } else { content }
    }
}

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
    @State private var lifecycle = ProfileFavoriteRemovalLifecycleDiagnostics()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if isCurrent(), controller.isAvailable(post: post, collectionScope: scope) {
                Button("profile.favoriteRemoval.open", role: .destructive) {
                    lifecycle.record("entry.tap", scene: scenePhase, presentation: presentation, controller: controller)
                    guard scenePhase == .active else {
                        lifecycle.record("entry.rejectedScene", scene: scenePhase, presentation: presentation, controller: controller)
                        return
                    }
                    guard isCurrent() else {
                        lifecycle.record("entry.rejectedCurrent", scene: scenePhase, presentation: presentation, controller: controller)
                        return
                    }
                    guard let id = controller.begin(post: post, collectionScope: scope) else {
                        lifecycle.record("entry.rejectedBegin", scene: scenePhase, presentation: presentation, controller: controller)
                        return
                    }
                    presentation = .init(id: id, postID: post.id, scope: scope)
                    lifecycle.record("entry.opened", scene: scenePhase, presentation: presentation, controller: controller)
                }.disabled(controller.isBusy)
                    .accessibilityIdentifier("profile.favoriteRemoval.open.\(post.id)")
                    .modifier(ProfileFavoriteRemovalLifecycleEvidence(diagnostics: lifecycle))
            }
        }
        .sheet(item: $presentation) { value in
            ProfileFavoriteRemovalSheet(presentation: value, contents: post.contents, controller: controller,
                isCurrent: isCurrent, onRemoved: onRemoved, diagnostics: lifecycle)
        }
        .onAppear { lifecycle.record("entryHost.appeared", scene: scenePhase, presentation: presentation, controller: controller) }
        .onChange(of: scope) { _, _ in
            lifecycle.record("entryHost.scopeChanged", scene: scenePhase, presentation: presentation, controller: controller)
            close()
        }
        .onChange(of: scenePhase) { _, value in
            lifecycle.record("entryHost.sceneChanged", scene: value, presentation: presentation, controller: controller)
            if value != .active { close() }
        }
        .onDisappear {
            lifecycle.record("entryHost.disappeared", scene: scenePhase, presentation: presentation, controller: controller)
            close()
        }
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
    @State private var lifecycle = ProfileFavoriteRemovalLifecycleDiagnostics()
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
                isCurrent: isCurrent, onRemoved: onRemoved, diagnostics: lifecycle)
        }
        .onAppear { lifecycle.record("recoveryHost.appeared", scene: scenePhase, presentation: presentation, controller: controller) }
        .onChange(of: scope) { _, _ in
            lifecycle.record("recoveryHost.scopeChanged", scene: scenePhase, presentation: presentation, controller: controller)
            close()
        }
        .onChange(of: scenePhase) { _, value in
            lifecycle.record("recoveryHost.sceneChanged", scene: value, presentation: presentation, controller: controller)
            if value != .active { close() }
        }
        .onDisappear {
            lifecycle.record("recoveryHost.disappeared", scene: scenePhase, presentation: presentation, controller: controller)
            close()
        }
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
    var diagnostics: ProfileFavoriteRemovalLifecycleDiagnostics? = nil
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
            .modifier(ProfileFavoriteRemovalLifecycleEvidence(diagnostics: diagnostics))
            .task(id: presentation.id) {
                diagnostics?.record("sheet.prepareEntered", scene: scenePhase, presentation: presentation, controller: controller)
                guard scenePhase == .active else {
                    diagnostics?.record("sheet.prepareRejectedScene", scene: scenePhase, presentation: presentation, controller: controller)
                    return
                }
                guard current else {
                    diagnostics?.record("sheet.prepareRejectedCurrent", scene: scenePhase, presentation: presentation, controller: controller)
                    return
                }
                await controller.prepare(presentation.id)
                diagnostics?.record("sheet.prepareReturned", scene: scenePhase, presentation: presentation, controller: controller)
            }
            .onDisappear {
                diagnostics?.record("sheet.disappeared", scene: scenePhase, presentation: presentation, controller: controller)
                finish()
            }
        }
    }
    private func finish() {
        diagnostics?.record("sheet.finish", scene: scenePhase, presentation: presentation, controller: controller)
        presentation.finish(controller: controller, isCurrent: isCurrent, onRemoved: onRemoved)
    }
    private func close() { finish(); dismiss() }
}
