import SwiftUI

/// Supplied by the ordinary own-account host using its existing editor, never a new write grant.
@MainActor struct ProfileSelfEditAccess {
    let coordinator: ProfileEditCoordinator
    let sessionRevision: UInt64
    var categoryReader: (any DiscoveryReading)? = nil
    func context(memberID: Int, reader: any SocialAccountReading, isCurrent: Bool) -> ProfileSelfEditContext? {
        .init(memberID: memberID, reader: reader, viewer: reader.identity, readerRevision: reader.presentationRevision,
              readerConfigured: reader.isConfigured, coordinator: coordinator, editorIdentity: coordinator.identity,
              editorRevision: coordinator.viewerRevision, editorConfigured: coordinator.isConfigured, isCurrent: isCurrent)
    }
}

@MainActor struct ProfileSelfEditDestination: View {
    let ticket: ProfileSelfEditTicket
    let access: ProfileSelfEditAccess?
    let isCurrent: () -> Bool
    var diagnosticText: (@MainActor () -> String)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if isCurrent(), let access {
                // Reuse the whole existing editor, including local field edits, discard review,
                // server-save gates and durable unknown-write handling. No shortcut save.
                ProfileEditView(coordinator: access.coordinator, sessionRevision: access.sessionRevision,
                    categoryReader: access.categoryReader)
                    .id(ticket.id)
            } else {
                ContentUnavailableView {
                    Label("profile.selfEdit.changed", systemImage: "person.crop.circle.badge.exclamationmark")
                } actions: {
                    Button("action.close") { dismiss() }.accessibilityIdentifier("profile.selfEdit.closeChanged")
                }
                #if DEBUG
                if let diagnosticText {
                    Text(verbatim: diagnosticText()).font(.caption)
                        .accessibilityIdentifier("profile.selfEdit.fixture.context")
                }
                #endif
            }
        }.accessibilityIdentifier("profile.selfEdit.destination")
    }
}
