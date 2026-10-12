import SwiftUI

@MainActor final class ClubPostEditExitModel: ObservableObject {
    struct Scope: Equatable {
        let clubID: Int
        let postID: Int
        let postClubID: Int?
        let version: Int
        let owner: ObjectIdentifier
        let session: ClubCommunitySession?
        let original: ClubPostEditDraft
    }
    struct Ticket: Identifiable, Equatable {
        let id: UUID
        let lifetime: UUID
        let scope: Scope
        let draft: ClubPostEditDraft
    }
    enum Decision: Equatable { case blocked, close, confirm }
    @Published private(set) var dialog = false
    private(set) var pending: Ticket?
    private var visible = false
    private var lifetime = UUID()

    func appear() { visible = true }
    func leave() { visible = false; invalidate() }
    func invalidate() { lifetime = UUID(); pending = nil; dialog = false }
    // SwiftUI may dismiss presentation before invoking its chosen button. Keep
    // the ticket until the explicit action, a new request, or invalidation.
    func presentationChanged(_ presented: Bool) { if !presented { dialog = false } }
    private func live(_ scope: Scope, currentSession: ClubCommunitySession?, canExit: Bool) -> Bool {
        visible && canExit && scope.clubID > 0 && scope.postID > 0 &&
        scope.postClubID == scope.clubID && scope.session?.identity.isSignedIn == true &&
        scope.session == currentSession
    }
    func request(scope: Scope, draft: ClubPostEditDraft,
                 currentSession: ClubCommunitySession?, canExit: Bool) -> Decision {
        guard live(scope, currentSession: currentSession, canExit: canExit) else { return .blocked }
        if draft == scope.original { leave(); return .close }
        if !dialog { pending = .init(id: UUID(), lifetime: lifetime, scope: scope, draft: draft) }
        dialog = true
        return .confirm
    }
    func keepEditing(_ ticket: Ticket) {
        guard pending == ticket else { return }
        pending = nil; dialog = false
    }
    func discard(_ ticket: Ticket, scope: Scope, draft: ClubPostEditDraft,
                 currentSession: ClubCommunitySession?, canExit: Bool) -> Bool {
        guard live(scope, currentSession: currentSession, canExit: canExit),
              pending == ticket, ticket.lifetime == lifetime,
              ticket.scope == scope, ticket.draft == draft else { return false }
        leave()
        return true
    }
}

@MainActor struct ClubPostEditExitControl: View {
    let post: ClubCommunityPost
    let clubID: Int
    @ObservedObject var source: ClubCommunityViewModel
    @Binding var content: String
    @Binding var images: [String]
    let canExit: () -> Bool
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = ClubPostEditExitModel()
    private var draft: ClubPostEditDraft { .init(content: content, images: images) }
    private var original: ClubPostEditDraft { .init(content: post.content, images: post.images) }
    private var session: ClubCommunitySession? { try? source.context.currentSession() }
    private var scope: ClubPostEditExitModel.Scope {
        .init(clubID: clubID, postID: post.id, postClubID: post.clubID, version: post.version,
              owner: ObjectIdentifier(source), session: session, original: original)
    }
    var body: some View {
        Button("club.community.cancel") {
            let decision = model.request(scope: scope, draft: draft,
                                         currentSession: session, canExit: canExit() && scenePhase == .active)
            if decision == .close { close() }
        }
        .disabled(!canExit() || scenePhase != .active)
        .accessibilityIdentifier("club.postEditExit.cancel")
        .confirmationDialog("club.postEditExit.title",
            isPresented: Binding(get: { model.dialog }, set: { model.presentationChanged($0) }),
            titleVisibility: .visible, presenting: model.pending) { ticket in
                Button("club.postEditExit.discard", role: .destructive) {
                    guard model.discard(ticket, scope: scope, draft: draft, currentSession: session,
                                        canExit: canExit() && scenePhase == .active) else { return }
                    close()
                }.accessibilityIdentifier("club.postEditExit.discard")
                Button("club.postEditExit.keep", role: .cancel) { model.keepEditing(ticket) }
                    .accessibilityIdentifier("club.postEditExit.keep")
            } message: { _ in Text("club.postEditExit.message") }
        .onAppear { model.appear() }
        .onDisappear { model.leave() }
        .onChange(of: draft) { _, _ in model.invalidate() }
        .onChange(of: scope) { _, _ in model.invalidate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appear() } else { model.leave() }
        }
    }
}
