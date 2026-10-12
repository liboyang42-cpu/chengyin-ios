import Foundation
import Observation

/// One navigation stack's visible-screen permits. Only appearance callbacks issue permits;
/// row/package actions revoke the departing screen synchronously, before pushing navigation.
@MainActor @Observable final class WorkshopPurchasedNavigationState {
    struct Selection: Hashable, Identifiable { let id: String }
#if DEBUG
    enum SyntheticEvent: String { case listAppear, listAppearReturned, listDisappear, listDisappearReturned, detailAppear, detailAppearReturned, detailDisappear, detailDisappearReturned, selectionChanged }
    struct SyntheticSnapshot {
        let event: SyntheticEvent
        let currentAppearance: Bool
        let displayedAppeared: Bool
        let displayedClosed: Bool
        let displayedLive: Bool
        let currentAppeared: Bool
        let currentClosed: Bool
        let eligible: Bool
        let list: Bool
        let detail: Bool
        let selected: Bool
    }
    @ObservationIgnored var syntheticTrace: ((SyntheticSnapshot) -> Void)? = nil
    @ObservationIgnored private var syntheticTraceCount = 0
    private func traceSynthetic(_ event: SyntheticEvent, displayed: WorkshopPurchasedViewAppearance) {
        guard let syntheticTrace, syntheticTraceCount < 24 else { return }
        syntheticTraceCount += 1
        let current: WorkshopPurchasedViewAppearance
        let eligible: Bool
        switch event {
        case .detailAppear, .detailAppearReturned, .detailDisappear, .detailDisappearReturned:
            current = detailAppearance; eligible = selection != nil
        default:
            current = listAppearance; eligible = selection == nil
        }
        syntheticTrace(.init(event: event, currentAppearance: current === displayed,
            displayedAppeared: displayed.syntheticAppeared, displayedClosed: displayed.syntheticClosed,
            displayedLive: displayed.permit?.isLive == true,
            currentAppeared: current.syntheticAppeared, currentClosed: current.syntheticClosed,
            eligible: eligible, list: listPermit != nil, detail: detailPermit != nil, selected: selection != nil))
    }
#endif
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
        didSet {
#if DEBUG
            if oldValue != selection { traceSynthetic(.selectionChanged, displayed: listAppearance) }
#endif
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
#if DEBUG
        traceSynthetic(.listAppear, displayed: displayed)
        defer { traceSynthetic(.listAppearReturned, displayed: displayed) }
#endif
        guard listAppearance === displayed, selection == nil else { return nil }
        return displayed.appear { listAppeared() }
    }
    func detailViewAppeared(_ displayed: WorkshopPurchasedViewAppearance, licenseId: String) -> WorkshopPurchasedPresentationPermit? {
#if DEBUG
        traceSynthetic(.detailAppear, displayed: displayed)
        defer { traceSynthetic(.detailAppearReturned, displayed: displayed) }
#endif
        guard detailAppearance === displayed, selection?.id == licenseId else { return nil }
        return displayed.appear { detailAppeared(licenseId: licenseId) }
    }
    func listViewDisappeared(_ displayed: WorkshopPurchasedViewAppearance) {
#if DEBUG
        traceSynthetic(.listDisappear, displayed: displayed)
        defer { traceSynthetic(.listDisappearReturned, displayed: displayed) }
#endif
        displayed.disappear { listDisappeared($0) }
        if listAppearance === displayed { listAppearance = WorkshopPurchasedViewAppearance() }
    }
    func detailViewDisappeared(_ displayed: WorkshopPurchasedViewAppearance) {
#if DEBUG
        traceSynthetic(.detailDisappear, displayed: displayed)
        defer { traceSynthetic(.detailDisappearReturned, displayed: displayed) }
#endif
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
#if DEBUG
    var syntheticAppeared: Bool { appeared }
    var syntheticClosed: Bool { closed }
#endif
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
