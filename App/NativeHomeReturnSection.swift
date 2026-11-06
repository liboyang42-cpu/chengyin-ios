import SwiftUI

/// W19 explicit foreground verification and separate restore confirmation. Default composition is OFF.
/// The home point is never displayed here; only resource facts and decisions are.
struct NativeHomeReturnSection: View {
    let model: NativeHomeReturnCoordinator?
    let home: PrivateHomeSnapshot?
    var body: some View {
        Section {
            if let model { content(model) }
            else {
                Text("homeReturn.notEnabled", tableName: "NativeHomeReturn").font(.footnote).accessibilityIdentifier("homeReturn.notEnabled")
            }
        } header: { Text("homeReturn.title", tableName: "NativeHomeReturn") }
        .task { if model?.phase == .idle { await model?.load() } }
        .onChange(of: home?.version) { _, _ in model?.cancelVerification() }
        .onDisappear { model?.cancelVerification() }
    }

    @ViewBuilder private func content(_ model: NativeHomeReturnCoordinator) -> some View {
        phaseText(model.phase).font(.footnote).accessibilityIdentifier("homeReturn.phase")
        Text("homeReturn.manual", tableName: "NativeHomeReturn").font(.footnote).fixedSize(horizontal: false, vertical: true)
        if case .run(let id, _) = model.scope {
            (Text("homeReturn.selectedRun", tableName: "NativeHomeReturn") + Text(verbatim: " #\(id)"))
                .accessibilityIdentifier("homeReturn.selectedRun")
        }
        if let account = model.account {
            LabeledContent { Text(verbatim: "\(account.current) / \(account.maximum)") } label: { scopeText(model.scope) }
                .accessibilityIdentifier("homeReturn.account")
        } else if model.phase == .unavailable {
            Text("homeReturn.unavailable", tableName: "NativeHomeReturn").font(.footnote)
        }
        if let failure = model.failure { failureText(failure).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeReturn.failure") }
        if let decision = model.decision { decisionText(decision).accessibilityIdentifier("homeReturn.decision") }
        if model.requiresAccountReadback { Text("homeReturn.readbackRequired", tableName: "NativeHomeReturn").font(.footnote) }
        if model.canRestore, home?.status == .active {
            Text("homeReturn.restorePurpose", tableName: "NativeHomeReturn").font(.footnote)
            Button { Task { await model.confirmRestore(home: home) } } label: { Text("homeReturn.confirmRestore", tableName: "NativeHomeReturn") }
                .accessibilityIdentifier("homeReturn.confirmRestore")
            Button { model.cancelVerification() } label: { Text("homeReturn.cancel", tableName: "NativeHomeReturn") }
                .accessibilityIdentifier("homeReturn.cancel")
        }
        if model.noReceiptYet { Text("homeReturn.noReceiptYet", tableName: "NativeHomeReturn").font(.footnote) }
        if model.isBusy { ProgressView() }
        if home?.status != .active, model.phase == .ready {
            Text("homeReturn.needHome", tableName: "NativeHomeReturn").font(.footnote).accessibilityIdentifier("homeReturn.needHome")
        }
        if model.canCheckIn, home?.status == .active {
            Button { Task { await model.checkIn(home: home) } } label: { Text("homeReturn.checkIn", tableName: "NativeHomeReturn") }
                .accessibilityIdentifier("homeReturn.checkIn")
        }
        if model.phase == .unknown {
            Text("homeReturn.unknown", tableName: "NativeHomeReturn").font(.footnote).fixedSize(horizontal: false, vertical: true)
            Button { Task { await model.readBack() } } label: { Text("homeReturn.readBack", tableName: "NativeHomeReturn") }
                .accessibilityIdentifier("homeReturn.readBack")
            if model.canRetryExact {
                Button { Task { await model.retryExact() } } label: { Text("homeReturn.retry", tableName: "NativeHomeReturn") }
                    .accessibilityIdentifier("homeReturn.retry")
            }
        }
        if model.phase == .unavailable || model.phase == .ready || model.phase == .blocked {
            Button { Task { await model.load() } } label: { Text("homeReturn.refresh", tableName: "NativeHomeReturn") }
                .accessibilityIdentifier("homeReturn.refresh")
        }
    }

    private func phaseText(_ phase: NativeHomeReturnCoordinator.Phase) -> Text {
        switch phase {
        case .disabled: return Text("homeReturn.phase.disabled", tableName: "NativeHomeReturn")
        case .idle, .ready: return Text("homeReturn.phase.ready", tableName: "NativeHomeReturn")
        case .loading: return Text("homeReturn.phase.loading", tableName: "NativeHomeReturn")
        case .unavailable: return Text("homeReturn.phase.unavailable", tableName: "NativeHomeReturn")
        case .verified: return Text("homeReturn.phase.verified", tableName: "NativeHomeReturn")
        case .dwelling: return Text("homeReturn.phase.dwelling", tableName: "NativeHomeReturn")
        case .blocked: return Text("homeReturn.failure.storageUnavailable", tableName: "NativeHomeReturn")
        case .checking: return Text("homeReturn.phase.checking", tableName: "NativeHomeReturn")
        case .restoring: return Text("homeReturn.phase.restoring", tableName: "NativeHomeReturn")
        case .unknown: return Text("homeReturn.phase.unknown", tableName: "NativeHomeReturn")
        case .invalidated: return Text("homeReturn.phase.invalidated", tableName: "NativeHomeReturn")
        }
    }

    private func scopeText(_ scope: NativeHomeResourceScope) -> Text {
        switch scope {
        case .global: return Text("homeReturn.scope.global", tableName: "NativeHomeReturn")
        case .run: return Text("homeReturn.scope.run", tableName: "NativeHomeReturn")
        case .theme: return Text("homeReturn.scope.theme", tableName: "NativeHomeReturn")
        }
    }

    private func failureText(_ failure: NativeHomeReturnFailure) -> Text {
        switch failure {
        case .disabled: return Text("homeReturn.phase.disabled", tableName: "NativeHomeReturn")
        case .locationOff: return Text("homeReturn.failure.locationOff", tableName: "NativeHomeReturn")
        case .permissionDenied: return Text("homeReturn.failure.permissionDenied", tableName: "NativeHomeReturn")
        case .lowAccuracy: return Text("homeReturn.failure.lowAccuracy", tableName: "NativeHomeReturn")
        case .staleFix: return Text("homeReturn.failure.staleFix", tableName: "NativeHomeReturn")
        case .cooldown(let seconds):
            return Text("homeReturn.failure.cooldown", tableName: "NativeHomeReturn") + Text(verbatim: " (\(seconds)s)")
        case .outOfRadius: return Text("homeReturn.failure.outOfRadius", tableName: "NativeHomeReturn")
        case .homeChanged: return Text("homeReturn.failure.homeChanged", tableName: "NativeHomeReturn")
        case .proofExpired: return Text("homeReturn.failure.proofExpired", tableName: "NativeHomeReturn")
        case .noHome: return Text("homeReturn.needHome", tableName: "NativeHomeReturn")
        case .network: return Text("homeReturn.failure.network", tableName: "NativeHomeReturn")
        case .unknown: return Text("homeReturn.unknown", tableName: "NativeHomeReturn")
        case .dwellRequired(let seconds): return Text("homeReturn.failure.dwellRequired", tableName: "NativeHomeReturn") + Text(verbatim: " (\(seconds)s)")
        case .runUnavailable: return Text("homeReturn.failure.runUnavailable", tableName: "NativeHomeReturn")
        case .storageUnavailable: return Text("homeReturn.failure.storageUnavailable", tableName: "NativeHomeReturn")
        case .invalid: return Text("homeReturn.failure.invalid", tableName: "NativeHomeReturn")
        }
    }

    private func decisionText(_ decision: NativeHomeRestoreReceipt.Decision) -> Text {
        switch decision {
        case .restored: return Text("homeReturn.decision.restored", tableName: "NativeHomeReturn")
        case .alreadyAtMax: return Text("homeReturn.decision.alreadyAtMax", tableName: "NativeHomeReturn")
        case .proofConsumed: return Text("homeReturn.decision.proofConsumed", tableName: "NativeHomeReturn")
        case .staleHome: return Text("homeReturn.failure.homeChanged", tableName: "NativeHomeReturn")
        case .proofExpired, .proofUnavailable: return Text("homeReturn.failure.proofExpired", tableName: "NativeHomeReturn")
        case .runUnavailable: return Text("homeReturn.failure.runUnavailable", tableName: "NativeHomeReturn")
        case .cooldown: return Text("homeReturn.failure.cooldown", tableName: "NativeHomeReturn")
        case .versionConflict: return Text("homeReturn.decision.versionConflict", tableName: "NativeHomeReturn")
        }
    }
}

/// Fixture injection retained; the normal Account route uses NativeHomeReturnSelectionCoordinator.
private struct NativeHomeReturnCoordinatorKey: EnvironmentKey {
    static let defaultValue: NativeHomeReturnCoordinator? = nil
}
extension EnvironmentValues {
    var nativeHomeReturnCoordinator: NativeHomeReturnCoordinator? {
        get { self[NativeHomeReturnCoordinatorKey.self] }
        set { self[NativeHomeReturnCoordinatorKey.self] = newValue }
    }
}
