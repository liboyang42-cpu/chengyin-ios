import SwiftUI

/// Host-provided own-shelf for the "模板" tab of mini-program subpackageA/pages/myproject.
/// Absent hosts show an explicit unavailable state instead of reusing `api/project/my` rows.
struct MyProjectTemplateShelfHost {
    let make: @MainActor () -> AnyView
}

private struct MyProjectTemplateShelfKey: EnvironmentKey {
    static let defaultValue: MyProjectTemplateShelfHost? = nil
}

extension EnvironmentValues {
    var myProjectTemplateShelf: MyProjectTemplateShelfHost? {
        get { self[MyProjectTemplateShelfKey.self] }
        set { self[MyProjectTemplateShelfKey.self] = newValue }
    }
}

/// Host-provided publishing entry for the empty-state CTA and the activity create row.
/// `canPublishActivity` mirrors the mini's local `roleGuard.role() === 'club'` gate; the publishing
/// hub re-checks `api/publish/home` before any activity review, so this only decides visibility.
struct MyProjectPublishEntry {
    let canPublishActivity: Bool
    let make: @MainActor () -> AnyView
}

private struct MyProjectPublishEntryKey: EnvironmentKey {
    static let defaultValue: MyProjectPublishEntry? = nil
}

extension EnvironmentValues {
    var myProjectPublishEntry: MyProjectPublishEntry? {
        get { self[MyProjectPublishEntryKey.self] }
        set { self[MyProjectPublishEntryKey.self] = newValue }
    }
}

/// Mini "发布单场活动" row above a non-empty activity list.
@MainActor struct MyProjectCreateActivityRow: View {
    let type: String
    let rowCount: Int
    @Environment(\.myProjectPublishEntry) private var entry
    var body: some View {
        if type == MyProjectTab.activity.rawValue, rowCount > 0, let entry, entry.canPublishActivity {
            NavigationLink { entry.make() } label: { Label("myProject.cta.activity", systemImage: "plus") }
                .accessibilityIdentifier("myProject.createActivity")
        }
    }
}

@MainActor struct MyProjectTemplateTabSection: View {
    let shelf: MyProjectTemplateShelfHost?
    var body: some View {
        Section {
            Text("myProject.template.scope").font(.caption).foregroundStyle(.secondary)
            if let shelf {
                NavigationLink { shelf.make() } label: {
                    Label("myProject.template.open", systemImage: "square.stack.3d.up")
                }.accessibilityIdentifier("myProject.template.open")
            } else {
                Text("myProject.template.unavailable").accessibilityIdentifier("myProject.template.unavailable")
            }
        }
    }
}

@MainActor struct MyProjectEmptyView: View {
    let type: String
    @Environment(\.myProjectPublishEntry) private var entry
    var body: some View {
        if let tab = MyProjectTab(rawValue: type) {
            let canPublishActivity = entry?.canPublishActivity == true
            let keys = MyProjectListPresentation.emptyKeys(for: tab, canPublishActivity: canPublishActivity)
            ContentUnavailableView {
                Label(LocalizedStringKey(keys.title), systemImage: "square.stack")
            } description: {
                if let detail = keys.detail { Text(LocalizedStringKey(detail)) }
            } actions: {
                if let entry, let cta = MyProjectListPresentation.emptyCTAKey(for: tab, canPublishActivity: canPublishActivity) {
                    NavigationLink { entry.make() } label: { Text(LocalizedStringKey(cta)) }
                        .accessibilityIdentifier("myProject.emptyCTA." + type)
                }
            }.accessibilityIdentifier("myProject.empty." + type)
        } else {
            ContentUnavailableView("creatorContent.empty", systemImage: "square.stack")
        }
    }
}

/// Card lines the mini-program derives locally: role tag, pending dot, schedule text.
@MainActor struct MyProjectCardMeta: View {
    let project: CreatorContentProject
    let chinese: Bool
    var body: some View {
        let card = MyProjectListPresentation.card(project)
        HStack(spacing: 6) {
            if card.pending { Circle().fill(Color.red).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(LocalizedStringKey(card.roleKey)).font(.caption.bold())
        }
        if let when = MyProjectListPresentation.whenText(start: project.startTime, end: project.endTime, chinese: chinese) {
            Text(verbatim: when).font(.caption)
        }
        if let address = project.addressName { Text(verbatim: address).font(.caption).foregroundStyle(.secondary) }
    }
}

/// Long-press list management. Every mutation stays disabled: toggle/cancel/delete have no reviewed
/// endpoint allowlist entry yet, so the menu only explains which actions the mini-program offers here.
@MainActor struct MyProjectRowOperationsMenu: View {
    let project: CreatorContentProject
    static func hasOperations(_ rows: [CreatorContentProject]) -> Bool {
        rows.contains { !MyProjectListPresentation.card($0).operations.isEmpty }
    }
    var body: some View {
        let card = MyProjectListPresentation.card(project)
        ForEach(card.operations, id: \.self) { op in
            Button(role: op == .delete ? .destructive : nil) {} label: {
                Text(LocalizedStringKey(op == .toggle ? card.toggleKey : op.localizationKey))
            }.disabled(true)
        }
        if !card.operations.isEmpty { Text("myProject.op.unavailable") }
    }
}

extension AppSession {
    /// Ordinary publishing hub; activity visibility follows the local session role like the mini.
    @MainActor func myProjectPublishEntry() -> MyProjectPublishEntry {
        .init(canPublishActivity: publishingSession?.role == "club",
              make: { AnyView(SessionPublishingModesView().environmentObject(self).id(self.publishingSession?.epoch)) })
    }

    /// Same own-shelf the template launch page opens; reads `/api/template/my-list` through the session coordinator.
    @MainActor func myProjectTemplateShelf() -> AnyView {
        AnyView(TemplateAuthoringMineView(coordinator: templateShelfCoordinator(), sessionRevision: sessionRevision,
            memberDetail: { AnyView(SessionOwnedMemberTemplateDetailView(id: $0)) },
            ownerConfiguration: { AnyView(SessionOwnedTemplateConfigurationView(id: $0)) },
            creatorConsent: { AnyView(SessionWorkshopCreatorConsentView(selection: $0)) })
            .id(templateShelfViewIdentity))
    }
}
