import SwiftUI

/// Retained by the entire activity page, not a lazy Form row.
@MainActor final class PublisherIdentityRegistrationOwner: ObservableObject {
    enum Status: String { case idle, loading, unregistered, registered, failed, unavailable, rejected, unknown, acknowledgedReadFailed }
    @Published private(set) var open = false
    @Published private(set) var busy = false
    @Published private(set) var status: Status = .idle
    @Published private(set) var name = ""
    @Published private(set) var idCard = ""
    @Published private(set) var consent = false
    @Published private(set) var uncertain = false
    @Published private(set) var confirmedRegistered = false
    private var acknowledged = false
    private var account: PublishingSession?
    private var draftID: UUID?
    private var source: Data?
    private var visit = UUID()
    var actionID: UUID { visit }
    private var pageVisible = false
    private var sceneActive = false
    private var service: PublisherIdentityRegistrationService?
    private var review: PublishingAuxiliaryReview?
    private struct Source: Encodable { let account: PublishingSession?; let id: UUID; let draft: ActivityPublishDraft }
    func bind(account: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft) {
        let bytes = ProjectEditPendingMaterials.exactData(Source(account: account, id: draftID, draft: draft))
        if self.account != account || self.draftID != draftID || source != bytes { retire(); confirmedRegistered = false; self.account = account; self.draftID = draftID; source = bytes }
    }
    func appear(active: Bool) { pageVisible = true; sceneActive = active }
    func disappear() { pageVisible = false; confirmedRegistered = false; retire() }
    func setActive(_ active: Bool) { sceneActive = active; if !active { confirmedRegistered = false; retire() } }
    private var current: Bool { pageVisible && sceneActive && open && service?.currentSession == account }
    var canEdit: Bool { current && !busy && !uncertain && !acknowledged && [.unregistered, .rejected].contains(status) }
    func begin(service: PublisherIdentityRegistrationService?, expected: UUID) async {
        guard expected == visit, pageVisible, sceneActive, !open, let account, account.region == .china, account.role == "club", source != nil else { return }
        visit = UUID(); self.service = service; open = true; service?.activate()
        guard let service, service.session == account else { status = .unavailable; return }
        await refresh(expected: visit)
    }
    func refresh(expected: UUID) async {
        guard expected == visit, current, !busy, let service else { return }; let stamp = visit
        busy = true; confirmedRegistered = false; status = .loading
        do {
            uncertain = try service.pending() != nil
            let registered = try await service.status()
            guard current, stamp == visit else { return }
            confirmedRegistered = registered
            status = registered ? .registered : acknowledged ? .acknowledgedReadFailed : uncertain ? .unknown : service.configured ? .unregistered : .unavailable
            if registered { clearInputs() }
        } catch {
            guard current, stamp == visit else { return }
            // An unreadable marker is not permission to attempt another registration.
            uncertain = (try? service.pending() == nil) != true
            status = uncertain ? .unknown : service.configured ? .failed : .unavailable
        }
        busy = false
    }
    func textBinding(nameField: Bool) -> Binding<String> {
        let stamp = visit
        return Binding(get: { [weak self] in
            guard let self, self.current, self.visit == stamp else { return "" }; return nameField ? self.name : self.idCard
        }, set: { [weak self] value in
            guard let self, self.canEdit, self.visit == stamp else { return }
            if nameField { self.name = value } else { self.idCard = value }; self.cancelReview()
        })
    }
    func consentBinding() -> Binding<Bool> {
        let stamp = visit
        return Binding(get: { [weak self] in self.map { $0.current && $0.visit == stamp && $0.consent } ?? false },
            set: { [weak self] value in guard let self, self.canEdit, self.visit == stamp else { return }; self.consent = value; self.cancelReview() })
    }
    func submit(currentYear: Int, expected: UUID) async {
        guard expected == visit, canEdit, let service else { return }; let stamp = visit
        do { review = try service.prepare(name: name, idCard: idCard, consent: consent, currentYear: currentYear) }
        catch { uncertain = (try? service.pending() == nil) != true; status = uncertain ? .unknown : .rejected; return }
        guard let captured = review else { return }; busy = true
        let result = await service.submit(captured)
        guard current, stamp == visit, review?.id == captured.id else { return }
        review = nil; busy = false
        switch result {
        case .acknowledged:
            clearInputs(); acknowledged = true; status = .acknowledgedReadFailed
            busy = true
            do {
                let registered = try await service.status()
                guard current, stamp == visit else { return }
                confirmedRegistered = registered
                status = registered ? .registered : .acknowledgedReadFailed
            } catch { guard current, stamp == visit else { return }; status = .acknowledgedReadFailed }
            busy = false
        case .unknown: uncertain = true; status = .unknown
        case .rejected, .unavailable: status = .rejected
        case .notSent:
            uncertain = (try? service.pending() == nil) != true
            status = uncertain ? .unknown : .rejected
        }
    }
    func close(_ expected: UUID) { guard expected == visit else { return }; retire() }
    private func retire() {
        visit = UUID(); cancelReview(); service?.retire(); service = nil
        open = false; busy = false; status = .idle; uncertain = false; acknowledged = false; clearInputs()
    }
    private func cancelReview() { if let review { service?.cancel(review) }; review = nil }
    private func clearInputs() { name = ""; idCard = ""; consent = false }
}

/// Inline in the original draft. No second sheet, copied draft or automatic publish action.
@MainActor struct PublisherIdentityRegistrationSection: View {
    @ObservedObject var owner: PublisherIdentityRegistrationOwner
    let makeService: (() -> PublisherIdentityRegistrationService?)?
    let enabled: Bool
    var body: some View {
        let stamp = owner.actionID
        Section {
            Text("notice", tableName: "PublisherIdentityRegistration")
            if owner.open {
                Text(LocalizedStringKey("status." + owner.status.rawValue), tableName: "PublisherIdentityRegistration")
                    .accessibilityIdentifier("publisherIdentity.status")
                if owner.uncertain && owner.status == .registered { Text("unknownReadback", tableName: "PublisherIdentityRegistration") }
                if owner.busy { ProgressView() }
                if owner.status != .registered && owner.status != .acknowledgedReadFailed {
                    TextField(text: owner.textBinding(nameField: true)) { Text("name", tableName: "PublisherIdentityRegistration") }
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .disabled(!owner.canEdit).accessibilityIdentifier("publisherIdentity.name")
                    SecureField(text: owner.textBinding(nameField: false)) { Text("idCard", tableName: "PublisherIdentityRegistration") }
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().privacySensitive()
                        .disabled(!owner.canEdit).accessibilityIdentifier("publisherIdentity.idCard")
                    Toggle(isOn: owner.consentBinding()) { Text("consent", tableName: "PublisherIdentityRegistration") }
                        .disabled(!owner.canEdit).accessibilityIdentifier("publisherIdentity.consent")
                    Button { Task { await owner.submit(currentYear: Calendar(identifier: .gregorian).component(.year, from: Date()), expected: stamp) } }
                        label: { Text("submit", tableName: "PublisherIdentityRegistration") }
                        .disabled(!owner.canEdit || !owner.consent).accessibilityIdentifier("publisherIdentity.submit")
                }
                if !owner.busy {
                    Button { Task { await owner.refresh(expected: stamp) } } label: { Text("refresh", tableName: "PublisherIdentityRegistration") }
                        .accessibilityIdentifier("publisherIdentity.refresh")
                }
                Button { owner.close(stamp) } label: { Text("return", tableName: "PublisherIdentityRegistration") }
                    .accessibilityIdentifier("publisherIdentity.return")
            } else {
                if owner.confirmedRegistered { Text("status.registered", tableName: "PublisherIdentityRegistration") }
                Button { Task { await owner.begin(service: makeService?(), expected: stamp) } }
                    label: { Text("open", tableName: "PublisherIdentityRegistration") }
                    .disabled(!enabled).accessibilityIdentifier("publisherIdentity.open")
            }
        } header: { Text("title", tableName: "PublisherIdentityRegistration") }
    }
}
