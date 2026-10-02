import SwiftUI

/// Session publisher tears down every private Square destination on account/epoch change.
@MainActor struct SessionSquareBrowserView: View {
    @ObservedObject var session: AppSession
    let onClose: () -> Void
    let onSignIn: () -> Void
    var body: some View {
        SquareBrowserView(reader: session.squareReader, accountReader: session.socialAccountReader,
            actions: session.socialActionCoordinator, workspace: session.squareWorkspace(),
            governance: session.squareGovernance(), governanceAccess: { session.squareGovernanceAccess(postID: $0) },
            onSignIn: onSignIn, onClose: onClose)
            .environment(\.squareReportContext, session.squareReportContext())
            .id(session.sessionRevision).privacySensitive()
    }
}
