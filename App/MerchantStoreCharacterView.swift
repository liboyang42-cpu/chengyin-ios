import SwiftUI

@MainActor final class StoreCharacterModel: ObservableObject {
    let coordinator: StoreCharacterCoordinator
    let reform: StoreCharacterReformContext?
    @Published private(set) var revision = 0
    init(_ coordinator: StoreCharacterCoordinator, reform: StoreCharacterReformContext?) {
        self.coordinator = coordinator; self.reform = reform
        coordinator.onChange = { [weak self] in self?.revision += 1 }
    }
}

/// W04/W05 inputs for the dormant scope section. Supplied only by the offline fixture.
struct StoreCharacterReformContext {
    let projection: StoreCharacterSceneProjection
    let draft: StoreCharacterAIDraftStatus
}

private func t(_ key: LocalizedStringKey) -> Text { Text(key, tableName: "StoreCharacter") }

/// Native `pages/merchant/decor/ai-npc` (AI 店铺角色): home view, avatar view and their sheets.
@MainActor struct MerchantStoreCharacterView: View {
    @StateObject private var model: StoreCharacterModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(coordinator: StoreCharacterCoordinator, reform: StoreCharacterReformContext? = nil) {
        _model = StateObject(wrappedValue: .init(coordinator, reform: reform))
    }
    private var c: StoreCharacterCoordinator { model.coordinator }

    var body: some View {
        content
            .navigationTitle(c.screen == .home ? t("storeCharacter.title.home") : t("storeCharacter.title.avatar"))
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if c.back() == .leave { dismiss() } } label: { t("storeCharacter.action.back") }
                        .disabled(c.saving).accessibilityIdentifier("aiNPC.back")
                }
            }
            .task { await c.load() }
            .task(id: c.shouldPoll) { await poll() }
            .task(id: deniedKey) { await autoExit() }
            .onAppear { c.setPageVisible(scenePhase == .active) }
            .onDisappear { c.setPageVisible(false) }
            .onChange(of: scenePhase) { _, phase in
                c.setPageVisible(phase == .active)
                if phase == .active, c.homeVoiceStatus == .pending { Task { await c.refreshVoice() } }
            }
            .sheet(isPresented: fieldPresented) { StoreCharacterFieldSheet(model: model) }
            .sheet(isPresented: presetsPresented) { StoreCharacterPresetSheet(model: model) }
            .sheet(isPresented: voicePresented) { StoreCharacterVoiceSheet(model: model) }
            .confirmationDialog(Text("storeCharacter.discard.title", tableName: "StoreCharacter"), isPresented: discardPresented, titleVisibility: .visible) {
                Button(role: .destructive) { if c.discardChanges() == .leave { dismiss() } } label: { t("storeCharacter.discard.discard") }
                Button(role: .cancel) { c.keepEditing() } label: { t("storeCharacter.discard.keep") }
            } message: { t("storeCharacter.discard.body") }
            .confirmationDialog(Text("storeCharacter.mapPoint.confirmTitle", tableName: "StoreCharacter"), isPresented: mapPointPresented, titleVisibility: .visible) {
                if let value = c.mapPointConfirmation {
                    Button { Task { await c.confirmMapPoint(value.id) } } label: { t("storeCharacter.action.confirmSave") }
                }
                Button(role: .cancel) { c.cancelMapPoint() } label: { t("storeCharacter.action.cancel") }
            } message: { t("storeCharacter.mapPoint.confirmBody") }
    }

    private var deniedKey: Bool { if case .denied = c.phase { return true }; return false }
    /// Source gate: a zero-button fail sheet that leaves after two seconds.
    private func autoExit() async {
        guard deniedKey else { return }
        try? await Task.sleep(for: .seconds(2))
        if !Task.isCancelled, deniedKey { dismiss() }
    }
    private func poll() async {
        while c.shouldPoll {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, c.shouldPoll else { return }
            await c.refreshVoice()
        }
    }
    private var fieldPresented: Binding<Bool> {
        Binding(get: { c.field != nil && c.discard == nil }, set: { if !$0 { c.closeField() } })
    }
    private var presetsPresented: Binding<Bool> {
        Binding(get: { c.presetPick != nil }, set: { if !$0 { c.closePresets() } })
    }
    private var voicePresented: Binding<Bool> {
        Binding(get: { c.voiceVisible }, set: { if !$0 { c.closeVoice() } })
    }
    private var discardPresented: Binding<Bool> {
        Binding(get: { c.discard != nil }, set: { if !$0, c.discard != nil { c.keepEditing() } })
    }
    private var mapPointPresented: Binding<Bool> {
        // Dismissal goes through the dialog's own buttons; confirm must still find its prepared value.
        Binding(get: { c.mapPointConfirmation != nil }, set: { _ in })
    }

    @ViewBuilder private var content: some View {
        switch c.phase {
        case .checking, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("aiNPC.loading")
        case .login:
            ContentUnavailableView {
                t("storeCharacter.gate.loginTitle")
            } description: { t("storeCharacter.gate.loginReason") }
            .accessibilityIdentifier("aiNPC.gate.login")
        case .denied(let reason):
            ContentUnavailableView {
                t("storeCharacter.gate.deniedTitle")
            } description: { denyText(reason) }
            .accessibilityIdentifier("aiNPC.gate.denied")
        case .failed(let message):
            ContentUnavailableView {
                t("storeCharacter.load.failedTitle")
            } description: {
                if let message { Text(verbatim: message) } else { t("storeCharacter.error.network") }
            } actions: {
                Button { Task { await c.load() } } label: { t("storeCharacter.action.retry") }.accessibilityIdentifier("aiNPC.retry")
            }
            .accessibilityIdentifier("aiNPC.load.failed")
        case .ready:
            List {
                if let notice = c.notice { Section { StoreCharacterNoticeText(notice: notice) } }
                Section { hero }
                if c.screen == .home { homeRows } else { avatarRows }
                if c.showsReformScopes, let reform = model.reform { StoreCharacterReformSection(context: reform) }
            }
            .accessibilityIdentifier("aiNPC.list")
        }
    }

    private func denyText(_ reason: StoreCharacterDenyReason) -> Text {
        switch reason {
        case .notMember: return t("storeCharacter.gate.notMember")
        case .missingPermission: return t("storeCharacter.gate.missingPermission")
        case .noViewPermission: return t("storeCharacter.gate.noViewPermission")
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            StoreCharacterPreview(avatar: c.selection, side: c.screen == .home ? 128 : 192)
            if c.screen == .home {
                if c.home.name.isEmpty { t("storeCharacter.hero.namePlaceholder").font(.title3.bold()).foregroundStyle(.secondary) }
                else { Text(verbatim: c.home.name).font(.title3.bold()).accessibilityIdentifier("aiNPC.hero.name") }
                if let badge = c.saved.badge {
                    badgeText(badge).font(.footnote.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(badgeColor(badge).opacity(0.15), in: Capsule()).foregroundStyle(badgeColor(badge))
                        .accessibilityIdentifier("aiNPC.hero.badge")
                    if let reason = c.saved.rejectionReason {
                        (t("storeCharacter.hero.rejectReason") + Text(verbatim: reason)).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("aiNPC.hero.rejectReason")
                    }
                }
            } else {
                t("storeCharacter.avatar.previewCaption").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
    private func badgeText(_ badge: StoreCharacterBadge) -> Text {
        switch badge {
        case .online: return t("storeCharacter.badge.online")
        case .rejected: return t("storeCharacter.badge.rejected")
        case .reviewing: return t("storeCharacter.badge.reviewing")
        }
    }
    private func badgeColor(_ badge: StoreCharacterBadge) -> Color {
        switch badge { case .online: return .green; case .rejected: return .orange; case .reviewing: return .secondary }
    }

    @ViewBuilder private var homeRows: some View {
        Section {
            StoreCharacterRow(title: t("storeCharacter.row.avatar"), value: t("storeCharacter.row.avatarValue"), id: "aiNPC.row.avatar") { c.openAvatar() }
            StoreCharacterRow(title: t("storeCharacter.row.voice"), value: voiceValue, id: "aiNPC.row.voice") { Task { await c.openVoice() } }
        }
        Section {
            StoreCharacterRow(title: t("storeCharacter.row.name"), required: true, value: fieldValue(.name), id: "aiNPC.row.name") { c.editField(.name) }
            StoreCharacterRow(title: t("storeCharacter.row.greeting"), value: fieldValue(.greeting), id: "aiNPC.row.greeting") { c.editField(.greeting) }
            StoreCharacterRow(title: t("storeCharacter.row.persona"), value: fieldValue(.persona), id: "aiNPC.row.persona") { c.editField(.persona) }
            StoreCharacterRow(title: t("storeCharacter.row.knowledge"), value: fieldValue(.knowledge), id: "aiNPC.row.knowledge") { c.editField(.knowledge) }
            StoreCharacterRow(title: t("storeCharacter.row.mapPoint"), value: mapPointValue, id: "aiNPC.row.mapPoint") { c.chooseStorePoint() }
        }
    }
    private var voiceValue: Text {
        switch c.homeVoiceStatus {
        case .pending?: return t("storeCharacter.voiceValue.pending")
        case .ready?: return t("storeCharacter.voiceValue.ready")
        case .failed?: return t("storeCharacter.voiceValue.failed")
        case .none?: return t("storeCharacter.voiceValue.none")
        case nil: return t("storeCharacter.voiceValue.unknown")
        }
    }
    private func fieldValue(_ field: StoreCharacterField) -> Text {
        let value = c.home[field]
        if !value.isEmpty { return Text(verbatim: value) }
        switch field {
        case .name: return t("storeCharacter.placeholder.name")
        case .greeting: return t("storeCharacter.placeholder.greeting")
        case .persona: return t("storeCharacter.placeholder.persona")
        case .knowledge: return t("storeCharacter.placeholder.knowledge")
        }
    }
    private var mapPointValue: Text {
        if let address = c.mapPoint.displayAddress { return Text(verbatim: address) }
        return c.mapPoint.hasPoint ? t("storeCharacter.mapPoint.selected") : t("storeCharacter.mapPoint.unset")
    }

    @ViewBuilder private var avatarRows: some View {
        Section {
            HStack(spacing: 12) {
                Button { c.choosePhoto() } label: { t("storeCharacter.avatar.uploadPhoto").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).disabled(c.saving).accessibilityIdentifier("aiNPC.avatar.photo")
                Button { c.openPresets() } label: { t("storeCharacter.avatar.presets").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).disabled(c.saving).accessibilityIdentifier("aiNPC.avatar.presets")
            }
        }
        if let issue = c.saveIssue { Section { StoreCharacterSaveIssueView(model: model, issue: issue) } }
        if let confirmation = c.saveConfirmation, confirmation.origin == .avatar {
            StoreCharacterSaveConfirmationSection(model: model, confirmation: confirmation)
        } else {
            Section {
                Button { c.saveAvatar() } label: {
                    HStack {
                        Spacer()
                        if c.saving { ProgressView() }
                        (c.saveIssue == nil ? t("storeCharacter.avatar.save") : t("storeCharacter.avatar.retrySave")).bold()
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent).disabled(c.saving || c.saveLocked).accessibilityIdentifier("aiNPC.avatar.save")
            }
        }
    }
}

private struct StoreCharacterRow: View {
    let title: Text
    var required = false
    let value: Text
    let id: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                title.foregroundStyle(.primary)
                if required { Text(verbatim: "*").foregroundStyle(.red).accessibilityHidden(true) }
                Spacer(minLength: 12)
                value.foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

struct StoreCharacterPreview: View {
    let avatar: StoreCharacterAvatar
    let side: CGFloat
    var body: some View {
        Group {
            if let preset = avatar.preset { MerchantNPCPresetArtwork(avatar: preset) }
            else {
                // The saved photo avatar is a remote image; this build shows a neutral placeholder.
                ZStack {
                    Color.secondary.opacity(0.15)
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.square").font(.largeTitle).accessibilityHidden(true)
                        t("storeCharacter.hero.photoSaved").font(.caption)
                    }.foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aiNPC.preview")
    }
}

struct StoreCharacterNoticeText: View {
    let notice: StoreCharacterCoordinator.Notice
    var body: some View {
        text.font(.subheadline).accessibilityIdentifier("aiNPC.notice")
    }
    private var text: Text {
        switch notice {
        case .saved: return t("storeCharacter.notice.saved")
        case .nameRequired: return t("storeCharacter.notice.nameRequired")
        case .nameFirst: return t("storeCharacter.notice.nameFirst")
        case .saveProfileFirst: return t("storeCharacter.notice.saveProfileFirst")
        case .photoUnavailable: return t("storeCharacter.notice.photoUnavailable")
        case .writesDisabled: return t("storeCharacter.notice.writesDisabled")
        case .mapPointUnavailable: return t("storeCharacter.notice.mapPointUnavailable")
        case .mapPointFailed(let message): return message.map { Text(verbatim: $0) } ?? t("storeCharacter.error.request")
        case .mapPointUnknown: return t("storeCharacter.notice.mapPointUnknown")
        case .readbackConfirmed: return t("storeCharacter.notice.readbackConfirmed")
        case .readbackMismatch: return t("storeCharacter.notice.readbackMismatch")
        }
    }
}

struct StoreCharacterSaveIssueView: View {
    @ObservedObject var model: StoreCharacterModel
    let issue: StoreCharacterCoordinator.SaveIssue
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            t("storeCharacter.issue.title").font(.subheadline.bold())
            switch issue {
            case .rejected(let message):
                if let message { Text(verbatim: message) } else { t("storeCharacter.error.request") }
            case .unknown: t("storeCharacter.issue.unknown")
            case .readbackFailed:
                t("storeCharacter.issue.readbackFailed")
                Button { Task { await model.coordinator.readbackSave() } } label: { t("storeCharacter.action.readback") }
                    .accessibilityIdentifier("aiNPC.save.readback")
            }
        }
        .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("aiNPC.save.issue")
    }
}

struct StoreCharacterSaveConfirmationSection: View {
    @ObservedObject var model: StoreCharacterModel
    let confirmation: StoreCharacterCoordinator.SaveConfirmation
    var body: some View {
        Section {
            line(t("storeCharacter.row.name"), confirmation.payload.name)
            line(t("storeCharacter.row.greeting"), confirmation.payload.greeting)
            line(t("storeCharacter.row.persona"), confirmation.payload.persona)
            line(t("storeCharacter.row.knowledge"), confirmation.payload.knowledge)
            HStack {
                t("storeCharacter.row.avatar")
                Spacer()
                if let avatar = StoreCharacterAvatar(code: confirmation.payload.avatar), let preset = avatar.preset {
                    Text(LocalizedStringKey(preset.titleKey))
                } else { t("storeCharacter.hero.photoSaved") }
            }
            t("storeCharacter.confirm.reviewHint").font(.footnote).foregroundStyle(.secondary)
            Button { Task { await model.coordinator.confirmSave(confirmation.id) } } label: { t("storeCharacter.action.confirmSave").bold() }
                .accessibilityIdentifier("aiNPC.save.confirm")
            Button(role: .cancel) { model.coordinator.cancelSave() } label: { t("storeCharacter.action.cancel") }
                .accessibilityIdentifier("aiNPC.save.cancel")
        } header: { t("storeCharacter.confirm.title") }
    }
    private func line(_ title: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.font(.caption).foregroundStyle(.secondary)
            if value.isEmpty { t("storeCharacter.confirm.empty").foregroundStyle(.secondary) } else { Text(verbatim: value) }
        }
    }
}

private struct StoreCharacterFieldSheet: View {
    @ObservedObject var model: StoreCharacterModel
    private var c: StoreCharacterCoordinator { model.coordinator }
    var body: some View {
        NavigationStack {
            Form {
                if let edit = c.field {
                    Section {
                        TextField(text: Binding(get: { c.field?.value ?? "" }, set: { c.updateField($0) }),
                                  axis: edit.field.multiline ? .vertical : .horizontal) { label(edit.field) }
                            .lineLimit(edit.field.multiline ? 6...14 : 1...1)
                            .disabled(c.saving).accessibilityIdentifier("aiNPC.field.input")
                        HStack { Spacer(); Text(verbatim: edit.counter).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("aiNPC.field.counter") }
                    }
                    if let notice = c.notice { Section { StoreCharacterNoticeText(notice: notice) } }
                    if let issue = c.saveIssue { Section { StoreCharacterSaveIssueView(model: model, issue: issue) } }
                    if let confirmation = c.saveConfirmation, case .field = confirmation.origin {
                        StoreCharacterSaveConfirmationSection(model: model, confirmation: confirmation)
                    } else {
                        Section {
                            Button { c.saveField() } label: {
                                HStack { Spacer(); if c.saving { ProgressView() }; t("storeCharacter.action.save").bold(); Spacer() }
                            }
                            .disabled(c.saving || c.saveLocked).accessibilityIdentifier("aiNPC.field.save")
                        }
                    }
                }
            }
            .navigationTitle(c.field.map { label($0.field) } ?? Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { c.closeField() } label: { t("storeCharacter.action.close") }.disabled(c.saving).accessibilityIdentifier("aiNPC.field.close")
                }
            }
        }
        .interactiveDismissDisabled(c.saving || c.field.map { $0.value != $0.initial } == true)
        .presentationDetents(c.field?.field.multiline == true ? Set<PresentationDetent>([.large]) : Set<PresentationDetent>([.medium]))
    }
    private func label(_ field: StoreCharacterField) -> Text {
        switch field {
        case .name: return t("storeCharacter.field.name")
        case .greeting: return t("storeCharacter.field.greeting")
        case .persona: return t("storeCharacter.field.persona")
        case .knowledge: return t("storeCharacter.field.knowledge")
        }
    }
}

private struct StoreCharacterPresetSheet: View {
    @ObservedObject var model: StoreCharacterModel
    private var c: StoreCharacterCoordinator { model.coordinator }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(MerchantNPCPresetAvatar.all) { preset in
                        Button { c.pickPreset(preset.id) } label: {
                            VStack(spacing: 6) {
                                MerchantNPCPresetArtwork(avatar: preset).frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.presetPick == preset.id ? Color.accentColor : .clear, lineWidth: 3))
                                Text(LocalizedStringKey(preset.titleKey)).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(c.presetPick == preset.id ? [.isSelected] : [])
                        .accessibilityIdentifier("aiNPC.preset." + preset.id)
                    }
                }
                .padding()
                Button { c.confirmPreset() } label: { t("storeCharacter.preset.use").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).padding(.horizontal).accessibilityIdentifier("aiNPC.preset.use")
            }
            .navigationTitle(t("storeCharacter.preset.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { c.closePresets() } label: { t("storeCharacter.action.close") } }
            }
        }
    }
}

private struct StoreCharacterVoiceSheet: View {
    @ObservedObject var model: StoreCharacterModel
    private var c: StoreCharacterCoordinator { model.coordinator }
    private var status: StoreCharacterVoiceState.Status { c.voice?.status ?? .none }
    var body: some View {
        NavigationStack {
            List {
                Section { t("storeCharacter.voice.heading").font(.headline) }
                if status != .pending {
                    Section {
                        Toggle(isOn: Binding(get: { c.voiceConsent }, set: { c.setVoiceConsent($0) })) { t("storeCharacter.voice.consent").font(.footnote) }
                            .accessibilityIdentifier("aiNPC.voice.consent")
                    }
                }
                switch status {
                case .pending:
                    Section {
                        ProgressView()
                        t("storeCharacter.voice.pendingBody")
                        Button { Task { await c.refreshVoice() } } label: { t("storeCharacter.voice.refresh") }.accessibilityIdentifier("aiNPC.voice.refresh")
                    }
                case .ready:
                    Section {
                        t("storeCharacter.voice.readyBody").accessibilityIdentifier("aiNPC.voice.ready")
                        if c.voice?.sample != nil {
                            Button {} label: { t("storeCharacter.voice.playOriginal") }.disabled(true)
                            t("storeCharacter.voice.playbackUnavailable").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button { c.resetRecording() } label: { t("storeCharacter.voice.rerecord") }.accessibilityIdentifier("aiNPC.voice.rerecord")
                    }
                case .none, .failed:
                    if status == .failed { Section { t("storeCharacter.voice.failedBody").foregroundStyle(.red) } }
                    if let recording = c.recording { recorded(recording) } else { voiceMode }
                }
                if let confirmation = c.voiceConfirmation { consentDialog(confirmation) }
                if let issue = c.voiceIssue {
                    Section {
                        VStack(alignment: .leading, spacing: 4) { t("storeCharacter.issue.title").bold(); issueText(issue) }
                            .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("aiNPC.voice.issue")
                    }
                }
                if c.voiceUnknown {
                    Section {
                        Button { Task { await c.refreshVoice() } } label: { t("storeCharacter.voice.queryStatus") }.accessibilityIdentifier("aiNPC.voice.query")
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { c.closeVoice() } label: { t("storeCharacter.action.close") }.disabled(c.voiceBusy).accessibilityIdentifier("aiNPC.voice.close")
                }
            }
        }
        .interactiveDismissDisabled(c.voiceBusy)
    }
    private var title: Text {
        if c.recording != nil { return t("storeCharacter.voice.titleConfirm") }
        switch status {
        case .pending: return t("storeCharacter.voiceValue.pending")
        case .ready: return t("storeCharacter.voiceValue.ready")
        default: return t("storeCharacter.voice.titleRecord")
        }
    }
    @ViewBuilder private var voiceMode: some View {
        Section {
            t("storeCharacter.voice.mode").font(.headline)
            HStack(spacing: 6) {
                ForEach(0..<StoreCharacterVoiceScript.sentenceCount, id: \.self) { index in
                    Capsule().fill(index == 0 ? Color.accentColor : Color.secondary.opacity(0.3)).frame(height: 4)
                }
            }
            .accessibilityElement().accessibilityLabel(t("storeCharacter.voice.progress"))
            t("storeCharacter.voice.sentence1")
            Button {} label: { t("storeCharacter.voice.hold").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).disabled(true).accessibilityIdentifier("aiNPC.voice.hold")
            t("storeCharacter.voice.recordingUnavailable").font(.footnote).foregroundStyle(.secondary)
            if c.canRecord {
                Button { c.useSyntheticRecording() } label: { t("storeCharacter.voice.useSample") }
                    .disabled(c.voiceBusy || c.voiceUnknown).accessibilityIdentifier("aiNPC.voice.useSample")
            }
        }
    }
    @ViewBuilder private func recorded(_ recording: StoreCharacterRecordedSample) -> some View {
        Section {
            t("storeCharacter.voice.recordedTitle").font(.headline).accessibilityIdentifier("aiNPC.voice.recorded")
            (Text(verbatim: String(recording.durationSeconds)) + t("storeCharacter.voice.recordedHint")).font(.footnote).foregroundStyle(.secondary)
            Button {} label: { t("storeCharacter.voice.play") }.disabled(true)
            Button { c.resetRecording() } label: { t("storeCharacter.voice.rerecord") }
                .disabled(c.voiceBusy || c.voiceUnknown).accessibilityIdentifier("aiNPC.voice.reset")
            Button { c.prepareEnroll() } label: {
                HStack { if c.voiceBusy { ProgressView() }; t("storeCharacter.voice.enroll").bold() }
            }
            .disabled(c.voiceBusy || c.voiceUnknown || !c.voiceConsent).accessibilityIdentifier("aiNPC.voice.enroll")
        }
    }
    @ViewBuilder private func consentDialog(_ confirmation: StoreCharacterCoordinator.VoiceConfirmation) -> some View {
        Section {
            t("storeCharacter.consent.body").font(.footnote)
            Button { Task { await c.agreeAndEnroll(confirmation.id) } } label: { t("storeCharacter.consent.agree").bold() }
                .accessibilityIdentifier("aiNPC.consent.agree")
            Button(role: .cancel) { c.declineVoiceConsent() } label: { t("storeCharacter.consent.decline") }
                .accessibilityIdentifier("aiNPC.consent.decline")
        } header: { t("storeCharacter.consent.title") }
    }
    private func issueText(_ issue: StoreCharacterCoordinator.VoiceIssue) -> Text {
        switch issue {
        case .server(let message): return message.map { Text(verbatim: $0) } ?? t("storeCharacter.error.request")
        case .statusUnconfirmed: return t("storeCharacter.voiceIssue.statusUnconfirmed")
        case .consentRequired: return t("storeCharacter.voiceIssue.consentRequired")
        case .consentDeclined: return t("storeCharacter.voiceIssue.consentDeclined")
        case .consentFailed: return t("storeCharacter.voiceIssue.consentFailed")
        case .enrollUnknown: return t("storeCharacter.voiceIssue.enrollUnknown")
        case .writesDisabled: return t("storeCharacter.voiceIssue.writesDisabled")
        }
    }
}

/// Reform plan v9 W04/W05, dormant: rendered only when a gate is on (offline fixture only).
private struct StoreCharacterReformSection: View {
    let context: StoreCharacterReformContext
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                t("storeCharacter.reform.storePublic").bold()
                if let key = context.projection.storePublicKey { Text(verbatim: key).font(.caption.monospaced()).textSelection(.enabled) }
                modeText(context.projection.storeMode).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("aiNPC.reform.storePublic")
            VStack(alignment: .leading, spacing: 4) {
                t("storeCharacter.reform.themeBinding").bold()
                switch context.projection.themeBinding {
                case .notBound: t("storeCharacter.reform.themeNotBound")
                case .bound(let key): Text(verbatim: key).font(.caption.monospaced()).textSelection(.enabled)
                case .hintMismatch: t("storeCharacter.reform.themeMismatch")
                }
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("aiNPC.reform.theme")
            if !context.projection.sharesIsolation { t("storeCharacter.reform.separate").font(.footnote) }
            if !context.projection.knowledgeReachesTheme {
                t("storeCharacter.reform.knowledgeIsolation").font(.footnote).accessibilityIdentifier("aiNPC.reform.knowledge")
            }
        } header: { t("storeCharacter.reform.scopesHeader") }
        Section {
            LabeledContent { Text(verbatim: context.draft.stage.rawValue) } label: { t("storeCharacter.reform.draftStage") }
            ForEach(context.draft.blockers, id: \.self) { blocker in
                blockerText(blocker).font(.footnote).accessibilityIdentifier("aiNPC.reform.blocker." + blocker.rawValue)
            }
            t("storeCharacter.reform.noGeneration").font(.footnote).foregroundStyle(.secondary)
        } header: { t("storeCharacter.reform.draftHeader") }
    }
    private func modeText(_ mode: SceneAIAvailability.Mode) -> Text {
        switch mode {
        case .generative: return t("storeCharacter.reform.generative")
        case .nonGenerative: return t("storeCharacter.reform.nonGenerative")
        }
    }
    private func blockerText(_ blocker: MerchantPublishBlocker) -> Text {
        switch blocker {
        case .notApproved: return t("storeCharacter.blocker.notApproved")
        case .missingMerchantFacts: return t("storeCharacter.blocker.missingMerchantFacts")
        case .missingThemeApproval: return t("storeCharacter.blocker.missingThemeApproval")
        case .wrongAuthority: return t("storeCharacter.blocker.wrongAuthority")
        case .selfApproval: return t("storeCharacter.blocker.selfApproval")
        case .editedAfterReview: return t("storeCharacter.blocker.editedAfterReview")
        case .capabilityDisabled: return t("storeCharacter.blocker.capabilityDisabled")
        }
    }
}
