import SwiftUI

struct MerchantStationSubmissionDraft: Equatable {
    let text: [String: String]
    let approve: Bool
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.approve == rhs.approve && lhs.text.count == rhs.text.count && lhs.text.allSatisfy { key, value in
            guard let other = rhs.text[key] else { return false }
            return value.utf8.elementsEqual(other.utf8)
        }
    }
}

struct MerchantStationSubmissionContext: Equatable {
    let snapshot: MerchantContentSnapshot
    let nodeID: Int
    private let bytes: Data
    init?(snapshot: MerchantContentSnapshot, nodeID: Int) {
        guard snapshot.access.active, let merchant = snapshot.access.merchantID, merchant > 0,
              let projection = try? MerchantStationProjection(snapshot.value),
              snapshot.query == .game(activityID: projection.activityID), projection.allows(.verify, nodeID: nodeID) else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(snapshot.value) else { return nil }
        self.snapshot = snapshot; self.nodeID = nodeID; self.bytes = bytes
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.nodeID == rhs.nodeID && lhs.snapshot == rhs.snapshot &&
            lhs.snapshot.observedAt == rhs.snapshot.observedAt && lhs.bytes == rhs.bytes
    }
    @MainActor func matches(_ owner: MerchantContentCoordinator) -> Bool {
        guard owner.isCurrent, owner.service.isConfigured, !owner.busy, !owner.locked,
              owner.review == nil, owner.receipt == nil, let current = owner.snapshot,
              current.scope == owner.service.scope,
              let context = Self(snapshot: current, nodeID: nodeID) else { return false }
        return context == self
    }
}

@MainActor final class MerchantStationSubmissionImportSession: ObservableObject, Identifiable {
    let id = UUID()
    let replacesExistingID: Bool
    @Published private(set) var raw = ""
    @Published private(set) var code: MerchantStationSubmissionCode?
    @Published private(set) var issue: String?
    private var retired = false
    private let validity: () -> Bool
    private let stage: (String) -> Bool
    init(replacesExistingID: Bool, validity: @escaping () -> Bool, stage: @escaping (String) -> Bool) {
        self.replacesExistingID = replacesExistingID; self.validity = validity; self.stage = stage
    }
    var isCurrent: Bool { !retired && validity() }
    func update(_ input: String) {
        guard isCurrent else { retire(changed: true); return }
        code = nil; issue = nil
        guard input.utf8.count <= MerchantStationSubmissionCode.maximumInputBytes else {
            raw = ""; issue = "merchant.submissionImport.oversized"; return
        }
        raw = input
    }
    func preview() {
        guard isCurrent else { retire(changed: true); return }
        do { code = try .init(raw); raw = ""; issue = nil }
        catch MerchantStationSubmissionCode.Failure.oversized { code = nil; issue = "merchant.submissionImport.oversized" }
        catch MerchantStationSubmissionCode.Failure.unsupportedLink { code = nil; issue = "merchant.submissionImport.unsupportedLink" }
        catch { code = nil; issue = "merchant.submissionImport.invalid" }
    }
    @discardableResult func apply() -> Bool {
        guard isCurrent, let code else { retire(changed: true); return false }
        // No await: final owner/draft check and the one-field local stage are atomic.
        guard stage(code.submissionID) else { retire(changed: true); return false }
        retire(); return true
    }
    func retire(changed: Bool = false) {
        retired = true; raw = ""; code = nil; issue = changed ? "merchant.submissionImport.changed" : nil
    }
}

@MainActor final class MerchantStationSubmissionImportModel: ObservableObject {
    @Published private(set) var session: MerchantStationSubmissionImportSession?
    @Published private(set) var generation: UInt64 = 0
    private(set) var active = false
    func activate() { guard !active else { return }; active = true; generation &+= 1 }
    func invalidate() { generation &+= 1; session?.retire(); session = nil }
    func deactivate() { active = false; invalidate() }
    func cancel(id: UUID) { guard session?.id == id else { return }; invalidate() }
    func presentationBinding() -> Binding<MerchantStationSubmissionImportSession?> {
        let presentedID = session?.id
        return Binding(get: { [weak self] in
            guard let self, self.session?.id == presentedID else { return nil }
            return self.session
        }, set: { [weak self] value in
            guard value == nil, let presentedID else { return }
            self?.cancel(id: presentedID)
        })
    }
    func open(permit: UInt64, owner: MerchantContentCoordinator, context: MerchantStationSubmissionContext,
              original: MerchantStationSubmissionDraft, currentDraft: @escaping () -> MerchantStationSubmissionDraft,
              stage: @escaping (String) -> Bool) {
        guard active, generation == permit, session == nil, context.matches(owner), currentDraft() == original else { return }
        let captured = generation
        session = .init(replacesExistingID: !(original.text["submissionId"] ?? "").isEmpty,
            validity: { [weak self, weak owner] in
                guard let self, let owner else { return false }
                return self.active && self.generation == captured && context.matches(owner) && currentDraft() == original
            }, stage: stage)
    }
}

/// The existing manual verification controls retain their labels, bindings and decision
/// semantics. Import only stages submissionId; it never prepares or sends a command.
@MainActor struct MerchantStationSubmissionImportView: View {
    let owner: MerchantContentViewModel
    let snapshot: MerchantContentSnapshot
    let nodeID: Int
    @Binding var text: [String: String]
    @Binding var approve: Bool
    let didChange: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = MerchantStationSubmissionImportModel()
    private var draft: MerchantStationSubmissionDraft { .init(text: text, approve: approve) }
    private var context: MerchantStationSubmissionContext? { .init(snapshot: snapshot, nodeID: nodeID) }
    var body: some View {
        let permit = model.generation
        Section {
            TextField("merchant.content.field.submissionId", text: field("submissionId"), axis: .vertical)
                .textInputAutocapitalization(.sentences).autocorrectionDisabled()
                .accessibilityIdentifier("merchant.content.field.submissionId")
            Button("merchant.submissionImport.open", systemImage: "text.viewfinder") {
                guard scenePhase == .active, let context else { return }
                let original = draft
                model.open(permit: permit, owner: owner.coordinator, context: context, original: original,
                    currentDraft: { draft }) { identifier in
                    guard scenePhase == .active, context.matches(owner.coordinator), draft == original else { return false }
                    if (text["submissionId"] ?? "").utf8.elementsEqual(identifier.utf8) { return true }
                    text["submissionId"] = identifier; didChange(); return true
                }
            }.disabled(context?.matches(owner.coordinator) != true || !model.active)
                .accessibilityIdentifier("merchant.submissionImport.open")
            Toggle("merchant.content.approve", isOn: Binding(get: { approve }, set: {
                model.invalidate(); approve = $0; didChange()
            }))
            if !approve {
                Picker("merchant.content.field.reasonCode", selection: field("reasonCode")) {
                    Text("merchant.content.chooseReason").tag("")
                    ForEach(["ANSWER_MISMATCH", "EVIDENCE_UNCLEAR", "DUPLICATE_SUBMISSION"], id: \.self) { code in
                        Text(LocalizedStringKey("merchant.content.reason." + code)).tag(code)
                    }
                }
            }
        }
        .sheet(item: model.presentationBinding()) { session in
            MerchantStationSubmissionImportSheet(session: session, cancel: { model.cancel(id: session.id) }) {
                guard session.apply() else { return }
                model.cancel(id: session.id)
            }
        }
        .onAppear { if scenePhase == .active { model.activate() } }
        .onChange(of: scenePhase) { _, value in if value == .active { model.activate() } else { model.deactivate() } }
        .onChange(of: context) { _, _ in model.invalidate() }
        .onChange(of: context?.matches(owner.coordinator) == true) { _, available in if !available { model.invalidate() } }
        .onChange(of: draft) { _, _ in model.invalidate() }
        .onDisappear { model.deactivate() }
    }
    private func field(_ name: String) -> Binding<String> {
        Binding(get: { text[name] ?? "" }, set: { model.invalidate(); text[name] = $0; didChange() })
    }
}

@MainActor private struct MerchantStationSubmissionImportSheet: View {
    @ObservedObject var session: MerchantStationSubmissionImportSession
    let cancel: () -> Void
    let apply: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Text("merchant.submissionImport.instructions").font(.footnote)
                Text("merchant.submissionImport.noCamera").font(.footnote).foregroundStyle(.secondary)
                if session.isCurrent, let code = session.code {
                    Section("merchant.submissionImport.unverified") {
                        LabeledContent("merchant.content.field.submissionId", value: code.submissionID).privacySensitive()
                        Text("merchant.submissionImport.unverifiedBody").font(.footnote)
                        if session.replacesExistingID { Text("merchant.submissionImport.replaceWarning").font(.footnote) }
                        Button("merchant.submissionImport.apply", action: apply).accessibilityIdentifier("merchant.submissionImport.apply")
                        Button("merchant.submissionImport.edit") { session.update("") }.accessibilityIdentifier("merchant.submissionImport.edit")
                    }
                } else {
                    SecureField("merchant.submissionImport.input", text: Binding(get: { session.raw }, set: session.update))
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .disabled(!session.isCurrent).accessibilityIdentifier("merchant.submissionImport.input")
                    Button("merchant.submissionImport.preview") { session.preview() }
                        .disabled(!session.isCurrent || session.raw.isEmpty).accessibilityIdentifier("merchant.submissionImport.preview")
                }
                if let issue = session.issue { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) }
            }
            .navigationTitle("merchant.submissionImport.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: cancel).accessibilityIdentifier("merchant.submissionImport.cancel") } }
        }
    }
}
