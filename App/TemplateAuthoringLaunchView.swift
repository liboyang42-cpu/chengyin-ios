import SwiftUI

@MainActor struct TemplateAuthoringLaunchView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        List {
            Section { Text("templateAuthor.introBody"); Text("templateAuthor.unavailable").foregroundStyle(.secondary) }
            Section {
                NavigationLink {
                    TemplateAuthoringView(coordinator: session.templateAuthoringEditor(), sessionRevision: session.sessionRevision, metadataReader: session,
                        imageSelectionApproved: { session.retainedImagePickerHost.nativeSelectionEnabled })
                } label: { Label("templateAuthor.title", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("templateAuthor.openEditor")
                NavigationLink {
                    TemplateAuthoringMineView(coordinator: session.templateShelfCoordinator(), sessionRevision: session.sessionRevision, memberDetail: { AnyView(SessionOwnedMemberTemplateDetailView(id: $0)) }, ownerConfiguration: { AnyView(SessionOwnedTemplateConfigurationView(id: $0)) })
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
