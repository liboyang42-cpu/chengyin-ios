import SwiftUI

@MainActor final class ActivityEditingController: ObservableObject {
    let activityID: Int
    let session: PublishingSession
    private let service: ActivityEditingService
    @Published private(set) var draft: ActivityEditingDraft?
    @Published private(set) var review: ActivityEditingReview?
    @Published private(set) var readback: ActivityEditingSnapshot?
    @Published private(set) var pending: OperationPendingRecord?
    @Published private(set) var busy = false
    @Published private(set) var status = "ready"
    @Published private(set) var rejection = ""
    @Published private(set) var visible = false
    @Published private var active = false
    private var lockUnverified = true
    private var visit = UUID()
    init(activityID: Int, session: PublishingSession, service: ActivityEditingService) {
        self.activityID = activityID; self.session = session; self.service = service
    }
    var current: Bool { visible && active && service.currentSession == session }
    var readable: Bool { current && service.canRead && !busy && review == nil }
    var editable: Bool { current && !busy && review == nil && pending == nil && !lockUnverified && status != "acknowledged" && status != "unknown" }
    var reviewable: Bool { editable && draft?.changed == true && service.canUpdate }
    var ownerID: UUID { visit }
    func appear(active: Bool) {
        visible = true; setActive(active)
        guard current else { return }
        lockUnverified = true
        do {
            pending = try service.pending(id: activityID, session: session); lockUnverified = false
            if draft == nil, let saved = try service.drafts.load(id: activityID, session: session),
               pending == nil || saved.requestID == pending?.operationID { draft = saved.draft }
            if pending != nil { status = "unknown" }
        } catch { status = "unavailable" }
    }
    func setActive(_ value: Bool) {
        active = value
        if !value { retireReview(); visit = UUID(); busy = false }
    }
    func disappear() { visible = false; visit = UUID(); busy = false; retireReview() }
    private func valid(_ captured: UUID) -> Bool { current && visit == captured }
    private func retireReview() { if let review { service.cancel(review) }; review = nil }
    func binding(_ field: ActivityEditingField) -> Binding<String> {
        let captured = visit, draftID = draft?.id
        return Binding(get: { [weak self] in
            guard let self, self.valid(captured), self.draft?.id == draftID else { return "" }
            return self.draft?.text(field) ?? ""
        }, set: { [weak self] value in
            guard let self, self.valid(captured), self.editable, self.draft?.id == draftID,
                  !(self.draft?.source.timeLocationLocked == true && field.timeOrPlace) else { return }
            self.draft?.set(field, value); self.status = "editing"
        })
    }
    func load() async {
        guard readable else { return }
        let captured = visit; busy = true; status = "loading"; rejection = ""
        defer { if valid(captured) { busy = false } }
        do {
            let latest = try await service.load(id: activityID, session: session, current: { [weak self] in self?.valid(captured) == true })
            guard valid(captured) else { return }
            readback = latest
            lockUnverified = true
            pending = try service.pending(id: activityID, session: session); lockUnverified = false
            let saved = try service.drafts.load(id: activityID, session: session)
            if let pending {
                // Keep the original sent draft; an independent info reply never consumes its replay lock.
                if let saved, saved.requestID == pending.operationID { draft = saved.draft }
                else { draft = nil }
                status = "unknown"
            } else if draft == nil {
                draft = saved?.draft ?? ActivityEditingDraft(source: latest)
                status = draft?.source.revision == latest.revision ? "editing" : "conflict"
            } else { status = "readback" }
        } catch {
            guard valid(captured) else { return }; report(error)
        }
    }
    func useReadback(owner: UUID) {
        guard valid(owner), !busy, pending == nil, !lockUnverified, status != "unknown", let readback else { return }
        retireReview(); draft = ActivityEditingDraft(source: readback); status = "editing"
    }
    func saveLocal() {
        guard editable, let draft else { return }
        lockUnverified = true
        do {
            pending = try service.pending(id: activityID, session: session); lockUnverified = false
            guard pending == nil else { status = "unknown"; return }
            try service.drafts.save(.init(session: session, draft: draft), session: session); status = "localSaved"
        } catch { report(error) }
    }
    func prepare() async {
        guard reviewable, let original = draft else { return }
        let captured = visit; busy = true; rejection = ""
        defer { if valid(captured) { busy = false } }
        do {
            let value = try await service.prepare(original, session: session, current: { [weak self] in self?.valid(captured) == true })
            guard valid(captured), draft == original else { service.cancel(value); return }
            review = value; status = "review"
        } catch { guard valid(captured) else { return }; report(error) }
    }
    func cancel(_ original: ActivityEditingReview) {
        guard current, !busy, review?.id == original.id else { return }
        service.cancel(original); review = nil; status = "editing"
    }
    func confirm(_ original: ActivityEditingReview) async {
        guard current, !busy, review == original, draft == original.draft else { return }
        let captured = visit; busy = true; status = "sending"
        let outcome = await service.submit(original, current: { [weak self] in self?.valid(captured) == true })
        guard valid(captured) else { return }
        busy = false; review = nil; readback = nil
        lockUnverified = true
        do { pending = try service.pending(id: activityID, session: session); lockUnverified = false }
        catch { status = "unknown"; return }
        switch outcome {
        case .acknowledged: status = "acknowledged"
        case .rejected(let message): status = "rejected"; rejection = message
        case .notSent: status = pending == nil ? "notSent" : "unknown"
        case .unknown: status = "unknown"
        }
    }
    private func report(_ error: Error) {
        if error as? PublishModesError == .conflict { status = "conflict" }
        else if error as? PublishModesError == .uncertain { status = "unknown" }
        else if let failure = error as? PublishModesError, case .rejected(let message) = failure { status = "rejected"; rejection = message }
        else { status = "unavailable" }
    }
}

/// One whole-page owner. Review stays on this page; hiding it always invalidates old callbacks.
@MainActor struct ActivityEditingView: View {
    @StateObject private var owner: ActivityEditingController
    @Environment(\.scenePhase) private var scenePhase
    init(owner: ActivityEditingController) { _owner = StateObject(wrappedValue: owner) }
    var body: some View {
        Form {
            Section {
                Text(LocalizedStringKey(owner.status), tableName: "ActivityEditing")
                    .accessibilityIdentifier("activityEdit.status")
                if !owner.rejection.isEmpty { Text(verbatim: owner.rejection) }
                Button { Task { await owner.load() } } label: { label("load") }
                    .disabled(!owner.readable).accessibilityIdentifier("activityEdit.load")
                if let request = owner.pending {
                    Text(verbatim: request.operationID.uuidString).textSelection(.enabled)
                        .accessibilityIdentifier("activityEdit.requestID")
                    label("unknownBoundary")
                }
            }
            if let draft = owner.draft {
                Section {
                    if draft.source.timeLocationLocked { label("timeLocked") }
                    ForEach(ActivityEditingField.allCases, id: \.rawValue) { field in
                        TextField(text: owner.binding(field), axis: field == .description ? .vertical : .horizontal) {
                            label(field.rawValue)
                        }
                        .disabled(!owner.editable || (draft.source.timeLocationLocked && field.timeOrPlace))
                        .accessibilityIdentifier("activityEdit." + field.rawValue)
                    }
                    label("ticketBoundary")
                }
                Section {
                    Button { owner.saveLocal() } label: { label("saveLocal") }.disabled(!owner.editable)
                        .accessibilityIdentifier("activityEdit.saveLocal")
                    Button { Task { await owner.prepare() } } label: { label("reviewAction") }.disabled(!owner.reviewable)
                        .accessibilityIdentifier("activityEdit.review")
                }
            }
            if let current = owner.review {
                Section {
                    label("reviewBoundary")
                    ForEach(ActivityEditingField.allCases, id: \.rawValue) { field in
                        LabeledContent { Text(verbatim: current.draft.text(field)) } label: { label(field.rawValue) }
                    }
                    Text(verbatim: current.id.uuidString).accessibilityIdentifier("activityEdit.reviewID")
                    Button { owner.cancel(current) } label: { label("cancel") }.disabled(owner.busy)
                    Button { Task { await owner.confirm(current) } } label: { label("confirm") }.disabled(owner.busy || !owner.current)
                        .accessibilityIdentifier("activityEdit.confirm")
                }
            }
            if owner.readback != nil && !owner.busy {
                let originalOwner = owner.ownerID
                Section {
                    label("latest")
                    if let latest = owner.readback {
                        ForEach(ActivityEditingField.allCases, id: \.rawValue) { field in
                            LabeledContent { Text(verbatim: latest.text(field)) } label: { label(field.rawValue) }
                        }
                    }
                    if owner.pending == nil {
                        Button { owner.useReadback(owner: originalOwner) } label: { label("useReadback") }
                            .disabled(!owner.current).accessibilityIdentifier("activityEdit.useReadback")
                    }
                }
            }
        }
        .navigationTitle(Text("title", tableName: "ActivityEditing"))
        .onAppear { owner.appear(active: scenePhase == .active) }
        .onDisappear { owner.disappear() }
        .onChange(of: scenePhase) { _, phase in owner.setActive(phase == .active) }
    }
    private func label(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "ActivityEditing") }
}
