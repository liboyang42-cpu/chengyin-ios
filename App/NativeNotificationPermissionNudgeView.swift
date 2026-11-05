import SwiftUI

@MainActor struct NativeNotificationPermissionNudgeView: View {
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    @Bindable var model: NativeNotificationPermissionState
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section {
                if model.busy {
                    ProgressView().frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("d7.notifyPermission.title"))
                        .accessibilityIdentifier("notification.permission.busy")
                }
                Label(NativeNotificationPermissionStatusPresentation.project(authorization: model.snapshot?.authorization, busy: model.busy, hasIssue: model.issue != nil).title(locale: locale), systemImage: "bell.badge")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notification.permission.status")
                if let snapshot = model.snapshot {
                    LabeledContent(n("permission.alerts"), value: label(snapshot.alerts))
                    LabeledContent(n("permission.sounds"), value: label(snapshot.sounds))
                    LabeledContent(n("permission.badges"), value: label(snapshot.badges))
                }
            }
            if let snapshot = model.snapshot {
                Section {
                    if snapshot.authorization == .notDetermined {
                        Button("d7.notifyPermission.request") { let revision = model.revision; Task { await model.requestFromUserAction(expectedRevision: revision) } }
                            .accessibilityIdentifier("notification.permission.request")
                    } else {
                        Button("d7.notifyPermission.settings") { let revision = model.revision; Task { await model.openSettingsFromUserAction(expectedRevision: revision) } }
                            .accessibilityIdentifier("notification.permission.settings")
                    }
                }
            }
            if let issue = model.issue { Section { Text(NativeChannelNotificationPresentation.permissionIssue(issue, locale: locale)).foregroundStyle(.secondary) } }
        }
        .formStyle(.grouped)
        .disabled(model.busy)
        .navigationTitle(Text("d7.notifyPermission.title"))
        // Pull to refresh replaces the "read permission again" button; it also rereads on return to the app.
        .refreshable { let revision = model.revision; await model.refresh(expectedRevision: revision) }
        .task { await model.refresh(expectedRevision: model.revision) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { let revision = model.revision; Task { await model.refresh(expectedRevision: revision) } } }
        .onDisappear { model.retire() }
    }
    private func label(_ setting: NativeNotificationPermissionSetting) -> String {
        NativeChannelNotificationPresentation.setting(setting, locale: locale)
    }
}
