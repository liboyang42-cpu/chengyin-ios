import SwiftUI

private struct NativeVerificationDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> AnyView)? = nil
}
extension EnvironmentValues {
    var nativeVerificationDestination: (@MainActor () -> AnyView)? {
        get { self[NativeVerificationDestinationKey.self] }
        set { self[NativeVerificationDestinationKey.self] = newValue }
    }
}
@MainActor struct SessionNativeVerificationView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        NativeVerificationView(flow: session.nativeVerificationFlow, cameraEnabled: session.verificationCameraEnabled,
            records: { AnyView(MerchantBusinessPage(reader: session.merchantBusinessReader,
                journal: session.merchantBusinessJournal, query: .redemptions(filter: "all", page: 1))) })
            .id(session.sessionRevision)
    }
}
/// Input, exact-purpose review, any server choice and result/readback are distinct states.
/// Camera/media/provider acceptance is independent of read access and mutation authority.
@MainActor struct NativeVerificationView: View {
    @Bindable var flow: NativeVerificationWorkflow
    var cameraEnabled = false
    let records: @MainActor () -> AnyView
    @State private var raw = ""
    @State private var camera = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                Text("verification.boundary").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("verification.screen")
                if let key = flow.issueKey { Text(LocalizedStringKey(key)).accessibilityIdentifier("verification.issue") }
                if flow.phase == .loading { ProgressView("verification.loading") }
                if let access = flow.access, flow.current {
                    LabeledContent("verification.merchant") { Text(verbatim: access.name ?? String(access.merchantID)) }
                }
            }
            if flow.current {
                if flow.needsReadback {
                    Section("verification.unknownTitle") {
                        Text("verification.unknownBody")
                        NavigationLink { records() } label: { Label("verification.records", systemImage: "list.bullet.rectangle") }
                            .accessibilityIdentifier("verification.readback")
                        Text("verification.readbackDoesNotUnlock").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if flow.phase == .submitting {
                    ProgressView("verification.submitting").accessibilityIdentifier("verification.submitting")
                } else if let result = flow.result {
                    resultSection(result)
                }
                if flow.canCapture {
                    Section("verification.capture") {
                        Button("verification.scan", systemImage: "qrcode.viewfinder") { camera = true }
                            .disabled(!cameraEnabled).accessibilityIdentifier("verification.scan")
                        if !cameraEnabled { Text("verification.cameraUnavailable").font(.footnote).foregroundStyle(.secondary) }
                        SecureField("verification.code", text: $raw)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("verification.code")
                        Button("verification.review") { capture() }
                            .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("verification.review")
                    }
                }
            }
            Section {
                if !flow.current { Button("verification.refreshAccess") { Task { await flow.activate() } }.disabled(flow.phase == .loading) }
                NavigationLink { records() } label: { Label("verification.records", systemImage: "list.bullet.rectangle") }
                if !flow.canDispatch { Text("verification.dispatchDisabled").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("verification.title").navigationBarTitleDisplayMode(.inline)
        .privacySensitive().scrollDismissesKeyboard(.interactively)
        .task(id: flow.scope) { raw = ""; await flow.activate() }
        .sheet(isPresented: $camera) {
            NativeQRScanner { value in raw = ""; Task { await flow.prepare(raw: value) } }
        }
        .sheet(item: Binding(get: { flow.review }, set: { if $0 == nil { flow.cancelReview() } })) { review in
            NativeVerificationReviewView(review: review, canConfirm: flow.canConfirm,
                confirm: { Task { await flow.confirm(review) } }, cancel: { flow.cancelReview() })
        }
        .onChange(of: scenePhase) { _, phase in
            // Camera permission dialogs can temporarily make the scene inactive.
            // Preserve that presentation; backgrounding or session loss still tears it down.
            if phase == .background { raw = ""; camera = false; flow.deactivate() }
            else if phase == .active, !flow.current { Task { await flow.activate() } }
        }
        .onDisappear { raw = ""; camera = false; flow.deactivate() }
    }
    private func capture() { let captured = raw; raw = ""; Task { await flow.prepare(raw: captured) } }
    @ViewBuilder private func resultSection(_ result: MerchantRedemptionResult) -> some View {
        Section {
            if let message = result.message { Text(verbatim: message) }
            switch result.outcome {
            case .redeemed:
                Label("verification.reportedRedeemed", systemImage: "checkmark.circle")
                Text("verification.receiptBoundary").font(.footnote)
            case .failed: Label("verification.rejected", systemImage: "exclamationmark.circle")
            case .needsChoice:
                Text("verification.choose")
                ForEach(result.choices) { choice in
                    Button { flow.prepareChoice(choice.target) } label: {
                        if let name = choice.name { Text(verbatim: name) }
                        else { Text(verbatim: choice.id) }
                    }.disabled(flow.phase != .choosing).accessibilityIdentifier("verification.choice." + choice.id)
                }
                Button("action.cancel", role: .cancel) { flow.cancelChoice() }
            }
        } header: { Text("verification.result").accessibilityIdentifier("verification.result") }
    }
}
@MainActor private struct NativeVerificationReviewView: View {
    let review: NativeVerificationReview
    let canConfirm: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("verification.review") {
                    LabeledContent("verification.merchant") { Text(verbatim: review.merchantName ?? String(review.merchantID)) }
                    LabeledContent("verification.kind") { Text(LocalizedStringKey("verification.kind." + review.kind.rawValue)) }
                    if let name = review.choiceName { LabeledContent("verification.selected") { Text(verbatim: name) } }
                    Text("verification.reviewEffect")
                    Text("verification.reviewPrivacy").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("verification.confirm", action: confirm).disabled(!canConfirm)
                        .accessibilityIdentifier("verification.confirm")
                    if !canConfirm { Text("verification.dispatchDisabled").font(.footnote) }
                }
            }.navigationTitle("verification.review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: cancel) } }
        }.presentationDetents([.large]).privacySensitive()
    }
}
