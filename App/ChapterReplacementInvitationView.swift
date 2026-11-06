import SwiftUI

/// C9 host-side replacement-invitation screen (exclusive module).
/// Flow: own topic -> withdrawn-supply vacancy -> invitable candidates (location
/// optional) -> impact review -> one invite -> exact-tuple readback -> vacancy refresh.
/// It contains no accept/supply/payment/refund actions and no inbox aggregation.
@MainActor
final class ChapterReplacementInvitationViewModel: ObservableObject {
    @Published private(set) var phase: ChapterReplacementInvitationCoordinator.Phase = .idle
    @Published private(set) var vacancies: [ChapterReplacementInvitationVacancy] = []
    @Published private(set) var candidates: [ChapterReplacementInvitationCandidate] = []
    @Published private(set) var selectedVacancy: ChapterReplacementInvitationVacancy?
    @Published var message = ""

    private let coordinator: ChapterReplacementInvitationCoordinator
    private let topicID: Int
    private let actorAccountID: Int
    private let scope: ChapterReplacementInvitationScope
    private let merchantAccess: MerchantAccess?
    /// Nil when the caller has no approved fresh topic-publisher read. Never synthesized here.
    private let publisherProof: ChapterReplacementInvitationPublisherProof?

    init(coordinator: ChapterReplacementInvitationCoordinator, topicID: Int, actorAccountID: Int,
         scope: ChapterReplacementInvitationScope, merchantAccess: MerchantAccess?, publisherProof: ChapterReplacementInvitationPublisherProof?) {
        self.coordinator = coordinator
        self.topicID = topicID; self.actorAccountID = actorAccountID
        self.scope = scope; self.merchantAccess = merchantAccess
        self.publisherProof = publisherProof
    }

    private func sync() {
        phase = coordinator.phase
        vacancies = coordinator.vacancies
        candidates = coordinator.candidates
        selectedVacancy = coordinator.selectedVacancy
    }

    func load() async {
        coordinator.begin(topicID: topicID, actorAccountID: actorAccountID)
        await coordinator.loadVacancies()
        sync()
    }

    func select(_ vacancy: ChapterReplacementInvitationVacancy, coordinates: ChapterReplacementInvitationCoordinates?) async {
        await coordinator.loadCandidates(for: vacancy, coordinates: coordinates)
        sync()
    }

    func prepare(_ candidate: ChapterReplacementInvitationCandidate) async {
        await coordinator.prepare(candidate: candidate, scope: scope, merchantAccess: merchantAccess,
                                  publisherProof: publisherProof, message: message)
        sync()
    }

    func confirm() async { await coordinator.confirmSend(); sync() }
    func verifyUnknown() async { await coordinator.verifyUnknown(); sync() }
    func cancelReview() { coordinator.cancelReview(); sync() }
}

/// Loads the host's fresh topic-publisher proof before showing the C9 screen.
/// A nil proof is passed through; the coordinator then refuses the invite.
@MainActor struct ChapterReplacementInvitationEntry: View {
    let context: MerchantChapterReplacementHostContext
    let topicID: Int
    let merchantAccess: MerchantAccess?
    @State private var model: ChapterReplacementInvitationViewModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model {
                ChapterReplacementInvitationView(model: model, coordinates: context.coordinates)
            } else if unavailable {
                Text("chapterReplacement.section.failed")
                    .accessibilityIdentifier("chapterReplacement.failed")
            } else {
                ProgressView().task { await resolve() }
            }
        }
    }

    private func resolve() async {
        let proof = await context.loadPublisherProof(topicID)
        guard !Task.isCancelled, let effects = context.makeEffects(proof) else { unavailable = true; return }
        model = .init(coordinator: .init(effects: effects), topicID: topicID, actorAccountID: context.actorAccountID,
            scope: context.scope, merchantAccess: merchantAccess ?? context.merchantAccess, publisherProof: proof)
    }
}

struct ChapterReplacementInvitationView: View {
    @StateObject private var model: ChapterReplacementInvitationViewModel
    /// Supplied by the host shell; `nil` means location was refused and candidates
    /// must still be queried by topic alone.
    let coordinates: ChapterReplacementInvitationCoordinates?

    init(model: ChapterReplacementInvitationViewModel, coordinates: ChapterReplacementInvitationCoordinates? = nil) {
        _model = StateObject(wrappedValue: model)
        self.coordinates = coordinates
    }

    var body: some View {
        List {
            Section {
                Text("chapterReplacement.intro")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("chapterReplacement.section.vacancies") {
                if model.vacancies.isEmpty {
                    Text("chapterReplacement.vacancies.empty").foregroundStyle(.secondary)
                }
                ForEach(model.vacancies) { vacancy in
                    Button {
                        Task { await model.select(vacancy, coordinates: coordinates) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("chapterReplacement.vacancy.row \(vacancy.chapterID) \(vacancy.offerID)")
                            Text(verbatim: vacancy.withdrawReason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("chapterReplacement.vacancy.\(vacancy.offerID)")
                }
            }
            if model.selectedVacancy != nil {
                Section("chapterReplacement.section.candidates") {
                    if model.candidates.isEmpty {
                        Text("chapterReplacement.candidates.empty").foregroundStyle(.secondary)
                    }
                    ForEach(model.candidates) { candidate in
                        Button {
                            Task { await model.prepare(candidate) }
                        } label: {
                            if let name = candidate.displayName {
                                Text(verbatim: name)
                            } else {
                                Text("chapterReplacement.candidate.member \(candidate.merchantMemberID)")
                            }
                        }
                        .accessibilityIdentifier("chapterReplacement.candidate.\(candidate.id)")
                    }
                }
                Section("chapterReplacement.section.message") {
                    TextField(text: $model.message, prompt: Text("chapterReplacement.message.prompt")) {
                        Text("chapterReplacement.message.label")
                    }
                    .accessibilityIdentifier("chapterReplacement.message")
                }
            }
            statusSection
        }
        .appNavigationTitle("chapterReplacement.title")
        .task { await model.load() }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.phase {
        case .reviewing(let plan):
            Section("chapterReplacement.section.review") {
                Text("chapterReplacement.review.invite \(plan.candidate.merchantMemberID) \(plan.candidate.chapterID) \(plan.candidate.replacementOfOfferID)")
                Text("chapterReplacement.review.pendingOnly").font(.footnote).foregroundStyle(.secondary)
                Button("chapterReplacement.send") { Task { await model.confirm() } }
                    .accessibilityIdentifier("chapterReplacement.send")
                Button("action.cancel", role: .cancel) { model.cancelReview() }
            }
        case .sending:
            Section { ProgressView().accessibilityIdentifier("chapterReplacement.sending") }
        case .unknown(let plan):
            Section("chapterReplacement.section.unknown") {
                Text("chapterReplacement.unknown \(plan.targetTuple)")
                    .font(.footnote)
                Button("chapterReplacement.verify") { Task { await model.verifyUnknown() } }
                    .accessibilityIdentifier("chapterReplacement.verifyUnknown")
            }
        case .verified(let verified):
            Section("chapterReplacement.section.verified") {
                Group {
                    if let applicationID = verified.applicationID {
                        Text("chapterReplacement.verified.application \(applicationID)")
                    } else {
                        Text("chapterReplacement.verified")
                    }
                }
                .accessibilityIdentifier("chapterReplacement.verified")
            }
        case .failed(let failure):
            Section("chapterReplacement.section.failed") {
                Text(verbatim: String(describing: failure)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("chapterReplacement.failed")
            }
        default:
            EmptyView()
        }
    }
}
