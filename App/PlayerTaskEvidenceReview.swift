import SwiftUI
import UIKit

@MainActor final class PlayerTaskEvidenceReviewController: ObservableObject {
    struct Review: Identifiable {
        enum Action { case upload; case submit(PlayerTaskEvidencePreparedReview) }
        let id = UUID()
        let visit: UUID
        let context: PlayerTaskEvidenceReviewContext
        let action: Action
        let scan: String?
        let photo: Data?
        let outputID: UUID?
    }
    struct Claim { fileprivate let review: Review }
    struct InputTicket {
        fileprivate let visit: UUID
        fileprivate let context: PlayerTaskEvidenceReviewContext
    }
    let target: PlayerTaskEvidenceTarget
    let player: PlayPlayerGameCoordinator
    let device: PlayDeviceCaptureCoordinator?
    @Published private(set) var review: Review?
    @Published private(set) var manualText = ""
    @Published private(set) var working = false
    @Published private(set) var issue: PlayExperienceError?
    @Published private var lifecycleRevision = 0
    private var visit = UUID()
    private var visible = false
    private var active = false
    private var claimed: UUID?
    private weak var root: PlayerTaskEvidenceRootController?
    init(target: PlayerTaskEvidenceTarget, player: PlayPlayerGameCoordinator, device: PlayDeviceCaptureCoordinator?) {
        self.target = target; self.player = player; self.device = device
    }
    var canInteract: Bool { visible && active && root?.isActuallyLeaving == false && player.acceptsEvidence(target) && review == nil && !working && device?.busy != true }
    func appear(active: Bool) { visible = true; self.active = active; lifecycleRevision += 1 }
    func sceneChanged(active: Bool) { self.active = active; lifecycleRevision += 1 }
    func attach(_ root: PlayerTaskEvidenceRootController) { self.root = root }
    func disappear() { if root?.isActuallyLeaving == false { return }; retire() }
    func departed(_ root: PlayerTaskEvidenceRootController) {
        guard self.root === root, root.isActuallyLeaving else { return }; retire()
    }
    func detached(_ root: PlayerTaskEvidenceRootController) { guard self.root === root else { return }; self.root = nil; retire() }
    func retire() {
        visible = false; active = false; visit = UUID(); review = nil; claimed = nil; working = false; issue = nil; manualText = ""; device?.cancel()
    }
    func captureInput() -> InputTicket? {
        guard canInteract, let context = try? player.captureEvidenceReview(target) else { return nil }
        return .init(visit: visit, context: context)
    }
    private func accepts(_ ticket: InputTicket?) -> Bool {
        guard let ticket else { return false }
        return canInteract && visit == ticket.visit && player.acceptsEvidenceReview(ticket.context)
    }
    func captureDevice(_ kind: PlayDeviceKind, library: Bool = false, offered: InputTicket?) async {
        guard !Task.isCancelled, accepts(offered), let offered, let device else { return }
        working = true
        defer { if visit == offered.visit { working = false } }
        await device.capture(kind, usePhotoLibrary: library)
    }
    func updateManual(_ text: String, offered: InputTicket?) {
        guard accepts(offered) else { return }; manualText = text
    }
    func prepareManual(_ text: String, offered: InputTicket?) {
        prepare(scan: text.trimmingCharacters(in: .whitespacesAndNewlines), outputID: nil, offered: offered)
    }
    func prepareCapturedScan(outputID: UUID?, offered: InputTicket?) {
        guard let device, device.canReviewOutput, let outputID, outputID == device.outputID,
              case .scan(let code) = device.output else { return }
        prepare(scan: code.trimmingCharacters(in: .whitespacesAndNewlines), outputID: outputID, offered: offered)
    }
    private func prepare(scan: String, outputID: UUID?, offered: InputTicket?) {
        guard accepts(offered), let offered else { return }
        do {
            let prepared = try player.prepareEvidenceReview(offered.context, scan: scan)
            review = .init(visit: visit, context: offered.context, action: .submit(prepared), scan: scan, photo: nil, outputID: outputID); issue = nil
        } catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
    func prepareUpload(outputID: UUID?, offered: InputTicket?) {
        guard accepts(offered), let offered, let device, device.canUpload,
              let outputID, outputID == device.outputID, case .photo(let bytes, _) = device.output else { return }
        review = .init(visit: visit, context: offered.context, action: .upload, scan: nil, photo: bytes, outputID: outputID); issue = nil
    }
    func prepareUploadedPhoto(outputID: UUID?, offered: InputTicket?) {
        guard accepts(offered), let offered, let device, let outputID, outputID == device.outputID,
              let evidence = device.reviewedPhoto(expectedOutputID: outputID), case .photo(let bytes, _) = device.output else { return }
        do {
            let prepared = try player.prepareEvidenceReview(offered.context, photo: evidence)
            review = .init(visit: visit, context: offered.context, action: .submit(prepared), scan: nil, photo: bytes, outputID: outputID); issue = nil
        } catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
    private func current(_ offered: Review) -> Bool {
        visible && active && root?.isActuallyLeaving == false && visit == offered.visit &&
            player.acceptsEvidenceReview(offered.context) &&
            (offered.outputID == nil || (device?.outputID == offered.outputID && device?.canReviewOutput == true))
    }
    func canConfirm(_ offered: Review) -> Bool { !working && review?.id == offered.id && current(offered) }
    func cancel(_ offered: Review) { guard review?.id == offered.id else { return }; review = nil }
    func claim(_ offered: Review) -> Claim? {
        guard canConfirm(offered) else { return nil }
        claimed = offered.id; working = true; review = nil
        return .init(review: offered)
    }
    /// Returns true only for the existing command attempt; its receipt/fresh read still
    /// owns the outcome. Unknown results retain the coordinator's original lock.
    func execute(_ claim: Claim) async -> Bool {
        let offered = claim.review
        guard claimed == offered.id, working, !Task.isCancelled, current(offered) else {
            if claimed == offered.id { claimed = nil; working = false; issue = .staleSession }
            return false
        }
        claimed = nil
        defer { if visit == offered.visit { working = false } }
        switch offered.action {
        case .upload:
            guard let outputID = offered.outputID else { return false }
            await device?.uploadPhoto(expectedOutputID: outputID)
            return false
        case .submit(let prepared):
            await player.submitEvidenceReview(prepared)
            return visible && active && visit == offered.visit && player.ownsEvidenceReview(offered.context)
        }
    }
}

@MainActor struct PlayerTaskEvidenceReviewCard: View {
    @ObservedObject var owner: PlayerTaskEvidenceReviewController
    let offered: PlayerTaskEvidenceReviewController.Review
    let submitted: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        Section {
            if owner.canConfirm(offered) {
                if let scan = offered.scan { Text(verbatim: scan).textSelection(.enabled).accessibilityIdentifier("playerEvidence.review.scan") }
                if let bytes = offered.photo, let image = UIImage(data: bytes) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).accessibilityLabel(Text(verbatim: localized("photo")))
                }
                Text(verbatim: localized(isUpload ? "uploadDetail" : "submitDetail"))
                Button {
                    guard let claim = owner.claim(offered) else { return }
                    Task { if await owner.execute(claim) { submitted() } }
                } label: { Text(verbatim: localized(isUpload ? "upload" : "submit")) }
                    .accessibilityIdentifier("playerEvidence.review.confirm")
            } else { Text(verbatim: localized("expired")) }
            Button { owner.cancel(offered) } label: { Text(verbatim: localized("cancel")) }
                .accessibilityIdentifier("playerEvidence.review.cancel")
        } header: { Text(verbatim: localized("title")) }
    }
    private var isUpload: Bool { if case .upload = offered.action { return true }; return false }
    private func localized(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(key), table: "PlayerTaskEvidenceReview", locale: locale))
    }
}

@MainActor struct PlayerTaskEvidenceRoot: UIViewControllerRepresentable {
    let owner: PlayerTaskEvidenceReviewController
    func makeUIViewController(context: Context) -> PlayerTaskEvidenceRootController { let root = PlayerTaskEvidenceRootController(owner: owner); owner.attach(root); return root }
    func updateUIViewController(_ root: PlayerTaskEvidenceRootController, context: Context) {}
    static func dismantleUIViewController(_ root: PlayerTaskEvidenceRootController, coordinator: ()) { root.owner?.detached(root) }
}
@MainActor final class PlayerTaskEvidenceRootController: UIViewController {
    weak var owner: PlayerTaskEvidenceReviewController?
    init(owner: PlayerTaskEvidenceReviewController) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
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
        super.viewDidDisappear(animated)
        owner?.departed(self)
        Task { @MainActor [weak self] in guard let self else { return }; self.owner?.departed(self) }
    }
}
