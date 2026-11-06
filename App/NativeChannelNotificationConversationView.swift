import SwiftUI

/// Screen ownership only; the original coordinator still owns grants, journal and writer.
typealias NativeChannelNotificationScreenOperation = @MainActor (NativeChannelNotificationCoordinator) async -> Void

@MainActor struct NativeChannelNotificationConversationView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    private func c(_ key: String) -> String { NativeChannelNotificationCopy.text(key, locale: locale) }
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
            } else if model.isBusy { ProgressView().accessibilityLabel(c("state.loading")) }
            Section {
                NativeChannelNotificationPermissionRow(permission: permission)
            }
        }
        .formStyle(.grouped)
        .nativeChannelScreen()
        .navigationTitle(model.scope?.isAccountDefault == true ? c("accountDefault.title")
            : NativeChannelNotificationPresentation.localized("notification.channel.title", locale: locale))
        .accessibilityIdentifier("notification.conversation.screen")
        .refreshable { await pullToRefresh(expected: ticket) }
        .onAppear { visible = true; reopen() }
        .onDisappear { visible = false; suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reopen() } else { suspend() }
        }
        .tint(Theme.Color.accent(in: domain))
    }
    private func pullToRefresh(expected: UInt64) async {
        guard !model.isBusy else { return }
        perform({ await $0.refresh() }, expected: expected)
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
    @Environment(\.locale) private var locale
    private func c(_ key: String) -> String { NativeChannelNotificationCopy.text(key, locale: locale) }
    @Bindable var model: NativeChannelNotificationCoordinator
    /// Optional to preserve existing message/ACK consumers; settings supply their visible owner.
    var perform: ((@escaping NativeChannelNotificationScreenOperation) -> Void)? = nil
    @State private var retryConfirmation = false
    var body: some View {
        Section {
            if !model.isCurrent && !model.isBusy {
                Text(c("state.accessClosed"))
            } else if let text = NativeChannelNotificationCopy.state(model.state, locale: locale) {
                Text(text).nativeChannelNotice(systemImage: "bell").accessibilityIdentifier("notification.request.status")
            }
            if model.directory == nil && !model.isBusy && model.state == .ready { Text(c("empty")) }
            if model.pendingRequestID != nil {
                Button(c("recovery.check")) { run { await $0.checkReceipt() } }
                    .disabled(!model.canCheckReceipt).accessibilityIdentifier("notification.receipt.check")
                Button(c("recovery.retry")) { retryConfirmation = true }.disabled(!model.canCheckReceipt)
                    .accessibilityIdentifier("notification.receipt.retry")
            }
            if let detail = NativeChannelNotificationCopy.failureDetail(model.lastFailure, state: model.state, locale: locale) {
                Text(detail).foregroundStyle(.secondary)
                    .accessibilityIdentifier("notification.request.explanation")
            }
            if model.unreadIssue { Text(c("unreadIssue")) }
        }
        .confirmationDialog(c("recovery.confirm"), isPresented: $retryConfirmation, titleVisibility: .visible) {
            Button(c("recovery.checkAndRetry")) { run { await $0.retryOriginal() } }
            Button(c("cancel"), role: .cancel) { }
        }
        .onDisappear { retryConfirmation = false }
        .onChange(of: model.isCurrent) { _, current in if !current { retryConfirmation = false } }
    }
    private func run(_ operation: @escaping NativeChannelNotificationScreenOperation) {
        if let perform { perform(operation) }
        else { Task { await operation(model) } }
    }
}

/// System permission row shared by the global and per-channel settings screens.
@MainActor struct NativeChannelNotificationPermissionRow: View {
    @Environment(\.locale) private var locale
    let permission: NativeNotificationPermissionState
    var body: some View {
        NavigationLink { NativeNotificationPermissionNudgeView(model: permission) } label: {
            LabeledContent {
                Text(permission.snapshot.map { NativeChannelNotificationCopy.authorization($0.authorization, locale: locale) } ?? "—")
            } label: {
                Label(NativeChannelNotificationCopy.text("permission.title", locale: locale), systemImage: "bell.badge")
            }
        }
    }
}

/// Player-facing copy for the notification screens. Keys live in the
/// NativeChannelNotification table under `d7.channelNotify.`; presentation only.
enum NativeChannelNotificationCopy {
    static func text(_ key: String, locale: Locale) -> String {
        NativeChannelNotificationPresentation.localized("d7.channelNotify." + key, locale: locale)
    }
    static func format(_ key: String, locale: Locale, _ value: String) -> String {
        NativeChannelNotificationPresentation.format("d7.channelNotify." + key, locale: locale, value)
    }
    /// Re-points an existing Core presentation key (`notification.x.y`) at its player copy.
    private static func remapped(_ key: String, locale: Locale) -> String {
        let prefix = "notification."
        return text(key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key, locale: locale)
    }
    static func level(_ value: NativeChannelNotificationLevel, locale: Locale) -> String {
        remapped(NativeChannelNotificationPresentation.levelKey(value), locale: locale)
    }
    static func state(_ state: NativeChannelNotificationState, locale: Locale) -> String? {
        NativeChannelNotificationPresentation.stateKey(state).map { remapped($0, locale: locale) }
    }
    static func failureDetail(_ failure: NativeChannelNotificationError?, state: NativeChannelNotificationState, locale: Locale) -> String? {
        NativeChannelNotificationPresentation.failureDetailKey(failure, state: state).map { remapped($0, locale: locale) }
    }
    static func mute(_ preference: NativeChannelNotificationPreference, locale: Locale) -> String {
        if preference.permanentMuted { return text("mute.permanent", locale: locale) }
        if let until = preference.mutedUntil, let date = NativeChannelNotificationCommand.instant(until) {
            return format("mute.until", locale: locale, date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
        }
        if preference.effective.muted { return text("mute.inherited", locale: locale) }
        return text("mute.none", locale: locale)
    }
    static func authorization(_ value: NativeNotificationPermissionAuthorization, locale: Locale) -> String {
        switch value {
        case .notDetermined: return text("permission.notDetermined", locale: locale)
        case .denied: return text("permission.denied", locale: locale)
        case .authorized: return text("permission.authorized", locale: locale)
        case .provisional: return text("permission.provisional", locale: locale)
        case .ephemeral: return text("permission.ephemeral", locale: locale)
        case .unknown: return "—"
        }
    }
}

@MainActor private struct NativeChannelNotificationEditor: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    private func c(_ key: String) -> String { NativeChannelNotificationCopy.text(key, locale: locale) }
    let model: NativeChannelNotificationCoordinator
    let preference: NativeChannelNotificationPreference
    let perform: (@escaping NativeChannelNotificationScreenOperation) -> Void
    @State private var draft: NativeChannelNotificationDraft
    @State private var quietEnabled: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var zone: String
    @State private var preview: Int
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
            Picker(c("editor.level"), selection: $draft.level) {
                ForEach(NativeChannelNotificationLevel.allCases) { Text(NativeChannelNotificationCopy.level($0, locale: locale)).tag($0) }
            }
            .pickerStyle(.inline).labelsHidden()
            .accessibilityIdentifier("notification.level")
            if preference.level == .inherit {
                LabeledContent(c("editor.effective"), value: NativeChannelNotificationCopy.level(preference.effective.level, locale: locale))
            }
        } header: { Text(c("editor.level")) }
        if !preference.scope.isAccountDefault {
            Section {
                Menu {
                    Button(c("mute.15m")) { mute(15) }; Button(c("mute.1h")) { mute(60) }; Button(c("mute.8h")) { mute(480) }
                    Button(c("mute.24h")) { mute(1440) }; Button(c("mute.30d")) { mute(43200) }
                    Button(c("mute.forever")) { mute(-1) }
                    Divider()
                    Button(c("mute.clear"), role: .destructive) { mute(0) }
                } label: {
                    LabeledContent {
                        Text(NativeChannelNotificationCopy.mute(preference, locale: locale))
                    } label: { Text(c("editor.mute")).foregroundStyle(.primary) }
                }
                .disabled(!model.canMute)
                .accessibilityIdentifier("notification.mute.choose")
                if preference.effective.permanentMuted == true && !preference.permanentMuted {
                    Text(c("editor.parentPermanent")).foregroundStyle(.secondary)
                }
            }
        }
        Section {
            Toggle(c("editor.quietEnabled"), isOn: $quietEnabled).accessibilityIdentifier("notification.quiet.enabled")
            if quietEnabled {
                DatePicker(c("editor.start"), selection: $start, displayedComponents: .hourAndMinute)
                DatePicker(c("editor.end"), selection: $end, displayedComponents: .hourAndMinute)
                Picker(c("editor.timeZone"), selection: $zone) {
                    ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + [zone])).sorted(), id: \.self) { Text(verbatim: $0).tag($0) }
                }.accessibilityIdentifier("notification.quiet.timezone")
            }
        }
        Section(c("editor.contents")) {
            if !preference.scope.isAccountDefault {
                Toggle(c("editor.suppressBroadcast"), isOn: $draft.suppressBroadcast)
                Toggle(c("editor.suppressTeamStatus"), isOn: $draft.suppressTeamStatus)
            }
            Picker(c("editor.preview"), selection: $preview) {
                Text(c("editor.previewDefault")).tag(-1); Text(c("editor.previewNever")).tag(0); Text(c("editor.previewAlways")).tag(1)
            }
        }
        .disabled(!model.canSave)
        Section {
            if let localIssue { Text(c(localIssue)).foregroundStyle(Theme.Color.danger(in: domain)) }
            Button(c("editor.save")) { prepareSave() }.nativeChannelPrimaryAction().disabled(!model.canSave)
                .accessibilityIdentifier("notification.save")
        }
        .confirmationDialog(c("editor.confirmSave"), isPresented: $saveConfirmation, titleVisibility: .visible) {
            Button(c("save")) {
                let intent = draft, version = preference.version
                perform { await $0.save(intent, expectedVersion: version) }
            }
            Button(c("cancel"), role: .cancel) { }
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
