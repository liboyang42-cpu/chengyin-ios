import SwiftUI
import Observation

/// The account NavigationStack owns the route; a covered detail is still on that stack.
@MainActor @Observable final class ProfileFavoriteTopicNavigationOwner {
    private(set) var selection: ProfileFavoriteTopicSelection?
    private var mounted = false
    private var foreground = false
    private var scope: UUID?
    func appear(scope: UUID, foreground: Bool) {
        mounted = true; self.foreground = foreground; updateScope(scope)
    }
    func updateScope(_ value: UUID) {
        if scope != value { retireSelection(); scope = value }
    }
    func setForeground(_ value: Bool) {
        foreground = value
        if !value { retireSelection() }
    }
    func disappear() { mounted = false; retireSelection() }
    @discardableResult func open(_ next: ProfileFavoriteTopicSelection, scope: UUID) -> Bool {
        guard mounted, foreground, self.scope == scope, next.isCurrent else { return false }
        retireSelection(); selection = next; return true
    }
    @discardableResult func close(id: UUID) -> Bool {
        guard let selected = selection, selected.id == id else { return false }
        selected.retire(); selection = nil; return true
    }
    func binding(for selected: ProfileFavoriteTopicSelection) -> Binding<ProfileFavoriteTopicSelection?> {
        let id = selected.id
        return Binding(get: {
            guard self.selection?.id == id, selected.isCurrent else { return nil }
            return selected
        }, set: { value in
            if value == nil { _ = self.close(id: id) }
        })
    }
    private func retireSelection() { selection?.retire(); selection = nil }
}

/// A new UUID mounts a new non-nil native item binding; no initial-nil binding is reused.
@MainActor struct ProfileFavoriteTopicNavigationLayer<Destination: View>: View {
    let owner: ProfileFavoriteTopicNavigationOwner
    let destination: (ProfileFavoriteTopicSelection) -> Destination
    var body: some View {
        Group {
            if let selected = owner.selection {
                Color.clear
                    .navigationDestination(item: owner.binding(for: selected), destination: destination)
                    .id(selected.id)
            }
        }
    }
}

/// Reuses the original full detail and its chapter/activity children; only this selection reads.
@MainActor struct ProfileFavoriteTopicDestination: View {
    let selection: ProfileFavoriteTopicSelection
    @ObservedObject var session: AppSession
    let makeReader: () -> ProfileFavoriteTopicReader
    @State private var reader: ProfileFavoriteTopicReader?
    var body: some View {
        ZStack {
            if let reader, selection.isCurrent {
                SessionTopicDetailView(id: selection.topicID, session: session, topicReaderOverride: reader).id(reader.scope)
            } else if selection.isCurrent { ProgressView("topic.loading") }
            else { AccountCollectionIssueView(issue: .login) }
        }
        .onAppear {
            guard reader == nil, selection.isCurrent else { return }
            reader = makeReader()
        }
    }
}
