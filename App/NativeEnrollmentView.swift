import SwiftUI
import CryptoKit

@MainActor struct NativeEnrollmentView: View {
    @Bindable var model: NativeEnrollmentCoordinator
    let privacyURL: URL?
    private enum Review: String, Identifiable { case create, enroll, revoke; var id: String { rawValue } }
    @State private var review: Review?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section("nativeEnrollment.title") {
                Text("nativeEnrollment.boundary").font(.footnote)
                LabeledContent("nativeEnrollment.app") { Text(verbatim: model.scope.appID) }
                LabeledContent("nativeEnrollment.environment") { Text(verbatim: model.scope.environment) }
                LabeledContent("nativeEnrollment.account") { Text(verbatim: String(model.scope.accountID)) }
                if let key = model.record?.deviceKeyID {
                    LabeledContent("nativeEnrollment.fingerprint") { Text(verbatim: fingerprint(key)).monospaced() }
                }
                Text(LocalizedStringKey("nativeEnrollment.phase." + model.phase)).accessibilityIdentifier("nativeEnrollment.phase")
                if let issue = model.issue { Text(LocalizedStringKey("nativeEnrollment.issue." + issue.rawValue)).accessibilityIdentifier("nativeEnrollment.issue") }
                if let privacyURL { Link("nativePlatform.privacy", destination: privacyURL) }
            }
            Section {
                Button("nativeEnrollment.refresh") { Task { await model.load() } }.accessibilityIdentifier("nativeEnrollment.refresh")
                if model.canResumePreparation {
                    Button("nativeEnrollment.resumeKey") { Task { await model.prepareSavedKey() } }.accessibilityIdentifier("nativeEnrollment.resumeKey")
                }
                if model.canCreate && !model.canResumePreparation {
                    Button(LocalizedStringKey(model.record == nil ? "nativeEnrollment.create" : "nativeEnrollment.createNew")) { review = .create }
                        .accessibilityIdentifier("nativeEnrollment.create")
                }
                if model.canSubmit {
                    Text("nativeEnrollment.proofLocal").font(.footnote)
                    Button("nativeEnrollment.enroll") { review = .enroll }.accessibilityIdentifier("nativeEnrollment.enroll")
                }
                if model.canRetryEnrollment {
                    Text("nativeEnrollment.recoveryProof").font(.footnote)
                    Button("nativeEnrollment.retryEnroll") { Task { await model.retryExactEnrollment() } }.accessibilityIdentifier("nativeEnrollment.retryEnroll")
                }
                if model.canRevoke {
                    Button("nativeEnrollment.revoke", role: .destructive) { review = .revoke }.accessibilityIdentifier("nativeEnrollment.revoke")
                }
                if model.canRetryRevocation {
                    Text("nativeEnrollment.recoveryRevoke").font(.footnote)
                    Button("nativeEnrollment.retryRevoke", role: .destructive) { review = .revoke }.accessibilityIdentifier("nativeEnrollment.retryRevoke")
                }
                if ["generating", "preparing", "attesting", "enrolling", "revoking"].contains(model.phase) {
                    ProgressView("nativePlatform.working")
                }
            }
        }.navigationTitle("nativeEnrollment.title").privacySensitive().accessibilityIdentifier("nativeEnrollment.host")
        .task { await model.load() }
        .sheet(item: $review) { action in
            NavigationStack {
                Form {
                    Section {
                        Text(LocalizedStringKey("nativeEnrollment.review." + action.rawValue))
                        Text("nativeEnrollment.noHardwareProof").font(.footnote)
                        if action == .create { Text("nativeEnrollment.keyDurability").font(.footnote) }
                        if action == .revoke { Text("nativeEnrollment.revokeConsequence").font(.footnote) }
                        LabeledContent("nativeEnrollment.account") { Text(verbatim: String(model.scope.accountID)) }
                        LabeledContent("nativeEnrollment.app") { Text(verbatim: model.scope.appID) }
                        if let privacyURL { Link("nativePlatform.privacy", destination: privacyURL) }
                        Button(LocalizedStringKey("nativeEnrollment.confirm." + action.rawValue), role: action == .revoke ? .destructive : nil) {
                            review = nil
                            Task {
                                switch action {
                                case .create: await model.prepareNewKey()
                                case .enroll: await model.submitReviewed()
                                case .revoke:
                                    if model.canRetryRevocation { await model.retryExactRevocation() }
                                    else { await model.revokeReviewed() }
                                }
                            }
                        }.accessibilityIdentifier("nativeEnrollment.confirm")
                    }
                }.navigationTitle("nativeEnrollment.reviewTitle")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("nativePlatform.cancel") { review = nil } } }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { review = nil; model.suspend() }
            if phase == .active { Task { await model.load() } }
        }
        .onDisappear { review = nil; model.pauseWork() }
    }
    private func fingerprint(_ key: String) -> String { SHA256.hash(data: Data(key.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined() }
}
