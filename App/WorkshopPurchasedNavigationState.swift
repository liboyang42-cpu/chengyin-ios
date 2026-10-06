import Foundation
import Observation

/// One navigation stack's visible-screen permits. Only appearance callbacks issue permits;
/// row/package actions revoke the departing screen synchronously, before pushing navigation.
@MainActor @Observable final class WorkshopPurchasedNavigationState {
    struct Selection: Hashable, Identifiable { let id: String }
    var selection: Selection? {
        willSet {
            // SwiftUI's Back binding changes before disappearance/animation callbacks. Retire the
            // old detail immediately, including actions already offered but not yet entered.
            if selection != newValue {
                if let permit = listPermit { browser.leaveList(permit, closing: false) }
                listTask?.cancel(); listTask = nil; listPermit = nil
                listAppearance = WorkshopPurchasedViewAppearance()
                detailAppearance = WorkshopPurchasedViewAppearance()
                detailTask?.cancel(); detailTask = nil; detailPermit = nil; browser.closeDetail()
            }
        }
    }
    private(set) var listAppearance = WorkshopPurchasedViewAppearance()
    private(set) var detailAppearance = WorkshopPurchasedViewAppearance()
    private(set) var listPermit: WorkshopPurchasedPresentationPermit?
    private(set) var detailPermit: WorkshopPurchasedPresentationPermit?
    private var listTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private let browser: WorkshopPurchasedBrowser
    init(browser: WorkshopPurchasedBrowser) { self.browser = browser }
    func listAppeared() -> WorkshopPurchasedPresentationPermit? {
        guard selection == nil else { return nil }
        let permit = browser.presentList(); listPermit = permit; return permit
    }
    func listDisappeared(_ presentation: WorkshopPurchasedPresentationPermit?) {
        guard let presentation, listPermit === presentation else { return }
        listTask?.cancel(); listTask = nil
        browser.leaveList(presentation, closing: selection == nil); listPermit = nil
    }
    func select(licenseId: String, presentation: WorkshopPurchasedPresentationPermit?) {
        guard let presentation, listPermit === presentation, presentation.isLive, browser.rows.contains(where: { $0.licenseId == licenseId }) else { return }
        if let permit = listPermit { browser.leaveList(permit, closing: false) }; listPermit = nil
        listTask?.cancel(); listTask = nil
        selection = .init(id: licenseId)
    }
    func detailAppeared(licenseId: String) -> WorkshopPurchasedPresentationPermit? {
        guard selection?.id == licenseId else { return nil }
        let permit = browser.presentDetail(licenseId: licenseId); detailPermit = permit; return permit
    }
    func detailDisappeared(_ presentation: WorkshopPurchasedPresentationPermit?) {
        guard let presentation, detailPermit === presentation else { return }
        detailTask?.cancel(); detailTask = nil
        browser.leaveDetail(presentation, closing: true); detailPermit = nil
    }
    // The navigation transition creates the next presentation BEFORE SwiftUI returns to it.
    // A cached View's previous box must never be reused if Back arrives before old onDisappear.
    func listViewAppeared(_ displayed: WorkshopPurchasedViewAppearance) -> WorkshopPurchasedPresentationPermit? {
        guard listAppearance === displayed, selection == nil else { return nil }
        return displayed.appear { listAppeared() }
    }
    func detailViewAppeared(_ displayed: WorkshopPurchasedViewAppearance, licenseId: String) -> WorkshopPurchasedPresentationPermit? {
        guard detailAppearance === displayed, selection?.id == licenseId else { return nil }
        return displayed.appear { detailAppeared(licenseId: licenseId) }
    }
    func listViewDisappeared(_ displayed: WorkshopPurchasedViewAppearance) {
        displayed.disappear { listDisappeared($0) }
        if listAppearance === displayed { listAppearance = WorkshopPurchasedViewAppearance() }
    }
    func detailViewDisappeared(_ displayed: WorkshopPurchasedViewAppearance) {
        displayed.disappear { detailDisappeared($0) }
        if detailAppearance === displayed { detailAppearance = WorkshopPurchasedViewAppearance() }
    }
    typealias ReadAction = @MainActor () async -> Void
    func offerList(_ permit: WorkshopPurchasedPresentationPermit?, before: Int64? = nil) -> ReadAction? {
        guard before == nil || before == browser.nextCursor, let permit, listPermit === permit, let action = permit.offer() else { return nil }
        return { [browser] in await browser.load(before: before, action: action) }
    }
    func offerDetail(_ permit: WorkshopPurchasedPresentationPermit?, licenseId: String) -> ReadAction? {
        guard let permit, detailPermit === permit, permit.licenseID == licenseId, let action = permit.offer() else { return nil }
        return { [browser] in await browser.open(licenseId: licenseId, action: action) }
    }
    func scheduleList(_ permit: WorkshopPurchasedPresentationPermit?, before: Int64? = nil) {
        guard let action = offerList(permit, before: before) else { return }; listTask?.cancel(); listTask = Task { await action() }
    }
    func scheduleDetail(_ permit: WorkshopPurchasedPresentationPermit?, licenseId: String) {
        guard let action = offerDetail(permit, licenseId: licenseId) else { return }; detailTask?.cancel(); detailTask = Task { await action() }
    }
}

/// A visible View owns this prebuilt box. onAppear installs the permit synchronously,
/// so even a disappearance before SwiftUI redraw retires the correct presentation.
@MainActor @Observable final class WorkshopPurchasedViewAppearance {
    private(set) var permit: WorkshopPurchasedPresentationPermit?
    private var appeared = false
    private var closed = false
    func appear(_ issue: () -> WorkshopPurchasedPresentationPermit?) -> WorkshopPurchasedPresentationPermit? {
        guard !closed else { return nil }
        if !appeared { appeared = true; permit = issue() }
        return permit
    }
    func disappear(_ retire: (WorkshopPurchasedPresentationPermit?) -> Void) {
        guard !closed else { return }
        closed = true; retire(permit)
    }
}
