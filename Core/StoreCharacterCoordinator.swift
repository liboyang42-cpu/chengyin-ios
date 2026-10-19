import Foundation

/// Page state for `pages/merchant/decor/ai-npc`. Every completion is dropped when the reader
/// scope changed (logout/account switch) or the page was invalidated.
@MainActor public final class StoreCharacterCoordinator {
    public enum Phase: Equatable {
        case checking, login, loading, ready
        case denied(StoreCharacterDenyReason)
        case failed(message: String?)
    }
    public enum Screen: Equatable { case home, avatar }
    public enum Notice: Equatable {
        case saved, nameRequired, nameFirst, saveProfileFirst, photoUnavailable, writesDisabled
        case mapPointUnavailable, mapPointFailed(String?), mapPointUnknown, readbackConfirmed, readbackMismatch
    }
    public enum SaveOrigin: Equatable { case field(StoreCharacterField), avatar }
    public struct SaveConfirmation: Equatable, Identifiable {
        public let id: UUID
        public let payload: StoreCharacterSavePayload
        public let origin: SaveOrigin
    }
    public enum SaveIssue: Equatable { case rejected(String?), unknown, readbackFailed }
    public struct FieldEdit: Equatable {
        public let field: StoreCharacterField
        public let initial: String
        public var value: String
        public var counter: String { "\(StoreCharacterText.length(value))/\(field.limit)" }
    }
    public enum Discard: Equatable { case page, field, avatar }
    public enum BackResult: Equatable { case stay, leave }
    public enum VoiceIssue: Equatable {
        case server(String?), statusUnconfirmed, consentRequired, consentDeclined, consentFailed, enrollUnknown, writesDisabled
    }
    public struct VoiceConfirmation: Equatable, Identifiable {
        public let id: UUID
        public let sample: StoreCharacterRecordedSample
        public let consent: StoreCharacterVoiceConsentRecord
    }
    public struct MapPointConfirmation: Equatable, Identifiable {
        public let id: UUID
        public let point: StoreCharacterMapPointWrite
    }

    public let reader: any StoreCharacterReading
    private let writer: (any StoreCharacterWriting)?
    public let gates: MerchantCityNPCParityGates
    private let syntheticRecording: StoreCharacterRecordedSample?
    private let syntheticPoint: StoreCharacterMapPointWrite?
    public var onChange: (() -> Void)?

    public private(set) var phase: Phase = .checking
    public private(set) var screen: Screen = .home
    public private(set) var saved = StoreCharacterProfile.empty
    public private(set) var home = StoreCharacterProfile.empty
    public private(set) var selection: StoreCharacterAvatar = .preset(StoreCharacterAvatar.defaultPresetID)
    private var avatarBaseline = "px1:" + StoreCharacterAvatar.defaultPresetID
    public private(set) var presetPick: String?
    public private(set) var field: FieldEdit?
    public private(set) var discard: Discard?
    public private(set) var notice: Notice?
    public private(set) var saveConfirmation: SaveConfirmation?
    private var prepared: SaveConfirmation?
    public private(set) var saveIssue: SaveIssue?
    public private(set) var saving = false
    public private(set) var saveLocked = false
    private var unresolved: SaveConfirmation?
    public private(set) var mapPoint = StoreCharacterMapPointState.unset
    public private(set) var mapPointConfirmation: MapPointConfirmation?
    public private(set) var voiceVisible = false
    public private(set) var voice: StoreCharacterVoiceState?
    public private(set) var voiceIssue: VoiceIssue?
    public private(set) var voiceBusy = false
    public private(set) var voiceUnknown = false
    public private(set) var voiceConsent = false
    public private(set) var recording: StoreCharacterRecordedSample?
    public private(set) var voiceConfirmation: VoiceConfirmation?
    private var preparedVoice: VoiceConfirmation?
    private var pageVisible = false
    private var active = true
    private var generation = 0

    public init(reader: any StoreCharacterReading, writer: (any StoreCharacterWriting)? = nil, gates: MerchantCityNPCParityGates = .disabled,
                syntheticRecording: StoreCharacterRecordedSample? = nil, syntheticPoint: StoreCharacterMapPointWrite? = nil) {
        self.reader = reader; self.writer = writer; self.gates = gates
        self.syntheticRecording = syntheticRecording; self.syntheticPoint = syntheticPoint
    }

    public var canSave: Bool { writer != nil && gates.storeCharacterSaves }
    public var canEnroll: Bool { writer != nil && gates.storeVoiceEnrollment }
    public var showsReformScopes: Bool { gates.themeNPCBinding || gates.merchantAIDrafts }
    public var canRecord: Bool { syntheticRecording != nil }
    public var avatarDirty: Bool { selection.code != avatarBaseline }
    public var homeVoiceStatus: StoreCharacterVoiceState.Status? {
        if let voice { return voice.status }
        return saved.voiceStatus.flatMap(StoreCharacterVoiceState.Status.init(rawValue:))
    }
    public var shouldPoll: Bool { active && pageVisible && voice?.status == .pending }

    private func changed() { onChange?() }
    private func current(_ stamp: Int, _ scope: UUID) -> Bool { active && stamp == generation && reader.scope == scope }
    private func message(_ error: Error) -> String? {
        if case .rejected(_, let message)? = error as? StoreCharacterFailure { return message }
        return nil
    }

    // MARK: Load
    public func load() async {
        generation += 1; let stamp = generation, scope = reader.scope
        phase = .checking; changed()
        guard reader.isAuthenticated else { phase = .login; changed(); return }
        let decision: StoreCharacterAccessDecision
        do { decision = StoreCharacterAccessDecision.decide(try await reader.access()) }
        catch { decision = StoreCharacterAccessDecision.decide(error: error) }
        guard current(stamp, scope) else { return }
        switch decision {
        case .login: phase = .login; changed(); return
        case .deny(let reason): phase = .denied(reason); changed(); return
        case .allow, .unknown: break   // unknown is not a lock: the server still enforces every route
        }
        phase = .loading; changed()
        do {
            let profile = try await reader.profile()
            guard current(stamp, scope) else { return }
            saved = profile; home = profile; restoreAvatar(); phase = .ready; changed()
        } catch {
            guard current(stamp, scope) else { return }
            if StoreCharacterAccessDecision.decide(error: error) == .login { phase = .login }
            else { phase = .failed(message: message(error)) }
            changed(); return
        }
        await loadMapPoint()
        await refreshVoice()
    }
    public func invalidate() {
        active = false; generation += 1; saveConfirmation = nil; voiceConfirmation = nil; mapPointConfirmation = nil
        field = nil; discard = nil; changed()
    }
    public func setPageVisible(_ visible: Bool) { pageVisible = visible; changed() }
    public func clearNotice() { notice = nil; changed() }

    // MARK: Avatar view
    private func restoreAvatar() {
        selection = StoreCharacterAvatar(code: saved.avatar) ?? .preset(StoreCharacterAvatar.defaultPresetID)
        // An empty profile previews the first preset; opening and leaving is not a change.
        avatarBaseline = saved.avatar.isEmpty ? "px1:" + StoreCharacterAvatar.defaultPresetID : saved.avatar
    }
    public func openAvatar() {
        guard !saving else { return }
        screen = .avatar; saveIssue = nil; restoreAvatar(); changed()
    }
    public func openPresets() {
        guard !saving else { return }
        presetPick = selection.preset?.id ?? StoreCharacterAvatar.defaultPresetID; changed()
    }
    public func pickPreset(_ id: String) {
        guard StoreCharacterAvatar.presetIDs.contains(id) else { return }
        presetPick = id; changed()
    }
    public func closePresets() { presetPick = nil; changed() }
    public func confirmPreset() {
        guard let id = presetPick else { return }
        selection = .preset(id); presetPick = nil; changed()
    }
    /// The source crops and pixelates a photo on-device before upload. Not executed in this build.
    public func choosePhoto() { guard !saving else { return }; notice = .photoUnavailable; changed() }
    public func saveAvatar() {
        guard !saving, !saveLocked else { return }
        guard !StoreCharacterText.trim(home.name).isEmpty else { editField(.name); return }
        prepareSave(home.payload(avatar: selection.code), origin: .avatar)
    }

    // MARK: Fields
    public func editField(_ value: StoreCharacterField) {
        field = FieldEdit(field: value, initial: home[value], value: home[value]); saveIssue = nil; changed()
    }
    public func updateField(_ text: String) {
        guard !saving, var edit = field else { return }
        edit.value = StoreCharacterText.clamp(text, limit: edit.field.limit); field = edit; changed()
    }
    public func closeField() {
        guard !saving, let edit = field else { return }
        if edit.value != edit.initial { discard = .field } else { field = nil }
        changed()
    }
    public func saveField() {
        guard !saving, !saveLocked, let edit = field else { return }
        let value = StoreCharacterText.trim(edit.value)
        if edit.field == .name && value.isEmpty { notice = .nameRequired; changed(); return }
        if !saved.hasProfile {
            // First save creates the profile, so it carries the previewed avatar (server requires one).
            home[edit.field] = value
            if edit.field != .name && StoreCharacterText.trim(home.name).isEmpty {
                notice = .nameFirst; editField(.name); return
            }
            prepareSave(home.payload(avatar: selection.code), origin: .field(edit.field)); return
        }
        var next = saved
        next[edit.field] = value
        prepareSave(next.payload(avatar: saved.avatar), origin: .field(edit.field))
    }

    // MARK: Save (explicit confirmation, one request ID per prepared payload, unknown -> readback)
    private func prepareSave(_ payload: StoreCharacterSavePayload, origin: SaveOrigin) {
        guard canSave else { notice = .writesDisabled; changed(); return }
        guard payload.blocker == nil else { notice = .nameRequired; changed(); return }
        let id = prepared?.payload == payload ? prepared?.id ?? UUID() : UUID()
        let value = SaveConfirmation(id: id, payload: payload, origin: origin)
        prepared = value; saveConfirmation = value; saveIssue = nil; changed()
    }
    public func cancelSave() { saveConfirmation = nil; changed() }
    public func confirmSave(_ id: UUID) async {
        guard let value = saveConfirmation, value.id == id, !saving, !saveLocked, let writer, canSave else { return }
        generation += 1; let stamp = generation, scope = reader.scope
        saveConfirmation = nil; saving = true; changed()
        do {
            try await writer.save(value.payload, requestID: value.id)
            guard current(stamp, scope) else { return }
            saving = false; prepared = nil
            saved = .acknowledged(value.payload, voiceStatus: saved.voiceStatus); home = saved
            finish(value.origin); notice = .saved; changed()
        } catch {
            guard current(stamp, scope) else { return }
            saving = false
            switch error as? StoreCharacterFailure {
            case .rejected(_, let message)?: saveIssue = .rejected(message)
            case .writesDisabled?: notice = .writesDisabled
            case .unauthorized?: phase = .login
            case .accessDenied?: phase = .denied(.noViewPermission)
            default:
                saveLocked = true; unresolved = value; saveIssue = .unknown; changed()
                await readbackSave(); return
            }
            changed()
        }
    }
    private func finish(_ origin: SaveOrigin) {
        field = nil
        if origin == .avatar { screen = .home }
        restoreAvatar()
    }
    /// Authoritative profile read after an uncertain save. Never re-sends the payload.
    public func readbackSave() async {
        guard saveLocked, let value = unresolved else { return }
        generation += 1; let stamp = generation, scope = reader.scope
        saving = true; changed()
        do {
            let profile = try await reader.profile()
            guard current(stamp, scope) else { return }
            saving = false; saveLocked = false; unresolved = nil; prepared = nil
            saved = profile; home = profile
            if value.payload.matches(profile) { finish(value.origin); notice = .readbackConfirmed; saveIssue = nil }
            else { restoreAvatar(); notice = .readbackMismatch; saveIssue = nil }
        } catch {
            guard current(stamp, scope) else { return }
            saving = false; saveIssue = .readbackFailed
        }
        changed()
    }

    // MARK: Navigation
    public func back() -> BackResult {
        guard !saving else { return .stay }
        if screen == .avatar {
            if avatarDirty { discard = .avatar; changed(); return .stay }
            screen = .home; restoreAvatar(); changed(); return .stay
        }
        if !home.sameText(saved) { discard = .page; changed(); return .stay }
        return .leave
    }
    public func keepEditing() { discard = nil; changed() }
    public func discardChanges() -> BackResult {
        let kind = discard; discard = nil
        switch kind {
        case .page?: home = saved; changed(); return .leave
        case .field?: field = nil
        case .avatar?: screen = .home; restoreAvatar()
        case nil: break
        }
        changed(); return .stay
    }

    // MARK: Map point
    public func loadMapPoint() async {
        let stamp = generation, scope = reader.scope
        let value = (try? await reader.mapPoint()) ?? .unset
        guard current(stamp, scope) else { return }
        mapPoint = value; changed()
    }
    /// The source opens `wx.chooseLocation`. No location picker runs here; only a fixture point.
    public func chooseStorePoint() {
        guard !saving else { return }
        guard let point = syntheticPoint, canSave else { notice = .mapPointUnavailable; changed(); return }
        let id = mapPointConfirmation?.point == point ? mapPointConfirmation?.id ?? UUID() : UUID()
        mapPointConfirmation = .init(id: id, point: point); changed()
    }
    public func cancelMapPoint() { mapPointConfirmation = nil; changed() }
    public func confirmMapPoint(_ id: UUID) async {
        guard let value = mapPointConfirmation, value.id == id, let writer, !saving else { return }
        let stamp = generation, scope = reader.scope
        mapPointConfirmation = nil; saving = true; changed()
        do {
            try await writer.saveMapPoint(value.point, requestID: value.id)
            guard current(stamp, scope) else { return }
            saving = false
        } catch {
            guard current(stamp, scope) else { return }
            saving = false
            if case .rejected(_, let message)? = error as? StoreCharacterFailure { notice = .mapPointFailed(message) }
            else { notice = .mapPointUnknown }
        }
        // Readback: the display shows the point the server actually stored.
        await loadMapPoint()
    }

    // MARK: Voice
    public func openVoice() async {
        guard saved.hasProfile else { notice = .saveProfileFirst; changed(); return }
        voiceVisible = true; voiceIssue = nil; changed()
        await refreshVoice()
    }
    public func closeVoice() {
        guard !voiceBusy else { return }
        voiceVisible = false; changed()
    }
    public func refreshVoice() async {
        let stamp = generation, scope = reader.scope
        do {
            let value = try await reader.voiceStatus()
            guard current(stamp, scope) else { return }
            voice = value; voiceUnknown = false
            if value.status == .pending || value.status == .ready, let recording, recording.url == value.sample { self.recording = nil }
        } catch {
            guard current(stamp, scope) else { return }
            if case .rejected(_, let message)? = error as? StoreCharacterFailure { voiceIssue = .server(message) }
            else { voiceIssue = .statusUnconfirmed }
        }
        changed()
    }
    public func setVoiceConsent(_ value: Bool) { voiceConsent = value; voiceIssue = nil; changed() }
    /// Recording is not executed (no microphone access). The fixture hands in an uploaded sample.
    public func useSyntheticRecording() {
        guard let syntheticRecording, !voiceBusy, voice?.status != .pending, !voiceUnknown else { return }
        guard voiceConsent else { voiceIssue = .consentRequired; changed(); return }
        recording = syntheticRecording; voiceIssue = nil; changed()
    }
    public func resetRecording() {
        guard !voiceBusy, !voiceUnknown else { return }
        recording = nil; voiceIssue = nil; preparedVoice = nil
        voice = .init(status: .none, sample: voice?.sample); changed()
    }
    public func prepareEnroll() {
        guard let recording, !voiceBusy, voice?.status != .pending, !voiceUnknown else { return }
        guard voiceConsent else { voiceIssue = .consentRequired; changed(); return }
        guard canEnroll else { voiceIssue = .writesDisabled; changed(); return }
        if let preparedVoice, preparedVoice.sample == recording { voiceConfirmation = preparedVoice }
        else {
            let id = UUID()
            let value = VoiceConfirmation(id: id, sample: recording, consent: .init(requestID: id))
            preparedVoice = value; voiceConfirmation = value
        }
        changed()
    }
    public func declineVoiceConsent() { voiceConfirmation = nil; voiceIssue = .consentDeclined; changed() }
    public func agreeAndEnroll(_ id: UUID) async {
        guard let value = voiceConfirmation, value.id == id, let writer, canEnroll, !voiceBusy else { return }
        guard let enrollment = StoreCharacterVoiceEnrollment(voiceSample: value.sample.url) else { return }
        let stamp = generation, scope = reader.scope
        voiceConfirmation = nil; voiceBusy = true; voiceIssue = nil; changed()
        do { try await writer.recordVoiceConsent(value.consent) }
        catch {
            guard current(stamp, scope) else { return }
            voiceBusy = false; voiceIssue = .consentFailed; changed(); return
        }
        guard current(stamp, scope) else { return }
        do {
            let status = try await writer.enroll(enrollment, requestID: value.id)
            guard current(stamp, scope) else { return }
            voiceBusy = false; voiceUnknown = false; recording = nil; preparedVoice = nil
            voice = .init(status: status, sample: enrollment.voiceSample); changed()
        } catch {
            guard current(stamp, scope) else { return }
            voiceBusy = false
            if case .rejected(_, let message)? = error as? StoreCharacterFailure { voiceIssue = .server(message) }
            else { voiceIssue = .enrollUnknown; voiceUnknown = true }
            changed()
        }
        // It may have been accepted already: confirm the status before any retry.
        await refreshVoice()
    }
}
