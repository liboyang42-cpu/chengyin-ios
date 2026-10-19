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
    var body: some View {
        if let tab = MyProjectTab(rawValue: type) {
            let keys = MyProjectListPresentation.emptyKeys(for: tab, canPublishActivity: false)
            ContentUnavailableView {
                Label(LocalizedStringKey(keys.title), systemImage: "square.stack")
            } description: {
                if let detail = keys.detail { Text(LocalizedStringKey(detail)) }
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
    /// Same own-shelf the template launch page opens; reads `/api/template/my-list` through the session coordinator.
    @MainActor func myProjectTemplateShelf() -> AnyView {
        AnyView(TemplateAuthoringMineView(coordinator: templateShelfCoordinator(), sessionRevision: sessionRevision,
            memberDetail: { AnyView(SessionOwnedMemberTemplateDetailView(id: $0)) },
            ownerConfiguration: { AnyView(SessionOwnedTemplateConfigurationView(id: $0)) },
            creatorConsent: { AnyView(SessionWorkshopCreatorConsentView(selection: $0)) })
            .id(templateShelfViewIdentity))
    }
}
