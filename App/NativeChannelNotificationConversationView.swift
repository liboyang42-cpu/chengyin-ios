import SwiftUI

/// Screen ownership only; the original coordinator still owns grants, journal and writer.
typealias NativeChannelNotificationScreenOperation = @MainActor (NativeChannelNotificationCoordinator) async -> Void

@MainActor struct NativeChannelNotificationConversationView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    @Bindable var model: NativeChannelNotificationCoordinator
    let permission: NativeNotificationPermissionState
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var screenGeneration: UInt64 = 0
    @State private var screenTask: Task<Void, Never>?
    var body: some View {
        let ticket = screenGeneration
        Form {
            NativeChannelNotificationStatusSection(model: model, perform: { perform($0, expected: ticket) })
            Section { NativeChannelUnreadSummaryContent(model: model) }
            if let row = model.preference {
                NativeChannelNotificationEditor(model: model, preference: row,
                    perform: { perform($0, expected: ticket) }).id(row.version)
            } else if model.isBusy { ProgressView().accessibilityLabel(n("state.loading")) }
            Section {
                NavigationLink { NativeNotificationPermissionNudgeView(model: permission) } label: {
                    Label(permission.snapshot.map { NativeChannelNotificationPresentation.authorization($0.authorization, locale: locale) } ?? n("permission.system"), systemImage: "bell.badge")
                }
            }
            Section { Button(n("conversation.refresh")) { perform({ await $0.refresh() }, expected: ticket) }
                .disabled(model.isBusy || screenTask != nil) }
        }
        .formStyle(.grouped)
        .nativeChannelScreen()
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .navigationTitle(model.scope?.isAccountDefault == true ? n("global.accountDefault")
            : NativeChannelNotificationPresentation.localized("notification.channel.title", locale: locale))
        .accessibilityIdentifier("notification.conversation.screen")
        .onAppear { visible = true; reopen() }
        .onDisappear { visible = false; suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reopen() } else { suspend() }
        }
        .tint(Theme.Color.accent(in: domain))
    }
    private func suspend() {
        screenGeneration &+= 1
        screenTask?.cancel(); screenTask = nil
        model.deactivate()
    }
    private func reopen() {
        suspend()
        guard visible, scenePhase == .active else { return }
        start { await $0.activate() }
    }
    private func perform(_ operation: @escaping NativeChannelNotificationScreenOperation, expected: UInt64) {
        guard owns(expected), screenTask == nil, model.isCurrent else { return }
        start(operation)
    }
    private func start(_ operation: @escaping NativeChannelNotificationScreenOperation) {
        screenGeneration &+= 1
        let ticket = screenGeneration
        screenTask = Task { @MainActor in
            guard !Task.isCancelled, owns(ticket) else { return }
            await operation(model)
            guard !Task.isCancelled, owns(ticket) else { return }
            await permission.refresh()
            guard !Task.isCancelled, owns(ticket) else { return }
            screenTask = nil
        }
    }
    private func owns(_ ticket: UInt64) -> Bool {
        visible && scenePhase == .active && screenGeneration == ticket
    }
}

@MainActor struct NativeChannelNotificationStatusSection: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    @Bindable var model: NativeChannelNotificationCoordinator
    /// Optional to preserve existing message/ACK consumers; settings supply their visible owner.
    var perform: ((@escaping NativeChannelNotificationScreenOperation) -> Void)? = nil
    @State private var retryConfirmation = false
    var body: some View {
        Section {
            if !model.isCurrent && !model.isBusy {
                Text(n("state.accessClosed"))
            } else if let text = NativeChannelNotificationPresentation.state(model.state, locale: locale) {
                Text(text).nativeChannelNotice(systemImage: "bell").accessibilityIdentifier("notification.request.status")
            }
            if model.directory == nil && !model.isBusy && model.state == .ready { Text(n("empty")) }
            if let key = model.pendingRequestID {
                VStack(alignment: .leading, spacing: Theme.Space.s1) {
                    Text(n("recovery.requestID")).font(Theme.Font.label).foregroundStyle(.secondary)
                    Text(verbatim: key).font(.callout.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(n("recovery.check")) { run { await $0.checkReceipt() } }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .disabled(!model.canCheckReceipt).accessibilityIdentifier("notification.receipt.check")
                Button(n("recovery.retry")) { retryConfirmation = true }.disabled(!model.canCheckReceipt)
                    .accessibilityIdentifier("notification.receipt.retry")
            }
            if let detail = NativeChannelNotificationPresentation.failureDetail(model.lastFailure, state: model.state, locale: locale) {
                Text(detail).font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                    .accessibilityIdentifier("notification.request.explanation")
            }
            if model.unreadIssue { Text(n("recovery.unreadIssue")) }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .confirmationDialog(n("recovery.confirm"), isPresented: $retryConfirmation, titleVisibility: .visible) {
            Button(n("recovery.checkAndRetry")) { run { await $0.retryOriginal() } }
            Button(n("cancel"), role: .cancel) { }
        }
        .onDisappear { retryConfirmation = false }
        .onChange(of: model.isCurrent) { _, current in if !current { retryConfirmation = false } }
        .tint(Theme.Color.accent(in: domain))
    }
    private func run(_ operation: @escaping NativeChannelNotificationScreenOperation) {
        if let perform { perform(operation) }
        else { Task { await operation(model) } }
    }
}

@MainActor private struct NativeChannelNotificationEditor: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    let model: NativeChannelNotificationCoordinator
    let preference: NativeChannelNotificationPreference
    let perform: (@escaping NativeChannelNotificationScreenOperation) -> Void
    @State private var draft: NativeChannelNotificationDraft
    @State private var quietEnabled: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var zone: String
    @State private var preview: Int
    @State private var muteMenu = false
    @State private var saveConfirmation = false
    @State private var localIssue: String?
    init(model: NativeChannelNotificationCoordinator, preference: NativeChannelNotificationPreference,
         perform: @escaping (@escaping NativeChannelNotificationScreenOperation) -> Void) {
        self.model = model; self.preference = preference; self.perform = perform
        _draft = State(initialValue: .init(preference)); _quietEnabled = State(initialValue: preference.quietHours != nil)
        _start = State(initialValue: Self.clock(preference.quietHours?.start ?? "23:00"))
        _end = State(initialValue: Self.clock(preference.quietHours?.end ?? "07:00"))
        _zone = State(initialValue: preference.quietHours?.timeZone ?? TimeZone.current.identifier)
        _preview = State(initialValue: preference.showPreview.map { $0 ? 1 : 0 } ?? -1)
    }
    var body: some View {
        Section {
            Picker(n("editor.level"), selection: $draft.level) {
                ForEach(NativeChannelNotificationLevel.allCases) { Text(NativeChannelNotificationPresentation.level($0, locale: locale)).tag($0) }
            }.accessibilityIdentifier("notification.level")
            Text(NativeChannelNotificationPresentation.effective(preference, locale: locale)).foregroundStyle(Theme.Color.textSecondary(in: domain))
            LabeledContent(n("editor.version"), value: String(preference.version)).font(Theme.Font.label)
        }
        if !preference.scope.isAccountDefault {
          Section(n("editor.mute")) {
            Text(NativeChannelNotificationPresentation.mute(preference, locale: locale))
            if preference.effective.permanentMuted == true && !preference.permanentMuted {
                Text(n("editor.parentPermanent"))
            }
            Button(n("editor.chooseMute")) { muteMenu = true }.disabled(!model.canMute)
                .accessibilityIdentifier("notification.mute.choose")
          }
        }
        Section {
            Toggle(n("editor.quietEnabled"), isOn: $quietEnabled).accessibilityIdentifier("notification.quiet.enabled")
            if quietEnabled {
                DatePicker(n("editor.start"), selection: $start, displayedComponents: .hourAndMinute)
                DatePicker(n("editor.end"), selection: $end, displayedComponents: .hourAndMinute)
                Picker(n("editor.timeZone"), selection: $zone) {
                    ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + [zone])).sorted(), id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("notification.quiet.timezone")
                Text(n("editor.crossMidnight"))
            }
        } header: { Text(n("editor.quietHours")) } footer: { Text(preference.effective.quiet ? n("editor.quietActive") : n("editor.quietBoundary")) }
        Section(n("editor.contents")) {
            if !preference.scope.isAccountDefault {
                Toggle(n("editor.suppressBroadcast"), isOn: $draft.suppressBroadcast)
                Toggle(n("editor.suppressTeamStatus"), isOn: $draft.suppressTeamStatus)
            }
            Picker(n("editor.preview"), selection: $preview) {
                Text(n("editor.inherit")).tag(-1); Text(n("editor.hide")).tag(0); Text(n("editor.show")).tag(1)
            }
            Text(preference.effective.showPreview ? n("editor.previewAllowed") : n("editor.previewHidden")).foregroundStyle(Theme.Color.textSecondary(in: domain))
        }
        .disabled(!model.canSave)
        Section {
            if let localIssue { Text(n(localIssue)).foregroundStyle(Theme.Color.danger(in: domain)) }
            Button(n("editor.save")) { prepareSave() }.nativeChannelPrimaryAction().disabled(!model.canSave)
                .accessibilityIdentifier("notification.save")
        } footer: { Text(n("editor.boundary")) }
        .confirmationDialog(n("editor.confirmSave"), isPresented: $saveConfirmation, titleVisibility: .visible) {
            Button(n("save")) {
                let intent = draft, version = preference.version
                perform { await $0.save(intent, expectedVersion: version) }
            }
            Button(n("cancel"), role: .cancel) { }
        }
        .confirmationDialog(n("editor.muteDuration"), isPresented: $muteMenu, titleVisibility: .visible) {
            Button(n("mute.15m")) { mute(15) }; Button(n("mute.1h")) { mute(60) }; Button(n("mute.8h")) { mute(480) }
            Button(n("mute.24h")) { mute(1440) }; Button(n("mute.30d")) { mute(43200) }
            Button(n("mute.forever")) { mute(-1) }; Button(n("mute.clear")) { mute(0) }
            Button(n("back"), role: .cancel) { }
        }
    }
    private func mute(_ minutes: Int) { perform { await $0.mute(minutes: minutes) } }
    private func prepareSave() {
        do {
            draft.quietHours = quietEnabled ? try .init(start: Self.time(start), end: Self.time(end), timeZone: zone) : nil
            draft.showPreview = preview == -1 ? nil : preview == 1
            _ = try NativeChannelNotificationCommand(preference: preference, draft: draft)
            localIssue = nil; saveConfirmation = true
        } catch { localIssue = "editor.invalid" }
    }
    private static func clock(_ value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: parts[0], minute: parts[1]))!
    }
    private static func time(_ value: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }
}
