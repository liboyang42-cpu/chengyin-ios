import SwiftUI

@MainActor struct CityArrivalEvidenceEntry: View {
    let board: CityReadBoard
    let factory: (@MainActor (CityReadBoard) -> CityArrivalEvidenceController)?
    var body: some View {
        if let factory { NavigationLink { CityArrivalEvidenceView(controller: factory(board)) } label: { Label { CityArrivalCopy.text("playerEntry") } icon: { Image(systemName: "checkmark.shield") } } }
        else { CityArrivalCopy.text("status.disabled") }
    }
}
enum CityArrivalCopy {
    static func text(_ key: String) -> Text { Text(LocalizedStringKey("cityArrival." + key), tableName: "CityArrivalEvidence") }
}
@MainActor struct CityArrivalEvidenceView: View {
    @State var controller: CityArrivalEvidenceController
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section {
                CityArrivalCopy.text("boundary")
                Text(LocalizedStringKey(controller.messageKey), tableName: "CityArrivalEvidence")
                Button { Task { await controller.load() } } label: { CityArrivalCopy.text("reload") }.disabled(controller.busy)
            }
            if controller.current, scenePhase == .active, let state = controller.player {
                CityArrivalCopy.text("state." + state.status)
                if let binding = state.binding {
                    Section { Text(verbatim: binding.title); row("rulesRelease", binding.rulesReleaseId); row("round", binding.rules.roundId) } header: { CityArrivalCopy.text("frozenBinding") }
                }
                ForEach(state.points) { point in
                    Section {
                        Text(verbatim: point.title)
                        row("merchant", String(point.merchantId)); row("place", String(point.placeId))
                        row("challengeWindow", String(point.rules.challengeTtlSeconds)); row("evidenceWindow", String(point.rules.evidenceTtlSeconds))
                        row("attemptLimit", String(point.rules.maxChallenges)); row("attempts", String(point.attemptVersion))
                        row("assuranceReason", point.rules.assuranceReason)
                        if !point.canIssue { CityArrivalCopy.text("sourceUnavailableHint") }
                        CityArrivalCopy.text("singlePerson")
                        Button { controller.prepareIssue(point) } label: { CityArrivalCopy.text("issue") }.disabled(!controller.canWrite || !point.canIssue)
                        if let challenge = point.challenge {
                            CityArrivalCopy.text("challenge." + challenge.state)
                            row("challengeId", challenge.id); row("expires", challenge.expiresAt)
                            if let code = controller.codes[challenge.id] { row("displayCode", code); CityArrivalCopy.text("showOnlyInPerson") }
                            if challenge.state == "ISSUED" { Button { controller.prepareSubmit(point) } label: { CityArrivalCopy.text("submitSelf") }.disabled(!controller.canWrite || controller.codes[challenge.id] == nil) }
                        }
                        if let proof = point.evidence { Button { Task { await controller.readProof(proof.id) } } label: { CityArrivalCopy.text("readEvidence") }.disabled(controller.busy || !controller.current) }
                    }
                }
            }
            if controller.current, scenePhase == .active, let state = controller.merchant {
                Section { row("merchant", String(state.merchantId)); CityArrivalCopy.text("role." + state.role); CityArrivalCopy.text("staffBoundary") }
                if state.pending.isEmpty { CityArrivalCopy.text("noPending") }
                ForEach(state.pending) { challenge in CityArrivalStaffClaimRow(controller: controller, challenge: challenge) }
            }
            if controller.current, scenePhase == .active, let proof = controller.proof {
                Section {
                    row("evidenceId", proof.id); row("requestId", proof.requestId); row("challengeId", proof.challengeId)
                    row("subject", String(proof.memberId)); row("point", proof.pointId); row("merchant", String(proof.merchantId)); row("place", String(proof.placeId))
                    row("round", proof.roundId); row("rulesRelease", proof.rulesReleaseId)
                    row("reviewer", String(proof.reviewerMemberId)); row("reason", proof.reason); row("recordedAt", proof.createdAt); row("expires", proof.expiresAt)
                    CityArrivalCopy.text("evidence." + proof.timeStatus); CityArrivalCopy.text("evidenceBoundary")
                } header: { CityArrivalCopy.text("originalEvidence") }
            }
            if controller.current, scenePhase == .active, let pending = controller.pendingRequestID {
                Section { row("requestId", pending.uuidString); CityArrivalCopy.text("unknownHint"); Button { Task { await controller.recover() } } label: { CityArrivalCopy.text("recover") }.disabled(controller.busy || !controller.current) }
            }
            if controller.current, scenePhase == .active, let receipt = controller.receipt {
                Section {
                    row("requestId", receipt.requestId); CityArrivalCopy.text(receipt.succeeded ? "receiptRecorded" : "receiptRejected")
                    if let proof = receipt.evidence { Button { Task { await controller.readProof(proof.id) } } label: { CityArrivalCopy.text("readEvidence") }.disabled(controller.busy || !controller.current) }
                }
            }
        }
        .navigationTitle(CityArrivalCopy.text("title"))
        .task { await controller.load() }
        .onChange(of: controller.current) { _, current in if !current { controller.invalidate() } }
        .onChange(of: scenePhase) { _, phase in controller.invalidate(); if phase == .active { Task { await controller.load() } } }
        .onDisappear { controller.invalidate() }
        .sheet(item: Binding(get: { controller.current && scenePhase == .active ? controller.confirmation : nil }, set: { if $0 == nil { controller.cancelConfirmation() } })) { captured in
            NavigationStack {
                Form {
                    Text(verbatim: captured.pointTitle); CityArrivalCopy.text("confirm." + captured.command.kind.rawValue)
                    if let reason = captured.command.reason { row("reason", reason) }
                    CityArrivalCopy.text("noAutomaticEffects")
                    Button { Task { await controller.confirm(captured) } } label: { CityArrivalCopy.text("confirmNow") }.disabled(!controller.canWrite)
                    Button { controller.cancelConfirmation() } label: { CityArrivalCopy.text("cancel") }
                }.navigationTitle(CityArrivalCopy.text("confirmTitle"))
            }
        }
    }
    private func row(_ key: String, _ value: String) -> some View { LabeledContent { Text(verbatim: value).textSelection(.enabled) } label: { CityArrivalCopy.text(key) } }
}
@MainActor private struct CityArrivalStaffClaimRow: View {
    let controller: CityArrivalEvidenceController
    let challenge: CityArrivalChallenge
    @State private var code = ""
    @State private var reason = ""
    var body: some View {
        Section {
            Text(verbatim: challenge.pointTitle ?? challenge.pointId)
            LabeledContent { Text(verbatim: challenge.id) } label: { CityArrivalCopy.text("challengeId") }
            LabeledContent { Text(verbatim: String(challenge.memberId)) } label: { CityArrivalCopy.text("subject") }
            LabeledContent { Text(verbatim: String(challenge.placeId)) } label: { CityArrivalCopy.text("place") }
            LabeledContent { Text(verbatim: challenge.expiresAt) } label: { CityArrivalCopy.text("expires") }
            TextField(text: $code) { CityArrivalCopy.text("enterPresentedCode") }.textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField(text: $reason, axis: .vertical) { CityArrivalCopy.text("enterReason") }
            Button { controller.prepareReview(challenge, confirms: true, code: code, reason: reason) } label: { CityArrivalCopy.text("staffConfirm") }.disabled(!controller.canWrite)
            Button { controller.prepareReview(challenge, confirms: false, code: "", reason: reason) } label: { CityArrivalCopy.text("staffReject") }.disabled(!controller.canWrite)
        }
        .onDisappear { code = ""; reason = "" }
        .onChange(of: controller.current) { _, current in if !current { code = ""; reason = "" } }
    }
}
