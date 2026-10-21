import SwiftUI

/// W19 manual "I'm back" check on the private-home page. Production passes no model
/// (no reviewed endpoint, `homeReturnRestore` OFF) and shows that restore is not enabled.
/// The home point is never displayed here; only resource facts and decisions are.
struct HomeReturnSection: View {
    let model: HomeReturnCoordinator?
    let home: PrivateHomeSnapshot?
    var body: some View {
        Section {
            if let model { content(model) }
            else {
                Text("homeReturn.notEnabled", tableName: "CityGame").font(.footnote).accessibilityIdentifier("homeReturn.notEnabled")
            }
        } header: { Text("homeReturn.title", tableName: "CityGame") }
        .task { await model?.load() }
    }

    @ViewBuilder private func content(_ model: HomeReturnCoordinator) -> some View {
        phaseText(model.phase).font(.footnote).accessibilityIdentifier("homeReturn.phase")
        Text("homeReturn.manual", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true)
        if let account = model.account {
            LabeledContent { Text(verbatim: "\(account.current) / \(account.maximum)") } label: { scopeText(model.scope) }
                .accessibilityIdentifier("homeReturn.account")
        } else if model.phase == .unavailable {
            Text("homeReturn.unavailable", tableName: "CityGame").font(.footnote)
        }
        if let failure = model.failure { failureText(failure).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeReturn.failure") }
        if let decision = model.decision { decisionText(decision).accessibilityIdentifier("homeReturn.decision") }
        if model.noReceiptYet { Text("homeReturn.noReceiptYet", tableName: "CityGame").font(.footnote) }
        if model.isBusy { ProgressView() }
        if home?.status != .active, model.phase == .ready {
            Text("homeReturn.needHome", tableName: "CityGame").font(.footnote).accessibilityIdentifier("homeReturn.needHome")
        }
        if model.canCheckIn, home?.status == .active {
            Button { Task { await model.checkIn(home: home) } } label: { Text("homeReturn.checkIn", tableName: "CityGame") }
                .accessibilityIdentifier("homeReturn.checkIn")
        }
        if model.phase == .unknown {
            Text("homeReturn.unknown", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true)
            Button { Task { await model.readBack() } } label: { Text("homeReturn.readBack", tableName: "CityGame") }
                .accessibilityIdentifier("homeReturn.readBack")
            if model.canRetryExact {
                Button { Task { await model.retryExact() } } label: { Text("homeReturn.retry", tableName: "CityGame") }
                    .accessibilityIdentifier("homeReturn.retry")
            }
        }
        if model.phase == .unavailable || model.phase == .ready {
            Button { Task { await model.load() } } label: { Text("homeReturn.refresh", tableName: "CityGame") }
                .accessibilityIdentifier("homeReturn.refresh")
        }
    }

    private func phaseText(_ phase: HomeReturnCoordinator.Phase) -> Text {
        switch phase {
        case .disabled: return Text("homeReturn.phase.disabled", tableName: "CityGame")
        case .idle, .ready: return Text("homeReturn.phase.ready", tableName: "CityGame")
        case .loading: return Text("homeReturn.phase.loading", tableName: "CityGame")
        case .unavailable: return Text("homeReturn.phase.unavailable", tableName: "CityGame")
        case .checking: return Text("homeReturn.phase.checking", tableName: "CityGame")
        case .restoring: return Text("homeReturn.phase.restoring", tableName: "CityGame")
        case .unknown: return Text("homeReturn.phase.unknown", tableName: "CityGame")
        case .invalidated: return Text("homeReturn.phase.invalidated", tableName: "CityGame")
        }
    }

    private func scopeText(_ scope: HomeResourceScope) -> Text {
        switch scope {
        case .global: return Text("homeReturn.scope.global", tableName: "CityGame")
        case .run: return Text("homeReturn.scope.run", tableName: "CityGame")
        case .theme: return Text("homeReturn.scope.theme", tableName: "CityGame")
        }
    }

    private func failureText(_ failure: HomeReturnFailure) -> Text {
        switch failure {
        case .disabled: return Text("homeReturn.phase.disabled", tableName: "CityGame")
        case .locationOff: return Text("homeReturn.failure.locationOff", tableName: "CityGame")
        case .permissionDenied: return Text("homeReturn.failure.permissionDenied", tableName: "CityGame")
        case .lowAccuracy: return Text("homeReturn.failure.lowAccuracy", tableName: "CityGame")
        case .staleFix: return Text("homeReturn.failure.staleFix", tableName: "CityGame")
        case .cooldown(let seconds):
            return Text("homeReturn.failure.cooldown", tableName: "CityGame") + Text(verbatim: " (\(seconds)s)")
        case .outOfRadius: return Text("homeReturn.failure.outOfRadius", tableName: "CityGame")
        case .homeChanged: return Text("homeReturn.failure.homeChanged", tableName: "CityGame")
        case .proofExpired: return Text("homeReturn.failure.proofExpired", tableName: "CityGame")
        case .noHome: return Text("homeReturn.needHome", tableName: "CityGame")
        case .network: return Text("homeReturn.failure.network", tableName: "CityGame")
        case .unknown: return Text("homeReturn.unknown", tableName: "CityGame")
        case .invalid: return Text("homeReturn.failure.invalid", tableName: "CityGame")
        }
    }

    private func decisionText(_ decision: HomeRestoreReceipt.Decision) -> Text {
        switch decision {
        case .restored: return Text("homeReturn.decision.restored", tableName: "CityGame")
        case .alreadyAtMax: return Text("homeReturn.decision.alreadyAtMax", tableName: "CityGame")
        case .proofConsumed: return Text("homeReturn.decision.proofConsumed", tableName: "CityGame")
        case .staleHome: return Text("homeReturn.failure.homeChanged", tableName: "CityGame")
        case .proofExpired: return Text("homeReturn.failure.proofExpired", tableName: "CityGame")
        case .cooldown: return Text("homeReturn.failure.cooldown", tableName: "CityGame")
        case .versionConflict: return Text("homeReturn.decision.versionConflict", tableName: "CityGame")
        }
    }
}

/// W19 restore model for the private-home page. Unset (nil) in production builds.
private struct HomeReturnCoordinatorKey: EnvironmentKey {
    static let defaultValue: HomeReturnCoordinator? = nil
}
extension EnvironmentValues {
    var homeReturnCoordinator: HomeReturnCoordinator? {
        get { self[HomeReturnCoordinatorKey.self] }
        set { self[HomeReturnCoordinatorKey.self] = newValue }
    }
}
