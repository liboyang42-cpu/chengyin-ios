import SwiftUI

/// App-side observable wrapper around the Core coordinator, which stays
/// free of SwiftUI/Combine.
@MainActor final class MerchantOfferWithdrawalModel: ObservableObject {
    let coordinator: MerchantOfferWithdrawalCoordinator
    @Published private(set) var phase: MerchantOfferWithdrawalCoordinator.Phase = .idle
    @Published private(set) var busy = false
    init(coordinator: MerchantOfferWithdrawalCoordinator) {
        self.coordinator = coordinator
        phase = coordinator.phase
    }
    var permitsSubmission: Bool { coordinator.permitsSubmission }
    private func sync() { phase = coordinator.phase; busy = coordinator.busy }
    @discardableResult
    func prepare(subject: MerchantOfferWithdrawalSubject, rawReason: String) -> MerchantOfferWithdrawalReview? {
        defer { sync() }
        return coordinator.prepare(subject: subject, rawReason: rawReason)
    }
    func confirm(_ review: MerchantOfferWithdrawalReview) async {
        busy = true
        await coordinator.confirm(review)
        sync()
    }
    func reconcileUnknown(offerID: Int, requestedReason: String?) async {
        busy = true
        await coordinator.reconcileUnknown(offerID: offerID, requestedReason: requestedReason)
        sync()
    }
    func consumeConfirmedOfferID() -> Int? {
        defer { sync() }
        return coordinator.consumeConfirmedOfferID()
    }
}

/// C8 entry: one's own chapter-supply detail → eligibility / impact / reason
/// → confirmation → withdrawal → `mine` readback by the original offerId →
/// return sync (the host reloads `mine` from `onReturnSync`).
/// Submission stays disabled until the integration owner injects a permitted
/// executor through the shared wiring; this view never submits by itself.
@MainActor struct MerchantOfferWithdrawalView: View {
    let subject: MerchantOfferWithdrawalSubject
    @StateObject private var model: MerchantOfferWithdrawalModel
    /// Called once with the original offerId after a confirmed readback, so
    /// the host can reload `mine` and pop back with synchronised state.
    var onReturnSync: ((Int) -> Void)? = nil

    @State private var reason = ""
    @State private var showingConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(subject: MerchantOfferWithdrawalSubject,
         coordinator: MerchantOfferWithdrawalCoordinator,
         onReturnSync: ((Int) -> Void)? = nil) {
        self.subject = subject
        _model = StateObject(wrappedValue: MerchantOfferWithdrawalModel(coordinator: coordinator))
        self.onReturnSync = onReturnSync
    }

    private var reasonLength: Int { MerchantOfferWithdrawalReason.length(of: reason) }
    private var reasonValid: Bool { MerchantOfferWithdrawalReason.isValid(raw: reason) }

    var body: some View {
        Form {
            Section {
                LabeledContent("merchant.offerWithdrawal.field.offerId",
                               value: subject.offerID.map(String.init) ?? "—")
                if let chapter = subject.chapterName {
                    LabeledContent("merchant.offerWithdrawal.field.chapter", value: chapter)
                }
                if let topic = subject.topicName {
                    LabeledContent("merchant.offerWithdrawal.field.topic", value: topic)
                }
            } header: { Text("merchant.offerWithdrawal.detail") }

            eligibilitySection
            impactSection

            if subject.isEligible {
                Section {
                    TextField("merchant.offerWithdrawal.reason.placeholder", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("merchant.offerWithdrawal.reason")
                    Text(verbatim: "\(reasonLength)/\(MerchantOfferWithdrawalReason.maximumLength)")
                        .font(.caption).foregroundStyle(reasonValid || reason.isEmpty ? .secondary : .red)
                } header: { Text("merchant.offerWithdrawal.reason") }
            }

            actionSection
        }
        .appNavigationTitle("merchant.offerWithdrawal.title")
        .confirmationDialog("merchant.offerWithdrawal.confirm.title", isPresented: $showingConfirmation) {
            Button("merchant.offerWithdrawal.confirm.action", role: .destructive) {
                if let review = model.coordinator.review ?? model.prepare(subject: subject, rawReason: reason) {
                    Task { await model.confirm(review); handleConfirmed() }
                }
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("merchant.offerWithdrawal.confirm.message")
        }
    }

    private func handleConfirmed() {
        if case .confirmed = model.phase, let offerID = model.consumeConfirmedOfferID() {
            onReturnSync?(offerID)
            dismiss()
        }
    }

    @ViewBuilder private var eligibilitySection: some View {
        Section {
            switch model.phase {
            case .alreadyWithdrawn(let serverReason):
                Label("merchant.offerWithdrawal.state.withdrawn", systemImage: "checkmark.circle")
                if !serverReason.isEmpty {
                    LabeledContent("merchant.offerWithdrawal.field.serverReason", value: serverReason)
                }
            case .ineligible(let reason):
                Label(LocalizedStringKey(Self.ineligibilityKey(reason)), systemImage: "exclamationmark.triangle")
            default:
                if let ineligibility = subject.ineligibility {
                    if case .alreadyWithdrawn(let serverReason) = ineligibility {
                        Label("merchant.offerWithdrawal.state.withdrawn", systemImage: "checkmark.circle")
                        if !serverReason.isEmpty {
                            LabeledContent("merchant.offerWithdrawal.field.serverReason", value: serverReason)
                        }
                    } else {
                        Label(LocalizedStringKey(Self.ineligibilityKey(ineligibility)), systemImage: "exclamationmark.triangle")
                    }
                } else {
                    Label("merchant.offerWithdrawal.state.eligible", systemImage: "checkmark.circle")
                }
            }
        } header: { Text("merchant.offerWithdrawal.eligibility") }
    }

    /// The full impact disclosure. It must not be omitted or shortened to a
    /// generic "are you sure": no automatic refund or dissolution is implied.
    @ViewBuilder private var impactSection: some View {
        let impact = MerchantOfferWithdrawalImpact(subject: subject)
        Section {
            if impact.mayPauseNewEnrolment {
                Label("merchant.offerWithdrawal.impact.mayPauseEnrolment", systemImage: "pause.circle")
            }
            Label("merchant.offerWithdrawal.impact.retainsOrders", systemImage: "doc.text")
            Label("merchant.offerWithdrawal.impact.noAutoRefund", systemImage: "arrow.uturn.backward.circle")
            if impact.mayInvalidateSupplyReviewAndPublication {
                Label("merchant.offerWithdrawal.impact.mayInvalidateReview", systemImage: "eye.slash")
            }
            if impact.mayNotifyParticipantsAndOwner {
                Label("merchant.offerWithdrawal.impact.mayNotify", systemImage: "bell")
            }
        } header: { Text("merchant.offerWithdrawal.impact") }
    }

    @ViewBuilder private var actionSection: some View {
        Section {
            switch model.phase {
            case .confirmed(let serverReason, let matches, let hint):
                Label("merchant.offerWithdrawal.state.withdrawn", systemImage: "checkmark.circle.fill")
                LabeledContent("merchant.offerWithdrawal.field.serverReason", value: serverReason)
                if !matches {
                    Text("merchant.offerWithdrawal.result.reasonDiffers").font(.footnote)
                }
                if let hint {
                    Text(LocalizedStringKey(hint
                        ? "merchant.offerWithdrawal.result.enrollmentPausedHint"
                        : "merchant.offerWithdrawal.result.enrollmentNotPausedHint")).font(.footnote)
                }
                Text("merchant.offerWithdrawal.result.hintBoundary").font(.footnote).foregroundStyle(.secondary)
            case .unknown(let readback):
                Label("merchant.offerWithdrawal.state.unknown", systemImage: "questionmark.circle")
                if let readback { Text(verbatim: String(describing: readback)).font(.footnote) }
                Button("merchant.offerWithdrawal.action.readbackOnly") {
                    if let offerID = subject.offerID {
                        Task { await model.reconcileUnknown(offerID: offerID, requestedReason: reason); handleConfirmed() }
                    }
                }
                .accessibilityIdentifier("merchant.offerWithdrawal.readbackOnly")
                Text("merchant.offerWithdrawal.unknown.noResend").font(.footnote).foregroundStyle(.secondary)
            case .rejected(let message):
                Label("merchant.offerWithdrawal.state.rejected", systemImage: "xmark.circle")
                if let message { Text(verbatim: message).font(.footnote) }
            default:
                if subject.isEligible {
                    Button("merchant.offerWithdrawal.action.review", role: .destructive) {
                        guard model.prepare(subject: subject, rawReason: reason) != nil else { return }
                        showingConfirmation = true
                    }
                    .disabled(!reasonValid || model.busy || !model.permitsSubmission)
                    .accessibilityIdentifier("merchant.offerWithdrawal.review")
                    if !model.permitsSubmission {
                        Text("merchant.offerWithdrawal.disabled").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func ineligibilityKey(_ reason: MerchantOfferWithdrawalIneligibility) -> String {
        switch reason {
        case .alreadyWithdrawn: return "merchant.offerWithdrawal.state.withdrawn"
        case .deactivatedNotWithdrawn: return "merchant.offerWithdrawal.ineligible.deactivated"
        case .circleSupply: return "merchant.offerWithdrawal.ineligible.circle"
        case .notOrdinaryFreeExplore: return "merchant.offerWithdrawal.ineligible.notOrdinary"
        case .topicTerminal: return "merchant.offerWithdrawal.ineligible.terminal"
        case .missingOffer: return "merchant.offerWithdrawal.ineligible.missingOffer"
        case .stateUnconfirmed, .productUnconfirmed, .lifecycleUnconfirmed:
            return "merchant.offerWithdrawal.ineligible.unconfirmed"
        }
    }
}
