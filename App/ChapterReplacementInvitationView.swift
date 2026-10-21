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
    private let topicPublisherVerified: Bool

    init(coordinator: ChapterReplacementInvitationCoordinator, topicID: Int, actorAccountID: Int,
         scope: ChapterReplacementInvitationScope, merchantAccess: MerchantAccess?, topicPublisherVerified: Bool) {
        self.coordinator = coordinator
        self.topicID = topicID; self.actorAccountID = actorAccountID
        self.scope = scope; self.merchantAccess = merchantAccess
        self.topicPublisherVerified = topicPublisherVerified
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
                                  topicPublisherVerified: topicPublisherVerified, message: message)
        sync()
    }

    func confirm() async { await coordinator.confirmSend(); sync() }
    func verifyUnknown() async { await coordinator.verifyUnknown(); sync() }
    func cancelReview() { coordinator.cancelReview(); sync() }
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
                Text(verbatim: "为已退出供给的章节补位。邀请成功仅生成待处理邀请，不会自动接受、补位上架或涉及付款退款。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("已退出供给 / 缺位") {
                if model.vacancies.isEmpty {
                    Text(verbatim: "暂无可补位缺位").foregroundStyle(.secondary)
                }
                ForEach(model.vacancies) { vacancy in
                    Button {
                        Task { await model.select(vacancy, coordinates: coordinates) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: "章节 \(vacancy.chapterID) · 原供给 \(vacancy.offerID)")
                            Text(verbatim: vacancy.withdrawReason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("chapterReplacement.vacancy.\(vacancy.offerID)")
                }
            }
            if model.selectedVacancy != nil {
                Section("可补位候选") {
                    if model.candidates.isEmpty {
                        Text(verbatim: "暂无可邀请候选").foregroundStyle(.secondary)
                    }
                    ForEach(model.candidates) { candidate in
                        Button {
                            Task { await model.prepare(candidate) }
                        } label: {
                            Text(verbatim: candidate.displayName ?? "商家成员 \(candidate.merchantMemberID)")
                        }
                        .accessibilityIdentifier("chapterReplacement.candidate.\(candidate.id)")
                    }
                }
                Section("邀请留言（可选）") {
                    TextField(text: $model.message, prompt: Text(verbatim: "留言")) { Text(verbatim: "留言") }
                        .accessibilityIdentifier("chapterReplacement.message")
                }
            }
            statusSection
        }
        .navigationTitle(Text(verbatim: "章节补位邀约"))
        .task { await model.load() }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.phase {
        case .reviewing(let plan):
            Section("影响复核") {
                Text(verbatim: "将邀请成员 \(plan.candidate.merchantMemberID) 补位章节 \(plan.candidate.chapterID)，原供给 \(plan.candidate.replacementOfOfferID)。")
                Text(verbatim: "发送后仅生成待处理邀请（PENDING），不会自动接受或填补供给。").font(.footnote).foregroundStyle(.secondary)
                Button("发送补位邀请") { Task { await model.confirm() } }
                    .accessibilityIdentifier("chapterReplacement.send")
                Button("取消", role: .cancel) { model.cancelReview() }
            }
        case .sending:
            Section { ProgressView().accessibilityIdentifier("chapterReplacement.sending") }
        case .unknown(let plan):
            Section("结果待核实") {
                Text(verbatim: "已发送请求但未取得确切结果（\(plan.targetTuple)）。请勿重复发送，只能按完整目标回读核实。")
                    .font(.footnote)
                Button("按完整目标回读核实") { Task { await model.verifyUnknown() } }
                    .accessibilityIdentifier("chapterReplacement.verifyUnknown")
            }
        case .verified(let verified):
            Section("已核实") {
                Text(verbatim: "补位邀请已回读确认（状态 PENDING\(verified.applicationID.map { "，申请 \($0)" } ?? "")）。")
                    .accessibilityIdentifier("chapterReplacement.verified")
            }
        case .failed(let failure):
            Section("无法继续") {
                Text(verbatim: String(describing: failure)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("chapterReplacement.failed")
            }
        default:
            EmptyView()
        }
    }
}
