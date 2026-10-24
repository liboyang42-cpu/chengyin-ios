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
    @State private var editorVisit: UUID?
    var body: some View {
        List {
            Section { Text("templateAuthor.introBody"); Text("templateAuthor.unavailable").foregroundStyle(.secondary) }
            Section {
                Button { editorVisit = UUID() } label: {
                    Label("templateAuthor.title", systemImage: "square.and.pencil")
                }.accessibilityIdentifier("templateAuthor.openEditor")
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
            .onChange(of: session.templateAuthoringViewIdentity) { _, _ in editorVisit = nil }
            .navigationDestination(item: $editorVisit) { visit in
                TemplateAuthoringEntryDestination(factory: { session.templateAuthoringEditor() },
                    completion: session.templateAuthoringCompletionContext,
                    sessionRevision: session.sessionRevision, metadataReader: session,
                    imageSelectionApproved: { session.retainedImagePickerHost.nativeSelectionEnabled })
                    .id(visit)
            }
    }
}


/// Retained by one ordinary navigation visit. Saving, publishing, and editing must share
/// this exact coordinator even when the parent recomputes its destination body.
@MainActor final class TemplateAuthoringEntryOwner: ObservableObject {
    let coordinator: TemplateAuthoringCoordinator
    let completion: TemplateAuthoringCompletionContext
    init(factory: () -> TemplateAuthoringCoordinator, completion: TemplateAuthoringCompletionContext) {
        self.coordinator = factory()
        self.completion = completion
    }
    var isCurrent: Bool { completion.isCurrent() }
}

@MainActor struct TemplateAuthoringEntryDestination: View {
    let sessionRevision: UInt64
    let metadataReader: any DiscoveryReading
    let imageSelectionApproved: () -> Bool
    @StateObject private var owner: TemplateAuthoringEntryOwner
    init(factory: @escaping () -> TemplateAuthoringCoordinator, completion: TemplateAuthoringCompletionContext,
         sessionRevision: UInt64, metadataReader: any DiscoveryReading,
         imageSelectionApproved: @escaping () -> Bool) {
        self.sessionRevision = sessionRevision
        self.metadataReader = metadataReader
        self.imageSelectionApproved = imageSelectionApproved
        _owner = StateObject(wrappedValue: TemplateAuthoringEntryOwner(factory: factory, completion: completion))
    }
    var body: some View {
        Group {
            if owner.isCurrent {
                TemplateAuthoringSaveFlow(coordinator: owner.coordinator, sessionRevision: sessionRevision,
                    metadataReader: metadataReader,
                    imageSelectionApproved: { owner.isCurrent && imageSelectionApproved() },
                    library: owner.completion.library)
                    .modifier(TemplateAuthoringPublishCompletion(coordinator: owner.coordinator,
                        library: owner.completion.library))
            } else { Text("discovery.templateSessionChanged") }
        }.accessibilityIdentifier("templateAuthor.entryFlow")
    }
}
