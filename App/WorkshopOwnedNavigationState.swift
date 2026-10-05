import Foundation
import Observation

/// One navigation stack's visible-screen permits. Only appearance callbacks issue permits;
/// row/package actions revoke the departing screen synchronously, before pushing navigation.
@MainActor @Observable final class WorkshopOwnedNavigationState {
    struct Selection: Hashable, Identifiable { let id: String }
    var selection: Selection?
    var showsPackage = false
    private(set) var listPermit: WorkshopOwnedPresentationPermit?
    private(set) var detailPermit: WorkshopOwnedPresentationPermit?
    private(set) var packagePermit: WorkshopOwnedPresentationPermit?
    private var listTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var packageTask: Task<Void, Never>?
    private let browser: WorkshopOwnedBrowser
    init(browser: WorkshopOwnedBrowser) { self.browser = browser }
    func listAppeared() -> WorkshopOwnedPresentationPermit? {
        let permit = browser.presentList(); listPermit = permit; return permit
    }
    func listDisappeared() {
        listTask?.cancel(); listTask = nil
        if let permit = listPermit { browser.leaveList(permit, closing: selection == nil) }; listPermit = nil
    }
    func select(claimId: String, presentation: WorkshopOwnedPresentationPermit?) {
        guard let presentation, listPermit === presentation, presentation.isLive, browser.rows.contains(where: { $0.claimId == claimId }) else { return }
        if let permit = listPermit { browser.leaveList(permit, closing: false) }; listPermit = nil
        listTask?.cancel(); listTask = nil
        selection = .init(id: claimId)
    }
    func detailAppeared(claimId: String) -> WorkshopOwnedPresentationPermit? {
        let permit = browser.presentDetail(claimId: claimId); detailPermit = permit; return permit
    }
    func detailDisappeared() {
        detailTask?.cancel(); detailTask = nil
        if let permit = detailPermit { browser.leaveDetail(permit, closing: !showsPackage) }; detailPermit = nil
    }
    func openPackage(presentation: WorkshopOwnedPresentationPermit?) {
        guard let presentation, detailPermit === presentation, presentation.isLive, let selected = selection?.id,
              browser.packageBrowser != nil, browser.detail?.item?.claimId == selected else { return }
        if let permit = detailPermit { browser.leaveDetail(permit, closing: false) }; detailPermit = nil
        detailTask?.cancel(); detailTask = nil
        showsPackage = true
    }
    func packageAppeared(claimId: String) -> WorkshopOwnedPresentationPermit? {
        let permit = browser.packageBrowser?.present(claimId: claimId); packagePermit = permit; return permit
    }
    func packageDisappeared() {
        packageTask?.cancel(); packageTask = nil
        if let permit = packagePermit { browser.packageBrowser?.leave(permit) }; packagePermit = nil
    }
    typealias ReadAction = @MainActor () async -> Void
    func offerList(_ permit: WorkshopOwnedPresentationPermit?) -> ReadAction? {
        guard let permit, listPermit === permit, let action = permit.offer() else { return nil }
        return { [browser] in await browser.load(action: action) }
    }
    func offerDetail(_ permit: WorkshopOwnedPresentationPermit?, claimId: String) -> ReadAction? {
        guard let permit, detailPermit === permit, permit.claimID == claimId, let action = permit.offer() else { return nil }
        return { [browser] in await browser.open(claimId: claimId, action: action) }
    }
    func offerPackage(_ permit: WorkshopOwnedPresentationPermit?, claimId: String) -> ReadAction? {
        guard let permit, packagePermit === permit, permit.claimID == claimId, let browser = browser.packageBrowser, let action = permit.offer() else { return nil }
        return { await browser.load(claimId: claimId, action: action) }
    }
    func scheduleList(_ permit: WorkshopOwnedPresentationPermit?) {
        guard let action = offerList(permit) else { return }; listTask?.cancel(); listTask = Task { await action() }
    }
    func scheduleDetail(_ permit: WorkshopOwnedPresentationPermit?, claimId: String) {
        guard let action = offerDetail(permit, claimId: claimId) else { return }; detailTask?.cancel(); detailTask = Task { await action() }
    }
    func schedulePackage(_ permit: WorkshopOwnedPresentationPermit?, claimId: String) {
        guard let action = offerPackage(permit, claimId: claimId) else { return }; packageTask?.cancel(); packageTask = Task { await action() }
    }
}
