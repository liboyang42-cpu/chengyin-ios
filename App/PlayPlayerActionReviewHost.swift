import SwiftUI
import UIKit

@MainActor final class PlayPlayerActionReviewController: ObservableObject {
    struct Ticket { fileprivate let visit: UUID; fileprivate let context: PlayPlayerActionReviewContext }
    struct Review: Identifiable {
        var id: UUID { value.id }
        let value: PlayPlayerActionReviewValue
        fileprivate let visit: UUID
    }
    struct Claim { fileprivate let review: Review }
    let model: PlayPlayerGameCoordinator
    @Published private(set) var review: Review?
    @Published private(set) var working = false
    @Published private(set) var issue: PlayExperienceError?
    @Published private var drafts: [Int: String] = [:]
    @Published private var lifecycleRevision = 0
    private var visible = false, active = false
    private var visit = UUID()
    private var claimed: UUID?
    private weak var root: PlayPlayerActionRootController?
    init(model: PlayPlayerGameCoordinator) { self.model = model }
    private var current: Bool { visible && active && root?.isActuallyLeaving == false && model.hasCurrentProjection }
    var canInteract: Bool { current && model.phase == "ready" && model.pending == nil && review == nil && !working }
    func appear(active: Bool) { visible = true; self.active = active; lifecycleRevision += 1 }
    func sceneChanged(active: Bool) { self.active = active; lifecycleRevision += 1 }
    func background() { clearVisit(); active = false }
    func retire() { visible = false; active = false; clearVisit() }
    private func clearVisit() { visit = UUID(); claimed = nil; review = nil; drafts = [:]; issue = nil; working = false; lifecycleRevision += 1 }
    func attach(_ root: PlayPlayerActionRootController) { self.root = root }
    func detached(_ root: PlayPlayerActionRootController) { guard self.root === root else { return }; self.root = nil; retire() }
    func departed(_ root: PlayPlayerActionRootController) { guard self.root === root, root.isActuallyLeaving else { return }; retire() }
    func disappear() { guard root?.isActuallyLeaving != false else { return }; retire() }
    func capture() -> Ticket? {
        guard canInteract, let context = try? model.capturePlayerActionReview() else { return nil }
        return .init(visit: visit, context: context)
    }
    func text(nodeID: Int) -> String { current ? drafts[nodeID] ?? "" : "" }
    func setText(_ text: String, nodeID: Int, ticket: Ticket?) {
        guard accepts(ticket), model.projection?.nodes.contains(where: { $0.id == nodeID && $0.task["inputType"].text == "TEXT" }) == true else { return }
        drafts[nodeID] = text
    }
    private func accepts(_ ticket: Ticket?) -> Bool {
        guard canInteract, let ticket else { return false }
        return visit == ticket.visit && model.acceptsPlayerActionReview(ticket.context)
    }
    func prepare(_ intent: PlayPlayerReviewIntent, ticket: Ticket?) {
        guard accepts(ticket), let ticket else { return }
        do { review = .init(value: try model.preparePlayerActionReview(ticket.context, intent: intent), visit: visit); issue = nil }
        catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
    func canConfirm(_ offered: Review) -> Bool {
        current && !working && review?.id == offered.id && visit == offered.visit && model.acceptsPlayerActionReview(offered.value)
    }
    func cancel(_ offered: Review) { guard review?.id == offered.id else { return }; review = nil }
    func claim(_ offered: Review) -> Claim? {
        guard canConfirm(offered) else { return nil }
        claimed = offered.id; working = true; review = nil; return .init(review: offered)
    }
    func execute(_ claim: Claim) async {
        let offered = claim.review
        guard claimed == offered.id, working, current, visit == offered.visit, !Task.isCancelled,
              model.acceptsPlayerActionReview(offered.value) else {
            if claimed == offered.id { claimed = nil; working = false; issue = .staleSession }; return
        }
        claimed = nil
        defer { if visit == offered.visit { working = false } }
        await model.submitPlayerActionReview(offered.value)
    }
}

@MainActor struct PlayPlayerActionReviewCard: View {
    @ObservedObject var owner: PlayPlayerActionReviewController
    let offered: PlayPlayerActionReviewController.Review
    @Environment(\.locale) private var locale
    var body: some View {
        Section {
            if owner.canConfirm(offered) {
                Text(verbatim: localized(actionKey)).font(.headline)
                if let title = offered.value.title { Text(verbatim: title) }
                if let question = offered.value.question { Text(verbatim: question) }
                if let detail = offered.value.detail { Text(verbatim: detail).textSelection(.enabled).accessibilityIdentifier("playx.player.review.detail") }
                if let level = offered.value.hintLevel { LabeledContent { Text(level, format: .number) } label: { Text(verbatim: localized("level")) } }
                if let impact = offered.value.consequence { Text(verbatim: impact).accessibilityIdentifier("playx.player.review.consequence") }
                Text(verbatim: localized("authority")).font(.footnote)
                Button {
                    guard let claim = owner.claim(offered) else { return }
                    Task { await owner.execute(claim) }
                } label: { Text(verbatim: localized("confirm")) }
                    .accessibilityIdentifier("playx.player.review.confirm")
            } else { Text(verbatim: localized("expired")) }
            Button { owner.cancel(offered) } label: { Text(verbatim: localized("cancel")) }
                .accessibilityIdentifier("playx.player.review.cancel")
        } header: { Text(verbatim: localized("title")) }
    }
    private var actionKey: String {
        switch offered.value.command.action { case .confirmRole: return "role"; case .submit: return "text"; case .choice: return "choice"; case .hint: return "hint"; case .reveal: return "reveal" }
    }
    private func localized(_ key: String) -> String { String(localized: LocalizedStringResource(String.LocalizationValue(key), table: "PlayPlayerActionReview", locale: locale)) }
}

@MainActor struct PlayPlayerActionRoot: UIViewControllerRepresentable {
    let owner: PlayPlayerActionReviewController
    func makeUIViewController(context: Context) -> PlayPlayerActionRootController { let root = PlayPlayerActionRootController(owner: owner); owner.attach(root); return root }
    func updateUIViewController(_ root: PlayPlayerActionRootController, context: Context) {}
    static func dismantleUIViewController(_ root: PlayPlayerActionRootController, coordinator: ()) { root.owner?.detached(root) }
}
@MainActor final class PlayPlayerActionRootController: UIViewController {
    weak var owner: PlayPlayerActionReviewController?
    init(owner: PlayPlayerActionReviewController) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { return nil }
    var isActuallyLeaving: Bool {
        guard parent != nil else { return true }
        var item: UIViewController? = self; var attached = false
        while let current = item {
            if current.isBeingDismissed || current.isMovingFromParent { return true }
            if let navigation = current.navigationController, navigation.topViewController !== current,
               navigation.viewControllers.contains(where: { $0 === current }) { return true }
            if let tabs = current.tabBarController, tabs.selectedViewController !== current,
               tabs.viewControllers?.contains(where: { $0 === current }) == true { return true }
            attached = attached || current.viewIfLoaded?.window != nil || current.presentedViewController?.viewIfLoaded?.window != nil
            item = current.parent
        }
        return !attached
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); owner?.departed(self)
        Task { @MainActor [weak self] in guard let self else { return }; self.owner?.departed(self) }
    }
}
