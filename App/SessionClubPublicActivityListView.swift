import SwiftUI

/// The host owns a stable reader per original scope; body evaluation never mints a reader or grant.
@MainActor struct SessionClubPublicActivityListView: View {
    let clubID: Int
    @ObservedObject var session: AppSession
    var onSignIn: (() -> Void)? = nil
    @State private var source: ClubPublicTopicsReader?
    @State private var capturedScope: ClubPublicTopicsScope?
    private var scope: ClubPublicTopicsScope? { session.clubPublicTopicsScope(clubID: clubID) }
    var body: some View {
        ClubPublicActivityListView(clubID: clubID, session: session, onSignIn: onSignIn,
            source: capturedScope == scope ? source : nil)
            .task(id: scope) {
                source = nil; capturedScope = nil
                guard !Task.isCancelled, let expected = scope,
                      let reader = session.makeClubPublicTopicsReader(clubID: clubID),
                      reader.scope(clubID: clubID) == expected, scope == expected else { return }
                capturedScope = expected; source = reader
            }
    }
}
