import SwiftUI

/// Both routes are pure local authoring. Guests can edit/review only in memory;
/// account-scoped Keychain saving requires the configured, authenticated session.
@MainActor struct ProjectEditLaunchView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        List {
            if session.account == nil {
                Section { Text("projectEdit.signIn") }
            }
            Section {
                NavigationLink { SessionPublishingModesView().id(session.publishingSession?.epoch) } label: {
                    Label("publishModes.title", systemImage: "square.and.pencil")
                }.accessibilityIdentifier("projectEdit.openPublishingModes")
            }
            Section("projectEdit.title") {
                NavigationLink {
                    ProjectEditView(coordinator: session.projectEditor(product: .city), sessionRevision: session.sessionRevision, publisherClient: session.publisherLifecycleContext?.client, publisherHost: { AnyView(SessionPublisherLifecycleView(session: session, resource: $0)) }).id(session.projectEditorContextID)
                } label: { Label("projectEdit.city", systemImage: "map") }
                    .accessibilityIdentifier("projectEdit.openCity")
                NavigationLink {
                    ProjectEditView(coordinator: session.projectEditor(product: .freeExplore), sessionRevision: session.sessionRevision, publisherClient: session.publisherLifecycleContext?.client, publisherHost: { AnyView(SessionPublisherLifecycleView(session: session, resource: $0)) }).id(session.projectEditorContextID)
                } label: { Label("projectEdit.freeExplore", systemImage: "location.magnifyingglass") }
                    .accessibilityIdentifier("projectEdit.openFreeExplore")
            }
            Section {
                NavigationLink { SessionCreatorProjectsView(session: session) } label: { Text("creatorContent.projects") }
                    .accessibilityIdentifier("projectRemote.myProjects")
            }
        }.appNavigationTitle("projectEdit.title")
    }
}
