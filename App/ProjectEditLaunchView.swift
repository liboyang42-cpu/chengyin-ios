import SwiftUI

/// Both routes are pure local authoring. Guests can edit/review only in memory;
/// account-scoped Keychain saving requires the configured, authenticated session.
@MainActor struct ProjectEditLaunchView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        List {
            Section {
                if !session.projectEditorIsConfigured { Text("projectEdit.unconfigured").foregroundStyle(.secondary) }
                if session.account == nil { Text("projectEdit.signIn").foregroundStyle(.secondary) }
            }
            Section {
                NavigationLink { SessionPublishingModesView().id(session.publishingSession?.epoch) } label: {
                    Label("publishModes.title", systemImage: "square.and.pencil")
                }.accessibilityIdentifier("projectEdit.openPublishingModes")
            }
            Section(session.projectEditorIsConfigured ? "projectEdit.title" : "projectEdit.createLocal") {
                NavigationLink {
                    ProjectEditView(coordinator: session.projectEditor(product: .city), sessionRevision: session.sessionRevision, publisherClient: session.publisherLifecycleContext?.client, publisherHost: { AnyView(SessionPublisherLifecycleView(session: session, resource: $0)) })
                } label: { Label("projectEdit.city", systemImage: "map") }
                    .accessibilityIdentifier("projectEdit.openCity")
                NavigationLink {
                    ProjectEditView(coordinator: session.projectEditor(product: .freeExplore), sessionRevision: session.sessionRevision, publisherClient: session.publisherLifecycleContext?.client, publisherHost: { AnyView(SessionPublisherLifecycleView(session: session, resource: $0)) })
                } label: { Label("projectEdit.freeExplore", systemImage: "location.magnifyingglass") }
                    .accessibilityIdentifier("projectEdit.openFreeExplore")
            }
            Section { Text("projectEdit.remoteEditDeferred").foregroundStyle(.secondary) }
        }.appNavigationTitle("projectEdit.title")
    }
}
