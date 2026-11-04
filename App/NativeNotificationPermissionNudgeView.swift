import SwiftUI

@MainActor struct NativeNotificationPermissionNudgeView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    @Bindable var model: NativeNotificationPermissionState
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section {
                if model.busy {
                    ProgressView().accessibilityLabel(Text(n("permission.title")))
                        .accessibilityIdentifier("notification.permission.busy")
                }
                Label(NativeNotificationPermissionStatusPresentation.project(authorization: model.snapshot?.authorization, busy: model.busy, hasIssue: model.issue != nil).title(locale: locale), systemImage: "bell.badge")
                    .font(Theme.Font.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notification.permission.status")
                Text(n("permission.explanation"))
                    .font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                    .fixedSize(horizontal: false, vertical: true)
                if let snapshot = model.snapshot {
                    LabeledContent(n("permission.alerts"), value: label(snapshot.alerts))
                    LabeledContent(n("permission.sounds"), value: label(snapshot.sounds))
                    LabeledContent(n("permission.badges"), value: label(snapshot.badges))
                    if snapshot.authorization == .notDetermined {
                        Button(n("permission.request")) { Task { await model.requestFromUserAction() } }
                            .accessibilityIdentifier("notification.permission.request")
                    } else {
                        Button(n("permission.settings")) { Task { await model.openSettingsFromUserAction() } }
                            .accessibilityIdentifier("notification.permission.settings")
                    }
                }
            } footer: { Text(n("permission.delivery")) }
            if let issue = model.issue { Section { Text(NativeChannelNotificationPresentation.permissionIssue(issue, locale: locale)).foregroundStyle(Theme.Color.textSecondary(in: domain)) } }
            Button(n("permission.refresh")) { Task { await model.refresh() } }
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.bgPage(in: domain))
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .disabled(model.busy)
        .navigationTitle(NativeChannelNotificationPresentation.localized("notification.permission.title", locale: locale))
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
    }
    private func label(_ setting: NativeNotificationPermissionSetting) -> String {
        NativeChannelNotificationPresentation.setting(setting, locale: locale)
    }
}
