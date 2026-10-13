import SwiftUI
import UIKit

/// Frozen memory-only input for one exact normal task and one visible visit.
/// It is never persisted, logged, or used to infer a successful answer.
struct PlayAnswerReview: Identifiable, Equatable {
    let id: UUID
    let visit: UUID
    let generation: UInt64
    let identity: PlayReadIdentity
    let snapshot: PlaySnapshot
    let nodeID: Int
    let question: String
    let answer: String
    let displayAnswer: String
}

@MainActor struct PlayAnswerReviewSheet: View {
    let review: PlayAnswerReview
    let isCurrent: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        NavigationStack {
            Form {
                if isCurrent {
                    Section { Text(verbatim: review.question).fixedSize(horizontal: false, vertical: true) }
                    Section {
                        Text(verbatim: review.displayAnswer).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("play.answer.review.value")
                    } header: { Text(verbatim: localized("answer")) }
                    Text(verbatim: localized("detail")).font(.footnote)
                    Button(action: confirm) { Text(verbatim: localized("confirm")) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("play.answer.review.confirm")
                } else {
                    Text(verbatim: localized("expired")).accessibilityIdentifier("play.answer.review.expired")
                }
            }.navigationTitle(Text(verbatim: localized("title")))
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) { Text(verbatim: localized("cancel")) }
                        .accessibilityIdentifier("play.answer.review.cancel")
                } }
        }.privacySensitive()
    }
    private func localized(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(key), table: "PlayAnswerReview", locale: locale))
    }
}

/// One stable screen owner. A concrete review gets its own presenter only after it exists.
@MainActor final class PlayAnswerReviewPresentation: ObservableObject {
    let model: PlayViewModel
    @Published private(set) var review: PlayAnswerReview?
    @Published private var showing = false
    @Published private var lifecycleRevision = 0
    struct Ticket {
        fileprivate let visit: UUID
        fileprivate let generation: UInt64
        fileprivate let snapshot: PlaySnapshot
        fileprivate let nodeID: Int
    }
    var hasVisibleVisit: Bool { visible && visit != nil }
    private var visit: UUID?
    private var visible = false
    private var active = false
    private var claimedID: UUID?
    private weak var root: PlayAnswerReviewRootController?
    init(model: PlayViewModel) { self.model = model }
    private var attached: Bool { root?.parent != nil && root?.isActuallyLeaving == false }
    func attach(_ root: PlayAnswerReviewRootController) { self.root = root }
    func nativeDisappeared(_ root: PlayAnswerReviewRootController) {
        guard self.root === root, root.isActuallyLeaving else { return }
        visible = false; retire()
    }
    func detach(_ root: PlayAnswerReviewRootController) {
        guard self.root === root else { return }
        self.root = nil; visible = false; retire()
    }
    func appear(active: Bool) {
        visible = true; self.active = active
        if active, visit == nil { visit = model.beginAnswerVisit() }
        lifecycleRevision += 1
    }
    /// A sheet can cover the source without leaving this task. Actual removal is also
    /// fenced synchronously by the native parent chain and, finally, root dismantling.
    func disappear() {
        if review != nil, attached { return }
        visible = false; retire()
    }
    func sceneChanged(active: Bool) {
        self.active = active
        if !active { retire() }
        else if visible, visit == nil { visit = model.beginAnswerVisit() }
    }
    func reset() { retire(); if visible, active { visit = model.beginAnswerVisit() } }
    private func retire() {
        model.endAnswerVisit(visit); visit = nil; review = nil; showing = false; claimedID = nil
    }
    func capture(nodeID: Int) -> Ticket? {
        guard visible, active, attached, review == nil, let visit,
              let generation = model.answerReviewGeneration(visit: visit), let snapshot = model.visibleSnapshot else { return nil }
        return Ticket(visit: visit, generation: generation, snapshot: snapshot, nodeID: nodeID)
    }
    func prepare(answer: String, offered: Ticket?) throws {
        guard let offered, visible, active, attached, review == nil, visit == offered.visit,
              model.answerReviewGeneration(visit: offered.visit) == offered.generation,
              model.visibleSnapshot == offered.snapshot else { throw APIError.invalidRequest }
        review = try model.prepareAnswerReview(nodeID: offered.nodeID, answer: answer, visit: offered.visit)
        showing = true
    }
    var readGeneration: UInt64? { visit.flatMap { model.answerReviewGeneration(visit: $0) } }
    func discardInvalidUnclaimedReview() {
        guard showing, let offered = review, claimedID == nil, !model.canConfirmAnswerReview(offered) else { return }
        model.cancelAnswerReview(offered); review = nil; showing = false
    }
    func isCurrent(_ offered: PlayAnswerReview) -> Bool {
        visible && active && attached && review?.id == offered.id && visit == offered.visit && model.canConfirmAnswerReview(offered)
    }
    func isPresented(_ offered: PlayAnswerReview) -> Bool { showing && isCurrent(offered) }
    func cancel(_ offered: PlayAnswerReview) {
        guard review?.id == offered.id else { return }
        model.cancelAnswerReview(offered); showing = false
    }
    func dismissed(_ offered: PlayAnswerReview) {
        guard review?.id == offered.id else { return }
        model.cancelAnswerReview(offered); review = nil; showing = false
    }
    func confirm(_ offered: PlayAnswerReview) -> Bool {
        guard isCurrent(offered), model.confirmAnswerReview(offered) else { return false }
        claimedID = offered.id; showing = false; return true
    }
    func sendClaimed(_ offered: PlayAnswerReview) async {
        guard claimedID == offered.id, visible, active, attached, visit == offered.visit else { return }
        claimedID = nil
        await model.submit(offered)
    }
}

@MainActor struct PlayAnswerReviewPresenter: View {
    @ObservedObject var owner: PlayAnswerReviewPresentation
    let offered: PlayAnswerReview
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: Binding(get: { owner.isPresented(offered) }, set: { if !$0 { owner.cancel(offered) } }),
                   onDismiss: { owner.dismissed(offered) }) {
                PlayAnswerReviewSheet(review: offered, isCurrent: owner.isCurrent(offered), confirm: {
                    guard owner.confirm(offered) else { return }
                    Task { await owner.sendClaimed(offered) }
                }, cancel: { owner.cancel(offered) })
            }
    }
}

@MainActor struct PlayAnswerReviewRoot: UIViewControllerRepresentable {
    let owner: PlayAnswerReviewPresentation
    func makeUIViewController(context: Context) -> PlayAnswerReviewRootController {
        let root = PlayAnswerReviewRootController(owner: owner); owner.attach(root); return root
    }
    func updateUIViewController(_ root: PlayAnswerReviewRootController, context: Context) {}
    static func dismantleUIViewController(_ root: PlayAnswerReviewRootController, coordinator: ()) { root.owner?.detach(root) }
}
@MainActor final class PlayAnswerReviewRootController: UIViewController {
    weak var owner: PlayAnswerReviewPresentation?
    init(owner: PlayAnswerReviewPresentation) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { return nil }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        owner?.nativeDisappeared(self)
        Task { @MainActor [weak self] in
            guard let self else { return }; self.owner?.nativeDisappeared(self)
        }
    }
    var isActuallyLeaving: Bool {
        var item: UIViewController? = self
        var attachedWindow = false
        while let current = item {
            if current.isBeingDismissed || current.isMovingFromParent { return true }
            if let navigation = current.navigationController, navigation.topViewController !== current,
               navigation.viewControllers.contains(where: { $0 === current }) { return true }
            if let tabs = current.tabBarController, tabs.selectedViewController !== current,
               tabs.viewControllers?.contains(where: { $0 === current }) == true { return true }
            attachedWindow = attachedWindow || current.viewIfLoaded?.window != nil || current.presentedViewController?.viewIfLoaded?.window != nil
            item = current.parent
        }
        return !attachedWindow
    }
}
