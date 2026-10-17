import SwiftUI

/// A completion route is presentation only. It grants neither shelf reads nor writes.
@MainActor struct TemplateAuthoringCompletionContext {
    let isCurrent: () -> Bool
    let library: () -> AnyView
}

extension AppSession {
    @MainActor var templateAuthoringCompletionContext: TemplateAuthoringCompletionContext {
        let identity = templateAuthoringViewIdentity
        return .init(isCurrent: { self.templateAuthoringViewIdentity == identity }, library: {
            AnyView(Group {
                if self.templateAuthoringViewIdentity == identity {
                    TemplateAuthoringMineView(coordinator: self.templateShelfCoordinator(), sessionRevision: self.sessionRevision,
                        memberDetail: { AnyView(SessionOwnedMemberTemplateDetailView(id: $0)) },
                        ownerConfiguration: { AnyView(SessionOwnedTemplateConfigurationView(id: $0)) },
                        creatorConsent: { AnyView(SessionWorkshopCreatorConsentView(selection: $0)) })
                        .id(self.templateShelfViewIdentity)
                } else { Text("discovery.templateSessionChanged") }
            })
        })
    }
}

@MainActor struct TemplateAuthoringLaunchView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        List {
            Section { Text("templateAuthor.introBody"); Text("templateAuthor.unavailable").foregroundStyle(.secondary) }
            Section {
                NavigationLink {
                    let coordinator = session.templateAuthoringEditor()
                    let library: () -> AnyView = {
                        AnyView(TemplateAuthoringMineView(coordinator: session.templateShelfCoordinator(), sessionRevision: session.sessionRevision,
                            memberDetail: { AnyView(SessionOwnedMemberTemplateDetailView(id: $0)) }, ownerConfiguration: { AnyView(SessionOwnedTemplateConfigurationView(id: $0)) },
                            creatorConsent: { AnyView(SessionWorkshopCreatorConsentView(selection: $0)) }).id(session.templateShelfViewIdentity))
                    }
                    TemplateAuthoringSaveFlow(coordinator: coordinator, sessionRevision: session.sessionRevision, metadataReader: session,
                        imageSelectionApproved: { session.retainedImagePickerHost.nativeSelectionEnabled }, library: library)
                        .modifier(TemplateAuthoringPublishCompletion(coordinator: coordinator, library: library))
                        .id(session.sessionRevision)
                } label: { Label("templateAuthor.title", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("templateAuthor.openEditor")
                NavigationLink {
                    TemplateAuthoringMineView(coordinator: session.templateShelfCoordinator(), sessionRevision: session.sessionRevision, memberDetail: { AnyView(SessionOwnedMemberTemplateDetailView(id: $0)) }, ownerConfiguration: { AnyView(SessionOwnedTemplateConfigurationView(id: $0)) }, creatorConsent: { AnyView(SessionWorkshopCreatorConsentView(selection: $0)) })
                        .id(session.templateShelfViewIdentity)
                } label: { Label("templateAuthor.mine", systemImage: "square.stack") }
                    .accessibilityIdentifier("templateAuthor.openMine")
                NavigationLink {
                    PrefabPreviewView(store: session.prefabPreviewStore, identity: .preview,
                                      sessionRevision: session.sessionRevision, currentSession: { session.currentTemplateAuthoringSession })
                } label: { Label("templateAuthor.prefab.title", systemImage: "book.pages") }
                    .accessibilityIdentifier("templateAuthor.openPrefab")
            }
        }.appNavigationTitle("templateAuthor.title")
    }
}
